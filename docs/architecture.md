# Architecture

Reverse-engineered from the RTL and cross-checked against `sw/ising.py`. Line
references are to files in `rtl/`.

Reference: D. Jiang, X. Wang, Z. Huang, L. Kang, S. Yang and E. Yao,
"A Spin Scale-Aware Self-Adaptive Ising Annealing Processing Architecture for
Combinatorial Optimization Problems", *IEEE Trans. Circuits Syst. I*, vol. 72,
no. 10, pp. 5811–5824, Oct. 2025, doi: 10.1109/TCSI.2025.3541888.

---

## 1. Module hierarchy

```
aiapa_top                                   aiapa_top.v
├── mem_j [0:1023] × 4096b                  off-chip coupling matrix (adj_matrix.txt)
├── spu #(ROW=5, COL=0)            spu1      spu.v
│   ├── ila_0 ila                           debug probe (sim stub in sim/stubs/)
│   ├── MuxKeyWithDefault #(5,3,16) mux1    operand A select
│   ├── MuxKeyWithDefault #(4,3,16) mux2    operand B select
│   ├── fifo #(17,256)             fifo2     flip-event queue
│   ├── fp16_lfsr                  lfsr_rng  fp16 random values in [0,1)
│   ├── float_mul                  mul       fp16 multiply
│   └── float_adder                adder, adder2
├── fifo #(4,16)                   fifo3     decouples the J fetch from the SPU
├── readout_router #(ROW=5, COL=0) rdout1    readout_router.v
├── top_control #(E=1, L=1, P=2)   top_controller   top_control.v
│   ├── fifo #(18,2048)            dataflow  flip stream
│   ├── float_mul i0, float_adder i1        parameter update
│   ├── uart uart0 → uart_transmitter       uart.v / uart_transmitter.v
│   └── fifo #(8,128)              tx_fifo   UART TX buffer
└── writeback_router #(ROW=5, COL=0) wb1    writeback_router.v
    └── ri_coord_rom_case #(64,3,5)         routing table
```

`MuxKey` / `MuxKeyWithDefault` come from `rtl/muxkey.v`; `fp16_lfsr` lives at the
bottom of `rtl/spu.v`. Only one SPU is instantiated, so the routers degenerate
into pass-throughs; the tree routing only becomes active in the multi-SPU
configuration the router parameters (`ROW`, `COL`) are written for.

Vendor primitives not in this repository: `ila_0`, `REGISTER_CE`,
`REGISTER_R_CE`. Behavioural stubs live in `sim/stubs/xilinx_prims.v` for
simulation; regenerate the real ILA IP and use the vendor primitive library for
hardware.

---

## 2. `top_control` — annealing control FSM

`aiapa_top`'s `rst_n` and `ap_start_n` are **active low** — they were inverted
from the original active-high `rst`/`ap_start` when the design was put on the
board. The internal `top_control` still uses the active-high `rst`/`ap_start`
(`aiapa_top.v` inverts them at the top), so testbenches must drive the top-level
ports active low.

Parameters `E`, `L`, `P` are overridden to `(1, 1, 2)` by `aiapa_top.v`.

| parameter | meaning |
|---|---|
| `E` | spin-block divisor: one pass covers `N/E` spins, so `E+1` ≈ the number of parallel tiles |
| `L` | sparsity threshold for the parallel-mode switch (`F > L`) — the "spin scale-aware" test |
| `P` | readout group width: chunks the `F` flips per sweep into groups of ≤ `P` |

> Note: module parameter `P` (readout group width) is unrelated to the input port
> `in_p`, which carries `pk_start`.

### Run configuration inputs

| port | meaning | default (`aiapa_top.v`) |
|---|---|---|
| `in_n` | `N`, number of spins | 800 |
| `in_k` | `K`, number of annealing sweeps | 800 |
| `in_p` | `pk_start`, fp16 | `0x3800` = 0.5 |
| `in_c` | `ck` at t=0, fp16 | `0x0000` = 0.0 |
| `in_temp` | `T_start`, fp16 | `0x4A80` = 13.0 |
| `in_alpha` | cooling rate, fp16 | `0x3BFA` = 0.99707 (nearest fp16 to 0.9969) |

These are now module parameters of `aiapa_top` — change them there.

### States

| state | role |
|---|---|
| `3'd1` | IDLE / config latch. Also drains the UART result stream. |
| `3'd2` | Parameter broadcast: a 4-deep micro-sequence `m = 0..3` that updates and re-sends `T`, `pk`, `ck` to the SPU. |
| `3'd3` | Momentum pass: issues `N/E` "f + M·σ" instructions (opcode `000001`). |
| `3'd4` | Field pass: issues `C` "f + J·σ" instructions (opcode `000010`), asserting `mem_r` to fetch couplings. |
| `3'd5`, `3'd6` | Parallel mode — **entirely commented out**, dead. |

### Per-sweep parameter micro-sequence

Because `para`/`coeff` are registered and `result` is selected combinationally
(`m == 1` → `float_mul`, else `float_adder`), state `3'd2` implements:

| `m` | action |
|---|---|
| 0 | `para <= t; coeff <= alpha` → send `SET_T` |
| 1 | `t <= t * alpha` (fp16 multiply); `para <= pk; coeff <= 0x9019` → `SET_PK` |
| 2 | `pk <= pk + 0x9019` (fp16 add); `para <= ck; coeff <= 0x1419` → `SET_CK` |
| 3 | `ck <= ck + 0x1419`; → state `3'd3` |

`0x9019` = fp16 **−1/2000** and `0x1419` = fp16 **+1/1000**, so per sweep

```
T  *= alpha          pk -= 1/2000          ck += 1/1000
```

> `sw/ising.py` uses `T = T_start · alpha^t` and `pk = pk_start − t/2000`, which
> match. It uses `ck = sqrt(t/1000)`, a **square root** ramp — the hardware has
> no sqrt unit and uses a linear ramp. This is a genuine numerical divergence
> between the reference model and the RTL.

---

## 3. 32-bit packet formats

All packets are selected by `data_type = pkt[31:29]`, built in `MuxKeyWithDefault
mux0` (`top_control.v`).

| type | direction | layout | meaning |
|---|---|---|---|
| `3'd1` | control → wb → spu | `[31:29]=1, [28:23]=opcode(6), [22]=flipspin, [21]=firststep, [20]=up, [19]=lr, [18:16]=0, [15:0]=addr` | instruction |
| `3'd2` | control → wb → spu | `[31:29]=2, [28:23]=opcode, [22:16]=0, [15:0]=fp16 param` | parameter load |
| `3'd3` | spu → wb | `[31:29]=3, [28:23]=0, [21:16]=addr(6), [15:0]=psum(fp16)` | partial sum / local field |
| `3'd4` | parallel frame | `[31:29]=4, [28:24]=0, [23:17]=num(7), [16:1]=index, [0]=spin` | spin stream — **no live producer**, see §7 |
| `3'd5` | — | — | null / idle sentinel |
| `3'd6` | spu → readout → control | `[31:29]=6, [28:18]=0, [17:2]=addr, [1]=other-copy spin, [0]=new spin` | flip event |
| `3'd7` | spu → control | `[31:29]=7, [2:0]=spin bit` (only `[0]` used) | finish / result bit stream |

Opcodes (`pkt[28:23]`): `000001` = "f + M·σ" (momentum), `000010` = "f + J·σ"
(interaction), `000011` = "f + psum" (parallel, unused), plus `SET_T = 000100`,
`SET_CK = 000101`, `SET_PK = 000110` (declared in both `top_control.v` and
`spu.v`).

### Handshake

* forward: `top_control.data_pkt` → `wb1.neighbor` → `spu1.datain_pkt`
* return: `spu1.local_res` → `wb1.local` → `wb1.local_out` → `spu1.datain_pkt`
* readout: `spu1.next_rdout` → `rdout1.local` → `rdout1.dout` → `top_control.datain_pkt`
* back-pressure: `readout_router.response[2]` → `spu1.response`;
  `top_control.rd_en_out = !fifo_full || finish_send`
* `spu1.fsn` = number of accepted flips in the sweep just completed, fed back as
  the next sweep's `Fl`/`Fr`
* `spu1.valid` = batch-complete pulse, used by state `3'd4`

---

## 4. SPU datapath

Memories and registers are all `[0:1024]`, i.e. sized for `N ≤ 1024`:

| array | width | contents |
|---|---|---|
| `w_mem` | 16 | fp16 momentum weight (`Wi.txt`) |
| `lf_mem_l`, `lf_mem_r` | 16 | local fields of the two replicas |
| `lf_temp_l`, `lf_temp_r` | 16 | accumulator for the momentum opcode |
| `spin_l`, `spin_r` | 1 | the two spin copies |

`pk`, `ck`, `t`, `psum` are fp16 registers; `fsn` is a 32-bit flip counter.

The datapath is a 3-stage pipeline (`_src` → `_lf` → `_sp`):

1. **Decode.** `data_type`, `opcode`, `addr`, plus `sigmaf <= pkt[22]`,
   `ctrl_firststep <= [21]`, `ctrl_up <= [20]`, `ctrl_lr <= [19]`,
   `num <= pkt[23:17]`, `spinindex <= pkt[16:1]`.
2. **Compute.** The 4-bit coupling `j_left = {sign, |J|:2:0}` is expanded to
   fp16 as `{sign, firststep ? 15 : 16, |J| << 7}` — so `|J|` is scaled ×1 or ×2
   depending on `ctrl_firststep`, matching `2*J if t > 1 else J` in
   `sw/ising.py`. `mux1`/`mux2` select operands; the sign of the `J` term comes
   from the flip bit carried in the instruction, the momentum term from the
   opposite spin copy. The result is `float_mul(ina, inb)` with
   `w = (pk < rand && opcode == 000001) ? w_mem[addr] : 0`, giving the gated
   momentum term `(pk < rand)·ck·w`; on the last "f + J·σ" instruction it becomes
   `rand·T`, the Metropolis threshold numerator.
3. **Writeback.** opcode `000010` writes `lf_mem_l/r[addr]`, opcode `000001`
   writes `lf_temp_l/r[addr]`.
4. **State update.** `delta_hi = 2·(sigmai_sp ? −fi : +fi)` — that is,
   `ΔH = 2·σ_i·F_i`. A flip is accepted when

   ```
   flip = (delta_hi < 0) | (delta_hi == 0) | (threshold >= 0 && delta_hi <= threshold)
   ```

   i.e. Metropolis: accept if `ΔH < 0`, else accept with probability `T·rand`,
   matching `deltaH <= 0 or deltaH <= T*rand` in `sw/ising.py`. Spins are
   written only when they actually flip, and only on the last instruction of a
   batch (`ctrl_up`). Flips are queued in `fifo2` as `{addr, new spin}`.

### `fp16_lfsr`

A 16-bit LFSR, feedback `lfsr_reg[15]^[13]^[12]^[10]`, seed `0xACE1`, enabled by
`opcode == 000001 | ctrl_up`. Its output is an fp16 value in `[0,1)`: sign
forced to 0, mantissa from `lfsr_reg[9:0]`, exponent clamped to `1..14` to avoid
subnormals and values ≥ 1. It is a **deterministic PRNG**, not an entropy
source — two runs of the same configuration produce identical results. It feeds
both the momentum Bernoulli gate `pk < rand` and the Metropolis threshold.

### Numerical formats

* **Arithmetic: IEEE-754 binary16 (fp16)**, hand-written combinational
  `float_adder` / `float_mul`. Both always assume the implicit leading 1, so
  **subnormals are not handled**, and underflowing exponents flush to
  `16'h0000`. No NaN/Inf handling.
* **Spins: 1 bit**, `0 ≡ +1`, `1 ≡ −1`; negation toggles the bit.
* **Couplings: 4-bit sign–magnitude**, `|J| ≤ 7`.
* Acceptance arithmetic mixes fp16 fields with integer comparisons.

---

## 5. UART readout

`uart.v` wraps `uart_transmitter` with `CLOCK_FREQ = 100 MHz`,
`BAUD_RATE = 115200`, matching the testbench clock. (`uart_transmitter`'s own
default is 125 MHz; the parameters passed by `uart.v` are what take effect.)

When annealing finishes, `finish_send` goes high and the SPU emits 800 type-7
packets, one result bit each. `top_control` packs them LSB-first into bytes and
pushes each to a 128×8 TX FIFO, which streams them out at 115200 baud. The UART
is therefore the **sole readout channel** for the final spin configuration:
800 bits ≈ 100 bytes ≈ 8.7 ms.

---

## 6. Data files

See [`data/README.md`](../data/README.md) for the verified layouts of
`graph.txt`, `adj_matrix.txt`, `spinsl.txt`, `spinsr.txt` and `Wi.txt`.

---

## 7. Known issues and dead code

Documented rather than silently changed, because fixing them would alter
behaviour that was validated on hardware.

* **Cycle cost of a sweep is `O(N·F)`.** In state `3'd4` the field pass streams
  all `N` columns (`C = N/E = 800`) for each of the `F` spins that flipped, so a
  sweep costs about `2·N·F` cycles — roughly 1.25M cycles at `T_start = 13`,
  where nearly every spin flips. A full 800-sweep run is therefore ~`10^9`
  cycles, which is why XSim runs are slow. `N_STEPS` on `aiapa_top` is the knob.
* **Sign convention — unresolved reading.** `sw/ising.py` uses `J_ij = −w_ij`
  (MaxCut: minimising `H = −½ s'Js` maximises the cut), while `adj_matrix.txt`
  stores `w_ij` sign-magnitude (`sign = 1` when `w < 0`). Tracing the SPU
  (`delta_hi = 2·(sigmai_sp ? −fi : +fi)`, accept when `delta_hi < 0`) suggests
  the hardware minimises `−Σ w σσ`, i.e. the *minimum* cut. Since the design is
  board-validated and presumably solves MaxCut, that trace is incomplete
  somewhere — most likely in the incremental local-field update, which flips
  which spin index the accumulated field belongs to. Left flagged rather than
  "fixed": the hardware path is unchanged, and `ising.py` now matches the
  reference formulation.
* **Parallel mode is dead.** States `3'd5`/`3'd6` are fully commented out, so
  the type-4 packet and opcode `000011` have no live producer and the writeback
  router's tree routing is inert in the single-SPU configuration.
* **`top_control.v` `flag` logic.** `flag <= 1; if (flag == 0) Fr <= fsn;` is a
  self-defeating nonblocking check — it reads the stale value, so it fires only
  once (or never) rather than on every sweep.
* **`ck` schedule mismatch.** The RTL ramps `ck` linearly (`+1/1000` per sweep)
  while `sw/ising.py` uses `sqrt(t/1000)`.
* **Address bit-order.** In `aiapa_top.v` the row is `mem_addr[15:0]-1` and the
  column is `mem_addr[31:16]`, which is the opposite order from the
  `{spinindex, addr}` naming used at the packet level in `top_control.v`.
* **`ri_coord_rom_case`** has no case for `r_idx == 63`.
* **fp16 units** do not handle subnormals and flush underflow to zero.
* **Line ends.** The RTL is Verilog-2001, **not** SystemVerilog: it will not
  compile with `xvlog -sv`, because `writeback_router` has a port named `local`,
  which `-sv` reserves. Compile in the default mode.
* **`uart_transmitter.v`** used an implicit 1-bit net for `symbol_edge`; an
  explicit forward declaration was added so it compiles in strict modes.
* **`spu.v`** used `rand` as an instance name (a SystemVerilog keyword); renamed
  to `lfsr_rng`.

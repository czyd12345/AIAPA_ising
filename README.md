# AIAPA_ising

RTL and an algorithm-level reference model for a **spin scale-aware self-adaptive
Ising annealing processing architecture** for combinatorial optimization,
evaluated on the MaxCut benchmark instance **G20**.

This repository accompanies:

> D. Jiang, X. Wang, Z. Huang, L. Kang, S. Yang and E. Yao,
> "A Spin Scale-Aware Self-Adaptive Ising Annealing Processing Architecture for
> Combinatorial Optimization Problems",
> *IEEE Transactions on Circuits and Systems I: Regular Papers*,
> vol. 72, no. 10, pp. 5811–5824, Oct. 2025.
> DOI: [10.1109/TCSI.2025.3541888](https://doi.org/10.1109/TCSI.2025.3541888)

It contains the Verilog RTL of the processor, a Python reference implementation
of the same annealing schedule, and the scripts that turn a benchmark graph into
the configuration data the RTL loads at time zero.

---

## Results

MaxCut on **G20** (800 spins, 4672 edges, `Σw = −46`):

| | MaxCut value `C` | Ising energy `H` |
|---|---|---|
| Python reference, 800 sweeps (`--seed 1`) | **892** | −1830 |
| Steepest-descent local search, 60 restarts | 554 | −1154 |

Both satisfy `H + 2C = Σw = −46`. The reference annealer is the stronger of the
two; the local-search column is included only to show the gap that the annealing
schedule closes.

### RTL simulation: correct, but very slow

The RTL compiles, elaborates and anneals correctly. The testbench computes
`W = Σw = −46` straight from the loaded coupling matrix — matching the Python
reference — and the identity `H + 2C = W` holds at every check, so the coupling
matrix, the spin files and the weight file are all read and interpreted as
intended. A per-cycle monitor confirms the FSM stepping through the field pass
normally (`state = 4, f = 249/800, c = 788/800` at cycle 200k of the first
sweep).

What makes a full run impractical is pure wall-clock cost, not correctness. The
field pass streams all `N` columns for each of the `F` spins that flipped in that
sweep, so an early sweep costs about `2·N·F` cycles. Measured:

| | |
|---|---|
| first two sweeps | 95 ns, then 12.54 ms — ~1.25M cycles for a full sweep |
| XSim throughput on this design | **~14 600 cycles/s** (2M cycles in 137 s) |
| one early sweep | ~1.4 min |
| 40 sweeps | ~1 hour |
| 800 sweeps (`N_STEPS = 800`) | **~19 hours** |

Sweeps get cheaper as the temperature falls and `F` drops, so those figures are
upper bounds, but the order of magnitude stands. **I verified the start of the
anneal, not a complete run** — the numbers in the table at the top of this
section are CPU results only.

For a complete anneal that finishes in reasonable time, shorten the run — both
the DUT's annealing length and the observation window:

```bash
echo "-d N_STEPS=40"  > .opts.f
echo "-d SWEEPS=40"  >> .opts.f
xvlog -f .opts.f -f rtl/filelist.f sim/tb_top_control.v
xelab -debug typical -s tb tb_top_control && xsim tb --runall
```

`scripts/run_sim.sh --fast` does a 20-sweep smoke run. Note that XSim buffers its
console output until the run ends, so a long run looks idle while it works.

---

## Layout

```
rtl/          Verilog-2001 RTL of the processor
  aiapa_top.v       top level: SPU + routers + coupling matrix + control
  top_control.v     annealing control FSM
  spu.v             spin processing unit + fp16 LFSR
  writeback_router.v, readout_router.v, muxkey.v, fifo.v
  float_op.v        fp16 adder
  float_mul.v       fp16 multiplier
  uart.v, uart_transmitter.v
  filelist.f        compile order
sim/
  tb_top_control.v  self-checking testbench (reports H and C per CHECK_EVERY sweeps)
  stubs/            behavioural stubs for the vendor primitives (ila_0, REGISTER_*)
sw/
  ising.py          reference momentum annealer (the algorithm the RTL implements)
  gen_config.py     benchmark graph -> RTL configuration files
data/               benchmark instance and generated configuration  (see data/README.md)
docs/architecture.md  module hierarchy, FSM, packet formats, numerics
scripts/run_sim.sh    compile + elaborate + run under Vivado XSim
```

---

## Quick start

### 1. Algorithm reference

```bash
pip install -r sw/requirements.txt
python sw/ising.py --steps 800 --seed 1 --save-plot energy.png
```

Prints the final Ising energy and MaxCut value and the final spin vector, and
optionally writes the energy-versus-sweep curve. `--steps 800` takes a couple of
minutes: the reference model is deliberately a direct transcription of the RTL
(including its `O(N²)` field-propagation loops) rather than a vectorised
reimplementation, so it stays comparable line by line.

### 2. Regenerate the RTL configuration

```bash
python sw/gen_config.py --keep-spins   # keep the bundled initial spins
python sw/gen_config.py                # or redraw them from --seed
python sw/gen_config.py --check        # verify adj_matrix.txt reproduces byte-for-byte
```

### 3. RTL simulation

Requires Vivado (the script finds `xvlog`/`xelab`/`xsim` automatically, or set
`VIVADO_BIN`):

```bash
scripts/run_sim.sh          # compile, elaborate, run
scripts/run_sim.sh --gui    # same, then open the waveform database
```

**Run it from the repository root** — the RTL loads `data/*.txt` with relative
paths.

With any other simulator, the equivalent is:

```bash
iverilog -o sim.out -f rtl/filelist.f sim/tb_top_control.v && vvp sim.out
```

The testbench prints, every `CHECK_EVERY` sweeps:

```
Instance: N=800  W = sum(w_ij) = -46
  k        H(ising)      C(maxcut)
   1            94           -70
```

(that first line is an actual run) and asserts `H + 2C = Σw` on every check,
warning on any violation. See the status note above before expecting a full run.

Runtime knobs are compile-time defines at the top of `sim/tb_top_control.v`
(`SWEEPS`, `CHECK_EVERY`, `TIMEOUT`) or on the command line with
`xvlog -d SWEEPS=50 -f rtl/filelist.f sim/tb_top_control.v`. Under Git Bash/MSYS
the `=` in `-d NAME=value` gets mangled, so use Vivado's own shell or edit the
defaults directly. `scripts/run_sim.sh --fast` does a 20-sweep smoke run.

> **Runtime.** XSim is slow on this design: one full 800-sweep anneal is a few
> million clock cycles through 800-bit spin memories and combinational fp16
> units, and XSim buffers its console output until the run ends, so a long run
> looks idle. Use `--fast` to check that everything builds and starts, and reduce
> `N_STEPS` on `aiapa_top` for shorter full anneals.

---

## Problem formulation

MaxCut: maximise

```
C(s) = Σ_{i<j} w_ij · [s_i ≠ s_j]        s_i ∈ {−1, +1}
```

With `s_i ∈ {−1,+1}`, `[s_i ≠ s_j] = (1 − s_i s_j)/2`, so

```
C = (Σw − H)/2,    H = Σ_{i<j} w_ij · s_i s_j
```

and maximising the cut is equivalent to minimising `H = −1/2 · s'Js` for the
coupling matrix **`J_ij = −w_ij`** — the *negative* of the graph edge weight.
This is the sign convention `sw/ising.py` uses.

`data/adj_matrix.txt` stores the coupling `J_ij = −w_ij`, the same convention —
the sign bit is set when the graph weight is positive. The SPU accumulates
`J_ij·σ_j` and minimises `H = −½ s'Js`, so this is what makes its ground state
the maximum cut. See `data/README.md` and `docs/architecture.md`.

---

## Annealing schedule

The schedule is momentum-assisted Metropolis annealing, run on two spin replicas
that update each other (the local fields of one replica are computed from the
other's spins).

| symbol | meaning | default |
|---|---|---|
| `N` | number of spins | 800 |
| `K` | number of sweeps | 800 |
| `T_start` | initial temperature | 13.0 |
| `alpha` | geometric cooling rate | 0.9969 |
| `pk_start` | initial momentum acceptance probability | 0.5 |
| `ck` | momentum step size | `sqrt(t/1000)` in `sw/`, linear `+1/1000` per sweep in RTL |

Per sweep the hardware updates `T *= alpha`, `pk -= 1/2000`, `ck += 1/1000`.

The "spin scale-aware" part is the momentum weight `w[i]`, computed once from the
initial spin configuration: for a spin at `+1` it is the local coupling sum, and
for a spin at `−1` it is tied to the spectral radius of the coupling matrix
instead — `0.5 · λ_max` with `λ_max = max|eigenvalue(J)|`. That scaling is what
lets the momentum term stay meaningful when the spin scale varies strongly
across the graph. Details in `data/README.md`.

The RTL run configuration is a set of `aiapa_top` module parameters
(`N_SPINS`, `N_STEPS`, `PK_INIT`, `CK_INIT`, `T_INIT`, `ALPHA`), all with the
defaults above.

---

## Data files

All four are generated by `sw/gen_config.py` from `data/graph.txt`:

| file | contents |
|---|---|
| `graph.txt` | G20, Gset format: `N M`, then `i j w` |
| `adj_matrix.txt` | 4-bit sign–magnitude couplings, 800 × 3200 chars |
| `spinsl.txt`, `spinsr.txt` | initial spins of the two replicas, 1 bit per line |
| `Wi.txt` | per-spin momentum weight, fp16 in big-endian hex |

The layouts are documented precisely, and the reverse-engineering is justified
against the committed data, in **[`data/README.md`](data/README.md)**.

---

## Architecture

**[`docs/architecture.md`](docs/architecture.md)** covers the module hierarchy,
the `top_control` FSM and its per-sweep parameter micro-sequence, all seven
32-bit packet types and the opcodes, the SPU pipeline, the fp16 LFSR, the UART
readout path, and the numerical formats.

In brief: one SPU holds two spin copies plus their local fields;
`top_control` runs a four-state FSM (idle → parameter broadcast → momentum pass
→ field pass) driven by flip counts fed back from the SPU; the writeback and
readout routers are written for a multi-SPU tree but degenerate to pass-throughs
in the single-SPU configuration built here; and the final spin configuration
leaves the chip over a 115200-baud UART.

---

## Known issues

`docs/architecture.md` documents these in full. The short version:

* **A full 800-sweep XSim run takes ~19 hours.** The field pass is `O(N·F)` per
  sweep (~1.25M cycles at high temperature) and XSim manages only ~14 600
  cycles/s here. Lower `N_STEPS` for simulation — see
  [RTL simulation](#rtl-simulation-correct-but-very-slow) above.
* **Parallel mode is dead code** — states `3'd5`/`3'd6` are commented out, so the
  type-4 packet has no live producer and the router tree is inert at one SPU.
* **`ck` schedule divergence** — the RTL ramps `ck` linearly while `sw/ising.py`
  uses `sqrt(t/1000)`; the RTL has no square-root unit.
* **`top_control` `flag` logic** is a self-defeating nonblocking check, so one of
  the `Fr` updates fires at most once.
* **fp16 units** ignore subnormals and flush underflow to zero; no NaN/Inf.
* **The RTL is Verilog-2001, not SystemVerilog** — it will not compile with
  `xvlog -sv`, because `writeback_router` has a port named `local`, which `-sv`
  reserves.

`sim/stubs/xilinx_prims.v` provides behavioural `ila_0`, `REGISTER_CE` and
`REGISTER_R_CE` so the design elaborates without the vendor IP. It is for
simulation only — regenerate the ILA IP and use the vendor library for hardware.

---

## Citing

If you use this code, please cite the paper above — see
[`CITATION.cff`](CITATION.cff). The bundled instance is **G20** from the
[Gset](https://web.stanford.edu/~yyye/yyye/Gset/) MaxCut benchmark.

## License

MIT — see [`LICENSE`](LICENSE).

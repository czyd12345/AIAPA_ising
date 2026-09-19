# Data files

All four RTL configuration files are generated from `graph.txt` by
[`sw/gen_config.py`](../sw/gen_config.py). Run it from the repository root:

```bash
python sw/gen_config.py --keep-spins   # keep the bundled initial spins
python sw/gen_config.py                # redraw them from --seed
python sw/gen_config.py --check        # verify adj_matrix.txt is reproduced byte-for-byte
```

`adj_matrix.txt` does not depend on the initial spins, so a fresh generation of
it is byte-identical to the committed file. `Wi.txt` *does* depend on
`spinsl.txt`; the committed trio was generated together and is self-consistent.

> **Note.** The `Wi.txt` originally committed to this repository was inconsistent
> with the accompanying `spinsl.txt`/`spinsr.txt`: no assignment of spin
> encodings or index shifts of those spin files reproduced it, so it had been
> generated from a different random spin draw and was stale. It has since been
> regenerated from the committed `spinsl.txt` with `--keep-spins`, so
> `Wi.txt`, `spinsl.txt` and `spinsr.txt` now agree. `adj_matrix.txt` and the
> initial spins are unchanged, so the simulated annealing run is unaffected.

---

## `graph.txt` — the benchmark instance

**G20** from the [Gset](https://web.stanford.edu/~yyye/yyye/Gset/) MaxCut
benchmark, in Gset format:

```
800 4672          <- N M
1 8 -1            <- i j w, one edge per line, sorted by i, with i < j
1 9 1
...
```

| property | value |
|---|---|
| spins `N` | 800 |
| edges `M` | 4672 (2313 at `+1`, 2359 at `-1`) |
| `W = Σ w_ij` | −46 |
| degree min / mean / max | 5 / 11.68 / 123 |
| triangles | 15957 |

G20 is not an Erdős–Rényi graph: a random graph of the same density (p = 0.0146)
has ~266 triangles and an average local clustering of 0.0146, against 15957 and
0.3475 here. That planted structure is what makes it a meaningful MaxCut
instance.

MaxCut objective: maximise

```
C(s) = Σ_{i<j} w_ij · [s_i ≠ s_j]
```

---

## `adj_matrix.txt` — 4-bit coupling matrix

800 lines × 3200 characters. **Layout verified against all 800 rows and all 9344
non-zero fields** (every edge of `graph.txt`, in both directions).

* Line `i` (1-based) holds the couplings of spin `i`.
* A row is `N` groups of 4 characters. `$readmemb` loads the 3200-character row
  **right-aligned** into the 4096-bit word `mem_j[i-1]`, so the group at
  character offset `4k` holds column `j = N - k` — i.e. **the columns appear in
  the file in reverse order**. (Natural order matches 0 of 800 rows; reversed
  matches 800 of 800.)
* The right-alignment was confirmed directly: loading a 3200-character row whose
  last four characters are `1111` places those ones in bits `3:0` of the
  register, and a CRLF copy of the same row loads bit-for-bit identically —
  `$readmemb` skips `\r` as whitespace. The files are nonetheless pinned to LF
  in `.gitattributes` so that `gen_config.py --check` stays byte-comparable
  everywhere.
* Each group is `{sign, |w|:2:0}`, with `sign = 1` when `w < 0`. The file
  therefore stores the raw graph weight `w_ij` in sign–magnitude form.

In bit terms, `rtl/aiapa_top.v` reads the coupling for column `j` from
`mem_j[i-1][(j-1)*4 +: 4]`, sign at bit `(j-1)*4+3`, and `rtl/spu.v` uses
`j_left[3]` as the sign and `j_left[2:0]` as the magnitude.

The 3-bit magnitude field caps `|w|` at 7. The bundled ±1 instance is well
inside that; `gen_config.py` raises an error for anything larger.

---

## `spinsl.txt`, `spinsr.txt` — initial spins

801 lines of one bit each. Line 0 is unused (the RTL indexes spins from 1);
line `i` is the initial spin of spin `i` for that replica.

Bit → spin mapping, from the flip logic in `rtl/spu.v` (`delta_hi` is
`2·(sigmai_sp ? −fi : +fi)`, matching `ΔH = 2·σ_i·F_i` in `sw/ising.py`):

| bit | spin |
|---|---|
| `0` | `+1` |
| `1` | `−1` |

The cut value `C` is invariant under this choice, since `[s_i ≠ s_j]` only
depends on whether the two bits differ.

---

## `Wi.txt` — spin-scale-aware momentum weight

801 lines, 4 hex digits each, read by `$readmemh`. Line 0 is unused; line `i`
holds `w[i]` as an **IEEE-754 binary16 (fp16) value in big-endian hex** — the
literal hex text is what lands in the register, with no byte swapping
(`0x4A80` = 13.0, `0x3800` = 0.5).

`w` is the "spin scale-aware" term from `sw/ising.py`, computed once from the
**initial left-replica spins** `s = spinsl`:

```
w[i] = Σ_j ( 0.5·|J_ij| if s[j] = +1 else |J_ij| )    if s[i] = +1
     = 0.5 · λ_max                                     if s[i] = −1

λ_max = max |eigenvalue(J)| = 12.7363   →   0.5·λ_max = 6.3682
```

So a spin sitting at `−1` gets a momentum scale tied to the spectral radius of
the coupling matrix rather than to its local coupling sum. In the committed
file, 398 of the 800 entries are `0x465E` ≈ 6.3672 (`0.5·λ_max` rounded to
fp16), exactly matching the 398 spins that start at `−1` — `gen_config.py`
regenerates the file to within fp16 rounding (max deviation 9.9e-4).

Using `max |eigenvalue|` rather than `max eigenvalue` keeps `λ_max` invariant
under the `J → −J` MaxCut sign convention.

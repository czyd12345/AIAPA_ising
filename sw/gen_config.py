#!/usr/bin/env python3
"""Generate the RTL configuration files for AIAPA_ising from a Gset graph.

Takes a Gset-format MaxCut instance and writes the four files that aiapa_top /
spu / top_control load with $readmem at time zero:

    data/adj_matrix.txt   4-bit sign-magnitude coupling matrix, N rows
    data/Wi.txt           per-spin momentum weight, fp16, N+1 hex lines
    data/spinsl.txt       initial spins of the left replica, N+1 bit lines
    data/spinsr.txt       initial spins of the right replica, N+1 bit lines

The exact layouts are documented in data/README.md; they were reverse-engineered
from the RTL and verified against the committed data (see --check).

The reference algorithm (sw/ising.py) solves the MaxCut problem, i.e. it uses
J_ij = -w_ij so that minimising H = -1/2 s'Js maximises the cut. The hardware
stores the raw edge weight w_ij in adj_matrix.txt; the sign convention is
applied inside the SPU datapath.

Usage
-----
    python sw/gen_config.py                       # regenerate all four files
    python sw/gen_config.py --keep-spins          # keep the existing spinsl/spinsr
    python sw/gen_config.py --check               # verify we reproduce the committed files
    python sw/gen_config.py --graph G20.txt --out-dir data --seed 7
"""

from __future__ import annotations

import argparse
import os
import struct
import sys

import numpy as np


# --------------------------------------------------------------------------- io

def read_gset(path):
    """Read a Gset-format graph: optional '#' comments, 'N M', then 'i j w'."""
    n = None
    edges = []
    with open(path, "r") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("c "):
                continue
            parts = line.split()
            if n is None and len(parts) == 2:
                n = int(parts[0])
                m = int(parts[1])
                if m != 0:
                    continue
            if len(parts) != 3:
                raise ValueError("%s:%d: expected 'i j w', got %r" % (path, lineno, line))
            i, j, w = int(parts[0]), int(parts[1]), int(parts[2])
            if i == j:
                raise ValueError("%s:%d: self-loop at %d" % (path, lineno, i))
            edges.append((min(i, j), max(i, j), w))
    if n is None:
        raise ValueError("%s: no 'N M' header found" % path)
    for u, v, _ in edges:
        if not (1 <= u <= n and 1 <= v <= n):
            raise ValueError("%s: node id out of range 1..%d" % (path, n))
    return n, edges


def build_J(n, edges):
    """Dense (n+1)x(n+1) symmetric coupling matrix, index 0 unused."""
    J = np.zeros((n + 1, n + 1), dtype=np.float64)
    for u, v, w in edges:
        J[u][v] = w
        J[v][u] = w
    return J


# ------------------------------------------------------------------- fp16 helpers

def fp16_hex(value):
    """Encode a Python float as IEEE-754 binary16, returned as 4 uppercase hex digits.

    The RTL reads Wi.txt with $readmemh, so the literal hex text is what ends up
    in the register - big-endian, no byte swapping.
    """
    return "%04X" % int.from_bytes(struct.pack(">e", float(value)), "big")


# ------------------------------------------------------------------- generators

def gen_adj_matrix(n, edges, path):
    """Write the packed 4-bit coupling matrix.

    Layout (verified against the committed file):
      * line i (1-based) holds the couplings of spin i,
      * the row is N groups of 4 characters, read right-aligned into a
        4096-bit register; the group at character offset 4k holds column
        j = N - k, i.e. the columns appear in the file in reverse order,
      * each group is {sign, |J|:2:0} where J = -w is the stored coupling, so
        the sign bit is set when the graph weight w is POSITIVE.
    """
    maxw = max(abs(w) for _, _, w in edges) if edges else 0
    if maxw > 7:
        raise ValueError(
            "|w| = %d does not fit the 3-bit magnitude field; "
            "this bitstream supports |w| <= 7" % maxw
        )

    # row -> {column: weight}
    rows = [dict() for _ in range(n + 1)]
    for u, v, w in edges:
        rows[u][v] = w
        rows[v][u] = w

    out = []
    for i in range(1, n + 1):
        parts = []
        for k in range(n):            # character offset 4k -> column N-k
            j = n - k
            w = rows[i].get(j, 0)
            # The SPU accumulates J_ij * sigma_j, so the value stored here must be
            # J = -w, not w. That sign is what makes the Ising ground state the
            # MAXIMUM cut: with J = -w, H = -1/2 s'Js = +sum_{i<j} w_ij s_i s_j,
            # whose minimum maximises C = sum w_ij [s_i != s_j].
            J = -w
            parts.append(("1" if J < 0 else "0") + format(abs(J), "03b"))
        out.append("".join(parts))
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")


def gen_spins(n, seed, path, which):
    """Write N+1 lines of spin bits; line 0 is unused by the RTL."""
    rng = np.random.default_rng(seed if which == "l" else seed + 1)
    bits = rng.integers(0, 2, size=n)
    with open(path, "w", newline="\n") as fh:
        fh.write("0\n")
        fh.write("\n".join(str(int(b)) for b in bits))
        fh.write("\n")
    return bits


def read_spins(path, n):
    """Read an existing spins file, returning the N bits at indices 1..N."""
    with open(path, "r") as fh:
        vals = [int(tok) for tok in fh.read().split()]
    if len(vals) < n + 1:
        raise ValueError("%s: expected at least %d entries, found %d" % (path, n + 1, len(vals)))
    return np.array(vals[1:n + 1], dtype=int)


def gen_weights(n, edges, spins_l, lambda_max, path):
    """Write the per-spin momentum weight `w` of sw/ising.py as fp16 hex.

        w[i] = sum_j ( 0.5*|J_ij| if s[j] == +1 else |J_ij| )   if s[i] == +1
             = 0.5*lambda_max                                   if s[i] == -1

    This is the "spin scale-aware" term: for a spin sitting at -1 the momentum
    scale is tied to the spectral radius of the coupling matrix instead of the
    local coupling sum.
    """
    rows = [dict() for _ in range(n + 1)]
    for u, v, w in edges:
        rows[u][v] = w
        rows[v][u] = w

    # Spins are stored as 1 bit. From the SPU flip logic (rtl/spu.v:268, where
    # delta_hi = 2*(sigmai_sp ? -fi : +fi)) the mapping is 0 -> sigma = +1,
    # 1 -> sigma = -1.
    s = np.where(spins_l == 1, -1, 1)

    lines = ["0000"]                                   # index 0 unused
    for i in range(1, n + 1):
        if s[i - 1] != 1:
            lines.append(fp16_hex(0.5 * lambda_max))
        else:
            total = 0.0
            for j, w in rows[i].items():
                total += 0.5 * abs(w) if s[j - 1] == 1 else abs(w)
            lines.append(fp16_hex(total))
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Generate the AIAPA_ising RTL configuration files from a Gset graph.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--graph", default="data/graph.txt",
                    help="Gset-format MaxCut instance (default: data/graph.txt)")
    ap.add_argument("--out-dir", default="data",
                    help="directory to write the configuration files into (default: data)")
    ap.add_argument("--seed", type=int, default=0,
                    help="seed for the initial spins (default: 0)")
    ap.add_argument("--keep-spins", action="store_true",
                    help="reuse the existing spinsl.txt/spinsr.txt instead of redrawing them")
    ap.add_argument("--check", action="store_true",
                    help="regenerate and byte-compare against the committed files; write nothing")
    args = ap.parse_args(argv)

    n, edges = read_gset(args.graph)
    print("graph   : %s" % args.graph)
    print("nodes   : %d" % n)
    print("edges   : %d" % len(edges))

    adj_path = os.path.join(args.out_dir, "adj_matrix.txt")
    wi_path = os.path.join(args.out_dir, "Wi.txt")
    sl_path = os.path.join(args.out_dir, "spinsl.txt")
    sr_path = os.path.join(args.out_dir, "spinsr.txt")

    if args.check:
        with open(adj_path, "r") as fh:
            committed = fh.read()
        tmp = adj_path + ".check"
        gen_adj_matrix(n, edges, tmp)
        with open(tmp, "r") as fh:
            regenerated = fh.read()
        os.remove(tmp)
        if regenerated == committed:
            print("check   : adj_matrix.txt reproduced BYTE-IDENTICAL (%d bytes)" % len(committed))
        else:
            cl, rl = committed.splitlines(), regenerated.splitlines()
            print("check   : MISMATCH", file=sys.stderr)
            print("          committed %d lines, regenerated %d lines" % (len(cl), len(rl)),
                  file=sys.stderr)
            for k in range(min(len(cl), len(rl))):
                if cl[k] != rl[k]:
                    print("          first differing row: %d" % (k + 1), file=sys.stderr)
                    print("            committed  : %s" % cl[k][:80], file=sys.stderr)
                    print("            regenerated: %s" % rl[k][:80], file=sys.stderr)
                    break
            return 1
        return 0

    J = build_J(n, edges)
    lambda_max = float(np.max(np.abs(np.linalg.eigvalsh(J))))
    print("lambda  : max|eig(J)| = %.4f  ->  0.5*lambda = %.4f" % (lambda_max, 0.5 * lambda_max))

    if args.keep_spins and os.path.exists(sl_path) and os.path.exists(sr_path):
        read_spins(sr_path, n)          # validate before we overwrite anything
        spins_l = read_spins(sl_path, n)
        print("spins   : kept existing %s and %s" % (sl_path, sr_path))
    else:
        spins_l = gen_spins(n, args.seed, sl_path, "l")
        gen_spins(n, args.seed, sr_path, "r")
        print("spins   : drawn with seed %d (+1 for the right replica)" % args.seed)

    gen_adj_matrix(n, edges, adj_path)
    print("wrote   : %s" % adj_path)

    gen_weights(n, edges, spins_l, lambda_max, wi_path)
    print("wrote   : %s" % wi_path)
    print("wrote   : %s" % sl_path)
    print("wrote   : %s" % sr_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

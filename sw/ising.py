#!/usr/bin/env python3
"""Algorithm-level reference model for the AIAPA spin scale-aware annealer.

This is the software counterpart of the RTL in rtl/. It runs the same
momentum-assisted Metropolis annealing schedule on a CPU so that the hardware
result can be checked against a reference.

Problem
-------
MaxCut. For a graph with edge weights w_ij, maximise

    C(s) = sum_{i<j} w_ij * [s_i != s_j]

which, with s_i in {-1,+1}, is equivalent to minimising

    H(s) = -1/2 * s' J s = sum_{i<j} w_ij * s_i * s_j

for the coupling matrix J_ij = -w_ij. Note the minus sign: J is the *negative*
of the graph edge weight, which is what makes the Ising ground state the maximum
cut and not the minimum cut.

Usage
-----
    python sw/ising.py                            # bundled instance, 800 sweeps
    python sw/ising.py --seed 3 --save-plot run.png
    python sw/ising.py --graph data/graph.txt --steps 800 --T-start 13
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np


def read_graph(file_path):
    """Read a Gset-format graph: optional '#', then 'N M', then 'i j w'."""
    graph = {}
    num_spins = None
    with open(file_path, "r") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("c "):
                continue
            parts = line.split()
            if num_spins is None and len(parts) == 2:
                num_spins = int(parts[0])
                continue
            if len(parts) != 3:
                raise ValueError("expected 'i j w', got %r" % line)
            u, v, weight = (int(t) for t in parts)
            graph.setdefault(u, []).append((v, weight))
            graph.setdefault(v, []).append((u, weight))  # undirected
    if num_spins is None:
        raise ValueError("%s: no 'N M' header found" % file_path)
    return graph, num_spins


def build_J(graph, num_spins):
    """Coupling matrix J_ij = -w_ij (MaxCut convention). Index 0 is unused."""
    J = np.zeros((num_spins + 1, num_spins + 1))
    for u in graph:
        for v, weight in graph[u]:
            J[u][v] = -weight
            J[v][u] = -weight
    return J


class MomentumAnnealerRef:
    """Two-replica momentum annealer, as implemented in the RTL.

    The two replicas hold independent spin vectors; each sweep updates the left
    replica from the right replica's spins and vice versa, so the local fields
    of one replica are computed from the other. `Fl`/`Fr` carry the local
    fields forward incrementally instead of recomputing J @ s each sweep.
    """

    def __init__(self, J, lambda_max, seed=None):
        self.N = J.shape[0]
        self.J = np.array(J, dtype=float)

        rng = np.random.default_rng(seed)
        # Independent random start for each replica. Index 0 is unused.
        self.spins_L = rng.choice([-1, 1], size=self.N)
        self.spins_R = rng.choice([-1, 1], size=self.N)

        # Local fields, carried across sweeps.
        self.Fl = np.zeros(self.N, dtype=np.float64)
        self.Fr = np.zeros(self.N, dtype=np.float64)

        # Spin-scale-aware momentum weight.
        #
        #   w[i] = sum_j ( 0.5*|J_ij| if s_L[j] == +1 else |J_ij| )  if s_L[i] == +1
        #        = 0.5*lambda_max                                     if s_L[i] == -1
        #
        # For a spin sitting at -1 the momentum scale is tied to the spectral
        # radius of the coupling matrix rather than to the local coupling sum.
        self.w = np.zeros(self.N, dtype=np.float64)
        for i in range(1, self.N):
            for j in range(1, self.N):
                if self.spins_L[i] == 1:
                    if self.spins_L[j] == 1:
                        self.w[i] += abs(self.J[i][j]) - 0.5 * abs(self.J[i][j])
                    else:
                        self.w[i] += abs(self.J[i][j])
                else:
                    self.w[i] = 0.5 * lambda_max

        self.fs = np.zeros(self.N, dtype=int)      # spins that flipped this sweep
        self.index = np.zeros(self.N, dtype=int)   # their indices
        self.fsn = 0                               # number of flips this sweep

        self.energy_history = []

    def energy(self, spins):
        """Ising Hamiltonian H = -1/2 s' J s."""
        return -0.5 * (spins @ self.J @ spins)

    def cut(self, spins):
        """MaxCut value C = sum_{i<j} w_ij [s_i != s_j].

        With J_ij = -w_ij and [s_i != s_j] = (1 - s_i s_j)/2:

            C = sum_{i<j} w_ij (1 - s_i s_j)/2 = -1/4 * sum_ij J_ij (1 - s_i s_j)

        the factor 1/4 coming from the 1/2 over unordered pairs applied to the
        1/2 in the indicator.
        """
        prod = np.outer(spins, spins)
        return -0.25 * float(np.sum(self.J * (1.0 - prod)))

    def update_spin(self, i, T, rand, lr, lf):
        """Metropolis test for spin i. `lr` selects the replica ('l' or 'r')."""
        if lr == "l":
            deltaH = 2 * self.spins_L[i] * lf
        else:
            deltaH = 2 * self.spins_R[i] * lf
        if deltaH <= 0 or deltaH <= T * rand:
            self.fsn += 1
            if lr == "l":
                self.spins_L[i] = -self.spins_L[i]
                self.fs[self.fsn] = self.spins_L[i]
            else:
                self.spins_R[i] = -self.spins_R[i]
                self.fs[self.fsn] = self.spins_R[i]
            self.index[self.fsn] = i

    def run(self, steps, T_start, pk_start, momentum_alpha, verbose=True):
        fs_r_new = []
        fs_l_new = []
        fs_indexl_new = []
        fs_indexr_new = []
        Fleft_new = 0
        Fright_new = 0
        self.fsn = 0
        self.energy_history = []

        # Cache the current state of each replica for the incremental updates.
        fs_r = self.spins_R.copy()
        fs_l = self.spins_L.copy()
        fs_indexl = list(range(0, self.N))
        fs_indexr = list(range(0, self.N))

        for t in range(1, steps + 1):
            if t == 1:
                Fleft = self.N - 1
                Fright = self.N - 1
                fs_indexl = [i for i in range(0, self.N)]
                fs_indexr = [i for i in range(0, self.N)]
                fs_r = self.spins_R.copy()
                fs_l = self.spins_L.copy()
            else:
                Fleft = Fleft_new
                Fright = Fright_new
                fs_indexl = fs_indexl_new
                fs_indexr = fs_indexr_new
                fs_r = fs_r_new
                fs_l = fs_l_new

            # Temperature schedule, momentum acceptance probability and step size.
            T = T_start * (momentum_alpha ** t)
            pk = pk_start - t * 1.0 / 2000
            ck = np.sqrt(t * 1.0 / 1000)
            momentum = np.zeros(self.N)

            # ---- left replica: momentum pass ----
            for i in range(1, self.N):
                rand = np.random.random()
                momentum[i] = (pk < rand) * ck * self.w[i]
                if Fright == 0:
                    lf = self.Fl[i] + momentum[i] * self.spins_R[i]
                    self.update_spin(i, T, rand, "l", lf)

            # ---- left replica: field pass, driven by the right replica's flips ----
            for i in range(1, Fright + 1):
                for j in range(1, self.N):
                    idx = fs_indexr[i]
                    self.Fl[j] += 2 * self.J[j][idx] * fs_r[i] if t > 1 else self.J[j][idx] * fs_r[i]
                    if i == Fright:
                        lf = self.Fl[j] + momentum[j] * self.spins_R[j]
                        rand = np.random.random()
                        self.update_spin(j, T, rand, "l", lf)
            fs_l_new = self.fs.copy()
            fs_indexl_new = self.index.copy()
            Fleft_new = self.fsn
            self.fsn = 0

            # ---- right replica: momentum pass ----
            for i in range(1, self.N):
                rand = np.random.random()
                momentum[i] = (pk < rand) * ck * self.w[i]
                if Fleft == 0:
                    lf = self.Fr[i] + momentum[i] * self.spins_L[i]
                    self.update_spin(i, T, rand, "r", lf)

            # ---- right replica: field pass, driven by the left replica's flips ----
            for i in range(1, Fleft + 1):
                for j in range(1, self.N):
                    idx = fs_indexl[i]
                    self.Fr[j] += 2 * self.J[j][idx] * fs_l[i] if t > 1 else self.J[j][idx] * fs_l[i]

            if i == Fleft:
                for j in range(1, self.N):
                    lf = self.Fr[j] + momentum[j] * self.spins_L[j]
                    rand = np.random.random()
                    self.update_spin(j, T, rand, "r", lf)
            fs_r_new = self.fs.copy()
            fs_indexr_new = self.index.copy()
            Fright_new = self.fsn
            self.fsn = 0

            a = self.energy(self.spins_L)
            self.energy_history.append(a)
            if verbose:
                print("%d %d %d %s" % (t, Fright_new, Fleft_new, a))

        return self.spins_L, a


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Reference momentum annealer for the AIAPA architecture (MaxCut).")
    ap.add_argument("--graph", default="data/graph.txt", help="Gset-format instance")
    ap.add_argument("--steps", type=int, default=800, help="number of sweeps K")
    ap.add_argument("--T-start", type=float, default=13.0, help="initial temperature")
    ap.add_argument("--pk-start", type=float, default=0.5, help="initial momentum acceptance probability")
    ap.add_argument("--alpha", type=float, default=0.9969, help="geometric cooling rate")
    ap.add_argument("--seed", type=int, default=None, help="RNG seed for reproducible runs")
    ap.add_argument("--save-plot", default=None, metavar="PATH",
                    help="write the energy curve to PATH instead of showing it")
    ap.add_argument("--show-plot", action="store_true", help="open the energy curve in a window")
    args = ap.parse_args(argv)

    if args.seed is not None:
        np.random.seed(args.seed)

    graph, num_spins = read_graph(args.graph)
    J = build_J(graph, num_spins)

    # Spectral radius of the coupling matrix; sets the momentum scale for spins
    # sitting at -1.
    lambda_max = float(np.max(np.abs(np.linalg.eigvalsh(J))))
    print("instance : %s" % args.graph)
    print("spins    : %d" % num_spins)
    print("lambda   : max|eig(J)| = %.4f" % lambda_max)

    annealer = MomentumAnnealerRef(J, lambda_max, seed=args.seed)
    spins, energy = annealer.run(
        steps=args.steps,
        T_start=args.T_start,
        pk_start=args.pk_start,
        momentum_alpha=args.alpha,
    )

    cut = annealer.cut(spins)
    print("-" * 60)
    print("final energy  H = %.1f" % energy)
    print("final MaxCut  C = %.1f" % cut)
    print("spins         : %s" % np.array2string(spins, separator=","))

    history = annealer.energy_history
    if args.save_plot or args.show_plot:
        import matplotlib
        if args.save_plot and not args.show_plot:
            matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.plot(range(1, len(history) + 1), history, linestyle="-", color="b")
        plt.xlabel("sweep")
        plt.ylabel("Ising energy")
        plt.title("AIAPA reference annealer (%s)" % os.path.basename(args.graph))
        plt.grid(alpha=0.3)
        if args.save_plot:
            plt.savefig(args.save_plot, dpi=150, bbox_inches="tight")
            print("plot          : %s" % args.save_plot)
        if args.show_plot:
            plt.show()

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
#
# Run the AIAPA_ising RTL simulation with Vivado XSim.
#
#   scripts/run_sim.sh              compile, elaborate and run the full 800 sweeps
#   scripts/run_sim.sh --fast       short smoke run (20 sweeps) - quick sanity check
#   scripts/run_sim.sh --gui        run, then open the waveform database in Vivado
#
# Must be run from anywhere - the script cd's to the repository root, because the
# RTL loads its configuration with relative paths (data/*.txt).
#
# Override the Vivado location with:  VIVADO_BIN=/path/to/Vivado/bin scripts/run_sim.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# NOTE: do not set MSYS2_ARG_CONV_EXCL / MSYS_NO_PATHCONV here. They would stop
# Git Bash rewriting `=`-bearing arguments, but they also break launching the
# Vivado .bat wrappers (cmd opens interactively instead of running the tool).
# Compile-time defines are passed through an -f options file instead, which
# sidesteps argument mangling entirely.

GUI=0
FAST=0
for arg in "$@"; do
  case "$arg" in
    --gui)  GUI=1 ;;
    --fast) FAST=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- locate Vivado
find_vivado_bin() {
  if [ -n "${VIVADO_BIN:-}" ]; then printf '%s\n' "$VIVADO_BIN"; return; fi
  if command -v xvlog >/dev/null 2>&1; then dirname "$(command -v xvlog)"; return; fi

  local candidate
  for candidate in \
      /d/Xilinx/Vivado/*/bin /c/Xilinx/Vivado/*/bin /e/Xilinx/Vivado/*/bin \
      "/c/Program Files/Xilinx/Vivado"/*/bin \
      "$HOME"/Xilinx/Vivado/*/bin ; do
    if [ -x "$candidate/xvlog" ] || [ -x "$candidate/xvlog.bat" ]; then
      printf '%s\n' "$candidate"; return
    fi
  done
  return 1
}

if ! VIVADO_BIN="$(find_vivado_bin)"; then
  cat >&2 <<'EOF'
error: could not find Vivado (xvlog).

Set it explicitly, e.g.
    VIVADO_BIN=/d/Xilinx/Vivado/2023.2/bin scripts/run_sim.sh

Any Verilog simulator will do - the equivalent with Icarus Verilog is
    iverilog -o sim.out -f rtl/filelist.f sim/tb_top_control.v && vvp sim.out
EOF
  exit 1
fi

SNAPSHOT=tb_top_control_sim

# Put Vivado on PATH and invoke the tools by bare name. On Windows this is what
# makes the shell pick up xvlog.bat / xelab.bat / xsim.bat: invoking a .bat by
# absolute path from Git Bash spawns an interactive cmd instead of running it.
export PATH="$VIVADO_BIN:$PATH"
XVLOG=xvlog
XELAB=xelab
XSIM=xsim

echo "== Vivado XSim : $VIVADO_BIN"
echo "== working dir : $REPO_ROOT"

# xsim.dir can be left locked by an interrupted run; removing it is best-effort.
rm -rf xsim.dir 2>/dev/null || true

echo "== xvlog (compile)"
# Plain Verilog-2001: the RTL is not SystemVerilog. It will not compile with -sv,
# because writeback_router has a port named `local`, which -sv reserves.
if [ "$FAST" -eq 1 ]; then
  OPTS="$REPO_ROOT/.xsim_fast_opts.f"
  printf -- "-d SWEEPS=20\n-d CHECK_EVERY=2\n" > "$OPTS"
  "$XVLOG" -f "$OPTS" -f rtl/filelist.f sim/tb_top_control.v
  rm -f "$OPTS"
else
  "$XVLOG" -f rtl/filelist.f sim/tb_top_control.v
fi

echo "== xelab (elaborate)"
"$XELAB" -debug typical -s "$SNAPSHOT" tb_top_control

echo "== xsim (run)"
# --runall is 'run all; quit'. Note: output is buffered until the run ends.
if [ "$GUI" -eq 1 ]; then
  "$XSIM" "$SNAPSHOT" -wdb tb_top_control.wdb --gui
else
  "$XSIM" "$SNAPSHOT" -wdb tb_top_control.wdb --runall
fi

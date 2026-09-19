# AIAPA_ising - convenience wrapper around scripts/run_sim.sh and sw/.
#
# The shell script is the tested path; this Makefile just wraps the same
# commands for people who prefer make. Run from the repository root.

VIVADO_BIN ?= /d/Xilinx/Vivado/2023.2/bin
XVLOG      := $(VIVADO_BIN)/xvlog
XELAB      := $(VIVADO_BIN)/xelab
XSIM       := $(VIVADO_BIN)/xsim
SNAPSHOT   := tb_top_control_sim

.PHONY: help sim fast wave algo config check clean

help:
	@echo "make sim      compile, elaborate and run the full simulation"
	@echo "make fast     short 20-sweep smoke run"
	@echo "make wave     same as sim, then open the waveform database"
	@echo "make algo     run the Python reference annealer (800 sweeps)"
	@echo "make config   regenerate the RTL configuration files"
	@echo "make check    verify adj_matrix.txt is reproduced byte-for-byte"
	@echo "make clean    remove build artefacts"

# The RTL loads data/*.txt by relative path, so everything runs from the root.
sim:
	$(XVLOG) -f rtl/filelist.f sim/tb_top_control.v
	$(XELAB) -debug typical -s $(SNAPSHOT) tb_top_control
	$(XSIM) $(SNAPSHOT) -wdb tb_top_control.wdb --runall

fast:
	$(XVLOG) -d SWEEPS=20 -d CHECK_EVERY=2 -f rtl/filelist.f sim/tb_top_control.v
	$(XELAB) -debug typical -s $(SNAPSHOT) tb_top_control
	$(XSIM) $(SNAPSHOT) -wdb tb_top_control.wdb --runall

wave:
	$(XVLOG) -f rtl/filelist.f sim/tb_top_control.v
	$(XELAB) -debug typical -s $(SNAPSHOT) tb_top_control
	$(XSIM) $(SNAPSHOT) -wdb tb_top_control.wdb --gui

algo:
	python sw/ising.py --steps 800 --seed 1

config:
	python sw/gen_config.py --keep-spins

check:
	python sw/gen_config.py --check

clean:
	rm -rf xsim.dir xsim.jou xsim.log *.wdb *.fst *.vcd *.pb sim.out
	find . -name __pycache__ -type d -prune -exec rm -rf {} +

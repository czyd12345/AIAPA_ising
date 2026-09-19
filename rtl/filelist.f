// AIAPA_ising compile order (rtl + simulation-only stubs).
//
// Used by scripts/run_sim.sh and the Makefile. `xvlog -f rtl/filelist.f` accepts
// any order, but `iverilog -f rtl/filelist.f` requires leaves before parents,
// so the order below is bottom-up.

// vendor primitive stubs (simulation only)
sim/stubs/xilinx_prims.v

// leaf modules
rtl/muxkey.v
rtl/fifo.v
rtl/float_op.v
rtl/float_mul.v

// UART
rtl/uart_transmitter.v
rtl/uart.v

// processing / routing
rtl/spu.v
rtl/writeback_router.v
rtl/readout_router.v

// control and top level
rtl/top_control.v
rtl/aiapa_top.v

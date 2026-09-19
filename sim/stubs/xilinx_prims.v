`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : xilinx_prims  (simulation-only behavioural stubs)
// Description : Behavioural stand-ins for the vendor primitives that the RTL
//               instantiates but that are not part of this repository:
//
//                 ila_0          Xilinx Integrated Logic Analyzer debug core
//                                instantiated in rtl/spu.v
//                 REGISTER_CE    N-bit register with clock enable
//                 REGISTER_R_CE  N-bit register with clock enable and reset
//                                instantiated in rtl/uart_transmitter.v
//
//               SIMULATION ONLY. These are not synthesis equivalents and must
//               not be used to build an FPGA bitstream. For hardware, regenerate
//               the ila_0 IP core and use the vendor primitive library with the
//               Xilinx flow instead.
//
//               The port lists and parameter names match the instantiations in
//               the RTL exactly, so no RTL edit is required to simulate.
//
//               Reset semantics: REGISTER_R_CE is modelled with a SYNCHRONOUS
//               reset that dominates the clock enable. If the vendor primitive
//               you target resets asynchronously, this differs only around a
//               reset edge, where the top-level reset is held for many cycles
//               anyway.
//////////////////////////////////////////////////////////////////////////////////

// Xilinx ILA debug core. Observes the 1024-bit spin vector; a no-op in
// simulation. Replace with the real IP when targeting hardware.
module ila_0 (
    input wire clk,
    input wire [1023:0] probe0
);
    // The ILA is purely passive - nothing to model.
endmodule


// N-bit register with clock enable. `q` holds its value while `ce` is low.
module REGISTER_CE #(
    parameter integer N    = 1,
    parameter integer INIT = 0
)(
    output reg  [N-1:0] q,
    input  wire [N-1:0] d,
    input  wire         ce,
    input  wire         clk
);
    initial q = INIT;

    always @(posedge clk)
        if (ce) q <= d;
endmodule


// N-bit register with clock enable and synchronous reset. Reset dominates the
// clock enable.
module REGISTER_R_CE #(
    parameter integer N    = 1,
    parameter integer INIT = 0
)(
    output reg  [N-1:0] q,
    input  wire [N-1:0] d,
    input  wire         ce,
    input  wire         rst,
    input  wire         clk
);
    initial q = INIT;

    always @(posedge clk)
        if (rst)     q <= INIT;
        else if (ce) q <= d;
endmodule

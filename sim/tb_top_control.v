`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_top_control
// Description : Self-checking testbench for aiapa_top on the bundled instance.
//
//               Every CHECK_EVERY sweeps it reads the on-chip spin register
//               (spu1.spin_l) together with the off-chip coupling matrix
//               (mem_j) and reports
//
//                   k  <Ising energy H>  <MaxCut value C>
//
//               where, over the edges (i,j) of the instance,
//
//                   H = sum_{i<j} w_ij * sigma_i * sigma_j
//                   C = sum_{i<j} w_ij * [sigma_i != sigma_j]
//
//               and the two are related by C = (W - H)/2 with W = sum w_ij,
//               computed here directly from mem_j so no instance knowledge is
//               hardcoded. Both are printed; C is the value to compare against
//               published MaxCut results for the instance.
//
//               mem_j layout: the stored coupling for column j occupies bits
//               (j-1)*4 +: 4 as {sign, |J|:2:0}, sign at bit (j-1)*4+3, where
//               J = -w (the MaxCut convention). To report the cut we recover
//               the graph edge weight w = -J.
//
//               Run from the repository root so that the data/*.txt paths in
//               the RTL resolve. See scripts/run_sim.sh.
//////////////////////////////////////////////////////////////////////////////////

module tb_top_control;
  // Compile-time knobs:
  //   SWEEPS       how many sweeps to observe       (default: aiapa_top's N_STEPS)
  //   CHECK_EVERY  how often the O(N^2) energy check runs
  //   TIMEOUT      watchdog, in clock cycles, so a hang cannot stall CI
  //   N_STEPS      annealing length passed to the DUT (800 in the RTL default)
  //
  // Override them through an -f options file. Git Bash/MSYS mangles the '=' in
  // `xvlog -d NAME=value`, and MSYS2_ARG_CONV_EXCL would break launching the
  // Vivado .bat wrappers, so an options file is the portable way:
  //
  //     echo "-d N_STEPS=40"  > .opts.f
  //     echo "-d SWEEPS=40"  >> .opts.f
  //     xvlog -f .opts.f -f rtl/filelist.f sim/tb_top_control.v
  `ifndef SWEEPS
    `define SWEEPS 800
  `endif
  `ifndef CHECK_EVERY
    `define CHECK_EVERY 50
  `endif
  `ifndef TIMEOUT
    // Watchdog, in CLOCK CYCLES. Converted to nanoseconds below using the
    // testbench's 10 ns clock period. This only guards against a genuine hang:
    // 100M cycles is 1 s of simulation time, far longer than any short run and
    // far shorter than the ~10^9 cycles a full 800-sweep anneal needs.
    `define TIMEOUT 100000000
  `endif
  `ifndef N_STEPS
    // Number of annealing sweeps the DUT runs. The RTL default is 800, but an
    // early sweep costs ~O(N * F) cycles (F = flips that sweep, ~800 at high
    // temperature), so a full 800-sweep XSim run takes hours. Lower this to
    // simulate a complete but shorter anneal.
    `define N_STEPS 800
  `endif
  `ifndef T_INIT
    // Initial temperature as an fp16 literal. 16'h4A80 = 13.0 (the RTL
    // default); 16'h3400 = 0.25 makes the first sweeps essentially greedy,
    // which is useful for short directional experiments.
    `define T_INIT 16'h4A80
  `endif
  `ifndef PK_INIT
    `define PK_INIT 16'h3800      // 0.5
  `endif
  `ifndef CK_INIT
    `define CK_INIT 16'h0000      // 0.0
  `endif
  `ifndef ALPHA
    `define ALPHA 16'h3BFA        // ~0.9969
  `endif

  // Spin count of the bundled instance. Kept separate from `N_STEPS` (the
  // annealing length): this one bounds the edge loops below.
  localparam integer N = 800;

  localparam integer SWEEPS      = `SWEEPS;
  localparam integer CHECK_EVERY = `CHECK_EVERY;
  localparam integer TIMEOUT     = `TIMEOUT;               // clock cycles
  // 100 MHz -> 10 ns per cycle. The multiply must be done in 64 bits: a 32-bit
  // `TIMEOUT * 10` overflows above 214,748,364 cycles and the negative result
  // makes the `#` delay fire at time 0.
  localparam time    TIMEOUT_NS  = TIMEOUT * 64'd10;

  wire serial_out;
  wire finish_send;

  reg clk = 0;
  reg rst_n = 1;
  reg ap_start_n = 1;

  always #5 clk = ~clk;  // 100 MHz

  aiapa_top #(
    .N_STEPS (`N_STEPS),
    .T_INIT  (`T_INIT),
    .PK_INIT (`PK_INIT),
    .CK_INIT (`CK_INIT),
    .ALPHA   (`ALPHA)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .ap_start_n (ap_start_n),
    .serial_out (serial_out),
    .finish_send(finish_send)
  );

  integer i, j, sweep;
  integer mag, w, same, cut, h, W;

  // Total edge weight, summed straight out of the coupling matrix.
  task calc_W;
    begin
      W = 0;
      for (i = 1; i <= N; i = i + 1)
        for (j = i + 1; j <= N; j = j + 1)
          if (dut.mem_j[i-1][(j-1)*4 +: 4] != 4'b0000)
            // stored J = -w, so w = -J; sum those to get W = sum(w_ij)
            W = W + (dut.mem_j[i-1][(j-1)*4+3] ? dut.mem_j[i-1][(j-1)*4 +: 3]
                                              : -dut.mem_j[i-1][(j-1)*4 +: 3]);
    end
  endtask

  // Ising energy and MaxCut value of the current spin configuration.
  //
  // With sigma_i * sigma_j = +1 for equal bits and -1 for different bits:
  //     same = sum_{i<j, equal bits}     w_ij
  //     cut  = sum_{i<j, differing bits} w_ij   (= MaxCut value C)
  //     H    = same - cut                        (Ising energy)
  //
  // The assertions below are NOT a physics check: same + cut == W holds for
  // every possible spin configuration, because each pair contributes its w_ij
  // to exactly one of the two accumulators. They only catch an accumulate /
  // truncate bug in this loop.
  task calc_energy;
    begin
      same = 0;
      cut  = 0;
      for (i = 1; i <= N; i = i + 1) begin
        for (j = i + 1; j <= N; j = j + 1) begin
          mag = dut.mem_j[i-1][(j-1)*4 +: 3];
          // recover the graph edge weight from the stored coupling J = -w
          w   = dut.mem_j[i-1][(j-1)*4+3] ? mag : -mag;
          if (dut.spu1.spin_l[i] == dut.spu1.spin_l[j]) same = same + w;
          else                                          cut  = cut  + w;
        end
      end
      h = same - cut;
      if (same + cut != W)
        $display("WARNING: accumulator consistency failed: same=%0d cut=%0d W=%0d", same, cut, W);
    end
  endtask

  initial begin
    $dumpfile("tb_top_control.fst");
    $dumpvars(0, tb_top_control);
  end

  // watchdog
  initial begin
    #TIMEOUT_NS;
    $display("TIMEOUT: simulation did not finish within %0d cycles", TIMEOUT);
    $finish(1);
  end

  initial begin
    // Reset: rst_n and ap_start_n are both active low. Hold reset for a few
    // cycles so that aiapa_top latches its run configuration, then release
    // reset and assert ap_start_n.
    rst_n      = 1'b0;
    ap_start_n = 1'b1;
    repeat (4) @(posedge clk);
    $display("[%0t] Release reset", $time);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    ap_start_n = 1'b0;   // ap_start = 1 -> top_control leaves IDLE

    calc_W;
    $display("Instance: N=%0d  W = sum(w_ij) = %0d", N, W);
    $display("  k        H(ising)      C(maxcut)");

    for (sweep = 1; sweep <= SWEEPS; sweep = sweep + 1) begin
      wait (dut.top_controller.state == 3'd2 && dut.top_controller.m == 3);
      if ((sweep % CHECK_EVERY) == 0 || sweep == SWEEPS) begin
        calc_energy;
        $display("%4d  %12d  %12d", sweep, h, cut);
      end
      repeat (2) @(posedge clk);
    end

    calc_energy;
    $display("--------------------------------------------------");
    $display("Final after %0d sweeps: H = %0d, MaxCut C = %0d", SWEEPS, h, cut);
    $finish(0);
  end

endmodule

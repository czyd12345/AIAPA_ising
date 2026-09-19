`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : aiapa_top
// Description : Top level of the AIAPA spin scale-aware self-adaptive Ising
//               annealing processing architecture.
//
//               Instantiates one SPU (spin processing unit) together with the
//               writeback / readout routers, the off-chip coupling matrix and
//               the top-level control FSM.
//
//               See docs/architecture.md for the module hierarchy, the 32-bit
//               packet formats and the data file layouts.
//
// Reference   : D. Jiang, X. Wang, Z. Huang, L. Kang, S. Yang and E. Yao,
//               "A Spin Scale-Aware Self-Adaptive Ising Annealing Processing
//               Architecture for Combinatorial Optimization Problems",
//               IEEE Trans. Circuits Syst. I, vol. 72, no. 10, pp. 5811-5824,
//               Oct. 2025, doi: 10.1109/TCSI.2025.3541888
//////////////////////////////////////////////////////////////////////////////////

module aiapa_top #(
    // ---------------------------------------------------------------------
    // Run configuration. These mirror the hyper-parameters of sw/ising.py;
    // each is latched into top_control while `rst_n` is asserted.
    // ---------------------------------------------------------------------
    parameter [31:0] N_SPINS = 32'd800,    // N : number of spins
    parameter [31:0] N_STEPS = 32'd800,    // K : number of annealing sweeps
    parameter [15:0] PK_INIT = 16'h3800,   // pk_start, fp16        = 0.5
    parameter [15:0] CK_INIT = 16'h0000,   // ck at t=0, fp16       = 0.0
    parameter [15:0] T_INIT  = 16'h4A80,   // T_start, fp16         = 13.0
    parameter [15:0] ALPHA   = 16'h3BFA    // cooling rate, fp16    = 0.99707
                                           //   (0x3BFA is the fp16 value
                                           //    nearest to ising.py's 0.9969)
)(
    input clk,
    input rst_n,
    input ap_start_n,
    output serial_out,
    output finish_send
);
   wire rst=~rst_n;
   wire ap_start=~ap_start_n;
    reg [31:0] in_n;
    reg [31:0] in_k;
    reg [15:0] in_p;
    reg [15:0] in_c;
    reg [15:0] in_temp;
    reg [15:0] in_alpha;
    wire [2:0] response;
    // Latch the run configuration while reset is asserted; top_control samples
    // these in its IDLE state. Change them via the aiapa_top parameters above.
    always @(posedge clk)
    begin
        if(rst)
        begin
            in_n       <= N_SPINS;   // N
            in_k       <= N_STEPS;   // K
            in_p       <= PK_INIT;   // pk_start
            in_c       <= CK_INIT;   // ck at t=0
            in_temp    <= T_INIT;    // T_start
            in_alpha   <= ALPHA;     // cooling rate
        end
    end
    wire [31:0] local_res,rdout_in,wb_out,dout_top,fsn;
    wire rd_en_top,rd_en_spu,mem_r,valid;
    wire [31:0] mem_addr,din_top;
    // ------------------------------------------------------------------
    // Off-chip coupling matrix J.
    //
    // mem_j[i] is one 4096-bit row holding N 4-bit sign-magnitude couplings,
    // {sign, |J|:2:0}, packed so that the coupling for column j sits at bits
    // 4*(j-1) +: 4. A 3200-character row is loaded right-aligned into the
    // 4096-bit word, so character offset 4k holds column j = N - k, i.e. the
    // columns appear in the file in REVERSE order.
    //
    // data/adj_matrix.txt is produced by sw/gen_config.py, which regenerates
    // it byte-for-byte (see `gen_config.py --check`).
    // ------------------------------------------------------------------
    reg [4095:0] mem_j [0:1023];
    wire [3:0] j_out;
    initial $readmemb("data/adj_matrix.txt",mem_j);
   
    reg [3:0] j;
    integer index1,index2;
    always @(*) begin
        index1=mem_addr[15:0]-1;
        index2=mem_addr[31:16]*4;
        j[0]=mem_j[index1][index2-4];//i,j
        j[1]=mem_j[index1][index2-3];//i,j
        j[2]=mem_j[index1][index2-2];//i,j
        j[3]=mem_j[index1][index2-1];//i,j
    end
    spu #(5,0)  spu1(
    .clk(clk),
    .rst(rst),
    .datain_pkt(wb_out),
    .j_left(j_out),
    .response(response[2]),
    .local_res(local_res),
    .next_rdout(rdout_in),
    .rd_en_j(rd_en_spu),
    .fsn(fsn),
    .valid(valid),
    .left_res(0),
    .right_res(0),
    .left_rdout(0),
    .right_rdout(0),
      .finish_send(finish_send)
    );
    wire empty,full;
    fifo #(4,16) fifo3(
        .clk(clk),
        .rst(rst),
        .wr_en(mem_r),
        .rd_en(rd_en_spu),
        .din(j),
        .dout(j_out),
        .full(full),
        .empty(empty)
    );
    readout_router #(5,0) rdout1(
    .clk(clk),
    .rst(rst),
    .local(rdout_in),
    .response_in(rd_en_top),
    .dout(din_top),
    .response(response),
    .rdout_L(0),
    .rdout_R(0),
    .res_L(0),
    .res_R(0)
    );
    wire [31:0] left_out,right_out;
     top_control #(1,1,2) top_controller(
    .clk(clk),
    .rst(rst),
    .ap_start(ap_start),
    .datain_pkt(din_top),// (reserved: extra inputs)
    .in_n      (in_n),
    .in_k      (in_k),
    .in_p      (in_p),
    .in_c      (in_c),
    .in_temp   (in_temp),
    .in_alpha  (in_alpha),
    .data_pkt  (dout_top),
    .mem_r(mem_r),
    .mem_addr(mem_addr), // off-chip coupling matrix address
    .rd_en_out(rd_en_top),
    .fsn(fsn),
    .valid(valid),
    .serial_out(serial_out),
    .finish_send(finish_send)
    );
   writeback_router #(5,0) wb1(
    .clk(clk),
    .rst(rst),
    .local(local_res),       // this SPU's result: {type(3), 6'b0, addr(6), psum(16)}
    .neighbor(dout_top),    // from the level below, parallel mode: {type(3), 5'b0, num(7), spin+index(17)}
    .local_out(wb_out),
    .right_out(right_out),
    .left_out(left_out)
    );
endmodule

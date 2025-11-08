`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/28 16:07:40
// Design Name: 
// Module Name: aiapa_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module aiapa_top(
    input clk,
    input rst_n,
    input ap_start_n,
    //input [31:0] in_n,
    //input [31:0] in_k,
    //input [15:0] in_p,
    //input [15:0] in_c,
    //input [15:0] in_temp,
    //input [15:0] in_alpha,
    //output [31:0] din_top,
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
    always @(posedge clk)
    begin
        if(rst) 
        begin
            in_n       <= 32'd800;   // N
            in_k       <= 32'd800;      // K
            in_p       <= 16'h3800;     // P=0.5
            in_c       <= 16'h0000;     // C=0 (按你协议，这里随便给�?????????�?????????)
            in_temp    <= 16'h4A80;
            in_alpha   <= 16'h3bfa;    // 0.9969
        end
    end
    wire [31:0] local_res,rdout_in,wb_out,dout_top,fsn;
    wire rd_en_top,rd_en_spu,mem_r,valid;
    wire [31:0] mem_addr,din_top;
    //128/4=32
    reg [4095:0] mem_j [0:1023];
    wire [3:0] j_out;
    initial $readmemb("F:/SDR/adj_matrix.txt",mem_j);
   
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
    .datain_pkt(din_top),//可能再加
    .in_n      (in_n),
    .in_k      (in_k),
    .in_p      (in_p),
    .in_c      (in_c),
    .in_temp   (in_temp),
    .in_alpha  (in_alpha),
    .data_pkt  (dout_top),
    .mem_r(mem_r),
    .mem_addr(mem_addr), //off-chip地址
    .rd_en_out(rd_en_top),
    .fsn(fsn),
    .valid(valid),
    .serial_out(serial_out),
    .finish_send(finish_send)
    );
   writeback_router #(5,0) wb1(
    .clk(clk),
    .rst(rst),
    .local(local_res),       //当前SPU的输入，计算结果 {type(3),6'b0,addr(6),psum(16)} e=63
    .neighbor(dout_top),    //来自下面一层的输入平行模式，{type(3),5'b0,num(7),spin+index(17)} p=64
    .local_out(wb_out),
    .right_out(right_out),
    .left_out(left_out)
    );
endmodule

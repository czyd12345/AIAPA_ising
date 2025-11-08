`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/08 19:24:33
// Design Name: 
// Module Name: fifo
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


module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 32,
    parameter POINTER_WIDTH = $clog2(DEPTH)
) (
    input clk, rst,

    // Write side
    input wr_en,
    input [WIDTH-1:0] din,
    output full,

    // Read side
    input rd_en,
    output [WIDTH-1:0] dout,
    output  empty
);
    // TODO replace these assignment statements.
    reg [WIDTH-1:0] buffer [DEPTH-1:0];
    reg [WIDTH-1:0] dout1;
    reg [POINTER_WIDTH:0] read_ptr,write_ptr;
    integer i;
    initial begin
        for(i=0;i<DEPTH;i=i+1) buffer[i]=0;
    end
    always @(posedge clk) 
    begin
        if(rst) begin
            read_ptr<=0;
            write_ptr<=0;
            dout1<=0;
        end
        else begin
            if(wr_en && !full) begin
               buffer[write_ptr[POINTER_WIDTH-1:0]]<=din;
               write_ptr<=write_ptr+1;
            end
            if(rd_en && !empty) begin
                dout1<=buffer[read_ptr[POINTER_WIDTH-1:0]];
                read_ptr<=read_ptr+1;
            end
        end
    end
    assign full=(read_ptr[POINTER_WIDTH-1:0]==write_ptr[POINTER_WIDTH-1:0]) && read_ptr[POINTER_WIDTH]!=write_ptr[POINTER_WIDTH];
    assign empty=(read_ptr==write_ptr);     
    //assign dout=(rd_en&& !empty)?buffer[read_ptr[POINTER_WIDTH-1:0]]:0;
    assign dout=dout1;       
endmodule
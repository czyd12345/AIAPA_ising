`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/29 11:38:00
// Design Name: 
// Module Name: readout_router
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


module readout_router #(
    parameter ROW=1,
    parameter COL=1
)(
    input clk,
    input rst,
  //  input [6:0] num,
    input [31:0] rdout_L,//0:spin;1:psum
    input [31:0] rdout_R,
    input [31:0] local,
    input [31:0] res_L,
    input [31:0] res_R,
    input response_in,
    output [31:0] dout,
    output [2:0] response
);
wire [2:0] s0;
wire [31:0] din,dout1;
wire i1,i2,i3,full,empty,rd_en,a,v,wr_en;
reg empty_r;
always @(posedge clk)
begin
    if(rst) empty_r<=0;
    else empty_r<=empty;
end
wire [1:0] y;
fifo #(32,2) fifo1(
    .clk(clk),
    .rst(rst),
    .wr_en(wr_en),
    .full(full),
    .rd_en(rd_en),
    .empty(empty),
    .din(din),
    .dout(dout1)
);

MuxKeyWithDefault #(5,3,32) mux1(din,s0,32'b0,{
    3'd0,rdout_L,
    3'd1,rdout_R,
    3'd2,local,
    3'd3,res_L,
    3'd4,res_R
});
reg [2:0] route_table[0:64];
assign y={i1,~i1&&i2};
assign response[0]=(y==2'b00)?v && !full:0;
assign response[1]=(y==2'b01)?v && !full:0;
assign response[2]=(y==2'b10)?v && !full:0;
assign i1=(local[31:29]!=3'd5);
assign i2=(rdout_L[31:29]!=3'd5);
assign i3=(rdout_R[31:29]!=3'd5);
assign v=i1||i2||i3;
assign s0=v?y:5;//
assign flipspin=(dout1[31:29]==3'd6);
assign rd_en=~empty && a;
assign a=!flipspin || (flipspin && response_in);
//assign wr_en=!(din[31:29]==3'd5 && route_table[i]==2);
assign wr_en=din[31:29]!=0;
integer i;
assign dout=empty_r?0:dout1;
/*always @(num)
begin
    if(ROW==0) 
    begin
        for(i=1;i<=64;i=i+1) 
            route_table[i]=2;
    end
    else if(ROW==1)
    begin
        if(COL==0) 
        begin
            if(num==3) route_table[num]=4;
        end
        if(COL==1) 
        begin
            if(num==6||num==3) route_table[num]=3;
            if(num==7) route_table[num]=4;
        end
        if(COL==2) 
        begin
            if(num==10) route_table[num]=3;
            if(num==11||num==6||num==3) route_table[num]=4;
        end
        if(COL==3) 
        begin
            if(num==14) route_table[num]=3;
            if(num==15||num==7||num==3) route_table[num]=4;
        end
        if(COL==4) 
        begin
            if(num==18) route_table[num]=3;
            if(num==19||num==8||num==3) route_table[num]=4;
        end
        if(COL==5) 
        begin
            if(num==22) route_table[num]=3;
            if(num==23||num==9||num==3) route_table[num]=4;
        end
        if(COL==6) 
        begin
            if(num==26) route_table[num]=3;
            if(num==27||num==9||num==3) route_table[num]=4;
        end
        if(COL==7) 
        begin
            if(num==30) route_table[num]=3;
            if(num==31||num==9||num==3) route_table[num]=4;
        end
        if(COL==8) 
        begin
            if(num==34) route_table[num]=3;
            if(num==35||num==9||num==3) route_table[num]=4;
        end
        if(COL==9) 
        begin
            if(num==38) route_table[num]=3;
            if(num==39||num==9||num==3) route_table[num]=4;
        end
        if(COL==10) 
        begin
            if(num==42) route_table[num]=3;
            if(num==43||num==9||num==3) route_table[num]=4;
        end
        if(COL==11) 
        begin
            if(num==46) route_table[num]=3;
            if(num==47||num==9||num==3) route_table[num]=4;
        end
        if(COL==12) 
        begin
            if(num==50) route_table[num]=3;
            if(num==51||num==9||num==3) route_table[num]=4;
        end
        if(COL==13) 
        begin
            if(num==54) route_table[num]=3;
            if(num==55||num==9||num==3) route_table[num]=4;
        end
        if(COL==14) 
        begin
            if(num==58) route_table[num]=3;
            if(num==59||num==9||num==3) route_table[num]=4;
        end
        if(COL==15) 
        begin
            if(num==62) route_table[num]=3;
            //if(num==59||num==9||num==3) route_table[num]=4;
        end
    end
end*/
endmodule
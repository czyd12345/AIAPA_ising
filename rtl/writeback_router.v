`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/08/01 11:24:17
// Design Name: 
// Module Name: writeback_router
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
module writeback_router#(
    parameter integer ROW = 0,
    parameter integer COL = 0
)(
    input clk,
    input rst,
    input [31:0] local,       // this SPU's result: {type(3), 6'b0, addr(6), psum(16)}
    input [31:0] neighbor,    // from the level below, parallel mode: {type(3), 5'b0, num(7), spin+index(17)}
    output reg [31:0] local_out,
    output reg [31:0] left_out,
    output reg [31:0] right_out
);
    wire [2:0]  type_loc = local[31:29];
    wire [2:0]  type_nei = neighbor[31:29];
    wire [6:0] addr_loc = local[21:16];
    wire [6:0] addr_nei = neighbor[21:16];

    wire [15:0] psum_loc = local[15:0];
    wire [15:0] psum_nei = neighbor[15:0];

    wire [6:0] num = neighbor[23:17];
    wire spin_bit = neighbor[0];          // sigma in {0,1}; interpreted as {-1,+1} one level up
    wire [15:0] idx_nei = neighbor[16:1];
    reg [5:0] addr=0;
    wire [1:0] s0;
    reg [1:0] route_dir_psum=0;
    wire [4:0] tar_col;
    wire [2:0] tar_row;
    wire zero;
    reg [5:0] s,t;
    always @(*)
    begin
        if ((ROW==tar_row) && (COL==tar_col))           route_dir_psum = 2'b00;         // -> local
        else if (tar_col>>(3-tar_row)==0) route_dir_psum = 2'b01;         // left half
        else if (tar_col>>(3-tar_row)==1) route_dir_psum = 2'b10;         // right half
    end
    always @(posedge clk) begin
    if(rst) begin
        addr<=0;
        local_out<=0;
    end
    else begin
        if (s0==1) begin
            addr<=addr_loc;
            case (route_dir_psum)
                2'b00: local_out <= local;   // 2'b00: consume locally
                2'b01: left_out  <= local;   // 2'b01: send to the left subtree
                2'b10: right_out <= local;   // 2'b10: send to the right subtree
                default: ;                  // default: not in this subtree, drop
            endcase
        end
        if(s0==2) begin
            addr<=addr_nei;
            case (route_dir_psum)
                2'b00: local_out <= neighbor;   // 2'b00: consume locally
                2'b01: left_out  <= neighbor;   // 2'b01: send to the left subtree
                2'b10: right_out <= neighbor;   // 2'b10: send to the right subtree
                default: ;                  // default: not in this subtree, drop
            endcase
        end
        if(s0==0) begin
            addr<=0;
            local_out<=(zero&&type_nei==3'd4)?32'b0:neighbor;
            left_out<=neighbor;
            right_out<=neighbor;
        end
    end
end
assign s0={local[31:29]==3'd3,neighbor[31:29]==3'd3};//10,01,00
reg [5:0] sigma1,sigma2;
reg ins;
integer v=-1,i,j=0;
reg rem[0:62];
always @(num)
begin
        s=64/num;
        t=64+s-s*num;
        for(i=0;i<=31;i=i+1) 
        begin
            v=v+2;
            if(v==num+1) begin
                v=2;
                ins=1;
                j=j+1;
            end
            else if(v==num) begin
                v=1;
                ins=1;
                j=j+1;
            end 
            else ins=0;
            if(i==COL && ROW==0) begin
                sigma1=v-1;
                sigma2=v;
            end
            if(j==s) rem[COL+1<<(5-ROW)]=1;
            else rem[COL+1<<(5-ROW)]=0;
            if(ins && ROW>0)
            begin
                if(COL<<ROW+1<<(ROW-1)==i) sigma1=(v==2)?0:num-1;// (row,col) is where a single sigma is inserted between two subtrees
                sigma2=0;
            end
        end
end
reg [5:0] count;
always @(posedge clk)
begin
    if(rst||count==num) count<=0;
    else if(type_nei==3'd3) count<=count+1;
end
assign zero=~(sigma1==count || sigma2==count&&ROW==0 ||(count-sigma2)%t==0 &&rem[COL+1<<(5-ROW)] && ROW==0 || (count-sigma1)%t==0 &&rem[COL+1<<(5-ROW)]);
ri_coord_rom_case #(64,3,5) route_table(addr,tar_row,tar_col);
// TODO: implement the zero decision based on the spin count
endmodule
module ri_coord_rom_case #(
    parameter integer R         = 64,  // number of r_i entries
    parameter integer LEVEL_W   = 3,   // level width (supports 0..7)
    parameter integer INDEX_W   = 5    // index width (supports 0..31)
)(
    input  wire [$clog2(R)-1:0] r_idx,        // 0-based：r1→0, r2→1, ...
    output reg  [LEVEL_W-1:0]   level,
    output reg  [INDEX_W-1:0]   index
);

    // pack into a single ID (level and index could also be driven out separately)

    always @(*) begin
    case (r_idx)
        // level 0: 0-31 (r0 to r31)
        0  : begin level = 3'd0; index = 5'd0;   end
        1  : begin level = 3'd0; index = 5'd1;   end
        2  : begin level = 3'd0; index = 5'd2;   end
        3  : begin level = 3'd0; index = 5'd3;   end
        4  : begin level = 3'd0; index = 5'd4;   end
        5  : begin level = 3'd0; index = 5'd5;   end
        6  : begin level = 3'd0; index = 5'd6;   end
        7  : begin level = 3'd0; index = 5'd7;   end
        8  : begin level = 3'd0; index = 5'd8;   end
        9  : begin level = 3'd0; index = 5'd9;   end
        10 : begin level = 3'd0; index = 5'd10;  end
        11 : begin level = 3'd0; index = 5'd11;  end
        12 : begin level = 3'd0; index = 5'd12;  end
        13 : begin level = 3'd0; index = 5'd13;  end
        14 : begin level = 3'd0; index = 5'd14;  end
        15 : begin level = 3'd0; index = 5'd15;  end
        16 : begin level = 3'd0; index = 5'd16;  end
        17 : begin level = 3'd0; index = 5'd17;  end
        18 : begin level = 3'd0; index = 5'd18;  end
        19 : begin level = 3'd0; index = 5'd19;  end
        20 : begin level = 3'd0; index = 5'd20;  end
        21 : begin level = 3'd0; index = 5'd21;  end
        22 : begin level = 3'd0; index = 5'd22;  end
        23 : begin level = 3'd0; index = 5'd23;  end
        24 : begin level = 3'd0; index = 5'd24;  end
        25 : begin level = 3'd0; index = 5'd25;  end
        26 : begin level = 3'd0; index = 5'd26;  end
        27 : begin level = 3'd0; index = 5'd27;  end
        28 : begin level = 3'd0; index = 5'd28;  end
        29 : begin level = 3'd0; index = 5'd29;  end
        30 : begin level = 3'd0; index = 5'd30;  end
        31 : begin level = 3'd0; index = 5'd31;  end

        // level 1: 32-47 (r32 to r47)
        32 : begin level = 3'd1; index = 5'd0;   end
        33 : begin level = 3'd1; index = 5'd1;   end
        34 : begin level = 3'd1; index = 5'd2;   end
        35 : begin level = 3'd1; index = 5'd3;   end
        36 : begin level = 3'd1; index = 5'd4;   end
        37 : begin level = 3'd1; index = 5'd5;   end
        38 : begin level = 3'd1; index = 5'd6;   end
        39 : begin level = 3'd1; index = 5'd7;   end
        40 : begin level = 3'd1; index = 5'd8;   end
        41 : begin level = 3'd1; index = 5'd9;   end
        42 : begin level = 3'd1; index = 5'd10;  end
        43 : begin level = 3'd1; index = 5'd11;  end
        44 : begin level = 3'd1; index = 5'd12;  end
        45 : begin level = 3'd1; index = 5'd13;  end
        46 : begin level = 3'd1; index = 5'd14;  end
        47 : begin level = 3'd1; index = 5'd15;  end

        // level 2: 48-55 (r48 to r55)
        48 : begin level = 3'd2; index = 5'd0;   end
        49 : begin level = 3'd2; index = 5'd1;   end
        50 : begin level = 3'd2; index = 5'd2;   end
        51 : begin level = 3'd2; index = 5'd3;   end
        52 : begin level = 3'd2; index = 5'd4;   end
        53 : begin level = 3'd2; index = 5'd5;   end
        54 : begin level = 3'd2; index = 5'd6;   end
        55 : begin level = 3'd2; index = 5'd7;   end

        // level 3: 56-59 (r56 to r59)
        56 : begin level = 3'd3; index = 5'd0;   end
        57 : begin level = 3'd3; index = 5'd1;   end
        58 : begin level = 3'd3; index = 5'd2;   end
        59 : begin level = 3'd3; index = 5'd3;   end

        // level 4: 60-61 (r60 to r61)
        60 : begin level = 3'd4; index = 5'd0;   end
        61 : begin level = 3'd4; index = 5'd1;   end

        // level 5: 62 (r62)
        62 : begin level = 3'd5; index = 5'd0;   end

        default: ; // keep the default (illegal) value
    endcase
end


endmodule
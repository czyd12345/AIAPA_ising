`timescale 1ns / 1ps
module spu #(
    parameter ROW=0,
    parameter COL=0
)(
    input clk,
    input rst,
    input [31:0] datain_pkt,
    input [31:0] left_res,
    input [31:0] right_res,
    input [31:0] left_rdout,
    input [31:0] right_rdout,
    input [3:0] j_left,
   // input [3:0] j_right,
    input response,
    input finish_send,
    output [31:0] local_res,
    output [31:0] next_rdout,
    output rd_en_j,
    output reg valid,
    output reg [31:0] fsn
    );
    
    reg [15:0] pk,ck,t,psum;
    reg [15:0] lf_temp_r [0:1024];
    reg [15:0] lf_temp_l [0:1024];
    wire [15:0] fi,w,ina,inb;
    wire [15:0] ina2,inb2,result;
    reg sigmaf,sigmaf_lf;//shift register
    wire sigmai,sigma_new;
    reg sigmai_lf,sigmai_sp;
    wire [15:0] addr;
    wire [6:0] opcode;
    wire [2:0] data_type;
    assign data_type=datain_pkt[31:29];
    assign opcode=datain_pkt[28:23];
    assign addr=(data_type==3'd1)?datain_pkt[15:0]:0;
    reg tci1,tci2;
    reg switch=0;
    reg [15:0] w_mem [0:1024];
    reg [15:0] lf_mem_l [0:1024];//1024+64
    reg [15:0] lf_mem_r [0:1024];
    reg [0:0] spin_l [0:1024];
    reg [0:0] spin_r [0:1024];
    wire [1023:0] ila_signal;
    genvar  l;
    generate 
        for(l=1;l<=1024;l=l+1) 
        begin
            assign ila_signal[l-1]=spin_l[l];
        end
    endgenerate
    ila_0 ila(
        .clk(clk),
        .probe0(ila_signal)
    );
    integer i;
    initial begin
        for(i=0;i<=1024;i=i+1) begin
            lf_mem_l[i]=0;
            lf_mem_r[i]=0;
        end
        for(i=0;i<=1024;i=i+1) begin
            lf_temp_l[i]=0;
            lf_temp_r[i]=0;
        end
        $readmemh("F:/SDR/Wi.txt",w_mem);
        $readmemb("F:/SDR/spinsl.txt",spin_l);
        $readmemb("F:/SDR/spinsr.txt",spin_r);
    end
    reg [15:0] addr_src,addr_lf,addr_sp,psum_lf,fi_lf,fi_sp,result_lf,spinindex,fi_temp_lf;
    reg [6:0] opcode_src,opcode_lf,opcode_sp,num;
    reg [2:0] data_type_lf,data_type_src,data_type_sp;
    wire [2:0] lut1,lut2;
    reg [2:0] s1,s2;
    wire [15:0] res,mask,res2,fi_temp;
    //reg [15:0] fi_op_lf;
    wire rd_en;
    
    reg ctrl_firststep,ctrl_firststep_lf,ctrl_lr,ctrl_lr_lf,ctrl_lr_sp,ctrl_up,ctrl_up_lf,ctrl_up_sp,empty_r;
    reg sigmai_op_lf;
    parameter SET_T=6'b000100;
    parameter SET_CK=6'b000101;
    parameter SET_PK=6'b000110;
    always @(posedge clk) begin
        if(rst) begin
            ctrl_lr<=0;
             ctrl_up<=0;
             psum<=0;
             ctrl_firststep<=0;
              tci1<=0;
            tci2<=0;
             sigmaf<=0;
            pk<=0;
            ck<=0;
            t<=0;
        end else begin
        ctrl_lr<=0;
        ctrl_firststep<=0;
        ctrl_up<=0;
        psum<=0;
        if(data_type==3'd3) 
            psum<=datain_pkt[15:0];
        else if(data_type==3'd4) 
        begin
            spinindex<=datain_pkt[16:1];
            if(switch&&ROW==0) tci2<=datain_pkt[0];
            else tci1<=datain_pkt[0];
            num<=datain_pkt[23:17];
            switch<=~switch;
        end
        else if(data_type==3'd2)
        begin
            if(opcode==SET_T) t<=datain_pkt[15:0];
            if(opcode==SET_PK) pk<=datain_pkt[15:0];
            if(opcode==SET_CK) ck<=datain_pkt[15:0];
        end
        else if(data_type==3'd1)
        begin
            sigmaf<=datain_pkt[22];
            ctrl_firststep<=datain_pkt[21];
            ctrl_lr<=datain_pkt[19];
            ctrl_up<=datain_pkt[20];
        end
        end
    end
    always @(posedge clk)
    begin
        if(rst) begin
             addr_src<=0;
              opcode_src<=0;
            data_type_src<=0;
        end else begin
        opcode_src<=opcode;
        addr_src<=addr;
        data_type_src<=data_type;
        if(data_type_lf==3'd1 && opcode_lf==6'b000010) begin
            if(ctrl_lr_lf) lf_mem_r[addr_lf]<=res;
            else lf_mem_l[addr_lf]<=res;
        end
        if(data_type_lf==3'd1 && opcode_lf==6'b000001) begin
            if(ctrl_lr_lf) lf_temp_r[addr_lf]<=res;
            else lf_temp_l[addr_lf]<=res;
        end
        if(ctrl_up_sp) begin
            if(ctrl_lr_sp) spin_r[addr_sp]<=sigma_new;
            else spin_l[addr_sp]<=sigma_new;
        end
        end
    end
    wire sigmai_op;
    wire [15:0] fi_op;
    assign sigmai=ctrl_lr?spin_r[addr_src]:spin_l[addr_src];//
    //assign fi_op=ctrl_lr?lf_mem_l[addr_src]:lf_mem_r[addr_src];
    assign fi=ctrl_lr?lf_mem_r[addr_src]:lf_mem_l[addr_src];
    assign fi_temp=ctrl_lr?lf_temp_r[addr_src]:lf_temp_l[addr_src];
    assign sigmai_op=ctrl_lr?spin_l[addr_src]:spin_r[addr_src];
    always @(posedge clk)
    begin
         if(rst) begin
             addr_lf<=0;
              opcode_lf<=0;
            data_type_lf<=0;
            ctrl_up_lf<=0;
            ctrl_lr_lf<=0;
            result_lf<=0;
        sigmaf_lf<=0;
        sigmai_op_lf<=0;
        fi_temp_lf<=0;
        sigmai_lf<=0;
        fi_lf<=0;
        psum_lf<=0;
        ctrl_firststep_lf<=0;
        end else begin
        sigmai_lf<=sigmai;
        fi_lf<=fi;
        psum_lf<=psum;
        ctrl_up_lf<=ctrl_up;
        ctrl_lr_lf<=ctrl_lr;
        addr_lf<=addr_src;
        ctrl_firststep_lf<=ctrl_firststep;
        opcode_lf<=opcode_src;
        data_type_lf<=data_type_src;
        result_lf<=result;
        sigmaf_lf<=sigmaf;
        sigmai_op_lf<=sigmai_op;
        fi_temp_lf<=fi_temp;
    end
    end
always @(*)
begin
    if(data_type_lf==3'd1) begin
        if(opcode_lf==6'b000001) s1=6;
        if(opcode_lf==6'b000010) s1=1;
        if(opcode_lf==6'b000011) s1=5;
    end
    else if(data_type==3'd4) s1=0;
    else s1=0;
    s2=(data_type_lf==3'd4)?0:5;
end
reg [15:0] j1,j2;
reg sign1,sign2;       // Sign bit
reg [4:0] exp1,exp2;  // Exponent (5 bits)
reg [9:0] frac1,frac2; // Fraction (10 bits)
wire sigma1,sigma2;
assign sigma1=(opcode_lf==6'b000001)?sigmai_op_lf:sigmaf_lf;
assign sigma2=0;
always @(*) begin
    sign1 = j_left[3];
    if (j_left == 0) begin
        exp1 = 5'b00000;
        frac1 = 10'b0000000000;
    end
    else if(j_left[2:0]==1) begin
        exp1 = ctrl_firststep_lf?5'b01111:5'b10000;
        frac1 = 10'b0000000000;
    end else begin
        exp1 = ctrl_firststep_lf?5'b01111:5'b10000; // Default exponent for normalized integers (bias of 15)
        frac1 = j_left[2:0]<< (10 - 3); // Align the integer in the 10-bit fraction field
    end
    j1 = {sign1, exp1, frac1}; 
    j2=0;
end
MuxKeyWithDefault #(5,3,16) mux1(ina2,s1,16'b0,{
    3'd1,j1,
    3'd2,left_res[15:0],
    3'd3,left_rdout[15:0],
    3'd5,psum_lf,
    3'd6,result_lf
});
MuxKeyWithDefault #(4,3,16) mux2(inb2,s2,16'b0,{
    3'd1,j2,
    3'd2,right_res[15:0],
    3'd3,right_rdout[15:0],
    3'd5,fi_lf
});
assign mask=(data_type==3'd4)?((s1==3'd2)?left_res[31:16]:left_rdout[31:16]):0;
assign local_res={mask,res};
//state update engine
wire wr_en,full,empty,flip;
always @(posedge clk)
begin
    if(rst) begin
        fi_sp<=0;
        sigmai_sp<=0;
        ctrl_lr_sp<=0;
    ctrl_up_sp<=0;
    data_type_sp<=0;
    addr_sp<=0;
    opcode_sp<=0;
    empty_r<=0;
    end else begin
    sigmai_sp<=sigmai_lf;
    if(opcode_lf==6'b1) fi_sp<=res;
    else if(opcode_lf==6'b10) fi_sp<=res2;
    else fi_sp<=0;
    ctrl_lr_sp<=ctrl_lr_lf;
    ctrl_up_sp<=ctrl_up_lf;
    data_type_sp<=data_type_lf;
    addr_sp<=addr_lf;
    opcode_sp<=opcode_lf;
    empty_r<=empty;
    end
end
wire [16:0] dout;

wire [15:0] delta_hi;
wire sign_d=sigmai_sp?(~fi_sp[15]):fi_sp[15];
wire [4:0] exp_d=(fi_sp[14:10]!=0)?(fi_sp[14:10]+1'b1):0;
assign delta_hi={sign_d,exp_d,fi_sp[9:0]};
wire a_lt_b = result[15]==0 && delta_hi <= result;
assign flip=(delta_hi[15]==1 |delta_hi==16'h0| a_lt_b) & ctrl_up_sp;
assign sigma_new=flip?~sigmai_sp:sigmai_sp;
assign wr_en=(sigma_new^sigmai_sp) && ctrl_up_sp;
assign rd_en=((dout!=0) && response) | dout==0;
fifo #(17,256) fifo2(
    .clk(clk),
    .rst(rst),
    .wr_en(wr_en),
    .full(full),
    .rd_en(rd_en),
    .empty(empty),
    .din({addr_sp,sigma_new}),
    .dout(dout)
);
reg finish_r;
reg [10:0] count;
assign next_rdout=finish_r?{3'd7,28'b0,spin_l[count]}:(((dout==0)|empty_r)?0:(ctrl_lr_sp?{3'd6,11'b0,dout[16:0],spin_l[addr_sp]}:{3'd6,11'b0,dout[16:1],spin_r[addr_sp],dout[0]}));
wire [15:0] r;
fp16_lfsr rand(
    .clk(clk),
    .rst(rst),
    .enable(opcode==6'b000001|ctrl_up),
    .random_fp16(r)
);
assign rd_en_j=(opcode_src==6'b000010);
assign w=(pk<r && opcode_src==6'b000001)?w_mem[addr_src]:0;
assign ina=(ctrl_up_sp&&opcode_sp==6'b000010)?r:w;
assign inb=(ctrl_up_sp&&opcode_sp==6'b000010)?t:ck;
floatMuilt mul(
  .floatA(ina),              // input wire [15 : 0] s_axis_a_tdata
  .floatB(inb),              // input wire [15 : 0] s_axis_b_tdata
  .product(result)    // output wire [15 : 0] m_axis_result_tdata
);
float_adder adder(sigma1?{~ina2[15],ina2[14:0]}:ina2,sigma2?{~inb2[15],inb2[14:0]}:inb2,res);
float_adder adder2(sigma1?{~ina2[15],ina2[14:0]}:ina2,fi_temp_lf,res2);
always @(posedge clk)
begin
    if(rst | data_type_sp==0) begin
        fsn<=0;
    end
    else begin
        if(flip) fsn<=fsn+1;
        else fsn<=fsn;
        if(data_type_lf==0 && opcode_sp==6'b000010) valid<=1;
        else valid<=0;
    end
end


always @(posedge clk) 
begin
    if(rst) begin
        count<=0;
        finish_r<=0;
    end 
    else if(finish_send) begin
        if(count==11'd799) finish_r<=0;
        else begin
            finish_r<=finish_send;
            count<=count+1;
        end
    end
end
endmodule
module fp16_lfsr (
    input  wire clk,
    input  wire rst,
    input  wire enable,
    output reg [15:0] random_fp16
);

    // LFSR寄存器
    reg [15:0] lfsr_reg;
    wire lfsr_feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];

    // 固定正数 [0,1)
    wire sign_bit = 1'b0;

    // mantissa 随机
    wire [9:0] frac_bits = lfsr_reg[9:0];

    // 使用高5位来控制指数（log2 映射，几何分布）
    reg [4:0] exp_bits;
    always @(*) begin
        if (lfsr_reg[14:10] == 0)
            exp_bits = 5'd1;    // 避免全零指数（subnormal），最低设为 1
        else if (lfsr_reg[14:10] > 5'd14)
            exp_bits = 5'd14;   // 上限14，对应最大<1的数
        else
            exp_bits = lfsr_reg[14:10];
    end

    wire [15:0] final_fp16 = {sign_bit, exp_bits, frac_bits};

    always @(posedge clk) begin
        if (rst) begin
            lfsr_reg     <= 16'hACE1; // 初始种子
            random_fp16  <= 16'h0000;
        end else if (enable) begin
            // 更新 LFSR
            lfsr_reg <= {lfsr_reg[14:0], lfsr_feedback};

            // 生成 FP16 随机数
            random_fp16 <= final_fp16;
        end
    end

endmodule

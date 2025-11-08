`timescale 1ns / 1ps
module top_control #(
    parameter E=63,
    parameter L=6,
    parameter P=64
)(
    input clk,
    input rst,
    input ap_start,
    input [31:0] datain_pkt,//可能再加
    input [31:0] in_n,
    input [31:0] in_k,
    input [15:0] in_p,
    input [15:0] in_c,
    input [15:0] in_temp,
    input [15:0] in_alpha,
    input [31:0] fsn,
    input valid,
    output [31:0] data_pkt,
    output reg mem_r,
    output [31:0] mem_addr, //off-chip地址
    output rd_en_out,
    output reg finish_send,
    output serial_out
);
  //  parameter E = 63,L=6,P=64;
    parameter SET_T=6'b000100;
    parameter SET_CK=6'b000101;
    parameter SET_PK=6'b000110;
    reg [31:0] rem=0,fp=0;
    reg [2:0] data_type;
    wire [28:0] inst;
    reg [15:0] pk,ck,t,para;
    reg [15:0] alpha,coeff;
    wire [15:0] result;//衰减系数
    reg [2:0] state;
    reg [31:0] N,K,F,Fl,Fr,Fl_last,Fr_last,F_new; //参数（输入），自旋数量
    reg [15:0] addr;  //onchip地址
    reg [15:0] spinindex_l [0:1024];
    reg [15:0] spinindex_r [0:1024];
    reg [0:0] spinstate_l [0:1024];
    reg [0:0] spinstate_r [0:1024];
    reg ctrl_firststep=0,ctrl_flipspin=0,ctrl_lr=0,ctrl_up=0,flag;
    wire fifo_empty,fifo_full;
    integer i,k,c,f,m;
    reg rd_en;
    wire wr_en;
    wire [17:0] dout;
    wire [17:0] din;
    reg [2:0] next_state; 
    reg [5:0] opcode; 
    reg [31:0] C;
    reg [3:0] bit_counter;
    reg tx_wr_en;
    reg [7:0] tx_din;
    //reg result_tvalid_r=0;
    initial begin
        $readmemb("F:/SDR/spinsl.txt",spinstate_l);
        $readmemb("F:/SDR/spinsr.txt",spinstate_r);
        for(i=0;i<=1024;i=i+1) begin
            spinindex_l[i]=i[15:0];
            spinindex_r[i]=i[15:0];
        end
    end
    always @(posedge clk)
    begin
        if(rst) begin
        state          <= 3'd1;
        rd_en          <= 1'b0;
        opcode         <= 6'd0;
        data_type      <= 3'd0;
        ctrl_firststep <= 1'b0;
        ctrl_flipspin  <= 1'b0;
        ctrl_up        <= 1'b0;
        addr           <= 16'd0;
        i <= 0; k <= 0; c <= 0; f <= 0; m <= 0;
        F <= 0; C <= 0; fp <= 0; rem <= 0;
        K <= 0; N <= 0;
        pk <= 0; ck <= 0; t <= 0;
        alpha <= 0; 
        Fl_last<=0;
        Fr_last<=0;
        Fl<=0;
        Fr<=0;
        flag<=0;
        finish_send<=0;
        bit_counter<=0;
        tx_din<=0;
        tx_wr_en<=0;
        end else begin
        data_type      <= 3'd0;
        ctrl_firststep <= 1'b0;
        ctrl_flipspin  <= 1'b0;
        ctrl_up        <= 1'b0;        
        state <= state; // 默认保持
        m     <= m;
        i     <= i; k <= k; c <= c; f <= f; 
        F     <= F; C <= C; fp <= fp; rem <= rem;
        opcode<= opcode;
        addr  <= addr;
        rd_en<=rd_en;
        mem_r<=0;
        case(state)
            3'd1: begin
                K<=in_k;
                N<=in_n;
                Fl<=in_n;
                Fr<=in_n;
                pk<=in_p;
                ck<=in_c;
                t<=in_temp;
                alpha<=in_alpha;
                if(ap_start && !finish_send) 
                begin
                    state<=3'd2;
                    k<=1;
                    m<=0; 
                end
                if(finish_send && (datain_pkt[31:29]==3'd7)) 
                begin
                    bit_counter<=bit_counter+1;
                    tx_din<={datain_pkt[0],tx_din[7:1]};
                    if(bit_counter==7) begin
                        tx_wr_en<=1;
                        bit_counter<=0;
                    end
                    else tx_wr_en<=0;
                end    
            end
            3'd2: begin
        // 三个参数逐个发送
        case (m)
          0: begin
            para   <= t;
            coeff  <= alpha;
            opcode <= SET_T;
            data_type  <= 3'd2;
            m          <= 1;
            end

          1: begin
            t<=result;
            para   <= pk;
            coeff  <= 16'h9019;
            opcode <= SET_PK;
            data_type  <= 3'd2;
              m          <= 2;
              
            end

          2: begin
            pk<=result;
            para   <= ck;
            coeff  <= 16'h1419;
            opcode <= SET_CK;
              data_type  <= 3'd2;
              m          <= 3;
            end
          3: begin 
                ck<=result;
                state <= 3'd3;
                i<=1;
                Fl_last<=Fl;
                Fr_last<=Fr;
          end
        endcase
        end                
            3'd3: 
            begin  //退火
                F<=ctrl_lr?Fl:Fr;
                if(i>N/E) 
                begin
                    data_type<=0;
                    if(F==0) 
                    begin //确保当前的数据全部读取到存储单元中 
                        i<=1;
                        m<=0;
                        if(ctrl_lr) 
                        begin
                            rd_en<=1;
                            if(fifo_empty) begin
                                k<=k+1;
                                state<=3'd2;
                                rd_en <= 1'b0;
                                ctrl_lr<=~ctrl_lr;
                            end
                        end
                        else begin
                            state<=3'd3;
                        end
                    end
                    else begin
                        f<=1;
                        if(N<E && F>L) state<=3'd5;
                        else begin 
                            state<=3'd4;
                            c<=1;
                            rem<=F%P;
                            fp<=F/P;
                            C<=(F>L)?N/E:N/E+1;
                        end
                    end
                end
                else begin
                    addr<=i;
                    i<=i+1;
                    ctrl_firststep<=(k==1);
                    ctrl_up<=(Fl==0&&ctrl_lr|Fr==0 && ~ctrl_lr);
                    opcode<=6'b000001;//f+Msigma
                    data_type<=1;
                end
            end
            3'd4: begin //计算
                if(f>F && valid) begin
                    if(N%E!=0 && F>L)
                    begin
                        state<=3'd5;
                        f<=1;
                    end 
                    else begin
                        if(k==K) begin
                            state<=3'd1;
                            finish_send<=1;
                        end
                        else begin
                            i<=1;m<=0;
                            if(ctrl_lr) begin
                                rd_en<=1;
                                flag<=1;
                                if(flag==0) Fr<=fsn;
                                if(fifo_empty) begin
                                    k<=k+1;
                                    state<=3'd2;
                                    rd_en <= 1'b0;
                                    ctrl_lr<=~ctrl_lr;
                                    f<=1;
                                    c<=1;
                                    flag<=0;
                                end
                            end
                            else begin
                                ctrl_lr<=~ctrl_lr;
                                state<=3'd3;
                                f<=1;
                                c<=1;
                                Fl<=fsn;
                            end
                        end
                    end
                end
                else if(f<=F) begin
                    mem_r<=1;
                    if(c==C) begin
                        f<=f+1;
                        c<=1;
                    end
                    else c<=c+1;
                    ctrl_firststep<=(k==1);
                    ctrl_up<=(f==F);
                    addr<=c;
                    ctrl_flipspin<=ctrl_lr?spinstate_l[f]:spinstate_r[f];
                    opcode<=6'b000010;//f+jsigma
                    data_type<=1;
                end
            end

/*            3'd5: begin //平行模式的计算 
                if(f>F) state<=3'd6;
                else begin 
                    f<=f+1;
                    data_type<=3'd4;
                end
            end
            3'd6:begin 
                addr<=C;
                opcode<=6'b000011;//f+psum
                data_type<=1;
                if(k==K) state<=3'd1;
                else begin 
                    rd_en<=1'b1;
                    if(fifo_empty) 
                    begin
                        ctrl_lr<=~ctrl_lr;
                        state<=ctrl_lr?3'd2:3'd3;
                        i<=1;
                        rd_en <= 1'b0;
                        if(ctrl_lr) k<=k+1;
                        m<=0;
                        f<=1;
                        c<=1;
                    end
                end //清空网络中的数据
            */
            default:state<=3'b1;
            endcase
        end

    end
    assign mem_addr={ctrl_lr?spinindex_l[f]:spinindex_r[f],addr};
    assign inst=(data_type==1)?{opcode,ctrl_flipspin,ctrl_firststep,ctrl_up,ctrl_lr,3'b000,addr}:{opcode,7'b0,result};
    wire [31:0] num=(f>fp*P)?P:rem;
    MuxKeyWithDefault #(3,3,32) mux0(data_pkt,data_type,32'b0,{
        3'd1,{3'b001,inst},
        3'd2,{3'b010,inst}, //para
        3'd4,{3'b100,5'b0,num[6:0],spinindex_l[f],ctrl_lr?spinstate_l[f]:spinstate_r[f]} //通过零选择块送到对应的位置，需要就接受，否则置零
    });//32=7+18+3+4=3+16+13

    fifo  #(18,2048) dataflow(
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .full(fifo_full),
        .rd_en(rd_en),
        .empty(fifo_empty),
        .din(din),
        .dout(dout)
    );
wire [15:0] result1,result2;
floatMuilt i0(para,coeff,result1);
float_adder i1(para,coeff,result2);
assign result=(m==1)?result1:result2;
assign rd_en_out=!fifo_full || finish_send;
integer v;
wire [15:0] index;
assign index=dout[17:2];
always @(posedge clk)
begin
    if(rst || state==3'd2) F_new<=0;
    if(rd_en) 
    begin
        if(F_new<=Fl) begin
            spinstate_l[F_new]<=dout[0];
            spinindex_l[F_new]<=index;
        end
        else begin
            spinstate_r[F_new-Fl]<=dout[1];
            spinindex_r[F_new-Fl]<=index;
        end
        F_new<=F_new+1;
    end
end
assign wr_en=datain_pkt[31:29]!=0;
assign din=datain_pkt[17:0];
wire [7:0] data_in;
wire data_in_ready,data_in_valid,tx_fifo_full,tx_fifo_empty;
reg tx_fifo_empty_delayed;
always @(posedge clk)
begin
    tx_fifo_empty_delayed<=tx_fifo_empty;
end
assign data_in_valid=~tx_fifo_empty_delayed;
uart uart0(
    .clk(clk),
    .reset(rst),
    .data_in(data_in),
    .data_in_valid(data_in_valid),
    .data_in_ready(data_in_ready),
    .serial_out(serial_out)
);
fifo #(.WIDTH(8), .DEPTH(128)) 
    tx_fifo (
        .clk(clk), 
        .rst(rst),
        .wr_en(tx_wr_en),
        .din(tx_din),
        .full(tx_fifo_full),
        .rd_en(data_in_ready && ~tx_fifo_empty),
        .dout(data_in),
        .empty(tx_fifo_empty)
    );
endmodule


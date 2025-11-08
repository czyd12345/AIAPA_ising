`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/08/25 11:56:38
// Design Name: 
// Module Name: tb_top_control
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
`timescale 1ns/1ns

module tb_top_control;
  wire serial_out;

  reg clk = 0;
  reg rst = 1;
  always #5 clk = ~clk;  // 100 MHz


  reg ap_start;
    integer i,j,j1=0;
  integer h=0;
  reg sign=0;
  aiapa_top  dut(
    .clk       (clk),
    .rst       (rst),
    .ap_start  (ap_start),
    .serial_out(serial_out)
  );
  initial begin
    #1;
    ap_start = 1'b1;
    wait(dut.top_controller.state==3'd2) 
    repeat(10) @(posedge clk)
    wait(dut.top_controller.state==3'd1) 
    $display("Annealing FINISH!");
    $finish(0);
  end

  initial begin
    $dumpfile("tb_top_control.fst");
    $dumpvars(0, tb_top_control);
    // 初始�?????????

    // 复位 10ns
    #1;
    rst = 1;
    repeat(2) @(posedge clk);
    rst = 0;
    $display("[%0t] Release reset", $time);
  
  repeat(400) 
  begin
    wait(dut.top_controller.state==3'd2 && dut.top_controller.m==3);
      h=0;
      for(i=1;i<=800;i=i+1)
      begin
        for(j=1;j<i;j=j+1) 
          begin
            j1=dut.mem_j[i-1][(j-1)*4+:3];
            sign=dut.mem_j[i-1][(j-1)*4+3];
            //$display("%d",j1);
            if(dut.spu1.spin_l[i]==dut.spu1.spin_l[j]) h=sign?h+j1:h-j1;
            else h=sign?h-j1:h+j1;
          end
        end
      $display("%d %d",dut.top_controller.k,h);  
      repeat(2) @(posedge clk);
  end
    
  end

endmodule


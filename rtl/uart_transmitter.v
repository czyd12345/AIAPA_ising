module uart_transmitter #(
    parameter CLOCK_FREQ = 125_000_000,
    parameter BAUD_RATE = 115_200)
(
    input clk,
    input reset,

    input [7:0] data_in,
    input data_in_valid,
    output data_in_ready,

    output serial_out
);
    // See diagram in the lab guide
    localparam  SYMBOL_EDGE_TIME    =   CLOCK_FREQ / BAUD_RATE;
    localparam  CLOCK_COUNTER_WIDTH =   $clog2(SYMBOL_EDGE_TIME);
  wire send_byte;
  wire [9:0] tx_shift_value;
  wire [9:0] tx_shift_next;
  wire tx_shift_ce;
  wire data_in_fire;
  reg data_in_fire_r=0;
  // MSB to LSB
      REGISTER_CE #(.N(10)) tx_shift (
        .q(tx_shift_value),
        .d(tx_shift_next),
        .ce(tx_shift_ce),
        .clk(clk)
    );
  assign tx_shift_next = data_in_fire_r ?
                           {1'b1, data_in, 1'b0} :   // stop + data + start
                           {1'b1, tx_shift_value[9:1]};
  assign tx_shift_ce   = data_in_fire_r | (send_byte & symbol_edge);
  wire [3:0] bit_counter_value;
  wire [3:0] bit_counter_next;
  wire bit_counter_ce, bit_counter_rst;
always @(posedge clk)
begin
  data_in_fire_r<=data_in_fire;
end
  REGISTER_R_CE #(.N(4), .INIT(0)) bit_counter (
    .q(bit_counter_value),
    .d(bit_counter_next),
    .ce(bit_counter_ce),
    .rst(bit_counter_rst),
    .clk(clk)
  );

  wire [CLOCK_COUNTER_WIDTH-1:0] clock_counter_value;
  wire [CLOCK_COUNTER_WIDTH-1:0] clock_counter_next;
  wire clock_counter_ce, clock_counter_rst;

  // Keep track of sample time and symbol edge time
  REGISTER_R_CE #(.N(CLOCK_COUNTER_WIDTH), .INIT(0)) clock_counter (
    .q(clock_counter_value),
    .d(clock_counter_next),
    .ce(clock_counter_ce),
    .rst(clock_counter_rst),
    .clk(clk)
  );

  assign data_in_fire = data_in_valid & data_in_ready;

  wire symbol_edge = (clock_counter_value == SYMBOL_EDGE_TIME - 1);
  wire done        = (bit_counter_value == 10);
  // 'has_byte' becomes HIGH once we finish sampling all 10 bits
  // ({stop_bit, char[7:0], start_bit}) from the serial interface

  REGISTER_R_CE #(.N(1), .INIT(0)) has_byte_reg (
    .q(send_byte),
    .d(1'b1),
    .ce(data_in_fire),
    .rst(done|reset),
    .clk(clk)
  );

  assign serial_out= send_byte?tx_shift_value[0]:1;
  assign bit_counter_next = bit_counter_value + 1;
  assign bit_counter_ce   = symbol_edge;
  assign bit_counter_rst  = done | reset;

  assign clock_counter_next = clock_counter_value + 1;
  assign clock_counter_ce   = send_byte;
  assign clock_counter_rst  = done | reset | symbol_edge | data_in_fire ;

  //assign tx_shift_value[9:1]={1'b1,data_in};
  //assign tx_shift_value[0]=
  assign data_in_ready = ~send_byte;
endmodule

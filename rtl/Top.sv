
module Top (
    input  logic       MAX10_CLK1_50,
    input  logic       UART_RX,
    input  logic       KEY0,
    output logic [9:0] LEDR
);

  logic [7:0] rx_data;
  logic       rx_valid;

  // UART Receiver
  uart_rx #(
      .CLK_FREQ (50_000_000),
      .BAUD_RATE(115200)
  ) uart_inst (
      .clk       (MAX10_CLK1_50),
      .rst_n     (KEY0),
      .rx        (UART_RX),
      .data_out  (rx_data),
      .data_valid(rx_valid)
  );

  // Display received byte on LEDs
  always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
    if (!KEY0) LEDR <= 10'b0;
    else if (rx_valid) LEDR <= {2'b00, rx_data};
  end

endmodule


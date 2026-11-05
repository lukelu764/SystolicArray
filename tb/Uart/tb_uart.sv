`timescale 1ns/1ps
//============================================================================
// UART loopback self-check (exercises both uart_tx and uart_rx):
//   uart_tx.tx --> uart_rx.rx
// Sends several known bytes through the transmitter, wires the serial line
// into the receiver, and verifies each byte is recovered intact.
//
// Baud params are overridden small (CLKS_PER_BIT = 10) so the sim is fast;
// the UART logic is independent of the exact divisor value.
//============================================================================
module tb_uart;

  localparam int CLK_FREQ  = 1000;   // -> CLKS_PER_BIT = CLK_FREQ/BAUD_RATE
  localparam int BAUD_RATE = 100;    //    = 10 clocks per bit

  logic       clk = 0;
  logic       rst_n = 0;
  always #5 clk = ~clk;              // 100 MHz sim clock

  // TX side
  logic [7:0] tx_data;
  logic       tx_start;
  logic       tx_busy;
  logic       tx_done;
  logic       serial;                // the shared UART line

  // RX side
  logic [7:0] rx_data;
  logic       rx_valid;

  uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
      .clk      (clk),
      .rst_n    (rst_n),
      .tx_data  (tx_data),
      .tx_start (tx_start),
      .tx_busy  (tx_busy),
      .tx_done  (tx_done),
      .tx       (serial)
  );

  uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
      .clk        (clk),
      .rst_n      (rst_n),
      .rx         (serial),
      .data_out   (rx_data),
      .data_valid (rx_valid)
  );

  // Test vectors
  localparam int N_BYTES = 5;
  logic [7:0] vectors [N_BYTES] = '{8'hA5, 8'h3C, 8'h00, 8'hFF, 8'h5A};
  integer errors = 0;

  // Send one byte and wait until the transmitter is fully done.
  task automatic send_byte(input logic [7:0] b);
    @(negedge clk);
    tx_data  = b;
    tx_start = 1'b1;
    @(negedge clk);
    tx_start = 1'b0;
    // wait for transmission to complete
    wait (tx_done == 1'b1);
    @(negedge clk);
  endtask

  // Capture every received byte and compare against what we sent.
  logic [7:0] expected;
  initial begin
    string wavefile;
    if (!$value$plusargs("WAVE=%s", wavefile))
      wavefile = "tb/tb_uart.vcd";
    $dumpfile(wavefile);
    $dumpvars(0, tb_uart);

    tx_data  = '0;
    tx_start = 1'b0;

    // reset
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (int i = 0; i < N_BYTES; i++) begin
      expected = vectors[i];
      fork
        // Transmitter: drive the byte out.
        send_byte(expected);
        // Receiver watcher: wait for a recovered byte and check it.
        begin : check
          @(posedge rx_valid);
          @(negedge clk);   // let rx_data settle
          if (rx_data !== expected) begin
            $display("MISMATCH byte %0d: sent 0x%02h, got 0x%02h",
                     i, expected, rx_data);
            errors++;
          end else begin
            $display("OK       byte %0d: 0x%02h looped back correctly",
                     i, expected);
          end
        end
      join
    end

    if (errors == 0)
      $display("PASS: all %0d bytes looped back correctly!", N_BYTES);
    else
      $fatal(1, "FAIL: %0d byte(s) mismatched", errors);

    $finish;
  end

  // Global safety timeout so a broken DUT can't hang the sim forever.
  initial begin
    #2_000_000;
    $fatal(1, "TIMEOUT: testbench did not finish");
  end

endmodule

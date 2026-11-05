module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input logic clk,
    input logic rst_n,

    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx_done,

    output logic tx
);

  localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

  typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;

  state_t        state;
  logic   [15:0] counter;
  logic   [ 2:0] bit_index;
  logic   [ 7:0] data_latch;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= IDLE;
      tx         <= 1'b1;
      tx_busy    <= 1'b0;
      tx_done    <= 1'b0;
      counter    <= 0;
      bit_index  <= 0;
      data_latch <= 0;
    end else begin
      tx_done <= 1'b0;
      case (state)
        IDLE: begin
          if (tx_start) begin
            counter    <= 16'(CLKS_PER_BIT - 1);
            tx         <= 0;
            tx_busy    <= 1;
            data_latch <= tx_data;
            state      <= START;
          end
        end

        START: begin
          if (counter == 0) begin
            counter   <= 16'(CLKS_PER_BIT - 1);
            tx        <= data_latch[0];
            bit_index <= 0;
            state     <= DATA;
          end else counter <= counter - 1;
        end

        DATA: begin
          if (counter == 0) begin
            counter <= 16'(CLKS_PER_BIT - 1);
            if (bit_index == 7) begin
              tx    <= 1'b1;
              state <= STOP;
            end else begin
              tx        <= data_latch[bit_index+1];
              bit_index <= bit_index + 1;
            end
          end else counter <= counter - 1;
        end

        STOP: begin
          if (counter == 0) begin
            tx_done <= 1'b1;
            tx_busy <= 1'b0;
            state   <= IDLE;
          end else counter <= counter - 1;
        end

      endcase
    end
  end

endmodule

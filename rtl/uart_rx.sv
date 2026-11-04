module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] data_out,
    output logic       data_valid
);

  localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

  typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;

  state_t        state = IDLE;

  logic   [15:0] counter;
  logic   [ 2:0] bit_index;
  logic   [ 7:0] rx_data;

  // Simple Syncrhonzer
  logic rx_meta, rx_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
    end else begin
      rx_meta <= rx;
      rx_sync <= rx_meta;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= IDLE;
      counter    <= 0;
      bit_index  <= 0;
      rx_data    <= 0;
      data_out   <= 0;
      data_valid <= 0;
    end else begin
      data_valid <= 0;

      case (state)

        IDLE: begin
          if (!rx_sync) begin  // if pulled low
            counter <= 16'(CLKS_PER_BIT / 2 - 1);
            state   <= START;
          end
        end

        START: begin
          if (counter == 0) begin
            if (!rx_sync) begin
              counter   <= 16'(CLKS_PER_BIT - 1);
              bit_index <= 0;
              state     <= DATA;
            end else begin
              state <= IDLE;
            end
          end else counter <= counter - 1;
        end

        DATA: begin
          if (counter == 0) begin
            rx_data[bit_index] <= rx_sync;
            counter            <= 16'(CLKS_PER_BIT - 1);

            if (bit_index == 7) state <= STOP;
            else bit_index <= bit_index + 1;
          end else counter <= counter - 1;
        end

        STOP: begin
          if (counter == 0) begin
            if (rx_sync) begin
              data_out   <= rx_data;
              data_valid <= 1;
            end
            state <= IDLE;
          end else counter <= counter - 1;
        end


      endcase
    end
  end

endmodule


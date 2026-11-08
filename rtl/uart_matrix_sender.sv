// uart_matrix_sender
// ------------------
// Streams the computed C-matrix back out over UART, mirroring the way
// uart_matrix_loader brings A and B in.
//
// Protocol (host side / matrix_gen.py receiver):
//   byte 0        : rows (dim)
//   byte 1        : cols (dim)
//   bytes 2..     : C elements, row-major. Each ACC_W-bit signed element is
//                   sent as ACC_W/8 bytes, little-endian (LSB first) so it
//                   reconstructs directly as a host-native integer.
//
// A one-cycle `start` pulse (drive it from tiling's `done`) kicks off the
// transfer. `tx_data`/`tx_start`/`tx_busy`/`tx_done` wire straight to a
// uart_tx instance. `send_done` pulses for one cycle when the whole matrix
// has been shipped.

module uart_matrix_sender #(
    parameter MAX_DIM = 64,
    parameter ACC_W   = 32
) (
    input logic clk,
    input logic rst_n,

    // Kick off a transfer (one-cycle pulse, e.g. tiling.done).
    input logic start,

    // matrix to send and its active dimension.
    input logic signed [            ACC_W-1:0] C_in[MAX_DIM][MAX_DIM],
    input logic        [$clog2(MAX_DIM+1)-1:0] dim,

    // uart_tx handshake.
    output logic [7:0] tx_data,
    output logic       tx_start,
    input  logic       tx_busy,
    input  logic       tx_done,

    output logic busy,
    output logic send_done
);

  localparam INDEX_W = $clog2(MAX_DIM);
  localparam DIM_W = $clog2(MAX_DIM + 1);
  // Number of bytes per C element.
  localparam BYTES_PER_ELEM = (ACC_W + 7) / 8;
  localparam BYTE_W = (BYTES_PER_ELEM <= 1) ? 1 : $clog2(BYTES_PER_ELEM);

  typedef enum logic [2:0] {
    IDLE,
    SEND_ROWS,
    SEND_COLS,
    SEND_DATA,
    WAIT_HDR,
    WAIT_DATA,
    DONE
  } state_t;

  state_t               state;

  logic   [INDEX_W-1:0] row_index;
  logic   [INDEX_W-1:0] col_index;
  logic   [ BYTE_W-1:0] byte_index;
  logic   [  DIM_W-1:0] dim_latch;

  // state to return to after a byte finishes transmitting.
  state_t               return_state;

  // Select the byte of a value indexed by idx (little-endian).
  function automatic logic [7:0] elem_byte(input logic signed [ACC_W-1:0] v,
                                           input logic [BYTE_W-1:0] idx);
    elem_byte = v[(idx*8)+:8];
  endfunction

  assign busy = (state != IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= IDLE;
      tx_data      <= 8'h00;
      tx_start     <= 1'b0;
      row_index    <= '0;
      col_index    <= '0;
      byte_index   <= '0;
      dim_latch    <= '0;
      return_state <= IDLE;
      send_done    <= 1'b0;
    end else begin
      // Defaults: tx_start and send_done are one-cycle pulses.
      tx_start  <= 1'b0;
      send_done <= 1'b0;

      case (state)
        IDLE: begin
          if (start && dim != 0) begin
            dim_latch  <= dim;
            row_index  <= '0;
            col_index  <= '0;
            byte_index <= '0;
            state      <= SEND_ROWS;
          end
        end

        // Send the rows header byte.
        SEND_ROWS: begin
          if (!tx_busy) begin
            tx_data      <= {{(8 - DIM_W) {1'b0}}, dim_latch};
            tx_start     <= 1'b1;
            return_state <= SEND_COLS;
            state        <= WAIT_HDR;
          end
        end

        // Send the cols header byte (square: same as rows).
        SEND_COLS: begin
          if (!tx_busy) begin
            tx_data      <= {{(8 - DIM_W) {1'b0}}, dim_latch};
            tx_start     <= 1'b1;
            return_state <= SEND_DATA;
            state        <= WAIT_HDR;
          end
        end

        // Send one byte of the current element, row-major, LSB first.
        SEND_DATA: begin
          if (!tx_busy) begin
            tx_data      <= elem_byte(C_in[row_index][col_index], byte_index);
            tx_start     <= 1'b1;
            state        <= WAIT_DATA;
          end
        end

        // A header byte is in flight; resume at return_state when done.
        WAIT_HDR: begin
          if (tx_done) state <= return_state;
        end

        // A data byte is in flight; when done, advance byte, then column,
        // then row.
        WAIT_DATA: begin
          if (tx_done) begin
            if (byte_index == BYTE_W'(BYTES_PER_ELEM - 1)) begin
              byte_index <= '0;
              if (col_index == INDEX_W'(dim_latch - 1'b1)) begin
                col_index <= '0;
                if (row_index == INDEX_W'(dim_latch - 1'b1)) begin
                  state <= DONE;  // whole matrix sent
                end else begin
                  row_index <= row_index + 1'b1;
                  state     <= SEND_DATA;
                end
              end else begin
                col_index <= col_index + 1'b1;
                state     <= SEND_DATA;
              end
            end else begin
              byte_index <= byte_index + 1'b1;
              state      <= SEND_DATA;
            end
          end
        end

        DONE: begin
          send_done <= 1'b1;
          state     <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule

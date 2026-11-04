module uart_matrix_loader #(  //i didnt start commenting yet just pushing cuz luke needs
    parameter MAX_DIM = 64
) (
    input logic clk,
    input logic rst_n,

    input logic [7:0] rx_data,
    input logic       rx_valid,

    // Connect these to tiling_block's load/control ports.
    output logic                                wr_en,
    output logic                                wr_sel,   // 0 = A, 1 = B
    output logic        [  $clog2(MAX_DIM)-1:0] wr_row,
    output logic        [  $clog2(MAX_DIM)-1:0] wr_col,
    output logic signed [                  7:0] wr_data,
    output logic        [$clog2(MAX_DIM+1)-1:0] dim,
    output logic                                start,

    output logic load_done,
    output logic error
);

  localparam INDEX_W = $clog2(MAX_DIM);
  localparam DIM_W   = $clog2(MAX_DIM + 1);

  typedef enum logic [2:0] {
    A_ROWS,
    A_COLS,
    A_DATA,
    B_ROWS,
    B_COLS,
    B_DATA,
    DONE,
    ERROR
  } state_t;

  state_t               state;
  logic   [        7:0] a_rows;
  logic   [INDEX_W-1:0] row_index;
  logic   [INDEX_W-1:0] col_index;

  // Present the current payload byte to tiling_block on its write edge.
  always_comb begin
    wr_en   = 1'b0;
    wr_sel  = 1'b0;
    wr_row  = row_index;
    wr_col  = col_index;
    wr_data = $signed(rx_data);

    if (rx_valid && state == A_DATA) wr_en = 1'b1;
    else if (rx_valid && state == B_DATA) begin
      wr_en  = 1'b1;
      wr_sel = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= A_ROWS;
      a_rows    <= 0;
      row_index <= 0;
      col_index <= 0;
      dim       <= 0;
      start     <= 0;
      load_done <= 0;
      error     <= 0;
    end else begin
      // start is a one-cycle pulse, issued after the final B byte.
      start <= 1'b0;

      if (rx_valid) begin
        case (state)
          A_ROWS: begin
            if (rx_data == 0 || rx_data > MAX_DIM) begin
              state <= ERROR;
              error <= 1'b1;
            end else begin
              a_rows <= rx_data;
              dim    <= rx_data[DIM_W-1:0];
              state  <= A_COLS;
            end
          end

          A_COLS: begin
            // Current tiling_block only supports square matrices.
            if (rx_data == 0 || rx_data > MAX_DIM || rx_data != a_rows) begin
              state <= ERROR;
              error <= 1'b1;
            end else begin
              row_index <= 0;
              col_index <= 0;
              state     <= A_DATA;
            end
          end

          A_DATA: begin
            if (col_index == dim - 1'b1) begin
              col_index <= 0;

              if (row_index == dim - 1'b1) begin
                row_index <= 0;
                state     <= B_ROWS;
              end else begin
                row_index <= row_index + 1'b1;
              end
            end else begin
              col_index <= col_index + 1'b1;
            end
          end

          B_ROWS: begin
            if (rx_data != dim) begin
              state <= ERROR;
              error <= 1'b1;
            end else begin
              state <= B_COLS;
            end
          end

          B_COLS: begin
            if (rx_data != dim) begin
              state <= ERROR;
              error <= 1'b1;
            end else begin
              row_index <= 0;
              col_index <= 0;
              state     <= B_DATA;
            end
          end

          B_DATA: begin
            if (col_index == dim - 1'b1) begin
              col_index <= 0;

              if (row_index == dim - 1'b1) begin
                row_index <= 0;
                state     <= DONE;
                load_done <= 1'b1;
                start     <= 1'b1;
              end else begin
                row_index <= row_index + 1'b1;
              end
            end else begin
              col_index <= col_index + 1'b1;
            end
          end

          default: begin
            // Ignore additional bytes after completion or error.
          end
        endcase
      end
    end
  end

endmodule


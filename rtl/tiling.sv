module tiling_block #(
    parameter N       = 8,      // systolic array size (Fixed)
    parameter MAX_DIM = 64,     // largest matrix supported
    parameter DATA_W  = 8, 
    parameter ACC_W   = 32
) (
    input  logic clk,
    input  logic rst_n,

    // load interface: write one element of A or B
    input  logic                         wr_en,
    input  logic                         wr_sel,    // 0 = A, 1 = B
    input  logic [$clog2(MAX_DIM)-1:0]   wr_row,
    input  logic [$clog2(MAX_DIM)-1:0]   wr_col,
    input  logic signed [DATA_W-1:0]     wr_data,

    // control
    input  logic                         start,
    input  logic [$clog2(MAX_DIM+1)-1:0] dim,
    output logic                         busy,
    output logic                         done,

    output logic signed [ACC_W-1:0]      C_out [MAX_DIM][MAX_DIM]
);

//----------------------------Initializing things--------------------------------------------------
  typedef enum logic [1:0] {IDLE, CLEAR, STREAM, WRITE} state_t;
  state_t state = IDLE;

  logic signed [DATA_W-1:0] A_mem [MAX_DIM][MAX_DIM];
  logic signed [DATA_W-1:0] B_mem [MAX_DIM][MAX_DIM];

  int tile_row, tile_col, stream_cycle; // current output tile and cycle
  int tiles_per_side;                   // tiles per side (rounded up)
  int padded_dim;                       // padded size (29x29 --> 32x32)
  int last_stream_cycle;                // last streaming cycle
  assign tiles_per_side    = (dim + N - 1) / N;
  assign padded_dim        = tiles_per_side * N;
  assign last_stream_cycle = padded_dim + 2*N - 3;

  logic clear_acc, en;
  assign clear_acc = (state == CLEAR);
  assign en        = (state == STREAM);
  assign busy      = (state != IDLE);
//----------------------------Calling Systolic_Array--------------------------------------------------

  logic signed [DATA_W-1:0] a_row_in [N];
  logic signed [DATA_W-1:0] b_col_in [N];
  logic signed [ACC_W-1:0]  c_matrix [N][N];

  Systolic_Array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_arr (
      .clk      (clk),
      .rst_n    (rst_n),
      .clear_acc(clear_acc),
      .en       (en),
      .a_row_in (a_row_in),
      .b_col_in (b_col_in),
      .c_matrix (c_matrix)
  );
//--------------------------------Writeing Data to Memory------------------------------------------------------
  always_ff @(posedge clk) begin
    if (wr_en) begin
      if (wr_sel) B_mem[wr_row][wr_col] <= wr_data;
      else        A_mem[wr_row][wr_col] <= wr_data;
    end
  end
//-------------------------------Skewed Feed-----------------------------------------------------
  int element_index, matrix_row, matrix_col;
  logic a_valid, b_valid;

  always_comb begin
    for (int i = 0; i < N; i++) begin
      element_index = stream_cycle - i;
      matrix_row = tile_row*N + i;
      a_valid = (matrix_row < dim) && (element_index >= 0 && element_index < dim);

      a_row_in[i] = a_valid ? A_mem[matrix_row][element_index] : '0;
    end

    for (int j = 0; j < N; j++) begin
      element_index = stream_cycle - j;
      matrix_col = tile_col*N + j;
      b_valid = (matrix_col < dim) && (element_index >= 0 && element_index < dim);

      b_col_in[j] = b_valid ? B_mem[element_index][matrix_col] : '0;
    end
  end

//------------------------------FSM Controller-----------------------------------------------------

  // control FSM: CLEAR -> STREAM -> WRITE, repeated for every output tile
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      done  <= 1'b0;
      
    end else begin
      done <= 1'b0;
      case (state)
        IDLE: if (start) begin
          tile_row <= 0;
          tile_col <= 0;
          state <= CLEAR;
        end



        CLEAR: begin
          stream_cycle <= 0;
          state <= STREAM;
        end



        STREAM: begin
          if (stream_cycle == last_stream_cycle) state <= WRITE;
          else                                  stream_cycle <= stream_cycle + 1;
        end



        WRITE: begin
          for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
              C_out[tile_row*N + i][tile_col*N + j] <= c_matrix[i][j];

          if (tile_col < tiles_per_side - 1) begin
            tile_col <= tile_col + 1;
            state <= CLEAR;
          end else if (tile_row < tiles_per_side - 1) begin
            tile_row <= tile_row + 1;
            tile_col <= 0;
            state <= CLEAR;
          end else begin
            state <= IDLE;
            done  <= 1'b1;
          end
        end

        
      endcase
    end
  end

endmodule

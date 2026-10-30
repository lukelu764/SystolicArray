module Systolic_Array #(
    parameter N      = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     clear_acc,
    input  logic                     en,
    input  logic signed [DATA_W-1:0] a_row_in [N],
    input  logic signed [DATA_W-1:0] b_col_in [N],
    output logic signed [ ACC_W-1:0] c_matrix [N][N]
);
  logic signed [DATA_W-1:0] a_wire[  N][N+1];
  logic signed [DATA_W-1:0] b_wire[N+1][  N];

  genvar i;
  genvar j;
  generate
    for (i = 0; i < N; i++) begin : gen_pe_row
      for (j = 0; j < N; j++) begin : gen_pe_col
        PE_Block #(
            .DATA_W(DATA_W),
            .ACC_W (ACC_W)
        ) u_pe (
            .clk      (clk),
            .rst_n    (rst_n),
            .clear_acc(clear_acc),
            .en       (en),
            .a_in     ((j == 0) ? a_row_in[i] : a_wire[i][j]),
            .b_in     ((i == 0) ? b_col_in[j] : b_wire[i][j]),
            .a_out    (a_wire[i][j+1]),
            .b_out    (b_wire[i+1][j]),
            .c_out    (c_matrix[i][j])
        );
      end
    end
  endgenerate
endmodule


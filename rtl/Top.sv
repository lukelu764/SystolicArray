module Top #(
    parameter N = 8,
    parameter MAX_DIM = 64,
    parameter DATA_W = 8,
    parameter ACC_W = 32
) (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic wr_sel,
    input logic [$clog2(MAX_DIM)-1:0] wr_row,
    input logic [$clog2(MAX_DIM)-1:0] wr_col,
    input logic signed [DATA_W-1:0] wr_data,
    input logic start,
    input logic [$clog2(MAX_DIM+1)-1:0] dim,
    output logic busy,
    output logic done,
    output logic signed [ACC_W-1:0] C_out [MAX_DIM][MAX_DIM]
);
    tiling_block #(
        .N(N), 
        .MAX_DIM(MAX_DIM), 
        .DATA_W(DATA_W), 
        .ACC_W(ACC_W)
    ) u_tiling (
        .clk(clk), 
        .rst_n(rst_n), 
        .wr_en(wr_en), 
        .wr_sel(wr_sel),
        .wr_row(wr_row), 
        .wr_col(wr_col), 
        .wr_data(wr_data),
        .start(start), 
        .dim(dim), .
        busy(busy), 
        .done(done), 
        .C_out(C_out)
    );
endmodule
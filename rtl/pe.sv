module PE_Block #(
    parameter DATA_W = 8,
    parameter ACC_W = 32
) (
    input logic                      clk,
    input logic                      rst_n,
    input logic                      clear_acc,
    input logic                      en,
    input logic signed  [DATA_W-1:0] a_in,
    input logic signed  [DATA_W-1:0] b_in,
    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic signed [ACC_W-1:0]  c_out
);

logic signed [ACC_W-1:0] acc;
assign c_out = acc;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_out <= '0;
        b_out <= '0;
        acc   <= '0;
    end else if (clear_acc) begin
        a_out <= '0;
        b_out <= '0;
        acc   <= '0;
    end else begin
        a_out <= a_in;
        b_out <= b_in;
        acc   <= acc + (a_in * b_in);
    end
end

endmodule
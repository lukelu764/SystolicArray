
module Top (
    input  wire [9:0] SW,
    output wire [9:0] LEDR
);

    assign LEDR = SW;

endmodule
module tb_systolic_array;
  localparam N      = 2;
  localparam DATA_W = 8;
  localparam ACC_W  = 32;

  logic                     clk = 0;
  logic                     rst_n = 0;
  logic                     clear_acc = 0;
  logic                     en = 0;
  logic signed [DATA_W-1:0] a_row_in      [N];
  logic signed [DATA_W-1:0] b_col_in      [N];
  logic signed [ ACC_W-1:0] c_matrix      [N] [N];

  // 50 MHz clock
  always #10 clk <= ~clk;

  // Instantiate your systolic_array
  systolic_array #(
      .N     (N),
      .DATA_W(DATA_W),
      .ACC_W (ACC_W)
  ) dut (
      .*
  );

  initial begin
    string wavefile;
    if (!$value$plusargs("WAVE=%s", wavefile))
      wavefile = "tb/systolic_wave.vcd";
    $dumpfile(wavefile);
    $dumpvars(0, tb_systolic_array);

    // Initialize inputs to 0
    for (int i = 0; i < N; i++) begin
      a_row_in[i] = '0;
      b_col_in[i] = '0;
    end

    // Release reset and pulse clear_acc on negedge clk
    #25 rst_n = 1;
    @(negedge clk);
    clear_acc = 1;
    @(negedge clk);
    clear_acc   = 0;

    // --- Cycle t = 0: Feed A[0][0]=1, B[0][0]=5 ---
    en          = 1;
    a_row_in[0] = 8'd1;
    a_row_in[1] = 8'd0;
    b_col_in[0] = 8'd5;
    b_col_in[1] = 8'd0;
    @(negedge clk);

    // --- Cycle t = 1: Feed A[0][1]=2, A[1][0]=3 | B[1][0]=7, B[0][1]=6 ---
    a_row_in[0] = 8'd2;
    a_row_in[1] = 8'd3;
    b_col_in[0] = 8'd7;
    b_col_in[1] = 8'd6;
    @(negedge clk);

    // --- Cycle t = 2: Feed A[1][1]=4 | B[1][1]=8 (Row 0 & Col 0 done -> pad 0) ---
    a_row_in[0] = 8'd0;
    a_row_in[1] = 8'd4;
    b_col_in[0] = 8'd0;
    b_col_in[1] = 8'd8;
    @(negedge clk);

    // --- Cycle t = 3 (3N-2 = 4th cycle): Pad 0s while PE[1][1] finishes ---
    a_row_in[0] = 8'd0;
    a_row_in[1] = 8'd0;
    b_col_in[0] = 8'd0;
    b_col_in[1] = 8'd0;
    @(negedge clk);

    // Freeze array after 4 posedges have completed
    en = 0;
    @(posedge clk);

    $display("Result Matrix C:");
    $display("[ %0d  %0d ] (Expected: [ 19  22 ])", c_matrix[0][0], c_matrix[0][1]);
    $display("[ %0d  %0d ] (Expected: [ 43  50 ])", c_matrix[1][0], c_matrix[1][1]);
    $finish;
  end
endmodule

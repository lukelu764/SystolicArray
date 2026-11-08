`timescale 1ns / 1ps
//============================================================================
// tb_matrix_io : self-checking test of the full matrix I/O path
//----------------------------------------------------------------------------
//   host uart_tx --serial_in--> uart_rx --> uart_matrix_loader --> tiling
//                                                                    |
//   host uart_rx <--serial_out-- uart_tx <-- uart_matrix_sender <----+
//
// Both directions go over real UART serial lines, so the loader sees bytes at
// the true UART rate and the sender is checked bit-accurately.
//
// Each test case resets the DUT (the loader accepts one load per reset).
//
// Valid-load cases check:
//   - loader: load_done set, error clear, exactly one start pulse
//   - tiling: exactly one done pulse, C_out matches the reference product
//   - sender: no bytes before start, exactly 2 + dim*dim*4 bytes, nothing
//     extra afterwards, one send_done pulse, busy returns low,
//     header == {dim, dim}, every element correct (little-endian int32)
// Error cases check that the loader flags error, never starts tiling, and
// ignores bytes that follow the error.
//
// Plusargs:
//   +FULL    also run the MAX_DIM x MAX_DIM case (slow; use with +NOWAVE)
//   +NOWAVE  skip VCD dumping
//   +SEED=n  seed for the random matrices
//============================================================================
module tb_matrix_io;

  // ---- Parameters -----------------------------------------------------------
  localparam int N = 8;
  localparam int MAX_DIM = 64;
  localparam int DATA_W = 8;
  localparam int ACC_W = 32;
  localparam int BYTES_PER_ELEM = ACC_W / 8;

  localparam int CLK_FREQ = 1000;  // CLKS_PER_BIT = 10 keeps the sim fast
  localparam int BAUD_RATE = 100;
  localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
  localparam int BYTE_CLKS = CLKS_PER_BIT * 10;  // start + 8 data + stop

  localparam int INDEX_W = $clog2(MAX_DIM);
  localparam int DIM_W = $clog2(MAX_DIM + 1);
  localparam int MAX_BYTES = 2 + MAX_DIM * MAX_DIM * BYTES_PER_ELEM;

  // Matrix fill patterns.
  localparam int PAT_RANDOM = 0;
  localparam int PAT_ALL_MIN = 1;  // every element -128
  localparam int PAT_EXTREMES = 2;  // mix of -128 and 127

  // ---- Clock / reset --------------------------------------------------------
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // ---- Host -> DUT serial link ------------------------------------------------
  logic [7:0] host_tx_data = 8'h00;
  logic host_tx_start = 1'b0;
  logic host_tx_busy, host_tx_done;
  logic serial_in;

  uart_tx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) u_host_tx (
      .clk     (clk),
      .rst_n   (rst_n),
      .tx_data (host_tx_data),
      .tx_start(host_tx_start),
      .tx_busy (host_tx_busy),
      .tx_done (host_tx_done),
      .tx      (serial_in)
  );

  logic [7:0] rx_data;
  logic       rx_valid;

  uart_rx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) u_dut_rx (
      .clk       (clk),
      .rst_n     (rst_n),
      .rx        (serial_in),
      .data_out  (rx_data),
      .data_valid(rx_valid)
  );

  // ---- Loader -> tiling ---------------------------------------------------------
  logic                     wr_en;
  logic                     wr_sel;
  logic        [INDEX_W-1:0] wr_row;
  logic        [INDEX_W-1:0] wr_col;
  logic signed [       7:0] wr_data;
  logic        [  DIM_W-1:0] dim;
  logic                     load_start;
  logic                     load_done;
  logic                     load_error;

  uart_matrix_loader #(
      .MAX_DIM(MAX_DIM)
  ) u_loader (
      .clk      (clk),
      .rst_n    (rst_n),
      .rx_data  (rx_data),
      .rx_valid (rx_valid),
      .wr_en    (wr_en),
      .wr_sel   (wr_sel),
      .wr_row   (wr_row),
      .wr_col   (wr_col),
      .wr_data  (wr_data),
      .dim      (dim),
      .start    (load_start),
      .load_done(load_done),
      .error    (load_error)
  );

  logic                    til_busy;
  logic                    til_done;
  logic signed [ACC_W-1:0] C_out    [MAX_DIM][MAX_DIM];

  tiling #(
      .N      (N),
      .MAX_DIM(MAX_DIM),
      .DATA_W (DATA_W),
      .ACC_W  (ACC_W)
  ) u_tiling (
      .clk    (clk),
      .rst_n  (rst_n),
      .wr_en  (wr_en),
      .wr_sel (wr_sel),
      .wr_row (wr_row),
      .wr_col (wr_col),
      .wr_data(wr_data),
      .start  (load_start),
      .dim    (dim),
      .busy   (til_busy),
      .done   (til_done),
      .C_out  (C_out)
  );

  // ---- Sender -> DUT uart_tx -> host --------------------------------------------
  logic       send_start = 1'b0;
  logic [7:0] snd_tx_data;
  logic snd_tx_start, snd_tx_busy, snd_tx_done;
  logic snd_busy, snd_send_done;
  logic serial_out;

  uart_matrix_sender #(
      .MAX_DIM(MAX_DIM),
      .ACC_W  (ACC_W)
  ) u_sender (
      .clk      (clk),
      .rst_n    (rst_n),
      .start    (send_start),
      .C_in     (C_out),
      .dim      (dim),
      .tx_data  (snd_tx_data),
      .tx_start (snd_tx_start),
      .tx_busy  (snd_tx_busy),
      .tx_done  (snd_tx_done),
      .busy     (snd_busy),
      .send_done(snd_send_done)
  );

  uart_tx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) u_dut_tx (
      .clk     (clk),
      .rst_n   (rst_n),
      .tx_data (snd_tx_data),
      .tx_start(snd_tx_start),
      .tx_busy (snd_tx_busy),
      .tx_done (snd_tx_done),
      .tx      (serial_out)
  );

  logic [7:0] cap_data;
  logic       cap_valid;

  uart_rx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) u_host_rx (
      .clk       (clk),
      .rst_n     (rst_n),
      .rx        (serial_out),
      .data_out  (cap_data),
      .data_valid(cap_valid)
  );

  // ---- Monitors -------------------------------------------------------------------
  // Each counter has a single driver and clears on reset; the stimulus
  // process only reads them.
  logic [7:0] cap_buf        [MAX_BYTES];
  int         cap_count;
  int         load_start_count;
  int         til_done_count;
  int         til_busy_rises;
  int         send_done_count;
  logic       til_busy_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_count        <= 0;
      load_start_count <= 0;
      til_done_count   <= 0;
      til_busy_rises   <= 0;
      send_done_count  <= 0;
      til_busy_q       <= 1'b0;
    end else begin
      til_busy_q <= til_busy;
      if (cap_valid) begin
        if (cap_count < MAX_BYTES) cap_buf[cap_count] <= cap_data;
        cap_count <= cap_count + 1;
      end
      if (load_start) load_start_count <= load_start_count + 1;
      if (til_done) til_done_count <= til_done_count + 1;
      if (til_busy && !til_busy_q) til_busy_rises <= til_busy_rises + 1;
      if (snd_send_done) send_done_count <= send_done_count + 1;
    end
  end

  // ---- Reference data -------------------------------------------------------------
  int A   [MAX_DIM][MAX_DIM];
  int B   [MAX_DIM][MAX_DIM];
  int Cexp[MAX_DIM][MAX_DIM];

  int total_cases = 0;
  int failed_cases = 0;
  int case_errors;

  // ---- Helpers ----------------------------------------------------------------------
  task automatic fail(input string msg);
    case_errors++;
    if (case_errors <= 10) $display("    ERROR: %s", msg);
  endtask

  task automatic reset_dut();
    @(negedge clk);
    rst_n = 1'b0;
    send_start = 1'b0;
    host_tx_start = 1'b0;
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);
  endtask

  task automatic wait_clks(input int n);
    repeat (n) @(negedge clk);
  endtask

  // Send one byte from the host over serial_in; return when it is fully out.
  task automatic host_send_byte(input logic [7:0] b);
    @(negedge clk);
    host_tx_data  = b;
    host_tx_start = 1'b1;
    @(negedge clk);
    host_tx_start = 1'b0;
    while (!host_tx_done) @(negedge clk);
  endtask

  function automatic int rand_int8();
    return int'($urandom_range(255)) - 128;
  endfunction

  task automatic gen_matrices(input int d, input int pattern);
    for (int i = 0; i < d; i++)
      for (int j = 0; j < d; j++)
        case (pattern)
          PAT_ALL_MIN: begin
            A[i][j] = -128;
            B[i][j] = -128;
          end
          PAT_EXTREMES: begin
            A[i][j] = ((i + j) % 2 == 0) ? 127 : -128;
            B[i][j] = ((i * j) % 3 == 0) ? -128 : 127;
          end
          default: begin
            A[i][j] = rand_int8();
            B[i][j] = rand_int8();
          end
        endcase
    for (int i = 0; i < d; i++)
      for (int j = 0; j < d; j++) begin
        Cexp[i][j] = 0;
        for (int k = 0; k < d; k++) Cexp[i][j] += A[i][k] * B[k][j];
      end
  endtask

  // Host framing: [rows][cols][A row-major][rows][cols][B row-major]
  task automatic host_send_matrices(input int d);
    host_send_byte(8'(d));
    host_send_byte(8'(d));
    for (int i = 0; i < d; i++) for (int j = 0; j < d; j++) host_send_byte(8'(A[i][j]));
    host_send_byte(8'(d));
    host_send_byte(8'(d));
    for (int i = 0; i < d; i++) for (int j = 0; j < d; j++) host_send_byte(8'(B[i][j]));
  endtask

  // Wait until cond_count >= target or timeout; returns 1 on success.
  task automatic wait_count(ref int cnt, input int target, input int max_clks, output bit ok);
    int c = 0;
    while (cnt < target && c < max_clks) begin
      @(negedge clk);
      c++;
    end
    ok = (cnt >= target);
  endtask

  task automatic finish_case(input string name);
    total_cases++;
    if (case_errors == 0) $display("  PASS  %s", name);
    else begin
      failed_cases++;
      $display("  FAIL  %s (%0d error(s))", name, case_errors);
    end
  endtask

  // ---- Valid load -> compute -> send case -----------------------------------
  task automatic run_case(input string name, input int d, input int pattern,
                          input bit restart_mid_send);
    int  exp_bytes;
    int  base;
    bit  ok;
    logic signed [ACC_W-1:0] got;

    case_errors = 0;
    exp_bytes   = 2 + d * d * BYTES_PER_ELEM;
    $display("[CASE] %s: %0dx%0d", name, d, d);

    reset_dut();
    gen_matrices(d, pattern);
    host_send_matrices(d);

    // Load + compute.
    wait_count(til_done_count, 1, 20 * (d + 2 * N) * ((d + N - 1) / N) ** 2 + 1000, ok);
    if (!ok) fail("timeout waiting for tiling.done");
    if (load_error) fail("loader raised error on a valid stream");
    if (!load_done) fail("load_done not set after full load");
    if (load_start_count != 1)
      fail($sformatf("loader issued %0d start pulses, expected 1", load_start_count));
    if (til_done_count != 1)
      fail($sformatf("tiling issued %0d done pulses, expected 1", til_done_count));
    if (dim != DIM_W'(d)) fail($sformatf("loader dim=%0d, expected %0d", dim, d));

    for (int i = 0; i < d; i++)
      for (int j = 0; j < d; j++)
        if (C_out[i][j] !== Cexp[i][j])
          fail($sformatf("tiling C[%0d][%0d]=%0d, expected %0d", i, j, C_out[i][j], Cexp[i][j]));

    // Sender must stay silent until told to send.
    wait_clks(3 * BYTE_CLKS);
    if (cap_count != 0) fail($sformatf("%0d byte(s) sent before sender start", cap_count));
    if (snd_busy) fail("sender busy before start");

    // Send.
    @(negedge clk);
    send_start = 1'b1;
    @(negedge clk);
    send_start = 1'b0;
    @(negedge clk);
    if (!snd_busy) fail("sender busy not asserted after start");

    if (restart_mid_send) begin
      // A second start during a transfer must be ignored.
      wait_count(cap_count, 5, 10 * BYTE_CLKS, ok);
      @(negedge clk);
      send_start = 1'b1;
      @(negedge clk);
      send_start = 1'b0;
    end

    wait_count(cap_count, exp_bytes, exp_bytes * (BYTE_CLKS + 20) + 1000, ok);
    if (!ok) fail($sformatf("received %0d of %0d bytes", cap_count, exp_bytes));

    // Anything extra would show up within a few byte times.
    wait_clks(4 * BYTE_CLKS);
    if (cap_count > exp_bytes)
      fail($sformatf("received %0d bytes, expected exactly %0d", cap_count, exp_bytes));
    if (send_done_count != 1)
      fail($sformatf("send_done pulsed %0d times, expected 1", send_done_count));
    if (snd_busy) fail("sender still busy after transfer");

    // Decode.
    if (cap_count >= 2) begin
      if (cap_buf[0] !== 8'(d)) fail($sformatf("header rows=%0d, expected %0d", cap_buf[0], d));
      if (cap_buf[1] !== 8'(d)) fail($sformatf("header cols=%0d, expected %0d", cap_buf[1], d));
    end
    if (cap_count >= exp_bytes) begin
      for (int i = 0; i < d; i++)
        for (int j = 0; j < d; j++) begin
          base = 2 + (i * d + j) * BYTES_PER_ELEM;
          for (int b = 0; b < BYTES_PER_ELEM; b++) got[(b*8)+:8] = cap_buf[base+b];
          if (got !== Cexp[i][j])
            fail($sformatf("received C[%0d][%0d]=%0d, expected %0d", i, j, got, Cexp[i][j]));
        end
    end

    if (d <= 4) begin
      $display("    C (expected):");
      for (int i = 0; i < d; i++) begin
        $write("     ");
        for (int j = 0; j < d; j++) $write(" %7d", Cexp[i][j]);
        $write("\n");
      end
    end

    finish_case(name);
  endtask

  // ---- Bad-header case ----------------------------------------------------------
  // Send `len` bytes from `seq`, expect the loader to flag error after them,
  // then send a full valid-looking stream and confirm it is ignored.
  task automatic run_error_case(input string name, input logic [7:0] seq[8], input int len);
    case_errors = 0;
    $display("[CASE] %s", name);
    reset_dut();

    for (int i = 0; i < len; i++) host_send_byte(seq[i]);
    wait_clks(2 * BYTE_CLKS);
    if (!load_error) fail("loader did not raise error");

    // Bytes after an error must be ignored.
    for (int i = 0; i < 2 + 2 * 2 + 2 + 2 * 2; i++) host_send_byte(8'd2);
    wait_clks(100);

    if (!load_error) fail("error flag cleared without reset");
    if (load_done) fail("load_done set after error");
    if (load_start_count != 0) fail("loader started tiling after error");
    if (til_busy_rises != 0) fail("tiling became busy after error");

    finish_case(name);
  endtask

  // ---- Sender with nothing loaded ------------------------------------------------
  task automatic run_sender_idle_case();
    case_errors = 0;
    $display("[CASE] sender ignores start when dim == 0");
    reset_dut();
    @(negedge clk);
    send_start = 1'b1;
    @(negedge clk);
    send_start = 1'b0;
    wait_clks(4 * BYTE_CLKS);
    if (cap_count != 0) fail($sformatf("sender emitted %0d byte(s) with dim == 0", cap_count));
    if (snd_busy) fail("sender busy with dim == 0");
    if (send_done_count != 0) fail("send_done pulsed with dim == 0");
    finish_case("sender ignores start when dim == 0");
  endtask

  // ---- Main ---------------------------------------------------------------------------
  initial begin
    string wavefile;
    int seed;
    logic [7:0] seq[8];

    if (!$test$plusargs("NOWAVE")) begin
      if (!$value$plusargs("WAVE=%s", wavefile)) wavefile = "tb/tb_matrix_io.vcd";
      $dumpfile(wavefile);
      $dumpvars(0, tb_matrix_io);
    end
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    void'($urandom(seed));
    $display("tb_matrix_io: seed=%0d", seed);

    // Valid loads.
    run_case("1x1 minimum size", 1, PAT_RANDOM, 0);
    run_case("2x2 random", 2, PAT_RANDOM, 0);
    run_case("4x4 all -128 (largest positive products)", 4, PAT_ALL_MIN, 0);
    run_case("4x4 mixed 127/-128", 4, PAT_EXTREMES, 0);
    run_case("8x8 exactly one tile", 8, PAT_RANDOM, 0);
    run_case("9x9 padding into a second tile", 9, PAT_RANDOM, 0);
    run_case("12x12 random, start re-pulsed mid-send", 12, PAT_RANDOM, 1);
    if ($test$plusargs("FULL")) run_case("64x64 MAX_DIM all -128", MAX_DIM, PAT_ALL_MIN, 0);

    // Bad headers.
    seq = '{8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0};
    run_error_case("A rows == 0", seq, 1);

    seq[0] = 8'(MAX_DIM + 1);
    run_error_case("A rows > MAX_DIM", seq, 1);

    seq[0] = 8'd3;
    seq[1] = 8'd4;
    run_error_case("non-square A (3x4)", seq, 2);

    seq = '{8'd2, 8'd2, 8'd1, 8'd2, 8'd3, 8'd4, 8'd3, 8'd0};
    run_error_case("B rows != A dim", seq, 7);

    seq = '{8'd2, 8'd2, 8'd1, 8'd2, 8'd3, 8'd4, 8'd2, 8'd3};
    run_error_case("B cols != A dim", seq, 8);

    run_sender_idle_case();

    $display("----------------------------------------------------------------");
    if (failed_cases == 0) $display("PASS: all %0d test cases passed.", total_cases);
    else $fatal(1, "FAIL: %0d of %0d test cases failed.", failed_cases, total_cases);
    $finish;
  end

  initial begin
    #200_000_000;
    $fatal(1, "TIMEOUT: testbench did not finish");
  end

endmodule

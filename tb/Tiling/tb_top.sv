
`timescale 1ns/1ps
module tb_top;
    localparam N=8, MAX_DIM=64, DATA_W=8, ACC_W=32;
    logic clk=0;
    always #5 clk=~clk;  // 100 MHz
    logic rst_n=0, wr_en=0, wr_sel=0, start=0;
    logic [$clog2(MAX_DIM)-1:0] wr_row=0, wr_col=0;
    logic signed [DATA_W-1:0] wr_data=0;
    logic [$clog2(MAX_DIM+1)-1:0] dim=12;
    logic busy, done;
    logic signed [ACC_W-1:0] C_out [MAX_DIM][MAX_DIM];
    integer A[0:11][0:11], B[0:11][0:11], expected[0:11][0:11];
    integer errors=0, cycles=0;

    // Directly instantiate tiling_block instead of Top
    tiling_block #(
        .N(N),
        .MAX_DIM(MAX_DIM),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_sel(wr_sel),
        .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .dim(dim), .busy(busy), .done(done), .C_out(C_out)
    );

    task automatic write_element(input bit select_b,
                                  input integer r, c, value);
        @(negedge clk);
        wr_en=1;
        wr_sel=select_b;
        wr_row=r;
        wr_col=c;
        wr_data=value;
        @(negedge clk);
        wr_en=0;
    endtask

    initial begin
        // Generate signed 12x12 matrices
        for (int i=0; i<12; i++) begin
            for (int j=0; j<12; j++) begin
                A[i][j]=((i*3+j*2)%11)-5;
                B[i][j]=((i*5+j*3)%13)-6;
            end
        end

        // Calculate expected results
        for (int i=0; i<12; i++)
            for (int j=0; j<12; j++) begin
                expected[i][j]=0;
                for (int k=0; k<12; k++)
                    expected[i][j]+=A[i][k]*B[k][j];
            end

        repeat (3) @(negedge clk);
        rst_n=1;
        $display("Loading 12x12 matrices A and B...");

        // Load Matrix A
        for (int i=0; i<12; i++)
            for (int j=0; j<12; j++)
                write_element(0,i,j,A[i][j]);

        // Load Matrix B
        for (int i=0; i<12; i++)
            for (int j=0; j<12; j++)
                write_element(1,i,j,B[i][j]);

        @(negedge clk);
        start=1;
        @(negedge clk);
        start=0;
        $display("Starting 12x12 multiplication with padding...");

        // Wait for done
        cycles=0;
        while (done !== 1'b1 && cycles < 200) begin
            @(negedge clk);
            cycles++;
        end

        if (done !== 1'b1)
            $fatal(1,"TIMEOUT: done never asserted");

        $display("Output matrix C:");

        // Check only the valid 12x12 output
        for (int i=0; i<12; i++) begin
            for (int j=0; j<12; j++) begin
                $write("%6d", C_out[i][j]);

                if (C_out[i][j] !== expected[i][j]) begin
                    $display("\nMISMATCH C[%0d][%0d]: got %0d, expected %0d",
                             i,j,C_out[i][j],expected[i][j]);
                    errors++;
                end
            end
            $write("\n");
        end

        if (errors==0)
            $display("PASS: All 144 matrix elements match!");
        else
            $fatal(1,"FAIL: %0d matrix elements incorrect",errors);

        $finish;
    end
endmodule

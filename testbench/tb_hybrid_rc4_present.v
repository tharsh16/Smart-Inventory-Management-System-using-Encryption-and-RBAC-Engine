`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench : tb_hybrid_rc4_present
// DUT       : hybrid_rc4_present (top_module.v)
//
// IMPORTANT : This module is named tb_hybrid_rc4_present
//             Set THIS as simulation top in Vivado
//
// Tests:
//   KAT  : PRESENT-64/80 ISO known answer test
//   1A   : Wrong password + encrypt  -> BLOCKED
//   1B   : Wrong password + decrypt  -> BLOCKED
//   2A   : USER  + encrypt           -> ALLOWED
//   2B   : USER  + decrypt           -> BLOCKED
//   3A   : ADMIN + encrypt           -> ALLOWED
//   3B   : ADMIN + decrypt           -> round-trip
//   4A   : ADMIN + HELLOWOR encrypt  -> ALLOWED
//   4B   : ADMIN + HELLOWOR decrypt  -> round-trip
//   5A   : ADMIN + 12345678 encrypt  -> ALLOWED
//   5B   : ADMIN + 12345678 decrypt  -> round-trip
//////////////////////////////////////////////////////////////////////////////////
module tb_hybrid_rc4_present;   // <-- DIFFERENT name from design module

    // Watchdog
    initial begin #20_000_000; $display("[WATCHDOG] timeout"); $finish; end

    // ---- DUT signals ----
    reg        clk, rst_n;
    reg  [7:0] data_in;
    reg  [1:0] load_sel;
    reg        wr_en;
    reg        mode_select;
    reg  [2:0] out_byte_sel;
    wire [7:0] data_out;
    wire       done;
    wire       auth_fail;

    // ---- Instantiate DUT ----
    // uut is the design, tb_hybrid_rc4_present is the testbench
    hybrid_rc4_present uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .load_sel    (load_sel),
        .wr_en       (wr_en),
        .mode_select (mode_select),
        .out_byte_sel(out_byte_sel),
        .data_out    (data_out),
        .done        (done),
        .auth_fail   (auth_fail)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // ---- Done latch ----
    reg done_latch;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    done_latch <= 1'b0;
        else if (done) done_latch <= 1'b1;
    end

    // ---- KAT: direct PRESENT check (module level, NOT inside initial) ----
    wire [63:0] kat_ct;
    present_encrypt kat_enc (
        .plaintext (64'h0000000000000000),
        .key       (80'h00000000000000000000),
        .ciphertext(kat_ct)
    );

    // =====================================================
    //  Tasks
    // =====================================================

    task read_output;
        output [63:0] result;
        integer i;
        begin
            result = 64'd0;
            for (i = 0; i < 8; i = i + 1) begin
                out_byte_sel = i[2:0]; #1;
                result[63 - i*8 -: 8] = data_out;
            end
        end
    endtask

    task write_password;
        input [15:0] pwd;
        begin
            @(negedge clk); load_sel=2'b00; data_in=pwd[15:8]; wr_en=1; @(posedge clk);
            @(negedge clk); data_in=pwd[7:0];                            @(posedge clk);
            @(negedge clk); wr_en=0;
        end
    endtask

    task write_plaintext;
        input [63:0] pt;
        integer j;
        begin
            for (j=7; j>=0; j=j-1) begin
                @(negedge clk);
                load_sel = 2'b01;
                data_in  = pt[j*8 +: 8];
                wr_en    = 1;
                @(posedge clk);
            end
            @(negedge clk); wr_en=0;
        end
    endtask

    task send_rc4_seed;
        input [63:0] seed;
        integer k;
        begin
            for (k=7; k>=0; k=k-1) begin
                @(negedge clk);
                load_sel = 2'b10;
                data_in  = seed[k*8 +: 8];
                wr_en    = 1;
                @(posedge clk);
            end
            @(negedge clk); wr_en=0;
        end
    endtask

    task fresh_start;
        input [15:0] pwd;
        input        mode;
        input [63:0] pt;
        begin
            rst_n=0; wr_en=0; data_in=0; load_sel=0; mode_select=0;
            repeat(4) @(posedge clk);
            @(negedge clk); rst_n=1;
            mode_select = mode;
            write_password(pwd);
            repeat(3) @(posedge clk);
            write_plaintext(pt);
        end
    endtask

    task wait_for_done;
        integer timeout;
        begin
            timeout=0;
            while (!done_latch && timeout<1200) begin
                @(posedge clk); timeout=timeout+1;
            end
            repeat(3) @(posedge clk); #1;
            if (timeout>=1200) $display("  [TIMEOUT] done never asserted");
        end
    endtask

    task wait_blocked;
        begin repeat(50) @(posedge clk); end
    endtask

    // =====================================================
    //  Test variables
    // =====================================================
    reg [63:0] enc_result, dec_result, original_pt;
    reg [63:0] rc4_seed;
    integer    pass_count, fail_count;

    initial begin
        $dumpfile("tb_hybrid_rc4_present.vcd");
        $dumpvars(0, tb_hybrid_rc4_present);

        pass_count=0; fail_count=0;

        $display("\n##################################################");
        $display("#   HYBRID RC4 -> PRESENT-64/80 TESTBENCH       #");
        $display("##################################################");
        $display("#  RC4 seed : 64-bit (8 bytes, byte-serial)     #");
        $display("#  RC4 out  : 80-bit keystream (10 bytes)       #");
        $display("#  Cipher   : PRESENT-64/80 ISO/IEC 29192-2     #");
        $display("#  ADMIN=0xA5C3 -> Encrypt+Decrypt              #");
        $display("#  USER =0xB2F1 -> Encrypt ONLY                 #");
        $display("#  WRONG=other  -> Blocked                      #");
        $display("##################################################");

        // ======================================================
        // KAT
        // ======================================================
        $display("\n>>> KAT: PRESENT-64/80 ISO Known Answer Test");
        $display("  plaintext = 0000000000000000");
        $display("  key       = 00000000000000000000");
        $display("  expected  = 2844b365c06992a3");
        #1;
        $display("  got       = %h", kat_ct);
        if (kat_ct===64'h2844b365c06992a3) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 1A: Wrong password + Encrypt -> BLOCKED
        // ======================================================
        $display("\n>>> CASE 1A: Wrong Password (0xDEAD) + Encrypt -> BLOCKED");
        rc4_seed = 64'hA1B2C3D4E5F60718;
        fresh_start(16'hDEAD, 1'b0, 64'h0011223344556677);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 1)", auth_fail);
        $display("  output=%h (expect 0)", enc_result);
        if (auth_fail===1'b1 && enc_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 1B: Wrong password + Decrypt -> BLOCKED
        // ======================================================
        $display("\n>>> CASE 1B: Wrong Password (0xDEAD) + Decrypt -> BLOCKED");
        fresh_start(16'hDEAD, 1'b1, 64'hDEADBEEFCAFEBABE);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 1)", auth_fail);
        $display("  output=%h (expect 0)", enc_result);
        if (auth_fail===1'b1 && enc_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 2A: USER + Encrypt -> ALLOWED
        // ======================================================
        $display("\n>>> CASE 2A: USER (0xB2F1) + Encrypt -> ALLOWED");
        rc4_seed = 64'h0102030405060708;
        fresh_start(16'hB2F1, 1'b0, 64'hAABBCCDDEEFF0011);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        $display("  output=%h (expect non-zero)", enc_result);
        if (auth_fail===1'b0 && enc_result!==64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 2B: USER + Decrypt -> BLOCKED by role
        // ======================================================
        $display("\n>>> CASE 2B: USER (0xB2F1) + Decrypt -> BLOCKED (role)");
        fresh_start(16'hB2F1, 1'b1, 64'hAABBCCDDEEFF0011);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(dec_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 0)", auth_fail, done_latch);
        $display("  output=%h (expect 0)", dec_result);
        if (auth_fail===1'b0 && dec_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 3A: ADMIN + Encrypt (original vector)
        // ======================================================
        original_pt = 64'h1122334455667788;
        rc4_seed    = 64'hDEADBEEFCAFEBABE;
        $display("\n>>> CASE 3A: ADMIN (0xA5C3) + Encrypt");
        $display("  plaintext  = %h", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 3B: ADMIN + Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 3B: ADMIN (0xA5C3) + Decrypt -> round-trip");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h", original_pt);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 4A: ADMIN + "HELLOWOR" Encrypt
        // ======================================================
        original_pt = 64'h48454C4C4F574F52;  // ASCII "HELLOWOR"
        rc4_seed    = 64'h13579BDF02468ACE;
        $display("\n>>> CASE 4A: ADMIN + Plaintext='HELLOWOR' Encrypt");
        $display("  plaintext  = %h  (ASCII: HELLOWOR)", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 4B: ADMIN + "HELLOWOR" Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 4B: ADMIN + Decrypt -> round-trip (HELLOWOR)");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h  (ASCII: HELLOWOR)", original_pt);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 5A: ADMIN + "12345678" Encrypt
        // ======================================================
        original_pt = 64'h3132333435363738;  // ASCII "12345678"
        rc4_seed    = 64'hA1B2C3D4E5F60718;
        $display("\n>>> CASE 5A: ADMIN + Plaintext='12345678' Encrypt");
        $display("  plaintext  = %h  (ASCII: 12345678)", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 5B: ADMIN + "12345678" Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 5B: ADMIN + Decrypt -> round-trip (12345678)");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h  (ASCII: 12345678)", original_pt);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // SUMMARY
        // ======================================================
        $display("\n##################################################");
        $display("#               FINAL SUMMARY                   #");
        $display("##################################################");
        $display("#  KAT : PRESENT ISO vector        -> VERIFIED  #");
        $display("#  1A  : Wrong pwd + Encrypt       -> BLOCKED   #");
        $display("#  1B  : Wrong pwd + Decrypt       -> BLOCKED   #");
        $display("#  2A  : USER  + Encrypt           -> ALLOWED   #");
        $display("#  2B  : USER  + Decrypt           -> BLOCKED   #");
        $display("#  3A  : ADMIN + 1122..7788 Enc    -> ALLOWED   #");
        $display("#  3B  : ADMIN + 1122..7788 Dec    -> ROUND-TRIP#");
        $display("#  4A  : ADMIN + HELLOWOR   Enc    -> ALLOWED   #");
        $display("#  4B  : ADMIN + HELLOWOR   Dec    -> ROUND-TRIP#");
        $display("#  5A  : ADMIN + 12345678   Enc    -> ALLOWED   #");
        $display("#  5B  : ADMIN + 12345678   Dec    -> ROUND-TRIP#");
        $display("##################################################");
        $display("  FINAL: %0d PASSED  |  %0d FAILED", pass_count, fail_count);
        $display("##################################################\n");
        $finish;
    end

    always @(posedge clk) begin
        if (done)
            $display("  [t=%0t ns] done | mode=%0b | auth_fail=%0b",
                     $time, mode_select, auth_fail);
    end

endmodule`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench : tb_hybrid_rc4_present
// DUT       : hybrid_rc4_present (top_module.v)
//
// IMPORTANT : This module is named tb_hybrid_rc4_present
//             Set THIS as simulation top in Vivado
//
// Tests:
//   KAT  : PRESENT-64/80 ISO known answer test
//   1A   : Wrong password + encrypt  -> BLOCKED
//   1B   : Wrong password + decrypt  -> BLOCKED
//   2A   : USER  + encrypt           -> ALLOWED
//   2B   : USER  + decrypt           -> BLOCKED
//   3A   : ADMIN + encrypt           -> ALLOWED
//   3B   : ADMIN + decrypt           -> round-trip
//   4A   : ADMIN + HELLOWOR encrypt  -> ALLOWED
//   4B   : ADMIN + HELLOWOR decrypt  -> round-trip
//   5A   : ADMIN + 12345678 encrypt  -> ALLOWED
//   5B   : ADMIN + 12345678 decrypt  -> round-trip
//////////////////////////////////////////////////////////////////////////////////
module tb_hybrid_rc4_present;   // <-- DIFFERENT name from design module

    // Watchdog
    initial begin #20_000_000; $display("[WATCHDOG] timeout"); $finish; end

    // ---- DUT signals ----
    reg        clk, rst_n;
    reg  [7:0] data_in;
    reg  [1:0] load_sel;
    reg        wr_en;
    reg        mode_select;
    reg  [2:0] out_byte_sel;
    wire [7:0] data_out;
    wire       done;
    wire       auth_fail;

    // ---- Instantiate DUT ----
    // uut is the design, tb_hybrid_rc4_present is the testbench
    hybrid_rc4_present uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .load_sel    (load_sel),
        .wr_en       (wr_en),
        .mode_select (mode_select),
        .out_byte_sel(out_byte_sel),
        .data_out    (data_out),
        .done        (done),
        .auth_fail   (auth_fail)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // ---- Done latch ----
    reg done_latch;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    done_latch <= 1'b0;
        else if (done) done_latch <= 1'b1;
    end

    // ---- KAT: direct PRESENT check (module level, NOT inside initial) ----
    wire [63:0] kat_ct;
    present_encrypt kat_enc (
        .plaintext (64'h0000000000000000),
        .key       (80'h00000000000000000000),
        .ciphertext(kat_ct)
    );

    // =====================================================
    //  Tasks
    // =====================================================

    task read_output;
        output [63:0] result;
        integer i;
        begin
            result = 64'd0;
            for (i = 0; i < 8; i = i + 1) begin
                out_byte_sel = i[2:0]; #1;
                result[63 - i*8 -: 8] = data_out;
            end
        end
    endtask

    task write_password;
        input [15:0] pwd;
        begin
            @(negedge clk); load_sel=2'b00; data_in=pwd[15:8]; wr_en=1; @(posedge clk);
            @(negedge clk); data_in=pwd[7:0];                            @(posedge clk);
            @(negedge clk); wr_en=0;
        end
    endtask

    task write_plaintext;
        input [63:0] pt;
        integer j;
        begin
            for (j=7; j>=0; j=j-1) begin
                @(negedge clk);
                load_sel = 2'b01;
                data_in  = pt[j*8 +: 8];
                wr_en    = 1;
                @(posedge clk);
            end
            @(negedge clk); wr_en=0;
        end
    endtask

    task send_rc4_seed;
        input [63:0] seed;
        integer k;
        begin
            for (k=7; k>=0; k=k-1) begin
                @(negedge clk);
                load_sel = 2'b10;
                data_in  = seed[k*8 +: 8];
                wr_en    = 1;
                @(posedge clk);
            end
            @(negedge clk); wr_en=0;
        end
    endtask

    task fresh_start;
        input [15:0] pwd;
        input        mode;
        input [63:0] pt;
        begin
            rst_n=0; wr_en=0; data_in=0; load_sel=0; mode_select=0;
            repeat(4) @(posedge clk);
            @(negedge clk); rst_n=1;
            mode_select = mode;
            write_password(pwd);
            repeat(3) @(posedge clk);
            write_plaintext(pt);
        end
    endtask

    task wait_for_done;
        integer timeout;
        begin
            timeout=0;
            while (!done_latch && timeout<1200) begin
                @(posedge clk); timeout=timeout+1;
            end
            repeat(3) @(posedge clk); #1;
            if (timeout>=1200) $display("  [TIMEOUT] done never asserted");
        end
    endtask

    task wait_blocked;
        begin repeat(50) @(posedge clk); end
    endtask

    // =====================================================
    //  Test variables
    // =====================================================
    reg [63:0] enc_result, dec_result, original_pt;
    reg [63:0] rc4_seed;
    integer    pass_count, fail_count;

    initial begin
        $dumpfile("tb_hybrid_rc4_present.vcd");
        $dumpvars(0, tb_hybrid_rc4_present);

        pass_count=0; fail_count=0;

        $display("\n##################################################");
        $display("#   HYBRID RC4 -> PRESENT-64/80 TESTBENCH       #");
        $display("##################################################");
        $display("#  RC4 seed : 64-bit (8 bytes, byte-serial)     #");
        $display("#  RC4 out  : 80-bit keystream (10 bytes)       #");
        $display("#  Cipher   : PRESENT-64/80 ISO/IEC 29192-2     #");
        $display("#  ADMIN=0xA5C3 -> Encrypt+Decrypt              #");
        $display("#  USER =0xB2F1 -> Encrypt ONLY                 #");
        $display("#  WRONG=other  -> Blocked                      #");
        $display("##################################################");

        // ======================================================
        // KAT
        // ======================================================
        $display("\n>>> KAT: PRESENT-64/80 ISO Known Answer Test");
        $display("  plaintext = 0000000000000000");
        $display("  key       = 00000000000000000000");
        $display("  expected  = 2844b365c06992a3");
        #1;
        $display("  got       = %h", kat_ct);
        if (kat_ct===64'h2844b365c06992a3) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 1A: Wrong password + Encrypt -> BLOCKED
        // ======================================================
        $display("\n>>> CASE 1A: Wrong Password (0xDEAD) + Encrypt -> BLOCKED");
        rc4_seed = 64'hA1B2C3D4E5F60718;
        fresh_start(16'hDEAD, 1'b0, 64'h0011223344556677);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 1)", auth_fail);
        $display("  output=%h (expect 0)", enc_result);
        if (auth_fail===1'b1 && enc_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 1B: Wrong password + Decrypt -> BLOCKED
        // ======================================================
        $display("\n>>> CASE 1B: Wrong Password (0xDEAD) + Decrypt -> BLOCKED");
        fresh_start(16'hDEAD, 1'b1, 64'hDEADBEEFCAFEBABE);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 1)", auth_fail);
        $display("  output=%h (expect 0)", enc_result);
        if (auth_fail===1'b1 && enc_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 2A: USER + Encrypt -> ALLOWED
        // ======================================================
        $display("\n>>> CASE 2A: USER (0xB2F1) + Encrypt -> ALLOWED");
        rc4_seed = 64'h0102030405060708;
        fresh_start(16'hB2F1, 1'b0, 64'hAABBCCDDEEFF0011);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        $display("  output=%h (expect non-zero)", enc_result);
        if (auth_fail===1'b0 && enc_result!==64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 2B: USER + Decrypt -> BLOCKED by role
        // ======================================================
        $display("\n>>> CASE 2B: USER (0xB2F1) + Decrypt -> BLOCKED (role)");
        fresh_start(16'hB2F1, 1'b1, 64'hAABBCCDDEEFF0011);
        send_rc4_seed(rc4_seed);
        wait_blocked;
        read_output(dec_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 0)", auth_fail, done_latch);
        $display("  output=%h (expect 0)", dec_result);
        if (auth_fail===1'b0 && dec_result===64'd0) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 3A: ADMIN + Encrypt (original vector)
        // ======================================================
        original_pt = 64'h1122334455667788;
        rc4_seed    = 64'hDEADBEEFCAFEBABE;
        $display("\n>>> CASE 3A: ADMIN (0xA5C3) + Encrypt");
        $display("  plaintext  = %h", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 3B: ADMIN + Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 3B: ADMIN (0xA5C3) + Decrypt -> round-trip");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h", original_pt);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 4A: ADMIN + "HELLOWOR" Encrypt
        // ======================================================
        original_pt = 64'h48454C4C4F574F52;  // ASCII "HELLOWOR"
        rc4_seed    = 64'h13579BDF02468ACE;
        $display("\n>>> CASE 4A: ADMIN + Plaintext='HELLOWOR' Encrypt");
        $display("  plaintext  = %h  (ASCII: HELLOWOR)", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 4B: ADMIN + "HELLOWOR" Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 4B: ADMIN + Decrypt -> round-trip (HELLOWOR)");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h  (ASCII: HELLOWOR)", original_pt);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 5A: ADMIN + "12345678" Encrypt
        // ======================================================
        original_pt = 64'h3132333435363738;  // ASCII "12345678"
        rc4_seed    = 64'hA1B2C3D4E5F60718;
        $display("\n>>> CASE 5A: ADMIN + Plaintext='12345678' Encrypt");
        $display("  plaintext  = %h  (ASCII: 12345678)", original_pt);
        $display("  rc4 seed   = %h", rc4_seed);
        fresh_start(16'hA5C3, 1'b0, original_pt);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(enc_result);
        $display("  ciphertext = %h", enc_result);
        $display("  auth_fail=%0b (expect 0)  done=%0b (expect 1)", auth_fail, done_latch);
        if (auth_fail===1'b0 && enc_result!==64'd0 && enc_result!==original_pt) begin
            $display("  RESULT: *** PASS ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // CASE 5B: ADMIN + "12345678" Decrypt -> round-trip
        // ======================================================
        $display("\n>>> CASE 5B: ADMIN + Decrypt -> round-trip (12345678)");
        $display("  input(ct)  = %h", enc_result);
        $display("  rc4 seed   = %h (same)", rc4_seed);
        fresh_start(16'hA5C3, 1'b1, enc_result);
        send_rc4_seed(rc4_seed);
        wait_for_done;
        read_output(dec_result);
        $display("  decrypted  = %h", dec_result);
        $display("  original   = %h  (ASCII: 12345678)", original_pt);
        if (auth_fail===1'b0 && dec_result===original_pt) begin
            $display("  RESULT: *** PASS - PERFECT ROUND-TRIP ***"); pass_count=pass_count+1;
        end else begin
            $display("  RESULT: !!! FAIL !!!"); fail_count=fail_count+1;
        end

        // ======================================================
        // SUMMARY
        // ======================================================
        $display("\n##################################################");
        $display("#               FINAL SUMMARY                   #");
        $display("##################################################");
        $display("#  KAT : PRESENT ISO vector        -> VERIFIED  #");
        $display("#  1A  : Wrong pwd + Encrypt       -> BLOCKED   #");
        $display("#  1B  : Wrong pwd + Decrypt       -> BLOCKED   #");
        $display("#  2A  : USER  + Encrypt           -> ALLOWED   #");
        $display("#  2B  : USER  + Decrypt           -> BLOCKED   #");
        $display("#  3A  : ADMIN + 1122..7788 Enc    -> ALLOWED   #");
        $display("#  3B  : ADMIN + 1122..7788 Dec    -> ROUND-TRIP#");
        $display("#  4A  : ADMIN + HELLOWOR   Enc    -> ALLOWED   #");
        $display("#  4B  : ADMIN + HELLOWOR   Dec    -> ROUND-TRIP#");
        $display("#  5A  : ADMIN + 12345678   Enc    -> ALLOWED   #");
        $display("#  5B  : ADMIN + 12345678   Dec    -> ROUND-TRIP#");
        $display("##################################################");
        $display("  FINAL: %0d PASSED  |  %0d FAILED", pass_count, fail_count);
        $display("##################################################\n");
        $finish;
    end

    always @(posedge clk) begin
        if (done)
            $display("  [t=%0t ns] done | mode=%0b | auth_fail=%0b",
                     $time, mode_select, auth_fail);
    end

endmodule

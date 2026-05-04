// SPDX-License-Identifier: MIT
// SoC Joint Simulation Testbench
// PicoRV32 CPU + NPU + Taxi AXI Interconnect
//
// Usage:
//   VCS:  vcs -sverilog -top soc_testbench ...
//   With VCD:  +vcd
//   With FSDB: +fsdb

`resetall
`timescale 1ns / 1ps
`default_nettype none

module soc_testbench;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter real HALF_CLK_PERIOD = 5.0;  // 100 MHz
    parameter integer RESET_CYCLES = 20;
    parameter integer TIMEOUT_CYCLES = 5000000;  // 5M cycles max

    // ========================================================================
    // Signals
    // ========================================================================
    reg        clk;
    reg        resetn;
    wire       trap;
    wire       tests_passed;
    wire       trace_valid;
    wire [35:0] trace_data;

    // ========================================================================
    // Plusarg parsing
    // ========================================================================
    reg        dump_vcd;
    reg        dump_fsdb;

    initial begin
        dump_vcd  = 1'b0;
        dump_fsdb = 1'b0;

        if ($test$plusargs("vcd")) begin
            dump_vcd = 1'b1;
            $display("[TB] VCD waveform dumping enabled");
        end
        if ($test$plusargs("fsdb")) begin
            dump_fsdb = 1'b1;
            $display("[TB] FSDB waveform dumping enabled");
        end
    end

    // ========================================================================
    // Clock generation
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #HALF_CLK_PERIOD clk = ~clk;
    end

    // ========================================================================
    // Reset generation
    // ========================================================================
    initial begin
        resetn = 1'b0;
        repeat (RESET_CYCLES) @(posedge clk);
        resetn = 1'b1;
        $display("[TB] Reset released at %0t", $time);
    end

    // ========================================================================
    // Waveform dumping
    // ========================================================================
    initial begin
        if (dump_vcd) begin
            $dumpfile("sim/soc_testbench.vcd");
            $dumpvars(0, soc_testbench);
            $display("[TB] Dumping VCD to sim/soc_testbench.vcd");
        end
    end

    // Use FSDB dumping via Verdi (VCS flow)
    `ifdef FSDB_DUMP
    initial begin
        if (dump_fsdb) begin
            $fsdbDumpfile("sim/soc_testbench.fsdb");
            $fsdbDumpvars(0, soc_testbench);
            $display("[TB] Dumping FSDB to sim/soc_testbench.fsdb");
        end
    end
    `endif

    // ========================================================================
    // DUT: SoC Top
    // ========================================================================
    soc_top #(
        .FIRMWARE_HEX("firmware/soc_firmware.hex")
    ) u_soc (
        .clk          (clk),
        .resetn       (resetn),
        .trap         (trap),
        .tests_passed (tests_passed),
        .trace_valid  (trace_valid),
        .trace_data   (trace_data)
    );

    // ========================================================================
    // Trap monitoring
    // ========================================================================
    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[TB] *** CPU TRAP asserted at %0t ***", $time);
            if (!tests_passed) begin
                $display("[TB] *** TESTS FAILED (trap before pass) ***");
            end
            $finish;
        end
    end

    // ========================================================================
    // Test-pass monitoring
    // ========================================================================
    always @(posedge clk) begin
        if (resetn && tests_passed) begin
            $display("[TB] *** ALL TESTS PASSED at %0t ***", $time);
            $finish;
        end
    end

    // ========================================================================
    // Timeout watchdog
    // ========================================================================
    integer cycle_count;
    initial begin
        cycle_count = 0;
        repeat (TIMEOUT_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("[TB] *** TIMEOUT after %0d cycles ***", cycle_count);
        $display("[TB] tests_passed = %0b, trap = %0b", tests_passed, trap);
        $finish;
    end

    // ========================================================================
    // Trace output (optional)
    // ========================================================================
    always @(posedge clk) begin
        if (resetn && trace_valid) begin
            $fwrite(32'h8000_0001, "[TRACE] pc=%08h insn=%08h\n",
                    trace_data[35:4], trace_data[3:0]);
        end
    end

endmodule

`resetall

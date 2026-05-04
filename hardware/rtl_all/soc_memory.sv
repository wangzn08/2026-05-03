// SPDX-License-Identifier: MIT
// SoC Shared Memory: AXI Full slave with MMIO support
//
// Features:
//   - 2 MB on-chip memory (524288 x 32-bit)
//   - Supports single-beat and burst AXI4 transactions
//   - Console output: writes to 0x1000_0000 print a character
//   - Test-pass: writing 123456789 to 0x2000_0000 sets tests_passed
//   - Optional firmware preload via $readmemh

`resetall
`timescale 1ns / 1ps
`default_nettype none

module soc_memory #(
    parameter integer DATA_W     = 32,
    parameter integer ADDR_W     = 32,
    parameter integer ID_W       = 4,
    parameter integer MEM_DEPTH  = 2*1024*1024/4,  // 2 MB in 32-bit words
    // Console MMIO address
    parameter [31:0] CONSOLE_ADDR = 32'h1000_0000,
    // Test-pass MMIO address
    parameter [31:0] TESTPASS_ADDR = 32'h2000_0000,
    // Firmware hex file (empty = skip preload)
    parameter string  FIRMWARE_HEX = ""
) (
    input wire logic clk,
    input wire logic rst,

    taxi_axi_if.wr_slv s_axi_wr,
    taxi_axi_if.rd_slv s_axi_rd,

    output reg        tests_passed
);

    // Memory array
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:MEM_DEPTH-1];

    // Write burst state
    reg        in_write_burst;
    reg [31:0] wr_addr;
    reg [7:0]  wr_burst_len;
    reg [7:0]  wr_cnt;
    reg [ID_W-1:0] wr_id;

    // Read burst state
    reg        in_read_burst;
    reg [31:0] rd_addr;
    reg [7:0]  rd_burst_len;
    reg [7:0]  rd_cnt;
    reg [ID_W-1:0] rd_id;

    // ========================================================================
    // Firmware preload
    // ========================================================================
    initial begin
        if (FIRMWARE_HEX != "") begin
            $readmemh(FIRMWARE_HEX, mem);
            $display("[soc_memory] Loaded firmware from %s", FIRMWARE_HEX);
        end
    end

    // ========================================================================
    // MMIO handling function
    // ========================================================================
    function automatic logic is_console(input [31:0] addr);
        return (addr == CONSOLE_ADDR);
    endfunction

    function automatic logic is_testpass(input [31:0] addr);
        return (addr == TESTPASS_ADDR);
    endfunction

    // ========================================================================
    // Write address channel
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_wr.awready <= 1'b0;
            in_write_burst   <= 1'b0;
        end else begin
            s_axi_wr.awready <= 1'b0;
            if (s_axi_wr.awvalid && !in_write_burst) begin
                s_axi_wr.awready <= 1'b1;
                wr_addr          <= s_axi_wr.awaddr;
                wr_burst_len     <= s_axi_wr.awlen;
                wr_cnt           <= 8'd0;
                wr_id            <= s_axi_wr.awid[ID_W-1:0];
                in_write_burst   <= 1'b1;
            end
        end
    end

    // ========================================================================
    // Write data channel
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_wr.wready <= 1'b0;
        end else begin
            s_axi_wr.wready <= in_write_burst;

            if (s_axi_wr.wvalid && s_axi_wr.wready && in_write_burst) begin
                // MMIO: console output
                if (is_console(wr_addr)) begin
                    $write("%c", s_axi_wr.wdata[7:0]);
                end
                // MMIO: test-pass detection
                else if (is_testpass(wr_addr) && s_axi_wr.wdata == 32'd123456789) begin
                    tests_passed <= 1'b1;
                    $display("\n*** TESTS PASSED ***");
                end
                // Normal memory write (within bounds)
                else if (wr_addr < (MEM_DEPTH * 4)) begin
                    if (s_axi_wr.wstrb[0]) mem[wr_addr >> 2][ 7: 0] <= s_axi_wr.wdata[ 7: 0];
                    if (s_axi_wr.wstrb[1]) mem[wr_addr >> 2][15: 8] <= s_axi_wr.wdata[15: 8];
                    if (s_axi_wr.wstrb[2]) mem[wr_addr >> 2][23:16] <= s_axi_wr.wdata[23:16];
                    if (s_axi_wr.wstrb[3]) mem[wr_addr >> 2][31:24] <= s_axi_wr.wdata[31:24];
                end

                wr_addr <= wr_addr + 32'd4;
                wr_cnt  <= wr_cnt + 8'd1;

                if (s_axi_wr.wlast) begin
                    in_write_burst   <= 1'b0;
                    s_axi_wr.wready  <= 1'b0;
                end
            end
        end
    end

    // ========================================================================
    // Write response channel
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_wr.bvalid <= 1'b0;
        end else begin
            if (s_axi_wr.wvalid && s_axi_wr.wready && in_write_burst && s_axi_wr.wlast) begin
                s_axi_wr.bvalid <= 1'b1;
                s_axi_wr.bresp  <= 2'b00;  // OKAY
                s_axi_wr.bid    <= wr_id;
            end else if (s_axi_wr.bvalid && s_axi_wr.bready) begin
                s_axi_wr.bvalid <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Read address channel
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_rd.arready <= 1'b0;
            in_read_burst    <= 1'b0;
        end else begin
            s_axi_rd.arready <= 1'b0;
            if (s_axi_rd.arvalid && !in_read_burst) begin
                s_axi_rd.arready <= 1'b1;
                rd_addr          <= s_axi_rd.araddr;
                rd_burst_len     <= s_axi_rd.arlen;
                rd_cnt           <= 8'd0;
                rd_id            <= s_axi_rd.arid[ID_W-1:0];
                in_read_burst    <= 1'b1;
            end
        end
    end

    // ========================================================================
    // Read data channel
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_rd.rvalid <= 1'b0;
            s_axi_rd.rlast  <= 1'b0;
        end else if (in_read_burst) begin
            if (!s_axi_rd.rvalid || s_axi_rd.rready) begin
                if (rd_cnt <= rd_burst_len) begin
                    // Read from memory (with bounds check)
                    if ((rd_addr >> 2) + rd_cnt < MEM_DEPTH)
                        s_axi_rd.rdata <= mem[(rd_addr >> 2) + rd_cnt];
                    else
                        s_axi_rd.rdata <= 32'hDEAD_BEEF;

                    s_axi_rd.rvalid <= 1'b1;
                    s_axi_rd.rresp  <= 2'b00;  // OKAY
                    s_axi_rd.rid    <= rd_id;
                    s_axi_rd.rlast  <= (rd_cnt == rd_burst_len) ? 1'b1 : 1'b0;
                    rd_cnt <= rd_cnt + 8'd1;
                end else begin
                    s_axi_rd.rvalid <= 1'b0;
                    s_axi_rd.rlast  <= 1'b0;
                    in_read_burst   <= 1'b0;
                end
            end
        end else begin
            s_axi_rd.rvalid <= 1'b0;
            s_axi_rd.rlast  <= 1'b0;
        end
    end

    // ========================================================================
    // Tie off unused AXI slave outputs
    // ========================================================================
    assign s_axi_wr.buser = '0;
    assign s_axi_rd.ruser = '0;

endmodule

`resetall

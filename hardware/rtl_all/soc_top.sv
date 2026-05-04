// SPDX-License-Identifier: MIT
// SoC Top-Level: PicoRV32 CPU + NPU + Taxi AXI Interconnect
//
// Architecture:
//   CPU (AXI-Lite) → cpu_axi_bridge → taxi_axil_crossbar_1s ─┬→ NPU slave regs
//                                                             └→ axil→axi adapter
//   NPU (AXI Full) → npu_axi_master_bridge ─────────────────────→ taxi_axi_interconnect
//   axil→axi adapter ───────────────────────────────────────────→ taxi_axi_interconnect
//   taxi_axi_interconnect ──────────────────────────────────────→ soc_memory
//
// Address Map:
//   0x0000_0000 - 0x0FFF_FFFF : Shared memory (256 MB region, 2 MB populated)
//   0x1000_0000               : Console output (MMIO)
//   0x2000_0000               : Test-pass register (MMIO)
//   0x4000_0000 - 0x4000_000F : NPU control registers

`resetall
`timescale 1ns / 1ps
`default_nettype none

module soc_top #(
    parameter string FIRMWARE_HEX = "firmware/firmware.hex",
    // CPU configuration
    parameter [ 0:0] CPU_COMPRESSED_ISA = 1,
    parameter [ 0:0] CPU_ENABLE_MUL     = 1,
    parameter [ 0:0] CPU_ENABLE_DIV     = 1,
    parameter [ 0:0] CPU_ENABLE_IRQ     = 1,
    parameter [ 0:0] CPU_ENABLE_TRACE   = 1,
    parameter [31:0] CPU_PROGADDR_RESET = 32'h0000_0000,
    parameter [31:0] CPU_STACKADDR      = 32'hffff_ffff,
    // NPU configuration
    parameter integer NPU_M_BURST_LEN   = 68,
    parameter [31:0] NPU_M_BASE_ADDR    = 32'h0000_0000
) (
    input wire logic clk,
    input wire logic resetn,        // active-low reset (CPU convention)

    output wire        trap,
    output wire        tests_passed,

    // Trace output
    output wire        trace_valid,
    output wire [35:0] trace_data
);

    // ========================================================================
    // Local signals
    // ========================================================================
    wire        cpu_awvalid,  cpu_awready;
    wire [31:0] cpu_awaddr;
    wire [ 2:0] cpu_awprot;
    wire        cpu_wvalid,   cpu_wready;
    wire [31:0] cpu_wdata;
    wire [ 3:0] cpu_wstrb;
    wire        cpu_bvalid,   cpu_bready;
    wire        cpu_arvalid,  cpu_arready;
    wire [31:0] cpu_araddr;
    wire [ 2:0] cpu_arprot;
    wire        cpu_rvalid,   cpu_rready;
    wire [31:0] cpu_rdata;

    // NPU slave (AXI-Lite, 4-bit address)
    wire [ 3:0] npu_s_awaddr,  npu_s_awvalid,  npu_s_awready;
    wire        npu_s_wready;
    wire [31:0] npu_s_wdata;
    wire [ 3:0] npu_s_wstrb;
    wire        npu_s_wvalid;
    wire [ 1:0] npu_s_bresp;
    wire        npu_s_bvalid;
    wire        npu_s_bready;
    wire [ 3:0] npu_s_araddr;
    wire [ 2:0] npu_s_arprot;
    wire        npu_s_arvalid,  npu_s_arready;
    wire [31:0] npu_s_rdata;
    wire [ 1:0] npu_s_rresp;
    wire        npu_s_rvalid;
    wire        npu_s_rready;

    // NPU master (AXI Full)
    wire [ 0:0] npu_m_awid;
    wire [31:0] npu_m_awaddr;
    wire [ 7:0] npu_m_awlen;
    wire [ 2:0] npu_m_awsize;
    wire [ 1:0] npu_m_awburst;
    wire        npu_m_awlock;
    wire [ 3:0] npu_m_awcache;
    wire [ 2:0] npu_m_awprot;
    wire [ 3:0] npu_m_awqos;
    wire        npu_m_awvalid,  npu_m_awready;
    wire [31:0] npu_m_wdata;
    wire [ 3:0] npu_m_wstrb;
    wire        npu_m_wlast;
    wire        npu_m_wvalid,   npu_m_wready;
    wire [ 0:0] npu_m_bid;
    wire [ 1:0] npu_m_bresp;
    wire        npu_m_bvalid,   npu_m_bready;
    wire [ 0:0] npu_m_arid;
    wire [31:0] npu_m_araddr;
    wire [ 7:0] npu_m_arlen;
    wire [ 2:0] npu_m_arsize;
    wire [ 1:0] npu_m_arburst;
    wire        npu_m_arlock;
    wire [ 3:0] npu_m_arcache;
    wire [ 2:0] npu_m_arprot;
    wire [ 3:0] npu_m_arqos;
    wire        npu_m_arvalid,  npu_m_arready;
    wire [ 0:0] npu_m_rid;
    wire [31:0] npu_m_rdata;
    wire [ 1:0] npu_m_rresp;
    wire        npu_m_rlast;
    wire        npu_m_rvalid,   npu_m_rready;

    // ========================================================================
    // Taxi interfaces
    // ========================================================================
    // CPU AXI-Lite interface
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) cpu_axil_wr_if ();
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) cpu_axil_rd_if ();

    // Crossbar → NPU slave (AXI-Lite, split wr/rd)
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) xbar_npu_wr_if ();
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) xbar_npu_rd_if ();

    // Crossbar → AXI-Lite-to-AXI adapter
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) xbar_mem_wr_if ();
    taxi_axil_if #(.DATA_W(32), .ADDR_W(32)) xbar_mem_rd_if ();

    // Adapter → Interconnect (AXI Full, split wr/rd)
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) cpu_mem_wr_if ();
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) cpu_mem_rd_if ();

    // NPU master → Interconnect (AXI Full, split wr/rd)
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) npu_mem_wr_if ();
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) npu_mem_rd_if ();

    // Interconnect → Memory (AXI Full, split wr/rd)
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) mem_wr_if ();
    taxi_axi_if #(.DATA_W(32), .ADDR_W(32), .ID_W(4)) mem_rd_if ();

    // ========================================================================
    // PicoRV32 CPU (AXI-Lite master)
    // ========================================================================
    picorv32_axi #(
        .COMPRESSED_ISA(CPU_COMPRESSED_ISA),
        .ENABLE_MUL    (CPU_ENABLE_MUL),
        .ENABLE_DIV    (CPU_ENABLE_DIV),
        .ENABLE_IRQ    (CPU_ENABLE_IRQ),
        .ENABLE_TRACE  (CPU_ENABLE_TRACE),
        .PROGADDR_RESET(CPU_PROGADDR_RESET),
        .STACKADDR     (CPU_STACKADDR),
        .REGS_INIT_ZERO(1),
        .LATCHED_IRQ   (32'hffff_ffff),
        .MASKED_IRQ    (32'h0000_0000)
    ) u_cpu (
        .clk             (clk),
        .resetn          (resetn),
        .trap            (trap),
        .mem_axi_awvalid (cpu_awvalid),
        .mem_axi_awready (cpu_awready),
        .mem_axi_awaddr  (cpu_awaddr),
        .mem_axi_awprot  (cpu_awprot),
        .mem_axi_wvalid  (cpu_wvalid),
        .mem_axi_wready  (cpu_wready),
        .mem_axi_wdata   (cpu_wdata),
        .mem_axi_wstrb   (cpu_wstrb),
        .mem_axi_bvalid  (cpu_bvalid),
        .mem_axi_bready  (cpu_bready),
        .mem_axi_arvalid (cpu_arvalid),
        .mem_axi_arready (cpu_arready),
        .mem_axi_araddr  (cpu_araddr),
        .mem_axi_arprot  (cpu_arprot),
        .mem_axi_rvalid  (cpu_rvalid),
        .mem_axi_rready  (cpu_rready),
        .mem_axi_rdata   (cpu_rdata),
        .irq             (32'd0),
        .eoi             (),
        .trace_valid     (trace_valid),
        .trace_data      (trace_data),
        // PCPI left unconnected
        .pcpi_valid      (),
        .pcpi_insn       (),
        .pcpi_rs1        (),
        .pcpi_rs2        (),
        .pcpi_wr         (1'b0),
        .pcpi_rd         (32'd0),
        .pcpi_wait       (1'b0),
        .pcpi_ready      (1'b0)
    );

    // ========================================================================
    // CPU AXI-Lite bridge: flat signals → taxi interfaces
    // ========================================================================
    cpu_axi_bridge u_cpu_bridge (
        .mem_axi_awvalid (cpu_awvalid),
        .mem_axi_awready (cpu_awready),
        .mem_axi_awaddr  (cpu_awaddr),
        .mem_axi_awprot  (cpu_awprot),
        .mem_axi_wvalid  (cpu_wvalid),
        .mem_axi_wready  (cpu_wready),
        .mem_axi_wdata   (cpu_wdata),
        .mem_axi_wstrb   (cpu_wstrb),
        .mem_axi_bvalid  (cpu_bvalid),
        .mem_axi_bready  (cpu_bready),
        .mem_axi_arvalid (cpu_arvalid),
        .mem_axi_arready (cpu_arready),
        .mem_axi_araddr  (cpu_araddr),
        .mem_axi_arprot  (cpu_arprot),
        .mem_axi_rvalid  (cpu_rvalid),
        .mem_axi_rready  (cpu_rready),
        .mem_axi_rdata   (cpu_rdata),
        .m_axil_wr       (cpu_axil_wr_if),
        .m_axil_rd       (cpu_axil_rd_if)
    );

    // ========================================================================
    // AXI-Lite Crossbar (1 slave → 2 masters)
    //   m_axil[0] → NPU control registers  (0x4000_0000)
    //   m_axil[1] → Memory (via AXI-Lite→AXI adapter)
    // ========================================================================
    taxi_axil_crossbar_1s #(
        .M_COUNT       (2),
        .ADDR_W        (32),
        .M_REGIONS     (1),
        // master[0] = NPU slave:   base=0x4000_0000, addr_w=4
        // master[1] = Memory path: base=0x0000_0000, addr_w=28
        .M_BASE_ADDR   ({32'h0000_0000, 32'h4000_0000}),
        .M_ADDR_W      ({32'd30, 32'd4}),  // 1GB memory region covers 0x00000000-0x3FFFFFFF
        .S_ACCEPT      (32'd4),
        .M_ISSUE       ({32'd4, 32'd4}),
        .M_SECURE      (2'b00),
        // Pipeline: minimal buffering for simplicity
        .S_AW_REG_TYPE (2'd0),
        .S_W_REG_TYPE  (2'd0),
        .S_B_REG_TYPE  (2'd0),
        .S_AR_REG_TYPE (2'd0),
        .S_R_REG_TYPE  (2'd0),
        .M_AW_REG_TYPE ({2{2'd0}}),
        .M_W_REG_TYPE  ({2{2'd0}}),
        .M_B_REG_TYPE  ({2{2'd0}}),
        .M_AR_REG_TYPE ({2{2'd0}}),
        .M_R_REG_TYPE  ({2{2'd0}})
    ) u_axil_crossbar (
        .clk        (clk),
        .rst        (~resetn),     // taxi uses active-high reset
        .s_axil_wr  (cpu_axil_wr_if),
        .s_axil_rd  (cpu_axil_rd_if),
        .m_axil_wr  ({xbar_mem_wr_if, xbar_npu_wr_if}),
        .m_axil_rd  ({xbar_mem_rd_if, xbar_npu_rd_if})
    );

    // ========================================================================
    // NPU AXI-Lite slave bridge: taxi interfaces → NPU flat signals
    // ========================================================================
    npu_axi_slave_bridge #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(4)
    ) u_npu_slave_bridge (
        .s_axil_wr    (xbar_npu_wr_if),
        .s_axil_rd    (xbar_npu_rd_if),
        .s_axi_awaddr (npu_s_awaddr),
        .s_axi_awvalid(npu_s_awvalid),
        .s_axi_awready(npu_s_awready),
        .s_axi_wdata  (npu_s_wdata),
        .s_axi_wstrb  (npu_s_wstrb),
        .s_axi_wvalid (npu_s_wvalid),
        .s_axi_wready (npu_s_wready),
        .s_axi_bresp  (npu_s_bresp),
        .s_axi_bvalid (npu_s_bvalid),
        .s_axi_bready (npu_s_bready),
        .s_axi_araddr (npu_s_araddr),
        .s_axi_arprot (npu_s_arprot),
        .s_axi_arvalid(npu_s_arvalid),
        .s_axi_arready(npu_s_arready),
        .s_axi_rdata  (npu_s_rdata),
        .s_axi_rresp  (npu_s_rresp),
        .s_axi_rvalid (npu_s_rvalid),
        .s_axi_rready (npu_s_rready)
    );

    // ========================================================================
    // NPU Top Wrapper
    // ========================================================================
    npu_top_wrapper #(
        .C_S_AXI_DATA_WIDTH        (32),
        .C_S_AXI_ADDR_WIDTH        (4),
        .C_M_AXI_DATA_WIDTH        (32),
        .C_M_AXI_ADDR_WIDTH        (32),
        .C_M_AXI_BURST_LEN         (NPU_M_BURST_LEN),
        .C_M_AXI_ID_WIDTH          (1),
        .C_M_TARGET_SLAVE_BASE_ADDR(NPU_M_BASE_ADDR)
    ) u_npu (
        .aclk          (clk),
        .aresetn       (resetn),       // both CPU and NPU use active-low reset
        // AXI-Lite slave (CPU control)
        .s_axi_awaddr  (npu_s_awaddr),
        .s_axi_awvalid (npu_s_awvalid),
        .s_axi_awready (npu_s_awready),
        .s_axi_wdata   (npu_s_wdata),
        .s_axi_wstrb   (npu_s_wstrb),
        .s_axi_wvalid  (npu_s_wvalid),
        .s_axi_wready  (npu_s_wready),
        .s_axi_bresp   (npu_s_bresp),
        .s_axi_bvalid  (npu_s_bvalid),
        .s_axi_bready  (npu_s_bready),
        .s_axi_araddr  (npu_s_araddr),
        .s_axi_arprot  (npu_s_arprot),
        .s_axi_arvalid (npu_s_arvalid),
        .s_axi_arready (npu_s_arready),
        .s_axi_rdata   (npu_s_rdata),
        .s_axi_rresp   (npu_s_rresp),
        .s_axi_rvalid  (npu_s_rvalid),
        .s_axi_rready  (npu_s_rready),
        // AXI Full master (DMA)
        .m_axi_awid    (npu_m_awid),
        .m_axi_awaddr  (npu_m_awaddr),
        .m_axi_awlen   (npu_m_awlen),
        .m_axi_awsize  (npu_m_awsize),
        .m_axi_awburst (npu_m_awburst),
        .m_axi_awlock  (npu_m_awlock),
        .m_axi_awcache (npu_m_awcache),
        .m_axi_awprot  (npu_m_awprot),
        .m_axi_awqos   (npu_m_awqos),
        .m_axi_awvalid (npu_m_awvalid),
        .m_axi_awready (npu_m_awready),
        .m_axi_wdata   (npu_m_wdata),
        .m_axi_wstrb   (npu_m_wstrb),
        .m_axi_wlast   (npu_m_wlast),
        .m_axi_wvalid  (npu_m_wvalid),
        .m_axi_wready  (npu_m_wready),
        .m_axi_bid     (npu_m_bid),
        .m_axi_bresp   (npu_m_bresp),
        .m_axi_bvalid  (npu_m_bvalid),
        .m_axi_bready  (npu_m_bready),
        .m_axi_arid    (npu_m_arid),
        .m_axi_araddr  (npu_m_araddr),
        .m_axi_arlen   (npu_m_arlen),
        .m_axi_arsize  (npu_m_arsize),
        .m_axi_arburst (npu_m_arburst),
        .m_axi_arlock  (npu_m_arlock),
        .m_axi_arcache (npu_m_arcache),
        .m_axi_arprot  (npu_m_arprot),
        .m_axi_arqos   (npu_m_arqos),
        .m_axi_arvalid (npu_m_arvalid),
        .m_axi_arready (npu_m_arready),
        .m_axi_rid     (npu_m_rid),
        .m_axi_rdata   (npu_m_rdata),
        .m_axi_rresp   (npu_m_rresp),
        .m_axi_rlast   (npu_m_rlast),
        .m_axi_rvalid  (npu_m_rvalid),
        .m_axi_rready  (npu_m_rready)
    );

    // ========================================================================
    // NPU AXI Full master bridge: flat signals → taxi interfaces
    // ========================================================================
    npu_axi_master_bridge #(
        .C_M_AXI_DATA_WIDTH(32),
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_ID_WIDTH  (1)
    ) u_npu_master_bridge (
        .m_axi_awid    (npu_m_awid),
        .m_axi_awaddr  (npu_m_awaddr),
        .m_axi_awlen   (npu_m_awlen),
        .m_axi_awsize  (npu_m_awsize),
        .m_axi_awburst (npu_m_awburst),
        .m_axi_awlock  (npu_m_awlock),
        .m_axi_awcache (npu_m_awcache),
        .m_axi_awprot  (npu_m_awprot),
        .m_axi_awqos   (npu_m_awqos),
        .m_axi_awvalid (npu_m_awvalid),
        .m_axi_awready (npu_m_awready),
        .m_axi_wdata   (npu_m_wdata),
        .m_axi_wstrb   (npu_m_wstrb),
        .m_axi_wlast   (npu_m_wlast),
        .m_axi_wvalid  (npu_m_wvalid),
        .m_axi_wready  (npu_m_wready),
        .m_axi_bid     (npu_m_bid),
        .m_axi_bresp   (npu_m_bresp),
        .m_axi_bvalid  (npu_m_bvalid),
        .m_axi_bready  (npu_m_bready),
        .m_axi_arid    (npu_m_arid),
        .m_axi_araddr  (npu_m_araddr),
        .m_axi_arlen   (npu_m_arlen),
        .m_axi_arsize  (npu_m_arsize),
        .m_axi_arburst (npu_m_arburst),
        .m_axi_arlock  (npu_m_arlock),
        .m_axi_arcache (npu_m_arcache),
        .m_axi_arprot  (npu_m_arprot),
        .m_axi_arqos   (npu_m_arqos),
        .m_axi_arvalid (npu_m_arvalid),
        .m_axi_arready (npu_m_arready),
        .m_axi_rid     (npu_m_rid),
        .m_axi_rdata   (npu_m_rdata),
        .m_axi_rresp   (npu_m_rresp),
        .m_axi_rlast   (npu_m_rlast),
        .m_axi_rvalid  (npu_m_rvalid),
        .m_axi_rready  (npu_m_rready),
        .m_axi_wr      (npu_mem_wr_if),
        .m_axi_rd      (npu_mem_rd_if)
    );

    // ========================================================================
    // AXI-Lite to AXI Full adapter (CPU memory path)
    // ========================================================================
    taxi_axil_axi_adapter u_axil_axi_adapter (
        .clk       (clk),
        .rst       (~resetn),
        .s_axil_wr (xbar_mem_wr_if),
        .s_axil_rd (xbar_mem_rd_if),
        .m_axi_wr  (cpu_mem_wr_if),
        .m_axi_rd  (cpu_mem_rd_if)
    );

    // ========================================================================
    // AXI Full Interconnect (2 slaves → 1 master)
    //   s_axi[0] ← CPU memory path (via AXI-Lite→AXI adapter)
    //   s_axi[1] ← NPU DMA master
    //   m_axi[0] → Shared memory
    // ========================================================================
    taxi_axi_interconnect #(
        .S_COUNT      (2),
        .M_COUNT      (1),
        .ADDR_W       (32),
        .M_REGIONS    (1),
        .M_BASE_ADDR  ('0),            // auto-compute from M_ADDR_W
        .M_ADDR_W     ({1{32'd30}}),   // 1 GB region covers 0x00000000-0x3FFFFFFF
        .M_CONNECT_RD ({1{2'b11}}),    // both slaves can read memory
        .M_CONNECT_WR ({1{2'b11}})     // both slaves can write memory
    ) u_axi_interconnect (
        .clk       (clk),
        .rst       (~resetn),
        .s_axi_wr  ({npu_mem_wr_if, cpu_mem_wr_if}),
        .s_axi_rd  ({npu_mem_rd_if, cpu_mem_rd_if}),
        .m_axi_wr  ({mem_wr_if}),
        .m_axi_rd  ({mem_rd_if})
    );

    // ========================================================================
    // Shared Memory (AXI Full slave)
    // ========================================================================
    soc_memory #(
        .DATA_W      (32),
        .ADDR_W      (32),
        .ID_W        (4),
        .MEM_DEPTH   (2*1024*1024/4),  // 2 MB
        .FIRMWARE_HEX(FIRMWARE_HEX)
    ) u_memory (
        .clk          (clk),
        .rst          (~resetn),
        .s_axi_wr     (mem_wr_if),
        .s_axi_rd     (mem_rd_if),
        .tests_passed (tests_passed)
    );

endmodule

`resetall

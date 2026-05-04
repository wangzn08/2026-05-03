// SPDX-License-Identifier: MIT
// SoC Bridge Modules: Flat AXI signals <-> Taxi SystemVerilog interfaces
//
// Three thin wrappers that bridge between the project's flat Verilog AXI
// signals and the taxi library's SystemVerilog interface + modport convention.

`resetall
`timescale 1ns / 1ps
`default_nettype none

// ==========================================================================
// cpu_axi_bridge: PicoRV32 flat AXI-Lite master -> taxi_axil_if wr_mst/rd_mst
// ==========================================================================
module cpu_axi_bridge (
    // Flat AXI-Lite signals (connect to picorv32_axi mem_axi_* ports)
    // The CPU is the AXI-Lite master. Bridge receives from CPU on the flat
    // side and drives the taxi interface on the other side. Directions are
    // the MIRROR of picorv32_axi's port directions.
    // Write address channel (CPU → bridge → taxi)
    input  wire        mem_axi_awvalid,
    output wire        mem_axi_awready,
    input  wire [31:0] mem_axi_awaddr,
    input  wire [ 2:0] mem_axi_awprot,

    // Write data channel (CPU → bridge → taxi)
    input  wire        mem_axi_wvalid,
    output wire        mem_axi_wready,
    input  wire [31:0] mem_axi_wdata,
    input  wire [ 3:0] mem_axi_wstrb,

    // Write response channel (taxi → bridge → CPU)
    output wire        mem_axi_bvalid,
    input  wire        mem_axi_bready,

    // Read address channel (CPU → bridge → taxi)
    input  wire        mem_axi_arvalid,
    output wire        mem_axi_arready,
    input  wire [31:0] mem_axi_araddr,
    input  wire [ 2:0] mem_axi_arprot,

    // Read data channel (taxi → bridge → CPU)
    output wire        mem_axi_rvalid,
    input  wire        mem_axi_rready,
    output wire [31:0] mem_axi_rdata,

    // Taxi AXI-Lite master interfaces (connect to crossbar slave port)
    taxi_axil_if.wr_mst m_axil_wr,
    taxi_axil_if.rd_mst m_axil_rd
);

    // Write address channel
    assign m_axil_wr.awaddr  = mem_axi_awaddr;
    assign m_axil_wr.awprot  = mem_axi_awprot;
    assign m_axil_wr.awvalid = mem_axi_awvalid;
    assign mem_axi_awready   = m_axil_wr.awready;

    // Write data channel
    assign m_axil_wr.wdata   = mem_axi_wdata;
    assign m_axil_wr.wstrb   = mem_axi_wstrb;
    assign m_axil_wr.wvalid  = mem_axi_wvalid;
    assign mem_axi_wready    = m_axil_wr.wready;

    // Write response channel
    assign mem_axi_bvalid    = m_axil_wr.bvalid;
    assign m_axil_wr.bready  = mem_axi_bready;

    // Read address channel
    assign m_axil_rd.araddr  = mem_axi_araddr;
    assign m_axil_rd.arprot  = mem_axi_arprot;
    assign m_axil_rd.arvalid = mem_axi_arvalid;
    assign mem_axi_arready   = m_axil_rd.arready;

    // Read data channel
    assign mem_axi_rvalid    = m_axil_rd.rvalid;
    assign m_axil_rd.rready  = mem_axi_rready;
    assign mem_axi_rdata     = m_axil_rd.rdata;

    // Tie off unused user signals
    assign m_axil_wr.awuser  = '0;
    assign m_axil_wr.wuser   = '0;
    assign m_axil_rd.aruser  = '0;

endmodule


// ==========================================================================
// npu_axi_master_bridge: NPU flat AXI Full master -> taxi_axi_if wr_mst/rd_mst
// ==========================================================================
module npu_axi_master_bridge #(
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_ID_WIDTH   = 1
) (
    // Flat AXI Full master signals (connect to npu_top_wrapper m_axi_* ports)
    // Write address channel
    input  wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_awid,
    input  wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    input  wire [7:0]                    m_axi_awlen,
    input  wire [2:0]                    m_axi_awsize,
    input  wire [1:0]                    m_axi_awburst,
    input  wire                          m_axi_awlock,
    input  wire [3:0]                    m_axi_awcache,
    input  wire [2:0]                    m_axi_awprot,
    input  wire [3:0]                    m_axi_awqos,
    input  wire                          m_axi_awvalid,
    output wire                          m_axi_awready,

    // Write data channel
    input  wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    input  wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    input  wire                          m_axi_wlast,
    input  wire                          m_axi_wvalid,
    output wire                          m_axi_wready,

    // Write response channel
    output wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_bid,
    output wire [1:0]                    m_axi_bresp,
    output wire                          m_axi_bvalid,
    input  wire                          m_axi_bready,

    // Read address channel
    input  wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_arid,
    input  wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    input  wire [7:0]                    m_axi_arlen,
    input  wire [2:0]                    m_axi_arsize,
    input  wire [1:0]                    m_axi_arburst,
    input  wire                          m_axi_arlock,
    input  wire [3:0]                    m_axi_arcache,
    input  wire [2:0]                    m_axi_arprot,
    input  wire [3:0]                    m_axi_arqos,
    input  wire                          m_axi_arvalid,
    output wire                          m_axi_arready,

    // Read data channel
    output wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_rid,
    output wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    output wire [1:0]                    m_axi_rresp,
    output wire                          m_axi_rlast,
    output wire                          m_axi_rvalid,
    input  wire                          m_axi_rready,

    // Taxi AXI Full master interfaces (connect to interconnect slave port)
    taxi_axi_if.wr_mst m_axi_wr,
    taxi_axi_if.rd_mst m_axi_rd
);

    // Write address channel
    assign m_axi_wr.awid    = m_axi_awid;
    assign m_axi_wr.awaddr  = m_axi_awaddr;
    assign m_axi_wr.awlen   = m_axi_awlen;
    assign m_axi_wr.awsize  = m_axi_awsize;
    assign m_axi_wr.awburst = m_axi_awburst;
    assign m_axi_wr.awlock  = m_axi_awlock;
    assign m_axi_wr.awcache = m_axi_awcache;
    assign m_axi_wr.awprot  = m_axi_awprot;
    assign m_axi_wr.awqos   = m_axi_awqos;
    assign m_axi_wr.awvalid = m_axi_awvalid;
    assign m_axi_awready    = m_axi_wr.awready;

    // Write data channel
    assign m_axi_wr.wdata   = m_axi_wdata;
    assign m_axi_wr.wstrb   = m_axi_wstrb;
    assign m_axi_wr.wlast   = m_axi_wlast;
    assign m_axi_wr.wvalid  = m_axi_wvalid;
    assign m_axi_wready     = m_axi_wr.wready;

    // Write response channel
    assign m_axi_bid        = m_axi_wr.bid;
    assign m_axi_bresp      = m_axi_wr.bresp;
    assign m_axi_bvalid     = m_axi_wr.bvalid;
    assign m_axi_wr.bready  = m_axi_bready;

    // Read address channel
    assign m_axi_rd.arid    = m_axi_arid;
    assign m_axi_rd.araddr  = m_axi_araddr;
    assign m_axi_rd.arlen   = m_axi_arlen;
    assign m_axi_rd.arsize  = m_axi_arsize;
    assign m_axi_rd.arburst = m_axi_arburst;
    assign m_axi_rd.arlock  = m_axi_arlock;
    assign m_axi_rd.arcache = m_axi_arcache;
    assign m_axi_rd.arprot  = m_axi_arprot;
    assign m_axi_rd.arqos   = m_axi_arqos;
    assign m_axi_rd.arvalid = m_axi_arvalid;
    assign m_axi_arready    = m_axi_rd.arready;

    // Read data channel
    assign m_axi_rid        = m_axi_rd.rid;
    assign m_axi_rdata      = m_axi_rd.rdata;
    assign m_axi_rresp      = m_axi_rd.rresp;
    assign m_axi_rlast      = m_axi_rd.rlast;
    assign m_axi_rvalid     = m_axi_rd.rvalid;
    assign m_axi_rd.rready  = m_axi_rready;

    // Tie off unused taxi signals
    assign m_axi_wr.awregion = '0;
    assign m_axi_wr.awuser   = '0;
    assign m_axi_wr.wuser    = '0;
    assign m_axi_rd.arregion = '0;
    assign m_axi_rd.aruser   = '0;

endmodule


// ==========================================================================
// npu_axi_slave_bridge: taxi_axil_if wr_mst/rd_mst -> NPU flat AXI-Lite slave
// ==========================================================================
module npu_axi_slave_bridge #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
) (
    // Taxi AXI-Lite slave interfaces (connect to crossbar master port)
    taxi_axil_if.wr_slv s_axil_wr,
    taxi_axil_if.rd_slv s_axil_rd,

    // Flat AXI-Lite slave signals (connect to npu_top_wrapper s_axi_* ports)
    // Note: NPU slave has 4-bit address, no AWPROT at top level
    output wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    output wire                          s_axi_awvalid,
    input  wire                          s_axi_awready,

    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    output wire [3:0]                    s_axi_wstrb,
    output wire                          s_axi_wvalid,
    input  wire                          s_axi_wready,

    input  wire [1:0]                    s_axi_bresp,
    input  wire                          s_axi_bvalid,
    output wire                          s_axi_bready,

    output wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    output wire [2:0]                    s_axi_arprot,
    output wire                          s_axi_arvalid,
    input  wire                          s_axi_arready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    input  wire [1:0]                    s_axi_rresp,
    input  wire                          s_axi_rvalid,
    output wire                          s_axi_rready
);

    // Write address channel — only lower C_S_AXI_ADDR_WIDTH bits used
    assign s_axi_awaddr  = s_axil_wr.awaddr[C_S_AXI_ADDR_WIDTH-1:0];
    assign s_axi_awvalid = s_axil_wr.awvalid;
    assign s_axil_wr.awready = s_axi_awready;

    // Write data channel
    assign s_axi_wdata   = s_axil_wr.wdata;
    assign s_axi_wstrb   = s_axil_wr.wstrb;
    assign s_axi_wvalid  = s_axil_wr.wvalid;
    assign s_axil_wr.wready = s_axi_wready;

    // Write response channel
    assign s_axil_wr.bresp  = s_axi_bresp;
    assign s_axil_wr.bvalid = s_axi_bvalid;
    assign s_axi_bready     = s_axil_wr.bready;

    // Read address channel
    assign s_axi_araddr  = s_axil_rd.araddr[C_S_AXI_ADDR_WIDTH-1:0];
    assign s_axi_arprot  = s_axil_rd.arprot;
    assign s_axi_arvalid = s_axil_rd.arvalid;
    assign s_axil_rd.arready = s_axi_arready;

    // Read data channel
    assign s_axil_rd.rdata  = s_axi_rdata;
    assign s_axil_rd.rresp  = s_axi_rresp;
    assign s_axil_rd.rvalid = s_axi_rvalid;
    assign s_axi_rready     = s_axil_rd.rready;

endmodule

`resetall

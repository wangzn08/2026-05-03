`timescale 1 ns / 1 ps

module npu_axi_master_v1_0_M00_AXI #(
    parameter  C_M_TARGET_SLAVE_BASE_ADDR = 32'h40000000,
    parameter integer C_M_AXI_BURST_LEN   = 16,
    parameter integer C_M_AXI_ID_WIDTH    = 1,
    parameter integer C_M_AXI_ADDR_WIDTH  = 32,
    parameter integer C_M_AXI_DATA_WIDTH  = 32,
    parameter integer C_M_AXI_AWUSER_WIDTH = 0,
    parameter integer C_M_AXI_ARUSER_WIDTH = 0,
    parameter integer C_M_AXI_WUSER_WIDTH = 0,
    parameter integer C_M_AXI_RUSER_WIDTH = 0,
    parameter integer C_M_AXI_BUSER_WIDTH = 0
) (
    input  wire  INIT_AXI_TXN,
    output wire  TXN_DONE,
    output reg   ERROR,
    input  wire  M_AXI_ACLK,
    input  wire  M_AXI_ARESETN,

    // === 新增控制端口 ===
    input  wire                         i_mode,      // 1: Read only, 0: Write only
    input  wire [C_M_AXI_ID_WIDTH-1:0] i_axi_id,    // 该 Master 使用的 ID

    // 外部数据 / 地址接口
    input  wire [C_M_AXI_ADDR_WIDTH-1 : 0] i_src_addr,   // 读起始地址
    input  wire [C_M_AXI_ADDR_WIDTH-1 : 0] i_dst_addr,   // 写起始地址
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] npu_wdata,    // 写数据（来自 NPU）

    // AXI 写地址通道
    output wire [C_M_AXI_ID_WIDTH-1 : 0] M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,
    output wire [7 : 0] M_AXI_AWLEN,
    output wire [2 : 0] M_AXI_AWSIZE,
    output wire [1 : 0] M_AXI_AWBURST,
    output wire  M_AXI_AWLOCK,
    output wire [3 : 0] M_AXI_AWCACHE,
    output wire [2 : 0] M_AXI_AWPROT,
    output wire [3 : 0] M_AXI_AWQOS,
    output wire [C_M_AXI_AWUSER_WIDTH-1 : 0] M_AXI_AWUSER,
    output wire  M_AXI_AWVALID,
    input  wire  M_AXI_AWREADY,
    // AXI 写数据通道
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
    output wire  M_AXI_WLAST,
    output wire [C_M_AXI_WUSER_WIDTH-1 : 0] M_AXI_WUSER,
    output wire  M_AXI_WVALID,
    input  wire  M_AXI_WREADY,
    // AXI 写响应
    input wire [C_M_AXI_ID_WIDTH-1 : 0] M_AXI_BID,
    input wire [1 : 0] M_AXI_BRESP,
    input wire [C_M_AXI_BUSER_WIDTH-1 : 0] M_AXI_BUSER,
    input wire  M_AXI_BVALID,
    output wire  M_AXI_BREADY,
    // AXI 读地址通道
    output wire [C_M_AXI_ID_WIDTH-1 : 0] M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
    output wire [7 : 0] M_AXI_ARLEN,
    output wire [2 : 0] M_AXI_ARSIZE,
    output wire [1 : 0] M_AXI_ARBURST,
    output wire  M_AXI_ARLOCK,
    output wire [3 : 0] M_AXI_ARCACHE,
    output wire [2 : 0] M_AXI_ARPROT,
    output wire [3 : 0] M_AXI_ARQOS,
    output wire [C_M_AXI_ARUSER_WIDTH-1 : 0] M_AXI_ARUSER,
    output wire  M_AXI_ARVALID,
    input  wire  M_AXI_ARREADY,
    // AXI 读数据通道
    input wire [C_M_AXI_ID_WIDTH-1 : 0] M_AXI_RID,
    input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
    input wire [1 : 0] M_AXI_RRESP,
    input wire  M_AXI_RLAST,
    input wire [C_M_AXI_RUSER_WIDTH-1 : 0] M_AXI_RUSER,
    input wire  M_AXI_RVALID,
    output wire  M_AXI_RREADY
);

    localparam integer IDLE       = 2'd0;
    localparam integer INIT_RW    = 2'd1;   // 读或写状态
    localparam integer WAIT_DONE  = 2'd2;   // 等待最后一拍完成

    reg [1:0] state;
    reg [C_M_AXI_ADDR_WIDTH-1:0]  awaddr, araddr;
    reg        awvalid, wvalid, wlast, bready, arvalid, rready;
    reg [7:0]  burst_len;
    reg [C_M_AXI_DATA_WIDTH-1:0]  wdata;
    reg [2:0]  wstrb_size; // not used, always 4'b1111
    reg        txn_done_r;
    wire       wnext, rnext;

    // 简单的 burst length 计数
    reg [7:0]  beat_cnt;

    assign M_AXI_AWID    = i_axi_id;
    assign M_AXI_ARID    = i_axi_id;

    assign M_AXI_AWADDR  = C_M_TARGET_SLAVE_BASE_ADDR + awaddr;
    assign M_AXI_AWVALID = awvalid;
    assign M_AXI_AWLEN   = burst_len;
    assign M_AXI_AWSIZE  = 3'b010; // 4 bytes
    assign M_AXI_AWBURST = 2'b01;  // INCR
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0;
    assign M_AXI_AWUSER  = 'b0;

    assign M_AXI_WDATA   = (i_mode == 1'b0) ? npu_wdata : 32'd0;  // 写模式下使用外部数据
    assign M_AXI_WSTRB   = 4'b1111;
    assign M_AXI_WVALID  = wvalid;
    assign M_AXI_WLAST   = wlast;
    assign M_AXI_WUSER   = 'b0;

    assign M_AXI_BREADY  = bready;

    assign M_AXI_ARADDR  = C_M_TARGET_SLAVE_BASE_ADDR + araddr;
    assign M_AXI_ARVALID = arvalid;
    assign M_AXI_ARLEN   = burst_len;
    assign M_AXI_ARSIZE  = 3'b010;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_ARQOS   = 4'b0;
    assign M_AXI_ARUSER  = 'b0;

    assign M_AXI_RREADY  = rready;

    assign TXN_DONE      = txn_done_r;
    assign wnext = M_AXI_WREADY & wvalid;
    assign rnext = M_AXI_RVALID & rready;

    // 状态机
    always @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) begin
            state   <= IDLE;
            awvalid <= 0; wvalid <= 0; wlast <= 0; bready <= 0;
            arvalid <= 0; rready <= 0;
            txn_done_r <= 0;
            ERROR    <= 0;
            beat_cnt <= 0;
            awaddr   <= 0; araddr <= 0;
            wdata    <= 0;
        end else begin
            txn_done_r <= 0; // pulse
            case (state)
                IDLE: begin
                    if (INIT_AXI_TXN) begin
                        beat_cnt <= 0;
                        if (i_mode == 1'b1) begin  // Read
                            arvalid <= 1;
                            araddr  <= i_src_addr;
                            burst_len <= C_M_AXI_BURST_LEN - 1;
                            rready  <= 1;
                            state   <= INIT_RW;
                        end else begin              // Write
                            awvalid <= 1;
                            awaddr  <= i_dst_addr;
                            burst_len <= C_M_AXI_BURST_LEN - 1;
                            wvalid  <= 1;
                            wlast   <= (C_M_AXI_BURST_LEN == 1);
                            state   <= INIT_RW;
                        end
                    end
                end

                INIT_RW: begin
                    if (i_mode == 1'b1) begin  // Read
                        if (M_AXI_ARREADY & arvalid)
                            arvalid <= 0;
                        if (rnext) begin
                            beat_cnt <= beat_cnt + 1;
                            if (M_AXI_RLAST) begin
                                rready <= 0;
                                state  <= WAIT_DONE;
                            end
                        end
                    end else begin            // Write
                        if (M_AXI_AWREADY & awvalid)
                            awvalid <= 0;
                        if (wnext) begin
                            beat_cnt <= beat_cnt + 1;
                            if (beat_cnt == C_M_AXI_BURST_LEN-2)
                                wlast <= 1;
                            else if (wlast)
                                wlast <= 0;
                            if (beat_cnt == C_M_AXI_BURST_LEN-1) begin
                                wvalid <= 0;
                                bready <= 1;
                                state  <= WAIT_DONE;
                            end
                        end
                    end
                end

                WAIT_DONE: begin
                    if (i_mode == 1'b1) begin  // Read: already done
                        txn_done_r <= 1;
                        state <= IDLE;
                    end else begin            // Write: wait for bvalid
                        if (M_AXI_BVALID & bready) begin
                            bready <= 0;
                            txn_done_r <= 1;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule

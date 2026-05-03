`timescale 1ns / 1ps

module npu_top_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_BURST_LEN  = 16,
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter [31:0]  C_M_TARGET_SLAVE_BASE_ADDR = 32'h4000_0000
) (
    input  wire  aclk,
    input  wire  aresetn,

    // ============================================================
    // AXI-Lite Slave (CPU 控制接口)
    // ============================================================
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [3:0]                    s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,

    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    // ============================================================
    // AXI Full Master (数据搬运接口 - 读写分离)
    // ============================================================
    // --- 写地址通道 (来自 Write Master) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                    m_axi_awlen,
    output wire [2:0]                    m_axi_awsize,
    output wire [1:0]                    m_axi_awburst,
    output wire                          m_axi_awlock,
    output wire [3:0]                    m_axi_awcache,
    output wire [2:0]                    m_axi_awprot,
    output wire [3:0]                    m_axi_awqos,
    output wire                          m_axi_awvalid,
    input  wire                          m_axi_awready,

    // --- 写数据通道 (来自 Write Master) ---
    output wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                          m_axi_wlast,
    output wire                          m_axi_wvalid,
    input  wire                          m_axi_wready,

    // --- 写响应通道 (来自 Write Master) ---
    input  wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output wire                          m_axi_bready,

    // --- 读地址通道 (来自 Read Master) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]                    m_axi_arlen,
    output wire [2:0]                    m_axi_arsize,
    output wire [1:0]                    m_axi_arburst,
    output wire                          m_axi_arlock,
    output wire [3:0]                    m_axi_arcache,
    output wire [2:0]                    m_axi_arprot,
    output wire [3:0]                    m_axi_arqos,
    output wire                          m_axi_arvalid,
    input  wire                          m_axi_arready,

    // --- 读数据通道 (来自 Read Master) ---
    input  wire [C_M_AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]                    m_axi_rresp,
    input  wire                          m_axi_rlast,
    input  wire                          m_axi_rvalid,
    output wire                          m_axi_rready
);

    // ============================================================
    // 1. 寄存器组 (从 AXI-Lite Slave 引出)
    // ============================================================
    wire [31:0] reg_ctrl;       // [0]Start, [1]PingPong, [2]AccClear, [3]StoreEn, [7:4]CalcAddr, [11:8]StoreAddr
    wire [31:0] reg_src_addr;   // DDR 读基地址
    wire [31:0] reg_dst_addr;   // DDR 写基地址
    wire [31:0] reg_param;      // [4:0]Shift, [7:5]ActType, [15:8]Clip, [21:16]CompLen

    npu_axi_lite_slave_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) u_slave (
        .S_AXI_ACLK    (aclk),
        .S_AXI_ARESETN (aresetn),
        .S_AXI_AWADDR  (s_axi_awaddr),
        .S_AXI_AWPROT  (3'h0),
        .S_AXI_AWVALID (s_axi_awvalid),
        .S_AXI_AWREADY (s_axi_awready),
        .S_AXI_WDATA   (s_axi_wdata),
        .S_AXI_WSTRB   (s_axi_wstrb),
        .S_AXI_WVALID  (s_axi_wvalid),
        .S_AXI_WREADY  (s_axi_wready),
        .S_AXI_BRESP   (s_axi_bresp),
        .S_AXI_BVALID  (s_axi_bvalid),
        .S_AXI_BREADY  (s_axi_bready),
        .S_AXI_ARADDR  (s_axi_araddr),
        .S_AXI_ARPROT  (s_axi_arprot),
        .S_AXI_ARVALID (s_axi_arvalid),
        .S_AXI_ARREADY (s_axi_arready),
        .S_AXI_RDATA   (s_axi_rdata),
        .S_AXI_RRESP   (s_axi_rresp),
        .S_AXI_RVALID  (s_axi_rvalid),
        .S_AXI_RREADY  (s_axi_rready),

        // 引出寄存器
        .slv_reg0      (reg_ctrl),
        .slv_reg1      (reg_src_addr),
        .slv_reg2      (reg_dst_addr),
        .slv_reg3      (reg_param)
    );

    // ============================================================
    // 3. 主状态机参数 & 信号声明 (前置，供缓冲块引用)
    // ============================================================
    localparam S_IDLE        = 3'd0;
    localparam S_READ_REQ    = 3'd1;
    localparam S_READ_WAIT   = 3'd2;
    localparam S_COMPUTE     = 3'd3;
    localparam S_WRITE_REQ   = 3'd4;
    localparam S_WRITE_WAIT  = 3'd5;
    localparam S_DONE        = 3'd6;

    reg [2:0] state;
    reg       read_start;      // 读 Master 启动脉冲
    reg       write_start;     // 写 Master 启动脉冲
    reg       pingpong_sel;    // 状态机自动翻转: COMPUTE→WRITE_REQ 时切换 bank
    reg [5:0] comp_cnt;       // K维度循环计数器 (0..comp_len)
    wire [5:0] comp_len = reg_param[21:16];  // K维度长度-1

    // ============================================================
    // 2. 内部数据缓冲 (ibuf / wbuf)
    // ============================================================
    reg [31:0] ibuf [0:63];
    reg [31:0] wbuf [0:63];
    reg [5:0]  buf_wr_ptr;      // 缓冲写入指针 (0~63)
    reg        buf_wr_sel;      // 0: 写 ibuf, 1: 写 wbuf

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            buf_wr_ptr <= 6'd0;
            buf_wr_sel <= 1'b0;
        end else if (state == S_IDLE && reg_ctrl[0]) begin
            // 新事务启动前复位缓冲指针
            buf_wr_ptr <= 6'd0;
            buf_wr_sel <= 1'b0;
        end else if (m_axi_rvalid && m_axi_rready) begin
            if (!buf_wr_sel)
                ibuf[buf_wr_ptr] <= m_axi_rdata;
            else
                wbuf[buf_wr_ptr] <= m_axi_rdata;

            if (buf_wr_ptr == 6'd63) begin
                buf_wr_ptr <= 6'd0;
                buf_wr_sel <= ~buf_wr_sel;   // ibuf 写满 64 个后切到 wbuf
            end else begin
                buf_wr_ptr <= buf_wr_ptr + 1;
            end
        end
    end

    // ============================================================
    // 3. 主状态机
    // ============================================================

    // 读事务完成检测
    wire read_done  = m_axi_rvalid && m_axi_rready && m_axi_rlast;
    // 写事务完成检测
    wire write_done = m_axi_bvalid && m_axi_bready;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            read_start   <= 1'b0;
            write_start  <= 1'b0;
            pingpong_sel <= 1'b0;
            comp_cnt     <= 6'd0;
        end else begin
            // 默认脉冲信号仅持续一拍
            read_start  <= 1'b0;
            write_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (reg_ctrl[0]) begin     // CPU 写 Start 位
                        state <= S_READ_REQ;
                    end
                end

                S_READ_REQ: begin
                    read_start <= 1'b1;        // 启动读 Master
                    state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    if (read_done) begin
                        comp_cnt <= 6'd0;
                        state <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    if (comp_cnt == comp_len) begin
                        pingpong_sel <= ~pingpong_sel;
                        state <= S_WRITE_REQ;
                    end else begin
                        comp_cnt <= comp_cnt + 1;
                    end
                end

                S_WRITE_REQ: begin
                    write_start <= 1'b1;       // 启动写 Master
                    state <= S_WRITE_WAIT;
                end

                S_WRITE_WAIT: begin
                    if (write_done)
                        state <= S_DONE;
                end

                S_DONE: begin
                    if (!reg_ctrl[0])
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ============================================================
    // 4. 脉动阵列控制信号
    // ============================================================
    wire calc_en   = (state == S_COMPUTE);
    wire store_en  = (state == S_WRITE_REQ) || (state == S_WRITE_WAIT);
    wire [3:0] calc_addr  = reg_ctrl[7:4];
    wire [3:0] store_addr = reg_ctrl[11:8];
    wire acc_clear    = (state == S_COMPUTE) && (comp_cnt == 0);

    // ============================================================
    // 5. 脉动阵列 (MAC Array)
    // ============================================================
    wire [511:0] psum_bus;

    // 当前 K 维度的 ibuf/wbuf 数据
    wire [31:0] cur_ibuf, cur_wbuf;
    assign cur_ibuf = ibuf[comp_cnt];
    assign cur_wbuf = wbuf[comp_cnt];

    MAC_Array_4x4 u_core (
        .clk            (aclk),
        .rst_n          (aresetn),
        .i_calc_en      (calc_en),
        .i_acc_clear    (acc_clear),
        .i_calc_addr    (calc_addr),
        .i_store_en     (store_en),
        .i_store_addr   (store_addr),
        .i_pingpong_sel (pingpong_sel),

        .i_act_m0 (cur_ibuf[7:0]),
        .i_act_m1 (cur_ibuf[15:8]),
        .i_act_m2 (cur_ibuf[23:16]),
        .i_act_m3 (cur_ibuf[31:24]),
        .i_wgt_n0 (cur_wbuf[7:0]),
        .i_wgt_n1 (cur_wbuf[15:8]),
        .i_wgt_n2 (cur_wbuf[23:16]),
        .i_wgt_n3 (cur_wbuf[31:24]),

        .i_bias_bus ({16{32'd0}}),
        .o_psum_bus (psum_bus)
    );

    // ============================================================
    // 6. 激活 + 重量化 (Re-quant & Activation)
    // ============================================================
    wire [127:0] act_out_128b;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_act
            requant_activation_unit u_act (
                .i_psum_32b   (psum_bus[i*32 +: 32]),
                .i_shift_val  (reg_param[4:0]),
                .i_act_type   (reg_param[7:5]),
                .i_clip_limit (reg_param[15:8]),
                .o_act_8b     (act_out_128b[i*8 +: 8])
            );
        end
    endgenerate

    // ============================================================
    // 7. 写数据拆解: 128bit → 4×32bit
    // ============================================================
    reg [1:0] wd_sel;
    wire [31:0] npu_wdata = act_out_128b[wd_sel*32 +: 32];

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            wd_sel <= 2'd0;
        else if ((state == S_WRITE_REQ || state == S_WRITE_WAIT) && m_axi_wvalid && m_axi_wready) begin
            if (wd_sel == 2'd3)
                wd_sel <= 2'd0;
            else
                wd_sel <= wd_sel + 1;
        end
    end

    // ============================================================
    // 8. AXI Master 实例 (读 + 写 各自独立)
    // ============================================================

    // ---------- 读 Master (ID = 0) ----------
    npu_axi_master_v1_0_M00_AXI #(
        .C_M_TARGET_SLAVE_BASE_ADDR(C_M_TARGET_SLAVE_BASE_ADDR),
        .C_M_AXI_BURST_LEN         (C_M_AXI_BURST_LEN),
        .C_M_AXI_ID_WIDTH          (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH        (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH        (C_M_AXI_DATA_WIDTH),
        .C_M_AXI_AWUSER_WIDTH      (0),
        .C_M_AXI_ARUSER_WIDTH      (0),
        .C_M_AXI_WUSER_WIDTH       (0),
        .C_M_AXI_RUSER_WIDTH       (0),
        .C_M_AXI_BUSER_WIDTH       (0)
    ) u_master_read (
        .INIT_AXI_TXN   (read_start),
        .TXN_DONE       (),                            // 可用 read_txn_done 脉冲
        .ERROR          (),
        .M_AXI_ACLK     (aclk),
        .M_AXI_ARESETN  (aresetn),

        .i_mode         (1'b1),                        // 读模式
        .i_axi_id       (1'b0),                        // ARID = 0
        .i_src_addr     (reg_src_addr),
        .i_dst_addr     (32'd0),
        .npu_wdata      (32'd0),

        // ---- 写通道未使用 ----
        .M_AXI_AWID     (),
        .M_AXI_AWADDR   (),
        .M_AXI_AWLEN    (),
        .M_AXI_AWSIZE   (),
        .M_AXI_AWBURST  (),
        .M_AXI_AWLOCK   (),
        .M_AXI_AWCACHE  (),
        .M_AXI_AWPROT   (),
        .M_AXI_AWQOS    (),
        .M_AXI_AWUSER   (),
        .M_AXI_AWVALID  (),
        .M_AXI_AWREADY  (1'b0),
        .M_AXI_WDATA    (),
        .M_AXI_WSTRB    (),
        .M_AXI_WLAST    (),
        .M_AXI_WUSER    (),
        .M_AXI_WVALID   (),
        .M_AXI_WREADY   (1'b0),
        .M_AXI_BID      (1'b0),
        .M_AXI_BRESP    (2'b0),
        .M_AXI_BUSER    (1'b0),
        .M_AXI_BVALID   (1'b0),
        .M_AXI_BREADY   (),

        // ---- 读通道接顶层 ----
        .M_AXI_ARID     (m_axi_arid),
        .M_AXI_ARADDR   (m_axi_araddr),
        .M_AXI_ARLEN    (m_axi_arlen),
        .M_AXI_ARSIZE   (m_axi_arsize),
        .M_AXI_ARBURST  (m_axi_arburst),
        .M_AXI_ARLOCK   (m_axi_arlock),
        .M_AXI_ARCACHE  (m_axi_arcache),
        .M_AXI_ARPROT   (m_axi_arprot),
        .M_AXI_ARQOS    (m_axi_arqos),
        .M_AXI_ARUSER   (),
        .M_AXI_ARVALID  (m_axi_arvalid),
        .M_AXI_ARREADY  (m_axi_arready),
        .M_AXI_RID      (m_axi_rid),
        .M_AXI_RDATA    (m_axi_rdata),
        .M_AXI_RRESP    (m_axi_rresp),
        .M_AXI_RLAST    (m_axi_rlast),
        .M_AXI_RUSER    (1'b0),
        .M_AXI_RVALID   (m_axi_rvalid),
        .M_AXI_RREADY   (m_axi_rready)
    );

    // ---------- 写 Master (ID = 1) ----------
    npu_axi_master_v1_0_M00_AXI #(
        .C_M_TARGET_SLAVE_BASE_ADDR(C_M_TARGET_SLAVE_BASE_ADDR),
        .C_M_AXI_BURST_LEN         (4),
        .C_M_AXI_ID_WIDTH          (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH        (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH        (C_M_AXI_DATA_WIDTH),
        .C_M_AXI_AWUSER_WIDTH      (0),
        .C_M_AXI_ARUSER_WIDTH      (0),
        .C_M_AXI_WUSER_WIDTH       (0),
        .C_M_AXI_RUSER_WIDTH       (0),
        .C_M_AXI_BUSER_WIDTH       (0)
    ) u_master_write (
        .INIT_AXI_TXN   (write_start),
        .TXN_DONE       (),                            // 可用 write_txn_done 脉冲
        .ERROR          (),
        .M_AXI_ACLK     (aclk),
        .M_AXI_ARESETN  (aresetn),

        .i_mode         (1'b0),                        // 写模式
        .i_axi_id       (1'b1),                        // AWID = 1 / WID = 1
        .i_src_addr     (32'd0),
        .i_dst_addr     (reg_dst_addr),
        .npu_wdata      (npu_wdata),

        // ---- 写通道接顶层 ----
        .M_AXI_AWID     (m_axi_awid),
        .M_AXI_AWADDR   (m_axi_awaddr),
        .M_AXI_AWLEN    (m_axi_awlen),
        .M_AXI_AWSIZE   (m_axi_awsize),
        .M_AXI_AWBURST  (m_axi_awburst),
        .M_AXI_AWLOCK   (m_axi_awlock),
        .M_AXI_AWCACHE  (m_axi_awcache),
        .M_AXI_AWPROT   (m_axi_awprot),
        .M_AXI_AWQOS    (m_axi_awqos),
        .M_AXI_AWUSER   (),
        .M_AXI_AWVALID  (m_axi_awvalid),
        .M_AXI_AWREADY  (m_axi_awready),
        .M_AXI_WDATA    (m_axi_wdata),
        .M_AXI_WSTRB    (m_axi_wstrb),
        .M_AXI_WLAST    (m_axi_wlast),
        .M_AXI_WUSER    (),
        .M_AXI_WVALID   (m_axi_wvalid),
        .M_AXI_WREADY   (m_axi_wready),
        .M_AXI_BID      (m_axi_bid),
        .M_AXI_BRESP    (m_axi_bresp),
        .M_AXI_BUSER    (1'b0),
        .M_AXI_BVALID   (m_axi_bvalid),
        .M_AXI_BREADY   (m_axi_bready),

        // ---- 读通道未使用 ----
        .M_AXI_ARID     (),
        .M_AXI_ARADDR   (),
        .M_AXI_ARLEN    (),
        .M_AXI_ARSIZE   (),
        .M_AXI_ARBURST  (),
        .M_AXI_ARLOCK   (),
        .M_AXI_ARCACHE  (),
        .M_AXI_ARPROT   (),
        .M_AXI_ARQOS    (),
        .M_AXI_ARUSER   (),
        .M_AXI_ARVALID  (),
        .M_AXI_ARREADY  (1'b0),
        .M_AXI_RID      (1'b0),
        .M_AXI_RDATA    (32'd0),
        .M_AXI_RRESP    (2'b0),
        .M_AXI_RLAST    (1'b0),
        .M_AXI_RUSER    (1'b0),
        .M_AXI_RVALID   (1'b0),
        .M_AXI_RREADY   ()
    );

endmodule

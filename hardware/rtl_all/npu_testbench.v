// ============================================================
// NPU Standalone Testbench (Bug-Fixed Ultimate Version)
// 绕过 CPU，直接通过 AXI-Lite 驱动 NPU，验证:
//   1. AXI-Lite Slave 寄存器读写
//   2. AXI Master Burst 读 (从内存读 ibuf/wbuf)
//   3. 4x4 脉动阵列 MAC 计算 (外积)
//   4. 重量化 + 激活函数
//   5. AXI Master Burst 写 (结果写回内存)
// ============================================================
`timescale 1ns / 1ps

module npu_testbench;

    // ============================================================
    // 时钟与复位
    // ============================================================
    reg clk = 1;
    reg aresetn = 0;
    always #5 clk = ~clk;  // 100MHz

    initial begin
        repeat (20) @(posedge clk);
        aresetn <= 1;
    end

    // ============================================================
    // FSDB 波形 + 超时
    // ============================================================
    initial begin
    `ifdef FSDB
        if ($test$plusargs("fsdb")) begin
            $fsdbDumpfile("npu_testbench.fsdb");
            $fsdbDumpvars(0, npu_testbench);
        end
    `endif
        repeat (100000) @(posedge clk);
        $display("TIMEOUT after 100000 cycles");
        $finish;
    end

    // ============================================================
    // AXI-Lite 信号 (TB → NPU Slave)
    // ============================================================
    reg  [3:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [3:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // ============================================================
    // AXI Full 信号 (NPU Master ↔ Memory)
    // ============================================================
    wire [0:0]  m_axi_awid;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awlock;
    wire [3:0]  m_axi_awcache;
    wire [2:0]  m_axi_awprot;
    wire [3:0]  m_axi_awqos;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [0:0]  m_axi_bid;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [0:0]  m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arlock;
    wire [3:0]  m_axi_arcache;
    wire [2:0]  m_axi_arprot;
    wire [3:0]  m_axi_arqos;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [0:0]  m_axi_rid;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // ============================================================
    // NPU Top Wrapper 例化
    // ============================================================
    npu_top_wrapper #(
        .C_M_TARGET_SLAVE_BASE_ADDR(32'h0000_0000),
        .C_M_AXI_BURST_LEN(68) // 68拍: ibuf[0..63] + wbuf[0..3] (K≤4)
    ) u_npu (
        .aclk           (clk),
        .aresetn        (aresetn),

        // AXI-Lite Slave
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (3'h0),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        // AXI Full Master
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awqos    (m_axi_awqos),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // ============================================================
    // AXI4 Memory (修复版)
    // ============================================================
    axi4_memory mem (
        .clk             (clk),
        .aresetn         (aresetn),
        .mem_axi_awid    (m_axi_awid),
        .mem_axi_awaddr  (m_axi_awaddr),
        .mem_axi_awlen   (m_axi_awlen),
        .mem_axi_awsize  (m_axi_awsize),
        .mem_axi_awvalid (m_axi_awvalid),
        .mem_axi_awready (m_axi_awready),
        .mem_axi_wdata   (m_axi_wdata),
        .mem_axi_wstrb   (m_axi_wstrb),
        .mem_axi_wlast   (m_axi_wlast),
        .mem_axi_wvalid  (m_axi_wvalid),
        .mem_axi_wready  (m_axi_wready),
        .mem_axi_bid     (m_axi_bid),
        .mem_axi_bresp   (m_axi_bresp),
        .mem_axi_bvalid  (m_axi_bvalid),
        .mem_axi_bready  (m_axi_bready),
        .mem_axi_arid    (m_axi_arid),
        .mem_axi_araddr  (m_axi_araddr),
        .mem_axi_arlen   (m_axi_arlen),
        .mem_axi_arsize  (m_axi_arsize),
        .mem_axi_arvalid (m_axi_arvalid),
        .mem_axi_arready (m_axi_arready),
        .mem_axi_rid     (m_axi_rid),
        .mem_axi_rdata   (m_axi_rdata),
        .mem_axi_rresp   (m_axi_rresp),
        .mem_axi_rlast   (m_axi_rlast),
        .mem_axi_rvalid  (m_axi_rvalid),
        .mem_axi_rready  (m_axi_rready)
    );

    // ============================================================
    // 调试: NPU 状态变化
    // ============================================================
    reg [2:0] prev_state;
    always @(posedge clk) begin
        prev_state <= u_npu.state;
        if (aresetn && (u_npu.state != prev_state)) begin
            $display("[%0t] NPU state: %0d -> %0d", $time, prev_state, u_npu.state);
        end
    end

    // ============================================================
    // 测试数据初始化
    // ============================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 2*1024*1024/4; init_i = init_i + 1)
            mem.memory[init_i] = 32'h0;

        // TEST 1/2 数据: ibuf[0] + wbuf[0] (单cycle)
        // ibuf[0]: act[0]=1, act[1]=2, act[2]=3, act[3]=4
        mem.memory['h00] = 32'h0403_0201;
        // wbuf[0]: wgt[0]=2, wgt[1]=2, wgt[2]=2, wgt[3]=2
        mem.memory['h40] = 32'h0202_0202;

        // TEST 3 数据: K=4 多cycle累加
        // ibuf[0..3] at words 0-3 (byte 0x00-0x0F)
        mem.memory['h00] = 32'h0403_0201;  // act=[1,2,3,4]  (K=0)
        mem.memory['h01] = 32'h0807_0605;  // act=[5,6,7,8]  (K=1)
        mem.memory['h02] = 32'h0C0B_0A09;  // act=[9,10,11,12] (K=2)
        mem.memory['h03] = 32'h100F_0E0D;  // act=[13,14,15,16] (K=3)
        // wbuf[0..3] at words 64-67 (byte 0x100-0x10F)
        mem.memory['h40] = 32'h0202_0202;  // wgt=[2,2,2,2]  (K=0)
        mem.memory['h41] = 32'h0202_0202;  // wgt=[2,2,2,2]  (K=1)
        mem.memory['h42] = 32'h0202_0202;  // wgt=[2,2,2,2]  (K=2)
        mem.memory['h43] = 32'h0202_0202;  // wgt=[2,2,2,2]  (K=3)
    end

    // ============================================================
    // AXI-Lite 任务
    // ============================================================
    task axi_lite_write;
        input [3:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hf;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            fork
                begin : aw_wr
                    forever begin
                        @(posedge clk);
                        if (s_axi_awready) begin
                            s_axi_awvalid <= 1'b0;
                            disable aw_wr;
                        end
                    end
                end
                begin : w_wr
                    forever begin
                        @(posedge clk);
                        if (s_axi_wready) begin
                            s_axi_wvalid <= 1'b0;
                            disable w_wr;
                        end
                    end
                end
            join

            wait (s_axi_bvalid);
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    reg [31:0] read_data;
    task axi_lite_read;
        input  [3:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            wait (s_axi_arready);
            @(posedge clk);
            s_axi_arvalid <= 1'b0;

            wait (s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    // ============================================================
    // 检查任务
    // ============================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check_val;
        input [31:0] addr;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual === expected) begin
                $display("  PASS: [%08x] = %08x", addr, actual);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: [%08x] = %08x, expected %08x", addr, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ============================================================
    // 主测试流程
    // ============================================================
    initial begin
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb  = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0;
        s_axi_rready  = 0;

        wait (aresetn);
        repeat (5) @(posedge clk);

        // ========================================================
        // TEST 1: AXI-Lite 寄存器读写
        // ========================================================
        $display("\n========================================");
        $display("TEST 1: AXI-Lite Register R/W");
        $display("========================================");

        axi_lite_write(4'h0, 32'h0000_0000);  
        axi_lite_write(4'h4, 32'h0000_0100);  
        axi_lite_write(4'h8, 32'h0000_0200);  
        axi_lite_write(4'hC, 32'h0000_0A41);  

        axi_lite_read(4'h0, read_data); check_val(32'h0, read_data, 32'h0000_0000);
        axi_lite_read(4'h4, read_data); check_val(32'h4, read_data, 32'h0000_0100);
        axi_lite_read(4'h8, read_data); check_val(32'h8, read_data, 32'h0000_0200);
        axi_lite_read(4'hC, read_data); check_val(32'hC, read_data, 32'h0000_0A41);

        // ========================================================
        // TEST 2: NPU 完整流程
        // ========================================================
        $display("\n========================================");
        $display("TEST 2: NPU Full Pipeline");
        $display("========================================");

        // 配置: src=0x0, dst=0x200, param(shift=0, ReLU, clip=0)
        axi_lite_write(4'h4, 32'h0000_0000);
        axi_lite_write(4'h8, 32'h0000_0200);
        axi_lite_write(4'hC, 32'h0000_0020);  // shift=0, ReLU, clip=0

        // 启动 NPU (Start=1, AccClear=1)
        axi_lite_write(4'h0, 32'h0000_0005);
        $display("[%0t] NPU Start asserted", $time);

        fork
            begin : npu_done_wait
                forever begin
                    @(posedge clk);
                    if (u_npu.state == 3'd6) begin
                        $display("[%0t] NPU reached DONE state", $time);
                        disable npu_timeout;
                        disable npu_done_wait;
                    end
                end
            end
            begin : npu_timeout
                repeat (5000) @(posedge clk);
                $display("ERROR: NPU timeout!");
                disable npu_done_wait;
            end
        join

        // 恢复 IDLE
        axi_lite_write(4'h0, 32'h0000_0000);
        repeat (5) @(posedge clk);

        // 验证输出: 因为是矩阵乘法（外积），第一行的 4 个 PE 获取的都是 act[0] * wgt
        // 即 1*2 = 2。所以四个结果均为 0x02。写回 DDR 的一个 word 是 0x02020202。
        $display("\nChecking output at 0x0200...");
        check_val(32'h200, mem.memory['h80], 32'h0202_0202);

        // ========================================================
        // TEST 3: K=4 Multi-Cycle Accumulation
        // ========================================================
        $display("\n========================================");
        $display("TEST 3: Multi-Cycle K=4 Accumulation");
        $display("========================================");

        // 配置: src=0x0 (ibuf[0..3] + wbuf[0..3]), dst=0x400, param(comp_len=3, ReLU, shift=0)
        axi_lite_write(4'h4, 32'h0000_0000);
        axi_lite_write(4'h8, 32'h0000_0400);
        axi_lite_write(4'hC, 32'h0003_0020);  // comp_len=3, ReLU, shift=0

        // 启动 NPU (Start=1)
        axi_lite_write(4'h0, 32'h0000_0001);
        $display("[%0t] NPU Start asserted for multi-cycle test", $time);

        fork
            begin : npu_done_wait2
                forever begin
                    @(posedge clk);
                    if (u_npu.state == 3'd6) begin
                        $display("[%0t] NPU reached DONE state", $time);
                        disable npu_timeout2;
                        disable npu_done_wait2;
                    end
                end
            end
            begin : npu_timeout2
                repeat (5000) @(posedge clk);
                $display("ERROR: NPU timeout in TEST 3!");
                disable npu_done_wait2;
            end
        join

        // 恢复 IDLE
        axi_lite_write(4'h0, 32'h0000_0000);
        repeat (5) @(posedge clk);

        // 验证: K=4, act=[1..16], wgt=2
        // PE[m][n]=sum(act_k[m]*2) = 2*(1+5+9+13)=56, 2*(2+6+10+14)=64, ...
        // act_out_128b[7:0]=PE[0][0]=56, [15:8]=PE[0][1]=56, [23:16]=PE[0][2]=56, [31:24]=PE[0][3]=56
        // wd_sel=0: {PE[0][3], PE[0][2], PE[0][1], PE[0][0]} = {56,56,56,56} = 0x38383838
        // No, wait: PE[m][0]=2*(act_m_0*2 summed), PE[m][n] shares same act broadcast per row
        // m=0: 2*(1+5+9+13)=56, m=1: 2*(2+6+10+14)=64, m=2: 2*(3+7+11+15)=72, m=3: 2*(4+8+12+16)=80
        // act_out_128b[7:0]=PE[0][0]=56=0x38, [15:8]=PE[0][1]=56=0x38, [23:16]=PE[0][2]=56=0x38, [31:24]=PE[0][3]=56=0x38
        // wd_sel=0: 0x38383838
        // wd_sel=1: PE[1][*] = 64=0x40 → 0x40404040
        // wd_sel=2: PE[2][*] = 72=0x48 → 0x48484848
        // wd_sel=3: PE[3][*] = 80=0x50 → 0x50505050
        $display("\nChecking output at 0x0400...");
        check_val(32'h400, mem.memory['h100], 32'h3838_3838);
        check_val(32'h404, mem.memory['h101], 32'h4040_4040);
        check_val(32'h408, mem.memory['h102], 32'h4848_4848);
        check_val(32'h40C, mem.memory['h103], 32'h5050_5050);

        $display("\n========================================");
        $display("FINAL: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("========================================");

        if (fail_cnt == 0) $display("ALL TESTS PASSED 🏆");
        else $display("SOME TESTS FAILED ❌");

        $finish;
    end
endmodule


// ============================================================
// AXI4 Memory — 修复版 (严格遵循时序)
// ============================================================
module axi4_memory (
    input             clk,
    input             aresetn,

    // 写地址通道
    input      [0:0]  mem_axi_awid,
    input      [31:0] mem_axi_awaddr,
    input      [7:0]  mem_axi_awlen,
    input      [2:0]  mem_axi_awsize,
    input             mem_axi_awvalid,
    output reg        mem_axi_awready,

    // 写数据通道
    input      [31:0] mem_axi_wdata,
    input      [3:0]  mem_axi_wstrb,
    input             mem_axi_wlast,
    input             mem_axi_wvalid,
    output reg        mem_axi_wready,

    // 写响应通道
    output reg [0:0]  mem_axi_bid,
    output reg [1:0]  mem_axi_bresp,
    output reg        mem_axi_bvalid,
    input             mem_axi_bready,

    // 读地址通道
    input      [0:0]  mem_axi_arid,
    input      [31:0] mem_axi_araddr,
    input      [7:0]  mem_axi_arlen,
    input      [2:0]  mem_axi_arsize,
    input             mem_axi_arvalid,
    output reg        mem_axi_arready,

    // 读数据通道
    output reg [0:0]  mem_axi_rid,
    output reg [31:0] mem_axi_rdata,
    output reg [1:0]  mem_axi_rresp,
    output reg        mem_axi_rlast,
    output reg        mem_axi_rvalid,
    input             mem_axi_rready
);

    reg [31:0] memory [0:2*1024*1024/4-1];

    reg        in_write_burst;
    reg [31:0] wr_addr;

    reg        in_read_burst;
    reg [31:0] rd_addr;
    reg [7:0]  rd_burst_len;
    reg [7:0]  rd_cnt;

    // ========================================================
    // 写通道：地址与数据严格握手
    // ========================================================
    always @(posedge clk) begin
        if (!aresetn) begin
            mem_axi_awready <= 0;
            in_write_burst  <= 0;
        end else begin
            mem_axi_awready <= 0;
            if (mem_axi_awvalid && !in_write_burst) begin
                mem_axi_awready <= 1;
                wr_addr        <= mem_axi_awaddr;
                in_write_burst <= 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!aresetn) begin
            mem_axi_wready <= 0;
        end else begin
            mem_axi_wready <= in_write_burst; 
            
            // 只有 Valid 和 Ready 同时拉高才写入数据
            if (mem_axi_wvalid && mem_axi_wready && in_write_burst) begin
                if (wr_addr < 2*1024*1024) begin
                    if (mem_axi_wstrb[0]) memory[wr_addr >> 2][ 7: 0] <= mem_axi_wdata[ 7: 0];
                    if (mem_axi_wstrb[1]) memory[wr_addr >> 2][15: 8] <= mem_axi_wdata[15: 8];
                    if (mem_axi_wstrb[2]) memory[wr_addr >> 2][23:16] <= mem_axi_wdata[23:16];
                    if (mem_axi_wstrb[3]) memory[wr_addr >> 2][31:24] <= mem_axi_wdata[31:24];
                end
                wr_addr <= wr_addr + 4;
                if (mem_axi_wlast) begin
                    in_write_burst <= 0;
                    mem_axi_wready <= 0; 
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!aresetn) begin
            mem_axi_bvalid <= 0;
        end else begin
            if (mem_axi_wvalid && mem_axi_wready && in_write_burst && mem_axi_wlast) begin
                mem_axi_bvalid <= 1;
                mem_axi_bresp  <= 2'b00;
                mem_axi_bid    <= mem_axi_awid;
            end else if (mem_axi_bvalid && mem_axi_bready) begin
                mem_axi_bvalid <= 0;
            end
        end
    end

    // ========================================================
    // 读通道：修复死锁逻辑
    // ========================================================
    always @(posedge clk) begin
        if (!aresetn) begin
            mem_axi_arready <= 0;
            in_read_burst   <= 0;
        end else begin
            mem_axi_arready <= 0;
            if (mem_axi_arvalid && !in_read_burst) begin
                mem_axi_arready <= 1;
                rd_addr        <= mem_axi_araddr;
                rd_burst_len   <= mem_axi_arlen;
                rd_cnt         <= 0;
                in_read_burst  <= 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!aresetn) begin
            mem_axi_rvalid <= 0;
            mem_axi_rlast  <= 0;
        end else if (in_read_burst) begin
            // 只有当总线上没有有效数据，或者主机已接收时才推入新数据
            if (!mem_axi_rvalid || mem_axi_rready) begin
                if (rd_cnt <= rd_burst_len) begin
                    if ((rd_addr >> 2) + rd_cnt < 2*1024*1024/4)
                        mem_axi_rdata <= memory[(rd_addr >> 2) + rd_cnt];
                    else
                        mem_axi_rdata <= 32'hDEAD_BEEF;

                    mem_axi_rvalid <= 1;
                    mem_axi_rresp  <= 2'b00;
                    mem_axi_rid    <= mem_axi_arid;
                    mem_axi_rlast  <= (rd_cnt == rd_burst_len) ? 1'b1 : 1'b0;
                    rd_cnt <= rd_cnt + 1;
                end else begin
                    // 传完最后一拍，复位状态
                    mem_axi_rvalid <= 0;
                    mem_axi_rlast  <= 0;
                    in_read_burst  <= 0;
                end
            end
        end else begin
            mem_axi_rvalid <= 0;
            mem_axi_rlast  <= 0;
        end
    end

endmodule

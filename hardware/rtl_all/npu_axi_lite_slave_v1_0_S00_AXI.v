`timescale 1 ns / 1 ps

module npu_axi_lite_slave_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
)
(
    input  wire  S_AXI_ACLK,
    input  wire  S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input  wire [2 : 0] S_AXI_AWPROT,
    input  wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input  wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input  wire  S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input  wire [2 : 0] S_AXI_ARPROT,
    input  wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input  wire  S_AXI_RREADY,

    // === MODIFIED: 新增四个输出端口，用于顶层读取 CPU 寄存器
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg0,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg1,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg2,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg3
);

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg  axi_awready;
    reg  axi_wready;
    reg [1 : 0] axi_bresp;
    reg  axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0] axi_rresp;
    reg  axi_rvalid;

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 1;

    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0_r;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1_r;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2_r;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3_r;
    wire slv_reg_rden;
    wire slv_reg_wren;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer byte_index;
    reg aw_en;

    // === MODIFIED: 连续赋值将内部寄存器引出
    assign slv_reg0 = slv_reg0_r;
    assign slv_reg1 = slv_reg1_r;
    assign slv_reg2 = slv_reg2_r;
    assign slv_reg3 = slv_reg3_r;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // axi_awready generation
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // axi_awaddr latching
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_awaddr <= 0;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
                axi_awaddr <= S_AXI_AWADDR;
        end
    end

    // axi_wready generation
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            slv_reg0_r <= 0;
            slv_reg1_r <= 0;
            slv_reg2_r <= 0;
            slv_reg3_r <= 0;
        end else begin
            if (slv_reg_wren) begin
                case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
                    2'h0:
                        for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 )
                                slv_reg0_r[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    2'h1:
                        for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 )
                                slv_reg1_r[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    2'h2:
                        for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 )
                                slv_reg2_r[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    2'h3:
                        for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 )
                                slv_reg3_r[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    default: begin
                        slv_reg0_r <= slv_reg0_r;
                        slv_reg1_r <= slv_reg1_r;
                        slv_reg2_r <= slv_reg2_r;
                        slv_reg3_r <= slv_reg3_r;
                    end
                endcase
            end
        end
    end

    // write response logic
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // axi_arready generation
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_rvalid <= 0;
            axi_rresp  <= 0;
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
    always @(*) begin
        case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
            2'h0   : reg_data_out <= slv_reg0_r;
            2'h1   : reg_data_out <= slv_reg1_r;
            2'h2   : reg_data_out <= slv_reg2_r;
            2'h3   : reg_data_out <= slv_reg3_r;
            default : reg_data_out <= 0;
        endcase
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 )
            axi_rdata  <= 0;
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

endmodule

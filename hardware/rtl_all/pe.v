`timescale 1ns / 1ps

module pe (
    input  wire        clk,
    input  wire        rst_n,
    
    // --- 计算流 (Compute Path) ---
    input  wire [7:0]  i_act_data,     // 激活值 a (INT8)
    input  wire [7:0]  i_wgt_data,     // 权重值 b (INT8)
    input  wire [31:0] i_bias,         // 初始偏置 c (INT32) <--- 【新增接口】
    input  wire        i_calc_en,      
    input  wire        i_acc_clear,    // 累加器清零 (K维度第一拍，此时加载Bias)
    input  wire [3:0]  i_calc_addr,    
    
    // --- 搬运流 (Transfer Path) ---
    input  wire        i_store_en,     
    input  wire [3:0]  i_store_addr,   
    output wire [31:0] o_psum_out,     
    
    // --- 乒乓控制 (Ping-Pong Control) ---
    input  wire        i_pingpong_sel  
);

    reg [31:0] psum_bank_0 [0:15];
    reg [31:0] psum_bank_1 [0:15];

    // 乘法器 (a * b)
    wire signed [15:0] dot_result;
    assign dot_result = $signed(i_act_data) * $signed(i_wgt_data);
    
    // 符号扩展至 32bit，防止加法溢出出错
    wire signed [31:0] dot_result_ext;
    assign dot_result_ext = {{16{dot_result[15]}}, dot_result};

    // 时序逻辑：带偏置的累加 (a*b + c)
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                psum_bank_0[i] <= 32'sd0;
                psum_bank_1[i] <= 32'sd0;
            end
        end else if (i_calc_en) begin
            if (i_pingpong_sel == 1'b0) begin
                if (i_acc_clear) 
                    // 【核心修改】：第一拍存入 (c + a*b)
                    psum_bank_0[i_calc_addr] <= $signed(i_bias) + dot_result_ext; 
                else 
                    // 后续拍继续累加 (+ a*b)
                    psum_bank_0[i_calc_addr] <= $signed(psum_bank_0[i_calc_addr]) + dot_result_ext; 
            end else begin
                if (i_acc_clear) 
                    psum_bank_1[i_calc_addr] <= $signed(i_bias) + dot_result_ext;
                else 
                    psum_bank_1[i_calc_addr] <= $signed(psum_bank_1[i_calc_addr]) + dot_result_ext;
            end
        end
    end

    // 组合逻辑读出
    wire [31:0] current_read_data;
    assign current_read_data = (i_pingpong_sel == 1'b0) ? psum_bank_1[i_store_addr] : psum_bank_0[i_store_addr];
    assign o_psum_out = i_store_en ? current_read_data : 32'sd0;

endmodule

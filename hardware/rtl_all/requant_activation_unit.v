`timescale 1ns / 1ps

module requant_activation_unit (
    input  wire signed [31:0] i_psum_32b,    // 脉动阵列输出的 32bit 部分和
    input  wire [4:0]         i_shift_val,   // 量化缩放右移位数 (0~31)
    
    // --- 激活函数选择 [2:0] ---
    // 000: Bypass (直通)
    // 001: ReLU
    // 010: Leaky ReLU (固定 alpha = 0.125, 即右移3位)
    // 011: ReLU6 (上限裁剪由 i_clip_limit 指定)
    input  wire [2:0]         i_act_type,    
    
    // --- 动态裁剪阈值 ---
    // 用于 ReLU6。例如量化后 '6' 对应的定点数是 110，则配置为 8'sd110
    input  wire signed [7:0]  i_clip_limit,  
    
    output reg  signed [7:0]  o_act_8b
);

    wire signed [31:0] shifted_val;
    reg  signed [31:0] activated_val;
    
    // --------------------------------------------------------
    // 第一步：量化缩放 (Re-quantization Scaling)
    // --------------------------------------------------------
    // 使用算术右移，确保符号位正确填充
    assign shifted_val = i_psum_32b >>> i_shift_val;

    // --------------------------------------------------------
    // 第二步：多模式非线性激活 (Activation Functions)
    // --------------------------------------------------------
    always @(*) begin
        case (i_act_type)
            3'b000: begin // Bypass
                activated_val = shifted_val;
            end
            
            3'b001: begin // ReLU: max(0, x)
                if (shifted_val < 32'sd0)
                    activated_val = 32'sd0;
                else
                    activated_val = shifted_val;
            end
            
            3'b010: begin // Leaky ReLU: x >= 0 ? x : 0.125*x
                if (shifted_val < 32'sd0)
                    activated_val = shifted_val >>> 3; // 算术右移实现缩放
                else
                    activated_val = shifted_val;
            end
            
            3'b011: begin // ReLU6: min(max(0, x), clip_limit)
                if (shifted_val < 32'sd0)
                    activated_val = 32'sd0;
                else if (shifted_val > $signed({{24{i_clip_limit[7]}}, i_clip_limit}))
                    activated_val = $signed({{24{i_clip_limit[7]}}, i_clip_limit});
                else
                    activated_val = shifted_val;
            end
            
            default: activated_val = shifted_val;
        endcase
    end

    // --------------------------------------------------------
    // 第三步：饱和钳位 (INT8 Saturation)
    // --------------------------------------------------------
    // 必须防止计算溢出导致数值“反转”（正变负）
    always @(*) begin
        if (activated_val > 32'sd127) begin
            o_act_8b = 8'sd127;
        end else if (activated_val < -32'sd128) begin
            o_act_8b = -8'sd128;
        end else begin
            o_act_8b = activated_val[7:0];
        end
    end

endmodule

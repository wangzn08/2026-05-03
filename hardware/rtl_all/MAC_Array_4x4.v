`timescale 1ns / 1ps

module MAC_Array_4x4 (
    input  wire         clk,
    input  wire         rst_n,
    
    input  wire         i_calc_en,
    input  wire         i_acc_clear,
    input  wire [3:0]   i_calc_addr,
    input  wire         i_store_en,
    input  wire [3:0]   i_store_addr,
    input  wire         i_pingpong_sel,
    
    // 输入总线
    input  wire [7:0]   i_act_m0, i_act_m1, i_act_m2, i_act_m3, 
    input  wire [7:0]   i_wgt_n0, i_wgt_n1, i_wgt_n2, i_wgt_n3, 
    input  wire [511:0] i_bias_bus,   // <--- 【新增】：16个32bit偏置输入宽总线
    
    // 输出总线
    output wire [511:0] o_psum_bus
);

    wire [7:0] act_bus [0:3];
    assign act_bus[0] = i_act_m0; assign act_bus[1] = i_act_m1;
    assign act_bus[2] = i_act_m2; assign act_bus[3] = i_act_m3;

    wire [7:0] wgt_bus [0:3];
    assign wgt_bus[0] = i_wgt_n0; assign wgt_bus[1] = i_wgt_n1;
    assign wgt_bus[2] = i_wgt_n2; assign wgt_bus[3] = i_wgt_n3;

    wire [31:0] psum_out_bus [0:3][0:3];

    genvar m, n;
    generate
        for (m = 0; m < 4; m = m + 1) begin : row_gen
            for (n = 0; n < 4; n = n + 1) begin : col_gen
                
                pe u_PE (
                    .clk            (clk),
                    .rst_n          (rst_n),
                    .i_act_data     (act_bus[m]),   
                    .i_wgt_data     (wgt_bus[n]),   
                    .i_bias         (i_bias_bus[((m*4+n)*32) +: 32]), // <--- 【切片分配】提取对应的32bit偏置
                    .i_calc_en      (i_calc_en),
                    .i_acc_clear    (i_acc_clear),
                    .i_calc_addr    (i_calc_addr),
                    .i_store_en     (i_store_en),
                    .i_store_addr   (i_store_addr),
                    .i_pingpong_sel (i_pingpong_sel),
                    .o_psum_out     (psum_out_bus[m][n])
                );
                
                assign o_psum_bus[((m*4+n)*32) +: 32] = psum_out_bus[m][n];
                
            end
        end
    endgenerate

endmodule

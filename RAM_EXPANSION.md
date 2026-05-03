# RAM 扩展记录

## 修改概述

将仿真环境的 RAM 从 128KB 扩展到 2MB，以支持更大的神经网络模型（如 DeepConvNet）。

## 修改的文件

### 1. sim/testbench.v

共修改 3 处：

#### 第 314 行 - 内存数组定义
```verilog
// 修改前
reg [31:0]   memory [0:128*1024/4-1] /* verilator public */;

// 修改后
reg [31:0]   memory [0:2*1024*1024/4-1] /* verilator public */;
```

#### 第 392 行 - 读边界检查
```verilog
// 修改前
if (latched_raddr < 128*1024) begin

// 修改后
if (latched_raddr < 2*1024*1024) begin
```

#### 第 405 行 - 写边界检查
```verilog
// 修改前
if (latched_waddr < 128*1024) begin

// 修改后
if (latched_waddr < 2*1024*1024) begin
```

### 2. firmware/sections.lds

#### 第 13 行 - 链接脚本内存长度
```ld
// 修改前
mem : ORIGIN = 0x00000000, LENGTH = 0x00018000

// 修改后
mem : ORIGIN = 0x00000000, LENGTH = 0x001E0000
```

## 内存布局

| 区域 | 起始地址 | 结束地址 | 大小 |
|------|----------|----------|------|
| 代码区 | 0x00000000 | 0x001C0000 | 1.75 MB |
| 栈区 | 0x001C0000 | 0x001E0000 | 256 KB |
| 总计 | 0x00000000 | 0x001E0000 | 2 MB |

## 支持的模型

扩展后可以支持：
- DeepConvNet（~211 KB 内存需求）
- 更大的全连接网络
- 其他需要大量内存的神经网络模型

## 注意事项

1. CPU 代码（rtl/picorv32.v）无需修改
2. 固件代码（firmware/*.c）无需修改
3. 只需修改仿真环境配置
4. 实际 FPGA 部署时需要调整 BRAM 大小

# PicoRV32 CPU + NPU 异构处理器设计

第九届中国研究生创芯大赛 - 赛题三：智核融合 · 低耗强算

## 项目概述

本项目设计并实现了一个基于 PicoRV32 RISC-V CPU 和 NPU 的异构处理器系统，用于 MNIST 手写数字识别任务。

### 主要特性

- **PicoRV32 CPU**: 32位 RISC-V 处理器，支持 AXI4-Lite 接口
- **NPU 设计**: 4×4 脉动阵列，支持卷积、池化等神经网络运算
- **AXI 总线**: 共享总线互连，支持 Burst 传输
- **DMA 控制器**: 高效数据搬运，减少 CPU 干预
- **低功耗设计**: 时钟门控，动态电压频率调整

## 目录结构

```
2026-05-03/
├── docs/                   # 项目文档
│   ├── README.md          # 项目说明
│   ├── INSTALL.md         # 安装指南
│   │   └── RAM_EXPANSION.md   # RAM 扩展说明
│
├── hardware/               # 硬件设计
│   └── rtl/               # Verilog RTL 代码
│       ├── picorv32.v     # PicoRV32 CPU 核心
│       └── npu/           # NPU 设计
│           ├── npu_axi_full_master/   # AXI Master 接口
│           └── npu_axi_lite_slave/    # AXI Slave 接口
│
├── firmware/               # 固件代码 (RISC-V C + 汇编)
│   ├── usercode.c         # 用户推理代码入口
│   ├── deepnet.c          # DeepConvNet 推理实现
│   ├── deepnet.h          # DeepConvNet 头文件
│   ├── start.S            # 启动汇编
│   └── sections.lds       # 链接脚本
│
├── sim/                    # 仿真文件
│   └── testbench.v        # 仿真 testbench
│
├── tests/                  # RISC-V 指令测试
├── scripts/                # 辅助脚本
├── training/               # 模型训练代码 (Python)
├── dataset/                # MNIST 数据集
├── tools/                  # 工具脚本
├── Makefile                # 构建配置
├── run.sh                  # 运行脚本
├── install.sh              # 安装脚本
├── setup_env.sh            # 环境配置
├── LICENSE                 # MIT 许可证
```

## 快速开始

### 1. 环境配置

```bash
# 一键配置开发环境
bash install.sh

# 或手动配置
source setup_env.sh
```

详细说明见 [INSTALL.md](INSTALL.md)

### 2. 训练模型

```bash
cd training
python train_deepnet.py
python export_deepnet_weights.py
```

### 3. 编译固件

```bash
./run.sh -c
```

### 4. 运行仿真

```bash
# 纯仿真（不生成波形，最快）
./run.sh -n

# 带波形仿真
./run.sh -s

# 完整流程（仿真 + Verdi）
./run.sh
```

## 赛题要求

- [x] PicoRV32 CPU (AXI-Lite Master)
- [ ] NPU 设计 (4×4 脉动阵列)
- [ ] AXI 共享总线互连
- [ ] AXI Burst 传输支持
- [ ] DMA 控制器
- [ ] 低功耗设计 (时钟门控)
- [ ] MNIST/CIFAR-10 推理验证

## 技术栈

- **CPU**: PicoRV32 (RISC-V RV32IM)
- **工具链**: riscv32-unknown-elf-gcc
- **仿真**: Synopsys VCS / iverilog
- **波形**: Synopsys Verdi
- **训练**: Python + NumPy
- **模型**: DeepConvNet (int8 量化)

## 相关文档

- [安装指南](INSTALL.md)
- [RAM 扩展说明](RAM_EXPANSION.md)

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](../LICENSE)。

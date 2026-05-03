# 飞腾杯 - PicoRV32 CPU + NPU 异构处理器设计

第九届中国研究生创芯大赛 - 赛题三：智核融合 · 低耗强算

## 项目结构

```
2026-05-03/
├── training/           # Python 模型训练代码
│   ├── common/         # 公共模块（层、优化器等）
│   ├── dataset/        # MNIST 数据集加载
│   ├── deep_convnet.py # DeepConvNet 模型定义
│   ├── train_deepnet.py# 训练脚本
│   └── export_deepnet_weights.py # 权重导出脚本
│
├── firmware/           # RISC-V 固件代码
│   ├── usercode.c      # 用户推理代码入口
│   ├── deepnet.c       # DeepConvNet 推理实现
│   ├── deepnet.h       # DeepConvNet 头文件
│   ├── start.S         # 启动汇编
│   └── sections.lds    # 链接脚本
│
├── rtl/                # Verilog RTL 代码
│   ├── picorv32.v      # PicoRV32 CPU 核心
│   └── npu/            # NPU 设计
│       ├── npu_axi_full_master/  # AXI Master 接口
│       └── npu_axi_lite_slave/   # AXI Slave 接口
│
├── sim/                # 仿真文件
│   └── testbench.v     # 仿真 testbench
│
├── tests/              # RISC-V 指令测试
├── scripts/            # 辅助脚本
├── Makefile            # 构建脚本
└── run.sh              # 一键运行脚本
```

## 快速开始

### 0. 配置环境

```bash
# 一键配置环境（推荐）
bash install.sh

# 或手动配置
source setup_env.sh
```

详细说明见 [INSTALL.md](INSTALL.md)

### 1. 训练模型

```bash
cd training
python train_deepnet.py
python export_deepnet_weights.py
```

### 2. 编译固件

```bash
./run.sh -c
```

### 3. 运行仿真

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

## 工具链

- **CPU**: PicoRV32 (RISC-V RV32IM)
- **工具链**: riscv32-unknown-elf-gcc
- **仿真**: Synopsys VCS / iverilog
- **波形**: Synopsys Verdi

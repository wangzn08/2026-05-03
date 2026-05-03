# 环境配置与安装指南

## 系统要求

- Linux (CentOS 7+ / Ubuntu 18.04+)
- bash shell

## 依赖软件

### 1. RISC-V 工具链

```bash
# 下载工具链 (如果还没有)
# https://github.com/riscv-collab/riscv-gnu-toolchain

# 或者使用预编译版本
# 解压到 /home/Riscv_Tools 或自定义路径
tar -xzf riscv32-unknown-elf-gcc.tar.gz -C /home/
```

设置环境变量：
```bash
export RISCV_TOOLCHAIN=/home/Riscv_Tools
export PATH=$RISCV_TOOLCHAIN/bin:$PATH

# 验证
riscv32-unknown-elf-gcc --version
```

### 2. Synopsys VCS (用于仿真)

```bash
# 需要 license
export VCS_HOME=/home/synopsys/vcs/O-2018.09-SP2
export VCS_ARCH_OVERRIDE=linux
```

### 3. Synopsys Verdi (用于查看波形，可选)

```bash
export VERDI_HOME=/home/synopsys/verdi/Verdi_O-2018.09-SP2
```

### 4. Python 3 + numpy

```bash
pip3 install numpy
```

### 5. iverilog (可选，用于快速仿真)

```bash
# Ubuntu
sudo apt install iverilog

# CentOS
sudo yum install iverilog
```

## 快速配置

### 方法一：一键安装（推荐）

```bash
cd 2026-05-03
bash install.sh
```

`install.sh` 会自动：
- 检测操作系统并安装系统依赖
- 配置 RISC-V 工具链
- 检查 VCS/Verdi 安装
- 安装 Python 依赖
- 生成环境配置文件 `.env`

可选参数：
```bash
bash install.sh --skip-apt   # 跳过系统包安装
bash install.sh --skip-pip   # 跳过 pip 包安装
bash install.sh --help       # 查看帮助
```

### 方法二：手动配置

```bash
cd 2026-05-03
source setup_env.sh
```

## 使用方法

### 编译固件

```bash
./run.sh -c
# 或
make firmware/firmware.hex
```

### 运行仿真

```bash
# 纯仿真 (最快，不生成波形)
./run.sh -n

# 带波形仿真
./run.sh -s

# 完整流程 (仿真 + Verdi)
./run.sh

# 或者用 make
make test_vcs          # 纯仿真
make test_vcs_fsdb     # 带波形
make verdi             # 打开 Verdi
```

### 添加自己的 C 程序

1. 将 `myapp.c` 放入 `firmware/`
2. 在 `Makefile` 的 `FIRMWARE_OBJS` 中添加 `firmware/myapp.o`
3. 在 `firmware/start.S` 中调用你的函数
4. 运行 `./run.sh -n`

## 目录结构

```
2026-05-03/
├── training/           # Python 模型训练代码
├── firmware/           # RISC-V 固件 (C + 汇编)
├── rtl/                # Verilog RTL (CPU + NPU)
├── sim/                # 仿真 testbench
├── tests/              # RISC-V 指令测试
├── scripts/            # 辅助脚本
├── setup_env.sh        # 环境配置脚本
├── run.sh              # 一键运行脚本
├── Makefile            # 构建脚本
└── README.md           # 项目说明
```

## 常见问题

### Q: 找不到 riscv32-unknown-elf-gcc

```bash
# 检查工具链路径
which riscv32-unknown-elf-gcc

# 如果找不到，设置 PATH
export PATH=/home/Riscv_Tools/bin:$PATH
```

### Q: VCS 报错找不到 license

需要配置 Synopsys license server，联系实验室管理员。

### Q: iverilog 仿真很慢

iverilog 是单线程的，对于大设计会比较慢。建议使用 VCS。

### Q: 固件太大超过 96KB

在 `Makefile` 的 `FIRMWARE_OBJS` 中移除不需要的模块，只保留必要的。

#!/bin/bash
# ============================================================
# setup_env.sh — 环境配置脚本
# source this file to set up the development environment:
#   source setup_env.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# 1. RISC-V 工具链
# ============================================================
# 默认路径，如果不在默认位置请修改
RISCV_TOOLCHAIN="${RISCV_TOOLCHAIN:-/home/Riscv_Tools}"

if [ -d "$RISCV_TOOLCHAIN/bin" ]; then
    export PATH="$RISCV_TOOLCHAIN/bin:$PATH"
    echo "[OK] RISC-V 工具链: $RISCV_TOOLCHAIN"
else
    echo "[WARN] RISC-V 工具链未找到: $RISCV_TOOLCHAIN"
    echo "       请设置环境变量 RISCV_TOOLCHAIN 指向工具链安装目录"
fi

# 检查工具链是否可用
if command -v riscv32-unknown-elf-gcc &>/dev/null; then
    echo "      $(riscv32-unknown-elf-gcc --version | head -1)"
else
    echo "[ERROR] riscv32-unknown-elf-gcc 不可用"
fi

# ============================================================
# 2. Synopsys VCS
# ============================================================
VCS_HOME="${VCS_HOME:-/home/synopsys/vcs/O-2018.09-SP2}"

if [ -d "$VCS_HOME" ]; then
    export VCS_HOME
    export VCS_ARCH_OVERRIDE=linux
    echo "[OK] VCS: $VCS_HOME"
else
    echo "[WARN] VCS 未找到: $VCS_HOME"
    echo "       请设置环境变量 VCS_HOME 指向 VCS 安装目录"
fi

# ============================================================
# 3. Synopsys Verdi
# ============================================================
VERDI_HOME="${VERDI_HOME:-/home/synopsys/verdi/Verdi_O-2018.09-SP2}"

if [ -d "$VERDI_HOME" ]; then
    export VERDI_HOME
    echo "[OK] Verdi: $VERDI_HOME"
else
    echo "[WARN] Verdi 未找到: $VERDI_HOME"
    echo "       请设置环境变量 VERDI_HOME 指向 Verdi 安装目录"
fi

# ============================================================
# 4. Python 环境
# ============================================================
PYTHON="${PYTHON:-python3}"

if command -v $PYTHON &>/dev/null; then
    echo "[OK] Python: $($PYTHON --version 2>&1)"
else
    echo "[ERROR] Python3 不可用"
fi

# 检查 numpy
if $PYTHON -c "import numpy" 2>/dev/null; then
    echo "[OK] numpy 已安装"
else
    echo "[WARN] numpy 未安装，运行: pip3 install numpy"
fi

# ============================================================
# 5. iverilog (可选，用于快速仿真)
# ============================================================
if command -v iverilog &>/dev/null; then
    echo "[OK] iverilog: $(iverilog -V 2>&1 | head -1)"
else
    echo "[INFO] iverilog 未安装 (可选，用于快速仿真)"
fi

# ============================================================
# 6. 项目路径
# ============================================================
export PROJECT_DIR="$SCRIPT_DIR"
export FIRMWARE_DIR="$SCRIPT_DIR/firmware"
export RTL_DIR="$SCRIPT_DIR/hardware/rtl"
export SIM_DIR="$SCRIPT_DIR/sim"

echo ""
echo "=========================================="
echo "  环境配置完成!"
echo "=========================================="
echo ""
echo "项目目录: $PROJECT_DIR"
echo ""
echo "快速开始:"
echo "  ./run.sh -c          # 编译固件"
echo "  ./run.sh -n          # 纯仿真 (不生成波形)"
echo "  ./run.sh -s          # 仿真 + FSDB 波形"
echo "  ./run.sh             # 仿真 + 打开 Verdi"
echo ""

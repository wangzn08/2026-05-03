#!/bin/bash
# ============================================================
# install.sh — 一键环境配置脚本
# 自动检测并安装所有依赖，配置开发环境
# 用法: bash install.sh [--skip-apt] [--skip-pip]
# ============================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_step() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# 解析命令行参数
SKIP_APT=0
SKIP_PIP=0
for arg in "$@"; do
    case $arg in
        --skip-apt) SKIP_APT=1 ;;
        --skip-pip) SKIP_PIP=1 ;;
        --help|-h)
            echo "用法: bash install.sh [选项]"
            echo "选项:"
            echo "  --skip-apt   跳过 apt/yum 包安装"
            echo "  --skip-pip   跳过 pip 包安装"
            echo "  --help, -h   显示帮助信息"
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}"
echo "============================================================"
echo "   飞腾杯 PicoRV32 + NPU 异构处理器 - 环境配置脚本"
echo "============================================================"
echo -e "${NC}"

# ============================================================
# 1. 检测操作系统
# ============================================================
print_step "Step 1: 检测操作系统"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    print_ok "操作系统: $PRETTY_NAME"
elif [ -f /etc/centos-release ]; then
    OS="centos"
    OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release | head -1)
    print_ok "操作系统: CentOS $OS_VERSION"
elif [ -f /etc/redhat-release ]; then
    OS="centos"
    OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    print_ok "操作系统: RedHat $OS_VERSION"
else
    print_err "无法检测操作系统类型"
    OS="unknown"
fi

# ============================================================
# 2. 安装系统依赖
# ============================================================
print_step "Step 2: 安装系统依赖"

install_package() {
    local pkg=$1
    if command -v $pkg &>/dev/null; then
        print_ok "$pkg 已安装"
        return 0
    fi

    if [ $SKIP_APT -eq 1 ]; then
        print_warn "跳过安装 $pkg (--skip-apt)"
        return 1
    fi

    print_info "安装 $pkg..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq $pkg
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        sudo yum install -y -q $pkg
    else
        print_err "不支持的操作系统，请手动安装 $pkg"
        return 1
    fi

    if command -v $pkg &>/dev/null; then
        print_ok "$pkg 安装成功"
        return 0
    else
        print_err "$pkg 安装失败"
        return 1
    fi
}

# 基础编译工具
echo ""
print_info "检查基础编译工具..."
install_package "gcc" || true
install_package "make" || true
install_package "git" || true
install_package "wget" || true
install_package "curl" || true
install_package "unzip" || true

# Python
echo ""
print_info "检查 Python 环境..."
if command -v python3 &>/dev/null; then
    print_ok "Python3: $(python3 --version 2>&1)"
else
    install_package "python3" || true
fi

if command -v pip3 &>/dev/null; then
    print_ok "pip3: $(pip3 --version 2>&1)"
elif command -v pip &>/dev/null; then
    print_ok "pip: $(pip --version 2>&1)"
else
    print_warn "pip 未安装，尝试安装..."
    if [ $SKIP_APT -eq 0 ]; then
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            sudo apt-get install -y -qq python3-pip
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            sudo yum install -y -q python3-pip || sudo easy_install-3.6 pip
        fi
    fi
fi

# ============================================================
# 3. 配置 RISC-V 工具链
# ============================================================
print_step "Step 3: 配置 RISC-V 工具链"

# 检查默认路径
RISCV_DEFAULT="/home/Riscv_Tools"
RISCV_TOOLCHAIN="${RISCV_TOOLCHAIN:-$RISCV_DEFAULT}"

# 检查工具链是否可用
if command -v riscv32-unknown-elf-gcc &>/dev/null; then
    RISCV_PATH=$(dirname $(which riscv32-unknown-elf-gcc))
    RISCV_TOOLCHAIN=$(dirname $RISCV_PATH)
    print_ok "RISC-V 工具链已找到: $RISCV_TOOLCHAIN"
    print_ok "版本: $(riscv32-unknown-elf-gcc --version | head -1)"
elif [ -d "$RISCV_TOOLCHAIN/bin" ]; then
    print_ok "RISC-V 工具链在默认路径: $RISCV_TOOLCHAIN"
    export PATH="$RISCV_TOOLCHAIN/bin:$PATH"
    print_ok "版本: $(riscv32-unknown-elf-gcc --version 2>/dev/null | head -1 || echo '无法获取版本')"
else
    print_warn "RISC-V 工具链未找到"
    echo ""
    echo "请按以下步骤安装 RISC-V 工具链："
    echo "  1. 下载工具链: https://github.com/riscv-collab/riscv-gnu-toolchain"
    echo "  2. 或使用预编译版本，解压到: $RISCV_DEFAULT"
    echo "  3. 或设置环境变量: export RISCV_TOOLCHAIN=/path/to/toolchain"
    echo ""

    # 尝试自动下载（可选）
    if [ $SKIP_APT -eq 0 ]; then
        read -p "是否尝试自动下载 RISC-V 工具链? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "下载 RISC-V 工具链..."
            # 这里可以添加下载脚本，需要根据实际URL
            print_warn "自动下载功能暂未实现，请手动安装"
        fi
    fi
fi

# ============================================================
# 4. 配置 Synopsys VCS
# ============================================================
print_step "Step 4: 检查 Synopsys VCS"

VCS_DEFAULT="/home/synopsys/vcs/O-2018.09-SP2"
VCS_HOME="${VCS_HOME:-$VCS_DEFAULT}"

if [ -d "$VCS_HOME" ]; then
    export VCS_HOME
    export VCS_ARCH_OVERRIDE=linux
    print_ok "VCS: $VCS_HOME"

    # 验证 vcs 命令
    if command -v vcs &>/dev/null; then
        print_ok "vcs 命令可用"
    else
        print_warn "vcs 命令不在 PATH 中，尝试添加..."
        export PATH="$VCS_HOME/bin:$PATH"
    fi
else
    print_warn "VCS 未找到: $VCS_HOME"
    echo "VCS 是商业软件，需要手动安装和配置 license"
    echo "请联系实验室管理员获取 VCS 安装包和 license"
fi

# ============================================================
# 5. 配置 Synopsys Verdi
# ============================================================
print_step "Step 5: 检查 Synopsys Verdi"

VERDI_DEFAULT="/home/synopsys/verdi/Verdi_O-2018.09-SP2"
VERDI_HOME="${VERDI_HOME:-$VERDI_DEFAULT}"

if [ -d "$VERDI_HOME" ]; then
    export VERDI_HOME
    print_ok "Verdi: $VERDI_HOME"
else
    print_warn "Verdi 未找到: $VERDI_HOME"
    echo "Verdi 是商业软件，需要手动安装"
fi

# ============================================================
# 6. 安装 Python 依赖
# ============================================================
print_step "Step 6: 安装 Python 依赖"

if [ $SKIP_PIP -eq 1 ]; then
    print_warn "跳过 pip 包安装 (--skip-pip)"
else
    # 确定 pip 命令
    if command -v pip3 &>/dev/null; then
        PIP="pip3"
    elif command -v pip &>/dev/null; then
        PIP="pip"
    else
        print_err "pip 未安装，跳过 Python 依赖安装"
        PIP=""
    fi

    if [ -n "$PIP" ]; then
        print_info "安装 Python 依赖..."

        # 升级 pip
        $PIP install --upgrade pip --quiet 2>/dev/null || true

        # 安装必要包
        $PIP install numpy --quiet
        print_ok "numpy 已安装"

        # 可选包
        $PIP install matplotlib --quiet 2>/dev/null && print_ok "matplotlib 已安装" || print_warn "matplotlib 安装失败（可选）"
        $PIP install Pillow --quiet 2>/dev/null && print_ok "Pillow 已安装" || print_warn "Pillow 安装失败（可选）"
    fi
fi

# ============================================================
# 7. 配置项目环境
# ============================================================
print_step "Step 7: 配置项目环境"

# 设置项目路径环境变量
export PROJECT_DIR="$SCRIPT_DIR"
export FIRMWARE_DIR="$SCRIPT_DIR/firmware"
export RTL_DIR="$SCRIPT_DIR/rtl"
export SIM_DIR="$SCRIPT_DIR/sim"

# 生成环境配置文件
ENV_FILE="$SCRIPT_DIR/.env"
print_info "生成环境配置文件: $ENV_FILE"

cat > "$ENV_FILE" << EOF
# 环境配置 - 由 install.sh 自动生成
# 使用方法: source .env

# 项目路径
export PROJECT_DIR="$SCRIPT_DIR"
export FIRMWARE_DIR="$SCRIPT_DIR/firmware"
export RTL_DIR="$SCRIPT_DIR/rtl"
export SIM_DIR="$SCRIPT_DIR/sim"

# RISC-V 工具链
export RISCV_TOOLCHAIN="$RISCV_TOOLCHAIN"
export PATH="$RISCV_TOOLCHAIN/bin:\$PATH"

# Synopsys VCS
export VCS_HOME="$VCS_HOME"
export VCS_ARCH_OVERRIDE=linux

# Synopsys Verdi
export VERDI_HOME="$VERDI_HOME"
EOF

print_ok "环境配置文件已生成"

# ============================================================
# 8. 验证安装
# ============================================================
print_step "Step 8: 验证安装"

echo ""
print_info "验证所有工具..."

ERRORS=0

# 验证 RISC-V 工具链
if command -v riscv32-unknown-elf-gcc &>/dev/null; then
    print_ok "riscv32-unknown-elf-gcc: $(riscv32-unknown-elf-gcc --version 2>&1 | head -1)"
else
    print_err "riscv32-unknown-elf-gcc 不可用"
    ERRORS=$((ERRORS + 1))
fi

# 验证 make
if command -v make &>/dev/null; then
    print_ok "make: $(make --version | head -1)"
else
    print_err "make 不可用"
    ERRORS=$((ERRORS + 1))
fi

# 验证 Python
if command -v python3 &>/dev/null; then
    print_ok "python3: $(python3 --version 2>&1)"
else
    print_warn "python3 不可用"
fi

# 验证 numpy
if python3 -c "import numpy" 2>/dev/null; then
    print_ok "numpy: $(python3 -c 'import numpy; print(numpy.__version__)')"
else
    print_warn "numpy 未安装"
fi

# 验证 VCS
if [ -d "$VCS_HOME" ]; then
    print_ok "VCS: $VCS_HOME"
else
    print_warn "VCS 未找到（可选，用于仿真）"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   环境配置完成!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    print_warn "有 $ERRORS 个错误需要修复，请查看上面的提示"
else
    print_ok "所有必要工具已配置完成"
fi

echo ""
echo "使用方法："
echo "  1. 加载环境变量: source .env"
echo "  2. 或重新加载: source setup_env.sh"
echo "  3. 编译固件: ./run.sh -c"
echo "  4. 运行仿真: ./run.sh -n"
echo ""
echo "快速命令："
echo "  ./run.sh -c          # 仅编译固件"
echo "  ./run.sh -n          # 纯仿真（不生成波形，最快）"
echo "  ./run.sh -s          # 仿真 + FSDB 波形"
echo "  ./run.sh             # 仿真 + 打开 Verdi"
echo ""

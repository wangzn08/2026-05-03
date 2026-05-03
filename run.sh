#!/bin/bash
# ============================================================
# run.sh — 飞腾杯 PicoRV32 自动化仿真脚本
# 从 C 代码 → 编译固件 → VCS 仿真 → Verdi 波形
#
# 用法:
#   ./run.sh                    # 使用默认 firmware/usercode.c
#   ./run.sh myapp.c            # 使用自定义 C 文件
#   ./run.sh -c                 # 仅编译固件,不仿真
#   ./run.sh -s                 # 仅仿真,不打开 Verdi
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ONLY_COMPILE=0
SKIP_VERDI=0
NO_WAVEFORM=0
USER_C_FILE=""

usage() {
    echo "用法: $0 [选项] [c文件]"
    echo ""
    echo "选项:"
    echo "  -c     仅编译固件 (生成 firmware.hex)"
    echo "  -s     跳过 Verdi, 仅运行仿真"
    echo "  -n     不生成波形文件, 纯仿真 (最快)"
    echo "  -h     显示帮助"
    echo ""
    echo "示例:"
    echo "  $0                    # 使用 firmware/usercode.c, 完整流程"
    echo "  $0 myapp.c            # 使用 myapp.c, 完整流程"
    echo "  $0 -s                 # 编译 + 仿真, 不打开 Verdi"
    echo "  $0 -n                 # 编译 + 纯仿真 (不生成波形, 最快)"
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c) ONLY_COMPILE=1; shift ;;
        -s) SKIP_VERDI=1; shift ;;
        -n) NO_WAVEFORM=1; SKIP_VERDI=1; shift ;;
        -h) usage ;;
        -*)
            echo "未知选项: $1"
            usage
            ;;
        *)
            USER_C_FILE="$1"
            shift
            ;;
    esac
done

# ============================================================
# Step 1: 准备用户 C 代码
# ============================================================
echo "========================================"
echo "  Step 1: 准备用户 C 代码"
echo "========================================"

if [ -n "$USER_C_FILE" ]; then
    if [ ! -f "$USER_C_FILE" ]; then
        echo "错误: 找不到文件 $USER_C_FILE"
        exit 1
    fi
    echo "  使用自定义 C 文件: $USER_C_FILE"
    cp "$USER_C_FILE" firmware/usercode.c
else
    # 确保 usercode.c 存在
    if [ ! -f "firmware/usercode.c" ]; then
        echo "错误: firmware/usercode.c 不存在"
        echo "请创建 firmware/usercode.c 或指定自定义 C 文件"
        exit 1
    fi
    echo "  使用默认 firmware/usercode.c"
fi

echo "  C 代码内容:"
echo "  ----------"
cat firmware/usercode.c
echo "  ----------"

# ============================================================
# Step 2: 编译固件 (C → .o → .elf → .bin → .hex)
# ============================================================
echo ""
echo "========================================"
echo "  Step 2: 编译固件"
echo "========================================"

# 清理旧的中间文件
make clean 2>/dev/null || true

# 编译固件
make firmware/firmware.hex

echo "  固件编译完成: firmware/firmware.hex"

if [ $ONLY_COMPILE -eq 1 ]; then
    echo ""
    echo "仅编译模式, 完成."
    exit 0
fi

# ============================================================
# Step 3: VCS 编译可执行文件 + 仿真
# ============================================================
echo ""
echo "========================================"
echo "  Step 3: VCS 编译 + 仿真"
echo "========================================"

if [ $NO_WAVEFORM -eq 1 ]; then
    # 纯仿真模式：不生成波形文件，最快
    echo "  纯仿真模式 (不生成波形)..."
    if [ ! -f "sim/simv" ] || [ "firmware/firmware.hex" -nt "sim/simv" ] || [ "sim/testbench.v" -nt "sim/simv" ] || [ "rtl/picorv32.v" -nt "sim/simv" ]; then
        echo "  编译 VCS 仿真可执行文件..."
        make sim/simv
    else
        echo "  VCS 可执行文件已是最新, 跳过编译"
    fi
    echo ""
    echo "  运行仿真..."
    ./sim/simv +noerror
else
    # FSDB 波形模式
    echo "  FSDB 波形模式..."
    if [ ! -f "sim/simv_fsdb" ] || [ "firmware/firmware.hex" -nt "sim/simv_fsdb" ] || [ "sim/testbench.v" -nt "sim/simv_fsdb" ] || [ "rtl/picorv32.v" -nt "sim/simv_fsdb" ]; then
        echo "  编译 VCS 仿真可执行文件..."
        make sim/simv_fsdb
    else
        echo "  VCS 可执行文件已是最新, 跳过编译"
    fi
    echo ""
    echo "  运行仿真..."
    make test_vcs_fsdb
fi

# ============================================================
# Step 4: 打开 Verdi 查看波形
# ============================================================
if [ $SKIP_VERDI -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "  Step 4: 打开 Verdi"
    echo "========================================"

    if [ -f "sim/testbench.fsdb" ]; then
        FSDB_SIZE=$(du -h sim/testbench.fsdb | cut -f1)
        echo "  FSDB 文件: sim/testbench.fsdb ($FSDB_SIZE)"
        echo "  启动 Verdi..."
        verdi -ssf sim/testbench.fsdb -top testbench -sv sim/testbench.v rtl/picorv32.v &
    else
        echo "错误: 未生成 sim/testbench.fsdb"
        exit 1
    fi
fi

echo ""
echo "========================================"
echo "  流程完成!"
echo "========================================"

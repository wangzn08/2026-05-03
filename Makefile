# Makefile for 飞腾杯赛题三: PicoRV32 CPU + NPU 异构处理器设计
# Based on PicoRV32 (YosysHQ) with modifications for competition
#
# 如何添加自己的 C 程序:
#   1. 将 myapp.c 放入 firmware/, 函数名自定 (不能叫 main)
#   2. 加到 FIRMWARE_OBJS:  firmware/myapp.o
#   3. 在 firmware/start.S 中 call myapp
#   4. make firmware/firmware.hex    # 编译固件
#   5. make test_vcs                # VCS 仿真 (控制台输出)
#   6. make test_vcs_vcd            # VCS 仿真 + 波形
#   7. make verdi                   # Verdi 查看波形

# 如果未设置环境变量，使用默认路径
RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX ?= /home/Riscv_Tools

SHELL = bash
PYTHON ?= python3
VERILATOR ?= verilator
ICARUS_SUFFIX =
IVERILOG = iverilog$(ICARUS_SUFFIX)
VVP = vvp$(ICARUS_SUFFIX)

TEST_OBJS =
FIRMWARE_OBJS = firmware/start.o firmware/irq.o firmware/print.o firmware/libgcc_stub.o \
                firmware/deepnet.o firmware/usercode.o
GCC_WARNS  = -Werror -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings
GCC_WARNS += -Wredundant-decls -Wstrict-prototypes -Wmissing-prototypes -pedantic
TOOLCHAIN_PREFIX = $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)/bin/riscv32-unknown-elf-
COMPRESSED_ISA = C

# ============================================================
# iverilog Simulation
# ============================================================
test: sim/testbench.vvp firmware/firmware.hex
	$(VVP) -N $<

test_vcd: sim/testbench.vvp firmware/firmware.hex
	$(VVP) -N $< +vcd +trace +noerror

sim/testbench.vvp: sim/testbench.v hw/rtl/picorv32.v
	$(IVERILOG) -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) -I hw/rtl -I sim $^
	chmod -x $@

# ============================================================
# VCS Simulation (Synopsys)
# ============================================================
VCS_ARCH_OVERRIDE ?= linux
VERDI_HOME ?= /home/synopsys/verdi/Verdi_O-2018.09-SP2
VCS_HOME ?= /home/synopsys/vcs/O-2018.09-SP2
VCS = VCS_HOME=$(VCS_HOME) VCS_ARCH_OVERRIDE=$(VCS_ARCH_OVERRIDE) vcs -full64 -debug_access+all -timescale=1ns/1ps
VCS_VERDI_PLI = -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a

sim/simv: sim/testbench.v hw/rtl/picorv32.v firmware/firmware.hex
	$(VCS) -o sim/simv sim/testbench.v hw/rtl/picorv32.v +define+COMPRESSED_ISA

sim/simv_fsdb: sim/testbench.v hw/rtl/picorv32.v firmware/firmware.hex
	$(VCS) -o sim/simv_fsdb sim/testbench.v hw/rtl/picorv32.v +define+COMPRESSED_ISA +define+FSDB $(VCS_VERDI_PLI)

test_vcs: sim/simv
	./sim/simv +vcd +trace +noerror

test_vcs_vcd: sim/simv
	./sim/simv +vcd +trace +noerror

test_vcs_fsdb: sim/simv_fsdb
	./sim/simv_fsdb +fsdb +trace +noerror

verdi: test_vcs_fsdb
	verdi -ssf sim/testbench.fsdb -top testbench -sv sim/testbench.v hw/rtl/picorv32.v &

# ============================================================
# Firmware Build (C code -> hex for CPU)
# ============================================================
firmware/firmware.hex: firmware/firmware.bin firmware/makehex.py
	$(PYTHON) firmware/makehex.py $< 524288 > $@

firmware/firmware.bin: firmware/firmware.elf
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

firmware/firmware.elf: $(FIRMWARE_OBJS) $(TEST_OBJS) firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,firmware/sections.lds,-Map,firmware/firmware.map,--strip-debug \
		$(FIRMWARE_OBJS) $(TEST_OBJS)
	chmod -x $@

firmware/start.o: firmware/start.S
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

firmware/%.o: firmware/%.c
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -O2 --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

tests/%.o: tests/%.S tests/riscv_test.h tests/test_macros.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im -o $@ -DTEST_FUNC_NAME=$(notdir $(basename $<)) \
		-DTEST_FUNC_TXT='"$(notdir $(basename $<))"' -DTEST_FUNC_RET=$(notdir $(basename $<))_ret $<

# ============================================================
# Burst Test (axi4_memory burst verification)
# ============================================================
sim/simv_burst: sim/testbench.v sim/testbench_burst.v
	$(VCS) -o $@ sim/testbench.v sim/testbench_burst.v -top testbench_burst

test_burst: sim/simv_burst
	./sim/simv_burst

# ============================================================
# Cleanup
# ============================================================
clean:
	rm -vrf $(FIRMWARE_OBJS) $(TEST_OBJS)
	rm -vrf firmware/firmware.elf firmware/firmware.bin firmware/firmware.hex firmware/firmware.map
	rm -vrf sim/testbench.vvp sim/testbench.vcd sim/testbench.fsdb sim/testbench.trace
	rm -vrf sim/simv sim/simv_fsdb sim/simv.daidir sim/simv_fsdb.daidir sim/csrc *.key verdiLog csrc

.PHONY: test test_vcd test_vcs test_vcs_vcd test_vcs_fsdb verdi clean

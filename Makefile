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
SOC_FIRMWARE_OBJS = firmware/start.o firmware/irq.o firmware/print.o firmware/libgcc_stub.o \
                firmware/npu_driver.o firmware/soc_test_usercode.o
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

sim/testbench.vvp: sim/testbench.v hardware/rtl/picorv32.v
	$(IVERILOG) -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) -I hardware/rtl -I sim $^
	chmod -x $@

# ============================================================
# VCS Simulation (Synopsys)
# ============================================================
VCS_ARCH_OVERRIDE ?= linux
VERDI_HOME ?= /home/synopsys/verdi/Verdi_O-2018.09-SP2
VCS_HOME ?= /home/synopsys/vcs/O-2018.09-SP2
VCS = VCS_HOME=$(VCS_HOME) VCS_ARCH_OVERRIDE=$(VCS_ARCH_OVERRIDE) vcs -full64 -debug_access+all -timescale=1ns/1ps
VCS_VERDI_PLI = -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a

sim/simv: sim/testbench.v hardware/rtl/picorv32.v firmware/firmware.hex
	$(VCS) -o sim/simv sim/testbench.v hardware/rtl/picorv32.v +define+COMPRESSED_ISA

sim/simv_fsdb: sim/testbench.v hardware/rtl/picorv32.v firmware/firmware.hex
	$(VCS) -o sim/simv_fsdb sim/testbench.v hardware/rtl/picorv32.v +define+COMPRESSED_ISA +define+FSDB $(VCS_VERDI_PLI)

test_vcs: sim/simv
	./sim/simv +vcd +trace +noerror

test_vcs_vcd: sim/simv
	./sim/simv +vcd +trace +noerror

test_vcs_fsdb: sim/simv_fsdb
	./sim/simv_fsdb +fsdb +trace +noerror

verdi: test_vcs_fsdb
	verdi -ssf sim/testbench.fsdb -top testbench -sv sim/testbench.v hardware/rtl/picorv32.v &

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
# SoC Joint Simulation (CPU + NPU + Taxi AXI Interconnect)
# VCS only — requires SystemVerilog interface support
# ============================================================
SOC_RTL_DIR = hardware/rtl_all
NPU_RTL_DIR = hardware/rtl_all
TAXI_DIR = hardware/taxi

SOC_RTL = sim/soc_testbench.sv \
          hardware/rtl/picorv32.v \
          $(SOC_RTL_DIR)/soc_bridges.sv \
          $(SOC_RTL_DIR)/soc_memory.sv \
          $(SOC_RTL_DIR)/soc_top.sv \
          $(NPU_RTL_DIR)/npu_top_wrapper.v \
          $(NPU_RTL_DIR)/MAC_Array_4x4.v \
          $(NPU_RTL_DIR)/pe.v \
          $(NPU_RTL_DIR)/requant_activation_unit.v \
          $(NPU_RTL_DIR)/npu_axi_lite_slave_v1_0_S00_AXI.v \
          $(NPU_RTL_DIR)/npu_axi_master_v1_0_M00_AXI.v

TAXI_RTL = $(TAXI_DIR)/axi/rtl/taxi_axi_if.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_if.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axi_interconnect.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axi_interconnect_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axi_interconnect_rd.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_1s.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_1s_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_1s_rd.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_rd.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_crossbar_addr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_register_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_register_rd.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_tie_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_tie_rd.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_axi_adapter.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_axi_adapter_wr.sv \
           $(TAXI_DIR)/axi/rtl/taxi_axil_axi_adapter_rd.sv \
           $(TAXI_DIR)/prim/rtl/taxi_arbiter.sv \
           $(TAXI_DIR)/prim/rtl/taxi_penc.sv

# SoC firmware
firmware/soc_firmware.hex: firmware/soc_firmware.bin firmware/makehex.py
	$(PYTHON) firmware/makehex.py $< 524288 > $@

firmware/soc_firmware.bin: firmware/soc_firmware.elf
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

firmware/soc_firmware.elf: $(SOC_FIRMWARE_OBJS) firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,firmware/sections.lds,-Map,firmware/soc_firmware.map,--strip-debug \
		$(SOC_FIRMWARE_OBJS)
	chmod -x $@

# VCS compilation for SoC
sim/soc_simv: $(SOC_RTL) $(TAXI_RTL) firmware/soc_firmware.hex
	$(VCS) -sverilog -o sim/soc_simv $(SOC_RTL) $(TAXI_RTL) \
		+define+COMPRESSED_ISA

sim/soc_simv_fsdb: $(SOC_RTL) $(TAXI_RTL) firmware/soc_firmware.hex
	$(VCS) -sverilog -o sim/soc_simv_fsdb $(SOC_RTL) $(TAXI_RTL) \
		+define+COMPRESSED_ISA +define+FSDB_DUMP $(VCS_VERDI_PLI)

# SoC simulation targets
soc_vcs: sim/soc_simv
	./sim/soc_simv +noerror

soc_vcs_fsdb: sim/soc_simv_fsdb
	./sim/soc_simv_fsdb +fsdb +noerror

soc_verdi: soc_vcs_fsdb
	verdi -ssf sim/soc_testbench.fsdb -top soc_testbench $(SOC_RTL) $(TAXI_RTL) &

# ============================================================
# Cleanup
# ============================================================
clean:
	rm -vrf $(FIRMWARE_OBJS) $(SOC_FIRMWARE_OBJS) $(TEST_OBJS)
	rm -vrf firmware/firmware.elf firmware/firmware.bin firmware/firmware.hex firmware/firmware.map
	rm -vrf firmware/soc_firmware.elf firmware/soc_firmware.bin firmware/soc_firmware.hex firmware/soc_firmware.map
	rm -vrf sim/testbench.vvp sim/testbench.vcd sim/testbench.fsdb sim/testbench.trace
	rm -vrf sim/soc_testbench.fsdb sim/soc_testbench.vcd
	rm -vrf sim/simv sim/simv_fsdb sim/simv.daidir sim/simv_fsdb.daidir
	rm -vrf sim/soc_simv sim/soc_simv_fsdb sim/soc_simv.daidir sim/soc_simv_fsdb.daidir
	rm -vrf sim/csrc *.key verdiLog csrc novas*

.PHONY: test test_vcd test_vcs test_vcs_vcd test_vcs_fsdb verdi clean
.PHONY: soc_vcs soc_vcs_fsdb soc_verdi

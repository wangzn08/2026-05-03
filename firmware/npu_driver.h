// NPU Driver for PicoRV32
// Memory-mapped control via AXI-Lite at base address 0x40000000

#ifndef NPU_DRIVER_H
#define NPU_DRIVER_H

#include <stdint.h>

// NPU register base address (AXI-Lite slave)
#define NPU_BASE           0x40000000

// Register offsets (4-bit address space, 4 registers)
#define NPU_REG_CTRL       (*(volatile uint32_t*)(NPU_BASE + 0x0))
#define NPU_REG_SRC_ADDR   (*(volatile uint32_t*)(NPU_BASE + 0x4))
#define NPU_REG_DST_ADDR   (*(volatile uint32_t*)(NPU_BASE + 0x8))
#define NPU_REG_PARAM      (*(volatile uint32_t*)(NPU_BASE + 0xC))

// Control register bits
#define NPU_CTRL_START      (1 << 0)
#define NPU_CTRL_BUSY       (1 << 1)
#define NPU_CTRL_DONE       (1 << 2)

// Parameter register field offsets
#define NPU_PARAM_SHIFT_S   0
#define NPU_PARAM_ACT_S     4
#define NPU_PARAM_CLIP_S    8
#define NPU_PARAM_COMP_LEN_S 16

// Activation types
#define NPU_ACT_BYPASS      0
#define NPU_ACT_RELU        1
#define NPU_ACT_LEAKY_RELU  2
#define NPU_ACT_RELU6       3

// Build param register value
#define NPU_PARAM(comp_len, shift, act, clip) \
    ((((comp_len) & 0xFFFF) << NPU_PARAM_COMP_LEN_S) | \
     (((shift) & 0xF) << NPU_PARAM_SHIFT_S) | \
     (((act) & 0xF) << NPU_PARAM_ACT_S) | \
     (((clip) & 0xF) << NPU_PARAM_CLIP_S))

// API
void npu_init(void);
void npu_start(uint32_t src_addr, uint32_t dst_addr, uint32_t param);
int  npu_is_done(void);
void npu_wait_done(void);

#endif // NPU_DRIVER_H

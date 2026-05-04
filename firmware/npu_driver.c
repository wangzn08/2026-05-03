// NPU Driver implementation

#include "npu_driver.h"

void npu_init(void)
{
    // Reset NPU to idle state
    NPU_REG_CTRL = 0;
}

void npu_start(uint32_t src_addr, uint32_t dst_addr, uint32_t param)
{
    // Configure NPU registers
    NPU_REG_SRC_ADDR = src_addr;
    NPU_REG_DST_ADDR = dst_addr;
    NPU_REG_PARAM   = param;

    // Start NPU with accumulator clear
    NPU_REG_CTRL = NPU_CTRL_START;
}

int npu_is_done(void)
{
    // Read control register and check done bit
    return (NPU_REG_CTRL & NPU_CTRL_DONE) ? 1 : 0;
}

void npu_wait_done(void)
{
    // Poll until NPU signals done
    while (!npu_is_done()) {
        // busy-wait
    }
    // Clear start to return to IDLE
    NPU_REG_CTRL = 0;
}

// SoC Joint Test Firmware
// Tests CPU + NPU integration via AXI interconnect
//
// Test flow:
//   1. Write known data into shared memory
//   2. Configure NPU registers via AXI-Lite
//   3. Start NPU, wait for completion
//   4. Verify NPU results in memory
//   5. Report pass/fail → write 123456789 to 0x20000000

#include "firmware.h"
#include "npu_driver.h"

// Test-pass MMIO address (write 123456789 here to signal success)
#define TESTPASS_ADDR (*(volatile uint32_t*)0x20000000)

// Shared memory addresses
#define IBUF_BASE    0x00000000
#define WBUF_BASE    0x00000100
#define RESULT_BASE1 0x00000200
#define RESULT_BASE2 0x00000400

static int tests_passed = 0;
static int tests_failed = 0;

static void check_val(const char *name, uint32_t actual, uint32_t expected)
{
    if (actual == expected) {
        tests_passed++;
    } else {
        tests_failed++;
        print_str("FAIL: ");
        print_str(name);
        print_str(" = ");
        print_hex(actual, 8);
        print_str(", expected ");
        print_hex(expected, 8);
        print_str("\n");
    }
}

void usercode(void)
{
    volatile uint32_t *ibuf = (volatile uint32_t *)IBUF_BASE;
    volatile uint32_t *wbuf = (volatile uint32_t *)WBUF_BASE;

    print_str("=== SoC CPU+NPU Joint Test ===\n\n");

    // ====================================================================
    // TEST 1: AXI-Lite NPU Register Read/Write
    // ====================================================================
    print_str("TEST 1: NPU Register R/W\n");

    NPU_REG_CTRL     = 0x00000000;
    NPU_REG_SRC_ADDR = 0x00000100;
    NPU_REG_DST_ADDR = 0x00000200;
    NPU_REG_PARAM    = 0x00000A41;

    check_val("REG_CTRL",     NPU_REG_CTRL,     0x00000000);
    check_val("REG_SRC_ADDR", NPU_REG_SRC_ADDR, 0x00000100);
    check_val("REG_DST_ADDR", NPU_REG_DST_ADDR, 0x00000200);
    check_val("REG_PARAM",    NPU_REG_PARAM,    0x00000A41);

    print_str("\n");

    // ====================================================================
    // TEST 2: Single-cycle NPU computation (K=1)
    // ====================================================================
    print_str("TEST 2: Single-Cycle NPU (K=1)\n");

    // Load test data into shared memory
    // ibuf[0]: act=[1,2,3,4] @ byte offset 0x00
    ibuf[0] = 0x04030201;
    // wbuf[0]: wgt=[2,2,2,2] @ byte offset 0x100
    wbuf[0] = 0x02020202;

    // Configure NPU: src=0x0, dst=0x200, param(shift=0, ReLU)
    NPU_REG_SRC_ADDR = IBUF_BASE;
    NPU_REG_DST_ADDR = RESULT_BASE1;
    NPU_REG_PARAM    = NPU_PARAM(0, 0, NPU_ACT_RELU, 0);

    // Start NPU
    print_str("  Starting NPU...\n");
    npu_start(IBUF_BASE, RESULT_BASE1, NPU_PARAM(0, 0, NPU_ACT_RELU, 0));

    // Wait for completion
    npu_wait_done();
    print_str("  NPU done.\n");

    // Verify: result at 0x200 should be 0x02020202
    volatile uint32_t *result1 = (volatile uint32_t *)RESULT_BASE1;
    check_val("result[0x200]", result1[0], 0x02020202);

    print_str("\n");

    // ====================================================================
    // TEST 3: Multi-cycle accumulation (K=4)
    // ====================================================================
    print_str("TEST 3: Multi-Cycle K=4 Accumulation\n");

    // Load ibuf[0..3] at byte offset 0x00-0x0F
    // act K=0: [1,2,3,4]; K=1: [5,6,7,8]; K=2: [9,10,11,12]; K=3: [13,14,15,16]
    ibuf[0] = 0x04030201;
    ibuf[1] = 0x08070605;
    ibuf[2] = 0x0C0B0A09;
    ibuf[3] = 0x100F0E0D;

    // Load wbuf[0..3] at byte offset 0x100-0x10F
    // wgt=[2,2,2,2] for all K cycles
    wbuf[0] = 0x02020202;
    wbuf[1] = 0x02020202;
    wbuf[2] = 0x02020202;
    wbuf[3] = 0x02020202;

    // Configure NPU: src=0x0, dst=0x400, param(comp_len=3, ReLU, shift=0)
    NPU_REG_SRC_ADDR = IBUF_BASE;
    NPU_REG_DST_ADDR = RESULT_BASE2;
    NPU_REG_PARAM    = NPU_PARAM(3, 0, NPU_ACT_RELU, 0);

    // Start NPU
    print_str("  Starting NPU (K=4)...\n");
    npu_start(IBUF_BASE, RESULT_BASE2, NPU_PARAM(3, 0, NPU_ACT_RELU, 0));

    // Wait for completion
    npu_wait_done();
    print_str("  NPU done.\n");

    // Verify results at 0x400-0x40C
    // K=4, wgt=2: PE[0]=2*(1+5+9+13)/4=14*2=28→wait
    // Actually: PE[0][0] = sum(1*2 + 5*2 + 9*2 + 13*2) = 2*(1+5+9+13) = 56 = 0x38
    // PE[1][0] = sum(2*2 + 6*2 + 10*2 + 14*2) = 2*(2+6+10+14) = 64 = 0x40
    // PE[2][0] = sum(3*2 + 7*2 + 11*2 + 15*2) = 2*(3+7+11+15) = 72 = 0x48
    // PE[3][0] = sum(4*2 + 8*2 + 12*2 + 16*2) = 2*(4+8+12+16) = 80 = 0x50
    // wd_sel=0: {PE[0][3],PE[0][2],PE[0][1],PE[0][0]} = {56,56,56,56} = 0x38383838
    // wd_sel=1: {PE[1][3],PE[1][2],PE[1][1],PE[1][0]} = {64,64,64,64} = 0x40404040
    // wd_sel=2: {PE[2][3],PE[2][2],PE[2][1],PE[2][0]} = {72,72,72,72} = 0x48484848
    // wd_sel=3: {PE[3][3],PE[3][2],PE[3][1],PE[3][0]} = {80,80,80,80} = 0x50505050
    volatile uint32_t *result2 = (volatile uint32_t *)RESULT_BASE2;
    check_val("result[0x400]", result2[0], 0x38383838);
    check_val("result[0x404]", result2[1], 0x40404040);
    check_val("result[0x408]", result2[2], 0x48484848);
    check_val("result[0x40C]", result2[3], 0x50505050);

    print_str("\n");

    // ====================================================================
    // Final report
    // ====================================================================
    print_str("========================================\n");
    print_str("RESULTS: ");
    print_dec(tests_passed);
    print_str(" PASS, ");
    print_dec(tests_failed);
    print_str(" FAIL\n");
    print_str("========================================\n");

    if (tests_failed == 0) {
        print_str("\n*** ALL TESTS PASSED ***\n");
        TESTPASS_ADDR = 123456789;
    } else {
        print_str("\n*** SOME TESTS FAILED ***\n");
    }

    // Halt
    while (1) { asm volatile ("wfi"); }
}

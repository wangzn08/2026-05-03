// DeepConvNet inference on PicoRV32 (int8 quantized)
// Architecture: Conv-ReLU-Conv-ReLU-Pool-Conv-ReLU-Conv-ReLU-Pool-Conv-ReLU-Conv-ReLU-Pool-Affine-ReLU-Affine

#include "deepnet.h"
#include "deepnet_weights.h"

// Global buffers (static allocation)
static int8_t featuremap_a[MAX_FEATUREMAP];
static int8_t featuremap_b[MAX_FEATUREMAP];
static int32_t accum_buf[MAX_FEATUREMAP];
static int8_t im2col_buf[MAX_IM2COL];

// im2col: unfold input patches into columns
// input: [C][H][W] -> output: [C*kH*kW][outH*outW]
static void im2col(const int8_t *input, int C, int H, int W,
                   int kH, int kW, int stride, int pad,
                   int outH, int outW, int8_t *output)
{
    int col_idx = 0;
    for (int c = 0; c < C; c++) {
        for (int kh = 0; kh < kH; kh++) {
            for (int kw = 0; kw < kW; kw++) {
                for (int oh = 0; oh < outH; oh++) {
                    for (int ow = 0; ow < outW; ow++) {
                        int ih = oh * stride - pad + kh;
                        int iw = ow * stride - pad + kw;
                        if (ih >= 0 && ih < H && iw >= 0 && iw < W) {
                            output[col_idx] = input[c * H * W + ih * W + iw];
                        } else {
                            output[col_idx] = 0;
                        }
                        col_idx++;
                    }
                }
            }
        }
    }
}

// Convolution forward using im2col + GEMM
// input: [inC][inH][inW], weight: [outC][inC*kH*kW], bias: [outC]
// output: [outC][outH*outW]
static void __attribute__((noinline)) conv_forward(const int8_t *input, int inC, int inH, int inW,
                         const int8_t *weight, const int32_t *bias,
                         int outC, int kH, int kW, int stride, int pad,
                         int outH, int outW, int32_t *output)
{
    int col_len = inC * kH * kW;
    int out_size = outH * outW;

    // im2col
    im2col(input, inC, inH, inW, kH, kW, stride, pad, outH, outW, im2col_buf);

    // GEMM: output = weight * im2col + bias
    for (int oc = 0; oc < outC; oc++) {
        for (int j = 0; j < out_size; j++) {
            int32_t sum = bias[oc];
            for (int k = 0; k < col_len; k++) {
                sum += (int32_t)weight[oc * col_len + k] * (int32_t)im2col_buf[k * out_size + j];
            }
            output[oc * out_size + j] = sum;
        }
    }
}

// 2x2 max pooling with stride 2
// input: [C][H][W] -> output: [C][H/2][W/2]
static void __attribute__((noinline)) pool_forward(const int8_t *input, int C, int H, int W,
                         int8_t *output)
{
    int outH = H / 2;
    int outW = W / 2;

    for (int c = 0; c < C; c++) {
        for (int oh = 0; oh < outH; oh++) {
            for (int ow = 0; ow < outW; ow++) {
                int8_t max_val = -128;
                for (int kh = 0; kh < 2; kh++) {
                    for (int kw = 0; kw < 2; kw++) {
                        int ih = oh * 2 + kh;
                        int iw = ow * 2 + kw;
                        int8_t val = input[c * H * W + ih * W + iw];
                        if (val > max_val) max_val = val;
                    }
                }
                output[c * outH * outW + oh * outW + ow] = max_val;
            }
        }
    }
}

// Affine (fully connected) forward
// input: [in_size], weight: [out_size][in_size], bias: [out_size]
// output: [out_size]
static void __attribute__((noinline)) affine_forward(const int8_t *input, int in_size,
                           const int8_t *weight, const int32_t *bias,
                           int out_size, int32_t *output)
{
    for (int o = 0; o < out_size; o++) {
        int32_t sum = bias[o];
        for (int i = 0; i < in_size; i++) {
            sum += (int32_t)weight[o * in_size + i] * (int32_t)input[i];
        }
        output[o] = sum;
    }
}

// ReLU activation (in-place on int8)
static void relu_int8(int8_t *data, int size)
{
    for (int i = 0; i < size; i++) {
        if (data[i] < 0) data[i] = 0;
    }
}

// Quantize int32 to int8 (dynamic range, integer-only)
static void __attribute__((noinline)) quantize_to_int8(const int32_t *input, int size, int8_t *output)
{
    // Find min/max
    int32_t min_val = input[0];
    int32_t max_val = input[0];
    for (int i = 1; i < size; i++) {
        if (input[i] < min_val) min_val = input[i];
        if (input[i] > max_val) max_val = input[i];
    }

    // Symmetric quantization
    int32_t abs_max = (max_val > -min_val) ? max_val : -min_val;
    if (abs_max == 0) abs_max = 1;

    for (int i = 0; i < size; i++) {
        // q = input[i] * 127 / abs_max (with rounding)
        int32_t v = input[i] * 127;
        int32_t q;
        if (v >= 0)
            q = (v + abs_max / 2) / abs_max;
        else
            q = (v - abs_max / 2) / abs_max;
        if (q > 127) q = 127;
        if (q < -128) q = -128;
        output[i] = (int8_t)q;
    }
}

// Main DeepConvNet inference
void deepnet_inference(const int8_t *input, int32_t *output)
{
    int8_t *buf_a = featuremap_a;
    int8_t *buf_b = featuremap_b;
    int32_t *acc = accum_buf;

    // Copy input to buf_a (already int8, 1x28x28)
    for (int i = 0; i < IMG_C * IMG_H * IMG_W; i++) {
        buf_a[i] = input[i];
    }

    // Conv1: 1x28x28 -> 16x28x28
    conv_forward(buf_a, IMG_C, IMG_H, IMG_W,
                 (const int8_t *)conv1_W, conv1_b, Conv1_OUT_C, 3, 3, 1, 1,
                 Conv1_OUT_H, Conv1_OUT_W, acc);
    quantize_to_int8(acc, Conv1_OUT_C * Conv1_OUT_H * Conv1_OUT_W, buf_b);
    relu_int8(buf_b, Conv1_OUT_C * Conv1_OUT_H * Conv1_OUT_W);

    // Conv2: 16x28x28 -> 16x28x28
    conv_forward(buf_b, Conv1_OUT_C, Conv1_OUT_H, Conv1_OUT_W,
                 (const int8_t *)conv2_W, conv2_b, Conv2_OUT_C, 3, 3, 1, 1,
                 Conv2_OUT_H, Conv2_OUT_W, acc);
    quantize_to_int8(acc, Conv2_OUT_C * Conv2_OUT_H * Conv2_OUT_W, buf_a);
    relu_int8(buf_a, Conv2_OUT_C * Conv2_OUT_H * Conv2_OUT_W);

    // Pool1: 16x28x28 -> 16x14x14
    pool_forward(buf_a, Pool1_OUT_C, Conv2_OUT_H, Conv2_OUT_W, buf_b);

    // Conv3: 16x14x14 -> 32x14x14
    conv_forward(buf_b, Pool1_OUT_C, Pool1_OUT_H, Pool1_OUT_W,
                 (const int8_t *)conv3_W, conv3_b, Conv3_OUT_C, 3, 3, 1, 1,
                 Conv3_OUT_H, Conv3_OUT_W, acc);
    quantize_to_int8(acc, Conv3_OUT_C * Conv3_OUT_H * Conv3_OUT_W, buf_a);
    relu_int8(buf_a, Conv3_OUT_C * Conv3_OUT_H * Conv3_OUT_W);

    // Conv4: 32x14x14 -> 32x16x16 (pad=2)
    conv_forward(buf_a, Conv3_OUT_C, Conv3_OUT_H, Conv3_OUT_W,
                 (const int8_t *)conv4_W, conv4_b, Conv4_OUT_C, 3, 3, 1, 2,
                 Conv4_OUT_H, Conv4_OUT_W, acc);
    quantize_to_int8(acc, Conv4_OUT_C * Conv4_OUT_H * Conv4_OUT_W, buf_b);
    relu_int8(buf_b, Conv4_OUT_C * Conv4_OUT_H * Conv4_OUT_W);

    // Pool2: 32x16x16 -> 32x8x8
    pool_forward(buf_b, Pool2_OUT_C, Conv4_OUT_H, Conv4_OUT_W, buf_a);

    // Conv5: 32x8x8 -> 64x8x8
    conv_forward(buf_a, Pool2_OUT_C, Pool2_OUT_H, Pool2_OUT_W,
                 (const int8_t *)conv5_W, conv5_b, Conv5_OUT_C, 3, 3, 1, 1,
                 Conv5_OUT_H, Conv5_OUT_W, acc);
    quantize_to_int8(acc, Conv5_OUT_C * Conv5_OUT_H * Conv5_OUT_W, buf_b);
    relu_int8(buf_b, Conv5_OUT_C * Conv5_OUT_H * Conv5_OUT_W);

    // Conv6: 64x8x8 -> 64x8x8
    conv_forward(buf_b, Conv5_OUT_C, Conv5_OUT_H, Conv5_OUT_W,
                 (const int8_t *)conv6_W, conv6_b, Conv6_OUT_C, 3, 3, 1, 1,
                 Conv6_OUT_H, Conv6_OUT_W, acc);
    quantize_to_int8(acc, Conv6_OUT_C * Conv6_OUT_H * Conv6_OUT_W, buf_a);
    relu_int8(buf_a, Conv6_OUT_C * Conv6_OUT_H * Conv6_OUT_W);

    // Pool3: 64x8x8 -> 64x4x4
    pool_forward(buf_a, Pool3_OUT_C, Conv6_OUT_H, Conv6_OUT_W, buf_b);

    // Flatten: 64x4x4 = 1024 (already in buf_b)

    // Affine1: 1024 -> 50
    affine_forward(buf_b, 1024, (const int8_t *)affine1_W, affine1_b, AFFINE1_OUT, acc);
    quantize_to_int8(acc, AFFINE1_OUT, buf_a);
    relu_int8(buf_a, AFFINE1_OUT);

    // Affine2: 50 -> 10
    affine_forward(buf_a, AFFINE1_OUT, (const int8_t *)affine2_W, affine2_b, AFFINE2_OUT, output);
}

// DeepConvNet inference on PicoRV32
// 6-layer CNN with int8 quantization

#include "firmware.h"
#include "deepnet.h"
#include "image.h"

// Find index of max value in int32 array
static int argmax(const int32_t *arr, int n)
{
    int best = 0;
    for (int i = 1; i < n; i++) {
        if (arr[i] > arr[best]) best = i;
    }
    return best;
}

void usercode(void)
{
    const int8_t *img = test_image;
    int32_t output[AFFINE2_OUT];

    print_str("DeepConvNet Inference Start\n");

    // Run DeepConvNet inference
    deepnet_inference(img, output);

    // Find prediction
    int pred = argmax(output, AFFINE2_OUT);

    // Output results
    print_str("Predicted: ");
    print_dec(pred);
    print_str("\nTrue label: ");
    print_dec(test_label);
    print_str("\nOutput raw: ");
    for (int i = 0; i < AFFINE2_OUT; i++) {
        print_dec(i);
        print_str("=");
        if (output[i] < 0) {
            print_chr('-');
            print_dec((unsigned int)(-output[i]));
        } else {
            print_dec((unsigned int)output[i]);
        }
        print_chr(' ');
    }
    print_str("\n");

    if (pred == test_label) {
        print_str("CORRECT!\n");
    } else {
        print_str("WRONG\n");
    }
}

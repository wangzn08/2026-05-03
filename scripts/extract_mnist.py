#!/usr/bin/env python3
"""从MNIST IDX格式数据集提取一张测试图片"""
import gzip
import struct
import os
import numpy as np

# 数据集路径（相对于脚本所在目录）
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
DATASET_DIR = os.path.join(PROJECT_DIR, 'dataset')

def read_idx_images(filename):
    with gzip.open(filename, 'rb') as f:
        magic, num, rows, cols = struct.unpack('>IIII', f.read(16))
        data = np.frombuffer(f.read(), dtype=np.uint8)
        return data.reshape(num, rows, cols)

def read_idx_labels(filename):
    with gzip.open(filename, 'rb') as f:
        magic, num = struct.unpack('>II', f.read(8))
        return np.frombuffer(f.read(), dtype=np.uint8)

# 读取测试集
images = read_idx_images(os.path.join(DATASET_DIR, 't10k-images-idx3-ubyte.gz'))
labels = read_idx_labels(os.path.join(DATASET_DIR, 't10k-labels-idx1-ubyte.gz'))

print(f"测试集大小: {len(labels)}")

# 找一个数字5的图片
target_digit = 5
for i in range(len(labels)):
    if labels[i] == target_digit:
        img = images[i]
        label = labels[i]
        print(f"找到数字 {label} 的图片，索引: {i}")

        # 归一化到0-127 (int8)
        img_int8 = (img.astype(np.float32) * 127.0 / 255.0).astype(np.int8)

        # 生成C数组格式
        print(f"\n// 数字 {label} 的图片数据")
        print(f"const int8_t test_image_new[784] = {{")
        flat = img_int8.flatten()
        for j in range(0, 784, 16):
            line = flat[j:j+16]
            print("    " + ", ".join([str(int(x)) for x in line]) + ",")
        print("};")
        print(f"const int32_t test_label_new = {int(label)};")

        # 保存图片为PPM格式
        with open('test_new_image.ppm', 'w') as f:
            f.write("P2\n28 28\n255\n")
            for row in range(28):
                f.write(' '.join([str(max(0, min(255, int(x) * 2))) for x in img_int8[row]]) + '\n')
        print("\n图片已保存为 test_new_image.ppm")

        break

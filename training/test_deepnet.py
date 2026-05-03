#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DeepConvNet 推理测试脚本
用法: python3 test_deepnet.py [num_images]
默认测试前1000张图片
"""

import sys, os, gzip, struct
import numpy as np
from deep_convnet import DeepConvNet

def load_mnist_images(filename):
    with gzip.open(filename, 'rb') as f:
        magic = struct.unpack('>I', f.read(4))[0]
        n_images = struct.unpack('>I', f.read(4))[0]
        n_rows = struct.unpack('>I', f.read(4))[0]
        n_cols = struct.unpack('>I', f.read(4))[0]
        data = np.frombuffer(f.read(), dtype=np.uint8)
        return data.reshape(n_images, 1, n_rows, n_cols).astype(np.float64) / 255.0

def load_mnist_labels(filename):
    with gzip.open(filename, 'rb') as f:
        magic = struct.unpack('>I', f.read(4))[0]
        n_labels = struct.unpack('>I', f.read(4))[0]
        return np.frombuffer(f.read(), dtype=np.uint8)

if __name__ == '__main__':
    num_images = 1000
    if len(sys.argv) > 1:
        num_images = int(sys.argv[1])

    dataset_dir = os.path.join(os.path.dirname(__file__), 'dataset')

    print("Loading MNIST test set...")
    x_test = load_mnist_images(os.path.join(dataset_dir, 't10k-images-idx3-ubyte.gz'))
    t_test = load_mnist_labels(os.path.join(dataset_dir, 't10k-labels-idx1-ubyte.gz'))
    print(f"  Test set: {x_test.shape}")

    print("\nLoading DeepConvNet model...")
    network = DeepConvNet()
    network.load_params(os.path.join(os.path.dirname(__file__), 'deep_convnet_params.pkl'))
    print("  Model loaded.")

    print(f"\nRunning inference on {num_images} images...")
    batch_size = 100
    correct = 0

    for i in range(0, num_images, batch_size):
        end = min(i + batch_size, num_images)
        x_batch = x_test[i:end]
        t_batch = t_test[i:end]
        y = network.predict(x_batch, train_flg=False)
        y_pred = np.argmax(y, axis=1)
        correct += np.sum(y_pred == t_batch)

    accuracy = correct / num_images
    print(f"\nResults: {correct}/{num_images} correct, accuracy = {accuracy:.4f}")

    # Show some examples
    print("\nSample predictions:")
    for idx in [0, 1, 7, 42, 100]:
        if idx < num_images:
            y = network.predict(x_test[idx:idx+1], train_flg=False)
            pred = np.argmax(y)
            true_label = t_test[idx]
            status = "CORRECT" if pred == true_label else "WRONG"
            print(f"  Image #{idx}: pred={pred}, true={true_label}, {status}, scores={y[0]}")

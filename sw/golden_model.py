#!/usr/bin/env python3
"""
Bit-accurate Python Golden Model for 2D Image Convolution / Sobel Accelerator.
Supports all 4 operational modes:
  Mode 0: Sobel Magnitude (|Gx| + |Gy|)
  Mode 1: Sobel X Gradient (|Gx|)
  Mode 2: Sobel Y Gradient (|Gy|)
  Mode 3: 3x3 Gaussian Blur (Sum >> 4)
Generates deterministic test patterns, applies hardware-matching arithmetic,
and outputs golden stimulus and verification hex files.
"""

import sys
import os

IMG_WIDTH = 128
IMG_HEIGHT = 128

SOBEL_X = [
    [-1, 0, 1],
    [-2, 0, 2],
    [-1, 0, 1]
]

SOBEL_Y = [
    [-1, -2, -1],
    [ 0,  0,  0],
    [ 1,  2,  1]
]

GAUSSIAN = [
    [1, 2, 1],
    [2, 4, 2],
    [1, 2, 1]
]

def generate_test_image(filename="input_pixels.hex"):
    """Creates a deterministic synthetic test pattern (checkerboard with gradient)."""
    pixels = []
    for r in range(IMG_HEIGHT):
        row = []
        for c in range(IMG_WIDTH):
            val = ((r // 16) + (c // 16)) % 2 * 180 + (r * 3 + c * 7) % 70
            val = min(255, max(0, val))
            row.append(val)
        pixels.append(row)

    with open(filename, "w") as f:
        for r in range(IMG_HEIGHT):
            for c in range(IMG_WIDTH):
                f.write(f"{pixels[r][c]:02x}\n")

    return pixels

def compute_golden_filter(pixels, mode=0, filename=None):
    """
    Simulates exact hardware convolution pipeline:
    - 3x3 window sliding raster
    - 9 products signed accumulation
    - Saturation clipping to [0, 255]
    """
    expected = []
    for r in range(1, IMG_HEIGHT - 1):
        for c in range(1, IMG_WIDTH - 1):
            gx = 0
            gy = 0
            g_sum = 0
            for kr in range(3):
                for kc in range(3):
                    pix = pixels[r - 1 + kr][c - 1 + kc]
                    gx += pix * SOBEL_X[kr][kc]
                    gy += pix * SOBEL_Y[kr][kc]
                    g_sum += pix * GAUSSIAN[kr][kc]

            abs_gx = abs(gx)
            abs_gy = abs(gy)

            if mode == 0:    # SOBEL_MAG
                comb = abs_gx + abs_gy
            elif mode == 1:  # SOBEL_X
                comb = abs_gx
            elif mode == 2:  # SOBEL_Y
                comb = abs_gy
            elif mode == 3:  # GAUSSIAN BLUR
                comb = g_sum >> 4
            else:
                comb = abs_gx + abs_gy

            out_pix = min(255, max(0, comb))
            expected.append(out_pix)

    if filename:
        with open(filename, "w") as f:
            for p in expected:
                f.write(f"{p:02x}\n")
        print(f"[GOLDEN_MODEL] Mode {mode}: Generated {len(expected)} expected pixels -> {filename}")

    return expected

if __name__ == "__main__":
    img = generate_test_image("input_pixels.hex")
    compute_golden_filter(img, mode=0, filename="expected_mode0_sobel_mag.hex")
    compute_golden_filter(img, mode=1, filename="expected_mode1_sobel_x.hex")
    compute_golden_filter(img, mode=2, filename="expected_mode2_sobel_y.hex")
    compute_golden_filter(img, mode=3, filename="expected_mode3_gaussian.hex")
    # Default for backwards compatibility
    compute_golden_filter(img, mode=0, filename="expected_pixels.hex")

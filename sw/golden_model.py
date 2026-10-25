#!/usr/bin/env python3
"""
Bit-accurate Python Golden Model for 2D Image Convolution / Sobel Accelerator.
Generates input test image, applies exact hardware-matching 3x3 convolution with
saturation clipping [0, 255], and outputs stimulus and expected hex files.
"""

import sys
import random

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

def generate_test_image(filename="input_pixels.hex"):
    """Creates a deterministic synthetic test pattern (checkerboard with gradient)."""
    pixels = []
    for r in range(IMG_HEIGHT):
        row = []
        for c in range(IMG_WIDTH):
            # Checkerboard + edge gradient
            val = ((r // 16) + (c // 16)) % 2 * 180 + (r + c) % 50
            val = min(255, max(0, val))
            row.append(val)
        pixels.append(row)

    with open(filename, "w") as f:
        for r in range(IMG_HEIGHT):
            for c in range(IMG_WIDTH):
                f.write(f"{pixels[r][c]:02x}\n")

    return pixels

def compute_golden_sobel(pixels, mode=0, filename="expected_pixels.hex"):
    """
    Simulates exact hardware convolution pipeline:
    - 3x3 window sliding raster
    - 9 products signed accumulation
    - Absolute value and saturation at 255
    """
    expected = []
    # RTL processes when 2 full rows + 2 pixels are buffered
    for r in range(1, IMG_HEIGHT - 1):
        for c in range(1, IMG_WIDTH - 1):
            gx = 0
            gy = 0
            for kr in range(3):
                for kc in range(3):
                    pix = pixels[r - 1 + kr][c - 1 + kc]
                    gx += pix * SOBEL_X[kr][kc]
                    gy += pix * SOBEL_Y[kr][kc]

            abs_gx = abs(gx)
            abs_gy = abs(gy)

            if mode == 0:  # SOBEL_MAG
                comb = abs_gx + abs_gy
            elif mode == 1: # SOBEL_X
                comb = abs_gx
            elif mode == 2: # SOBEL_Y
                comb = abs_gy
            else:
                comb = abs_gx + abs_gy

            out_pix = min(255, comb)
            expected.append(out_pix)

    with open(filename, "w") as f:
        for p in expected:
            f.write(f"{p:02x}\n")

    print(f"[GOLDEN_MODEL] Generated {len(expected)} expected pixels for {IMG_WIDTH}x{IMG_HEIGHT} frame.")
    return expected

if __name__ == "__main__":
    img = generate_test_image("input_pixels.hex")
    exp = compute_golden_sobel(img, mode=0, filename="expected_pixels.hex")

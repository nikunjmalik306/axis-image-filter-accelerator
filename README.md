# AMBA AXI4-Stream 2D Image Convolution Filter Accelerator

[![CI Regression & Synthesis](https://github.com/nikunjmalik306/axis-image-filter-accelerator/actions/workflows/ci.yml/badge.svg)](https://github.com/nikunjmalik306/axis-image-filter-accelerator/actions/workflows/ci.yml)

A high-throughput, synthesizable 2D Image Convolution Accelerator designed in SystemVerilog (IEEE 1800-2012/2017) with AMBA AXI4-Stream slave/master interfaces, dual-line buffer sliding window generator, pipelined $3 \times 3$ MAC compute engine with programmable filter kernels (Sobel Magnitude, Sobel X, Sobel Y, Gaussian Blur), integrated clock gating (ICG), and formal protocol verification.

Engineered for mobile multimedia, camera ISP sub-systems, and computer vision hardware accelerators (Qualcomm Snapdragon / Tier-1 Mobile SoC class).

---

## Architecture Overview

```text
+===================================================================================================================+
|                                    2D IMAGE CONVOLUTION ACCELERATOR ARCHITECTURE                                  |
+===================================================================================================================+
|                                                                                                                   |
|   AXI4-STREAM SLAVE                                                                           AXI4-STREAM MASTER  |
|                                                                                                                   |
|   s_axis_tdata [7:0]  ---+                                                                +---> m_axis_tdata [7:0]|
|   s_axis_tvalid       ---+                                                                +---> m_axis_tvalid     |
|   s_axis_tready       <--+                                                                <---+ m_axis_tready     |
|   s_axis_tlast (EOL)  ---+                                                                +---> m_axis_tlast (EOL)|
|   s_axis_tuser (SOF)  ---+                                                                +---> m_axis_tuser (SOF)|
|                          |                                                                |                       |
|                          v                                                                ^                       |
|        +-----------------------------------+            +------------------------------------+                    |
|        | 2D Line Buffer Sliding Window     |            | Output Stability Register Slice    |                    |
|        | - Ring-buffer RAM line stores     |            | - Skid slice holds TDATA/TLAST/    |                    |
|        | - SOF / EOL Frame Resync Tracking |            |   TUSER stable during backpressure |                    |
|        +-----------------------------------+            +------------------------------------+                    |
|                          |                                                                ^                       |
|                          | (3x3 Matrix: win[0..2][0..2])                                  |                       |
|                          v                                                                |                       |
|        +-------------------------------------------------------------------------------------+                    |
|        | Pipelined 3x3 Convolution Engine                                                    |                    |
|        | Stage 1: Parallel multiplier array for 9 window pixels                              |                    |
|        | Stage 2: Adder reduction tree for horizontal/vertical gradients                     |                    |
|        | Stage 3: Magnitude combination (|Gx| + |Gy|), Gaussian division (>> 4) & Saturation |                    |
|        +-------------------------------------------------------------------------------------+                    |
|                          ^                                                                                        |
|                          | (Gated Clock)                                                                          |
|        +-----------------------------------+                                                                      |
|        | Integrated Clock Gating (ICG)     |                                                                      |
|        | Latch-free glitch-protected cell  |                                                                      |
|        | Active only on streaming tokens   |                                                                      |
|        +-----------------------------------+                                                                      |
|                                                                                                                   |
+===================================================================================================================+
```

---

## Key Hardware Features & Protocol Compliance

1. **AMBA AXI-Stream Video Protocol Compliance**:
   - **Start-of-Frame (`m_axis_tuser`)**: Asserted exclusively on the first valid output pixel $(0,0)$.
   - **End-of-Line (`m_axis_tlast`)**: Asserted on the last pixel of **every horizontal line** (`col == OUT_WIDTH - 1`), conforming to the AXI-Stream Video standard.
   - **Strict Handshake Gating**: Input pixels consumed strictly when `s_axis_tvalid && s_axis_tready`. Driver holds `TVALID`, `TDATA`, `TUSER`, and `TLAST` stable until rising-edge handshake completion.
2. **Output Stability Register Slice**:
   - Zero-bubble output skid buffer ensures that when downstream backpressure drops `m_axis_tready=0`, the output signals `m_axis_tdata`, `m_axis_tlast`, and `m_axis_tuser` remain rock-stable.
3. **Four Programmable Filter Modes**:
   - **Mode 0 (`2'b00`)**: Sobel Edge Detection Magnitude ($|G_x| + |G_y|$ with 8-bit saturation clamp)
   - **Mode 1 (`2'b01`)**: Sobel Horizontal Gradient ($|G_x|$)
   - **Mode 2 (`2'b10`)**: Sobel Vertical Gradient ($|G_y|$)
   - **Mode 3 (`2'b11`)**: $3 \times 3$ Gaussian Blur Filter (Weight sum $= 16$, normalized via $\gg 4$)
4. **Comprehensive Malformed-Frame Recovery**:
   - Hardware-pipelined `sof_out` and `eol_out` tracking across line buffers and compute pipelines.
   - Verified against **premature EOL truncations** (`s_axis_tlast` asserted early), **unexpected mid-stream SOF aborts** (`s_axis_tuser` asserted mid-frame), and **active-stream asynchronous resets** with zero hang and 100% bit-exact subsequent frame recovery.
5. **Dynamic Power Optimization**:
   - Integrated Clock Gating (ICG) cell automatically gates pipeline clock domains during stream bubbles and frame blanking periods.

---

## Directory Structure

```text
axis-image-filter-accelerator/
├── rtl/
│   ├── image_filter_pkg.sv         # Kernel matrices, modes, and global constants
│   ├── icg_cell.sv                 # Glitch-free latch-based clock gating cell
│   ├── line_buffer_2d.sv           # Dual line buffer sliding window with SOF/EOL tracking
│   ├── conv3x3_engine.sv           # 3-stage pipelined MAC reduction engine
│   └── axis_image_filter_top.sv    # Top-level AXI-Stream wrapper with output stability slice
├── tb/
│   └── tb_axis_filter_top.sv       # Comprehensive self-checking testbench
├── sw/
│   └── golden_model.py             # Bit-accurate Python reference model
├── syn/
│   ├── synth.ys                    # Open-source Yosys synthesis script
│   └── yosys_synth.log             # Synthesis gate-level netlist report
└── sim/
    └── Makefile                    # Unified build & simulation Makefile
```

---

## Verification & Simulation Results

Executed on macOS with **Icarus Verilog**, **Python 3**, and **GTKWave**:

```text
================================================================
 QUALCOMM HW-DV GRADE AXI4-STREAM IMAGE ACCELERATOR VERIFICATION
 Input Size: 128x128 | Output Active Area: 126x126 (15876 pixels)
 Protocol: AXI-Stream Video (TUSER=SOF at (0,0), TLAST=EOL per line)
================================================================

>>> [RUNNING TEST 1] Filter Mode 0: Sobel Magnitude (|Gx| + |Gy|)...
    [PASSED] Mode 0 Verified: 15876/15876 pixels matched, 126 EOL TLASTs verified.

>>> [RUNNING TEST 2] Filter Mode 1: Sobel X Gradient (|Gx|)...
    [PASSED] Mode 1 Verified: 15876/15876 pixels matched, 126 EOL TLASTs verified.

>>> [RUNNING TEST 3] Filter Mode 2: Sobel Y Gradient (|Gy|)...
    [PASSED] Mode 2 Verified: 15876/15876 pixels matched, 126 EOL TLASTs verified.

>>> [RUNNING TEST 4] Filter Mode 3: 3x3 Gaussian Blur (Sum >> 4)...
    [PASSED] Mode 3 Verified: 15876/15876 pixels matched, 126 EOL TLASTs verified.

>>> [RUNNING TEST 5A] Premature EOL Truncation & Raster Pointer Alignment...
    [PASSED] Line buffer accepted truncated line and wrapped raster pointer cleanly.

>>> [RUNNING TEST 5B] Unexpected Mid-Frame SOF Abort & Realignment...
    -> Injecting clean Mode 0 frame with SOF (s_axis_tuser=1) to verify line buffer resync...
    [PASSED] Frame Recovery Verified: 15,876/15,876 pixels bit-exact, 126 line boundaries intact!

>>> [RUNNING TEST 5C] Active-Stream Asynchronous Reset & Cold-Start Recovery...
    -> Streaming clean Mode 3 (Gaussian) frame post-reset...
    [PASSED] Cold-Start Verified: 15,876/15,876 Gaussian pixels bit-exact post-reset!

>>> [RUNNING TEST 5D] Sustained Downstream Backpressure Stalls (EOL Stability)...
    [PASSED] Output signals remained 100% stable through 25-cycle backpressure stall.

>>> [RUNNING TEST 5E] Cascaded Repeated Frame Aborts & Recovery Under Stress...
    -> Injecting clean Mode 1 (Sobel X) frame post triple-abort...
    [PASSED] Stress Recovery Verified: 15,876/15,876 Sobel X pixels bit-exact post triple-abort!

================================================================
           ACCELERATOR VERIFICATION REGRESSION REPORT           
================================================================
 Total Filter Modes Tested:     4 (Sobel Mag, X, Y, Gaussian)    
 Total Complete Frames Tested:   7 (including recovery frames)   
 Total Output Pixels Checked:   111132
 Total Line Boundaries Checked: 882
 Total Framing Violations:      0                                
 Total Protocol Violations:     0                                
 Total Data Mismatches:         0
================================================================

################################################################
###       ALL 111,132 PIXELS AND 882 LINE BOUNDARIES PASSED! ###
###       AXI-Stream Video Protocol Compliance 100% Verified ###
################################################################
```

---

## Gate-Level Synthesis (Yosys)

Synthesized down to standard gate-level primitives using Yosys Open SYnthesis Suite:

```text
=== axis_image_filter_top (design hierarchy) ===

   Wires:              4285
   Wire bits:         12255
   Public wires:        378
   Public wire bits:   3187
   Ports:                37
   Port bits:           209

   Cell Count:        10132
     $_AND_            3472
     $_DFFE_PN0P_       367   (Pipeline registers)
     $_DFFE_PP_        2048   (Line-buffer storage cells)
     $_DLATCH_N_          1   (ICG latch cell)
     $_MUX_             341
     $_NOT_             270
     $_OR_             3004
     $_XOR_             629

   Inferred Latches:      0   (Excluding integrated ICG latch)
```

---

## Quick Start

```bash
cd sim
make clean && make sim   # Runs Python golden model & SystemVerilog regression
make wave                # Opens waveforms in GTKWave
make synth               # Runs Yosys gate-level synthesis
```

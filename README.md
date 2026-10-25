# AXI4-Stream 2D Image Convolution & Edge Detection Accelerator

A high-throughput, synthesizable 2D Image Convolution and Sobel Edge Detection Hardware Accelerator implemented in SystemVerilog (IEEE 1800-2012/2017). Designed for high-definition image streaming with AMBA AXI4-Stream master/slave interfaces, low-power Integrated Clock Gating (ICG), continuous 3x3 sliding-window line buffering, and robust frame boundary resynchronization (`s_axis_tuser` SOF recovery).

Targeted for Multimedia, Computer Vision, and Image Signal Processing (ISP) subsystems in modern mobile SoCs.

---

## Key Architectural Highlights

```
+========================================================================================================+
|                                    AXI4-STREAM 2D CONVOLUTION ACCELERATOR                              |
+========================================================================================================+
|                                                                                                        |
|  AXI-Stream In                                                             AXI-Stream Out              |
|  (TDATA, TVALID)  +------------------+     +------------------+     +------------------+  (TDATA,      |
|  ==============>==| 2D Line Buffer   |==>==| 3x3 Convolution  |==>==| Output Register  |==> VALID,     |
|                   | (2-Row Circular  |     | Compute Engine   |     | Slice (SOF / EOF |    TLAST,     |
|  <==============--|  SRAM Shift Reg) |     | (9 Parallel MACs |     |  Packet Framing) |    TUSER)     |
|  (TREADY          +------------------+     | + Adder Tree +   |     +------------------+               |
|   Backpressure)             ^              | Saturation Mux)  |               |                        |
|                             |              +------------------+               |                        |
|                             |                       ^                         |                        |
|                             +-----------------------|-------------------------+                        |
|                                                     |                                                  |
|                        +----------------------------+-----------------------------+                    |
|                        | Integrated Clock Gating (ICG) & Pipeline Stall Controller |                    |
|                        +----------------------------------------------------------+                    |
+========================================================================================================+
```

1. **AMBA AXI4-Stream Protocol Compliance**:
   - Gated input consumption: pixels are only consumed on completed handshakes (`s_axis_tvalid && s_axis_tready`).
   - Output skid buffer: strictly preserves `m_axis_tdata`, `m_axis_tlast`, and `m_axis_tuser` without glitching or mutating while `m_axis_tvalid == 1` and `m_axis_tready == 0`.
   - Start-of-Frame (`s_axis_tuser`) and End-of-Line (`s_axis_tlast`) tracking with mid-stream frame truncation recovery.
2. **Zero-Bubble 2D Line Buffer**:
   - Circular buffer storing two $128$-pixel raster rows.
   - Emits a fresh $3\times 3$ pixel window every single clock cycle without pipeline stalls.
3. **Pipelined Multi-Mode Arithmetic Unit**:
   - Stage 1: 9 parallel signed multipliers ($8\text{b} \times 8\text{b} \to 16\text{b}$).
   - Stage 2: Balanced adder tree summing 9 products into a 20-bit accumulator.
   - Stage 3: Dynamic gradient magnitude calculation ($|G_x| + |G_y|$) with saturation clipping $[0, 255]$.
   - Supports 4 operational modes:
     - **Mode 0**: Sobel Magnitude ($|G_x| + |G_y|$)
     - **Mode 1**: Sobel X Gradient ($|G_x|$)
     - **Mode 2**: Sobel Y Gradient ($|G_y|$)
     - **Mode 3**: 3x3 Gaussian Blur Smoothing ($\sum W_i \cdot P_i \gg 4$)
4. **Low Power Design (ICG)**:
   - Integrated latch-based clock gating shuts off clock distribution to line buffers and MAC arrays when input stream is idle or downstream is stalled.

---

## Directory Structure

```text
axis-image-filter-accelerator/
├── rtl/
│   ├── image_filter_pkg.sv      # Parameters, bit-widths, filter modes
│   ├── icg_cell.sv              # Latch-based Integrated Clock Gating module
│   ├── line_buffer_2d.sv        # 2D circular line buffer (3x3 window sliding raster & SOF recovery)
│   ├── conv3x3_engine.sv        # 3-stage pipelined MAC array and adder tree
│   └── axis_image_filter_top.sv # Top-level AXI-Stream wrapper & framing slice
├── sw/
│   └── golden_model.py          # Bit-accurate Python reference model generating all 4 modes
├── tb/
│   └── tb_axis_filter_top.sv    # Self-checking regression suite with protocol checkers
├── syn/
│   ├── synth.ys                 # Open-source Yosys synthesis script for macOS/Linux
│   ├── genus_run.tcl            # Cadence Genus ASIC synthesis script
│   └── constraints.sdc          # SDC timing constraints (250 MHz target)
└── sim/
    └── Makefile                 # Native build & simulation Makefile
```

---

## Verification & Simulation Results

Verified across **all 4 filter modes** plus a **frame truncation recovery test** against a bit-accurate Python NumPy reference model across 5 complete frames ($79,380$ total output pixels) with randomized downstream backpressure stalls:

```text
================================================================
 STARTING AXI4-STREAM IMAGE ACCELERATOR VERIFICATION SUITE     
 Frame Size: 128x128 | Output Valid Area: 126x126 (15876 pixels)
================================================================

>>> [RUNNING TEST 1] Filter Mode 0: Sobel Magnitude (|Gx| + |Gy|)...
    [PASSED] Mode 0 Verified: 15876/15876 pixels matched.

>>> [RUNNING TEST 2] Filter Mode 1: Sobel X Gradient (|Gx|)...
    [PASSED] Mode 1 Verified: 15876/15876 pixels matched.

>>> [RUNNING TEST 3] Filter Mode 2: Sobel Y Gradient (|Gy|)...
    [PASSED] Mode 2 Verified: 15876/15876 pixels matched.

>>> [RUNNING TEST 4] Filter Mode 3: 3x3 Gaussian Blur (Sum >> 4)...
    [PASSED] Mode 3 Verified: 15876/15876 pixels matched.

>>> [RUNNING TEST 5] Framing Resync Recovery Test...
    -> Asserting SOF (s_axis_tuser=1) for fresh frame recovery...
    [PASSED] Frame Recovery Verified: Line buffer cleanly resynchronized!

================================================================
           ACCELERATOR VERIFICATION REGRESSION REPORT           
================================================================
 Total Filter Modes Tested:     4 (Sobel Mag, X, Y, Gaussian)    
 Total Complete Frames Tested:   5 (including recovery frame)    
 Total Output Pixels Checked:   79380
 Total Protocol Violations:     0                                
 Total Data Mismatches:         0
================================================================

################################################################
###               ALL ACCELERATOR TESTS PASSED!              ###
###    Hardware RTL matches Python Golden Model in All Modes ###
################################################################
```

---

## Synthesis & Hardware Utilization

Synthesized down to gate-level primitives using **Yosys 0.70+**:

| Metric | Complete Accelerator Count |
| :--- | :--- |
| **Total Gate Count** | 10,125 primitive cells |
| **Sequential Storage** | 2,415 D-Flip-Flops (`$_DFFE_`) |
| **Clock Gating Cells** | 1 Integrated Clock Gating (ICG) latch cell (`$_DLATCH_N_`) |
| **Logic Breakdown** | 3,475 `$_AND_`, 2,945 `$_OR_`, 629 `$_XOR_`, 341 `$_MUX_`, 319 `$_NOT_` |
| **Timing & Latch Violations**| 0 inferred latches; 100% synchronous datapath |

---

## How to Run on macOS

```bash
# 1. Run bit-accurate Python co-simulation with Icarus Verilog
cd sim
make sim

# 2. View waveforms in GTKWave
make wave

# 3. Run logic synthesis
make synth
```

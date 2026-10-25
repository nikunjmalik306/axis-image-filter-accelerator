# AXI4-Stream 2D Image Convolution & Edge Detection Accelerator

A high-throughput, synthesizable 2D Image Convolution and Sobel Edge Detection Hardware Accelerator implemented in SystemVerilog (IEEE 1800-2012/2017). Designed for high-definition image streaming with AMBA AXI4-Stream master/slave interfaces, low-power Integrated Clock Gating (ICG), and continuous 3x3 sliding-window line buffering.

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
   - Decoupled `s_axis_tready` and `m_axis_tvalid` handshakes with backpressure support.
   - Start-of-Frame (`s_axis_tuser`) and End-of-Frame (`s_axis_tlast`) detection and regeneration.
2. **Zero-Bubble 2D Line Buffer**:
   - Circular buffer storing two $128$-pixel raster rows.
   - Emits a fresh $3\times 3$ pixel window every single clock cycle without pipeline stalls.
3. **Pipelined Arithmetic Unit**:
   - Stage 1: 9 parallel signed multipliers ($8\text{b} \times 8\text{b} \to 16\text{b}$).
   - Stage 2: Balanced adder tree summing 9 products into a 20-bit accumulator.
   - Stage 3: Dynamic gradient magnitude calculation ($|G_x| + |G_y|$) with saturation clipping $[0, 255]$.
   - Supports 4 modes: Sobel Magnitude, Sobel X, Sobel Y, and 3x3 Gaussian Blur.
4. **Low Power Design (ICG)**:
   - Integrated latch-based clock gating shuts off clock distribution to line buffers and MAC arrays when input stream is idle or downstream is stalled.

---

## Directory Structure

```text
axis-image-filter-accelerator/
├── rtl/
│   ├── image_filter_pkg.sv      # Parameters, bit-widths, filter modes
│   ├── icg_cell.sv              # Latch-based Integrated Clock Gating module
│   ├── line_buffer_2d.sv        # 2D circular line buffer (3x3 window sliding raster)
│   ├── conv3x3_engine.sv        # 3-stage pipelined MAC array and adder tree
│   └── axis_image_filter_top.sv # Top-level AXI-Stream wrapper & framing slice
├── sw/
│   └── golden_model.py          # Bit-accurate Python reference model & hex generator
├── tb/
│   └── tb_axis_filter_top.sv    # Self-checking testbench with randomized backpressure
├── syn/
│   ├── synth.ys                 # Open-source Yosys synthesis script for macOS/Linux
│   ├── genus_run.tcl            # Cadence Genus ASIC synthesis script
│   └── constraints.sdc          # SDC timing constraints (250 MHz target)
└── sim/
    └── Makefile                 # Native build & simulation Makefile
```

---

## Verification & Simulation Results

Verified using an automated self-checking testbench co-simulated with a bit-accurate Python NumPy/math reference model across a full $128 \times 128$ image frame ($16,384$ pixels) with randomized $10\%$ downstream backpressure stalls:

```text
================================================================
   FINAL VERIFICATION SUMMARY REPORT
================================================================
Total Pixels Streamed In:  16384
Total Pixels Received Out: 15876 / 15876 expected
Total Pixel Mismatches:    0

################################################################
###                 ALL TESTS PASSED!                        ###
###    Hardware RTL matches Python Golden Model bit-for-bit  ###
################################################################
```

---

## Synthesis & Hardware Utilization

Synthesized down to gate-level primitives using **Yosys 0.70+**:

| Metric | Complete Accelerator Count |
| :--- | :--- |
| **Total Gate Count** | 9,948 primitive cells |
| **Sequential Storage** | 2,418 D-Flip-Flops (DFFE) |
| **Clock Gating Cells** | 1 Integrated Clock Gating (ICG) latch cell |
| **Logic Gates** | 3,465 `$_AND_`, 2,936 `$_OR_`, 632 `$_XOR_`, 173 `$_MUX_` |
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

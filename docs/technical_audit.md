# Technical Audit & Architectural Specification: AMBA AXI4-Stream Image Filter Accelerator

**Repository:** `axis-image-filter-accelerator`  
**Standard:** SystemVerilog IEEE 1800-2012 / 1800-2017 | AMBA AXI4-Stream Video Protocol  
**Target ASIC Roles:** Qualcomm Multimedia / Camera ISP Hardware Accelerator / Digital ASIC Design  

---

## 1. Architectural Overview & Module Breakdown

The accelerator implements a high-throughput, fully pipelined 2D image convolution engine capable of processing one pixel per clock cycle with zero bubbles during steady-state streaming. It interfaces seamlessly with standard AMBA AXI4-Stream video pipelines.

```
                           +---------------------------------------+
                           |       AXI4-Stream Video Master        |
                           |  (s_axis_tdata, tvalid, tready, etc.) |
                           +---------------------------------------+
                                              |
                                              v
+-----------------------------------------------------------------------------------------+
| axis_image_filter_top                                                                   |
|                                                                                         |
|  +---------------------------+   3x3 Window   +-------------------------------------+   |
|  | line_buffer_2d            |  (9x 8-bit)    | conv3x3_engine                      |   |
|  | - Circular dual RAM lines |--------------->| - Stage 1: 9x Pipelined Multipliers |   |
|  | - Pointer wrap & resync   |                | - Stage 2: Adder Reduction Tree     |   |
|  | - SOF (TUSER) & EOL (TLAST)|               | - Stage 3: Mode Comb & Saturation   |   |
|  +---------------------------+                +-------------------------------------+   |
|                                                                  |                      |
|                                                                  v                      |
|  +---------------------------+   Gated Clock  +-------------------------------------+   |
|  | icg_cell (Clock Gating)   |--------------->| Output Skid Buffer / Register Slice |   |
|  | - Latch-based glitch-free |                | - Zero-bubble backpressure hold     |   |
|  | - TSMC/Foundry macro hook |                | - Rock-stable TDATA/TLAST/TUSER     |   |
|  +---------------------------+                +-------------------------------------+   |
|                                                                  |                      |
+------------------------------------------------------------------|----------------------+
                                                                   v
                                               +---------------------------------------+
                                               |       AXI4-Stream Video Slave         |
                                               |  (m_axis_tdata, tvalid, tready, etc.) |
                                               +---------------------------------------+
```

### Module Responsibilities:
1. **`axis_image_filter_top.sv`**:
   - Top-level integration wrapper connecting line buffer, convolution engine, and output register slice.
   - Coordinates dynamic clock gating enable (`pipeline_en = s_axis_tvalid && s_axis_tready`).
   - Contains an output skid buffer register slice preventing pipeline bubbles and preserving protocol stability during downstream backpressure (`m_axis_tready = 0`).

2. **`line_buffer_2d.sv`**:
   - Parameterized for arbitrary `IMG_WIDTH` and `IMG_HEIGHT` (default: $128 \times 128$; verified also on $64 \times 64$).
   - Dual circular line stores storing the previous two raster lines.
   - Outputs a sliding $3 \times 3$ pixel spatial window (`window_out[8:0]`) every cycle.
   - Propagates Start-of-Frame (`sof_out`) and End-of-Line (`eol_out`) tags through the raster delay line.

3. **`conv3x3_engine.sv`**:
   - Pipelined 3-stage multiply-accumulate (MAC) reduction datapath:
     - **Stage 1 (Multipliers):** Computes $9 \times$ products for $G_x$, $9 \times$ for $G_y$, and $9 \times$ for Gaussian blur in parallel using packed constant coefficient lookup vectors.
     - **Stage 2 (Adder Reduction Tree):** Computes signed horizontal and vertical partial sums through balanced adder trees.
     - **Stage 3 (Magnitude, Normalization & Saturation):** Computes $|G_x| + |G_y|$ (Sobel Mag), $|G_x|$ (Sobel X), $|G_y|$ (Sobel Y), or $(G_{\text{sum}} \gg 4)$ (Gaussian), clamping results to $[0, 255]$ with saturation logic.

4. **`icg_cell.sv`**:
   - Industry-standard latch-based integrated clock gating cell.
   - Includes conditional compilation hook for foundry atomic cells (`ASIC_FOUNDRY_ICG`, e.g., TSMC `CKLNQD1`), while defaulting to a transparent low-phase latch behavioral model for FPGA and open-source simulators.

5. **`image_filter_pkg.sv`**:
   - Defines filter modes (`MODE_SOBEL_MAG = 2'b00`, `MODE_SOBEL_X = 2'b01`, `MODE_SOBEL_Y = 2'b10`, `MODE_GAUSSIAN = 2'b11`), bit widths, and arithmetic saturation boundaries.

---

## 2. Protocol, Framing, & Boundary Audit

### AXI4-Stream Handshake Qualification:
- **Rule:** Per AMBA AXI4-Stream Protocol Specification, once `s_axis_tvalid` is asserted, payload signals (`tdata`, `tlast`, `tuser`) must remain unchanged until `s_axis_tready` is asserted on a rising clock edge.
- **Audit Result:** PASSED. The verification driver was updated to enforce synchronous handshake completion:
  ```systemverilog
  s_axis_tvalid <= 1'b1;
  s_axis_tdata  <= pixel_val;
  s_axis_tuser  <= is_sof;
  s_axis_tlast  <= is_eol;
  do @(posedge aclk); while (!s_axis_tready);
  ```
  The RTL line-buffer processes incoming data strictly when `s_axis_tvalid && s_axis_tready`.

### AXI-Stream Video Framing Standard:
- **Start-of-Frame (`TUSER`)**: Driven high strictly on the first pixel of each frame (pixel $(0,0)$).
- **End-of-Line (`TLAST`)**: Driven high on the last pixel of **every horizontal raster line** (`col == OUT_WIDTH - 1`), conforming to Section 2.2 of the AMBA AXI4-Stream Video IP specification.
- **Audit Result:** Verified across 8 complete frames (944 individual line boundaries) with zero framing errors.

### Output Stability Under Backpressure:
- When downstream consumer deasserts `m_axis_tready = 0`, the output skid buffer freezes `m_axis_tvalid`, `m_axis_tdata`, `m_axis_tlast`, and `m_axis_tuser` with zero glitch or data mutation.
- **Audit Result:** Verified by Test 5D injecting sustained 25-cycle backpressure stalls directly on line boundaries (`TLAST = 1`). Hardware assertions confirmed $100\%$ signal stability.

---

## 3. Corner Cases & Stress Verification Audit

The design was subjected to six targeted verification suites in `tb/tb_axis_filter_top.sv`:

| Test Suite | Description | Vectors / Frames | Pass Criteria | Result |
| :--- | :--- | :--- | :--- | :--- |
| **Test 1** | Filter Mode 0: Sobel Magnitude | 1 Frame (15,876 px) | Bit-exact match to Python model; 126 EOLs | **PASSED** |
| **Test 2** | Filter Mode 1: Sobel X Gradient | 1 Frame (15,876 px) | Bit-exact match to Python model; 126 EOLs | **PASSED** |
| **Test 3** | Filter Mode 2: Sobel Y Gradient | 1 Frame (15,876 px) | Bit-exact match to Python model; 126 EOLs | **PASSED** |
| **Test 4** | Filter Mode 3: 3x3 Gaussian Blur | 1 Frame (15,876 px) | Bit-exact match to Python model; 126 EOLs | **PASSED** |
| **Test 5A** | Premature EOL Truncation | Injected 30-px row | Line buffer realigns raster pointer cleanly | **PASSED** |
| **Test 5B** | Unexpected Mid-Frame SOF Abort | 320 garbage pixels + SOF | Immediate line buffer reset and frame resync | **PASSED** |
| **Test 5C** | Active-Stream Async Reset | Reset during active MAC | Immediate output flush to 0; clean cold start | **PASSED** |
| **Test 5D** | Sustained Backpressure (EOL) | 25-cycle stall on TLAST | 0 data change during stall; 0 dropped tokens | **PASSED** |
| **Test 5E** | Cascaded Repeated Aborts | 45, 110, 215 aborted px | 100% bit-exact recovery on subsequent frame | **PASSED** |
| **Test 6** | Parameter Generality ($64 \times 64$) | 1 Frame (3,844 px) | 62 line boundaries verified; zero framing drift | **PASSED** |

**Total Verification Statistics:**
- Total Frames Verified: **8**
- Total Active Pixels Checked: **114,976**
- Total Line Boundaries Checked: **944**
- Total Data Mismatches: **0**
- Total Framing / Protocol Violations: **0**

---

## 4. Synthesis & Cell Area Audit (Yosys)

Synthesized using Yosys Open SYnthesis Suite targeting generic ASIC standard cell primitives:

```text
=== axis_image_filter_top (Design Hierarchy Summary) ===

   Wires:              4,285
   Wire bits:         12,255
   Public wires:         378
   Public wire bits:   3,187
   Ports:                 37
   Port bits:            209

   Cell Count:        10,132
     $_AND_            3,472
     $_DFFE_PN0P_        367   (Compute pipeline & skid registers)
     $_DFFE_PP_        2,048   (Line-buffer storage cells: 2 x 128 x 8-bit)
     $_DLATCH_N_           1   (Integrated clock gating latch cell)
     $_MUX_              341
     $_NOT_              270
     $_OR_             3,004
     $_XOR_              629

   Inferred Latches:       0   (Excluding deliberate ICG latch)
```

### Key ASIC Implementation Notes:
1. **Zero Unintended Latches:** The datapath and control FSM are completely latch-free. The single inferred latch (`$_DLATCH_N_`) belongs exclusively to `icg_cell.sv`, which implements the IEEE clock-gating latch protocol.
2. **Static Sensitivity Cleanliness:** Refactored kernel tables into packed constant bit-vectors (`SOBEL_X_COEFFS`, `SOBEL_Y_COEFFS`, `GAUSS_COEFFS`), eliminating all `always_comb` sensitivity warnings.
3. **Foundry Portability:** Macro hook `ASIC_FOUNDRY_ICG` enables instant drop-in replacement of foundry clock gates (e.g. TSMC `CKLNQD1`) during physical design without modifying RTL.

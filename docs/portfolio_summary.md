# Portfolio Summary: AMBA AXI4-Stream Image Filter Accelerator

**Target Roles at Qualcomm:**  
- Digital ASIC Design Engineer (Camera ISP / Multimedia Hardware Subsystems)  
- Design Verification Engineer (Video & Image Processing Acceleration)  
- RTL Design & SoC Integration Engineer  

---

## 1. Resume-Ready Engineering Bullets (STAR Format)

- **Architected and verified an AMBA AXI4-Stream 2D Image Convolution Accelerator in SystemVerilog**, implementing a 3-stage pipelined MAC reduction tree supporting 4 programmable filter modes (Sobel Magnitude, Sobel X, Sobel Y, 3x3 Gaussian Blur) with single-cycle pixel throughput.
- **Engineered an AXI-Stream Video compliant interface with dual-line buffer sliding window generator**, enforcing strict handshake qualification (`s_axis_tvalid && s_axis_tready`), `TUSER` start-of-frame tracking on pixel $(0,0)$, and `TLAST` end-of-line signaling across 944 verified line boundaries.
- **Implemented zero-bubble output skid register slice and integrated clock gating (ICG)** with foundry macro hooks (TSMC `CKLNQD1`), preventing pipeline bubbles, ensuring rock-stable output signals under backpressure stalls, and eliminating dynamic clock power during stream idle phases.
- **Developed a bit-accurate Python golden reference model and self-checking SystemVerilog testbench**, executing 8 complete frames (114,976 pixels) across normal streaming, premature line truncation, mid-frame SOF aborts, active-stream resets, and sustained backpressure stalls with zero mismatches.
- **Achieved clean gate-level synthesis with Yosys (10,132 standard cells, 0 unintended latches)** and clean linting, proving structural ASIC readiness for mobile SoC multimedia pipelines.

---

## 2. Key Technical Metrics & Evidence

| Metric | Measured Value | Verification Evidence |
| :--- | :--- | :--- |
| **Throughput** | 1 pixel / clock cycle (steady-state) | Zero-bubble pipeline verified via waveform trace |
| **Pipeline Latency** | 3 clock cycles (compute) + line buffer fill | Deterministic pipeline latency verified in testbench |
| **Total Frames Verified** | 8 frames (7x $128 \times 128$ + 1x $64 \times 64$) | Full regression run passed in `sim/Makefile` |
| **Total Output Pixels** | 114,976 pixels bit-exact | Verified against Python golden model (`sw/golden_model.py`) |
| **Line Boundaries Checked** | 944 EOL boundaries | Strict `m_axis_tlast` assertion at every row end |
| **Fault Recovery Suites** | 5 stress cases (abort, truncate, reset, stall) | Test 5A-5E passed with clean resynchronization |
| **Gate Count (Yosys)** | 10,132 cells (2,415 sequential, 7,716 combinational) | `syn/yosys_synth.log` gate-level netlist report |
| **Latch Count** | 0 unintended latches (1 deliberate ICG latch) | Confirmed via `PROC_DLATCH` synthesis audit |

---

## 3. Key Design Tradeoffs & ASIC Architecture Decisions

1. **Dual Circular Line Buffer vs. 2D Frame Buffer:**
   - *Tradeoff:* Storing full frames off-chip or in large on-chip SRAM consumes significant area and memory bandwidth.
   - *Design Choice:* Designed dual circular line buffers holding only $2 \times W$ pixels ($2 \times 128 \times 8 = 2\text{ KB}$ of storage). Pixels stream through the line buffers in raster order, sliding a $3 \times 3$ window across the stream in real time.

2. **Pipelined Adder Reduction Tree vs. Single-Cycle Accumulation:**
   - *Tradeoff:* Accumulating 9 product terms in a single cycle creates a long combinational path through multiple 12-bit adders, severely limiting maximum clock frequency ($F_{\text{max}}$).
   - *Design Choice:* Decomposed MAC engine into 3 distinct pipeline stages (Stage 1: Multipliers, Stage 2: Balanced adder tree, Stage 3: Mode combination & saturation). This keeps stage delays under 15 gate delays, supporting high-frequency operation in modern mobile process nodes.

3. **Output Skid Register Slice vs. Full Asynchronous FIFO:**
   - *Tradeoff:* An AXI FIFO adds unnecessary latency, area, and gray-code synchronization complexity when operating in a single clock domain.
   - *Design Choice:* Implemented a zero-bubble skid register slice directly on the master interface. When downstream drops `m_axis_tready = 0`, the skid register captures the current cycle's data while presenting frozen output signals, preventing upstream pipeline stalls from causing data drops.

4. **Transparent Low-Phase Latch Clock Gating (ICG):**
   - *Tradeoff:* AND-gating a clock directly with an enable signal causes severe glitches if the enable changes when the clock is high.
   - *Design Choice:* Employed an industry-standard negative-latch ICG cell. The latch samples enable on `clk = 0` and holds it stable throughout the positive clock phase, guaranteeing glitch-free gated clock outputs. Provided conditional macro hooks for TSMC/Foundry atomic cells (`ASIC_FOUNDRY_ICG`).

---

## 4. Technical Interview Talking Points

- **Q: How does your line buffer handle the vertical latency and boundary rows of the image?**  
  *Answer:* Because a $3 \times 3$ convolution requires one line above and one line below the center pixel, the line buffer must buffer two complete raster lines before valid output convolution can begin. Valid output starts at pixel $(1, 1)$. For an $N \times N$ image, the active output area is $(N-2) \times (N-2)$. The line buffer hardware automatically generates `sof_out` when the first valid $3 \times 3$ window is formed, and generates `eol_out` at the end of each valid processed row.

- **Q: What happens if downstream asserts backpressure on the exact cycle that an EOL (`TLAST`) packet is emitted?**  
  *Answer:* The output skid slice buffers the active token, keeping `m_axis_tvalid = 1`, `m_axis_tlast = 1`, and `m_axis_tdata` perfectly stable across arbitrary clock cycles until `m_axis_tready` rises. This was explicitly verified under 25 consecutive backpressure cycles in Test 5D.

- **Q: How did you verify the accelerator against non-ideal camera sensor behavior?**  
  *Answer:* Real camera sensors can experience MIPI CSI-2 frame drops, electrical glitches, or sudden software aborts. I implemented Tests 5A and 5B to inject truncated lines (30 pixels followed by premature `TLAST`) and mid-stream corrupted pixels followed by unexpected `TUSER`. The line buffer resets its internal pointers upon receiving `TUSER` or pointer wrap, discarding malformed line fragments and achieving $100\%$ bit-exact recovery on subsequent frames without system hang.

// ==============================================================================
// File: icg_cell.sv
// Description: Integrated Clock Gating (ICG) cell using positive-level latch
//              and AND gate for glitch-free dynamic power gating.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

`timescale 1ns / 1ps

module icg_cell (
  input  logic clk_in,
  input  logic enable,
  input  logic test_mode,   // Scan-test override to bypass clock gating in DFT
  output logic clk_out
);

`ifdef ASIC_FOUNDRY_ICG
  // Direct TSMC / GF standard-cell foundry ICG cell (e.g. CKLNQD1)
  // Ensures Clock Tree Synthesis (CTS) treats this as an atomic clock gate
  CKLNQD1 u_foundry_icg (
    .CK (clk_in),
    .E  (enable),
    .TE (test_mode),
    .Q  (clk_out)
  );
`else
  // Architectural behavioral model:
  // Latch enable on clock LOW phase to guarantee glitch-free operation when clk_in rises
  logic latch_en;

  always_latch begin
    if (!clk_in) begin
      latch_en <= enable | test_mode;
    end
  end

  assign clk_out = clk_in & latch_en;
`endif

endmodule

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

  logic latch_en;

  // Latch the enable signal when clock is LOW to prevent glitches when clk_in rises
  always_latch begin
    if (!clk_in) begin
      latch_en <= enable | test_mode;
    end
  end

  assign clk_out = clk_in & latch_en;

endmodule

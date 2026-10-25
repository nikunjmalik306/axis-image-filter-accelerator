// ==============================================================================
// File: conv3x3_engine.sv
// Description: Pipelined 3x3 2D Convolution and Sobel / Gaussian arithmetic core.
//              Performs 9 parallel multiplications, adder tree summation,
//              magnitude calculation, and rounding/clamping to [0, 255].
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

`timescale 1ns / 1ps

module conv3x3_engine #(
  parameter int PIXEL_WIDTH = 8
)(
  input  logic                                  clk,
  input  logic                                  rst_n,
  input  logic                                  en,
  input  logic [1:0]                            mode,
  input  logic [(9*PIXEL_WIDTH)-1:0]            window_in,
  input  logic                                  valid_in,
  input  logic                                  sof_in,
  input  logic                                  eol_in,

  output logic [PIXEL_WIDTH-1:0]                pixel_out,
  output logic                                  valid_out,
  output logic                                  sof_out,
  output logic                                  eol_out,
  output logic                                  s1_valid_o,
  output logic                                  s2_valid_o
);

  localparam PROD_WIDTH = image_filter_pkg::PROD_WIDTH;
  localparam ACC_WIDTH  = image_filter_pkg::ACC_WIDTH;

  // Kernel Coefficients (Packed constant vectors for universal synthesis and zero simulation warnings)
  localparam logic signed [71:0] SOBEL_X_COEFFS = {
    -8'sd1,  8'sd0,  8'sd1,
    -8'sd2,  8'sd0,  8'sd2,
    -8'sd1,  8'sd0,  8'sd1
  };

  localparam logic signed [71:0] SOBEL_Y_COEFFS = {
    -8'sd1, -8'sd2, -8'sd1,
     8'sd0,  8'sd0,  8'sd0,
     8'sd1,  8'sd2,  8'sd1
  };

  localparam logic signed [71:0] GAUSS_COEFFS = {
     8'sd1,  8'sd2,  8'sd1,
     8'sd2,  8'sd4,  8'sd2,
     8'sd1,  8'sd2,  8'sd1
  };

  // --------------------------------------------------------------------------
  // Stage 1: Pipelined Multipliers (9 parallel products for Gx, 9 for Gy)
  // --------------------------------------------------------------------------
  logic signed [PROD_WIDTH-1:0] gx_mult [0:2][0:2];
  logic signed [PROD_WIDTH-1:0] gy_mult [0:2][0:2];
  logic signed [PROD_WIDTH-1:0] gauss_mult [0:2][0:2];
  logic                         s1_valid;
  logic [1:0]                   s1_mode;

  genvar gr, gc;
  generate
    for (gr = 0; gr < 3; gr++) begin : gen_mult_row
      for (gc = 0; gc < 3; gc++) begin : gen_mult_col
        wire [PIXEL_WIDTH-1:0] cur_px = window_in[(8 - (gr*3 + gc))*PIXEL_WIDTH +: PIXEL_WIDTH];
        wire signed [7:0]      k_sx   = SOBEL_X_COEFFS[(8 - (gr*3 + gc))*8 +: 8];
        wire signed [7:0]      k_sy   = SOBEL_Y_COEFFS[(8 - (gr*3 + gc))*8 +: 8];
        wire signed [7:0]      k_ga   = GAUSS_COEFFS[(8 - (gr*3 + gc))*8 +: 8];

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            gx_mult[gr][gc]    <= '0;
            gy_mult[gr][gc]    <= '0;
            gauss_mult[gr][gc] <= '0;
          end else if (en) begin
            gx_mult[gr][gc]    <= $signed({1'b0, cur_px}) * k_sx;
            gy_mult[gr][gc]    <= $signed({1'b0, cur_px}) * k_sy;
            gauss_mult[gr][gc] <= $signed({1'b0, cur_px}) * k_ga;
          end
        end
      end
    end
  endgenerate

  logic s1_sof;
  logic s1_eol;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
      s1_mode  <= 2'b00;
      s1_sof   <= 1'b0;
      s1_eol   <= 1'b0;
    end else if (en) begin
      s1_valid <= valid_in;
      s1_mode  <= mode;
      s1_sof   <= sof_in;
      s1_eol   <= eol_in;
    end
  end

  assign s1_valid_o = s1_valid;

  // --------------------------------------------------------------------------
  // Stage 2: Adder Tree
  // --------------------------------------------------------------------------
  logic signed [ACC_WIDTH-1:0] sum_gx;
  logic signed [ACC_WIDTH-1:0] sum_gy;
  logic signed [ACC_WIDTH-1:0] sum_gauss;
  logic                        s2_valid;
  logic [1:0]                  s2_mode;
  logic                        s2_sof;
  logic                        s2_eol;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_valid  <= 1'b0;
      s2_mode   <= 2'b00;
      s2_sof    <= 1'b0;
      s2_eol    <= 1'b0;
      sum_gx    <= '0;
      sum_gy    <= '0;
      sum_gauss <= '0;
    end else if (en) begin
      s2_valid  <= s1_valid;
      s2_mode   <= s1_mode;
      s2_sof    <= s1_sof;
      s2_eol    <= s1_eol;
      sum_gx    <= gx_mult[0][0] + gx_mult[0][1] + gx_mult[0][2] +
                   gx_mult[1][0] + gx_mult[1][1] + gx_mult[1][2] +
                   gx_mult[2][0] + gx_mult[2][1] + gx_mult[2][2];

      sum_gy    <= gy_mult[0][0] + gy_mult[0][1] + gy_mult[0][2] +
                   gy_mult[1][0] + gy_mult[1][1] + gy_mult[1][2] +
                   gy_mult[2][0] + gy_mult[2][1] + gy_mult[2][2];

      sum_gauss <= gauss_mult[0][0] + gauss_mult[0][1] + gauss_mult[0][2] +
                   gauss_mult[1][0] + gauss_mult[1][1] + gauss_mult[1][2] +
                   gauss_mult[2][0] + gauss_mult[2][1] + gauss_mult[2][2];
    end
  end

  assign s2_valid_o = s2_valid;

  // --------------------------------------------------------------------------
  // Stage 3: Magnitude, Normalization & Saturation
  // --------------------------------------------------------------------------
  logic signed [ACC_WIDTH-1:0] abs_gx;
  logic signed [ACC_WIDTH-1:0] abs_gy;
  logic [ACC_WIDTH-1:0]        combined_val;

  always_comb begin
    abs_gx = (sum_gx < 0) ? -sum_gx : sum_gx;
    abs_gy = (sum_gy < 0) ? -sum_gy : sum_gy;

    case (s2_mode)
      2'b00:   combined_val = abs_gx + abs_gy; // MODE_SOBEL_MAG
      2'b01:   combined_val = abs_gx;          // MODE_SOBEL_X
      2'b10:   combined_val = abs_gy;          // MODE_SOBEL_Y
      2'b11:   combined_val = sum_gauss >>> 4; // MODE_GAUSSIAN
      default: combined_val = abs_gx + abs_gy;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      sof_out   <= 1'b0;
      eol_out   <= 1'b0;
      pixel_out <= '0;
    end else if (en) begin
      valid_out <= s2_valid;
      sof_out   <= s2_sof;
      eol_out   <= s2_eol;
      if (combined_val > 20'd255) begin
        pixel_out <= 8'd255;
      end else begin
        pixel_out <= combined_val[7:0];
      end
    end
  end

endmodule

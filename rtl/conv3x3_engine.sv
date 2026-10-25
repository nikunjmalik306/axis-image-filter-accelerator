// ==============================================================================
// File: conv3x3_engine.sv
// Description: Pipelined 3x3 2D Convolution and Sobel / Gaussian arithmetic core.
//              Performs 9 parallel multiplications, adder tree summation,
//              magnitude calculation, and rounding/clamping to [0, 255].
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

`timescale 1ns / 1ps

import image_filter_pkg::*;

module conv3x3_engine #(
  parameter int PIXEL_WIDTH = 8
)(
  input  logic                                  clk,
  input  logic                                  rst_n,
  input  logic                                  en,
  input  logic [1:0]                            mode,
  input  logic [(9*PIXEL_WIDTH)-1:0]            window_in,
  input  logic                                  valid_in,

  output logic [PIXEL_WIDTH-1:0]                pixel_out,
  output logic                                  valid_out,
  output logic                                  s1_valid_o,
  output logic                                  s2_valid_o
);

  // Kernel Coefficients
  logic signed [7:0] sobel_x [0:2][0:2];
  logic signed [7:0] sobel_y [0:2][0:2];
  logic signed [7:0] gauss [0:2][0:2];

  always_comb begin
    sobel_x[0][0] = -8'sd1; sobel_x[0][1] =  8'sd0; sobel_x[0][2] =  8'sd1;
    sobel_x[1][0] = -8'sd2; sobel_x[1][1] =  8'sd0; sobel_x[1][2] =  8'sd2;
    sobel_x[2][0] = -8'sd1; sobel_x[2][1] =  8'sd0; sobel_x[2][2] =  8'sd1;

    sobel_y[0][0] = -8'sd1; sobel_y[0][1] = -8'sd2; sobel_y[0][2] = -8'sd1;
    sobel_y[1][0] =  8'sd0; sobel_y[1][1] =  8'sd0; sobel_y[1][2] =  8'sd0;
    sobel_y[2][0] =  8'sd1; sobel_y[2][1] =  8'sd2; sobel_y[2][2] =  8'sd1;

    gauss[0][0]   =  8'sd1; gauss[0][1]   =  8'sd2; gauss[0][2]   =  8'sd1;
    gauss[1][0]   =  8'sd2; gauss[1][1]   =  8'sd4; gauss[1][2]   =  8'sd2;
    gauss[2][0]   =  8'sd1; gauss[2][1]   =  8'sd2; gauss[2][2]   =  8'sd1;
  end

  // Unpack window matrix from flattened input vector for synthesis portability
  logic [PIXEL_WIDTH-1:0] win [0:2][0:2];
  assign {win[0][0], win[0][1], win[0][2],
          win[1][0], win[1][1], win[1][2],
          win[2][0], win[2][1], win[2][2]} = window_in;

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
        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            gx_mult[gr][gc]    <= '0;
            gy_mult[gr][gc]    <= '0;
            gauss_mult[gr][gc] <= '0;
          end else if (en) begin
            gx_mult[gr][gc]    <= $signed({1'b0, win[gr][gc]}) * sobel_x[gr][gc];
            gy_mult[gr][gc]    <= $signed({1'b0, win[gr][gc]}) * sobel_y[gr][gc];
            gauss_mult[gr][gc] <= $signed({1'b0, win[gr][gc]}) * gauss[gr][gc];
          end
        end
      end
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
      s1_mode  <= 2'b00;
    end else if (en) begin
      s1_valid <= valid_in;
      s1_mode  <= mode;
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_valid  <= 1'b0;
      s2_mode   <= 2'b00;
      sum_gx    <= '0;
      sum_gy    <= '0;
      sum_gauss <= '0;
    end else if (en) begin
      s2_valid  <= s1_valid;
      s2_mode   <= s1_mode;
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
      pixel_out <= '0;
    end else if (en) begin
      valid_out <= s2_valid;
      if (combined_val > 20'd255) begin
        pixel_out <= 8'd255;
      end else begin
        pixel_out <= combined_val[7:0];
      end
    end
  end

endmodule

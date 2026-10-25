// ==============================================================================
// File: line_buffer_2d.sv
// Description: Parameterized 2D Line Buffer providing continuous 3x3 sliding
//              pixel windows from a 1D raster-scan pixel stream without stalls.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

`timescale 1ns / 1ps

module line_buffer_2d #(
  parameter int IMG_WIDTH   = 128,
  parameter int IMG_HEIGHT  = 128,
  parameter int PIXEL_WIDTH = 8
)(
  input  logic                                  clk,
  input  logic                                  rst_n,
  input  logic                                  shift_en,
  input  logic [PIXEL_WIDTH-1:0]                pixel_in,
  input  logic                                  pixel_in_valid,
  
  // 3x3 packed output matrix
  output logic [2:0][2:0][PIXEL_WIDTH-1:0]      window_out,
  output logic                                  window_valid
);

  logic [PIXEL_WIDTH-1:0] line_buf_0 [0:IMG_WIDTH-1];
  logic [PIXEL_WIDTH-1:0] line_buf_1 [0:IMG_WIDTH-1];

  initial begin
    for (int i = 0; i < IMG_WIDTH; i++) begin
      line_buf_0[i] = '0;
      line_buf_1[i] = '0;
    end
  end

  logic [$clog2(IMG_WIDTH)-1:0] wr_ptr;
  logic [31:0] col_idx;
  logic [31:0] row_idx;

  logic [2:0][2:0][PIXEL_WIDTH-1:0] win;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      col_idx      <= '0;
      row_idx      <= '0;
      window_valid <= 1'b0;
      win          <= '0;
    end else if (shift_en && pixel_in_valid) begin
      line_buf_0[wr_ptr] <= line_buf_1[wr_ptr];
      line_buf_1[wr_ptr] <= pixel_in;

      if (wr_ptr == IMG_WIDTH - 1) begin
        wr_ptr <= '0;
      end else begin
        wr_ptr <= wr_ptr + 1'b1;
      end

      win[0][0] <= win[0][1];
      win[0][1] <= win[0][2];
      win[0][2] <= line_buf_0[wr_ptr];

      win[1][0] <= win[1][1];
      win[1][1] <= win[1][2];
      win[1][2] <= line_buf_1[wr_ptr];

      win[2][0] <= win[2][1];
      win[2][1] <= win[2][2];
      win[2][2] <= pixel_in;

      if (row_idx >= 2 && col_idx >= 2) begin
        window_valid <= 1'b1;
      end else begin
        window_valid <= 1'b0;
      end

      if (col_idx == IMG_WIDTH - 1) begin
        col_idx <= '0;
        row_idx <= row_idx + 1'b1;
      end else begin
        col_idx <= col_idx + 1'b1;
      end
    end else if (shift_en && !pixel_in_valid) begin
      window_valid <= 1'b0;
    end
  end

  assign window_out = win;

endmodule

// ==============================================================================
// File: axis_image_filter_top.sv
// Description: Top-Level 2D Image Convolution Accelerator with AMBA AXI4-Stream
//              Slave/Master interfaces, Integrated Clock Gating, and Backpressure.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

`timescale 1ns / 1ps

import image_filter_pkg::*;

module axis_image_filter_top #(
  parameter int IMG_WIDTH   = 128,
  parameter int IMG_HEIGHT  = 128,
  parameter int PIXEL_WIDTH = 8
)(
  input  logic                    aclk,
  input  logic                    aresetn,
  input  logic [1:0]              filter_mode,
  input  logic                    test_mode,

  // AXI4-Stream Slave Interface (Input Grayscale Stream)
  input  logic [PIXEL_WIDTH-1:0]  s_axis_tdata,
  input  logic                    s_axis_tvalid,
  output logic                    s_axis_tready,
  input  logic                    s_axis_tlast,
  input  logic                    s_axis_tuser,

  // AXI4-Stream Master Interface (Filtered Output Stream)
  output logic [PIXEL_WIDTH-1:0]  m_axis_tdata,
  output logic                    m_axis_tvalid,
  input  logic                    m_axis_tready,
  output logic                    m_axis_tlast,
  output logic                    m_axis_tuser
);

  logic pipeline_en;
  logic gated_aclk;
  logic pipe_active;
  logic [3:0] drain_cnt;

  assign pipeline_en = m_axis_tready | ~m_axis_tvalid;
  assign s_axis_tready = pipeline_en;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      drain_cnt <= '0;
    end else if (s_axis_tvalid) begin
      drain_cnt <= 4'd8;
    end else if (drain_cnt > 0) begin
      drain_cnt <= drain_cnt - 1'b1;
    end
  end

  assign pipe_active = s_axis_tvalid | m_axis_tvalid | (drain_cnt > 0);

  icg_cell u_icg (
    .clk_in    (aclk),
    .enable    (pipe_active),
    .test_mode (test_mode),
    .clk_out   (gated_aclk)
  );

  // Line Buffer & Window Generation
  logic [2:0][2:0][PIXEL_WIDTH-1:0] kernel_window;
  logic                             window_valid;

  line_buffer_2d #(
    .IMG_WIDTH   (IMG_WIDTH),
    .IMG_HEIGHT  (IMG_HEIGHT),
    .PIXEL_WIDTH (PIXEL_WIDTH)
  ) u_line_buffer (
    .clk            (gated_aclk),
    .rst_n          (aresetn),
    .shift_en       (pipeline_en),
    .pixel_in       (s_axis_tdata),
    .pixel_in_valid (s_axis_tvalid),
    .window_out     (kernel_window),
    .window_valid   (window_valid)
  );

  // Convolution Compute Engine
  logic [PIXEL_WIDTH-1:0] conv_pixel_out;
  logic                   conv_valid_out;

  conv3x3_engine #(
    .PIXEL_WIDTH (PIXEL_WIDTH)
  ) u_conv_engine (
    .clk        (gated_aclk),
    .rst_n      (aresetn),
    .en         (pipeline_en),
    .mode       (filter_mode),
    .window_in  (kernel_window),
    .valid_in   (window_valid),
    .pixel_out  (conv_pixel_out),
    .valid_out  (conv_valid_out)
  );

  // Output Register Slice
  logic [31:0] out_pixel_counter;
  localparam int TOTAL_OUTPUT_PIXELS = (IMG_WIDTH - 2) * (IMG_HEIGHT - 2);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      m_axis_tdata      <= '0;
      m_axis_tvalid     <= 1'b0;
      m_axis_tlast      <= 1'b0;
      m_axis_tuser      <= 1'b0;
      out_pixel_counter <= '0;
    end else if (pipeline_en) begin
      m_axis_tdata  <= conv_pixel_out;
      m_axis_tvalid <= conv_valid_out;

      if (conv_valid_out) begin
        if (out_pixel_counter == 0) begin
          m_axis_tuser <= 1'b1;
        end else begin
          m_axis_tuser <= 1'b0;
        end

        if (out_pixel_counter == TOTAL_OUTPUT_PIXELS - 1) begin
          m_axis_tlast      <= 1'b1;
          out_pixel_counter <= '0;
        end else begin
          m_axis_tlast      <= 1'b0;
          out_pixel_counter <= out_pixel_counter + 1'b1;
        end
      end else begin
        m_axis_tuser <= 1'b0;
        m_axis_tlast <= 1'b0;
      end
    end
  end

endmodule

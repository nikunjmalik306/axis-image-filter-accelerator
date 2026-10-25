// ==============================================================================
// File: axis_image_filter_top.sv
// Description: Top-Level 2D Image Convolution Accelerator with AMBA AXI4-Stream
//              Slave/Master interfaces, Integrated Clock Gating, and Backpressure.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// Protocol Compliance:
//   - Input handshake gated strictly on s_axis_tvalid && s_axis_tready
//   - Output stability slice holding m_axis_tdata, tlast, tuser during backpressure
//   - AXI-Stream Video framing:
//       m_axis_tuser asserted on Start-of-Frame (pixel (0,0))
//       m_axis_tlast asserted on End-of-Line (each row at col == OUT_WIDTH - 1)
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

  localparam OUT_WIDTH           = IMG_WIDTH - 2;
  localparam OUT_HEIGHT          = IMG_HEIGHT - 2;
  localparam TOTAL_OUTPUT_PIXELS = OUT_WIDTH * OUT_HEIGHT;

  logic gated_aclk;
  logic pipe_active;
  logic in_handshake;
  logic out_ready;
  logic in_progress;

  // AXI4-Stream Backpressure Handshake:
  assign out_ready     = m_axis_tready | ~m_axis_tvalid;
  assign s_axis_tready = out_ready;
  assign in_handshake  = s_axis_tvalid && s_axis_tready;

  // Tracking Output Framing Coordinates (AXI-Stream Video Convention)
  logic [15:0] out_col;
  logic [15:0] out_row;

  logic is_first_pixel;
  logic is_eol_pixel;
  logic is_eof_pixel;

  assign is_first_pixel = (out_col == 16'd0) && (out_row == 16'd0);
  assign is_eol_pixel   = (out_col == (OUT_WIDTH - 1));
  assign is_eof_pixel   = (out_col == (OUT_WIDTH - 1)) && (out_row == (OUT_HEIGHT - 1));

  // Track active frame processing:
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      in_progress <= 1'b0;
    end else if (in_handshake) begin
      in_progress <= 1'b1;
    end else if (out_ready && m_axis_tvalid && m_axis_tready && is_eof_pixel) begin
      in_progress <= 1'b0;
    end
  end

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
    .shift_en       (out_ready),
    .pixel_in       (s_axis_tdata),
    .pixel_in_valid (in_handshake),
    .s_axis_tuser   (s_axis_tuser),
    .s_axis_tlast   (s_axis_tlast),
    .window_out     (kernel_window),
    .window_valid   (window_valid)
  );

  // Convolution Compute Engine
  logic [PIXEL_WIDTH-1:0] conv_pixel_out;
  logic                   conv_valid_out;
  logic                   conv_s1_valid;
  logic                   conv_s2_valid;

  conv3x3_engine #(
    .PIXEL_WIDTH (PIXEL_WIDTH)
  ) u_conv_engine (
    .clk        (gated_aclk),
    .rst_n      (aresetn),
    .en         (out_ready),
    .mode       (filter_mode),
    .window_in  (kernel_window),
    .valid_in   (window_valid),
    .pixel_out  (conv_pixel_out),
    .valid_out  (conv_valid_out),
    .s1_valid_o (conv_s1_valid),
    .s2_valid_o (conv_s2_valid)
  );

  // Dynamic Clock Gating: active whenever pixels are streaming, in flight, or frame in progress
  assign pipe_active = s_axis_tvalid | m_axis_tvalid | in_progress | conv_s1_valid | conv_s2_valid | conv_valid_out;

  icg_cell u_icg (
    .clk_in    (aclk),
    .enable    (pipe_active),
    .test_mode (test_mode),
    .clk_out   (gated_aclk)
  );

  // Output Register Slice (Guarantees TDATA/TLAST/TUSER are held rock-stable during backpressure)
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      m_axis_tdata  <= '0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 1'b0;
      out_col       <= '0;
      out_row       <= '0;
    end else if (out_ready) begin
      m_axis_tdata  <= conv_pixel_out;
      m_axis_tvalid <= conv_valid_out;

      if (conv_valid_out) begin
        // AXI-Stream Video Protocol Framing:
        // TUSER asserted on Start-of-Frame (pixel (0,0))
        m_axis_tuser <= is_first_pixel;

        // TLAST asserted on End-of-Line (each line's final pixel)
        m_axis_tlast <= is_eol_pixel;

        // Update output raster coordinates
        if (is_eol_pixel) begin
          out_col <= '0;
          if (out_row == OUT_HEIGHT - 1) begin
            out_row <= '0;
          end else begin
            out_row <= out_row + 1'b1;
          end
        end else begin
          out_col <= out_col + 1'b1;
        end
      end else begin
        m_axis_tuser <= 1'b0;
        m_axis_tlast <= 1'b0;
      end
    end
  end

endmodule

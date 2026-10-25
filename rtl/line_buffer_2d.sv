// ==============================================================================
// File: line_buffer_2d.sv
// Description: Parameterized 2D Line Buffer with AXI4-Stream Framing Recovery.
//              Uses s_axis_tuser (SOF) and s_axis_tlast (EOL) to resynchronize
//              pointers and state across truncated, malformed, or backpressured frames.
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
  input  logic                                  shift_en,         // Handshake: s_axis_tvalid && s_axis_tready
  input  logic [PIXEL_WIDTH-1:0]                pixel_in,
  input  logic                                  pixel_in_valid,
  input  logic                                  s_axis_tuser,     // Start-of-Frame (SOF)
  input  logic                                  s_axis_tlast,     // End-of-Line (EOL)
  
  // 3x3 packed output matrix (flattened for universal EDA tool compatibility)
  output logic [(9*PIXEL_WIDTH)-1:0]            window_out,
  output logic                                  window_valid,
  output logic                                  sof_out,
  output logic                                  eol_out
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

  logic [PIXEL_WIDTH-1:0] win [0:2][0:2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      col_idx      <= '0;
      row_idx      <= '0;
      window_valid <= 1'b0;
      sof_out      <= 1'b0;
      eol_out      <= 1'b0;
      for (int r = 0; r < 3; r++) begin
        for (int c = 0; c < 3; c++) begin
          win[r][c] <= '0;
        end
      end
    end else if (shift_en && pixel_in_valid) begin
      logic [$clog2(IMG_WIDTH)-1:0] cur_wr_ptr;
      logic [31:0] cur_col;
      logic [31:0] cur_row;

      // Start of Frame Resynchronization:
      if (s_axis_tuser) begin
        cur_wr_ptr = '0;
        cur_col    = '0;
        cur_row    = '0;
      end else begin
        cur_wr_ptr = wr_ptr;
        cur_col    = col_idx;
        cur_row    = row_idx;
      end

      // Update line buffer memory
      line_buf_0[cur_wr_ptr] <= line_buf_1[cur_wr_ptr];
      line_buf_1[cur_wr_ptr] <= pixel_in;

      // Pointer ring buffer
      if (cur_wr_ptr == IMG_WIDTH - 1) begin
        wr_ptr <= '0;
      end else begin
        wr_ptr <= cur_wr_ptr + 1'b1;
      end

      // Shift 3x3 window registers
      win[0][0] <= win[0][1];
      win[0][1] <= win[0][2];
      win[0][2] <= line_buf_0[cur_wr_ptr];

      win[1][0] <= win[1][1];
      win[1][1] <= win[1][2];
      win[1][2] <= line_buf_1[cur_wr_ptr];

      win[2][0] <= win[2][1];
      win[2][1] <= win[2][2];
      win[2][2] <= pixel_in;

      // Interior 3x3 region valid: must be within valid image boundaries
      if (cur_row >= 2 && cur_row < IMG_HEIGHT && cur_col >= 2 && cur_col < IMG_WIDTH) begin
        window_valid <= 1'b1;
        sof_out      <= (cur_row == 2 && cur_col == 2);
        eol_out      <= (s_axis_tlast || cur_col == IMG_WIDTH - 1);
      end else begin
        window_valid <= 1'b0;
        sof_out      <= 1'b0;
        eol_out      <= 1'b0;
      end

      // End-of-Line (EOL) boundary recovery via s_axis_tlast
      if (s_axis_tlast || cur_col == IMG_WIDTH - 1) begin
        col_idx <= '0;
        row_idx <= cur_row + 1'b1;
      end else begin
        col_idx <= cur_col + 1'b1;
        row_idx <= cur_row;
      end
    end else if (shift_en && !pixel_in_valid) begin
      window_valid <= 1'b0;
      sof_out      <= 1'b0;
      eol_out      <= 1'b0;
    end
  end

  assign window_out = {win[0][0], win[0][1], win[0][2],
                       win[1][0], win[1][1], win[1][2],
                       win[2][0], win[2][1], win[2][2]};

endmodule

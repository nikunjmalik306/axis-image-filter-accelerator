// ==============================================================================
// File: image_filter_pkg.sv
// Description: Global parameters, datatypes, and kernel definitions for 2D
//              Image Convolution and Sobel Edge Detection Accelerator.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ==============================================================================

package image_filter_pkg;

  // Image Geometry Configuration
  localparam int IMG_WIDTH_DEFAULT  = 128;
  localparam int IMG_HEIGHT_DEFAULT = 128;
  localparam int PIXEL_WIDTH        = 8;      // 8-bit unsigned grayscale [0, 255]
  localparam int KERNEL_SIZE        = 3;      // 3x3 convolution window
  localparam int KERNEL_WEIGHT_W    = 8;      // 8-bit signed kernel weights [-128, 127]

  // Arithmetic Precision
  // 8b unsigned pixel * 8b signed weight = 16b signed product
  localparam int PROD_WIDTH         = 16;
  // Sum of 9 x 16b signed products = 20b signed sum
  localparam int ACC_WIDTH          = 20;

  // Operational Modes
  typedef enum logic [1:0] {
    MODE_SOBEL_MAG = 2'b00,  // Sobel Magnitude: |Gx| + |Gy|
    MODE_SOBEL_X   = 2'b01,  // Sobel Gx only
    MODE_SOBEL_Y   = 2'b10,  // Sobel Gy only
    MODE_GAUSSIAN  = 2'b11   // 3x3 Gaussian Blur (scaled >> 4)
  } filter_mode_t;

endpackage: image_filter_pkg

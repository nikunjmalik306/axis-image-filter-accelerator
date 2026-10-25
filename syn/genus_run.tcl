# ==============================================================================
# File: genus_run.tcl
# Description: Cadence Genus ASIC Synthesis Script for AXI4-Stream Filter
# ==============================================================================

set_db init_lib_search_path {/cad/libraries/standard_cells/tsmc28/lib}
set_db init_hdl_search_path {../rtl}
set_db library {slow_vdd1v0_basicCells.lib}

read_hdl -language sv {
  image_filter_pkg.sv
  icg_cell.sv
  line_buffer_2d.sv
  conv3x3_engine.sv
  axis_image_filter_top.sv
}

elaborate axis_image_filter_top

read_sdc constraints.sdc

syn_generic
syn_map
syn_opt

report_timing > reports_timing.rpt
report_power  > reports_power.rpt
report_area   > reports_area.rpt
report_qor    > reports_qor.rpt

write_hdl > axis_image_filter_netlist.v
write_sdc > axis_image_filter_out.sdc

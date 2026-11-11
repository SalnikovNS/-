set PART   xc7a200tfbg484-2
set PERIOD 10.000

set dir [file dirname [file normalize [info script]]]
create_project -in_memory -part $PART
set_property include_dirs [file join $dir rtl] [current_fileset]
read_verilog [glob [file join $dir rtl *.v]]
synth_design -top kuz_mgm -part $PART -mode out_of_context -include_dirs [file join $dir rtl]
create_clock -name clk -period $PERIOD [get_ports clk]
opt_design
report_utilization -hierarchical -hierarchical_depth 2 -file [file join $dir syn_utilization.txt]
report_timing_summary -no_detailed_paths -file [file join $dir syn_timing.txt]
puts "=================================================="
puts " part $PART, clock $PERIOD ns"
puts " WNS (post-synthesis estimate) = [get_property SLACK [get_timing_paths -max_paths 1 -setup]] ns"
puts " reports: syn_utilization.txt, syn_timing.txt"
puts "=================================================="

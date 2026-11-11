foreach L {0 1 2 3} {
    set c [get_cells -hier -filter "REF_NAME == GTXE2_CHANNEL && NAME =~ *pipe_lane\[$L\]*"]
    set_property LOC GTXE2_CHANNEL_X0Y[expr {3 - $L}] $c
}
set_property LOC GTXE2_COMMON_X0Y0 [get_cells -hier -filter {REF_NAME == GTXE2_COMMON && NAME =~ *pipe_wrapper_i*}]

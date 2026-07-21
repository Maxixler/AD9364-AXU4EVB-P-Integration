set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir .. ..]]
set rtl_file [file join $root_dir Related-Docs hdl-main library axi_ad9364_fft_capture spectrum_pingpong.v]

if {![file exists $rtl_file]} {
  error "Missing spectrum bank RTL: $rtl_file"
}

read_verilog $rtl_file
synth_design -top spectrum_pingpong -part xczu4ev-sfvc784-1-i -mode out_of_context

set utilization [report_utilization -return_string]
set ramb36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ramb18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set lutram_count -1
if {[regexp {\|\s*LUT as Memory\s*\|\s*([0-9]+)\s*\|} $utilization match count]} {
  set lutram_count $count
}

puts "SYNTH_BANK: RAMB36=$ramb36_count RAMB18=$ramb18_count LUT_AS_MEMORY=$lutram_count"
if {$ramb36_count != 8} {
  error "Expected exactly 8 RAMB36 primitives for two 2048x64 banks, got $ramb36_count"
}
if {$ramb18_count != 0} {
  error "Expected exactly 0 RAMB18 primitives, got $ramb18_count"
}
if {$lutram_count != 0} {
  error "Expected exactly 0 LUTs as memory, got $lutram_count"
}
puts "PASS: spectrum_pingpong infers block RAM"

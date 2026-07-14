if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set project_dir [file join $workspace_root "Related-Docs" "hdl-main" "projects" "fmcomms2" "axu4ev"]
set project_file [file join $project_dir "fmcomms2_axu4ev.xpr"]
set target_xdc [file join $project_dir "system_constr.xdc"]

if {![file exists $project_file]} {
  error "Vivado project does not exist at '$project_file'."
}

proc require_equal {label actual expected} {
  if {$actual ne $expected} {
    error "$label mismatch: expected '$expected', got '$actual'"
  }
  puts "PASS: $label = $actual"
}

open_project $project_file -read_only

require_equal "Part" [get_property PART [current_project]] "xczu4ev-sfvc784-1-i"
require_equal "Top" [get_property TOP [current_fileset]] "system_top"

set matching_files {}
foreach candidate [get_files -of_objects [get_filesets constrs_1]] {
  if {[string equal -nocase [string map {\\ /} $candidate] $target_xdc]} {
    lappend matching_files $candidate
  }
}

if {[llength $matching_files] != 1} {
  error "Expected exactly one active constraint file at '$target_xdc'; found [llength $matching_files]."
}

set xdc_file [lindex $matching_files 0]
require_equal "XDC file type" [get_property FILE_TYPE $xdc_file] "XDC"
require_equal "XDC used in synthesis" [get_property USED_IN_SYNTHESIS $xdc_file] "1"
require_equal "XDC used in implementation" [get_property USED_IN_IMPLEMENTATION $xdc_file] "1"
puts "PASS: Active XDC = [string map {\\ /} $xdc_file]"

close_project
puts "PASS: Project source-graph inspection completed."

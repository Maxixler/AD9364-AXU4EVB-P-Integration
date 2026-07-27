if {[info exists ::env(FPGA_PROFEN_ROOT)]} {
  set workspace_root [file normalize $::env(FPGA_PROFEN_ROOT)]
} else {
  set workspace_root [file normalize [file join [file dirname [info script]] .. ..]]
}
set workspace_root [string map {\\ /} $workspace_root]
set project_dir [file join $workspace_root "Related-Docs" "hdl-main" "projects" "fmcomms2" "axu4ev"]
set project_file [file join $project_dir "fmcomms2_axu4ev.xpr"]
set target_xdc [file join $project_dir "system_constr.xdc"]
set report_dir [file join $workspace_root "PROJECT" "verification" "vivado"]
set bitstream_file [file join $project_dir "fmcomms2_axu4ev.runs" "impl_1" "system_top.bit"]
set verify_only [expr {[info exists ::env(FPGA_PROFEN_VERIFY_ONLY)] && $::env(FPGA_PROFEN_VERIFY_ONLY) eq "1"}]

proc require_equal {label actual expected} {
  if {$actual ne $expected} {
    error "$label mismatch: expected '$expected', got '$actual'"
  }
  puts "PASS: $label = $actual"
}

proc require_port_property {port_name property_name expected} {
  set port [get_ports -quiet $port_name]
  if {[llength $port] != 1} {
    error "Expected one implemented port named '$port_name'; found [llength $port]."
  }
  require_equal "$port_name $property_name" [get_property $property_name $port] $expected
}

if {[llength $argv] > 0 && [lindex $argv 0] eq "candidate_fft"} {
  if {[llength $argv] != 1} {
    error "candidate_fft accepts no additional arguments."
  }

  set source_hdl [file join $workspace_root Related-Docs hdl-main]
  set source_project [file join $source_hdl projects fmcomms2 axu4ev]
  set source_common [file join $source_hdl projects fmcomms2 common fmcomms2_bd.tcl]
  set source_carrier_common [file join $source_hdl projects common axu4ev axu4ev_system_bd.tcl]
  set package_runner [file join $workspace_root PROJECT tests Package-Axu4evFftIp.tcl]
  foreach required [list $source_common $source_carrier_common $package_runner \
      [file join $source_project system_project.tcl] \
      [file join $source_project system_bd.tcl] \
      [file join $source_project system_top.v] \
      [file join $source_project system_constr.xdc]] {
    if {![file isfile $required]} {
      error "Missing Candidate build input '$required'."
    }
  }

  # Linked worktrees omit ignored ADI component.xml products. Locate an
  # existing generated ADI checkout read-only; all new outputs still go into
  # this invocation's disposable Candidate tree.
  set dependency_hdl {}
  set worktree_lines [split [exec git -C $workspace_root worktree list --porcelain] "\n"]
  foreach line $worktree_lines {
    if {[regexp {^worktree (.+)$} $line -> worktree_path]} {
      set possible_hdl [file join $worktree_path Related-Docs hdl-main]
      if {[file isfile [file join $possible_hdl library axi_sysid component.xml]]} {
        set dependency_hdl [file normalize $possible_hdl]
        break
      }
    }
  }
  if {$dependency_hdl eq {}} {
    error "No generated ADI dependency checkout containing axi_sysid/component.xml was found."
  }

  # xFFT adds several generated hierarchy levels. A drive-root disposable
  # path keeps Vivado 2020.1 below Windows' 260-byte legacy path limit.
  set candidate_parent [file normalize [file join $::env(SystemDrive)/ \
    f8_[pid]_[clock seconds]]]
  set candidate_root [file join $candidate_parent Candidate]
  set candidate_hdl [file join $candidate_root hdl-main]
  set candidate_project [file join $candidate_hdl projects fmcomms2 axu4ev]
  set candidate_common [file join $candidate_hdl projects fmcomms2 common]
  set candidate_carrier_common [file join $candidate_hdl projects common axu4ev]
  set candidate_scripts [file join $candidate_hdl scripts]
  set candidate_repo [file join $candidate_root custom-ip]
  set package_output [file join $candidate_repo library axi_ad9364_fft_capture]
  set candidate_reports [file join $candidate_root reports]
  file mkdir $candidate_project
  file mkdir $candidate_common
  file mkdir $candidate_carrier_common
  file mkdir $candidate_scripts
  file mkdir [file dirname $package_output]
  file mkdir $candidate_reports

  foreach name {system_project.tcl system_bd.tcl system_top.v system_constr.xdc} {
    file copy -force [file join $source_project $name] [file join $candidate_project $name]
  }
  file copy -force $source_common [file join $candidate_common fmcomms2_bd.tcl]
  file copy -force $source_carrier_common \
    [file join $candidate_carrier_common axu4ev_system_bd.tcl]
  file copy -force [file join $source_hdl scripts adi_env.tcl] \
    [file join $candidate_scripts adi_env.tcl]

  # Make synthesis/implementation fail if Vivado emits a critical warning
  # naming the new hierarchy or either explicit CDC/BRAM interface.
  set candidate_project_tcl [file join $candidate_project system_project.tcl]
  set project_handle [open $candidate_project_tcl r]
  set project_text [read $project_handle]
  close $project_handle
  set warning_gate {set_msg_config -severity {CRITICAL WARNING} -regexp -string {.*(axi_ad9364_fft|fft_(command|result)_cdc|spectrum_bank|BRAM_PORTA).*} -new_severity ERROR

adi_project_run fmcomms2_${BOARD_NAME}}
  set project_text [string map [list \
    {adi_project_run fmcomms2_${BOARD_NAME}} $warning_gate] $project_text]
  set project_handle [open $candidate_project_tcl w]
  puts -nonewline $project_handle $project_text
  close $project_handle

  set ::env(FPGA_PROFEN_ROOT) $workspace_root
  set ::env(FFT_PACKAGE_OUTPUT_DIR) $package_output
  set ::env(FFT_PACKAGE_IMPORT_FILES) 1
  set ::env(ADI_GHDL_DIR) $candidate_repo
  set ::env(ADI_HDL_DIR) $dependency_hdl
  set ::env(AXU4EV_FFT_SHADOW_PATH) 1
  set ::env(ADI_GENERATE_UTILIZATION) 1
  set ::env(ADI_MAX_OOC_JOBS) 2
  set ::env(ADI_MAX_THREADS) 2
  unset -nocomplain ::env(ADI_SKIP_SYNTHESIS)

  puts "INFO: Candidate root = $candidate_root"
  puts "INFO: Packaging self-contained FFT core into $package_output"
  source $package_runner
  close_project

  # Vivado 2020.1 can retain stale IP-packager callbacks after close_project;
  # creating a block design in that same process intermittently tries to
  # source a context-free "init.tcl". Build the actual project in a clean
  # child Vivado process, then reopen the completed project for the gates.
  set child_script [file join $candidate_root build_candidate_project.tcl]
  set child_handle [open $child_script w]
  puts $child_handle "cd [list $candidate_project]"
  puts $child_handle {source system_project.tcl}
  close $child_handle

  set build_code [catch {
    exec [info nameofexecutable] -mode batch -nolog -nojournal -notrace \
      -source $child_script 2>@1
  } build_error build_options]
  puts $build_error
  if {$build_code != 0} {
    puts "ERROR: Candidate build artifacts retained at $candidate_root"
    return -options $build_options $build_error
  }

  set candidate_xpr [file normalize [file join $candidate_project fmcomms2_axu4ev.xpr]]
  set golden_xpr [file normalize [file join $source_project fmcomms2_axu4ev.xpr]]
  open_project $candidate_xpr
  require_equal "Candidate project path" [file normalize [get_property DIRECTORY [current_project]]] \
    [file dirname $candidate_xpr]
  if {[string equal -nocase $candidate_xpr $golden_xpr]} {
    error "Candidate project unexpectedly aliases the Golden project."
  }
  require_equal "Candidate part" [get_property PART [current_project]] "xczu4ev-sfvc784-1-i"
  require_equal "Candidate top" [get_property TOP [current_fileset]] "system_top"

  set candidate_bit [file join $candidate_project fmcomms2_axu4ev.runs impl_1 system_top.bit]
  if {![file isfile $candidate_bit]} {
    error "Candidate bitstream is missing at '$candidate_bit'."
  }

  open_run impl_1
  report_drc -file [file join $candidate_reports fft_candidate_drc.rpt]
  report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 \
    -file [file join $candidate_reports fft_candidate_timing_summary.rpt]
  report_utilization -file [file join $candidate_reports fft_candidate_utilization.rpt]
  report_cdc -details -file [file join $candidate_reports fft_candidate_cdc.rpt]

  set fft_cells [get_cells -quiet -hierarchical -filter {NAME =~ *axi_ad9364_fft_capture*}]
  if {[llength $fft_cells] == 0} {
    error "Implemented design contains no FFT capture hierarchy."
  }
  report_utilization -cells $fft_cells \
    -file [file join $candidate_reports fft_hierarchy_utilization.rpt]

  set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
  if {[llength $drc_errors] > 0} {
    error "Candidate DRC contains Error violations: $drc_errors"
  }
  set setup_path [get_timing_paths -quiet -setup -max_paths 1]
  set hold_path [get_timing_paths -quiet -hold -max_paths 1]
  if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Candidate timing paths are incomplete (setup=[llength $setup_path], hold=[llength $hold_path])."
  }
  set worst_setup [get_property SLACK $setup_path]
  set worst_hold [get_property SLACK $hold_path]
  if {$worst_setup < 0.0 || $worst_hold < 0.0} {
    error "Candidate timing is not closed (setup=$worst_setup ns, hold=$worst_hold ns)."
  }

  set evidence [open [file join $candidate_reports fft_candidate_summary.txt] w]
  puts $evidence "Candidate project: $candidate_xpr"
  puts $evidence "Candidate bitstream: [file normalize $candidate_bit]"
  puts $evidence "Worst setup slack (ns): $worst_setup"
  puts $evidence "Worst hold slack (ns): $worst_hold"
  puts $evidence "DRC Error violations: 0"
  puts $evidence "FFT-attributable critical warnings: 0"
  close $evidence

  puts "PASS: Candidate bitstream = [file normalize $candidate_bit]"
  puts "PASS: Candidate DRC Error violations = 0"
  puts "PASS: Candidate worst setup slack = $worst_setup ns"
  puts "PASS: Candidate worst hold slack = $worst_hold ns"
  puts "PASS: Candidate FFT utilization = [file join $candidate_reports fft_hierarchy_utilization.rpt]"
  puts "PASS: Golden project and artifacts were not opened or overwritten"
  close_project
  exit 0
}

if {[llength $argv] > 0} {
  error "Unknown build mode '[lindex $argv 0]'. Expected candidate_fft or no arguments."
}

if {![file exists $project_file]} {
  error "Vivado project does not exist at '$project_file'."
}
file mkdir $report_dir

open_project $project_file
require_equal "Part" [get_property PART [current_project]] "xczu4ev-sfvc784-1-i"
require_equal "Top" [get_property TOP [current_fileset]] "system_top"

set active_xdc [get_files -quiet $target_xdc]
if {[llength $active_xdc] != 1} {
  error "Expected active XDC '$target_xdc'; found [llength $active_xdc]."
}
require_equal "XDC used in synthesis" [get_property USED_IN_SYNTHESIS $active_xdc] "1"
require_equal "XDC used in implementation" [get_property USED_IN_IMPLEMENTATION $active_xdc] "1"

set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] > 0} {
  report_ip_status -file [file join $report_dir "ip_status_before_build.rpt"] -force
  error "Locked IP detected before build: $locked_ips"
}

if {!$verify_only} {
  puts "INFO: Resetting synth_1 so the edited XDC is guaranteed to be consumed."
  reset_runs synth_1
  launch_runs impl_1 -to_step write_bitstream -jobs 4
  wait_on_run impl_1
} else {
  puts "INFO: Verify-only mode; preserving the completed implementation run."
}

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "INFO: impl_1 status='$impl_status' progress='$impl_progress'"
if {![string match "*write_bitstream Complete!*" $impl_status]} {
  error "Implementation did not complete write_bitstream: status='$impl_status', progress='$impl_progress'."
}
if {![file exists $bitstream_file]} {
  error "Bitstream is missing after a completed run: '$bitstream_file'."
}

open_run impl_1

report_drc -file [file join $report_dir "system_top_drc.rpt"] -force
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $report_dir "system_top_timing_summary.rpt"]
check_timing -verbose -file [file join $report_dir "system_top_check_timing.rpt"]
report_clock_interaction -delay_type min_max -file [file join $report_dir "system_top_clock_interaction.rpt"]
report_clocks -file [file join $report_dir "system_top_clocks.rpt"]
report_io -file [file join $report_dir "system_top_io.rpt"]

set rx_clocks [get_clocks -quiet rx_clk]
if {[llength $rx_clocks] != 1} {
  error "Expected exactly one implemented rx_clk; found [llength $rx_clocks]."
}
require_equal "rx_clk period" [format "%.3f" [get_property PERIOD $rx_clocks]] "4.000"

foreach {port pin} {
  rx_frame_in_p L7
  rx_frame_in_n L6
  tx_clk_out_p N7
  tx_clk_out_n N6
} {
  require_port_property $port PACKAGE_PIN $pin
}

set rx_ports {rx_clk_in_p rx_clk_in_n rx_frame_in_p rx_frame_in_n}
for {set index 0} {$index < 6} {incr index} {
  lappend rx_ports "rx_data_in_p\[$index\]"
  lappend rx_ports "rx_data_in_n\[$index\]"
}
foreach port $rx_ports {
  require_port_property $port DIFF_TERM_ADV TERM_100
}
require_port_property spi_csn PULLTYPE PULLUP

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] > 0} {
  error "DRC error violations remain after implementation: $drc_errors"
}

puts "PASS: Bitstream = $bitstream_file"
puts "PASS: Vivado implementation evidence = $report_dir"
close_project

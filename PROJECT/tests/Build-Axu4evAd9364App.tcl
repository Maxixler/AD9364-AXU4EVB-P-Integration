if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set workspace [file join $root Vitis workspace]
set platform_name fmcomms2_axu4ev_hw
set platform_file [file join $workspace $platform_name platform.spr]
set app_name ad9364app
set app_dir [file join $workspace $app_name]
set system_dir [file join $workspace ${app_name}_system]
set app_config [file join $app_dir src adc9364_src app_config.h]
set app_project [file join $app_dir ${app_name}.prj]
set system_project [file join $system_dir ${app_name}_system.sprj]
set elf [file join $app_dir Release ${app_name}.elf]

proc read_text {path} {
  set channel [open $path r]
  set data [read $channel]
  close $channel
  return $data
}

if {![file exists $platform_file]} {
  error "Platform file is missing: $platform_file"
}
if {![file exists $app_config]} {
  error "AD9364 application configuration is missing: $app_config"
}

set config_text [read_text $app_config]
if {![regexp {#define[ \t]+AD9361_DEVICE[ \t]+0} $config_text]} {
  error "AD9361_DEVICE must be disabled in app_config.h."
}
if {![regexp {#define[ \t]+AD9364_DEVICE[ \t]+1} $config_text]} {
  error "AD9364_DEVICE must be enabled in app_config.h."
}

set expected_platform "fmcomms2_axu4ev_hw.xpfm"
set expected_domain "standalone_domain"
foreach project_file [list $app_project $system_project] {
  set project_text [read_text $project_file]
  if {[string first $expected_platform $project_text] < 0} {
    error "Project is not bound to the verified platform: $project_file"
  }
  if {[string first $expected_domain $project_text] < 0} {
    error "Project is not bound to the verified domain: $project_file"
  }
}

if {[catch {
  setws $workspace
  platform read $platform_file
  platform active $platform_name

  # These directories were copied into the workspace but were not registered
  # in its metadata. Importing is idempotent for subsequent verification runs.
  catch {importprojects $app_dir}
  catch {importprojects $system_dir}
  if {[string first $app_name [app list]] < 0} {
    error "Application import did not register '$app_name'."
  }

  app config -name $app_name build-config Release

  set include_dirs {}
  foreach source_dir {adc include adc9364_src api dac dmac drivers_rf_transceiver iio xilinx} {
    lappend include_dirs "\${workspace_loc:/$app_name/src/$source_dir}"
  }
  set current_includes [app config -name $app_name include-path]
  foreach include_dir $include_dirs {
    if {[string first $include_dir $current_includes] < 0} {
      app config -name $app_name -add include-path $include_dir
    }
  }
  set current_libraries [app config -name $app_name libraries]
  if {[lsearch -exact $current_libraries m] < 0} {
    app config -name $app_name -add libraries m
  }

  app clean -name $app_name
  app build -name $app_name

  if {![file exists $elf]} {
    error "Application build did not produce '$elf'."
  }
} result options]} {
  puts stderr "FAIL: AD9364 application rebuild failed: $result"
  exit 1
}

puts "PASS: AD9364 application rebuilt against verified platform: $elf"
exit 0

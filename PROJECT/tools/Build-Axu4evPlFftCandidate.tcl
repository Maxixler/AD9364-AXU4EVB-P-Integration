if {$argc != 4 && $argc != 5} {
    error "Usage: xsct Build-Axu4evPlFftCandidate.tcl <project-root> <candidate-xsa> <vitis-workspace> <allowed-workspace-root> ?compiler-symbol?"
}

set project_root [file normalize [lindex $argv 0]]
set xsa_path [file normalize [lindex $argv 1]]
set workspace_path [file normalize [lindex $argv 2]]
set allowed_workspace_root [file normalize [lindex $argv 3]]
set compiler_symbol PL_FFT_SINGLE_SHOT
if {$argc == 5} {
    set compiler_symbol [lindex $argv 4]
}
set allowed_symbols {
    PL_FFT_SINGLE_SHOT
    PL_FFT_PERIODIC_MONITOR
    PL_FFT_LAB_UART
}
if {[lsearch -exact $allowed_symbols $compiler_symbol] == -1} {
    error "Invalid Candidate compiler symbol: $compiler_symbol"
}
set source_root [file join $project_root Vitis workspace ad9364app src]

if {![file exists $xsa_path]} {
    error "Missing Candidate XSA: $xsa_path"
}
if {![file isdirectory $source_root]} {
    error "Missing application source tree: $source_root"
}
set allowed_prefix "${allowed_workspace_root}/"
set workspace_prefix "${workspace_path}/"
if {$workspace_path eq $allowed_workspace_root ||
    ![string match -nocase "${allowed_prefix}*" $workspace_prefix] ||
    $workspace_path eq $project_root ||
    [string match -nocase "${workspace_prefix}*" "${project_root}/"] ||
    [string match -nocase "${project_root}/*" $workspace_prefix]} {
    error "Unsafe Candidate Vitis workspace path: $workspace_path"
}

if {[file isdirectory $workspace_path]} {
    file delete -force $workspace_path
}
file mkdir $workspace_path
setws $workspace_path

set platform_name "fmcomms2_axu4ev_fft_hw"
platform create \
    -name $platform_name \
    -hw $xsa_path \
    -proc psu_cortexa53_0 \
    -os standalone \
    -arch 64-bit \
    -no-boot-bsp
bsp setlib -name xilffs
platform generate

set app_name "ad9364app"
app create \
    -name $app_name \
    -platform $platform_name \
    -domain standalone_domain \
    -lang c \
    -template {Empty Application}

set app_source [file join $workspace_path $app_name src]
foreach leftover [glob -nocomplain -directory $app_source *] {
    file delete -force $leftover
}
foreach item [glob -directory $source_root *] {
    file copy -force $item [file join $app_source [file tail $item]]
}

app config -name $app_name build-config Release
foreach source_dir {adc include adc9364_src api dac dmac drivers_rf_transceiver iio xilinx} {
    set include_path "\${workspace_loc:/$app_name/src/$source_dir}"
    app config -name $app_name -add include-path $include_path
}
app config -name $app_name -add include-path "\${workspace_loc:/$app_name/src/iio/iio_app}"
app config -name $app_name -add libraries m
app config -name $app_name compiler-optimization {Optimize more (-O2)}
app config -name $app_name define-compiler-symbols $compiler_symbol

app clean -name $app_name
app build -name $app_name

set elf_path [file join $workspace_path $app_name Release ${app_name}.elf]
if {![file exists $elf_path]} {
    error "Candidate application build did not produce ELF: $elf_path"
}

puts "PASS: Candidate Vitis platform and $compiler_symbol application built."
puts "CANDIDATE_ELF=$elf_path"

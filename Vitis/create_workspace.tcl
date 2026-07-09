setws C:/Users/DELL/Desktop/Yazilim/FPGA-Profen/Vitis/workspace
platform create -name fmcomms2_axu4ev_hw -hw C:/Users/DELL/Desktop/Yazilim/FPGA-Profen/Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.sdk/system_top.xsa -proc psu_cortexa53_0 -os standalone -arch 64-bit
platform generate
app create -name fmcomms2_app -platform fmcomms2_axu4ev_hw -domain standalone_psu_cortexa53_0 -lang c -template {Empty Application(C)}

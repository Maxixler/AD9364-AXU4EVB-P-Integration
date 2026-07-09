import sys

with open(r'C:\Users\DELL\Desktop\Yazilim\FPGA-Profen\Related-Docs\hdl-main\projects\common\axu4ev\axu4ev_system_bd.tcl', 'r') as f:
    bd_content = f.read()

with open(r'C:\Users\DELL\Desktop\Yazilim\FPGA-Profen\PROJECT\apply_ps_config.tcl', 'r') as f:
    ps_config = f.read()

start_idx = bd_content.find('ad_ip_parameter sys_ps8 CONFIG.PSU__PSS_REF_CLK__FREQMHZ')
end_idx = bd_content.find('] [get_bd_cells sys_ps8]') + len('] [get_bd_cells sys_ps8]')

if start_idx != -1 and end_idx != -1:
    new_content = bd_content[:start_idx] + ps_config + '\n' + bd_content[end_idx:]
    with open(r'C:\Users\DELL\Desktop\Yazilim\FPGA-Profen\Related-Docs\hdl-main\projects\common\axu4ev\axu4ev_system_bd.tcl', 'w') as f:
        f.write(new_content)
    print("axu4ev_system_bd.tcl updated successfully.")
else:
    print("Could not find blocks to replace.")

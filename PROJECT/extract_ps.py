import re

with open('sdr_bd_export.tcl', 'r') as f:
    content = f.read()

# Find the block: set_property -dict [ list \ ... ] $sys_ps8
marker = 'xilinx.com:ip:zynq_ultra_ps_e:3.3 sys_ps8 ]'
start_idx = content.find(marker)
if start_idx != -1:
    prop_start = content.find('set_property -dict', start_idx)
    end_idx = content.find('] $sys_ps8', prop_start)

    if prop_start != -1 and end_idx != -1:
        ps_config = content[prop_start:end_idx+10]
        
        # Write to a new tcl file
        with open('apply_ps_config.tcl', 'w') as f:
            f.write('set sys_ps8 [get_bd_cells sys_ps8]\n')
            f.write(ps_config + '\n')
        print("PS config extracted successfully.")
    else:
        print("Could not find PS config block end.")
else:
    print("Could not find marker.")

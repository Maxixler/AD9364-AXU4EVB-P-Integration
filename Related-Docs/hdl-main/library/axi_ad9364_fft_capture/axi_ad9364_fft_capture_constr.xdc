# The CPU and ADC clocks are asynchronous, but the FFT datapath itself remains
# fully timed in adc_clk. These exceptions cover only the two bundled-data
# mailboxes and the D inputs of their first-stage synchronizers.

set_false_path -to [get_pins -quiet -hier -regexp \
  {.*((i_command_cdc|i_result_cdc)/(acknowledge|adc_ready|request|pending|cpu_up|cpu_ready|adc_up)_sync1_reg|(configured_sync1_cpu_reg|busy_sync1_cpu_reg))/D$}]

# The reset synchronizers are the only legal asynchronous-reset endpoints.
# Their CLR pins provide immediate assertion; the two ASYNC_REG stages make
# every functional reset release synchronous to its receiving clock.
set_false_path -to [get_pins -quiet -hier -regexp \
  {.*i_(command|result)_cdc/(cpu|adc)_(mailbox|domains)_reset_sync_reg(\[[01]\])?/CLR$}]

# A source holds each payload until the request crosses two synchronizer
# stages and the acknowledgement returns. Constrain the physical data path to
# one 8 ns ADC period and remove only the meaningless asynchronous hold check.
# Destination D/CE pins remain covered by the max-delay bound; unrelated FFT
# registers and both same-domain datapaths retain normal setup/hold timing.
set_max_delay 8.000 -datapath_only \
  -from [get_cells -quiet -hier -regexp {.*i_command_cdc/payload_hold_reg(\[[0-9]+\])?$}] \
  -to [get_pins -quiet -hier -regexp \
    {.*i_command_cdc/o_adc_(payload_reg(\[[0-9]+\])?|valid_reg|epoch_fault_reg)/(D|CE)$}]
set_false_path -hold \
  -from [get_cells -quiet -hier -regexp {.*i_command_cdc/payload_hold_reg(\[[0-9]+\])?$}] \
  -to [get_pins -quiet -hier -regexp \
    {.*i_command_cdc/o_adc_(payload_reg(\[[0-9]+\])?|valid_reg|epoch_fault_reg)/(D|CE)$}]

set_max_delay 8.000 -datapath_only \
  -from [get_cells -quiet -hier -regexp {.*i_result_cdc/payload_hold_reg(\[[0-9]+\])?$}] \
  -to [get_pins -quiet -hier -regexp \
    {.*i_result_cdc/o_cpu_(payload_reg(\[[0-9]+\])?|valid_reg|epoch_fault_reg)/(D|CE)$}]
set_false_path -hold \
  -from [get_cells -quiet -hier -regexp {.*i_result_cdc/payload_hold_reg(\[[0-9]+\])?$}] \
  -to [get_pins -quiet -hier -regexp \
    {.*i_result_cdc/o_cpu_(payload_reg(\[[0-9]+\])?|valid_reg|epoch_fault_reg)/(D|CE)$}]

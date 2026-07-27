`timescale 1ns/1ps

module tb_fft_cdc;
  localparam integer COMMAND_WIDTH = 80;
  localparam integer RESULT_WIDTH = 160;

  logic cpu_clk = 1'b0;
  logic adc_clk = 1'b0;
  logic cpu_resetn = 1'b0;
  logic adc_resetn = 1'b0;

  logic [15:0] cpu_command_epoch = 16'h0010;
  logic cpu_command_valid = 1'b0;
  logic [COMMAND_WIDTH-1:0] cpu_command_payload = '0;
  logic cpu_command_ready;
  logic cpu_command_busy;
  logic [15:0] adc_command_epoch = 16'h0010;
  logic adc_command_valid;
  logic [COMMAND_WIDTH-1:0] adc_command_payload;
  logic adc_command_epoch_fault;

  logic [15:0] adc_result_epoch = 16'h0010;
  logic adc_result_valid = 1'b0;
  logic [RESULT_WIDTH-1:0] adc_result_payload = '0;
  logic adc_result_ready;
  logic adc_result_busy;
  logic [15:0] cpu_result_epoch = 16'h0010;
  logic cpu_result_valid;
  logic [RESULT_WIDTH-1:0] cpu_result_payload;
  logic cpu_result_epoch_fault;

  integer command_count = 0;
  integer result_count = 0;
  integer command_fault_count = 0;
  integer result_fault_count = 0;
  integer command_accept_count = 0;
  integer result_accept_count = 0;
  integer command_valid_edge_count = 0;
  integer result_valid_edge_count = 0;
  integer command_fault_edge_count = 0;
  integer result_fault_edge_count = 0;
  integer delivery_before;
  integer fault_before;
  integer index;
  logic [COMMAND_WIDTH-1:0] expected_command [0:15];
  logic [RESULT_WIDTH-1:0] expected_result [0:15];

  always #3.5 cpu_clk = ~cpu_clk;
  always #5.5 adc_clk = ~adc_clk;

  always @(posedge adc_command_valid) command_valid_edge_count = command_valid_edge_count + 1;
  always @(posedge cpu_result_valid) result_valid_edge_count = result_valid_edge_count + 1;
  always @(posedge adc_command_epoch_fault) command_fault_edge_count = command_fault_edge_count + 1;
  always @(posedge cpu_result_epoch_fault) result_fault_edge_count = result_fault_edge_count + 1;

  fft_command_cdc #(
    .PAYLOAD_WIDTH(COMMAND_WIDTH)
  ) u_command_cdc (
    .cpu_clk(cpu_clk),
    .cpu_resetn(cpu_resetn),
    .i_cpu_epoch(cpu_command_epoch),
    .i_cpu_valid(cpu_command_valid),
    .i_cpu_payload(cpu_command_payload),
    .o_cpu_ready(cpu_command_ready),
    .o_cpu_busy(cpu_command_busy),
    .adc_clk(adc_clk),
    .adc_resetn(adc_resetn),
    .i_adc_epoch(adc_command_epoch),
    .o_adc_valid(adc_command_valid),
    .o_adc_payload(adc_command_payload),
    .o_adc_epoch_fault(adc_command_epoch_fault)
  );

  fft_result_cdc #(
    .PAYLOAD_WIDTH(RESULT_WIDTH)
  ) u_result_cdc (
    .adc_clk(adc_clk),
    .adc_resetn(adc_resetn),
    .i_adc_epoch(adc_result_epoch),
    .i_adc_valid(adc_result_valid),
    .i_adc_payload(adc_result_payload),
    .o_adc_ready(adc_result_ready),
    .o_adc_busy(adc_result_busy),
    .cpu_clk(cpu_clk),
    .cpu_resetn(cpu_resetn),
    .i_cpu_epoch(cpu_result_epoch),
    .o_cpu_valid(cpu_result_valid),
    .o_cpu_payload(cpu_result_payload),
    .o_cpu_epoch_fault(cpu_result_epoch_fault)
  );

  task automatic require_true;
    input logic condition;
    input [8*128-1:0] message;
    begin
      if (condition !== 1'b1) begin
        $display("FAIL: %0s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic wait_command_ready;
    integer timeout;
    begin
      timeout = 0;
      while (!cpu_command_ready && timeout < 100) begin
        @(posedge cpu_clk);
        timeout = timeout + 1;
      end
      require_true(cpu_command_ready, "command mailbox did not become ready");
    end
  endtask

  task automatic wait_result_ready;
    integer timeout;
    begin
      timeout = 0;
      while (!adc_result_ready && timeout < 100) begin
        @(posedge adc_clk);
        timeout = timeout + 1;
      end
      require_true(adc_result_ready, "result mailbox did not become ready");
    end
  endtask

  task automatic send_command;
    input logic [COMMAND_WIDTH-1:0] payload;
    begin
      wait_command_ready();
      @(negedge cpu_clk);
      cpu_command_payload = payload;
      cpu_command_valid = 1'b1;
      @(negedge cpu_clk);
      cpu_command_valid = 1'b0;
      cpu_command_payload = ~payload;
    end
  endtask

  task automatic send_result;
    input logic [RESULT_WIDTH-1:0] payload;
    begin
      wait_result_ready();
      @(negedge adc_clk);
      adc_result_payload = payload;
      adc_result_valid = 1'b1;
      @(negedge adc_clk);
      adc_result_valid = 1'b0;
      adc_result_payload = ~payload;
    end
  endtask

  always @(posedge adc_clk) begin
    if (adc_resetn) begin
      require_true(!$isunknown({adc_command_valid, adc_command_epoch_fault}),
                   "X/Z on command destination control");
      if (adc_command_valid) begin
        require_true(adc_command_payload === expected_command[command_count],
                     "command payload was torn or reordered");
        command_count = command_count + 1;
      end
      if (adc_command_epoch_fault)
        command_fault_count = command_fault_count + 1;
      if (adc_result_valid && adc_result_ready)
        result_accept_count = result_accept_count + 1;
    end
  end

  always @(posedge cpu_clk) begin
    if (cpu_resetn) begin
      require_true(!$isunknown({cpu_result_valid, cpu_result_epoch_fault}),
                   "X/Z on result destination control");
      if (cpu_result_valid) begin
        require_true(cpu_result_payload === expected_result[result_count],
                     "result payload was torn or reordered");
        result_count = result_count + 1;
      end
      if (cpu_result_epoch_fault)
        result_fault_count = result_fault_count + 1;
      if (cpu_command_valid && cpu_command_ready)
        command_accept_count = command_accept_count + 1;
    end
  end

  initial begin
    #200000;
    $display("FAIL: fft_cdc testbench timeout");
    $fatal(1);
  end

  initial begin
    // Randomized phase offset plus unrelated 7 ns and 11 ns clocks.
    #13;
    cpu_resetn = 1'b1;
    #17;
    adc_resetn = 1'b1;
    wait_command_ready();
    wait_result_ready();

    // More than two deliveries force both request toggles to wrap repeatedly.
    for (index = 0; index < 8; index = index + 1) begin
      expected_command[index] = {16'h0010, index[31:0], 32'hc0de_0000 ^ index};
      send_command(expected_command[index]);
      #($urandom_range(1, 9));
    end
    wait_command_ready();
    repeat (5) @(posedge adc_clk);
    require_true(command_count == 8, "command delivery was not exactly once");

    for (index = 0; index < 8; index = index + 1) begin
      expected_result[index] = {16'h0010, 16'h55aa, index[31:0],
                                64'h0123_4567_89ab_cdef ^ index, 32'h9000_0000 | index};
      send_result(expected_result[index]);
      #($urandom_range(1, 13));
    end
    wait_result_ready();
    repeat (5) @(posedge cpu_clk);
    require_true(result_count == 8, "result delivery was not exactly once");

    // Destination-only reset cannot replay the last acknowledged command.
    @(negedge adc_clk);
    adc_resetn = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_command_epoch = 16'h0011;
    adc_resetn = 1'b1;
    repeat (8) @(posedge adc_clk);
    require_true(command_count == 8, "ADC reset replayed an old command");

    // A stale epoch is acknowledged and rejected; a new matching epoch recovers.
    send_command({16'h0010, 64'hdead_beef_0000_0010});
    wait_command_ready();
    repeat (4) @(posedge adc_clk);
    require_true(command_count == 8 && command_fault_count == 1,
                 "stale command epoch was not rejected exactly once");
    cpu_command_epoch = 16'h0011;
    expected_command[8] = {16'h0011, 64'hfeed_face_0000_0011};
    send_command(expected_command[8]);
    wait_command_ready();
    repeat (4) @(posedge adc_clk);
    require_true(command_count == 9, "matching command epoch did not recover");

    // Source-only reset cannot create a phantom command toggle.
    @(negedge cpu_clk);
    cpu_resetn = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_resetn = 1'b1;
    repeat (10) @(posedge adc_clk);
    require_true(command_count == 9, "CPU reset created a phantom command");

    // Mirror the one-sided reset and epoch checks for the result direction.
    @(negedge cpu_clk);
    cpu_resetn = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_result_epoch = 16'h0011;
    cpu_resetn = 1'b1;
    repeat (8) @(posedge cpu_clk);
    require_true(result_count == 8, "CPU reset replayed an old result");

    send_result({16'h0010, 144'hdead_beef_cafe_0001_2345_6789_abcd_ef01_0010});
    wait_result_ready();
    repeat (4) @(posedge cpu_clk);
    require_true(result_count == 8 && result_fault_count == 1,
                 "stale result epoch was not rejected exactly once");
    adc_result_epoch = 16'h0011;
    expected_result[8] = {16'h0011, 144'hfeed_face_cafe_0001_2345_6789_abcd_ef01_0011};
    send_result(expected_result[8]);
    wait_result_ready();
    repeat (4) @(posedge cpu_clk);
    require_true(result_count == 9, "matching result epoch did not recover");

    @(negedge adc_clk);
    adc_resetn = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_resetn = 1'b1;
    repeat (10) @(posedge cpu_clk);
    require_true(result_count == 9, "ADC reset created a phantom result");

    // A remote destination reset must gate ready immediately, before the
    // synchronized ready indication has time to fall. A pulse in that window
    // is not accepted and must never become a transfer after recovery.
    wait_command_ready();
    index = command_accept_count;
    @(negedge adc_clk);
    adc_resetn = 1'b0;
    #1;
    require_true(!cpu_command_ready,
                 "command ready stayed high after ADC reset assertion");
    @(negedge cpu_clk);
    cpu_command_payload = {16'h0011, 64'hbad0_0000_0000_0001};
    cpu_command_valid = 1'b1;
    @(posedge cpu_clk); #1;
    require_true(command_accept_count == index,
                 "command was silently accepted while ADC reset was visible");
    @(negedge cpu_clk);
    cpu_command_valid = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_resetn = 1'b1;
    repeat (10) @(posedge adc_clk);
    require_true(command_count == 9 && command_fault_count == 1,
                 "command reset-window attempt produced valid or fault");

    wait_result_ready();
    index = result_accept_count;
    @(negedge cpu_clk);
    cpu_resetn = 1'b0;
    #1;
    require_true(!adc_result_ready,
                 "result ready stayed high after CPU reset assertion");
    @(negedge adc_clk);
    adc_result_payload = {16'h0011, 144'hbad0_0000_0000_0000_0000_0000_0000_0000_0001};
    adc_result_valid = 1'b1;
    @(posedge adc_clk); #1;
    require_true(result_accept_count == index,
                 "result was silently accepted while CPU reset was visible");
    @(negedge adc_clk);
    adc_result_valid = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_resetn = 1'b1;
    repeat (10) @(posedge cpu_clk);
    require_true(result_count == 9 && result_fault_count == 1,
                 "result reset-window attempt produced valid or fault");

    // A transfer accepted before a destination-only reset remains pending and
    // is delivered once after recovery; reset may not align/ack it silently.
    wait_command_ready();
    expected_command[9] = {16'h0011, 64'h1111_2222_3333_4444};
    @(negedge cpu_clk);
    cpu_command_payload = expected_command[9];
    cpu_command_valid = 1'b1;
    @(posedge cpu_clk); #1;
    require_true(command_accept_count == 11,
                 "in-flight command was not accepted before ADC reset");
    @(negedge cpu_clk);
    cpu_command_valid = 1'b0;
    cpu_command_payload = ~expected_command[9];
    adc_resetn = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_resetn = 1'b1;
    repeat (16) @(posedge adc_clk);
    require_true(command_count == 10 && command_fault_count == 1,
                 "in-flight command was lost, duplicated, or faulted across ADC reset");

    wait_result_ready();
    expected_result[9] = {16'h0011, 144'h1111_2222_3333_4444_5555_6666_7777_8888_9999};
    @(negedge adc_clk);
    adc_result_payload = expected_result[9];
    adc_result_valid = 1'b1;
    @(posedge adc_clk); #1;
    require_true(result_accept_count == 11,
                 "in-flight result was not accepted before CPU reset");
    @(negedge adc_clk);
    adc_result_valid = 1'b0;
    adc_result_payload = ~expected_result[9];
    cpu_resetn = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_resetn = 1'b1;
    repeat (16) @(posedge cpu_clk);
    require_true(result_count == 10 && result_fault_count == 1,
                 "in-flight result was lost, duplicated, or faulted across CPU reset");

    // The preceding eleven accepted transfers leave each request toggle at
    // one. Resetting that source must not create a falling-edge request,
    // stale payload, duplicate delivery, or phantom epoch fault.
    wait_command_ready();
    require_true(u_command_cdc.request_toggle == 1'b1,
                 "command reset-at-toggle-one precondition not reached");
    @(negedge cpu_clk);
    cpu_resetn = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_resetn = 1'b1;
    repeat (12) @(posedge adc_clk);
    require_true(command_count == 10 && command_fault_count == 1,
                 "command source reset at toggle one replayed stale state");

    wait_result_ready();
    require_true(u_result_cdc.request_toggle == 1'b1,
                 "result reset-at-toggle-one precondition not reached");
    @(negedge adc_clk);
    adc_resetn = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_resetn = 1'b1;
    repeat (12) @(posedge cpu_clk);
    require_true(result_count == 10 && result_fault_count == 1,
                 "result source reset at toggle one replayed stale state");

    // Reset the destination after it has delivered and retained-ack has
    // changed, but before that acknowledgement can clear source_pending. The
    // completed bundle must not be recovered and delivered a second time.
    wait_command_ready();
    delivery_before = command_valid_edge_count;
    fault_before = command_fault_edge_count;
    expected_command[10] = {16'h0011, 64'haaaa_bbbb_cccc_dddd};
    @(negedge cpu_clk);
    cpu_command_payload = expected_command[10];
    cpu_command_valid = 1'b1;
    @(negedge cpu_clk);
    cpu_command_valid = 1'b0;
    cpu_command_payload = ~expected_command[10];
    @(posedge adc_command_valid); #1;
    require_true(command_valid_edge_count == delivery_before + 1,
                 "post-delivery command reset precondition missing valid");
    require_true(u_command_cdc.source_pending,
                 "command acknowledgement returned before reset window");
    adc_resetn = 1'b0;
    repeat (3) @(negedge adc_clk);
    adc_resetn = 1'b1;
    wait_command_ready();
    repeat (8) @(posedge adc_clk);
    require_true(command_valid_edge_count == delivery_before + 1 &&
                 command_fault_edge_count == fault_before,
                 "command replayed after destination reset post-acknowledge");

    wait_result_ready();
    delivery_before = result_valid_edge_count;
    fault_before = result_fault_edge_count;
    expected_result[10] = {16'h0011, 144'haaaa_bbbb_cccc_dddd_eeee_ffff_1111_2222_3333};
    @(negedge adc_clk);
    adc_result_payload = expected_result[10];
    adc_result_valid = 1'b1;
    @(negedge adc_clk);
    adc_result_valid = 1'b0;
    adc_result_payload = ~expected_result[10];
    @(posedge cpu_result_valid); #1;
    require_true(result_valid_edge_count == delivery_before + 1,
                 "post-delivery result reset precondition missing valid");
    require_true(u_result_cdc.source_pending,
                 "result acknowledgement returned before reset window");
    cpu_resetn = 1'b0;
    repeat (3) @(negedge cpu_clk);
    cpu_resetn = 1'b1;
    wait_result_ready();
    repeat (8) @(posedge cpu_clk);
    require_true(result_valid_edge_count == delivery_before + 1 &&
                 result_fault_edge_count == fault_before,
                 "result replayed after destination reset post-acknowledge");

    $display("PASS: fft_cdc");
    $finish;
  end
endmodule

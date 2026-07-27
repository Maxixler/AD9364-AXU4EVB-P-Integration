`timescale 1ns/1ps

module tb_adc_frame_capture;

  localparam integer FRAME_LENGTH = 2048;

  reg         adc_clk = 1'b0;
  reg         adc_resetn = 1'b0;
  reg         start = 1'b0;
  reg         abort = 1'b0;
  reg         adc_valid = 1'b0;
  reg         adc_enable = 1'b0;
  reg  [15:0] adc_i = 16'd0;
  reg  [15:0] adc_q = 16'd0;
  reg  [2:0]  rf_state = 3'd0;
  reg  [10:0] mem_rd_addr = 11'd0;

  wire        busy;
  wire        frame_ready;
  wire        aborted;
  wire [31:0] first_sample;
  wire [11:0] sample_count;
  wire [31:0] frame_crc32;
  wire [31:0] dropped_count;
  wire [2:0]  frame_rf_state;
  wire [31:0] mem_rd_data;

  integer sample_index;
  integer collision_failures;
  reg [31:0] expected_crc;
  reg [31:0] read_word;

  always #5 adc_clk = ~adc_clk;

  adc_frame_capture #(
    .DROPPED_COUNTER_WIDTH(4)
  ) dut (
    .adc_clk(adc_clk),
    .adc_resetn(adc_resetn),
    .start(start),
    .abort(abort),
    .adc_valid(adc_valid),
    .adc_enable(adc_enable),
    .adc_i(adc_i),
    .adc_q(adc_q),
    .rf_state(rf_state),
    .busy(busy),
    .frame_ready(frame_ready),
    .aborted(aborted),
    .first_sample(first_sample),
    .sample_count(sample_count),
    .frame_crc32(frame_crc32),
    .dropped_count(dropped_count),
    .frame_rf_state(frame_rf_state),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_data(mem_rd_data)
  );

  function automatic [31:0] crc32_word;
    input [31:0] crc_in;
    input [31:0] data;
    integer bit_index;
    reg [31:0] crc;
    begin
      crc = crc_in;
      for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
        if (crc[0] ^ data[bit_index])
          crc = (crc >> 1) ^ 32'hEDB88320;
        else
          crc = crc >> 1;
      end
      crc32_word = crc;
    end
  endfunction

  function automatic [31:0] sample_word;
    input integer index;
    reg [15:0] i_value;
    reg [15:0] q_value;
    begin
      i_value = index + 16'h1200;
      q_value = -index - 1;
      sample_word = {q_value, i_value};
    end
  endfunction

  task automatic drive_cycle;
    input valid;
    input enable;
    input [31:0] word;
    begin
      @(negedge adc_clk);
      adc_valid = valid;
      adc_enable = enable;
      adc_i = word[15:0];
      adc_q = word[31:16];
      @(posedge adc_clk);
      #1;
      @(negedge adc_clk);
      adc_valid = 1'b0;
      adc_enable = 1'b0;
    end
  endtask

  task automatic pulse_start;
    input [2:0] tag;
    begin
      @(negedge adc_clk);
      rf_state = tag;
      start = 1'b1;
      @(posedge adc_clk);
      #1;
      @(negedge adc_clk);
      start = 1'b0;
    end
  endtask

  task automatic pulse_abort;
    begin
      @(negedge adc_clk);
      abort = 1'b1;
      @(posedge adc_clk);
      #1;
      @(negedge adc_clk);
      abort = 1'b0;
    end
  endtask

  task automatic read_memory;
    input [10:0] address;
    output [31:0] value;
    begin
      @(negedge adc_clk);
      mem_rd_addr = address;
      @(posedge adc_clk);
      #1 value = mem_rd_data;
    end
  endtask

  task automatic require_true;
    input condition;
    input [8*96-1:0] message;
    begin
      if (condition !== 1'b1) begin
        $display("FAIL: %0s", message);
        $fatal(1);
        $finish;
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge adc_clk);
    adc_resetn = 1'b1;
    repeat (2) @(posedge adc_clk);

    // START and ABORT retain control precedence, but a source sample on the
    // same edge is still rejected traffic and therefore must be counted.
    collision_failures = 0;
    @(negedge adc_clk);
    start = 1'b1;
    adc_valid = 1'b1;
    adc_enable = 1'b1;
    adc_i = 16'h1111;
    adc_q = 16'h2222;
    @(posedge adc_clk);
    #1;
    if (dropped_count !== 32'd1) begin
      $display("FAIL: START/sample collision was not counted as dropped");
      collision_failures = collision_failures + 1;
    end
    require_true(busy && sample_count == 12'd0,
                 "START/sample collision captured the rejected sample");

    @(negedge adc_clk);
    start = 1'b0;
    abort = 1'b1;
    adc_i = 16'h3333;
    adc_q = 16'h4444;
    @(posedge adc_clk);
    #1;
    if (dropped_count !== 32'd2) begin
      $display("FAIL: ABORT/sample collision was not counted as dropped");
      collision_failures = collision_failures + 1;
    end
    require_true(!busy && aborted && !frame_ready,
                 "ABORT/sample collision did not preserve abort precedence");

    @(negedge adc_clk);
    abort = 1'b0;
    adc_valid = 1'b0;
    adc_enable = 1'b0;
    require_true(collision_failures == 0, "control/sample collision accounting failed");

    // Reset before the independent saturation and frame-integrity cases.
    adc_resetn = 1'b0;
    @(posedge adc_clk);
    #1;
    @(negedge adc_clk);
    adc_resetn = 1'b1;
    repeat (2) @(posedge adc_clk);

    // Samples arriving while no capture is armed are rejected.  The reduced
    // test width proves that the externally 32-bit counter saturates.
    for (sample_index = 0; sample_index < 20; sample_index = sample_index + 1)
      drive_cycle(1'b1, 1'b1, 32'hCAFE0000 + sample_index);
    require_true(dropped_count == 32'd15, "dropped counter did not saturate");

    // Abort immediately after the first accepted sample.
    pulse_start(3'd1);
    require_true(busy && !frame_ready, "capture did not arm");
    drive_cycle(1'b1, 1'b1, sample_word(0));
    require_true(sample_count == 12'd1, "first accepted sample was not counted");
    pulse_abort();
    require_true(!busy && !frame_ready && aborted, "abort at sample 1 published a partial frame");
    require_true(sample_count == 12'd0, "abort did not invalidate sample count");
    @(posedge adc_clk);
    #1 require_true(!aborted, "aborted must be a one-cycle indication");

    // Abort with 2047 accepted samples; the almost-complete frame is still
    // forbidden from becoming visible.
    pulse_start(3'd2);
    for (sample_index = 0; sample_index < FRAME_LENGTH-1; sample_index = sample_index + 1)
      drive_cycle(1'b1, 1'b1, sample_word(sample_index));
    require_true(sample_count == 12'd2047 && !frame_ready, "frame published before sample 2048");
    pulse_abort();
    require_true(!busy && !frame_ready && aborted, "abort at sample 2047 published a partial frame");

    // Complete a frame while injecting both valid-only and enable-only gaps.
    pulse_start(3'd5);
    expected_crc = 32'hFFFFFFFF;
    for (sample_index = 0; sample_index < FRAME_LENGTH; sample_index = sample_index + 1) begin
      if ((sample_index % 17) == 3)
        drive_cycle(1'b1, 1'b0, 32'hBAD10000 + sample_index);
      if ((sample_index % 19) == 4)
        drive_cycle(1'b0, 1'b1, 32'hBAD20000 + sample_index);

      if (sample_index == 37) begin
        pulse_start(3'd7);
        require_true(busy && sample_count == 12'd37,
                     "start while busy restarted or corrupted capture");
      end

      require_true(!frame_ready, "frame_ready asserted before final accepted sample");
      expected_crc = crc32_word(expected_crc, sample_word(sample_index));
      drive_cycle(1'b1, 1'b1, sample_word(sample_index));
    end

    require_true(!busy && frame_ready, "complete frame was not published");
    require_true(sample_count == 12'd2048, "complete sample count is not 2048");
    require_true(first_sample == sample_word(0), "first sample metadata mismatch");
    require_true(frame_crc32 == (expected_crc ^ 32'hFFFFFFFF), "CRC-32/ISO-HDLC mismatch");
    // Frozen independently with Python zlib.crc32 over the 2048 little-endian
    // {Q,I} words.  This catches a matching bug in the two HDL CRC functions.
    require_true(frame_crc32 == 32'hC266883D, "CRC does not match frozen zlib oracle");
    require_true(frame_rf_state == 3'd5, "RF tag changed after start acceptance");
    require_true(dropped_count == 32'd15, "accepted traffic changed dropped count");

    read_memory(11'd0, read_word);
    require_true(read_word == sample_word(0), "RAM sample 0 mismatch");
    read_memory(11'd1024, read_word);
    require_true(read_word == sample_word(1024), "RAM sample 1024 mismatch");
    read_memory(11'd2047, read_word);
    require_true(read_word == sample_word(2047), "RAM sample 2047 mismatch");

    $display("PASS: adc_frame_capture");
    $finish;
  end

endmodule

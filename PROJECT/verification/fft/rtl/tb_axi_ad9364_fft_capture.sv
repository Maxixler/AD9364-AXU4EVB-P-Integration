`timescale 1ns/1ps

module tb_axi_ad9364_fft_capture;
  reg adc_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  reg adc_resetn = 1'b0;
  reg s_axi_aresetn = 1'b0;
  reg adc_valid = 1'b0;
  reg adc_enable = 1'b0;
  reg [15:0] adc_i = 16'd0;
  reg [15:0] adc_q = 16'd0;
  reg [2:0] rf_state = 3'd0;

  reg [7:0] s_axi_awaddr = 8'd0;
  reg s_axi_awvalid = 1'b0;
  wire s_axi_awready;
  reg [31:0] s_axi_wdata = 32'd0;
  reg [3:0] s_axi_wstrb = 4'd0;
  reg s_axi_wvalid = 1'b0;
  wire s_axi_wready;
  wire [1:0] s_axi_bresp;
  wire s_axi_bvalid;
  reg s_axi_bready = 1'b0;
  reg [7:0] s_axi_araddr = 8'd0;
  reg s_axi_arvalid = 1'b0;
  wire s_axi_arready;
  wire [31:0] s_axi_rdata;
  wire [1:0] s_axi_rresp;
  wire s_axi_rvalid;
  reg s_axi_rready = 1'b0;

  reg bank0_bram_en = 1'b0;
  reg [10:0] bank0_bram_addr = 11'd0;
  wire [63:0] bank0_bram_rddata;
  reg bank1_bram_en = 1'b0;
  reg [10:0] bank1_bram_addr = 11'd0;
  wire [63:0] bank1_bram_rddata;
  wire irq;

  reg [31:0] input_words [0:2047];
  reg [31:0] fft_words [0:2047];
  reg [63:0] power_words [0:2047];
  integer fft_index = 0;
  integer checked_cases = 0;
  reg case_active = 1'b0;

  always #4 adc_clk = ~adc_clk;
  always #5.5 s_axi_aclk = ~s_axi_aclk;

  axi_ad9364_fft_capture dut (
    .adc_clk(adc_clk), .adc_resetn(adc_resetn),
    .adc_valid(adc_valid), .adc_enable(adc_enable),
    .adc_i(adc_i), .adc_q(adc_q), .rf_state(rf_state),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .bank0_bram_en(bank0_bram_en), .bank0_bram_addr(bank0_bram_addr),
    .bank0_bram_rddata(bank0_bram_rddata),
    .bank1_bram_en(bank1_bram_en), .bank1_bram_addr(bank1_bram_addr),
    .bank1_bram_rddata(bank1_bram_rddata), .irq(irq)
  );

  task automatic fail(input string reason);
    begin
      $display("FAIL: %s", reason);
      $finish;
    end
  endtask

  task automatic axi_write(input [7:0] address, input [31:0] data);
    integer wait_cycles;
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr = address;
      s_axi_awvalid = 1'b1;
      s_axi_wdata = data;
      s_axi_wstrb = 4'hf;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      wait_cycles = 0;
      while (!(s_axi_awready && s_axi_wready) && wait_cycles < 100) begin
        @(negedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (!(s_axi_awready && s_axi_wready))
        fail("AXI write address/data handshake timeout");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      wait_cycles = 0;
      while (!s_axi_bvalid && wait_cycles < 100) begin
        @(negedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (!s_axi_bvalid)
        fail("AXI write response timeout");
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic axi_read(input [7:0] address, output [31:0] data);
    integer wait_cycles;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      wait_cycles = 0;
      while (!s_axi_arready && wait_cycles < 100) begin
        @(negedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (!s_axi_arready)
        fail("AXI read address handshake timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      wait_cycles = 0;
      while (!s_axi_rvalid && wait_cycles < 100) begin
        @(negedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (!s_axi_rvalid)
        fail("AXI read data timeout");
      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic expect_reg(input [7:0] address, input [31:0] expected,
                            input string label_text);
    reg [31:0] actual;
    begin
      axi_read(address, actual);
      if (actual !== expected) begin
        $display("FAIL: %s expected=%08x actual=%08x", label_text,
                 expected, actual);
        $finish;
      end
    end
  endtask

  task automatic send_sample(input [31:0] sample_word, input integer gap);
    integer n;
    begin
      adc_valid = 1'b0;
      adc_enable = 1'b0;
      for (n = 0; n < gap; n = n + 1)
        @(posedge adc_clk);
      @(negedge adc_clk);
      adc_i = sample_word[15:0];
      adc_q = sample_word[31:16];
      adc_valid = 1'b1;
      adc_enable = 1'b1;
      @(negedge adc_clk);
      adc_valid = 1'b0;
      adc_enable = 1'b0;
    end
  endtask

  task automatic read_bank0(input [10:0] address, output [63:0] data);
    begin
      @(negedge s_axi_aclk);
      bank0_bram_addr = address;
      bank0_bram_en = 1'b1;
      @(posedge s_axi_aclk);
      #1 data = bank0_bram_rddata;
      @(negedge s_axi_aclk);
      bank0_bram_en = 1'b0;
    end
  endtask

  task automatic run_case(
    input string case_name,
    input string input_file,
    input string fft_file,
    input string power_file,
    input [10:0] search_start,
    input [10:0] search_stop,
    input [10:0] dc_guard,
    input [31:0] expected_crc,
    input [10:0] expected_peak_bin,
    input [32:0] expected_peak_power,
    input signed [15:0] expected_peak_re,
    input signed [15:0] expected_peak_im,
    input [2:0] test_rf_state,
    input [31:0] expected_frame_id);
    integer index;
    integer timeout_count;
    reg [31:0] value;
    reg [63:0] bank_word;
    reg [31:0] dropped_before;
    begin
      $display("TRACE: starting %s", case_name);
      $readmemh(input_file, input_words);
      $readmemh(fft_file, fft_words);
      $readmemh(power_file, power_words);
      rf_state = test_rf_state;

      axi_write(8'h0c, {5'd0, search_stop, 5'd0, search_start});
      axi_write(8'h10, {14'd0, 2'd0, 5'd0, dc_guard});
      axi_write(8'h14, {16'd0, 13'd0, test_rf_state});
      fft_index = 0;
      case_active = 1'b1;
      axi_write(8'h04, 32'h0000_0001);
      timeout_count = 0;
      while (!dut.capture_busy && timeout_count < 1000) begin
        @(posedge adc_clk);
        timeout_count = timeout_count + 1;
      end
      if (!dut.capture_busy)
        fail("accepted START did not arm ADC capture");
      $display("TRACE: %s capture armed at %0t", case_name, $time);

      // A second start while the capture is active must be consumed and
      // rejected locally without replacing the active frame.
      for (index = 0; index < 2048; index = index + 1) begin
        send_sample(input_words[index], ((index % 7) == 0) ? 2 : 0);
        if (index == 63)
          axi_write(8'h04, 32'h0000_0001);
        if ((index % 257) == 0) begin
          axi_read(8'h40, value);
          if (value[1:0] != 2'b00)
            fail("partial capture changed CPU-visible bank validity");
        end
      end
      $display("TRACE: %s capture feed complete at %0t", case_name, $time);

      // Hold the internal FFT-to-bank path stopped while the non-backpressured
      // ADC source continues. These samples must be counted as dropped; there
      // is deliberately no ready signal on the ADC interface.
      force dut.magnitude_ready = 1'b0;
      repeat (20) @(posedge adc_clk);
      dropped_before = dut.capture_dropped_count;
      for (index = 0; index < 16; index = index + 1)
        send_sample(32'h5a00_0000 + index, 0);
      if (dut.capture_dropped_count < (dropped_before + 16)) begin
        $display("FAIL: stalled ADC dropped_before=%0d dropped_after=%0d",
                 dropped_before, dut.capture_dropped_count);
        fail("ADC traffic did not continue while FFT output was stalled");
      end
      axi_read(8'h40, value);
      if (value[1:0] != 2'b00)
        fail("stalled partial spectrum became CPU-visible");
      release dut.magnitude_ready;
      $display("TRACE: %s output stall released at %0t", case_name, $time);

      timeout_count = 0;
      value = 32'd0;
      while ((value[0] == 1'b0) && (timeout_count < 1000)) begin
        repeat (10) @(posedge s_axi_aclk);
        axi_read(8'h40, value);
        timeout_count = timeout_count + 1;
      end
      if (!value[0]) begin
        $display("FAIL: timeout state pipe=%0d capture_ready=%0b replay_busy=%0b replay_done=%0b fft_index=%0d fft_valid=%0b fft_ready=%0b bank_active=%0b bank_rejected=%0b bank0_adc_valid=%0b cmd_ready=%0b fft_error=%0b",
                 dut.pipeline_state, dut.capture_frame_ready, dut.replay_busy,
                 dut.replay_done, fft_index, dut.fft_valid, dut.fft_ready,
                 dut.bank_frame_active, dut.bank_frame_rejected,
                 dut.bank0_valid_adc, dut.command_ready, dut.fft_error_adc);
        fail("timed out waiting for atomic bank publication");
      end
      $display("TRACE: %s bank published at %0t", case_name, $time);
      case_active = 1'b0;
      if (fft_index != 2048)
        fail("FFT did not produce exactly 2048 components");

      expect_reg(8'h18, expected_frame_id, "FRAME_ID");
      expect_reg(8'h1c, {16'd0, 12'd0, test_rf_state, 1'b0}, "RESULT_TAG");
      expect_reg(8'h20, 32'd2048, "SAMPLE_COUNT");
      expect_reg(8'h24, {21'd0, expected_peak_bin}, "PEAK_BIN");
      expect_reg(8'h28, expected_peak_power[31:0], "PEAK_POWER_LO");
      expect_reg(8'h2c, {31'd0, expected_peak_power[32]}, "PEAK_POWER_HI");
      expect_reg(8'h30, {expected_peak_im, expected_peak_re}, "PEAK_RE_IM");
      expect_reg(8'h34, input_words[0], "FIRST_SAMPLE");
      expect_reg(8'h38, expected_crc, "FRAME_CRC32");
      axi_read(8'h08, value);
      if (!value[1] || value[7] || value[6] || value[5])
        fail("DONE/error/overflow status invariant failed");

      for (index = 0; index < 2048; index = index + 1) begin
        read_bank0(index[10:0], bank_word);
        if (bank_word !== power_words[index]) begin
          $display("FAIL: %s power bin %0d expected=%016x actual=%016x",
                   case_name, index, power_words[index], bank_word);
          $finish;
        end
      end
      $display("TRACE: %s bank verified at %0t", case_name, $time);

      checked_cases = checked_cases + 1;
      axi_write(8'h04, 32'h0000_0010);
      axi_write(8'h08, 32'h0000_07f2);
      axi_read(8'h40, value);
      if (value[0])
        fail("bank release did not clear CPU-visible ownership");
      repeat (20) @(posedge adc_clk);
    end
  endtask

  // This checks the actual Xilinx FFT output before magnitude calculation,
  // proving component-level zero-LSB equivalence as well as power equivalence.
  always @(posedge adc_clk) begin
    if (case_active && dut.fft_valid && dut.fft_ready) begin
      if (fft_index >= 2048)
        fail("FFT produced more than 2048 components");
      if (dut.fft_data !== fft_words[fft_index]) begin
        $display("FAIL: FFT component bin %0d expected=%08x actual=%08x",
                 fft_index, fft_words[fft_index], dut.fft_data);
        $finish;
      end
      if (dut.fft_last !== (fft_index == 2047))
        fail("FFT TLAST did not identify bin 2047");
      fft_index = fft_index + 1;
    end
  end

  initial begin
    repeat (8) @(posedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (8) @(posedge adc_clk);
    adc_resetn = 1'b1;

    // The ready bit includes both mailbox arming and the one-time raw 0x0D57
    // configuration handshake with the actual xFFT instance.
    begin : wait_ready
      integer ready_timeout;
      reg [31:0] ready_status;
      ready_timeout = 0;
      ready_status = 0;
      while (!ready_status[2] && ready_timeout < 1000) begin
        axi_read(8'h08, ready_status);
        ready_timeout = ready_timeout + 1;
      end
      if (!ready_status[2])
        fail("CDC/xFFT configuration never became ready");
    end

    run_case("zeros", "zeros.input.hex", "zeros.fft.hex", "zeros.power.hex",
             0, 2047, 0, 32'hD8F49994, 1, 33'd0, 0, 0, 3'd1, 1);
    run_case("impulse", "impulse.input.hex", "impulse.fft.hex", "impulse.power.hex",
             0, 2047, 4, 32'hF5EB8ADF, 5, 33'd64, 8, 0, 3'd2, 2);
    run_case("tone_bin_137", "tone_bin_137.input.hex", "tone_bin_137.fft.hex",
             "tone_bin_137.power.hex", 0, 2047, 0, 32'hB4B6B2BD,
             137, 33'd4194304, 2048, 0, 3'd3, 3);
    run_case("tone_bin_1901", "tone_bin_1901.input.hex", "tone_bin_1901.fft.hex",
             "tone_bin_1901.power.hex", 0, 2047, 0, 32'hABB86F03,
             1901, 33'd4194304, 2048, 0, 3'd4, 4);
    run_case("two_tone_tie", "two_tone_tie.input.hex", "two_tone_tie.fft.hex",
             "two_tone_tie.power.hex", 0, 2047, 0, 32'h4DEA120B,
             300, 33'd1048576, 1024, 0, 3'd5, 5);
    run_case("near_full_scale", "near_full_scale.input.hex",
             "near_full_scale.fft.hex", "near_full_scale.power.hex",
             0, 2047, 0, 32'h92652EAB, 137, 33'd268435456,
             16384, 0, 3'd6, 6);

    if (checked_cases != 6)
      fail("not all manifest cases completed");
    $display("PASS: axi_ad9364_fft_capture single-shot");
    $finish;
  end
endmodule

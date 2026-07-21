`timescale 1ns/1ps

module tb_fft_regs;
  logic s_axi_aclk = 1'b0;
  logic s_axi_aresetn = 1'b0;
  logic [7:0] s_axi_awaddr = 8'd0;
  logic s_axi_awvalid = 1'b0;
  logic s_axi_awready;
  logic [31:0] s_axi_wdata = 32'd0;
  logic [3:0] s_axi_wstrb = 4'd0;
  logic s_axi_wvalid = 1'b0;
  logic s_axi_wready;
  logic [1:0] s_axi_bresp;
  logic s_axi_bvalid;
  logic s_axi_bready = 1'b0;
  logic [7:0] s_axi_araddr = 8'd0;
  logic s_axi_arvalid = 1'b0;
  logic s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rvalid;
  logic s_axi_rready = 1'b0;

  logic i_busy = 1'b0;
  logic i_cdc_ready = 1'b0;
  logic i_done = 1'b0;
  logic i_cdc_fault = 1'b0;
  logic i_aborted = 1'b0;
  logic i_frame_error = 1'b0;
  logic i_fft_error = 1'b0;
  logic i_overflow = 1'b0;
  logic i_dropped_samples = 1'b0;
  logic i_bank_overrun = 1'b0;
  logic [31:0] i_frame_id = 32'h1234_5678;
  logic i_active_bank = 1'b1;
  logic [2:0] i_result_rf_state = 3'd5;
  logic [15:0] i_result_epoch = 16'hbeef;
  logic [31:0] i_sample_count = 32'd2048;
  logic [10:0] i_peak_bin = 11'd137;
  logic [32:0] i_peak_power = 33'h1_89ab_cdef;
  logic signed [15:0] i_peak_re = -16'sd123;
  logic signed [15:0] i_peak_im = 16'sd456;
  logic [31:0] i_first_sample = 32'h1357_2468;
  logic [31:0] i_frame_crc32 = 32'hcbf4_3926;
  logic [31:0] i_dropped_count = 32'hffff_fffe;
  logic [1:0] i_bank_valid = 2'b11;

  logic o_start;
  logic o_abort;
  logic o_soft_reset;
  logic o_mode_continuous;
  logic o_bank0_release;
  logic o_bank1_release;
  logic [10:0] o_search_start;
  logic [10:0] o_search_stop;
  logic [10:0] o_dc_guard;
  logic [1:0] o_window_select;
  logic [2:0] o_rf_state;
  logic [15:0] o_reset_epoch;
  logic [10:0] o_status_clear;

  integer start_count = 0;
  integer abort_count = 0;
  integer soft_reset_count = 0;
  integer release0_count = 0;
  integer release1_count = 0;
  logic [31:0] read_value;

  always #5 s_axi_aclk = ~s_axi_aclk;

  axi_ad9364_fft_regs u_dut (
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready), .i_busy(i_busy),
    .i_cdc_ready(i_cdc_ready), .i_done(i_done),
    .i_cdc_fault(i_cdc_fault), .i_aborted(i_aborted),
    .i_frame_error(i_frame_error), .i_fft_error(i_fft_error),
    .i_overflow(i_overflow), .i_dropped_samples(i_dropped_samples),
    .i_bank_overrun(i_bank_overrun), .i_frame_id(i_frame_id),
    .i_active_bank(i_active_bank), .i_result_rf_state(i_result_rf_state),
    .i_result_epoch(i_result_epoch), .i_sample_count(i_sample_count),
    .i_peak_bin(i_peak_bin), .i_peak_power(i_peak_power),
    .i_peak_re(i_peak_re), .i_peak_im(i_peak_im),
    .i_first_sample(i_first_sample), .i_frame_crc32(i_frame_crc32),
    .i_dropped_count(i_dropped_count), .i_bank_valid(i_bank_valid),
    .o_start(o_start), .o_abort(o_abort), .o_soft_reset(o_soft_reset),
    .o_mode_continuous(o_mode_continuous),
    .o_bank0_release(o_bank0_release), .o_bank1_release(o_bank1_release),
    .o_search_start(o_search_start), .o_search_stop(o_search_stop),
    .o_dc_guard(o_dc_guard), .o_window_select(o_window_select),
    .o_rf_state(o_rf_state), .o_reset_epoch(o_reset_epoch),
    .o_status_clear(o_status_clear)
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

  task automatic axi_write;
    input logic [7:0] address;
    input logic [31:0] data;
    input logic [3:0] strobe;
    input integer order;
    input integer response_stall;
    integer count;
    begin
      s_axi_bready = 1'b0;
      if (order == 0) begin
        @(negedge s_axi_aclk); s_axi_awaddr = address; s_axi_awvalid = 1'b1;
        while (!s_axi_awready) @(negedge s_axi_aclk);
        @(negedge s_axi_aclk); s_axi_awvalid = 1'b0;
        repeat (3) @(negedge s_axi_aclk);
        s_axi_wdata = data; s_axi_wstrb = strobe; s_axi_wvalid = 1'b1;
        while (!s_axi_wready) @(negedge s_axi_aclk);
        @(negedge s_axi_aclk); s_axi_wvalid = 1'b0;
      end else begin
        @(negedge s_axi_aclk); s_axi_wdata = data; s_axi_wstrb = strobe; s_axi_wvalid = 1'b1;
        while (!s_axi_wready) @(negedge s_axi_aclk);
        @(negedge s_axi_aclk); s_axi_wvalid = 1'b0;
        repeat (2) @(negedge s_axi_aclk);
        s_axi_awaddr = address; s_axi_awvalid = 1'b1;
        while (!s_axi_awready) @(negedge s_axi_aclk);
        @(negedge s_axi_aclk); s_axi_awvalid = 1'b0;
      end
      while (!s_axi_bvalid) @(negedge s_axi_aclk);
      for (count = 0; count < response_stall; count = count + 1) begin
        require_true(s_axi_bvalid && s_axi_bresp == 2'b00,
                     "write response changed under backpressure");
        @(negedge s_axi_aclk);
      end
      s_axi_bready = 1'b1;
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic axi_read;
    input logic [7:0] address;
    input integer response_stall;
    output logic [31:0] data;
    integer count;
    logic [31:0] held_data;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      while (!s_axi_arready) @(negedge s_axi_aclk);
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      while (!s_axi_rvalid) @(negedge s_axi_aclk);
      held_data = s_axi_rdata;
      for (count = 0; count < response_stall; count = count + 1) begin
        require_true(s_axi_rvalid && s_axi_rresp == 2'b00 && s_axi_rdata === held_data,
                     "read response changed under backpressure");
        @(negedge s_axi_aclk);
      end
      data = s_axi_rdata;
      s_axi_rready = 1'b1;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  always @(posedge s_axi_aclk) begin
    if (s_axi_aresetn) begin
      require_true(!$isunknown({s_axi_awready, s_axi_wready, s_axi_bvalid,
                                s_axi_arready, s_axi_rvalid}),
                   "X/Z on AXI-Lite control");
      if (o_start) start_count = start_count + 1;
      if (o_abort) abort_count = abort_count + 1;
      if (o_soft_reset) soft_reset_count = soft_reset_count + 1;
      if (o_bank0_release) release0_count = release0_count + 1;
      if (o_bank1_release) release1_count = release1_count + 1;
    end
  end

  initial begin
    #500000;
    $display("FAIL: fft_regs testbench timeout");
    $fatal(1);
  end

  initial begin
    repeat (5) @(posedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (2) @(posedge s_axi_aclk);

    axi_read(8'h00, 3, read_value);
    require_true(read_value == 32'h0001_0000, "VERSION mismatch");

    // Independent AW then W, and W then AW, plus byte-lane preservation.
    axi_write(8'h0c, 32'h0555_0123, 4'b1111, 0, 4);
    axi_read(8'h0c, 0, read_value);
    require_true(read_value == 32'h0555_0123, "SEARCH_RANGE full write mismatch");
    axi_write(8'h0c, 32'h07aa_00ee, 4'b1100, 1, 0);
    axi_read(8'h0c, 0, read_value);
    require_true(read_value == 32'h07aa_0123, "SEARCH_RANGE WSTRB mismatch");

    axi_write(8'h10, 32'h0000_0100, 4'b0011, 0, 0);
    axi_write(8'h10, 32'h0003_0100, 4'b0010, 1, 0);
    require_true(o_window_select == 2'd0,
                 "WSTRB byte 1 changed WINDOW_SELECT in byte 2");
    axi_write(8'h14, 32'ha5a5_0006, 4'b1111, 1, 0);
    require_true(o_search_start == 11'h123 && o_search_stop == 11'h7aa &&
                 o_dc_guard == 11'h100 && o_window_select == 2'd0 &&
                 o_rf_state == 3'd6 && o_reset_epoch == 16'ha5a5,
                 "configuration outputs mismatch");

    // Valid start and all other CONTROL command bits are one-cycle pulses.
    axi_write(8'h04, 32'h0000_003f, 4'b0001, 1, 2);
    repeat (3) @(posedge s_axi_aclk);
    require_true(start_count == 1 && abort_count == 1 && soft_reset_count == 1 &&
                 release0_count == 1 && release1_count == 1,
                 "CONTROL pulses missing or repeated");
    require_true(o_mode_continuous && !o_start && !o_abort && !o_soft_reset &&
                 !o_bank0_release && !o_bank1_release,
                 "CONTROL persistence/pulse contract mismatch");
    axi_read(8'h04, 0, read_value);
    require_true(read_value == 32'h0000_0008, "CONTROL readback exposes pulse bits");

    // Invalid range, guard, and window each reject START and set CONFIG_ERROR.
    axi_write(8'h0c, 32'h0001_0002, 4'b1111, 0, 0);
    axi_write(8'h04, 32'h0000_0001, 4'b0001, 1, 0);
    axi_read(8'h08, 0, read_value);
    require_true(start_count == 1 && read_value[10], "invalid range was accepted");
    axi_write(8'h08, 32'h0000_0400, 4'b0011, 0, 0);
    axi_write(8'h0c, 32'h07ff_0000, 4'b1111, 1, 0);
    axi_write(8'h10, 32'h0000_0401, 4'b0011, 0, 0);
    axi_write(8'h04, 32'h0000_0001, 4'b0001, 1, 0);
    require_true(start_count == 1, "invalid DC guard was accepted");
    axi_write(8'h08, 32'h0000_0400, 4'b0011, 0, 0);
    axi_write(8'h10, 32'h0001_0100, 4'b0111, 1, 0);
    axi_write(8'h04, 32'h0000_0001, 4'b0001, 0, 0);
    require_true(start_count == 1, "unsupported window was accepted");

    // Restore valid configuration and prove recovery.
    axi_write(8'h08, 32'h0000_0400, 4'b0011, 0, 0);
    axi_write(8'h10, 32'h0000_0400, 4'b0111, 1, 0);
    axi_write(8'h04, 32'h0000_0001, 4'b0001, 0, 0);
    require_true(start_count == 2, "valid configuration did not recover START");

    // Sticky events latch, W1C clears them, while BUSY/CDC_READY remain live.
    @(negedge s_axi_aclk);
    i_busy = 1'b1; i_cdc_ready = 1'b1; i_done = 1'b1; i_cdc_fault = 1'b1;
    i_aborted = 1'b1; i_frame_error = 1'b1; i_fft_error = 1'b1;
    i_overflow = 1'b1; i_dropped_samples = 1'b1; i_bank_overrun = 1'b1;
    @(negedge s_axi_aclk);
    i_done = 1'b0; i_cdc_fault = 1'b0; i_aborted = 1'b0; i_frame_error = 1'b0;
    i_fft_error = 1'b0; i_overflow = 1'b0; i_dropped_samples = 1'b0;
    i_bank_overrun = 1'b0;
    axi_read(8'h08, 0, read_value);
    require_true(read_value[10:0] == 11'h3ff, "STATUS live/sticky map mismatch");
    axi_write(8'h08, 32'h0000_07ff, 4'b0011, 1, 0);
    axi_read(8'h08, 0, read_value);
    require_true(read_value[10:0] == 11'h005, "STATUS W1C cleared live bits or missed sticky bits");
    require_true((o_status_clear & 11'h3fa) == 0, "W1C clear output was not a pulse");

    // A new sticky event coincident with its W1C write wins over the clear.
    @(negedge s_axi_aclk);
    s_axi_awaddr = 8'h08; s_axi_awvalid = 1'b1;
    s_axi_wdata = 32'h0000_0002; s_axi_wstrb = 4'b0001; s_axi_wvalid = 1'b1;
    while (!s_axi_awready || !s_axi_wready) @(negedge s_axi_aclk);
    @(negedge s_axi_aclk);
    s_axi_awvalid = 1'b0; s_axi_wvalid = 1'b0;
    while (!u_dut.write_commit) @(negedge s_axi_aclk);
    i_done = 1'b1;
    @(negedge s_axi_aclk);
    i_done = 1'b0;
    while (!s_axi_bvalid) @(negedge s_axi_aclk);
    s_axi_bready = 1'b1;
    @(negedge s_axi_aclk);
    s_axi_bready = 1'b0;
    axi_read(8'h08, 0, read_value);
    require_true(read_value[1],
                 "coincident DONE event did not win over STATUS W1C");
    axi_write(8'h08, 32'h0000_0002, 4'b0001, 0, 0);

    // Exact fixed result map.
    axi_read(8'h18, 0, read_value); require_true(read_value == 32'h1234_5678, "FRAME_ID map mismatch");
    axi_read(8'h1c, 0, read_value); require_true(read_value == 32'hbeef_000b, "RESULT_TAG map mismatch");
    axi_read(8'h20, 0, read_value); require_true(read_value == 32'd2048, "SAMPLE_COUNT map mismatch");
    axi_read(8'h24, 0, read_value); require_true(read_value == 32'd137, "PEAK_BIN map mismatch");
    axi_read(8'h28, 0, read_value); require_true(read_value == 32'h89ab_cdef, "PEAK_POWER_LO map mismatch");
    axi_read(8'h2c, 0, read_value); require_true(read_value == 32'h0000_0001, "PEAK_POWER_HI map mismatch");
    axi_read(8'h30, 0, read_value); require_true(read_value == {16'd456, -16'sd123}, "PEAK_RE_IM map mismatch");
    axi_read(8'h34, 0, read_value); require_true(read_value == 32'h1357_2468, "FIRST_SAMPLE map mismatch");
    axi_read(8'h38, 0, read_value); require_true(read_value == 32'hcbf4_3926, "FRAME_CRC32 map mismatch");
    axi_read(8'h3c, 0, read_value); require_true(read_value == 32'hffff_fffe, "DROPPED_COUNT map mismatch");
    axi_read(8'h40, 5, read_value); require_true(read_value == 32'h0000_0003, "BANK_VALID map mismatch");

    // Writes to RO registers return OKAY but cannot alter their values.
    axi_write(8'h00, 32'hffff_ffff, 4'b1111, 0, 0);
    axi_write(8'h18, 32'h0000_0000, 4'b1111, 1, 0);
    axi_read(8'h00, 0, read_value); require_true(read_value == 32'h0001_0000, "VERSION was writable");
    axi_read(8'h18, 0, read_value); require_true(read_value == 32'h1234_5678, "FRAME_ID was writable");

    $display("PASS: fft_regs");
    $finish;
  end
endmodule

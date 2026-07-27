`timescale 1ns/1ps

module tb_spectrum_pingpong;
  localparam integer NFFT = 2048;

  reg pl_clk = 1'b0;
  reg pl_resetn = 1'b0;
  reg mode_continuous = 1'b0;
  reg begin_frame = 1'b0;
  reg abort_frame = 1'b0;
  reg release_bank0 = 1'b0;
  reg release_bank1 = 1'b0;
  reg clear_overrun = 1'b0;
  reg [15:0] reset_epoch = 16'h0100;
  reg epoch_update = 1'b0;
  reg [31:0] frame_id = 32'd0;
  reg [2:0] rf_state = 3'd0;
  reg [10:0] peak_bin_in = 11'd0;
  reg [32:0] peak_power_in = 33'd0;
  reg signed [15:0] peak_re_in = 16'sd0;
  reg signed [15:0] peak_im_in = 16'sd0;
  reg spectrum_tvalid = 1'b0;
  wire spectrum_tready;
  reg [10:0] spectrum_bin = 11'd0;
  reg [63:0] spectrum_tdata = 64'd0;
  reg spectrum_tlast = 1'b0;

  wire frame_active;
  wire frame_accepted;
  wire frame_rejected;
  wire publish;
  wire published_bank;
  wire bank0_valid;
  wire bank1_valid;
  wire bank_overrun;
  wire [31:0] bank0_frame_id;
  wire [31:0] bank1_frame_id;
  wire [2:0] bank0_rf_state;
  wire [2:0] bank1_rf_state;
  wire [15:0] bank0_epoch;
  wire [15:0] bank1_epoch;
  wire [10:0] bank0_peak_bin;
  wire [10:0] bank1_peak_bin;
  wire [32:0] bank0_peak_power;
  wire [32:0] bank1_peak_power;
  wire signed [15:0] bank0_peak_re;
  wire signed [15:0] bank1_peak_re;
  wire signed [15:0] bank0_peak_im;
  wire signed [15:0] bank1_peak_im;

  reg cpu_clk = 1'b0;
  reg cpu_bank_select = 1'b0;
  reg cpu_read_enable = 1'b0;
  reg [10:0] cpu_read_address = 11'd0;
  wire [63:0] cpu_read_data;

  integer index;
  integer publish_count;
  integer accept_count;
  integer reject_count;

  always #5 pl_clk = ~pl_clk;
  always #7 cpu_clk = ~cpu_clk;

  spectrum_pingpong dut (
    .pl_clk(pl_clk), .pl_resetn(pl_resetn),
    .mode_continuous(mode_continuous), .begin_frame(begin_frame),
    .abort_frame(abort_frame), .release_bank0(release_bank0),
    .release_bank1(release_bank1), .clear_overrun(clear_overrun),
    .reset_epoch(reset_epoch),
    .epoch_update(epoch_update), .frame_id(frame_id), .rf_state(rf_state),
    .peak_bin_in(peak_bin_in), .peak_power_in(peak_power_in),
    .peak_re_in(peak_re_in), .peak_im_in(peak_im_in),
    .spectrum_tvalid(spectrum_tvalid), .spectrum_tready(spectrum_tready),
    .spectrum_bin(spectrum_bin), .spectrum_tdata(spectrum_tdata),
    .spectrum_tlast(spectrum_tlast), .frame_active(frame_active),
    .frame_accepted(frame_accepted), .frame_rejected(frame_rejected),
    .publish(publish), .published_bank(published_bank),
    .bank0_valid(bank0_valid), .bank1_valid(bank1_valid),
    .bank_overrun(bank_overrun), .bank0_frame_id(bank0_frame_id),
    .bank1_frame_id(bank1_frame_id), .bank0_rf_state(bank0_rf_state),
    .bank1_rf_state(bank1_rf_state), .bank0_epoch(bank0_epoch),
    .bank1_epoch(bank1_epoch), .bank0_peak_bin(bank0_peak_bin),
    .bank1_peak_bin(bank1_peak_bin), .bank0_peak_power(bank0_peak_power),
    .bank1_peak_power(bank1_peak_power), .bank0_peak_re(bank0_peak_re),
    .bank1_peak_re(bank1_peak_re), .bank0_peak_im(bank0_peak_im),
    .bank1_peak_im(bank1_peak_im), .cpu_clk(cpu_clk),
    .cpu_bank_select(cpu_bank_select), .cpu_read_enable(cpu_read_enable),
    .cpu_read_address(cpu_read_address), .cpu_read_data(cpu_read_data),
    .cpu_bank0_read_enable(1'b0), .cpu_bank0_read_address(11'd0),
    .cpu_bank0_read_data(), .cpu_bank1_read_enable(1'b0),
    .cpu_bank1_read_address(11'd0), .cpu_bank1_read_data()
  );

  task automatic require_true;
    input condition;
    input [8*112-1:0] message;
    begin
      if (condition !== 1'b1) begin
        $display("FAIL: %0s", message);
        $fatal(1);
        $finish;
      end
    end
  endtask

  always @(posedge pl_clk) begin
    if (pl_resetn) begin
      require_true(!$isunknown({spectrum_tready, frame_active, frame_accepted,
                                frame_rejected, publish, published_bank,
                                bank0_valid, bank1_valid, bank_overrun}),
                   "X/Z observed on bank PL interface");
      if (publish) publish_count = publish_count + 1;
      if (frame_accepted) accept_count = accept_count + 1;
      if (frame_rejected) reject_count = reject_count + 1;
    end
  end

  initial begin
    #1000000;
    $display("FAIL: spectrum_pingpong testbench timeout");
    $fatal(1);
  end

  function automatic [63:0] spectrum_word;
    input [31:0] id;
    input integer bin;
    begin
      spectrum_word = {id[15:0], 5'd0, bin[10:0], id[20:0], bin[10:0]};
    end
  endfunction

  task automatic pulse_begin;
    input [31:0] id;
    input [2:0] state;
    begin
      @(negedge pl_clk);
      frame_id = id;
      rf_state = state;
      peak_bin_in = id[10:0];
      peak_power_in = {1'b0, id};
      peak_re_in = id[15:0];
      peak_im_in = -$signed(id[15:0]);
      begin_frame = 1'b1;
      @(negedge pl_clk);
      begin_frame = 1'b0;
      // Allow the persistent pre-NBA event monitor to observe the pulse.
      @(posedge pl_clk); #1;
    end
  endtask

  task automatic pulse_abort;
    begin
      @(negedge pl_clk); abort_frame = 1'b1;
      @(negedge pl_clk); abort_frame = 1'b0;
    end
  endtask

  task automatic pulse_release;
    input bank;
    begin
      @(negedge pl_clk);
      release_bank0 = !bank;
      release_bank1 = bank;
      @(negedge pl_clk);
      release_bank0 = 1'b0;
      release_bank1 = 1'b0;
    end
  endtask

  task automatic send_bins;
    input [31:0] id;
    input integer count;
    begin
      for (index = 0; index < count; index = index + 1) begin
        @(negedge pl_clk);
        spectrum_tvalid = 1'b1;
        spectrum_bin = index[10:0];
        spectrum_tdata = spectrum_word(id, index);
        spectrum_tlast = (index == NFFT-1);
        while (!spectrum_tready) @(negedge pl_clk);
      end
      @(negedge pl_clk);
      spectrum_tvalid = 1'b0;
      spectrum_tlast = 1'b0;
    end
  endtask

  task automatic cpu_read_check;
    input bank;
    input [10:0] address;
    input [63:0] expected;
    begin
      @(negedge cpu_clk);
      cpu_bank_select = bank;
      cpu_read_address = address;
      cpu_read_enable = 1'b1;
      @(posedge cpu_clk); #1;
      require_true(!$isunknown(cpu_read_data), "X/Z observed on CPU read data");
      require_true(cpu_read_data === expected, "independent-clock bank read mismatch");
      @(negedge cpu_clk);
      cpu_read_enable = 1'b0;
    end
  endtask

  initial begin
    publish_count = 0;
    accept_count = 0;
    reject_count = 0;
    repeat (5) @(posedge pl_clk);
    pl_resetn = 1'b1;
    repeat (2) @(posedge pl_clk);

    // Single-shot always owns bank 0 and is invisible until accepted bin 2047/last.
    mode_continuous = 1'b0;
    pulse_begin(32'h1001, 3'd1);
    require_true(frame_active && accept_count == 1, "single frame not accepted");
    send_bins(32'h1001, NFFT-1);
    require_true(!bank0_valid && !bank1_valid && publish_count == 0,
                 "partial frame became visible");
    @(negedge pl_clk);
    spectrum_tvalid = 1'b1;
    spectrum_bin = 11'd2047;
    spectrum_tdata = spectrum_word(32'h1001, 2047);
    spectrum_tlast = 1'b1;
    @(negedge pl_clk);
    spectrum_tvalid = 1'b0;
    spectrum_tlast = 1'b0;
    @(posedge pl_clk); #1;
    require_true(bank0_valid && !bank1_valid && publish_count == 1,
                 "single frame did not publish bank 0 atomically");
    require_true(bank0_frame_id == 32'h1001 && bank0_rf_state == 3'd1 &&
                 bank0_epoch == 16'h0100 && bank0_peak_bin == 11'h001 &&
                 bank0_peak_power == 33'h000001001,
                 "bank 0 metadata mismatch");
    // Read the complete first bank through the unrelated CPU clock so a
    // missing/interleaved PL write cannot hide behind spot checks.
    for (index = 0; index < NFFT; index = index + 1)
      cpu_read_check(1'b0, index[10:0], spectrum_word(32'h1001, index));

    // In single mode bank 0 is the only legal target. Releasing it in the
    // same PL cycle as begin must make it immediately available.
    index = accept_count;
    @(negedge pl_clk);
    frame_id = 32'h1111;
    rf_state = 3'd1;
    release_bank0 = 1'b1;
    begin_frame = 1'b1;
    @(negedge pl_clk);
    release_bank0 = 1'b0;
    begin_frame = 1'b0;
    @(posedge pl_clk); #1;
    require_true(frame_active && accept_count == index + 1 && !bank_overrun,
                 "same-cycle release+begin rejected the only legal bank");
    pulse_abort();

    // Continuous alternates when free, preserves unread banks, then overruns.
    require_true(!bank0_valid, "bank 0 release failed");
    mode_continuous = 1'b1;
    pulse_begin(32'h2002, 3'd2);
    send_bins(32'h2002, NFFT);
    @(posedge pl_clk); #1;
    require_true(bank1_valid && published_bank == 1'b1,
                 "continuous mode did not alternate to bank 1");
    pulse_begin(32'h3003, 3'd3);
    send_bins(32'h3003, NFFT);
    @(posedge pl_clk); #1;
    require_true(bank0_valid && bank1_valid && published_bank == 1'b0,
                 "continuous mode did not alternate back to bank 0");
    cpu_read_check(1'b1, 11'd137, spectrum_word(32'h2002, 137));
    cpu_read_check(1'b0, 11'd137, spectrum_word(32'h3003, 137));

    pulse_begin(32'h4004, 3'd4);
    require_true(!frame_active && reject_count == 1 && bank_overrun,
                 "full-bank request was not rejected with sticky overrun");
    require_true(bank0_frame_id == 32'h3003 && bank1_frame_id == 32'h2002,
                 "overrun corrupted unread metadata");

    // W1C pulse clears sticky state and it stays clear without a new event.
    @(negedge pl_clk); clear_overrun = 1'b1;
    @(negedge pl_clk); clear_overrun = 1'b0;
    require_true(!bank_overrun, "clear_overrun did not clear sticky status");
    repeat (3) begin
      @(posedge pl_clk); #1;
      require_true(!bank_overrun, "overrun reasserted without a collision");
    end

    // A new collision wins over a simultaneous W1C clear pulse.
    @(negedge pl_clk);
    clear_overrun = 1'b1;
    begin_frame = 1'b1;
    frame_id = 32'h4444;
    @(negedge pl_clk);
    clear_overrun = 1'b0;
    begin_frame = 1'b0;
    @(posedge pl_clk); #1;
    require_true(bank_overrun, "new collision did not win over clear_overrun");

    // Releasing one bank permits a frame, but abort never publishes it.
    pulse_release(1'b1);
    pulse_begin(32'h5005, 3'd5);
    require_true(frame_active, "released bank was not reusable");
    send_bins(32'h5005, 17);
    pulse_abort();
    require_true(!frame_active && !bank1_valid && publish_count == 3,
                 "aborted partial frame was published");
    require_true(bank0_valid && bank0_frame_id == 32'h3003,
                 "abort changed other unread bank");

    // Epoch change is an atomic invalidation/reset for banks and partial frame.
    pulse_begin(32'h6006, 3'd6);
    send_bins(32'h6006, 9);
    @(negedge pl_clk);
    reset_epoch = 16'h0101;
    epoch_update = 1'b1;
    @(negedge pl_clk);
    epoch_update = 1'b0;
    require_true(!frame_active && !bank0_valid && !bank1_valid && !bank_overrun,
                 "epoch update did not invalidate banks/partial frame/status");

    // A last word at bin 2047 is insufficient without all preceding bins.
    pulse_begin(32'h7007, 3'd7);
    @(negedge pl_clk);
    spectrum_tvalid = 1'b1;
    spectrum_bin = 11'd2047;
    spectrum_tdata = spectrum_word(32'h7007, 2047);
    spectrum_tlast = 1'b1;
    @(negedge pl_clk);
    spectrum_tvalid = 1'b0;
    spectrum_tlast = 1'b0;
    @(posedge pl_clk); #1;
    require_true(!frame_active && !bank0_valid && !bank1_valid,
                 "sparse frame published without all 2048 bins");

    // Reset invalidates any diagnostic state before the precedence test.
    @(negedge pl_clk); epoch_update = 1'b1;
    @(negedge pl_clk); epoch_update = 1'b0;

    // Abort must win even when it coincides with an otherwise valid last word.
    pulse_begin(32'h8008, 3'd0);
    send_bins(32'h8008, NFFT-1);
    @(negedge pl_clk);
    abort_frame = 1'b1;
    spectrum_tvalid = 1'b1;
    spectrum_bin = 11'd2047;
    spectrum_tdata = spectrum_word(32'h8008, 2047);
    spectrum_tlast = 1'b1;
    @(negedge pl_clk);
    abort_frame = 1'b0;
    spectrum_tvalid = 1'b0;
    spectrum_tlast = 1'b0;
    @(posedge pl_clk); #1;
    require_true(!frame_active && !bank0_valid && !bank1_valid,
                 "abort coincident with last word published a frame");

    // Malformed early last must not publish.
    pulse_begin(32'h9009, 3'd1);
    @(negedge pl_clk);
    spectrum_tvalid = 1'b1;
    spectrum_bin = 11'd12;
    spectrum_tdata = spectrum_word(32'h9009, 12);
    spectrum_tlast = 1'b1;
    @(negedge pl_clk);
    spectrum_tvalid = 1'b0;
    spectrum_tlast = 1'b0;
    @(posedge pl_clk); #1;
    require_true(!frame_active && !bank0_valid && !bank1_valid,
                 "malformed last published or left frame active");

    $display("PASS: spectrum_pingpong");
    $finish;
  end
endmodule

`timescale 1ns/1ps

module tb_magnitude_peak;
  localparam integer NFFT = 2048;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg start = 1'b0;
  reg [10:0] search_start = 11'd0;
  reg [10:0] search_stop = 11'd2047;
  reg [10:0] dc_guard = 11'd0;
  reg [31:0] s_axis_tdata = 32'd0;
  reg s_axis_tvalid = 1'b0;
  wire s_axis_tready;
  reg s_axis_tlast = 1'b0;
  wire [63:0] m_axis_tdata;
  wire [10:0] m_axis_bin;
  wire m_axis_tvalid;
  reg m_axis_tready = 1'b0;
  wire m_axis_tlast;
  wire peak_valid;
  wire [10:0] peak_bin;
  wire [32:0] peak_power;
  wire signed [15:0] peak_re;
  wire signed [15:0] peak_im;

  reg [31:0] fft_words [0:NFFT-1];
  reg [63:0] power_words [0:NFFT-1];
  integer tx_index;
  integer rx_index;
  integer cycles;
  integer peak_pulses;
  integer input_accept_count;
  integer transfer_count;
  integer peak_event_count;
  reg vector_check_enable;
  reg [63:0] last_transfer_data;
  reg [10:0] last_transfer_bin;
  reg last_transfer_last;
  reg [10:0] latched_peak_bin;
  reg [32:0] latched_peak_power;
  reg signed [15:0] latched_peak_re;
  reg signed [15:0] latched_peak_im;
  reg [15:0] lfsr;
  reg held;
  reg [63:0] held_data;
  reg [10:0] held_bin;
  reg held_last;

  always #5 clk = ~clk;

  initial begin
    #500000;
    $display("FAIL: magnitude_peak testbench timeout");
    $fatal(1);
  end

  // Sample handshakes before DUT nonblocking assignments update the channel.
  // Tests wait on these persistent counters rather than transient valid pulses.
  always @(posedge clk) begin
    if (!resetn) begin
      input_accept_count = 0;
      transfer_count = 0;
      peak_event_count = 0;
    end else begin
      if (s_axis_tvalid && s_axis_tready)
        input_accept_count = input_accept_count + 1;
      if (m_axis_tvalid && m_axis_tready) begin
        last_transfer_data = m_axis_tdata;
        last_transfer_bin = m_axis_bin;
        last_transfer_last = m_axis_tlast;
        if (vector_check_enable) begin
          require_true(m_axis_bin == transfer_count[10:0], "natural bin sequence mismatch");
          require_true(m_axis_tdata === power_words[transfer_count], "33-bit power mismatch");
          require_true(m_axis_tlast == (transfer_count == NFFT-1), "output last position mismatch");
        end
        transfer_count = transfer_count + 1;
      end
      if (peak_valid) begin
        latched_peak_bin = peak_bin;
        latched_peak_power = peak_power;
        latched_peak_re = peak_re;
        latched_peak_im = peak_im;
        peak_event_count = peak_event_count + 1;
      end
    end
  end

  magnitude_peak dut (
    .clk(clk), .resetn(resetn), .start(start),
    .search_start(search_start), .search_stop(search_stop), .dc_guard(dc_guard),
    .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_bin(m_axis_bin),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast), .peak_valid(peak_valid),
    .peak_bin(peak_bin), .peak_power(peak_power),
    .peak_re(peak_re), .peak_im(peak_im)
  );

  task automatic require_true;
    input condition;
    input [8*112-1:0] message;
    begin
      if (condition !== 1'b1) begin
        $display("FAIL: %0s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk); start = 1'b1;
      @(negedge clk); start = 1'b0;
    end
  endtask

  task automatic send_word;
    input [31:0] word_value;
    input last_value;
    begin
      @(negedge clk);
      s_axis_tdata = word_value;
      s_axis_tlast = last_value;
      s_axis_tvalid = 1'b1;
      while (!s_axis_tready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;
    end
  endtask

  task automatic run_vector;
    begin
      $display("TRACE: magnitude vector start t=%0t", $time);
      pulse_start();
      tx_index = 0;
      rx_index = 0;
      cycles = 0;
      peak_pulses = 0;
      input_accept_count = 0;
      transfer_count = 0;
      peak_event_count = 0;
      vector_check_enable = 1'b1;
      lfsr = 16'hA53C;
      held = 1'b0;
      while (rx_index < NFFT) begin
        @(negedge clk);
        if (held) begin
          require_true(m_axis_tvalid, "output valid dropped under stall");
          require_true(m_axis_tdata === held_data, "output power changed under stall");
          require_true(m_axis_bin === held_bin, "output bin changed under stall");
          require_true(m_axis_tlast === held_last, "output last changed under stall");
        end
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        m_axis_tready = lfsr[0] | lfsr[4];
        if (input_accept_count < NFFT) begin
          s_axis_tvalid = 1'b1;
          s_axis_tdata = fft_words[input_accept_count];
          s_axis_tlast = (input_accept_count == NFFT-1);
        end else begin
          s_axis_tvalid = 1'b0;
          s_axis_tlast = 1'b0;
        end
        @(posedge clk);
        #1;
        require_true(!$isunknown({s_axis_tready, m_axis_tvalid, m_axis_tdata,
                                  m_axis_bin, m_axis_tlast, peak_valid}),
                     "X/Z observed on magnitude interface");
        tx_index = input_accept_count;
        rx_index = transfer_count;
        peak_pulses = peak_event_count;
        held = m_axis_tvalid && !m_axis_tready;
        held_data = m_axis_tdata;
        held_bin = m_axis_bin;
        held_last = m_axis_tlast;
        cycles = cycles + 1;
        require_true(cycles < 20000, "vector test timed out");
      end
      repeat (2) begin
        @(posedge clk); #1;
        peak_pulses = peak_event_count;
      end
      vector_check_enable = 1'b0;
      require_true(peak_pulses == 1, "peak_valid must pulse exactly once");
      require_true(latched_peak_bin == 11'd137, "golden tone peak bin mismatch");
      require_true(latched_peak_power == 33'd4194304, "golden tone peak power mismatch");
      require_true(latched_peak_re == 16'sd2048 && latched_peak_im == 16'sd0,
                   "golden tone peak complex value mismatch");
      $display("TRACE: magnitude vector done t=%0t", $time);
    end
  endtask

  initial begin
    $readmemh("tone_bin_137.fft.hex", fft_words);
    $readmemh("tone_bin_137.power.hex", power_words);
    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);
    run_vector();

    // Exact signed corner: (-32768)^2 + (-32768)^2 = 2^31.
    $display("TRACE: signed corner start t=%0t", $time);
    search_start = 11'd0;
    search_stop = 11'd0;
    dc_guard = 11'd1; // Bin zero is excluded even when it is inside search.
    m_axis_tready = 1'b1;
    transfer_count = 0;
    peak_event_count = 0;
    pulse_start();
    send_word({16'h8000, 16'h8000}, 1'b1);
    cycles = 0;
    while ((transfer_count < 1 || peak_event_count < 1) && cycles < 20) begin
      @(posedge clk); #1; cycles = cycles + 1;
    end
    require_true(transfer_count == 1 && peak_event_count == 1, "signed corner events missing");
    require_true(last_transfer_data == 64'h0000000080000000, "signed -32768 power is not exact");
    require_true(latched_peak_power == 33'd0, "DC guard did not exclude bin zero");
    $display("TRACE: signed corner done t=%0t", $time);

    // Inclusive range and lower-bin tie. Bins 1 and 2 tie; bin 1 must win.
    $display("TRACE: tie test start t=%0t", $time);
    search_start = 11'd1;
    search_stop = 11'd2;
    dc_guard = 11'd0;
    peak_event_count = 0;
    pulse_start();
    send_word({16'sd0, 16'sd3}, 1'b0); // bin 0, excluded by range and guard
    send_word({16'sd0, 16'sd7}, 1'b0); // bin 1, power 49
    send_word({16'sd0, -16'sd7}, 1'b1); // bin 2, equal power
    cycles = 0;
    while (peak_event_count < 1 && cycles < 20) begin
      @(posedge clk); #1; cycles = cycles + 1;
    end
    require_true(peak_event_count == 1, "tie-test peak event missing");
    require_true(latched_peak_bin == 11'd1 && latched_peak_power == 33'd49,
                 "inclusive search or lower-bin tie rule failed");
    require_true(latched_peak_re == 16'sd7 && latched_peak_im == 16'sd0,
                 "winning peak complex sample was not retained");
    $display("TRACE: tie test done t=%0t", $time);

    // Configuration is a frame command: later bus changes and a start while
    // active must not alter the accepted frame or reset its natural bin index.
    search_start = 11'd2;
    search_stop = 11'd2;
    dc_guard = 11'd0;
    peak_event_count = 0;
    pulse_start();
    send_word({16'sd0, 16'sd1}, 1'b0); // bin 0
    search_start = 11'd1;
    search_stop = 11'd1;
    pulse_start(); // ignored while active
    send_word({16'sd0, 16'sd10}, 1'b0); // bin 1, excluded by latched range
    send_word({16'sd0, 16'sd2}, 1'b1);  // bin 2, sole eligible bin
    cycles = 0;
    while (peak_event_count < 1 && cycles < 20) begin
      @(posedge clk); #1; cycles = cycles + 1;
    end
    require_true(peak_event_count == 1 && latched_peak_bin == 11'd2 &&
                 latched_peak_power == 33'd4,
                 "frame config was not latched or busy start reset the frame");

    // A completed frame still owns the output stage until its final handshake.
    // A new start during that stall must neither overwrite peak metadata nor
    // replace the held spectrum word.
    search_start = 11'd0;
    search_stop = 11'd1;
    dc_guard = 11'd0;
    m_axis_tready = 1'b1;
    pulse_start();
    send_word({16'sd0, 16'sd1}, 1'b0);
    repeat (2) @(posedge clk);
    m_axis_tready = 1'b0;
    send_word({16'sd4, 16'sd3}, 1'b1);
    require_true(m_axis_tvalid && m_axis_tlast, "final word was not held for stall test");
    require_true(peak_power == 33'd25 && peak_bin == 11'd1,
                 "stalled-frame peak baseline mismatch");
    held_data = m_axis_tdata;
    pulse_start();
    require_true(m_axis_tvalid && m_axis_tlast && m_axis_tdata === held_data,
                 "start changed a stalled final AXIS payload");
    require_true(peak_power == 33'd25 && peak_bin == 11'd1,
                 "start cleared peak metadata before final output handshake");
    m_axis_tready = 1'b1;
    @(posedge clk); #1;

    // Wrapped DC guard excludes bins [0,2] and [2046,2047].
    $display("TRACE: wrapped guard start t=%0t", $time);
    search_start = 11'd2045;
    search_stop = 11'd2047;
    dc_guard = 11'd2;
    peak_event_count = 0;
    pulse_start();
    for (tx_index = 0; tx_index < NFFT; tx_index = tx_index + 1)
      send_word({16'sd0, (tx_index == 2045) ? 16'sd4 : 16'sd20}, tx_index == NFFT-1);
    cycles = 0;
    while (peak_event_count < 1 && cycles < 20) begin
      @(posedge clk); #1; cycles = cycles + 1;
    end
    require_true(peak_event_count == 1, "wrapped-guard peak event missing");
    require_true(latched_peak_bin == 11'd2045 && latched_peak_power == 33'd16,
                 "wrapped DC guard failed at upper natural bins");
    $display("TRACE: wrapped guard done t=%0t", $time);

    $display("PASS: magnitude_peak");
    $finish;
  end
endmodule

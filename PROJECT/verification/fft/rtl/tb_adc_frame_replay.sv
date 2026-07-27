`timescale 1ns/1ps

module tb_adc_frame_replay;

  localparam integer FRAME_LENGTH = 2048;

  reg         adc_clk = 1'b0;
  reg         adc_resetn = 1'b0;
  reg         start = 1'b0;
  reg         frame_available = 1'b0;
  wire [10:0] mem_rd_addr;
  reg  [31:0] mem_rd_data = 32'd0;
  wire [31:0] m_axis_tdata;
  wire        m_axis_tvalid;
  reg         m_axis_tready = 1'b0;
  wire        m_axis_tlast;
  wire        busy;
  wire        done;

  reg [31:0] memory [0:FRAME_LENGTH-1];
  integer index;
  integer received;
  integer tlast_count;
  integer cycles;
  integer final_stall_cycles;
  reg [15:0] lfsr;
  reg [31:0] held_data;
  reg        held_last;
  reg        was_stalled;
  reg [31:0] transfer_data;
  reg        transfer_valid;
  reg        transfer_last;
  reg        transfer_ready;

  always #5 adc_clk = ~adc_clk;

  always @(posedge adc_clk)
    mem_rd_data <= memory[mem_rd_addr];

  adc_frame_replay dut (
    .adc_clk(adc_clk),
    .adc_resetn(adc_resetn),
    .start(start),
    .frame_available(frame_available),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_data(mem_rd_data),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .busy(busy),
    .done(done)
  );

  function automatic [31:0] sample_word;
    input integer sample_number;
    begin
      sample_word = {16'h8000 ^ sample_number[15:0], 16'h2000 + sample_number[15:0]};
    end
  endfunction

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

  task automatic pulse_start;
    begin
      @(negedge adc_clk);
      start = 1'b1;
      @(posedge adc_clk);
      #1;
      @(negedge adc_clk);
      start = 1'b0;
    end
  endtask

  initial begin
    for (index = 0; index < FRAME_LENGTH; index = index + 1)
      memory[index] = sample_word(index);

    repeat (4) @(posedge adc_clk);
    adc_resetn = 1'b1;
    repeat (2) @(posedge adc_clk);

    // A replay request without a completed capture must be ignored.
    pulse_start();
    repeat (3) @(posedge adc_clk);
    #1 require_true(!busy && !m_axis_tvalid, "replay began without frame_available");

    frame_available = 1'b1;
    pulse_start();
    require_true(busy, "replay did not accept start");

    received = 0;
    tlast_count = 0;
    cycles = 0;
    final_stall_cycles = 0;
    lfsr = 16'h1ACE;
    was_stalled = 1'b0;

    while (received < FRAME_LENGTH) begin
      @(negedge adc_clk);
      if (was_stalled) begin
        require_true(m_axis_tvalid, "tvalid dropped while stalled");
        require_true(m_axis_tdata == held_data, "tdata changed while stalled");
        require_true(m_axis_tlast == held_last, "tlast changed while stalled");
      end

      lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
      if (received == FRAME_LENGTH-1 && m_axis_tvalid && final_stall_cycles < 2) begin
        m_axis_tready = 1'b0;
        final_stall_cycles = final_stall_cycles + 1;
      end else begin
        m_axis_tready = lfsr[0] | lfsr[3];
      end

      // A start request while the final word is stalled must not restart the
      // stream or change the held AXI payload.
      start = (received == FRAME_LENGTH-1 && m_axis_tvalid && !m_axis_tready);

      transfer_valid = m_axis_tvalid;
      transfer_ready = m_axis_tready;
      transfer_data = m_axis_tdata;
      transfer_last = m_axis_tlast;

      @(posedge adc_clk);
      #1;
      cycles = cycles + 1;

      if (transfer_valid && transfer_ready) begin
        require_true(transfer_data == sample_word(received), "replay word order/data mismatch");
        require_true(transfer_last == (received == FRAME_LENGTH-1), "tlast position mismatch");
        if (transfer_last)
          tlast_count = tlast_count + 1;
        received = received + 1;
      end

      was_stalled = transfer_valid && !transfer_ready;
      held_data = transfer_data;
      held_last = transfer_last;
      require_true(cycles < 20000, "replay timed out");
    end

    require_true(!busy && done && !m_axis_tvalid, "final handshake did not complete replay");
    require_true(tlast_count == 1, "replay emitted other than one tlast");
    require_true(final_stall_cycles == 2, "final-word busy/start collision was not exercised");
    @(negedge adc_clk);
    start = 1'b0;
    m_axis_tready = 1'b1;
    @(posedge adc_clk);
    #1;
    require_true(!done, "done must be a one-cycle indication");

    // A new replay is accepted only after the prior final handshake.
    pulse_start();
    require_true(busy, "new replay was not accepted after completion");
    while (!m_axis_tvalid) begin
      @(posedge adc_clk);
      #1;
    end
    require_true(m_axis_tdata == sample_word(0), "second replay did not restart at word 0");

    $display("PASS: adc_frame_replay");
    $finish;
  end

endmodule

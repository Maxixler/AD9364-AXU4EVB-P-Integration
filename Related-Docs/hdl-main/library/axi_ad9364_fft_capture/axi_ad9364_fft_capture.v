`timescale 1ns/1ps

module axi_ad9364_fft_capture #(
  // This model parameter is the IP-XACT source for both BRAM-port
  // MEM_WIDTH bus parameters. The AXU4EV integration fixes it at 64 bits.
  parameter integer SPECTRUM_BANK_DATA_WIDTH = 64
) (
  input  wire        s_axi_aclk,
  input  wire        s_axi_aresetn,
  input  wire [7:0]  s_axi_awaddr,
  input  wire [2:0]  s_axi_awprot,
  input  wire        s_axi_awvalid,
  output wire        s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output wire        s_axi_wready,
  output wire [1:0]  s_axi_bresp,
  output wire        s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [7:0]  s_axi_araddr,
  input  wire [2:0]  s_axi_arprot,
  input  wire        s_axi_arvalid,
  output wire        s_axi_arready,
  output wire [31:0] s_axi_rdata,
  output wire [1:0]  s_axi_rresp,
  output wire        s_axi_rvalid,
  input  wire        s_axi_rready,

  input  wire        adc_clk,
  input  wire        adc_resetn,
  input  wire        adc_valid,
  input  wire        adc_enable,
  input  wire [15:0] adc_i,
  input  wire [15:0] adc_q,
  input  wire [2:0]  rf_state,

  input  wire        bank0_bram_en,
  // AXI BRAM Controller addresses are byte addresses. The 2K x 64-bit
  // spectrum banks consume 16 KiB, so bits [13:3] select the stored word.
  // AXI4 controller transactions for this read-only aperture are 64-bit
  // aligned; low address bits are intentionally not used by the RAM index.
  input  wire [13:0] bank0_bram_addr,
  output wire [SPECTRUM_BANK_DATA_WIDTH-1:0] bank0_bram_rddata,
  input  wire        bank1_bram_en,
  input  wire [13:0] bank1_bram_addr,
  output wire [SPECTRUM_BANK_DATA_WIDTH-1:0] bank1_bram_rddata,
  output wire        irq
);

  localparam integer COMMAND_WIDTH = 59;
  localparam integer RESULT_WIDTH = 264;
  localparam [2:0] PIPE_IDLE = 3'd0;
  localparam [2:0] PIPE_CAPTURE = 3'd1;
  localparam [2:0] PIPE_RESERVE = 3'd2;
  localparam [2:0] PIPE_PROCESS = 3'd3;
  localparam [2:0] PIPE_RECOVER = 3'd4;

  wire reg_start, reg_abort, reg_soft_reset, reg_mode_continuous;
  wire reg_bank0_release, reg_bank1_release;
  wire [10:0] reg_search_start, reg_search_stop, reg_dc_guard;
  wire [1:0] reg_window_select;
  wire [2:0] reg_rf_state;
  wire [15:0] reg_reset_epoch;
  wire [10:0] reg_status_clear;
  wire command_ready, command_busy;
  wire command_valid_cpu = reg_start || reg_abort || reg_soft_reset ||
                           reg_bank0_release || reg_bank1_release ||
                           reg_status_clear[9];
  wire [COMMAND_WIDTH-1:0] command_payload_cpu = {
    reg_reset_epoch, reg_rf_state, reg_dc_guard, reg_search_stop,
    reg_search_start, reg_status_clear[9], reg_bank1_release, reg_bank0_release,
    reg_mode_continuous, reg_soft_reset, reg_abort, reg_start};

  wire command_valid_adc, command_epoch_fault_adc;
  wire [COMMAND_WIDTH-1:0] command_payload_adc;
  wire cmd_start = command_payload_adc[0];
  wire cmd_abort = command_payload_adc[1];
  wire cmd_soft_reset = command_payload_adc[2];
  wire cmd_mode_continuous = command_payload_adc[3];
  wire cmd_release0 = command_payload_adc[4];
  wire cmd_release1 = command_payload_adc[5];
  wire cmd_clear_overrun = command_payload_adc[6];
  wire [10:0] cmd_search_start = command_payload_adc[17:7];
  wire [10:0] cmd_search_stop = command_payload_adc[28:18];
  wire [10:0] cmd_dc_guard = command_payload_adc[39:29];
  wire [2:0] cmd_rf_state = command_payload_adc[42:40];
  wire [15:0] cmd_epoch = command_payload_adc[58:43];

  (* ASYNC_REG = "TRUE" *) reg configured_sync1_cpu, configured_sync2_cpu;
  (* ASYNC_REG = "TRUE" *) reg busy_sync1_cpu, busy_sync2_cpu;

  wire capture_busy, capture_frame_ready, capture_aborted;
  wire [31:0] capture_first_sample, capture_crc, capture_dropped_count;
  wire [11:0] capture_sample_count;
  wire [2:0] capture_rf_state;
  wire [31:0] capture_mem_data;
  wire [10:0] capture_mem_addr;
  reg capture_start, capture_abort;

  wire [31:0] replay_data;
  wire replay_valid, replay_ready, replay_last, replay_busy, replay_done;
  reg replay_start;

  reg fft_config_valid;
  reg fft_configured;
  wire fft_config_ready;
  wire [31:0] fft_data;
  wire fft_valid, fft_ready, fft_last;
  wire [7:0] fft_user;
  wire fft_event_started, fft_event_tlast_unexpected, fft_event_tlast_missing;
  wire fft_event_status_halt, fft_event_input_halt, fft_event_output_halt;

  wire [63:0] magnitude_data;
  wire [10:0] magnitude_bin;
  wire magnitude_valid, magnitude_ready, magnitude_last;
  wire peak_valid;
  wire [10:0] peak_bin;
  wire [32:0] peak_power;
  wire signed [15:0] peak_re, peak_im;
  reg magnitude_start;

  reg bank_begin_frame, bank_abort_frame;
  wire bank_frame_active, bank_frame_accepted, bank_frame_rejected;
  wire bank_publish, bank_published;
  wire bank0_valid_adc, bank1_valid_adc, bank_overrun_adc;
  wire [31:0] bank0_frame_id, bank1_frame_id;
  wire [2:0] bank0_rf_state, bank1_rf_state;
  wire [15:0] bank0_epoch, bank1_epoch;
  wire [10:0] bank0_peak_bin, bank1_peak_bin;
  wire [32:0] bank0_peak_power, bank1_peak_power;
  wire signed [15:0] bank0_peak_re, bank1_peak_re;
  wire signed [15:0] bank0_peak_im, bank1_peak_im;
  wire [63:0] legacy_bank_data;
  wire [10:0] bank0_bram_word_addr = bank0_bram_addr[13:3];
  wire [10:0] bank1_bram_word_addr = bank1_bram_addr[13:3];

  reg [2:0] pipeline_state;
  reg [10:0] active_search_start, active_search_stop, active_dc_guard;
  reg [15:0] active_epoch;
  reg [2:0] active_command_rf_state;
  reg active_mode_continuous;
  reg [31:0] adc_frame_id;
  reg fft_error_adc, fft_overflow_adc;
  reg [31:0] dropped_count_at_start;
  reg [1:0] datapath_reset_count;
  wire datapath_reset = |datapath_reset_count;
  wire datapath_resetn = adc_resetn && !datapath_reset;

  wire result_ready_adc, result_busy_adc;
  reg result_valid_adc;
  reg [15:0] result_epoch_adc;
  reg [RESULT_WIDTH-1:0] result_payload_adc;
  wire result_valid_cpu, result_epoch_fault_cpu;
  wire [RESULT_WIDTH-1:0] result_payload_cpu;

  reg [31:0] cpu_frame_id, cpu_sample_count, cpu_first_sample;
  reg [31:0] cpu_crc, cpu_dropped_count;
  reg cpu_active_bank;
  reg [2:0] cpu_result_rf_state;
  reg [15:0] cpu_result_epoch;
  reg [10:0] cpu_peak_bin;
  reg [32:0] cpu_peak_power;
  reg signed [15:0] cpu_peak_re, cpu_peak_im;
  reg [1:0] cpu_bank_valid;
  reg done_cpu;
  reg cdc_fault_cpu, aborted_cpu, frame_error_cpu, fft_error_cpu;
  reg overflow_cpu, dropped_samples_cpu, bank_overrun_cpu;
  wire status_irq;

  wire pipeline_busy_adc = (pipeline_state != PIPE_IDLE) || result_busy_adc;
  wire cdc_ready_cpu = command_ready && configured_sync2_cpu;

  always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      configured_sync1_cpu <= 1'b0;
      configured_sync2_cpu <= 1'b0;
      busy_sync1_cpu <= 1'b0;
      busy_sync2_cpu <= 1'b0;
    end else begin
      configured_sync1_cpu <= fft_configured;
      configured_sync2_cpu <= configured_sync1_cpu;
      busy_sync1_cpu <= pipeline_busy_adc;
      busy_sync2_cpu <= busy_sync1_cpu;
    end
  end

  fft_command_cdc #(
    .PAYLOAD_WIDTH(COMMAND_WIDTH), .DEST_EPOCH_CHECK(0)
  ) i_command_cdc (
    .cpu_clk(s_axi_aclk), .cpu_resetn(s_axi_aresetn),
    .i_cpu_epoch(reg_reset_epoch), .i_cpu_valid(command_valid_cpu),
    .i_cpu_payload(command_payload_cpu), .o_cpu_ready(command_ready),
    .o_cpu_busy(command_busy), .adc_clk(adc_clk), .adc_resetn(adc_resetn),
    .i_adc_epoch(active_epoch), .o_adc_valid(command_valid_adc),
    .o_adc_payload(command_payload_adc),
    .o_adc_epoch_fault(command_epoch_fault_adc));

  adc_frame_capture i_capture (
    .adc_clk(adc_clk), .adc_resetn(adc_resetn), .start(capture_start),
    .abort(capture_abort), .adc_valid(adc_valid), .adc_enable(adc_enable),
    .adc_i(adc_i), .adc_q(adc_q), .rf_state(rf_state),
    .busy(capture_busy), .frame_ready(capture_frame_ready),
    .aborted(capture_aborted), .first_sample(capture_first_sample),
    .sample_count(capture_sample_count), .frame_crc32(capture_crc),
    .dropped_count(capture_dropped_count), .frame_rf_state(capture_rf_state),
    .mem_rd_addr(capture_mem_addr), .mem_rd_data(capture_mem_data));

  adc_frame_replay i_replay (
    .adc_clk(adc_clk), .adc_resetn(datapath_resetn), .start(replay_start),
    .frame_available(capture_frame_ready), .mem_rd_addr(capture_mem_addr),
    .mem_rd_data(capture_mem_data), .m_axis_tdata(replay_data),
    .m_axis_tvalid(replay_valid), .m_axis_tready(replay_ready),
    .m_axis_tlast(replay_last), .busy(replay_busy), .done(replay_done));

  ad9364_fft_2048 i_fft (
    .aclk(adc_clk), .aresetn(datapath_resetn),
    .s_axis_config_tdata(16'h0D57),
    .s_axis_config_tvalid(fft_config_valid),
    .s_axis_config_tready(fft_config_ready),
    .s_axis_data_tdata(replay_data), .s_axis_data_tvalid(replay_valid),
    .s_axis_data_tready(replay_ready), .s_axis_data_tlast(replay_last),
    .m_axis_data_tdata(fft_data), .m_axis_data_tvalid(fft_valid),
    .m_axis_data_tready(fft_ready), .m_axis_data_tlast(fft_last),
    .m_axis_data_tuser(fft_user),
    .event_frame_started(fft_event_started),
    .event_tlast_unexpected(fft_event_tlast_unexpected),
    .event_tlast_missing(fft_event_tlast_missing),
    .event_status_channel_halt(fft_event_status_halt),
    .event_data_in_channel_halt(fft_event_input_halt),
    .event_data_out_channel_halt(fft_event_output_halt));

  magnitude_peak i_magnitude (
    .clk(adc_clk), .resetn(datapath_resetn), .start(magnitude_start),
    .search_start(active_search_start), .search_stop(active_search_stop),
    .dc_guard(active_dc_guard), .s_axis_tdata(fft_data),
    .s_axis_tvalid(fft_valid), .s_axis_tready(fft_ready),
    .s_axis_tlast(fft_last), .m_axis_tdata(magnitude_data),
    .m_axis_bin(magnitude_bin), .m_axis_tvalid(magnitude_valid),
    .m_axis_tready(magnitude_ready), .m_axis_tlast(magnitude_last),
    .peak_valid(peak_valid), .peak_bin(peak_bin), .peak_power(peak_power),
    .peak_re(peak_re), .peak_im(peak_im));

  spectrum_pingpong i_banks (
    .pl_clk(adc_clk), .pl_resetn(adc_resetn),
    .mode_continuous(active_mode_continuous), .begin_frame(bank_begin_frame),
    .abort_frame(bank_abort_frame), .release_bank0(cmd_release0 && command_valid_adc),
    .release_bank1(cmd_release1 && command_valid_adc),
    .clear_overrun(cmd_clear_overrun && command_valid_adc), .reset_epoch(active_epoch),
    .epoch_update(cmd_soft_reset && command_valid_adc),
    .frame_id(adc_frame_id + 1'b1), .rf_state(active_command_rf_state),
    .peak_bin_in(peak_bin), .peak_power_in(peak_power),
    .peak_re_in(peak_re), .peak_im_in(peak_im),
    .spectrum_tvalid(magnitude_valid), .spectrum_tready(magnitude_ready),
    .spectrum_bin(magnitude_bin), .spectrum_tdata(magnitude_data),
    .spectrum_tlast(magnitude_last), .frame_active(bank_frame_active),
    .frame_accepted(bank_frame_accepted), .frame_rejected(bank_frame_rejected),
    .publish(bank_publish), .published_bank(bank_published),
    .bank0_valid(bank0_valid_adc), .bank1_valid(bank1_valid_adc),
    .bank_overrun(bank_overrun_adc), .bank0_frame_id(bank0_frame_id),
    .bank1_frame_id(bank1_frame_id), .bank0_rf_state(bank0_rf_state),
    .bank1_rf_state(bank1_rf_state), .bank0_epoch(bank0_epoch),
    .bank1_epoch(bank1_epoch), .bank0_peak_bin(bank0_peak_bin),
    .bank1_peak_bin(bank1_peak_bin), .bank0_peak_power(bank0_peak_power),
    .bank1_peak_power(bank1_peak_power), .bank0_peak_re(bank0_peak_re),
    .bank1_peak_re(bank1_peak_re), .bank0_peak_im(bank0_peak_im),
    .bank1_peak_im(bank1_peak_im), .cpu_clk(s_axi_aclk),
    .cpu_bank_select(1'b0), .cpu_read_enable(1'b0),
    .cpu_read_address(11'd0), .cpu_read_data(legacy_bank_data),
    .cpu_bank0_read_enable(bank0_bram_en),
    .cpu_bank0_read_address(bank0_bram_word_addr),
    .cpu_bank0_read_data(bank0_bram_rddata),
    .cpu_bank1_read_enable(bank1_bram_en),
    .cpu_bank1_read_address(bank1_bram_word_addr),
    .cpu_bank1_read_data(bank1_bram_rddata));

  always @(posedge adc_clk or negedge adc_resetn) begin
    if (!adc_resetn) begin
      fft_config_valid <= 1'b0;
      fft_configured <= 1'b0;
      pipeline_state <= PIPE_IDLE;
      capture_start <= 1'b0;
      capture_abort <= 1'b0;
      replay_start <= 1'b0;
      magnitude_start <= 1'b0;
      bank_begin_frame <= 1'b0;
      bank_abort_frame <= 1'b0;
      active_search_start <= 11'd0;
      active_search_stop <= 11'd2047;
      active_dc_guard <= 11'd0;
      active_epoch <= 16'd0;
      active_command_rf_state <= 3'd0;
      active_mode_continuous <= 1'b0;
      adc_frame_id <= 32'd0;
      fft_error_adc <= 1'b0;
      fft_overflow_adc <= 1'b0;
      dropped_count_at_start <= 32'd0;
      datapath_reset_count <= 2'd0;
      result_valid_adc <= 1'b0;
      result_epoch_adc <= 16'd0;
      result_payload_adc <= {RESULT_WIDTH{1'b0}};
    end else begin
      capture_start <= 1'b0;
      capture_abort <= 1'b0;
      replay_start <= 1'b0;
      magnitude_start <= 1'b0;
      bank_begin_frame <= 1'b0;
      bank_abort_frame <= 1'b0;
      result_valid_adc <= 1'b0;
      if (datapath_reset_count != 0)
        datapath_reset_count <= datapath_reset_count - 1'b1;

      if (datapath_reset) begin
        fft_config_valid <= 1'b0;
        fft_configured <= 1'b0;
      end else if (!fft_configured && !fft_config_valid) begin
        fft_config_valid <= 1'b1;
      end else if (fft_config_valid && fft_config_ready) begin
        fft_config_valid <= 1'b0;
        fft_configured <= 1'b1;
      end

      if (fft_event_tlast_unexpected || fft_event_tlast_missing ||
          fft_event_status_halt)
        fft_error_adc <= 1'b1;
      if (fft_valid && fft_ready && fft_user[0])
        fft_overflow_adc <= 1'b1;

      if (command_valid_adc && cmd_soft_reset) begin
        pipeline_state <= PIPE_RECOVER;
        capture_abort <= 1'b1;
        bank_abort_frame <= 1'b1;
        datapath_reset_count <= 2'd3;
        fft_config_valid <= 1'b0;
        fft_configured <= 1'b0;
        active_epoch <= cmd_epoch;
        fft_error_adc <= 1'b0;
        fft_overflow_adc <= 1'b0;
      end else begin
        if (command_valid_adc && (cmd_epoch != active_epoch)) begin
          if (result_ready_adc) begin
            result_epoch_adc <= cmd_epoch;
            result_payload_adc <= {1'b0, 1'b1, 6'b0, 256'd0};
            result_valid_adc <= 1'b1;
          end
        end else if (command_valid_adc && cmd_abort &&
                     (pipeline_state != PIPE_IDLE)) begin
          capture_abort <= 1'b1;
          bank_abort_frame <= 1'b1;
          datapath_reset_count <= 2'd3;
          fft_config_valid <= 1'b0;
          fft_configured <= 1'b0;
          pipeline_state <= PIPE_RECOVER;
          if (result_ready_adc) begin
            result_epoch_adc <= active_epoch;
            result_payload_adc <= {
              1'b0, 1'b0, 1'b0,
              (capture_dropped_count != dropped_count_at_start),
              fft_overflow_adc, fft_error_adc, 1'b0, 1'b1,
              capture_dropped_count, capture_crc, capture_first_sample,
              16'd0, 16'd0, 33'd0, 11'd0,
              20'd0, capture_sample_count,
              active_epoch, active_command_rf_state, 1'b0, adc_frame_id};
            result_valid_adc <= 1'b1;
          end
        end else if (command_valid_adc && cmd_start && fft_configured &&
            (pipeline_state == PIPE_IDLE) && !result_busy_adc) begin
          active_search_start <= cmd_search_start;
          active_search_stop <= cmd_search_stop;
          active_dc_guard <= cmd_dc_guard;
          active_epoch <= cmd_epoch;
          active_command_rf_state <= cmd_rf_state;
          active_mode_continuous <= cmd_mode_continuous;
          dropped_count_at_start <= capture_dropped_count;
          fft_error_adc <= 1'b0;
          fft_overflow_adc <= 1'b0;
          capture_start <= 1'b1;
          pipeline_state <= PIPE_CAPTURE;
        end

        // frame_ready is held by the capture block until it observes the next
        // start. Do not mistake the previous frame's held level for completion
        // of the newly armed frame on that start-clear cycle.
        if ((pipeline_state == PIPE_CAPTURE) && capture_frame_ready &&
            !capture_start) begin
          bank_begin_frame <= 1'b1;
          pipeline_state <= PIPE_RESERVE;
        end

        if ((pipeline_state == PIPE_RESERVE) && bank_frame_accepted) begin
          replay_start <= 1'b1;
          magnitude_start <= 1'b1;
          pipeline_state <= PIPE_PROCESS;
        end else if ((pipeline_state == PIPE_RESERVE) && bank_frame_rejected) begin
          pipeline_state <= PIPE_IDLE;
          if (result_ready_adc) begin
            result_epoch_adc <= active_epoch;
            result_payload_adc <= {
              1'b0, 1'b0, bank_overrun_adc,
              (capture_dropped_count != dropped_count_at_start),
              fft_overflow_adc, fft_error_adc, 1'b1, 1'b0,
              capture_dropped_count, capture_crc, capture_first_sample,
              16'd0, 16'd0, 33'd0, 11'd0,
              20'd0, capture_sample_count,
              active_epoch, active_command_rf_state, 1'b0, adc_frame_id};
            result_valid_adc <= 1'b1;
          end
        end

        if ((pipeline_state == PIPE_PROCESS) && bank_publish) begin
          adc_frame_id <= adc_frame_id + 1'b1;
          // Re-arm the vendor core between frames.  This also gives abort and
          // normal completion one deterministic recovery path; no residual
          // FFT state can leak into the next command.
          pipeline_state <= PIPE_RECOVER;
          datapath_reset_count <= 2'd3;
          fft_config_valid <= 1'b0;
          fft_configured <= 1'b0;
          if (result_ready_adc) begin
            result_epoch_adc <= active_epoch;
            result_payload_adc <= {
              1'b1, 1'b0, bank_overrun_adc,
              (capture_dropped_count != dropped_count_at_start),
              fft_overflow_adc, fft_error_adc, 1'b0, 1'b0,
              capture_dropped_count, capture_crc, capture_first_sample,
              bank_published ? bank1_peak_im : bank0_peak_im,
              bank_published ? bank1_peak_re : bank0_peak_re,
              bank_published ? bank1_peak_power : bank0_peak_power,
              bank_published ? bank1_peak_bin : bank0_peak_bin,
              20'd0, capture_sample_count,
              active_epoch, active_command_rf_state, bank_published,
              adc_frame_id + 1'b1};
            result_valid_adc <= 1'b1;
          end else begin
            fft_error_adc <= 1'b1;
          end
        end

        if ((pipeline_state == PIPE_RECOVER) && fft_configured &&
            !result_busy_adc)
          pipeline_state <= PIPE_IDLE;
      end
    end
  end

  fft_result_cdc #(.PAYLOAD_WIDTH(RESULT_WIDTH)) i_result_cdc (
    .adc_clk(adc_clk), .adc_resetn(adc_resetn), .i_adc_epoch(result_epoch_adc),
    .i_adc_valid(result_valid_adc), .i_adc_payload(result_payload_adc),
    .o_adc_ready(result_ready_adc), .o_adc_busy(result_busy_adc),
    .cpu_clk(s_axi_aclk), .cpu_resetn(s_axi_aresetn),
    .i_cpu_epoch(reg_reset_epoch), .o_cpu_valid(result_valid_cpu),
    .o_cpu_payload(result_payload_cpu),
    .o_cpu_epoch_fault(result_epoch_fault_cpu));

  always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      cpu_frame_id <= 32'd0;
      cpu_active_bank <= 1'b0;
      cpu_result_rf_state <= 3'd0;
      cpu_result_epoch <= 16'd0;
      cpu_sample_count <= 32'd0;
      cpu_peak_bin <= 11'd0;
      cpu_peak_power <= 33'd0;
      cpu_peak_re <= 16'sd0;
      cpu_peak_im <= 16'sd0;
      cpu_first_sample <= 32'd0;
      cpu_crc <= 32'd0;
      cpu_dropped_count <= 32'd0;
      cpu_bank_valid <= 2'b00;
      done_cpu <= 1'b0;
      cdc_fault_cpu <= 1'b0;
      aborted_cpu <= 1'b0;
      frame_error_cpu <= 1'b0;
      fft_error_cpu <= 1'b0;
      overflow_cpu <= 1'b0;
      dropped_samples_cpu <= 1'b0;
      bank_overrun_cpu <= 1'b0;
    end else begin
      done_cpu <= 1'b0;
      cdc_fault_cpu <= result_epoch_fault_cpu;
      aborted_cpu <= 1'b0;
      frame_error_cpu <= 1'b0;
      fft_error_cpu <= 1'b0;
      overflow_cpu <= 1'b0;
      dropped_samples_cpu <= 1'b0;
      bank_overrun_cpu <= 1'b0;
      if (reg_bank0_release)
        cpu_bank_valid[0] <= 1'b0;
      if (reg_bank1_release)
        cpu_bank_valid[1] <= 1'b0;
      if (reg_soft_reset)
        cpu_bank_valid <= 2'b00;
      if (result_valid_cpu) begin
        cpu_frame_id <= result_payload_cpu[31:0];
        cpu_active_bank <= result_payload_cpu[32];
        cpu_result_rf_state <= result_payload_cpu[35:33];
        cpu_result_epoch <= result_payload_cpu[51:36];
        cpu_sample_count <= result_payload_cpu[83:52];
        cpu_peak_bin <= result_payload_cpu[94:84];
        cpu_peak_power <= result_payload_cpu[127:95];
        cpu_peak_re <= result_payload_cpu[143:128];
        cpu_peak_im <= result_payload_cpu[159:144];
        cpu_first_sample <= result_payload_cpu[191:160];
        cpu_crc <= result_payload_cpu[223:192];
        cpu_dropped_count <= result_payload_cpu[255:224];
        aborted_cpu <= result_payload_cpu[256];
        frame_error_cpu <= result_payload_cpu[257];
        fft_error_cpu <= result_payload_cpu[258];
        overflow_cpu <= result_payload_cpu[259];
        dropped_samples_cpu <= result_payload_cpu[260];
        bank_overrun_cpu <= result_payload_cpu[261];
        cdc_fault_cpu <= result_payload_cpu[262] | result_epoch_fault_cpu;
        done_cpu <= result_payload_cpu[263];
        if (result_payload_cpu[263])
          cpu_bank_valid[result_payload_cpu[32]] <= 1'b1;
      end
    end
  end

  axi_ad9364_fft_regs i_regs (
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
    .i_busy(busy_sync2_cpu || command_busy || command_valid_cpu),
    .i_cdc_ready(cdc_ready_cpu), .i_done(done_cpu),
    .i_cdc_fault(cdc_fault_cpu), .i_aborted(aborted_cpu),
    .i_frame_error(frame_error_cpu), .i_fft_error(fft_error_cpu),
    .i_overflow(overflow_cpu), .i_dropped_samples(dropped_samples_cpu),
    .i_bank_overrun(bank_overrun_cpu), .i_frame_id(cpu_frame_id),
    .i_active_bank(cpu_active_bank), .i_result_rf_state(cpu_result_rf_state),
    .i_result_epoch(cpu_result_epoch), .i_sample_count(cpu_sample_count),
    .i_peak_bin(cpu_peak_bin), .i_peak_power(cpu_peak_power),
    .i_peak_re(cpu_peak_re), .i_peak_im(cpu_peak_im),
    .i_first_sample(cpu_first_sample), .i_frame_crc32(cpu_crc),
    .i_dropped_count(cpu_dropped_count), .i_bank_valid(cpu_bank_valid),
    .o_start(reg_start), .o_abort(reg_abort), .o_soft_reset(reg_soft_reset),
    .o_mode_continuous(reg_mode_continuous),
    .o_bank0_release(reg_bank0_release), .o_bank1_release(reg_bank1_release),
    .o_search_start(reg_search_start), .o_search_stop(reg_search_stop),
    .o_dc_guard(reg_dc_guard), .o_window_select(reg_window_select),
    .o_rf_state(reg_rf_state), .o_reset_epoch(reg_reset_epoch),
    .o_status_clear(reg_status_clear), .o_irq(status_irq));

  assign irq = status_irq;

endmodule

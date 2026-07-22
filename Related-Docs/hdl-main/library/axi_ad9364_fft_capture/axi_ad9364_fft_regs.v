`timescale 1ns/1ps

module axi_ad9364_fft_regs (
  input  wire                s_axi_aclk,
  input  wire                s_axi_aresetn,
  input  wire [7:0]          s_axi_awaddr,
  input  wire                s_axi_awvalid,
  output wire                s_axi_awready,
  input  wire [31:0]         s_axi_wdata,
  input  wire [3:0]          s_axi_wstrb,
  input  wire                s_axi_wvalid,
  output wire                s_axi_wready,
  output wire [1:0]          s_axi_bresp,
  output reg                 s_axi_bvalid,
  input  wire                s_axi_bready,
  input  wire [7:0]          s_axi_araddr,
  input  wire                s_axi_arvalid,
  output wire                s_axi_arready,
  output reg  [31:0]         s_axi_rdata,
  output wire [1:0]          s_axi_rresp,
  output reg                 s_axi_rvalid,
  input  wire                s_axi_rready,

  input  wire                i_busy,
  input  wire                i_cdc_ready,
  input  wire                i_done,
  input  wire                i_cdc_fault,
  input  wire                i_aborted,
  input  wire                i_frame_error,
  input  wire                i_fft_error,
  input  wire                i_overflow,
  input  wire                i_dropped_samples,
  input  wire                i_bank_overrun,
  input  wire [31:0]         i_frame_id,
  input  wire                i_active_bank,
  input  wire [2:0]          i_result_rf_state,
  input  wire [15:0]         i_result_epoch,
  input  wire [31:0]         i_sample_count,
  input  wire [10:0]         i_peak_bin,
  input  wire [32:0]         i_peak_power,
  input  wire signed [15:0] i_peak_re,
  input  wire signed [15:0] i_peak_im,
  input  wire [31:0]         i_first_sample,
  input  wire [31:0]         i_frame_crc32,
  input  wire [31:0]         i_dropped_count,
  input  wire [1:0]          i_bank_valid,

  output reg                 o_start,
  output reg                 o_abort,
  output reg                 o_soft_reset,
  output reg                 o_mode_continuous,
  output reg                 o_bank0_release,
  output reg                 o_bank1_release,
  output reg  [10:0]         o_search_start,
  output reg  [10:0]         o_search_stop,
  output reg  [10:0]         o_dc_guard,
  output reg  [1:0]          o_window_select,
  output reg  [2:0]          o_rf_state,
  output reg  [15:0]         o_reset_epoch,
  output reg  [10:0]         o_status_clear,
  output wire                o_irq
);

  localparam [7:0] ADDR_VERSION = 8'h00;
  localparam [7:0] ADDR_CONTROL = 8'h04;
  localparam [7:0] ADDR_STATUS = 8'h08;
  localparam [7:0] ADDR_SEARCH_RANGE = 8'h0c;
  localparam [7:0] ADDR_DC_GUARD_WINDOW = 8'h10;
  localparam [7:0] ADDR_COMMAND_TAG = 8'h14;
  localparam [7:0] ADDR_FRAME_ID = 8'h18;
  localparam [7:0] ADDR_RESULT_TAG = 8'h1c;
  localparam [7:0] ADDR_SAMPLE_COUNT = 8'h20;
  localparam [7:0] ADDR_PEAK_BIN = 8'h24;
  localparam [7:0] ADDR_PEAK_POWER_LO = 8'h28;
  localparam [7:0] ADDR_PEAK_POWER_HI = 8'h2c;
  localparam [7:0] ADDR_PEAK_RE_IM = 8'h30;
  localparam [7:0] ADDR_FIRST_SAMPLE = 8'h34;
  localparam [7:0] ADDR_FRAME_CRC32 = 8'h38;
  localparam [7:0] ADDR_DROPPED_COUNT = 8'h3c;
  localparam [7:0] ADDR_BANK_VALID = 8'h40;

  reg aw_pending;
  reg [7:0] awaddr_hold;
  reg w_pending;
  reg [31:0] wdata_hold;
  reg [3:0] wstrb_hold;
  reg [10:0] sticky_status;

  wire [31:0] wstrb_mask;
  wire write_commit;
  wire [10:0] status_w1c;
  wire [10:0] event_status;
  wire config_valid;
  wire invalid_start;
  wire [10:0] visible_status;

  assign s_axi_awready = !aw_pending && !s_axi_bvalid;
  assign s_axi_wready = !w_pending && !s_axi_bvalid;
  assign s_axi_bresp = 2'b00;
  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_rresp = 2'b00;

  assign wstrb_mask = {{8{wstrb_hold[3]}}, {8{wstrb_hold[2]}},
                       {8{wstrb_hold[1]}}, {8{wstrb_hold[0]}}};
  assign write_commit = aw_pending && w_pending && !s_axi_bvalid;
  assign status_w1c = (write_commit && (awaddr_hold == ADDR_STATUS)) ?
                      (wdata_hold[10:0] & wstrb_mask[10:0]) : 11'd0;
  assign event_status = {i_bank_overrun, i_dropped_samples, i_overflow,
                         i_fft_error, i_frame_error, i_aborted,
                         i_cdc_fault, 1'b0, i_done, 1'b0};
  assign config_valid = (o_search_start <= o_search_stop) &&
                        (o_dc_guard <= 11'd1024) &&
                        (o_window_select == 2'd0);
  assign invalid_start = write_commit && (awaddr_hold == ADDR_CONTROL) &&
                         wstrb_hold[0] && wdata_hold[0] && !config_valid;
  assign visible_status = sticky_status |
                          {8'd0, i_cdc_ready, 1'b0, i_busy};
  assign o_irq = |(sticky_status & 11'b11111111010);

  always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      aw_pending <= 1'b0;
      awaddr_hold <= 8'd0;
      w_pending <= 1'b0;
      wdata_hold <= 32'd0;
      wstrb_hold <= 4'd0;
      s_axi_bvalid <= 1'b0;
      sticky_status <= 11'd0;
      o_start <= 1'b0;
      o_abort <= 1'b0;
      o_soft_reset <= 1'b0;
      o_mode_continuous <= 1'b0;
      o_bank0_release <= 1'b0;
      o_bank1_release <= 1'b0;
      o_search_start <= 11'd0;
      o_search_stop <= 11'd2047;
      o_dc_guard <= 11'd0;
      o_window_select <= 2'd0;
      o_rf_state <= 3'd0;
      o_reset_epoch <= 16'd0;
      o_status_clear <= 11'd0;
    end else begin
      o_start <= 1'b0;
      o_abort <= 1'b0;
      o_soft_reset <= 1'b0;
      o_bank0_release <= 1'b0;
      o_bank1_release <= 1'b0;
      o_status_clear <= 11'd0;

      sticky_status <= (sticky_status & ~status_w1c) | event_status |
                       {invalid_start, 10'd0};

      if (s_axi_awvalid && s_axi_awready) begin
        aw_pending <= 1'b1;
        awaddr_hold <= s_axi_awaddr;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        w_pending <= 1'b1;
        wdata_hold <= s_axi_wdata;
        wstrb_hold <= s_axi_wstrb;
      end

      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;

      if (write_commit) begin
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
        s_axi_bvalid <= 1'b1;
        case (awaddr_hold)
          ADDR_CONTROL: begin
            if (wstrb_hold[0]) begin
              o_mode_continuous <= wdata_hold[3];
              o_start <= wdata_hold[0] && config_valid;
              o_abort <= wdata_hold[1];
              o_soft_reset <= wdata_hold[2];
              o_bank0_release <= wdata_hold[4];
              o_bank1_release <= wdata_hold[5];
            end
          end
          ADDR_STATUS: begin
            o_status_clear <= status_w1c;
          end
          ADDR_SEARCH_RANGE: begin
            if (wstrb_hold[0]) o_search_start[7:0] <= wdata_hold[7:0];
            if (wstrb_hold[1]) o_search_start[10:8] <= wdata_hold[10:8];
            if (wstrb_hold[2]) o_search_stop[7:0] <= wdata_hold[23:16];
            if (wstrb_hold[3]) o_search_stop[10:8] <= wdata_hold[26:24];
          end
          ADDR_DC_GUARD_WINDOW: begin
            if (wstrb_hold[0]) o_dc_guard[7:0] <= wdata_hold[7:0];
            if (wstrb_hold[1]) begin
              o_dc_guard[10:8] <= wdata_hold[10:8];
            end
            if (wstrb_hold[2]) o_window_select <= wdata_hold[17:16];
          end
          ADDR_COMMAND_TAG: begin
            if (wstrb_hold[0]) o_rf_state <= wdata_hold[2:0];
            if (wstrb_hold[2]) o_reset_epoch[7:0] <= wdata_hold[23:16];
            if (wstrb_hold[3]) o_reset_epoch[15:8] <= wdata_hold[31:24];
          end
          default: begin
          end
        endcase
      end
    end
  end

  always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rdata <= 32'd0;
    end else begin
      if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;
      if (s_axi_arvalid && s_axi_arready) begin
        s_axi_rvalid <= 1'b1;
        case (s_axi_araddr)
          ADDR_VERSION: s_axi_rdata <= 32'h0001_0000;
          ADDR_CONTROL: s_axi_rdata <= {28'd0, o_mode_continuous, 3'd0};
          ADDR_STATUS: s_axi_rdata <= {21'd0, visible_status};
          ADDR_SEARCH_RANGE: s_axi_rdata <= {5'd0, o_search_stop, 5'd0, o_search_start};
          ADDR_DC_GUARD_WINDOW: s_axi_rdata <= {14'd0, o_window_select, 5'd0, o_dc_guard};
          ADDR_COMMAND_TAG: s_axi_rdata <= {o_reset_epoch, 13'd0, o_rf_state};
          ADDR_FRAME_ID: s_axi_rdata <= i_frame_id;
          ADDR_RESULT_TAG: s_axi_rdata <= {i_result_epoch, 12'd0,
                                           i_result_rf_state, i_active_bank};
          ADDR_SAMPLE_COUNT: s_axi_rdata <= i_sample_count;
          ADDR_PEAK_BIN: s_axi_rdata <= {21'd0, i_peak_bin};
          ADDR_PEAK_POWER_LO: s_axi_rdata <= i_peak_power[31:0];
          ADDR_PEAK_POWER_HI: s_axi_rdata <= {31'd0, i_peak_power[32]};
          ADDR_PEAK_RE_IM: s_axi_rdata <= {i_peak_im, i_peak_re};
          ADDR_FIRST_SAMPLE: s_axi_rdata <= i_first_sample;
          ADDR_FRAME_CRC32: s_axi_rdata <= i_frame_crc32;
          ADDR_DROPPED_COUNT: s_axi_rdata <= i_dropped_count;
          ADDR_BANK_VALID: s_axi_rdata <= {30'd0, i_bank_valid};
          default: s_axi_rdata <= 32'd0;
        endcase
      end
    end
  end

endmodule

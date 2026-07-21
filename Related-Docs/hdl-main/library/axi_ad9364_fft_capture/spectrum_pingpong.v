`timescale 1ns/1ps

module spectrum_pingpong (
  input  wire                pl_clk,
  input  wire                pl_resetn,
  input  wire                mode_continuous,
  input  wire                begin_frame,
  input  wire                abort_frame,
  input  wire                release_bank0,
  input  wire                release_bank1,
  input  wire                clear_overrun,
  input  wire [15:0]         reset_epoch,
  input  wire                epoch_update,
  input  wire [31:0]         frame_id,
  input  wire [2:0]          rf_state,
  input  wire [10:0]         peak_bin_in,
  input  wire [32:0]         peak_power_in,
  input  wire signed [15:0] peak_re_in,
  input  wire signed [15:0] peak_im_in,

  input  wire                spectrum_tvalid,
  output wire                spectrum_tready,
  input  wire [10:0]         spectrum_bin,
  input  wire [63:0]         spectrum_tdata,
  input  wire                spectrum_tlast,

  output reg                 frame_active,
  output reg                 frame_accepted,
  output reg                 frame_rejected,
  output reg                 publish,
  output reg                 published_bank,
  output reg                 bank0_valid,
  output reg                 bank1_valid,
  output reg                 bank_overrun,

  output reg  [31:0]         bank0_frame_id,
  output reg  [31:0]         bank1_frame_id,
  output reg  [2:0]          bank0_rf_state,
  output reg  [2:0]          bank1_rf_state,
  output reg  [15:0]         bank0_epoch,
  output reg  [15:0]         bank1_epoch,
  output reg  [10:0]         bank0_peak_bin,
  output reg  [10:0]         bank1_peak_bin,
  output reg  [32:0]         bank0_peak_power,
  output reg  [32:0]         bank1_peak_power,
  output reg  signed [15:0] bank0_peak_re,
  output reg  signed [15:0] bank1_peak_re,
  output reg  signed [15:0] bank0_peak_im,
  output reg  signed [15:0] bank1_peak_im,

  input  wire                cpu_clk,
  input  wire                cpu_bank_select,
  input  wire                cpu_read_enable,
  input  wire [10:0]         cpu_read_address,
  output wire [63:0]         cpu_read_data
);

  localparam [10:0] LAST_BIN = 11'd2047;

  (* ram_style = "block" *) reg [63:0] bank0_memory [0:2047];
  (* ram_style = "block" *) reg [63:0] bank1_memory [0:2047];

  reg active_bank;
  reg preferred_bank;
  reg [31:0] pending_frame_id;
  reg [2:0] pending_rf_state;
  reg [15:0] pending_epoch;
  reg [10:0] expected_bin;
  reg [63:0] bank0_read_data;
  reg [63:0] bank1_read_data;

  wire bank0_free = !bank0_valid || release_bank0;
  wire bank1_free = !bank1_valid || release_bank1;
  wire continuous_bank = ((preferred_bank == 1'b0) && bank0_free) ? 1'b0 :
                         ((preferred_bank == 1'b1) && bank1_free) ? 1'b1 :
                         bank0_free ? 1'b0 : 1'b1;
  wire legal_bank_available = mode_continuous ? (bank0_free || bank1_free) : bank0_free;
  wire write_accepted = spectrum_tvalid && spectrum_tready;
  wire ordered_write = write_accepted && !abort_frame && (spectrum_bin == expected_bin);
  wire complete_word = ordered_write && spectrum_tlast && (expected_bin == LAST_BIN);
  wire bank0_write_enable = ordered_write && (active_bank == 1'b0);
  wire bank1_write_enable = ordered_write && (active_bank == 1'b1);

  assign spectrum_tready = frame_active;

  always @(posedge pl_clk) begin
    if (!pl_resetn) begin
      frame_active <= 1'b0;
      frame_accepted <= 1'b0;
      frame_rejected <= 1'b0;
      publish <= 1'b0;
      published_bank <= 1'b0;
      bank0_valid <= 1'b0;
      bank1_valid <= 1'b0;
      bank_overrun <= 1'b0;
      active_bank <= 1'b0;
      preferred_bank <= 1'b0;
      pending_frame_id <= 32'd0;
      pending_rf_state <= 3'd0;
      pending_epoch <= 16'd0;
      expected_bin <= 11'd0;
      bank0_frame_id <= 32'd0;
      bank1_frame_id <= 32'd0;
      bank0_rf_state <= 3'd0;
      bank1_rf_state <= 3'd0;
      bank0_epoch <= 16'd0;
      bank1_epoch <= 16'd0;
      bank0_peak_bin <= 11'd0;
      bank1_peak_bin <= 11'd0;
      bank0_peak_power <= 33'd0;
      bank1_peak_power <= 33'd0;
      bank0_peak_re <= 16'sd0;
      bank1_peak_re <= 16'sd0;
      bank0_peak_im <= 16'sd0;
      bank1_peak_im <= 16'sd0;
    end else begin
      frame_accepted <= 1'b0;
      frame_rejected <= 1'b0;
      publish <= 1'b0;

      if (release_bank0)
        bank0_valid <= 1'b0;
      if (release_bank1)
        bank1_valid <= 1'b0;
      if (clear_overrun)
        bank_overrun <= 1'b0;

      if (epoch_update) begin
        frame_active <= 1'b0;
        bank0_valid <= 1'b0;
        bank1_valid <= 1'b0;
        bank_overrun <= 1'b0;
        preferred_bank <= 1'b0;
        expected_bin <= 11'd0;
      end else begin
        if (abort_frame && frame_active)
          frame_active <= 1'b0;

        if (begin_frame) begin
          if (!frame_active && legal_bank_available) begin
            active_bank <= mode_continuous ? continuous_bank : 1'b0;
            pending_frame_id <= frame_id;
            pending_rf_state <= rf_state;
            pending_epoch <= reset_epoch;
            expected_bin <= 11'd0;
            frame_active <= 1'b1;
            frame_accepted <= 1'b1;
          end else begin
            frame_rejected <= 1'b1;
            if (!legal_bank_available)
              bank_overrun <= 1'b1;
          end
        end

        // Abort has priority over a coincident last-word handshake. A frame is
        // publishable only after the exact natural sequence 0 through 2047.
        if (ordered_write) begin
          if (complete_word) begin
            frame_active <= 1'b0;
            publish <= 1'b1;
            published_bank <= active_bank;
            preferred_bank <= !active_bank;
            if (active_bank == 1'b0) begin
              bank0_frame_id <= pending_frame_id;
              bank0_rf_state <= pending_rf_state;
              bank0_epoch <= pending_epoch;
              bank0_peak_bin <= peak_bin_in;
              bank0_peak_power <= peak_power_in;
              bank0_peak_re <= peak_re_in;
              bank0_peak_im <= peak_im_in;
              bank0_valid <= 1'b1;
            end else begin
              bank1_frame_id <= pending_frame_id;
              bank1_rf_state <= pending_rf_state;
              bank1_epoch <= pending_epoch;
              bank1_peak_bin <= peak_bin_in;
              bank1_peak_power <= peak_power_in;
              bank1_peak_re <= peak_re_in;
              bank1_peak_im <= peak_im_in;
              bank1_valid <= 1'b1;
            end
          end else if (spectrum_tlast || (expected_bin == LAST_BIN)) begin
            frame_active <= 1'b0;
          end else begin
            expected_bin <= expected_bin + 1'b1;
          end
        end else if (write_accepted && !abort_frame) begin
          frame_active <= 1'b0;
        end
      end
    end
  end

  // Keep each RAM's write and read ports in dedicated clocked blocks. This is
  // the Vivado simple-dual-port, dual-clock block-RAM inference template.
  always @(posedge pl_clk) begin
    if (bank0_write_enable)
      bank0_memory[spectrum_bin] <= spectrum_tdata;
  end

  always @(posedge pl_clk) begin
    if (bank1_write_enable)
      bank1_memory[spectrum_bin] <= spectrum_tdata;
  end

  always @(posedge cpu_clk) begin
    if (cpu_read_enable && (cpu_bank_select == 1'b0))
      bank0_read_data <= bank0_memory[cpu_read_address];
  end

  always @(posedge cpu_clk) begin
    if (cpu_read_enable && (cpu_bank_select == 1'b1))
      bank1_read_data <= bank1_memory[cpu_read_address];
  end

  assign cpu_read_data = cpu_bank_select ? bank1_read_data : bank0_read_data;

endmodule

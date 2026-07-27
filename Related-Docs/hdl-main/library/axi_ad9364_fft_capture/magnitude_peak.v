`timescale 1ns/1ps

module magnitude_peak (
  input  wire                clk,
  input  wire                resetn,
  input  wire                start,
  input  wire [10:0]         search_start,
  input  wire [10:0]         search_stop,
  input  wire [10:0]         dc_guard,

  input  wire [31:0]         s_axis_tdata,
  input  wire                s_axis_tvalid,
  output wire                s_axis_tready,
  input  wire                s_axis_tlast,

  output reg  [63:0]         m_axis_tdata,
  output reg  [10:0]         m_axis_bin,
  output reg                 m_axis_tvalid,
  input  wire                m_axis_tready,
  output reg                 m_axis_tlast,

  output reg                 peak_valid,
  output reg  [10:0]         peak_bin,
  output reg  [32:0]         peak_power,
  output reg  signed [15:0] peak_re,
  output reg  signed [15:0] peak_im
);

  reg active;
  reg [10:0] input_bin;
  reg peak_found;
  reg [10:0] frame_search_start;
  reg [10:0] frame_search_stop;
  reg [10:0] frame_dc_guard;

  wire signed [15:0] input_re = s_axis_tdata[15:0];
  wire signed [15:0] input_im = s_axis_tdata[31:16];
  wire signed [31:0] re_square_signed = input_re * input_re;
  wire signed [31:0] im_square_signed = input_im * input_im;
  wire [32:0] input_power = {1'b0, re_square_signed[31:0]} +
                            {1'b0, im_square_signed[31:0]};
  wire [11:0] upper_guard_start = 12'd2048 - {1'b0, frame_dc_guard};
  wire in_search = (input_bin >= frame_search_start) && (input_bin <= frame_search_stop);
  wire in_lower_guard = (input_bin <= frame_dc_guard);
  wire in_upper_guard = ({1'b0, input_bin} >= upper_guard_start);
  wire eligible = in_search && !in_lower_guard && !in_upper_guard;
  wire accepted = s_axis_tvalid && s_axis_tready;
  wire candidate_wins = eligible && (!peak_found || (input_power > peak_power));

  // One-entry elastic output stage. Its payload is frozen whenever downstream
  // removes ready, and backpressure never reaches beyond this FFT-side input.
  assign s_axis_tready = active && (!m_axis_tvalid || m_axis_tready);

  always @(posedge clk) begin
    if (!resetn) begin
      active <= 1'b0;
      input_bin <= 11'd0;
      peak_found <= 1'b0;
      frame_search_start <= 11'd0;
      frame_search_stop <= 11'd0;
      frame_dc_guard <= 11'd0;
      m_axis_tdata <= 64'd0;
      m_axis_bin <= 11'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      peak_valid <= 1'b0;
      peak_bin <= 11'd0;
      peak_power <= 33'd0;
      peak_re <= 16'sd0;
      peak_im <= 16'sd0;
    end else begin
      peak_valid <= 1'b0;

      if (m_axis_tvalid && m_axis_tready)
        m_axis_tvalid <= 1'b0;

      if (start && !active && !m_axis_tvalid) begin
        active <= 1'b1;
        input_bin <= 11'd0;
        peak_found <= 1'b0;
        frame_search_start <= search_start;
        frame_search_stop <= search_stop;
        frame_dc_guard <= dc_guard;
        peak_bin <= 11'd0;
        peak_power <= 33'd0;
        peak_re <= 16'sd0;
        peak_im <= 16'sd0;
      end

      if (accepted) begin
        m_axis_tdata <= {31'd0, input_power};
        m_axis_bin <= input_bin;
        m_axis_tlast <= s_axis_tlast;
        m_axis_tvalid <= 1'b1;

        if (candidate_wins) begin
          peak_found <= 1'b1;
          peak_bin <= input_bin;
          peak_power <= input_power;
          peak_re <= input_re;
          peak_im <= input_im;
        end

        if (s_axis_tlast) begin
          active <= 1'b0;
          peak_valid <= 1'b1;
        end else begin
          input_bin <= input_bin + 1'b1;
        end
      end
    end
  end

endmodule

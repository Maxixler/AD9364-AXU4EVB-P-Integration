`timescale 1ns/1ps

module adc_frame_replay (
  input  wire         adc_clk,
  input  wire         adc_resetn,
  input  wire         start,
  input  wire         frame_available,

  output reg  [10:0]  mem_rd_addr,
  input  wire [31:0]  mem_rd_data,

  output reg  [31:0]  m_axis_tdata,
  output reg          m_axis_tvalid,
  input  wire         m_axis_tready,
  output reg          m_axis_tlast,

  output reg          busy,
  output reg          done
);

  localparam integer FRAME_LENGTH = 2048;
  localparam [1:0] STATE_IDLE = 2'd0;
  localparam [1:0] STATE_READ_WAIT = 2'd1;
  localparam [1:0] STATE_READ_CAPTURE = 2'd2;
  localparam [1:0] STATE_SEND = 2'd3;
  localparam [10:0] LAST_WORD = 11'd2047;

  reg [1:0] state;
  reg [10:0] word_index;

  always @(posedge adc_clk) begin
    if (!adc_resetn) begin
      state <= STATE_IDLE;
      word_index <= 11'd0;
      mem_rd_addr <= 11'd0;
      m_axis_tdata <= 32'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state)
        STATE_IDLE: begin
          busy <= 1'b0;
          m_axis_tvalid <= 1'b0;
          m_axis_tlast <= 1'b0;
          if (start && frame_available) begin
            busy <= 1'b1;
            word_index <= 11'd0;
            mem_rd_addr <= 11'd0;
            state <= STATE_READ_WAIT;
          end
        end

        // The capture RAM contract is a one-clock synchronous read.  The
        // first wait launches the address; the second state observes data
        // produced by that read without relying on simulator scheduling.
        STATE_READ_WAIT: begin
          state <= STATE_READ_CAPTURE;
        end

        STATE_READ_CAPTURE: begin
          m_axis_tdata <= mem_rd_data;
          m_axis_tlast <= (word_index == LAST_WORD);
          m_axis_tvalid <= 1'b1;
          state <= STATE_SEND;
        end

        STATE_SEND: begin
          if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid <= 1'b0;
            if (word_index == LAST_WORD) begin
              busy <= 1'b0;
              done <= 1'b1;
              m_axis_tlast <= 1'b0;
              state <= STATE_IDLE;
            end else begin
              word_index <= word_index + 1'b1;
              mem_rd_addr <= word_index + 1'b1;
              state <= STATE_READ_WAIT;
            end
          end
        end

        default: begin
          state <= STATE_IDLE;
          busy <= 1'b0;
          m_axis_tvalid <= 1'b0;
          m_axis_tlast <= 1'b0;
        end
      endcase
    end
  end

endmodule

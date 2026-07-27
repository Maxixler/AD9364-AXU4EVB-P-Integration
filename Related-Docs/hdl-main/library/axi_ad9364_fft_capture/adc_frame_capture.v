`timescale 1ns/1ps

module adc_frame_capture #(
  parameter integer DROPPED_COUNTER_WIDTH = 32
) (
  input  wire         adc_clk,
  input  wire         adc_resetn,
  input  wire         start,
  input  wire         abort,
  input  wire         adc_valid,
  input  wire         adc_enable,
  input  wire [15:0]  adc_i,
  input  wire [15:0]  adc_q,
  input  wire [2:0]   rf_state,

  output reg          busy,
  output reg          frame_ready,
  output reg          aborted,
  output reg  [31:0]  first_sample,
  output reg  [11:0]  sample_count,
  output reg  [31:0]  frame_crc32,
  output reg  [31:0]  dropped_count,
  output reg  [2:0]   frame_rf_state,

  input  wire [10:0]  mem_rd_addr,
  output reg  [31:0]  mem_rd_data
);

  localparam integer FRAME_LENGTH = 2048;
  localparam [11:0] LAST_SAMPLE_COUNT = 12'd2047;
  localparam [31:0] DROPPED_MAX =
    (DROPPED_COUNTER_WIDTH >= 32) ? 32'hFFFFFFFF :
    ((32'h00000001 << DROPPED_COUNTER_WIDTH) - 1);

  (* ram_style = "block" *) reg [31:0] sample_memory [0:FRAME_LENGTH-1];

  reg [10:0] write_address;
  reg [31:0] crc_state;
  reg [2:0]  active_rf_state;

  wire [31:0] input_word = {adc_q, adc_i};
  wire [31:0] next_crc = crc32_word(crc_state, input_word);
  wire        sample_present = adc_valid && adc_enable;

  function [31:0] crc32_word;
    input [31:0] crc_in;
    input [31:0] data;
    integer bit_index;
    reg [31:0] crc;
    begin
      crc = crc_in;
      for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
        if (crc[0] ^ data[bit_index])
          crc = (crc >> 1) ^ 32'hEDB88320;
        else
          crc = crc >> 1;
      end
      crc32_word = crc;
    end
  endfunction

  // Independent synchronous read port for the downstream replay engine.
  always @(posedge adc_clk) begin
    mem_rd_data <= sample_memory[mem_rd_addr];
  end

  always @(posedge adc_clk) begin
    if (!adc_resetn) begin
      busy <= 1'b0;
      frame_ready <= 1'b0;
      aborted <= 1'b0;
      first_sample <= 32'd0;
      sample_count <= 12'd0;
      frame_crc32 <= 32'd0;
      dropped_count <= 32'd0;
      frame_rf_state <= 3'd0;
      write_address <= 11'd0;
      crc_state <= 32'hFFFFFFFF;
      active_rf_state <= 3'd0;
    end else begin
      aborted <= 1'b0;

      if (abort && busy) begin
        busy <= 1'b0;
        frame_ready <= 1'b0;
        aborted <= 1'b1;
        sample_count <= 12'd0;
        write_address <= 11'd0;
        crc_state <= 32'hFFFFFFFF;
        if (sample_present && dropped_count != DROPPED_MAX)
          dropped_count <= dropped_count + 1'b1;
      end else if (start && !busy) begin
        busy <= 1'b1;
        frame_ready <= 1'b0;
        first_sample <= 32'd0;
        sample_count <= 12'd0;
        write_address <= 11'd0;
        crc_state <= 32'hFFFFFFFF;
        active_rf_state <= rf_state;
        if (sample_present && dropped_count != DROPPED_MAX)
          dropped_count <= dropped_count + 1'b1;
      end else if (busy && sample_present) begin
        sample_memory[write_address] <= input_word;
        crc_state <= next_crc;

        if (sample_count == 12'd0)
          first_sample <= input_word;

        if (sample_count == LAST_SAMPLE_COUNT) begin
          busy <= 1'b0;
          frame_ready <= 1'b1;
          sample_count <= FRAME_LENGTH;
          frame_crc32 <= next_crc ^ 32'hFFFFFFFF;
          frame_rf_state <= active_rf_state;
        end else begin
          sample_count <= sample_count + 1'b1;
          write_address <= write_address + 1'b1;
        end
      end else if (!busy && sample_present && dropped_count != DROPPED_MAX) begin
        dropped_count <= dropped_count + 1'b1;
      end
    end
  end

endmodule

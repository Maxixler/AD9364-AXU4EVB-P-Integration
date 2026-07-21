`timescale 1ns/1ps

module fft_command_cdc #(
  parameter integer PAYLOAD_WIDTH = 64
) (
  input  wire                     cpu_clk,
  input  wire                     cpu_resetn,
  input  wire [15:0]              i_cpu_epoch,
  input  wire                     i_cpu_valid,
  input  wire [PAYLOAD_WIDTH-1:0] i_cpu_payload,
  output wire                     o_cpu_ready,
  output wire                     o_cpu_busy,

  input  wire                     adc_clk,
  input  wire                     adc_resetn,
  input  wire [15:0]              i_adc_epoch,
  output reg                      o_adc_valid,
  output reg  [PAYLOAD_WIDTH-1:0] o_adc_payload,
  output reg                      o_adc_epoch_fault
);

  reg request_toggle;
  reg [PAYLOAD_WIDTH+15:0] payload_hold;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;
  (* ASYNC_REG = "TRUE" *) reg adc_ready_sync1;
  (* ASYNC_REG = "TRUE" *) reg adc_ready_sync2;

  (* ASYNC_REG = "TRUE" *) reg request_sync1;
  (* ASYNC_REG = "TRUE" *) reg request_sync2;
  (* ASYNC_REG = "TRUE" *) reg cpu_up_sync1;
  (* ASYNC_REG = "TRUE" *) reg cpu_up_sync2;
  reg acknowledge_toggle;
  reg request_seen;
  reg adc_ready;

  assign o_cpu_busy = request_toggle != acknowledge_sync2;
  assign o_cpu_ready = adc_ready_sync2 && !o_cpu_busy;

  always @(posedge cpu_clk or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      request_toggle <= 1'b0;
      payload_hold <= {(PAYLOAD_WIDTH+16){1'b0}};
      acknowledge_sync1 <= 1'b0;
      acknowledge_sync2 <= 1'b0;
      adc_ready_sync1 <= 1'b0;
      adc_ready_sync2 <= 1'b0;
    end else begin
      acknowledge_sync1 <= acknowledge_toggle;
      acknowledge_sync2 <= acknowledge_sync1;
      adc_ready_sync1 <= adc_ready;
      adc_ready_sync2 <= adc_ready_sync1;
      if (i_cpu_valid && o_cpu_ready) begin
        payload_hold <= {i_cpu_epoch, i_cpu_payload};
        request_toggle <= !request_toggle;
      end
    end
  end

  always @(posedge adc_clk or negedge adc_resetn) begin
    if (!adc_resetn) begin
      request_sync1 <= 1'b0;
      request_sync2 <= 1'b0;
      cpu_up_sync1 <= 1'b0;
      cpu_up_sync2 <= 1'b0;
      acknowledge_toggle <= 1'b0;
      request_seen <= 1'b0;
      adc_ready <= 1'b0;
      o_adc_valid <= 1'b0;
      o_adc_payload <= {PAYLOAD_WIDTH{1'b0}};
      o_adc_epoch_fault <= 1'b0;
    end else begin
      request_sync1 <= request_toggle;
      request_sync2 <= request_sync1;
      cpu_up_sync1 <= cpu_resetn;
      cpu_up_sync2 <= cpu_up_sync1;
      o_adc_valid <= 1'b0;
      o_adc_epoch_fault <= 1'b0;

      if (!cpu_up_sync2) begin
        adc_ready <= 1'b0;
        acknowledge_toggle <= request_sync2;
        request_seen <= request_sync2;
      end else if (!adc_ready) begin
        // Align to the current request after either side resets. This consumes
        // no payload and prevents a reset-to-zero toggle from being replayed.
        acknowledge_toggle <= request_sync2;
        request_seen <= request_sync2;
        adc_ready <= 1'b1;
      end else if (request_sync2 != request_seen) begin
        request_seen <= request_sync2;
        acknowledge_toggle <= request_sync2;
        if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_adc_epoch) begin
          o_adc_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
          o_adc_valid <= 1'b1;
        end else begin
          o_adc_epoch_fault <= 1'b1;
        end
      end
    end
  end

endmodule

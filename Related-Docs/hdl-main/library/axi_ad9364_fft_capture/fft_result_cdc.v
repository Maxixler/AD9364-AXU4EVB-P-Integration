`timescale 1ns/1ps

module fft_result_cdc #(
  parameter integer PAYLOAD_WIDTH = 160
) (
  input  wire                     adc_clk,
  input  wire                     adc_resetn,
  input  wire [15:0]              i_adc_epoch,
  input  wire                     i_adc_valid,
  input  wire [PAYLOAD_WIDTH-1:0] i_adc_payload,
  output wire                     o_adc_ready,
  output wire                     o_adc_busy,

  input  wire                     cpu_clk,
  input  wire                     cpu_resetn,
  input  wire [15:0]              i_cpu_epoch,
  output reg                      o_cpu_valid,
  output reg  [PAYLOAD_WIDTH-1:0] o_cpu_payload,
  output reg                      o_cpu_epoch_fault
);

  reg request_toggle;
  reg [PAYLOAD_WIDTH+15:0] payload_hold;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;
  (* ASYNC_REG = "TRUE" *) reg cpu_ready_sync1;
  (* ASYNC_REG = "TRUE" *) reg cpu_ready_sync2;

  (* ASYNC_REG = "TRUE" *) reg request_sync1;
  (* ASYNC_REG = "TRUE" *) reg request_sync2;
  (* ASYNC_REG = "TRUE" *) reg adc_up_sync1;
  (* ASYNC_REG = "TRUE" *) reg adc_up_sync2;
  reg acknowledge_toggle;
  reg request_seen;
  reg cpu_ready;

  assign o_adc_busy = request_toggle != acknowledge_sync2;
  assign o_adc_ready = cpu_ready_sync2 && !o_adc_busy;

  always @(posedge adc_clk or negedge adc_resetn) begin
    if (!adc_resetn) begin
      request_toggle <= 1'b0;
      payload_hold <= {(PAYLOAD_WIDTH+16){1'b0}};
      acknowledge_sync1 <= 1'b0;
      acknowledge_sync2 <= 1'b0;
      cpu_ready_sync1 <= 1'b0;
      cpu_ready_sync2 <= 1'b0;
    end else begin
      acknowledge_sync1 <= acknowledge_toggle;
      acknowledge_sync2 <= acknowledge_sync1;
      cpu_ready_sync1 <= cpu_ready;
      cpu_ready_sync2 <= cpu_ready_sync1;
      if (i_adc_valid && o_adc_ready) begin
        payload_hold <= {i_adc_epoch, i_adc_payload};
        request_toggle <= !request_toggle;
      end
    end
  end

  always @(posedge cpu_clk or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      request_sync1 <= 1'b0;
      request_sync2 <= 1'b0;
      adc_up_sync1 <= 1'b0;
      adc_up_sync2 <= 1'b0;
      acknowledge_toggle <= 1'b0;
      request_seen <= 1'b0;
      cpu_ready <= 1'b0;
      o_cpu_valid <= 1'b0;
      o_cpu_payload <= {PAYLOAD_WIDTH{1'b0}};
      o_cpu_epoch_fault <= 1'b0;
    end else begin
      request_sync1 <= request_toggle;
      request_sync2 <= request_sync1;
      adc_up_sync1 <= adc_resetn;
      adc_up_sync2 <= adc_up_sync1;
      o_cpu_valid <= 1'b0;
      o_cpu_epoch_fault <= 1'b0;

      if (!adc_up_sync2) begin
        cpu_ready <= 1'b0;
        acknowledge_toggle <= request_sync2;
        request_seen <= request_sync2;
      end else if (!cpu_ready) begin
        acknowledge_toggle <= request_sync2;
        request_seen <= request_sync2;
        cpu_ready <= 1'b1;
      end else if (request_sync2 != request_seen) begin
        request_seen <= request_sync2;
        acknowledge_toggle <= request_sync2;
        if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_cpu_epoch) begin
          o_cpu_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
          o_cpu_valid <= 1'b1;
        end else begin
          o_cpu_epoch_fault <= 1'b1;
        end
      end
    end
  end

endmodule

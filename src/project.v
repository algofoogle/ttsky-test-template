/*
 * Copyright (c) 2026 Anton Maurovic
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_algofoogle_test (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  assign uio_out[6:0] = 0;
  assign uio_oe[6:0] = 0;
  assign uio_oe[7] = 1;

  wire speaker;

  assign uio_out[7] = speaker;


  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] h;
  wire [9:0] v;

  wire [5:0] rgb;

  assign {R,G,B} = rgb & {6{video_active}};

  assign rgb =
    (h < 256) ? ((sample >= h[7:0]) ? 6'b11_11_00 : 6'b00_00_10) : // Waveform.
    (h < 384) ? {sample[7:6], sample[4:3], sample[1:0]} :         // Colour bars.
                {4'b0000, {2{speaker}}};                          // 1-bit DAC diffusion.

  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  wire line_end; // Single pulse at the last clock of each horizontal VGA line (CLK/800).
  wire frame_end;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .line_end(line_end),
    .frame_end(frame_end),
    .display_on(video_active),
    .hpos(h),
    .vpos(v)
  );

  wire [7:0] sample;

  // synth synth(
  //   .clk(clk),
  //   .rst(~rst_n),
  //   .sample_out(sample)
  // );

  // newsynth synth(
  //   .clk(clk),
  //   .reset(~rst_n),
  //   .sample(sample)
  // );

  wire synth_tick = (h==399 || h==799); //line_end

  newsynth_v2 synth(
    .clk(clk),
    .reset(~rst_n),
    .tick(synth_tick),
    .up(ui_in[7:4]),
    .down(ui_in[3:0]),
    .sample(sample)
  );



  // synth_v2 synth(
  //   .clk(clk),
  //   .rst(~rst_n),
  //   .sample_out(sample)
  // );

  // synth_gpt33ff synth(
  //   .clk(clk),
  //   .rst_n(rst_n),
  //   .audio_out(sample)
  // );

  // 1-bit sigma-delta DAC, 8-bit input
  sigmadelta_dac_8 dac (
    .clk(clk),
    .rst(~rst_n),
    .sample_in(sample),
    .dac_out(speaker)
  );

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in, 1'b0};

endmodule


module sigmadelta_dac_8(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] sample_in,
    output reg        dac_out
);
    reg  [7:0] sd_err;
    wire [8:0] sd_sum = {1'b0, sd_err} + {1'b0, sample_in};

    always @(posedge clk) begin
        if (rst) begin
            sd_err  <= 8'd0;
            dac_out <= 1'b0;
        end else begin
            sd_err  <= sd_sum[7:0];
            dac_out <= sd_sum[8];
        end
    end
endmodule


/*
Video sync generator, used to drive a VGA monitor.
Timing from: https://en.wikipedia.org/wiki/Video_Graphics_Array
To use:
- Wire the hsync and vsync signals to top level outputs
- Add a 3-bit (or more) "rgb" output to the top level
*/

module hvsync_generator(
  input clk,
  input reset,
  output reg hsync, vsync,
  output display_on,
  output reg [9:0] hpos,
  output reg [9:0] vpos,
  output wire line_end,
  output wire frame_end
);

  // declarations for TV-simulator sync parameters
  // horizontal constants
  parameter H_DISPLAY       = 640; // horizontal display width
  parameter H_BACK          =  48; // horizontal left border (back porch)
  parameter H_FRONT         =  16; // horizontal right border (front porch)
  parameter H_SYNC          =  96; // horizontal sync width
  // vertical constants
  parameter V_DISPLAY       = 480; // vertical display height
  parameter V_TOP           =  33; // vertical top border
  parameter V_BOTTOM        =  10; // vertical bottom border
  parameter V_SYNC          =   2; // vertical sync # lines
  // derived constants
  parameter H_SYNC_START    = H_DISPLAY + H_FRONT;
  parameter H_SYNC_END      = H_DISPLAY + H_FRONT + H_SYNC - 1;
  parameter H_MAX           = H_DISPLAY + H_BACK + H_FRONT + H_SYNC - 1;
  parameter V_SYNC_START    = V_DISPLAY + V_BOTTOM;
  parameter V_SYNC_END      = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
  parameter V_MAX           = V_DISPLAY + V_TOP + V_BOTTOM + V_SYNC - 1;

  wire hmaxxed = (hpos == H_MAX) || reset;	// set when hpos is maximum
  wire vmaxxed = (vpos == V_MAX) || reset;	// set when vpos is maximum

  assign line_end = hmaxxed;
  assign frame_end = vmaxxed;
  
  // horizontal position counter
  always @(posedge clk)
  begin
    hsync <= ~(hpos>=H_SYNC_START && hpos<=H_SYNC_END);
    if(hmaxxed)
      hpos <= 0;
    else
      hpos <= hpos + 1;
  end

  // vertical position counter
  always @(posedge clk)
  begin
    vsync <= ~(vpos>=V_SYNC_START && vpos<=V_SYNC_END);
    if(hmaxxed)
      if (vmaxxed)
        vpos <= 0;
      else
        vpos <= vpos + 1;
  end
  
  // display_on is set when beam is in "safe" visible frame
  assign display_on = (hpos<H_DISPLAY) && (vpos<V_DISPLAY);

endmodule

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

    wire reset = ~rst_n;
    // All output pins must be assigned. If not used, assign to 0:
    assign uio_out[6:0] = 0;
    assign uio_oe[6:0] = 0;
    assign uio_oe[7] = 1;

    // Basic RGB222 VGA output routing with registered pixel RGB:
    wire hsync;
    wire vsync;
    wire video_active;
    wire [9:0] h;
    wire [9:0] v;
    wire [5:0] rgb;
    reg [5:0] rgb_reg;
    always @(posedge clk) rgb_reg <= rgb & {6{video_active}};
    assign uo_out = {
        hsync, rgb_reg[0], rgb_reg[2], rgb_reg[4],
        vsync, rgb_reg[1], rgb_reg[3], rgb_reg[5]
    };

    wire line_end;
    wire frame_end;
    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(reset),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(h),
        .vpos(v),
        .line_end(line_end),
        .frame_end(frame_end)
    );

    reg [11:0] frame_counter; // 4096 frames @ 60Hz ~= 68 seconds.
    always @(posedge clk) begin
        if (reset)
            frame_counter <= 0;
        else if (frame_end)
            frame_counter <= frame_counter + 1;
    end

    // wire [9:0] a = (v>>2)+frame_counter;
    // wire [5:0] circle_radius = 6'd63; //6'd31+$signed( {5{frame_counter[7]}}^(frame_counter[6:2]) );
    // wire circle_start = (h==0);
    // wire circle_done;
    // wire circle_valid;
    // wire [5:0] circle_edge;
    // wire signed [6:0] wave_sample = circle_valid ? {7{a[7]}} ^ {1'b0,~circle_edge} : 0;
    // wire signed [6:0] shaped_sample = wave_sample;// >>> 1;
    // wire [5:0] circle_input = ({6{a[6]}} ^ a[5:0]);// + shaped_sample_reg;
    // circle_edge slow_circle(
    //     // Inputs:
    //     .clk(clk),
    //     .reset(reset),
    //     .radius(circle_radius),
    //     .vertical_line(circle_input), // Circle is vertically symmetrical.
    //     .start(circle_start),
    //     // Outputs:
    //     .done(circle_done),
    //     .valid(circle_valid),
    //     .edge_point(circle_edge)
    // );
    // reg [6:0] shaped_sample_reg;
    // always @(posedge clk)
    //     if (reset)
    //         shaped_sample_reg <= 0;
    //     else if (circle_done)
    //         shaped_sample_reg <= shaped_sample;
    // wire [7:0] shaped_sample_unsigned_8b = (shaped_sample_reg << 1) + 8'd128;
    wire dac_out;
    assign uio_out[7] = dac_out;

    reg [31:0] a;
    always @(posedge clk)
        if (reset)
            a <= 0;
        else if (line_end)
            a <= a + 1;

    localparam B = 6;

    wire [B:0] p = {a[6:6-B]}; //v[5:0] + frame_counter[5:0]; // {v[6:0],2'b00}; // {a[B-2:0],2'b00};

    wire signed [B-1:0] sample =
        frame_counter[6]    ?   {B{p[B]}} ^ (1<<(B-1)) :
                                //(p[B] ? 5'b1_0000 : 5'b0_1111) :
                                //{B-1{p[B]}} ^ (1<<(B-1)) :
                                (({B{p[B]}} ^ p[B-1:0]) + (1<<(B-1)));

    sigmadelta_dac #(.B(B)) dac(
        .clk(clk),
        .reset(reset),
        .sample_in(sample+(1<<(B-1))),
        .dac_out(dac_out)
    );

    wire signed [7:0] visual_sample = {sample,{7-B+1{1'b0000}}};

    wire [9:0] hlut = h-320;
    wire [3:0] hlutcell = hlut[6:3];
    wire in_hlut_cell = (hlut[9:3] < B);
    wire [3:0] samplebit = (B-1-hlutcell);

    assign rgb = {
        {2{h<256 && $signed(h-128)==visual_sample}},
        {2{h>=320 && in_hlut_cell && sample[samplebit]}},
        {2{h>=256 && dac_out && h<320}}
    };

    // List all unused inputs to prevent warnings:
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule

module sigmadelta_dac #(
    parameter B = 5 // Sample bit resolution.
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         [B-1:0] sample_in,
    output reg          dac_out //NOTE: Does this need to be registered??
);
    reg  [B-1:0] sd_err;
    wire [B:0] sd_sum = {1'b0, sd_err} + {1'b0, sample_in};

    always @(posedge clk) begin
        if (reset) begin
            sd_err  <= 0;
            dac_out <= 0;
        end else begin
            sd_err  <= sd_sum[B-1:0];
            dac_out <= sd_sum[B];
        end
    end
endmodule

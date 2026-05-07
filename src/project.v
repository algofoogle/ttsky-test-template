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

    wire dac_out;
    assign uio_out[7] = dac_out;

    reg [31:0] a;
    always @(posedge clk)
        if (reset)
            a <= 0;
        else if (line_end)
            a <= a + 1;

    localparam RSP = 6; // Rate scaling point: For B above this, phase is multiplied. Below it, phase is divided. This maintains desired frequency.
    localparam B = 5; // Bit depth of audio samples. 8 smooth, minor harmonics. 9 smooth, distant harmonics. 10 ~clean. 6 present harmonics. 5 workable. 4 barely passes. 3 Atari.
    localparam BS = B-RSP; // Bit left shift factor.
    localparam SB = RSP-B; // BIt right shift factor.

    // // Phase comes from a continuous accumulator:
    // wire [B:0] p = (B>=RSP) ? a[B:0]<<BS : a[B+SB:SB];
    // Phase comes from vertical line index (has 60Hz hard sync): //NOTE: hvsync_generator is currently hacked to use 512-line frame length.
    wire [B:0] p = (B>=RSP) ? v[B:0]<<BS : v[B+SB:SB];

    // Generate a signed square wave from the phase:
    wire signed [B-1:0] sq_sample = ({B{p[B]}} ^ (1<<(B-1)));
    // Generate a signed triangle wave from the phase:
    wire signed [B-1:0] tr_sample = (({B{p[B]}} ^ p[B-1:0]) + (1<<(B-1))); //NOTE: midpoint bias added for making this signed. Is there a way to avoid that?
    // wire signed [4:0] lfo_base = (frame_counter[7] ? ~frame_counter[6:2] : frame_counter[6:2]);
    // wire signed [B-1:0] lfo = {  {B-5{1'b0}}, lfo_base  };
    // wire signed [B-1:0] lfo = {~lfo_base[4],lfo_base};// + (1<<(B-1)); //{  {B-5{1'b0}}, lfo_base  };
    // wire signed [B-1:0] lfo = sq_sample; //(frame_counter[7] ? ~frame_counter[6:1] : frame_counter[6:1]) ^ (1<<(B-1));

    // Exponential attenuation factor:
    wire [2:0] exp_atten = frame_counter[5:3];

    // Attenuates a signed sample by a given attenuation factor (right-shift amount):
    function signed [B-1:0] attenuated_sample;
        input signed [B-1:0] sample;
        input [2:0] afactor;
        begin
            if (afactor>=B)
                attenuated_sample = 0; // Mute.
            else
                attenuated_sample = sample >>> afactor;
        end
    endfunction

    // Mixer: Start with triangle sample, periodically add in square sample:
    wire signed [B:0] mixed_sample =
                            attenuated_sample(tr_sample, exp_atten) +
        (frame_counter[7] ? attenuated_sample(sq_sample, exp_atten) : 0);
    // Average mixing of the two samples:
    wire signed [B-1:0] sample = mixed_sample[B:1];

    sigmadelta_dac #(.B(B)) dac(
        .clk(clk),
        .reset(reset),
        .sample_in(sample+(1<<(B-1))), // signed => unsigned.
        .dac_out(dac_out)
    );

    // Generate a scaled version of the sample amplitude to fit within a 256-pixel range on screen:
    function signed [7:0] visual_repr;
        input [B-1:0] a;
        begin
            if (B<=8)
                visual_repr = {a,{7-B+1{1'b0}}};
            else
                visual_repr = a[B-1:B-8];
        end
    endfunction

    // Generate a visual representation of raw bits in the sample:
    wire [9:0] hlut = h-320;
    wire [3:0] hlutcell = hlut[6:3];
    wire in_hlut_cell = (hlut[9:3] < B);
    wire [3:0] samplebit = (B-1-hlutcell);

    assign rgb =
        h == 128 ? 6'b11_10_00 : // Waveform midline (0)
    {
        (h<256)                     ?   {2{$signed(h-128)==visual_repr(sample)}} : 2'b00,   // Waveform rendering.

        (h>=320 && in_hlut_cell)    ?   {2{sample[samplebit]}} : 2'b00,                     // Sample bits rendering.

        (h<256)                     ?   {2{$signed(h-128)==visual_repr(sq_sample)}} :       // Square wave.
        (h<320)                     ?   {2{dac_out}} :
                                        2'b00
    };

    // List all unused inputs to prevent warnings:
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule


// module voice #(
//     parameter B = 5
// ) (

// );

// endmodule


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

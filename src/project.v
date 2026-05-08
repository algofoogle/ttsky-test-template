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
    localparam SB = RSP-B; // Bit right shift factor.
    localparam SUB = 9; // Sub-resolution of the voice phase accumulator. SUB+B+1 is the total phase bit depth: Larger gives more tonal precision. 4+8 is minimum.

    // // Tuning based on B1=59.94Hz (making it possible for us to tune based on VSYNC):
    // // C2 = B1*2^(1/12) ~= 59.94*1.0595 ~= 63.5Hz
    // // Sampling rate (based on line_end) is (25175000/800)=31468.75Hz
    // // Hence, each sample is a fractional slice:
    // // n = 63.5/31468.75 ~= 0.0020179
    // // This becomes a portion of the full phase ramp range of 2^(B+SUB)=8192
    // // Hence, the frequency factor is C2=0.0020179*8192=16.53 => round up to 17
    // //                       f*1E6           RampRange      Fs*1000 Round /1000
    // // Maybe make 60Hz G1? That will give everything slightly better tuning as the base.
    // localparam [63:0] P_C  = (( 63_504_217 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_Cs = (( 67_280_375 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_D  = (( 71_281_074 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_Ds = (( 75_519_667 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_E  = (( 80_010_300 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_F  = (( 84_767_960 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_Fs = (( 89_808_526 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_G  = (( 95_148_819 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_Gs = ((100_806_662 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_A  = ((106_800_938 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_As = ((113_151_652 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // localparam [63:0] P_B  = ((119_880_000 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    // ×2^(1÷12)
    // Tuning based on G1=59.94Hz:
    // C2 = G1*2^(5/12) ~= 80.0103Hz
    localparam [63:0] P_C  = (( 80_010_301 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_Cs = (( 84_767_961 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_D  = (( 89_808_526 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_Ds = (( 95_148_819 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_E  = ((100_806_662 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_F  = ((106_800_938 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_Fs = ((113_151_653 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_G  = ((119_880_000 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_Gs = ((127_008_436 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_A  = ((134_560_750 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_As = ((142_562_149 * (2**(B+SUB+1)) / 31468750)+500)/1000;
    localparam [63:0] P_B  = ((151_039_335 * (2**(B+SUB+1)) / 31468750)+500)/1000;

    initial $display("AAANTON", P_C, P_Cs, P_D, P_Ds, P_E, P_F, P_Fs, P_G, P_Gs, P_A, P_As, P_B);

    // // Phase comes from a continuous accumulator:
    // wire [B:0] p = (B>=RSP) ? a[B:0]<<BS : a[B+SB:SB];
    // // Phase comes from vertical line index (has 60Hz hard sync): //NOTE: hvsync_generator is currently hacked to use 512-line frame length.
    // wire [B:0] p = (B>=RSP) ? v[B:0]<<BS : v[B+SB:SB];
    // Phase comes from 'voice' phase accumulator:
    reg [B+SUB:0] pi;
    always @(*) begin
        pi = P_G<<1;
        // C   G   C2  G   Gs  F   E   Cs
        case (frame_counter[6:4])
        4'd0:  pi = P_C;
        4'd1:  pi = P_E;
        4'd2:  pi = P_G;
        4'd3:  pi = P_C<<1;
        4'd4:  pi = P_G;
        4'd5:  pi = P_F;
        4'd6:  pi = P_D;
        4'd7:  pi = P_B;
        4'd8:  pi = P_C<<1;
        4'd9:  pi = P_D;
        4'd10: pi = P_E;
        4'd11: pi = P_G;


        // 4'd8:  pi = P_C;
        // 4'd9:  pi = P_D;
        // 4'd10: pi = P_E;
        // 4'd11: pi = P_G;
        // 4'd0:  pi = P_C;
        // 4'd1:  pi = P_G;
        // 4'd2:  pi = P_C<<1;
        // 4'd3:  pi = P_G;
        // 4'd4:  pi = P_Gs;
        // 4'd5:  pi = P_F;
        // 4'd6:  pi = P_E;
        // 4'd7:  pi = P_Cs;
        // 4'd8:  pi = P_C;
        // 4'd9:  pi = P_D;
        // 4'd10: pi = P_E;
        // 4'd11: pi = P_G;


        endcase
        pi = pi<<2;
    end

    wire [B:0] p;
    voice #(
        .B(B+1), // Extra bit is sign for wave folding.
        .SUB(SUB)
    ) v1 (
        .clk(clk),
        .reset(reset),
        .triga(line_end),
        .inc(pi),
        .sample_out(p)
    );

    // // Generate a signed square wave from the phase:
    // wire signed [B-1:0] sq_sample = ({B{p[B]}} ^ (1<<(B-1)));
    // Generate a signed triangle wave from the phase:
    wire signed [B-1:0] tr_sample = (({B{p[B]}} ^ p[B-1:0]) + (1<<(B-1))); //NOTE: midpoint bias added for making this signed. Is there a way to avoid that?

    // Exponential attenuation factor:
    wire [2:0] exp_atten = 0;//frame_counter[5:3];

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
    // wire signed [B:0] mixed_sample =
    //                         attenuated_sample(tr_sample, exp_atten) +
    //     (frame_counter[7] ? {3'd0,{3{vsync}}} : 0);
    //                         // 0;
    wire sq60 = v>240;
    wire signed [B-1:0] sq_sample = 0;// $signed( {{B-1{sq60}},{1{~sq60}}} );
    wire signed [B:0] mixed_sample =
        sq_sample +
        tr_sample;
    
    // frame_counter[10] ? $signed({1'd0,{5{v>240}}}): tr_sample;
        // (frame_counter[7] ? attenuated_sample(sq_sample, exp_atten) : 0);
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


module voice #(
    parameter B = 5,
    parameter SUB = 8,
    parameter MSB = B+SUB-1
) (
    input clk,
    input reset,
    input triga,
    input [MSB:0] inc,
    output [B-1:0] sample_out
);
    // localparam MSB = B+SUB-1;
    reg [MSB:0] phase;
    assign sample_out = phase[MSB:SUB];
    always @(posedge clk) begin
        if (reset)
            phase <= 0;
        else if (triga)
            phase <= phase + {inc};
    end
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

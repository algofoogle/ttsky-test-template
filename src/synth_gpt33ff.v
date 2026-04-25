module synth_gpt33ff (
    input  wire       clk,         // 25.175 MHz
    input  wire       rst_n,
    output reg  [7:0] audio_out
);

    // ------------------------------------------------------------------------
    // Register budget:
    //   master_time : 25 bits
    //   audio_out   :  8 bits
    // Total real DFF bits = 33
    // ------------------------------------------------------------------------

    // Free-running master time.
    // low  9 bits: sub-sample phase (gives sample rate = clk / 512)
    // high bits : audio sample index
    reg [24:0] master_time;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            master_time <= 25'd0;
        else
            master_time <= master_time + 25'd1;
    end

    // Sample update every 512 clocks:
    // 25.175 MHz / 512 = 49,169.921875 Hz
    wire sample_tick = (master_time[8:0] == 9'h1FF);

    // Audio-sample counter
    wire [15:0] sample_idx = master_time[24:9];

    // ------------------------------------------------------------------------
    // Song timing
    // ------------------------------------------------------------------------
    //
    // One step = 4096 audio samples
    // Step rate = 49,169.921875 / 4096 = 12.0044 Hz
    // Step duration ≈ 83.30 ms
    //
    // 16-step loop:
    // step_idx   = current step in the loop
    // step_phase = sample offset within the current step
    //
    localparam integer STEP_BITS = 12;   // 4096 samples per step

    wire [3:0]  step_idx   = sample_idx[15:12];
    wire [11:0] step_phase = sample_idx[11:0];

    // ------------------------------------------------------------------------
    // Shared fade shape
    // ------------------------------------------------------------------------
    //
    // Fade length = 256 samples = ~5.21 ms at 49.17 kHz
    //
    // Everybody shares the same fade timing:
    //   first 256 samples of a step  -> fade in
    //   middle                       -> full
    //   last 256 samples of a step   -> fade out
    //
    // Because STEP_BITS=12 and FADE_LEN=256=2^8, this becomes very cheap.
    //
    function [7:0] step_fade_gain;
        input [11:0] ph;
        begin
            if (ph[11:8] == 4'h0)
                step_fade_gain = ph[7:0];        // 0..255 fade-in
            else if (ph[11:8] == 4'hF)
                step_fade_gain = ~ph[7:0];       // 255..0 fade-out
            else
                step_fade_gain = 8'hFF;          // full level
        end
    endfunction

    wire [7:0] global_fade = step_fade_gain(step_phase);

    // ------------------------------------------------------------------------
    // Note frequency words for fs = 25.175 MHz / 512 = 49,169.921875 Hz
    // freq_word = round(f * 65536 / fs)
    // ------------------------------------------------------------------------
    localparam [15:0] N_REST = 16'd0;
    localparam [15:0] N_C4   = 16'd349;
    localparam [15:0] N_D4   = 16'd391;
    localparam [15:0] N_E4   = 16'd439;
    localparam [15:0] N_F4   = 16'd465;
    localparam [15:0] N_G4   = 16'd522;

    localparam [15:0] N_A3   = 16'd293;
    localparam [15:0] N_G3   = 16'd261;
    localparam [15:0] N_E3   = 16'd220;
    localparam [15:0] N_D3   = 16'd196;
    localparam [15:0] N_C3   = 16'd174;

    localparam [15:0] N_G2   = 16'd131;
    localparam [15:0] N_F2   = 16'd116;

    // ------------------------------------------------------------------------
    // Score ROM (purely combinational)
    // ------------------------------------------------------------------------
    //
    // Every step, each voice gets:
    //   - a note
    //   - a volume
    //
    // The phase reset / "t1" idea is implicit:
    // relative_time = step_phase
    // i.e. each step starts at phase 0 automatically.
    //
    reg [15:0] freq0, freq1, freq2, freq3;
    reg [7:0]  vol0,  vol1,  vol2,  vol3;

    always @* begin
        // defaults
        freq0 = N_REST; vol0 = 8'd0;
        freq1 = N_REST; vol1 = 8'd0;
        freq2 = N_REST; vol2 = 8'd0;
        freq3 = N_REST; vol3 = 8'd0;

        case (step_idx)
            4'd0: begin
                freq0 = N_C4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd1: begin
                freq0 = N_D4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_A3; vol3 = 8'd96;
            end
            4'd2: begin
                freq0 = N_E4; vol0 = 8'd220;
                freq1 = N_F4; vol1 = 8'd150;
                freq2 = N_F2; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd3: begin
                freq0 = N_G4; vol0 = 8'd220;
                freq1 = N_F4; vol1 = 8'd150;
                freq2 = N_F2; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd4: begin
                freq0 = N_E4; vol0 = 8'd220;
                freq1 = N_G4; vol1 = 8'd150;
                freq2 = N_G2; vol2 = 8'd170;
                freq3 = N_E3; vol3 = 8'd96;
            end
            4'd5: begin
                freq0 = N_D4; vol0 = 8'd220;
                freq1 = N_G4; vol1 = 8'd150;
                freq2 = N_G2; vol2 = 8'd170;
                freq3 = N_D3; vol3 = 8'd96;
            end
            4'd6: begin
                freq0 = N_C4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_E3; vol3 = 8'd96;
            end
            4'd7: begin
                freq0 = N_REST; vol0 = 8'd0;
                freq1 = N_REST; vol1 = 8'd0;
                freq2 = N_REST; vol2 = 8'd0;
                freq3 = N_REST; vol3 = 8'd0;
            end

            // repeat / variation
            4'd8: begin
                freq0 = N_C4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd9: begin
                freq0 = N_D4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_A3; vol3 = 8'd96;
            end
            4'd10: begin
                freq0 = N_E4; vol0 = 8'd220;
                freq1 = N_F4; vol1 = 8'd150;
                freq2 = N_F2; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd11: begin
                freq0 = N_G4; vol0 = 8'd220;
                freq1 = N_F4; vol1 = 8'd150;
                freq2 = N_F2; vol2 = 8'd170;
                freq3 = N_G3; vol3 = 8'd96;
            end
            4'd12: begin
                freq0 = N_E4; vol0 = 8'd220;
                freq1 = N_G4; vol1 = 8'd150;
                freq2 = N_G2; vol2 = 8'd170;
                freq3 = N_E3; vol3 = 8'd96;
            end
            4'd13: begin
                freq0 = N_D4; vol0 = 8'd220;
                freq1 = N_G4; vol1 = 8'd150;
                freq2 = N_G2; vol2 = 8'd170;
                freq3 = N_D3; vol3 = 8'd96;
            end
            4'd14: begin
                freq0 = N_C4; vol0 = 8'd220;
                freq1 = N_E4; vol1 = 8'd150;
                freq2 = N_C3; vol2 = 8'd170;
                freq3 = N_E3; vol3 = 8'd96;
            end
            4'd15: begin
                freq0 = N_REST; vol0 = 8'd0;
                freq1 = N_REST; vol1 = 8'd0;
                freq2 = N_REST; vol2 = 8'd0;
                freq3 = N_REST; vol3 = 8'd0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Effective per-voice gain
    // ------------------------------------------------------------------------
    //
    // Voices either:
    //   - use the shared fade
    //   - or are silent
    //
    wire [7:0] gain0 = (freq0 == N_REST || vol0 == 8'd0) ? 8'd0 : global_fade;
    wire [7:0] gain1 = (freq1 == N_REST || vol1 == 8'd0) ? 8'd0 : global_fade;
    wire [7:0] gain2 = (freq2 == N_REST || vol2 == 8'd0) ? 8'd0 : global_fade;
    wire [7:0] gain3 = (freq3 == N_REST || vol3 == 8'd0) ? 8'd0 : global_fade;

    // ------------------------------------------------------------------------
    // Virtual phase accumulator
    // ------------------------------------------------------------------------
    //
    // No stored phase per voice.
    //
    // Instead:
    //   phase16 = step_phase * freq_word   (mod 65536)
    //
    // This means each step starts at phase 0 automatically.
    // It is the "fade and restart" simplification of the t1 concept.
    //
    wire [27:0] prod0 = step_phase * freq0;
    wire [27:0] prod1 = step_phase * freq1;
    wire [27:0] prod2 = step_phase * freq2;
    wire [27:0] prod3 = step_phase * freq3;

    wire [15:0] phase0 = prod0[15:0];
    wire [15:0] phase1 = prod1[15:0];
    wire [15:0] phase2 = prod2[15:0];
    wire [15:0] phase3 = prod3[15:0];

    // ------------------------------------------------------------------------
    // Triangle from top 8 bits of phase16
    // ------------------------------------------------------------------------
    function [7:0] tri8;
        input [15:0] ph16;
        reg [7:0] ph8;
        begin
            ph8 = ph16[15:8];
            if (ph8 < 8'd128)
                tri8 = ph8 << 1;
            else
                tri8 = (8'd255 - ph8) << 1;
        end
    endfunction

    wire [7:0] vtri0 = tri8(phase0);
    wire [7:0] vtri1 = tri8(phase1);
    wire [7:0] vtri2 = tri8(phase2);
    wire [7:0] vtri3 = tri8(phase3);

    // ------------------------------------------------------------------------
    // Volume + fade
    // ------------------------------------------------------------------------
    //
    // Signed voice sample:
    //   signed_triangle * volume * gain >> 16
    //
    // signed_triangle is roughly -128..+126
    //
    wire signed [8:0] tri_s0 = $signed({1'b0, vtri0}) - 9'sd128;
    wire signed [8:0] tri_s1 = $signed({1'b0, vtri1}) - 9'sd128;
    wire signed [8:0] tri_s2 = $signed({1'b0, vtri2}) - 9'sd128;
    wire signed [8:0] tri_s3 = $signed({1'b0, vtri3}) - 9'sd128;

    wire signed [17:0] sv0 = tri_s0 * $signed({1'b0, vol0});
    wire signed [17:0] sv1 = tri_s1 * $signed({1'b0, vol1});
    wire signed [17:0] sv2 = tri_s2 * $signed({1'b0, vol2});
    wire signed [17:0] sv3 = tri_s3 * $signed({1'b0, vol3});

    wire signed [25:0] svg0 = sv0 * $signed({1'b0, gain0});
    wire signed [25:0] svg1 = sv1 * $signed({1'b0, gain1});
    wire signed [25:0] svg2 = sv2 * $signed({1'b0, gain2});
    wire signed [25:0] svg3 = sv3 * $signed({1'b0, gain3});

    wire signed [9:0] voice0 = svg0 >>> 16;
    wire signed [9:0] voice1 = svg1 >>> 16;
    wire signed [9:0] voice2 = svg2 >>> 16;
    wire signed [9:0] voice3 = svg3 >>> 16;

    wire signed [11:0] mix_s = voice0 + voice1 + voice2 + voice3;

    // ------------------------------------------------------------------------
    // Clip to signed 8-bit then bias to unsigned 8-bit
    // ------------------------------------------------------------------------
    reg signed [7:0] mix_clip_s;
    reg [7:0] mix_u8;

    always @* begin
        if (mix_s > 12'sd127)
            mix_clip_s = 8'sd127;
        else if (mix_s < -12'sd128)
            mix_clip_s = -8'sd128;
        else
            mix_clip_s = mix_s[7:0];

        mix_u8 = mix_clip_s + 8'd128;
    end

    // ------------------------------------------------------------------------
    // Register only the final output sample
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            audio_out <= 8'd128;
        else if (sample_tick)
            audio_out <= mix_u8;
    end

endmodule

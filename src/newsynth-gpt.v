module tiny_timebase_tri_4voice (
    input  wire        clk,
    input  wire        rst_n,

    // Shared sample-rate divider:
    // sample_tick occurs when sample_div_ctr == sample_div
    input  wire [15:0] sample_div,

    // Per-voice "frequency factors".
    // Higher value = higher pitch.
    input  wire [15:0] freq0,
    input  wire [15:0] freq1,
    input  wire [15:0] freq2,
    input  wire [15:0] freq3,

    // Per-voice time offsets (phase/time anchors).
    // These play the role of t1.
    input  wire [15:0] t1_0,
    input  wire [15:0] t1_1,
    input  wire [15:0] t1_2,
    input  wire [15:0] t1_3,

    // Per-voice 8-bit volumes.
    input  wire [7:0]  vol0,
    input  wire [7:0]  vol1,
    input  wire [7:0]  vol2,
    input  wire [7:0]  vol3,

    // Mixed 8-bit unsigned output sample.
    output reg  [7:0]  sample_out
);

    // ------------------------------------------------------------------------
    // 1) Shared timebase
    // ------------------------------------------------------------------------
    //
    // pos     = coarse time
    // subpos  = fractional time
    //
    // This is the "single bigger counter used to compute all phases".
    //
    reg [15:0] sample_div_ctr;
    reg [15:0] pos;
    reg [7:0]  subpos;

    wire sample_tick = (sample_div_ctr == sample_div);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_div_ctr <= 16'd0;
            pos            <= 16'd0;
            subpos         <= 8'd0;
        end else begin
            if (sample_tick) begin
                sample_div_ctr <= 16'd0;

                // Fractional time runs every sample tick.
                subpos <= subpos + 8'd1;

                // When subpos wraps, increment coarse time.
                if (subpos == 8'hFF)
                    pos <= pos + 16'd1;
            end else begin
                sample_div_ctr <= sample_div_ctr + 16'd1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2) Build per-voice effective time
    // ------------------------------------------------------------------------
    //
    // Each voice sees:
    //   full_t = { pos + t1, subpos }
    //
    // So each voice can have its own phase/time offset without needing
    // a private running phase accumulator.
    //
    wire [15:0] t_eff0 = pos + t1_0;
    wire [15:0] t_eff1 = pos + t1_1;
    wire [15:0] t_eff2 = pos + t1_2;
    wire [15:0] t_eff3 = pos + t1_3;

    wire [23:0] full_t0 = {t_eff0, subpos};
    wire [23:0] full_t1 = {t_eff1, subpos};
    wire [23:0] full_t2 = {t_eff2, subpos};
    wire [23:0] full_t3 = {t_eff3, subpos};

    // ------------------------------------------------------------------------
    // 3) Phase from global time
    // ------------------------------------------------------------------------
    //
    // A normal DDS would do:
    //   phase <= phase + phase_inc
    //
    // This design instead does:
    //   phase = full_t * freq
    //
    // Then we take the upper bits as the oscillator phase.
    //
    // For simplicity, this example uses normal '*' operators.
    // A Tiny Tapeout-minimised version would replace these with a shared
    // bit-serial multiply datapath.
    //
    wire [39:0] prod0 = full_t0 * freq0;
    wire [39:0] prod1 = full_t1 * freq1;
    wire [39:0] prod2 = full_t2 * freq2;
    wire [39:0] prod3 = full_t3 * freq3;

    // Use top 8 bits as the phase for an 8-bit triangle.
    wire [7:0] phase0 = prod0[39:32];
    wire [7:0] phase1 = prod1[39:32];
    wire [7:0] phase2 = prod2[39:32];
    wire [7:0] phase3 = prod3[39:32];

    // ------------------------------------------------------------------------
    // 4) Triangle generation from 8-bit phase
    // ------------------------------------------------------------------------
    //
    // Standard 8-bit unsigned triangle:
    //   if phase < 128 : tri = phase * 2
    //   else           : tri = 255 - ((phase - 128) * 2)
    //
    function automatic [7:0] tri8;
        input [7:0] ph;
        begin
            if (!ph[7])
                tri8 = {ph[6:0], 1'b0};
            else
                tri8 = {~ph[6:0], 1'b1};
        end
    endfunction

    wire [7:0] tri0 = tri8(phase0);
    wire [7:0] tri1 = tri8(phase1);
    wire [7:0] tri2 = tri8(phase2);
    wire [7:0] tri3 = tri8(phase3);

    // ------------------------------------------------------------------------
    // 5) Apply 8-bit volume per voice
    // ------------------------------------------------------------------------
    //
    // voice_sample = triangle * volume / 256
    //
    wire [15:0] vprod0 = tri0 * vol0;
    wire [15:0] vprod1 = tri1 * vol1;
    wire [15:0] vprod2 = tri2 * vol2;
    wire [15:0] vprod3 = tri3 * vol3;

    wire [7:0] voice0 = vprod0[15:8];
    wire [7:0] voice1 = vprod1[15:8];
    wire [7:0] voice2 = vprod2[15:8];
    wire [7:0] voice3 = vprod3[15:8];

    // ------------------------------------------------------------------------
    // 6) Mix voices
    // ------------------------------------------------------------------------
    //
    // Sum 4 unsigned voices, then divide by 4 so output stays in 8 bits.
    //
    wire [9:0] mix_sum = {2'b00, voice0} +
                         {2'b00, voice1} +
                         {2'b00, voice2} +
                         {2'b00, voice3};

    wire [7:0] mix_scaled = mix_sum[9:2];

    // Register the sample on sample_tick.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out <= 8'd0;
        end else if (sample_tick) begin
            sample_out <= mix_scaled;
        end
    end

endmodule
`default_nettype none

/* verilator lint_off DECLFILENAME */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */

module newsynth_v2(
    input clk,          // System clock (nom. 25.175MHz).
    input reset,
    input tick,         // Sample advance tick (nom. VGA Hfreq: clk/800 = 31468.75Hz).
    input [3:0] up,
    input [3:0] down,
    output [7:0] sample // 8-bit audio sample output.
);
    localparam [63:0] SRM = 314687500; // clk/800*10000
    // (x10000 is applied to frequencies below, for better precision)
    localparam [63:0] FR = SRM/2; // F_ rounding factor.

    // Why *65536? See prod0...
    localparam [63:0] F_C4  = ((2616256 * 65536) + FR) / SRM; // C4  target=261.6256 Hz => int(545); C2=136; C1=68; C6=2181; C7=4362
    localparam [63:0] F_Cs4 = ((2771826 * 65536) + FR) / SRM; // C#4 target=277.1826 Hz
    localparam [63:0] F_D4  = ((2936648 * 65536) + FR) / SRM; // D4  target=293.6648 Hz
    localparam [63:0] F_Ds4 = ((3111270 * 65536) + FR) / SRM; // D#4 target=311.1270 Hz
    localparam [63:0] F_E4  = ((3296276 * 65536) + FR) / SRM; // E4  target=329.6276 Hz
    localparam [63:0] F_F4  = ((3492282 * 65536) + FR) / SRM; // F4  target=349.2282 Hz
    localparam [63:0] F_Fs4 = ((3699944 * 65536) + FR) / SRM; // F#4 target=369.9944 Hz
    localparam [63:0] F_G4  = ((3919954 * 65536) + FR) / SRM; // G4  target=391.9954 Hz
    localparam [63:0] F_Gs4 = ((4153047 * 65536) + FR) / SRM; // G#4 target=415.3047 Hz
    localparam [63:0] F_A4  = ((4400000 * 65536) + FR) / SRM; // A4  target=440.0000 Hz
    localparam [63:0] F_As4 = ((4661638 * 65536) + FR) / SRM; // A#4 target=466.1638 Hz
    localparam [63:0] F_B4  = ((4938833 * 65536) + FR) / SRM; // B4  target=493.8833 Hz

    initial begin
        $display("F_C4=", F_C4);
    end

    // Synth master counter, which increments by 1 every (sample) tick.
    reg [21:0] t; // 22 bits is enough for about 4.2 million samples (~133 seconds).
    always @(posedge clk) begin
        if (reset)
            t <= 0;
        else if (tick)
            t <= t+1;
    end

    wire [7:0] ft = t[7:0];    // Fine time: ~31.78us
    wire [13:0] ct = t[21:8];   // Coarse time: ft/256 = ~8.135ms

    function [11:0] note_lut;
        input [3:0] note_index;
        input [2:0] octave;
        begin
            if (octave < 4)
                case (note_index)
                4'd0:       note_lut = F_C4     >> (4-octave);
                4'd1:       note_lut = F_Cs4    >> (4-octave);
                4'd2:       note_lut = F_D4     >> (4-octave);
                4'd3:       note_lut = F_Ds4    >> (4-octave);
                4'd4:       note_lut = F_E4     >> (4-octave);
                4'd5:       note_lut = F_F4     >> (4-octave);
                4'd6:       note_lut = F_Fs4    >> (4-octave);
                4'd7:       note_lut = F_G4     >> (4-octave);
                4'd8:       note_lut = F_Gs4    >> (4-octave);
                4'd9:       note_lut = F_A4     >> (4-octave);
                4'd10:      note_lut = F_As4    >> (4-octave);
                4'd11:      note_lut = F_B4     >> (4-octave);
                default:    note_lut = 0;
                endcase
            else
                case (note_index)
                4'd0:       note_lut = F_C4     << (octave-4);
                4'd1:       note_lut = F_Cs4    << (octave-4);
                4'd2:       note_lut = F_D4     << (octave-4);
                4'd3:       note_lut = F_Ds4    << (octave-4);
                4'd4:       note_lut = F_E4     << (octave-4);
                4'd5:       note_lut = F_F4     << (octave-4);
                4'd6:       note_lut = F_Fs4    << (octave-4);
                4'd7:       note_lut = F_G4     << (octave-4);
                4'd8:       note_lut = F_Gs4    << (octave-4);
                4'd9:       note_lut = F_A4     << (octave-4);
                4'd10:      note_lut = F_As4    << (octave-4);
                4'd11:      note_lut = F_B4     << (octave-4);
                default:    note_lut = 0;
                endcase
        end
    endfunction

    //NOTE: Highest multiplicand would be maybe 4095 (12-bit; just shy of B6) or possibly 13-bit.
    // Need to test the range from (say) A2 to A6 to see how it sounds...
    // ...i.e. chromatic purity, and then compare accuracy of one octave to another.
    // Anyway, we assume the product will be {22b}*{13b} => {35b}
    // ...but since F_ factors are derived from *65536 (i.e. 1<<16) then we only actually
    // look at [15:0] from each product, and then need only the upper 9 bits of that to
    // get our phase, which is then converted to an 8-bit tri8() sample (using the 9th
    // bit for folding what is otherwise a sawtooth into a triangle).
    // I figure we could go for a lower bit depth on some of these, and see how the
    // quality goes. If ft is fewer bits, I guess we'd have smaller frequency factors, and start to
    // lose frequency precision?

    wire gate0 = up[0] & down[0];
    wire gate1 = up[1] & down[1];
    wire gate2 = up[2] & down[2];
    wire gate3 = up[3] & down[3];

    // wire [2:0] octave = t[14] + 3;

    // wire [34:0] prod0 = gate0 ? 0 : ( t * (note_lut(0, 5)-(t[0]&down[0])+(t[0]&up[0])) ); //{ct[13:0], ft} * (F_C4<<1);
    // // wire [34:0] prod1 = gate1 ? 0 : ( t * (note_lut(4, 5)-(t[0]&down[1])+(t[0]&up[1])) ); //{ct[13:0], ft} * (F_E4<<1);
    // wire [34:0] prod1 = gate1 ? 0 : ( t * (note_lut(0, 2)-(t[0]&down[1])+(t[0]&up[1])) ); //{ct[13:0], ft} * (F_E4<<1);
    // wire [34:0] prod2 = gate2 ? 0 : ( t * (note_lut(7, 5)-(t[0]&down[2])+(t[0]&up[2])) ); //{ct[13:0], ft} * (F_G4<<1);
    // wire [34:0] prod3 = gate3 ? 0 : ( t * (note_lut(0, octave)-(t[0]&down[3])+(t[0]&up[3])) ); //{ct[13:0], ft} * (F_C4<<0);

    wire [34:0] prod0 = gate0 ? 0 : ( t * (note_lut(n0, o0)));
    wire [34:0] prod1 = gate1 ? 0 : ( t * (note_lut(n1, o1)));
    wire [34:0] prod2 = gate2 ? 0 : ( t * (note_lut(n2, o2)));
    wire [34:0] prod3 = gate3 ? 0 : ( t * (note_lut(n3, o3)));

    // IDEAS:
    //  - Add t[0] to some or all: Makes a nice "dynamic" phasing effect.
    //      It goes in and out of phase because of cumulative error.
    //      npnp (negative, positive, negative, positive) might be nicer.
    //      +t[1:0] and even +t[1] are horrible though. Maybe t[0] works because it is high freq enough.
    //  - Add t[11:0] makes a crazy multi-layered "laser".
    //      npnp might be nicer.
    //  - Solo note(4,5) with +t[0] sounds like a nice instrument. Maybe similar to a pipe?
    //  - C3+phaser goes well with C2(no-phaser)

    function automatic [7:0] tri8;
        input [8:0] ph;
        begin
            if (!ph[8])
                tri8 = ph[7:0];
            else
                tri8 = ~ph[7:0]; // Fold the wave to make it a triangle: Also HALVES the frequency.
        end
    endfunction

    function [7:0] tri8_pwm;
        input [8:0] ph;
        input [8:0] duty;
        begin
            if (ph >= duty)
                tri8_pwm = 0;
            else
                tri8_pwm = tri8(ph);
        end
    endfunction

    // // Sample values computed at 'tick' for each sample...
    // //NOTE: 9 bits go from phase (prodN) into tri8() to get 8-bit sample output.
    // wire [9:0] sample_wide =
    //     // {2'b00, tri8_pwm(prod0[16:8], 9'd448 + $signed((t[9] ? t[8:5] : ~t[8:5])))} + // Buzzy.
    //     // {2'b00, tri8_pwm(prod0[16:8], 9'd400 + $signed((t[11] ? t[10:8] : ~t[10:8])))} + // Sharp tremolo.
    //     // {2'b00, tri8_pwm(prod0[16:8], 9'd480 + $signed((t[11] ? t[10:8] : ~t[10:8])))} + // Gentler/smoother tremolo
    //     {2'b00, 8'd0} + //tri8_pwm(prod0[16:8], 9'd480 + $signed((t[11] ? t[10:8] : ~t[10:8])))} +
    //     {2'b00, tri8(prod1[16:8]>>t[12:10])>>t[12:10]} +
    //     {2'b00, tri8(prod2[16:8])>>t[12:10]} + // Fast decay.
    //     {2'b00, tri8(prod3[16:8]>>t[12:10])>>t[12:10]}; // More of a "fat bass" sound.
    //     // {2'b00, tri8(prod3[16:8]>>t[12:10])}; // More of a "fat bass" sound.

    // Sample values computed at 'tick' for each sample...
    //NOTE: 9 bits go from phase (prodN) into tri8() to get 8-bit sample output.
    wire [9:0] sample_wide =
        {2'b00, tri8(prod0[16:8])>>a0} + //>>a0} +
        {2'b00, tri8(prod1[16:8])} + //>>a1} +
        {2'b00, tri8(prod2[16:8])} + //>>a2} +
        {2'b00, tri8(prod3[16:8])}; //>>a3};
    assign sample = sample_wide[9:2];

    wire [2:0] o0;
    wire [2:0] o1;
    wire [2:0] o2;
    wire [2:0] o3;
    wire [3:0] n0;
    wire [3:0] n1;
    wire [3:0] n2;
    wire [3:0] n3;
    wire [2:0] a0;
    wire [2:0] a1;
    wire [2:0] a2;
    wire [2:0] a3;

    sequencer musical_events(
        .t(ct),
        .o0(o0),
        .o1(o1),
        .o2(o2),
        .o3(o3),
        .n0(n0),
        .n1(n1),
        .n2(n2),
        .n3(n3),
        .a0(a0),
        .a1(a1),
        .a2(a2),
        .a3(a3)
    );

endmodule


module sequencer(
    input [13:0] t, // ~8.135ms granularity.
    output reg [ 2:0] o0, output reg [ 2:0] o1, output reg [ 2:0] o2, output reg [ 2:0] o3, // Octaves.
    output reg [ 3:0] n0, output reg [ 3:0] n1, output reg [ 3:0] n2, output reg [ 3:0] n3, // Notes.
    output reg [ 2:0] a0, output reg [ 2:0] a1, output reg [ 2:0] a2, output reg [ 2:0] a3  // Amplitude (bit-shift).
);

    localparam [63:0] SRM = 314687500; // clk/800*10000
    // (x10000 is applied to frequencies below, for better precision)
    localparam [63:0] FR = SRM/2; // F_ rounding factor.

    // Why *65536? See prod0...
    localparam C   = 0;
    localparam Cs  = 1;
    localparam D   = 2;
    localparam Ds  = 3;
    localparam E   = 4;
    localparam F   = 5;
    localparam Fs  = 6;
    localparam G   = 7;
    localparam Gs  = 8;
    localparam A   = 9;
    localparam As  = 10;
    localparam B   = 11;
    localparam R   = 15;
    always @(*) begin
        casez (t[13:3]) // ~32.54ms granularity, and up to 4096 events: ~133 seconds. NOTE: 32 events is a little over 1 second.
            // 1st 16 notes (0.5s) are C4, and subsequent are just a major scale up to C5:
            11'h?0?: begin o0= 3; n0=C; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?1?: begin o0= 3; n0=D; a0=1; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?2?: begin o0= 3; n0=E; a0=2; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?3?: begin o0= 3; n0=F; a0=3; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?4?: begin o0= 3; n0=G; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?5?: begin o0= 3; n0=A; a0=1; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?6?: begin o0= 3; n0=B; a0=2; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            11'h?7?: begin o0= 4; n0=C; a0=3; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
            // Then a chord for the rest of the time...
            default: begin o0= 4; n0=C; a0=4; /* o1= 4; n1= R; */ end
            // Because most significant nibble is also covered by '?', the above sequence should also repeat continuously.
        endcase
    end

    assign o1 = o0;
    assign n1 = n0;
    assign a1 = 1;

    assign n2 = C;
    assign o2 = 1;
    assign a2 = 0;
    assign n3 = C;
    assign o3 = 2;
    assign a3 = 0;

endmodule

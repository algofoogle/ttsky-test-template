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

    wire [34:0] prod0 = gate0 ? 0 : ( t * (note_lut(n0, o0)+{d0,1'b0}));
    wire [34:0] prod1 = gate1 ? 0 : ( t * (note_lut(n1, o1)+{d1,1'b0}));
    wire [34:0] prod2 = gate2 ? 0 : ( t * (note_lut(n2, o2)+{d2,1'b0}));
    wire [34:0] prod3 = gate3 ? 0 : ( t * (note_lut(n3, o3)+{d3,1'b0}));

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

    function [7:0] saw8;
        input [8:0] ph;
        saw8 = ph[8:1];
    endfunction

    function [7:0] square8;
        input [8:0] ph;
        square8 = {8{ph[8]}};
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

    wire g0 = a0 >= 4;
    wire g1 = 0; //a1 >= 4;
    wire g2 = 0; //a2 >= 4;
    wire g3 = 0; //a3 >= 4;

    wire [9:0] sample_wide =
        {2'b00, {8{~g0}} & tri8(prod0[16:8])>>a0} + //>>a0} +
        {2'b00, {8{~g1}} & tri8(prod1[16:8])>>a1} + //>>a1} +
        {2'b00, {8{~g2}} & saw8(prod2[16:8])>>a2}/* + //>>a2} +
        {2'b00, {8{~g3}} & saw8(prod3[16:8])>>a3}*/; //>>a3};
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
    wire d0;
    wire d1;
    wire d2;
    wire d3;

    sequencer musical_events(
        .clk(clk),
        .reset(reset),
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
        .a3(a3),
        .d0(d0),
        .d1(d1),
        .d2(d2),
        .d3(d3)
    );

endmodule


module sequencer(
    input clk,
    input reset,
    input [13:0] t, // ~8.135ms granularity.
    output reg [ 2:0] o0, output reg [ 2:0] o1, output reg [ 2:0] o2, output reg [ 2:0] o3, // Octaves.
    output reg [ 3:0] n0, output reg [ 3:0] n1, output reg [ 3:0] n2, output reg [ 3:0] n3, // Notes.
    output reg [ 2:0] a0, output reg [ 2:0] a1, output reg [ 2:0] a2, output reg [ 2:0] a3, // Amplitude (bit-shift).
    output reg        d0, output reg        d1, output reg        d2, output reg        d3  // Detune.
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
    localparam _   = 15;

    reg [2:0] upper_frame;
    reg last_t7;
    always @(posedge clk) begin
        last_t7 <= reset ? 0 : t[7];
    end

    reg [1:0] act;

    always @(posedge clk) begin
        if (reset) begin
            upper_frame <= 0;
            act <= 0;
        end else if (last_t7 && ~t[7])
            if (upper_frame == 5) begin
                upper_frame <= 0;
                act <= act + 1;
            end else
                upper_frame <= upper_frame + 1;
    end

    wire [11:0] timeslice = {1'b0,upper_frame,t[7:0]};

    always @(*) begin
        n0 = _; n1 = _; n2 = _; n3 = _;
        o0 = 0; o1 = 0; o2 = 0; o3 = 0;
        a0 = 0; a1 = 0; a2 = 0; a3 = 0;
        d0 = 0; d1 = 0; d2 = 0; d3 = 0;
        casez (timeslice)
        // Track 0 - Beat melody.
            12'h00?: begin n0 = B ;    o0 = 3; end    // START
            12'h01?: begin n0 = B ;    o0 = 3; end
            12'h02?: begin n0 = B ;    o0 = 3; end
            12'h03?: begin n0 = B ;    o0 = 3; end
            12'h04?: begin n0 = B ;    o0 = 3; end    // START
            12'h05?: begin n0 = B ;    o0 = 3; end
            12'h06?: begin n0 = _ ;    o0 = 0; end
            12'h07?: begin n0 = _ ;    o0 = 0; end
            12'h08?: begin n0 = _ ;    o0 = 0; end
            12'h09?: begin n0 = _ ;    o0 = 0; end
            12'h0A?: begin n0 = B ;    o0 = 3; end    // START
            12'h0B?: begin n0 = B ;    o0 = 3; end
            12'h0C?: begin n0 = B ;    o0 = 3; end
            12'h0D?: begin n0 = B ;    o0 = 3; end
            12'h0E?: begin n0 = _ ;    o0 = 0; end
            12'h0F?: begin n0 = _ ;    o0 = 0; end
            12'h10?: begin n0 = _ ;    o0 = 0; end
            12'h11?: begin n0 = _ ;    o0 = 0; end
            12'h12?: begin n0 = Cs;    o0 = 4; end    // START
            12'h13?: begin n0 = Cs;    o0 = 4; end
            12'h14?: begin n0 = _ ;    o0 = 0; end
            12'h15?: begin n0 = _ ;    o0 = 0; end
            12'h16?: begin n0 = _ ;    o0 = 0; end
            12'h17?: begin n0 = _ ;    o0 = 0; end
            12'h18?: begin n0 = D ;    o0 = 4; end    // START
            12'h19?: begin n0 = D ;    o0 = 4; end
            12'h1A?: begin n0 = D ;    o0 = 4; end
            12'h1B?: begin n0 = D ;    o0 = 4; end
            12'h1C?: begin n0 = D ;    o0 = 4; end    // START
            12'h1D?: begin n0 = D ;    o0 = 4; end
            12'h1E?: begin n0 = _ ;    o0 = 0; end
            12'h1F?: begin n0 = _ ;    o0 = 0; end
            12'h20?: begin n0 = _ ;    o0 = 0; end
            12'h21?: begin n0 = _ ;    o0 = 0; end
            12'h22?: begin n0 = D ;    o0 = 4; end    // START
            12'h23?: begin n0 = D ;    o0 = 4; end
            12'h24?: begin n0 = D ;    o0 = 4; end
            12'h25?: begin n0 = D ;    o0 = 4; end
            12'h26?: begin n0 = _ ;    o0 = 0; end
            12'h27?: begin n0 = _ ;    o0 = 0; end
            12'h28?: begin n0 = _ ;    o0 = 0; end
            12'h29?: begin n0 = _ ;    o0 = 0; end
            12'h2A?: begin n0 = E ;    o0 = 4; end    // START
            12'h2B?: begin n0 = E ;    o0 = 4; end
            12'h2C?: begin n0 = _ ;    o0 = 0; end
            12'h2D?: begin n0 = _ ;    o0 = 0; end
            12'h2E?: begin n0 = _ ;    o0 = 0; end
            12'h2F?: begin n0 = _ ;    o0 = 0; end
            12'h30?: begin n0 = Cs;    o0 = 4; end    // START
            12'h31?: begin n0 = Cs;    o0 = 4; end
            12'h32?: begin n0 = Cs;    o0 = 4; end
            12'h33?: begin n0 = Cs;    o0 = 4; end
            12'h34?: begin n0 = Cs;    o0 = 4; end    // START
            12'h35?: begin n0 = Cs;    o0 = 4; end
            12'h36?: begin n0 = _ ;    o0 = 0; end
            12'h37?: begin n0 = _ ;    o0 = 0; end
            12'h38?: begin n0 = _ ;    o0 = 0; end
            12'h39?: begin n0 = _ ;    o0 = 0; end
            12'h3A?: begin n0 = Cs;    o0 = 4; end    // START
            12'h3B?: begin n0 = Cs;    o0 = 4; end
            12'h3C?: begin n0 = Cs;    o0 = 4; end
            12'h3D?: begin n0 = Cs;    o0 = 4; end
            12'h3E?: begin n0 = _ ;    o0 = 0; end
            12'h3F?: begin n0 = _ ;    o0 = 0; end
            12'h40?: begin n0 = _ ;    o0 = 0; end
            12'h41?: begin n0 = _ ;    o0 = 0; end
            12'h42?: begin n0 = A ;    o0 = 3; end    // START
            12'h43?: begin n0 = A ;    o0 = 3; end
            12'h44?: begin n0 = _ ;    o0 = 0; end
            12'h45?: begin n0 = _ ;    o0 = 0; end
            12'h46?: begin n0 = _ ;    o0 = 0; end
            12'h47?: begin n0 = _ ;    o0 = 0; end
            12'h48?: begin n0 = G ;    o0 = 3; end    // START
            12'h49?: begin n0 = G ;    o0 = 3; end
            12'h4A?: begin n0 = G ;    o0 = 3; end
            12'h4B?: begin n0 = G ;    o0 = 3; end
            12'h4C?: begin n0 = G ;    o0 = 3; end    // START
            12'h4D?: begin n0 = G ;    o0 = 3; end
            12'h4E?: begin n0 = _ ;    o0 = 0; end
            12'h4F?: begin n0 = _ ;    o0 = 0; end
            12'h50?: begin n0 = _ ;    o0 = 0; end
            12'h51?: begin n0 = _ ;    o0 = 0; end
            12'h52?: begin n0 = Fs;    o0 = 3; end    // START
            12'h53?: begin n0 = Fs;    o0 = 3; end
            12'h54?: begin n0 = Cs;    o0 = 4; end    // START
            12'h55?: begin n0 = Cs;    o0 = 4; end
            12'h56?: begin n0 = _ ;    o0 = 0; end
            12'h57?: begin n0 = _ ;    o0 = 0; end
            12'h58?: begin n0 = _ ;    o0 = 0; end
            12'h59?: begin n0 = _ ;    o0 = 0; end
            12'h5A?: begin n0 = D ;    o0 = 4; end    // START
            12'h5B?: begin n0 = D ;    o0 = 4; end
            12'h5C?: begin n0 = _ ;    o0 = 0; end
            12'h5D?: begin n0 = _ ;    o0 = 0; end
            12'h5E?: begin n0 = _ ;    o0 = 0; end
            12'h5F?: begin n0 = _ ;    o0 = 0; end
            12'h60?: begin n0 = _ ;    o0 = 0; end
        endcase

        casez (timeslice)
        // Track 1 - Scales.
            12'h00?: begin n1 = B ;    o1 = 2; end    // START
            12'h01?: begin n1 = B ;    o1 = 2; end
            12'h02?: begin n1 = D ;    o1 = 3; end    // START
            12'h03?: begin n1 = D ;    o1 = 3; end
            12'h04?: begin n1 = Fs;    o1 = 3; end    // START
            12'h05?: begin n1 = Fs;    o1 = 3; end
            12'h06?: begin n1 = D ;    o1 = 3; end    // START
            12'h07?: begin n1 = D ;    o1 = 3; end
            12'h08?: begin n1 = B ;    o1 = 2; end    // START
            12'h09?: begin n1 = B ;    o1 = 2; end
            12'h0A?: begin n1 = D ;    o1 = 3; end    // START
            12'h0B?: begin n1 = D ;    o1 = 3; end
            12'h0C?: begin n1 = Fs;    o1 = 3; end    // START
            12'h0D?: begin n1 = Fs;    o1 = 3; end
            12'h0E?: begin n1 = D ;    o1 = 3; end    // START
            12'h0F?: begin n1 = D ;    o1 = 3; end
            12'h10?: begin n1 = B ;    o1 = 2; end    // START
            12'h11?: begin n1 = B ;    o1 = 2; end
            12'h12?: begin n1 = D ;    o1 = 3; end    // START
            12'h13?: begin n1 = D ;    o1 = 3; end
            12'h14?: begin n1 = Fs;    o1 = 3; end    // START
            12'h15?: begin n1 = Fs;    o1 = 3; end
            12'h16?: begin n1 = D ;    o1 = 3; end    // START
            12'h17?: begin n1 = D ;    o1 = 3; end
            12'h18?: begin n1 = A ;    o1 = 2; end    // START
            12'h19?: begin n1 = A ;    o1 = 2; end
            12'h1A?: begin n1 = D ;    o1 = 3; end    // START
            12'h1B?: begin n1 = D ;    o1 = 3; end
            12'h1C?: begin n1 = Fs;    o1 = 3; end    // START
            12'h1D?: begin n1 = Fs;    o1 = 3; end
            12'h1E?: begin n1 = D ;    o1 = 3; end    // START
            12'h1F?: begin n1 = D ;    o1 = 3; end
            12'h20?: begin n1 = A ;    o1 = 2; end    // START
            12'h21?: begin n1 = A ;    o1 = 2; end
            12'h22?: begin n1 = D ;    o1 = 3; end    // START
            12'h23?: begin n1 = D ;    o1 = 3; end
            12'h24?: begin n1 = Fs;    o1 = 3; end    // START
            12'h25?: begin n1 = Fs;    o1 = 3; end
            12'h26?: begin n1 = D ;    o1 = 3; end    // START
            12'h27?: begin n1 = D ;    o1 = 3; end
            12'h28?: begin n1 = A ;    o1 = 2; end    // START
            12'h29?: begin n1 = A ;    o1 = 2; end
            12'h2A?: begin n1 = D ;    o1 = 3; end    // START
            12'h2B?: begin n1 = D ;    o1 = 3; end
            12'h2C?: begin n1 = Fs;    o1 = 3; end    // START
            12'h2D?: begin n1 = Fs;    o1 = 3; end
            12'h2E?: begin n1 = D ;    o1 = 3; end    // START
            12'h2F?: begin n1 = D ;    o1 = 3; end
            12'h30?: begin n1 = Cs;    o1 = 3; end    // START
            12'h31?: begin n1 = Cs;    o1 = 3; end
            12'h32?: begin n1 = E ;    o1 = 3; end    // START
            12'h33?: begin n1 = E ;    o1 = 3; end
            12'h34?: begin n1 = A ;    o1 = 3; end    // START
            12'h35?: begin n1 = A ;    o1 = 3; end
            12'h36?: begin n1 = E ;    o1 = 3; end    // START
            12'h37?: begin n1 = E ;    o1 = 3; end
            12'h38?: begin n1 = Cs;    o1 = 3; end    // START
            12'h39?: begin n1 = Cs;    o1 = 3; end
            12'h3A?: begin n1 = A ;    o1 = 2; end    // START
            12'h3B?: begin n1 = A ;    o1 = 2; end
            12'h3C?: begin n1 = Cs;    o1 = 3; end    // START
            12'h3D?: begin n1 = Cs;    o1 = 3; end
            12'h3E?: begin n1 = A ;    o1 = 2; end    // START
            12'h3F?: begin n1 = A ;    o1 = 2; end
            12'h40?: begin n1 = E ;    o1 = 2; end    // START
            12'h41?: begin n1 = E ;    o1 = 2; end
            12'h42?: begin n1 = A ;    o1 = 2; end    // START
            12'h43?: begin n1 = A ;    o1 = 2; end
            12'h44?: begin n1 = Cs;    o1 = 3; end    // START
            12'h45?: begin n1 = Cs;    o1 = 3; end
            12'h46?: begin n1 = E ;    o1 = 3; end    // START
            12'h47?: begin n1 = E ;    o1 = 3; end
            12'h48?: begin n1 = Cs;    o1 = 3; end    // START
            12'h49?: begin n1 = Cs;    o1 = 3; end
            12'h4A?: begin n1 = D ;    o1 = 3; end    // START
            12'h4B?: begin n1 = D ;    o1 = 3; end
            12'h4C?: begin n1 = E ;    o1 = 3; end    // START
            12'h4D?: begin n1 = E ;    o1 = 3; end
            12'h4E?: begin n1 = Fs;    o1 = 3; end    // START
            12'h4F?: begin n1 = Fs;    o1 = 3; end
            12'h50?: begin n1 = E ;    o1 = 3; end    // START
            12'h51?: begin n1 = E ;    o1 = 3; end
            12'h52?: begin n1 = D ;    o1 = 3; end    // START
            12'h53?: begin n1 = D ;    o1 = 3; end
            12'h54?: begin n1 = Cs;    o1 = 3; end    // START
            12'h55?: begin n1 = Cs;    o1 = 3; end
            12'h56?: begin n1 = B ;    o1 = 2; end    // START
            12'h57?: begin n1 = B ;    o1 = 2; end
            12'h58?: begin n1 = As;    o1 = 2; end    // START
            12'h59?: begin n1 = As;    o1 = 2; end
            12'h5A?: begin n1 = D ;    o1 = 3; end    // START
            12'h5B?: begin n1 = D ;    o1 = 3; end
            12'h5C?: begin n1 = Cs;    o1 = 3; end    // START
            12'h5D?: begin n1 = Cs;    o1 = 3; end
            12'h5E?: begin n1 = D ;    o1 = 3; end    // START
            12'h5F?: begin n1 = D ;    o1 = 3; end
        endcase

    // // Track 2 -- DRUMS
    //     12'h00?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h01?: begin n2 = _ ;    o2 = 0; end
    //     12'h02?: begin n2 = _ ;    o2 = 0; end
    //     12'h03?: begin n2 = _ ;    o2 = 0; end
    //     12'h04?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h05?: begin n2 = _ ;    o2 = 0; end
    //     12'h06?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h07?: begin n2 = _ ;    o2 = 0; end
    //     12'h08?: begin n2 = _ ;    o2 = 0; end
    //     12'h09?: begin n2 = _ ;    o2 = 0; end
    //     12'h0A?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h0B?: begin n2 = _ ;    o2 = 0; end
    //     12'h0C?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h0D?: begin n2 = _ ;    o2 = 0; end
    //     12'h0E?: begin n2 = _ ;    o2 = 0; end
    //     12'h0F?: begin n2 = _ ;    o2 = 0; end
    //     12'h10?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h11?: begin n2 = _ ;    o2 = 0; end
    //     12'h12?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h13?: begin n2 = _ ;    o2 = 0; end
    //     12'h14?: begin n2 = _ ;    o2 = 0; end
    //     12'h15?: begin n2 = _ ;    o2 = 0; end
    //     12'h16?: begin n2 = _ ;    o2 = 0; end
    //     12'h17?: begin n2 = _ ;    o2 = 0; end
    //     12'h18?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h19?: begin n2 = _ ;    o2 = 0; end
    //     12'h1A?: begin n2 = _ ;    o2 = 0; end
    //     12'h1B?: begin n2 = _ ;    o2 = 0; end
    //     12'h1C?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h1D?: begin n2 = _ ;    o2 = 0; end
    //     12'h1E?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h1F?: begin n2 = _ ;    o2 = 0; end
    //     12'h20?: begin n2 = _ ;    o2 = 0; end
    //     12'h21?: begin n2 = _ ;    o2 = 0; end
    //     12'h22?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h23?: begin n2 = _ ;    o2 = 0; end
    //     12'h24?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h25?: begin n2 = _ ;    o2 = 0; end
    //     12'h26?: begin n2 = _ ;    o2 = 0; end
    //     12'h27?: begin n2 = _ ;    o2 = 0; end
    //     12'h28?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h29?: begin n2 = _ ;    o2 = 0; end
    //     12'h2A?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h2B?: begin n2 = _ ;    o2 = 0; end
    //     12'h2C?: begin n2 = _ ;    o2 = 0; end
    //     12'h2D?: begin n2 = _ ;    o2 = 0; end
    //     12'h2E?: begin n2 = _ ;    o2 = 0; end
    //     12'h2F?: begin n2 = _ ;    o2 = 0; end
    //     12'h30?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h31?: begin n2 = _ ;    o2 = 0; end
    //     12'h32?: begin n2 = _ ;    o2 = 0; end
    //     12'h33?: begin n2 = _ ;    o2 = 0; end
    //     12'h34?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h35?: begin n2 = _ ;    o2 = 0; end
    //     12'h36?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h37?: begin n2 = _ ;    o2 = 0; end
    //     12'h38?: begin n2 = _ ;    o2 = 0; end
    //     12'h39?: begin n2 = _ ;    o2 = 0; end
    //     12'h3A?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h3B?: begin n2 = _ ;    o2 = 0; end
    //     12'h3C?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h3D?: begin n2 = _ ;    o2 = 0; end
    //     12'h3E?: begin n2 = _ ;    o2 = 0; end
    //     12'h3F?: begin n2 = _ ;    o2 = 0; end
    //     12'h40?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h41?: begin n2 = _ ;    o2 = 0; end
    //     12'h42?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h43?: begin n2 = _ ;    o2 = 0; end
    //     12'h44?: begin n2 = _ ;    o2 = 0; end
    //     12'h45?: begin n2 = _ ;    o2 = 0; end
    //     12'h46?: begin n2 = _ ;    o2 = 0; end
    //     12'h47?: begin n2 = _ ;    o2 = 0; end
    //     12'h48?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h49?: begin n2 = _ ;    o2 = 0; end
    //     12'h4A?: begin n2 = _ ;    o2 = 0; end
    //     12'h4B?: begin n2 = _ ;    o2 = 0; end
    //     12'h4C?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h4D?: begin n2 = _ ;    o2 = 0; end
    //     12'h4E?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h4F?: begin n2 = _ ;    o2 = 0; end
    //     12'h50?: begin n2 = _ ;    o2 = 0; end
    //     12'h51?: begin n2 = _ ;    o2 = 0; end
    //     12'h52?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h53?: begin n2 = _ ;    o2 = 0; end
    //     12'h54?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h55?: begin n2 = _ ;    o2 = 0; end
    //     12'h56?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h57?: begin n2 = _ ;    o2 = 0; end
    //     12'h58?: begin n2 = B ;    o2 = 2; end    // START
    //     12'h59?: begin n2 = _ ;    o2 = 0; end
    //     12'h5A?: begin n2 = E ;    o2 = 4; end    // START
    //     12'h5B?: begin n2 = _ ;    o2 = 0; end
    //     12'h5C?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h5D?: begin n2 = _ ;    o2 = 0; end
    //     12'h5E?: begin n2 = D ;    o2 = 3; end    // START
    //     12'h5F?: begin n2 = _ ;    o2 = 0; end
    //     12'h60?: begin n2 = _ ;    o2 = 0; end

        // casez (timeslice)
        // // Track 2 -- Slow harmony.
        //     12'h00?: begin n2 = B ;    o2 = 4; end    // START
        //     12'h01?: begin n2 = B ;    o2 = 4; end
        //     12'h02?: begin n2 = B ;    o2 = 4; end
        //     12'h03?: begin n2 = B ;    o2 = 4; end
        //     12'h04?: begin n2 = B ;    o2 = 4; end
        //     12'h05?: begin n2 = B ;    o2 = 4; end
        //     12'h06?: begin n2 = B ;    o2 = 4; end
        //     12'h07?: begin n2 = B ;    o2 = 4; end
        //     12'h08?: begin n2 = B ;    o2 = 4; end
        //     12'h09?: begin n2 = B ;    o2 = 4; end
        //     12'h0A?: begin n2 = B ;    o2 = 4; end
        //     12'h0B?: begin n2 = B ;    o2 = 4; end
        //     12'h0C?: begin n2 = B ;    o2 = 4; end
        //     12'h0D?: begin n2 = B ;    o2 = 4; end
        //     12'h0E?: begin n2 = B ;    o2 = 4; end
        //     12'h0F?: begin n2 = B ;    o2 = 4; end
        //     12'h10?: begin n2 = B ;    o2 = 4; end
        //     12'h11?: begin n2 = B ;    o2 = 4; end
        //     12'h12?: begin n2 = Cs;    o2 = 5; end    // START
        //     12'h13?: begin n2 = Cs;    o2 = 5; end
        //     12'h14?: begin n2 = Cs;    o2 = 5; end
        //     12'h15?: begin n2 = Cs;    o2 = 5; end
        //     12'h16?: begin n2 = Cs;    o2 = 5; end
        //     12'h17?: begin n2 = Cs;    o2 = 5; end
        //     12'h18?: begin n2 = D ;    o2 = 5; end    // START
        //     12'h19?: begin n2 = D ;    o2 = 5; end
        //     12'h1A?: begin n2 = D ;    o2 = 5; end
        //     12'h1B?: begin n2 = D ;    o2 = 5; end
        //     12'h1C?: begin n2 = D ;    o2 = 5; end
        //     12'h1D?: begin n2 = D ;    o2 = 5; end
        //     12'h1E?: begin n2 = D ;    o2 = 5; end
        //     12'h1F?: begin n2 = D ;    o2 = 5; end
        //     12'h20?: begin n2 = D ;    o2 = 5; end
        //     12'h21?: begin n2 = D ;    o2 = 5; end
        //     12'h22?: begin n2 = D ;    o2 = 5; end
        //     12'h23?: begin n2 = D ;    o2 = 5; end
        //     12'h24?: begin n2 = D ;    o2 = 5; end
        //     12'h25?: begin n2 = D ;    o2 = 5; end
        //     12'h26?: begin n2 = D ;    o2 = 5; end
        //     12'h27?: begin n2 = D ;    o2 = 5; end
        //     12'h28?: begin n2 = D ;    o2 = 5; end
        //     12'h29?: begin n2 = D ;    o2 = 5; end
        //     12'h2A?: begin n2 = D ;    o2 = 5; end    // START
        //     12'h2B?: begin n2 = D ;    o2 = 5; end
        //     12'h2C?: begin n2 = D ;    o2 = 5; end
        //     12'h2D?: begin n2 = D ;    o2 = 5; end
        //     12'h2E?: begin n2 = D ;    o2 = 5; end
        //     12'h2F?: begin n2 = D ;    o2 = 5; end
        //     12'h30?: begin n2 = E ;    o2 = 5; end    // START
        //     12'h31?: begin n2 = E ;    o2 = 5; end
        //     12'h32?: begin n2 = E ;    o2 = 5; end
        //     12'h33?: begin n2 = E ;    o2 = 5; end
        //     12'h34?: begin n2 = E ;    o2 = 5; end
        //     12'h35?: begin n2 = E ;    o2 = 5; end
        //     12'h36?: begin n2 = E ;    o2 = 5; end
        //     12'h37?: begin n2 = E ;    o2 = 5; end
        //     12'h38?: begin n2 = E ;    o2 = 5; end
        //     12'h39?: begin n2 = E ;    o2 = 5; end
        //     12'h3A?: begin n2 = E ;    o2 = 5; end
        //     12'h3B?: begin n2 = E ;    o2 = 5; end
        //     12'h3C?: begin n2 = E ;    o2 = 5; end
        //     12'h3D?: begin n2 = E ;    o2 = 5; end
        //     12'h3E?: begin n2 = E ;    o2 = 5; end
        //     12'h3F?: begin n2 = E ;    o2 = 5; end
        //     12'h40?: begin n2 = E ;    o2 = 5; end
        //     12'h41?: begin n2 = E ;    o2 = 5; end
        //     12'h42?: begin n2 = D ;    o2 = 5; end    // START
        //     12'h43?: begin n2 = D ;    o2 = 5; end
        //     12'h44?: begin n2 = D ;    o2 = 5; end
        //     12'h45?: begin n2 = D ;    o2 = 5; end
        //     12'h46?: begin n2 = D ;    o2 = 5; end
        //     12'h47?: begin n2 = D ;    o2 = 5; end
        //     12'h48?: begin n2 = Cs;    o2 = 5; end    // START
        //     12'h49?: begin n2 = Cs;    o2 = 5; end
        //     12'h4A?: begin n2 = Cs;    o2 = 5; end
        //     12'h4B?: begin n2 = Cs;    o2 = 5; end
        //     12'h4C?: begin n2 = Cs;    o2 = 5; end
        //     12'h4D?: begin n2 = Cs;    o2 = 5; end
        //     12'h4E?: begin n2 = Cs;    o2 = 5; end
        //     12'h4F?: begin n2 = Cs;    o2 = 5; end
        //     12'h50?: begin n2 = Cs;    o2 = 5; end
        //     12'h51?: begin n2 = Cs;    o2 = 5; end
        //     12'h52?: begin n2 = Cs;    o2 = 5; end
        //     12'h53?: begin n2 = Cs;    o2 = 5; end
        //     12'h54?: begin n2 = Cs;    o2 = 5; end
        //     12'h55?: begin n2 = Cs;    o2 = 5; end
        //     12'h56?: begin n2 = Cs;    o2 = 5; end
        //     12'h57?: begin n2 = Cs;    o2 = 5; end
        //     12'h58?: begin n2 = Cs;    o2 = 5; end
        //     12'h59?: begin n2 = Cs;    o2 = 5; end
        //     12'h5A?: begin n2 = As;    o2 = 4; end    // START
        //     12'h5B?: begin n2 = As;    o2 = 4; end
        //     12'h5C?: begin n2 = As;    o2 = 4; end
        //     12'h5D?: begin n2 = As;    o2 = 4; end
        //     12'h5E?: begin n2 = As;    o2 = 4; end
        //     12'h5F?: begin n2 = As;    o2 = 4; end
        // endcase

        // casez (timeslice)
        // // Track 3 -- Medium harmony.
        //     12'h00?: begin n3 = Fs;    o3 = 5; end    // START
        //     12'h01?: begin n3 = Fs;    o3 = 5; end
        //     12'h02?: begin n3 = Fs;    o3 = 5; end
        //     12'h03?: begin n3 = Fs;    o3 = 5; end
        //     12'h04?: begin n3 = Fs;    o3 = 5; end
        //     12'h05?: begin n3 = Fs;    o3 = 5; end
        //     12'h06?: begin n3 = E ;    o3 = 5; end    // START
        //     12'h07?: begin n3 = E ;    o3 = 5; end
        //     12'h08?: begin n3 = E ;    o3 = 5; end
        //     12'h09?: begin n3 = E ;    o3 = 5; end
        //     12'h0A?: begin n3 = E ;    o3 = 5; end
        //     12'h0B?: begin n3 = E ;    o3 = 5; end
        //     12'h0C?: begin n3 = D ;    o3 = 5; end    // START
        //     12'h0D?: begin n3 = D ;    o3 = 5; end
        //     12'h0E?: begin n3 = D ;    o3 = 5; end
        //     12'h0F?: begin n3 = D ;    o3 = 5; end
        //     12'h10?: begin n3 = D ;    o3 = 5; end
        //     12'h11?: begin n3 = D ;    o3 = 5; end
        //     12'h12?: begin n3 = Fs;    o3 = 5; end    // START
        //     12'h13?: begin n3 = Fs;    o3 = 5; end
        //     12'h14?: begin n3 = Fs;    o3 = 5; end
        //     12'h15?: begin n3 = Fs;    o3 = 5; end
        //     12'h16?: begin n3 = Fs;    o3 = 5; end
        //     12'h17?: begin n3 = Fs;    o3 = 5; end
        //     12'h18?: begin n3 = E ;    o3 = 5; end    // START
        //     12'h19?: begin n3 = E ;    o3 = 5; end
        //     12'h1A?: begin n3 = E ;    o3 = 5; end
        //     12'h1B?: begin n3 = E ;    o3 = 5; end
        //     12'h1C?: begin n3 = E ;    o3 = 5; end
        //     12'h1D?: begin n3 = E ;    o3 = 5; end
        //     12'h1E?: begin n3 = _ ;    o3 = 0; end
        //     12'h1F?: begin n3 = _ ;    o3 = 0; end
        //     12'h20?: begin n3 = _ ;    o3 = 0; end
        //     12'h21?: begin n3 = _ ;    o3 = 0; end
        //     12'h22?: begin n3 = _ ;    o3 = 0; end
        //     12'h23?: begin n3 = _ ;    o3 = 0; end
        //     12'h24?: begin n3 = Fs;    o3 = 5; end    // START
        //     12'h25?: begin n3 = Fs;    o3 = 5; end
        //     12'h26?: begin n3 = Fs;    o3 = 5; end
        //     12'h27?: begin n3 = Fs;    o3 = 5; end
        //     12'h28?: begin n3 = Fs;    o3 = 5; end
        //     12'h29?: begin n3 = Fs;    o3 = 5; end
        //     12'h2A?: begin n3 = _ ;    o3 = 0; end
        //     12'h2B?: begin n3 = _ ;    o3 = 0; end
        //     12'h2C?: begin n3 = _ ;    o3 = 0; end
        //     12'h2D?: begin n3 = _ ;    o3 = 0; end
        //     12'h2E?: begin n3 = _ ;    o3 = 0; end
        //     12'h2F?: begin n3 = _ ;    o3 = 0; end
        //     12'h30?: begin n3 = G ;    o3 = 5; end    // START
        //     12'h31?: begin n3 = G ;    o3 = 5; end
        //     12'h32?: begin n3 = G ;    o3 = 5; end
        //     12'h33?: begin n3 = G ;    o3 = 5; end
        //     12'h34?: begin n3 = G ;    o3 = 5; end
        //     12'h35?: begin n3 = G ;    o3 = 5; end
        //     12'h36?: begin n3 = A ;    o3 = 5; end    // START
        //     12'h37?: begin n3 = A ;    o3 = 5; end
        //     12'h38?: begin n3 = A ;    o3 = 5; end
        //     12'h39?: begin n3 = A ;    o3 = 5; end
        //     12'h3A?: begin n3 = A ;    o3 = 5; end
        //     12'h3B?: begin n3 = A ;    o3 = 5; end
        //     12'h3C?: begin n3 = G ;    o3 = 5; end    // START
        //     12'h3D?: begin n3 = G ;    o3 = 5; end
        //     12'h3E?: begin n3 = G ;    o3 = 5; end
        //     12'h3F?: begin n3 = G ;    o3 = 5; end
        //     12'h40?: begin n3 = G ;    o3 = 5; end
        //     12'h41?: begin n3 = G ;    o3 = 5; end
        //     12'h42?: begin n3 = Fs;    o3 = 5; end    // START
        //     12'h43?: begin n3 = Fs;    o3 = 5; end
        //     12'h44?: begin n3 = Fs;    o3 = 5; end
        //     12'h45?: begin n3 = Fs;    o3 = 5; end
        //     12'h46?: begin n3 = Fs;    o3 = 5; end
        //     12'h47?: begin n3 = Fs;    o3 = 5; end
        //     12'h48?: begin n3 = E ;    o3 = 5; end    // START
        //     12'h49?: begin n3 = E ;    o3 = 5; end
        //     12'h4A?: begin n3 = E ;    o3 = 5; end
        //     12'h4B?: begin n3 = E ;    o3 = 5; end
        //     12'h4C?: begin n3 = E ;    o3 = 5; end
        //     12'h4D?: begin n3 = E ;    o3 = 5; end
        //     12'h4E?: begin n3 = _ ;    o3 = 0; end
        //     12'h4F?: begin n3 = _ ;    o3 = 0; end
        //     12'h50?: begin n3 = _ ;    o3 = 0; end
        //     12'h51?: begin n3 = _ ;    o3 = 0; end
        //     12'h52?: begin n3 = _ ;    o3 = 0; end
        //     12'h53?: begin n3 = _ ;    o3 = 0; end
        //     12'h54?: begin n3 = Fs;    o3 = 5; end    // START
        //     12'h55?: begin n3 = Fs;    o3 = 5; end
        //     12'h56?: begin n3 = Fs;    o3 = 5; end
        //     12'h57?: begin n3 = Fs;    o3 = 5; end
        //     12'h58?: begin n3 = Fs;    o3 = 5; end
        //     12'h59?: begin n3 = Fs;    o3 = 5; end
        //     12'h5A?: begin n3 = As;    o3 = 5; end    // START
        //     12'h5B?: begin n3 = As;    o3 = 5; end
        //     12'h5C?: begin n3 = As;    o3 = 5; end
        //     12'h5D?: begin n3 = As;    o3 = 5; end
        //     12'h5E?: begin n3 = As;    o3 = 5; end
        //     12'h5F?: begin n3 = As;    o3 = 5; end
        // endcase

        casez (timeslice)
        // Track 0
            12'h03E: begin a0 =  3; end
            12'h05E: begin a0 =  3; end
            12'h0DE: begin a0 =  3; end
            12'h13E: begin a0 =  3; end
            12'h1BE: begin a0 =  3; end
            12'h1DE: begin a0 =  3; end
            12'h25E: begin a0 =  3; end
            12'h2BE: begin a0 =  3; end
            12'h33E: begin a0 =  3; end
            12'h35E: begin a0 =  3; end
            12'h3DE: begin a0 =  3; end
            12'h43E: begin a0 =  3; end
            12'h4BE: begin a0 =  3; end
            12'h4DE: begin a0 =  3; end
            12'h53E: begin a0 =  3; end
            12'h55E: begin a0 =  3; end
            12'h5BE: begin a0 =  3; end

            12'h03F: begin a0 =  7; end
            12'h05F: begin a0 =  7; end
            12'h0DF: begin a0 =  7; end
            12'h13F: begin a0 =  7; end
            12'h1BF: begin a0 =  7; end
            12'h1DF: begin a0 =  7; end
            12'h25F: begin a0 =  7; end
            12'h2BF: begin a0 =  7; end
            12'h33F: begin a0 =  7; end
            12'h35F: begin a0 =  7; end
            12'h3DF: begin a0 =  7; end
            12'h43F: begin a0 =  7; end
            12'h4BF: begin a0 =  7; end
            12'h4DF: begin a0 =  7; end
            12'h53F: begin a0 =  7; end
            12'h55F: begin a0 =  7; end
            12'h5BF: begin a0 =  7; end
        endcase

        casez (timeslice)
        // Track 1
            12'h01E: begin a1 =  3; end
            12'h03E: begin a1 =  3; end
            12'h05E: begin a1 =  3; end
            12'h07E: begin a1 =  3; end
            12'h09E: begin a1 =  3; end
            12'h0BE: begin a1 =  3; end
            12'h0DE: begin a1 =  3; end
            12'h0FE: begin a1 =  3; end
            12'h11E: begin a1 =  3; end
            12'h13E: begin a1 =  3; end
            12'h15E: begin a1 =  3; end
            12'h17E: begin a1 =  3; end
            12'h19E: begin a1 =  3; end
            12'h1BE: begin a1 =  3; end
            12'h1DE: begin a1 =  3; end
            12'h1FE: begin a1 =  3; end
            12'h21E: begin a1 =  3; end
            12'h23E: begin a1 =  3; end
            12'h25E: begin a1 =  3; end
            12'h27E: begin a1 =  3; end
            12'h29E: begin a1 =  3; end
            12'h2BE: begin a1 =  3; end
            12'h2DE: begin a1 =  3; end
            12'h2FE: begin a1 =  3; end
            12'h31E: begin a1 =  3; end
            12'h33E: begin a1 =  3; end
            12'h35E: begin a1 =  3; end
            12'h37E: begin a1 =  3; end
            12'h39E: begin a1 =  3; end
            12'h3BE: begin a1 =  3; end
            12'h3DE: begin a1 =  3; end
            12'h3FE: begin a1 =  3; end
            12'h41E: begin a1 =  3; end
            12'h43E: begin a1 =  3; end
            12'h45E: begin a1 =  3; end
            12'h47E: begin a1 =  3; end
            12'h49E: begin a1 =  3; end
            12'h4BE: begin a1 =  3; end
            12'h4DE: begin a1 =  3; end
            12'h4FE: begin a1 =  3; end
            12'h51E: begin a1 =  3; end
            12'h53E: begin a1 =  3; end
            12'h55E: begin a1 =  3; end
            12'h57E: begin a1 =  3; end
            12'h59E: begin a1 =  3; end
            12'h5BE: begin a1 =  3; end
            12'h5DE: begin a1 =  3; end
            12'h5FE: begin a1 =  3; end

            12'h01F: begin a1 =  7; end
            12'h03F: begin a1 =  7; end
            12'h05F: begin a1 =  7; end
            12'h07F: begin a1 =  7; end
            12'h09F: begin a1 =  7; end
            12'h0BF: begin a1 =  7; end
            12'h0DF: begin a1 =  7; end
            12'h0FF: begin a1 =  7; end
            12'h11F: begin a1 =  7; end
            12'h13F: begin a1 =  7; end
            12'h15F: begin a1 =  7; end
            12'h17F: begin a1 =  7; end
            12'h19F: begin a1 =  7; end
            12'h1BF: begin a1 =  7; end
            12'h1DF: begin a1 =  7; end
            12'h1FF: begin a1 =  7; end
            12'h21F: begin a1 =  7; end
            12'h23F: begin a1 =  7; end
            12'h25F: begin a1 =  7; end
            12'h27F: begin a1 =  7; end
            12'h29F: begin a1 =  7; end
            12'h2BF: begin a1 =  7; end
            12'h2DF: begin a1 =  7; end
            12'h2FF: begin a1 =  7; end
            12'h31F: begin a1 =  7; end
            12'h33F: begin a1 =  7; end
            12'h35F: begin a1 =  7; end
            12'h37F: begin a1 =  7; end
            12'h39F: begin a1 =  7; end
            12'h3BF: begin a1 =  7; end
            12'h3DF: begin a1 =  7; end
            12'h3FF: begin a1 =  7; end
            12'h41F: begin a1 =  7; end
            12'h43F: begin a1 =  7; end
            12'h45F: begin a1 =  7; end
            12'h47F: begin a1 =  7; end
            12'h49F: begin a1 =  7; end
            12'h4BF: begin a1 =  7; end
            12'h4DF: begin a1 =  7; end
            12'h4FF: begin a1 =  7; end
            12'h51F: begin a1 =  7; end
            12'h53F: begin a1 =  7; end
            12'h55F: begin a1 =  7; end
            12'h57F: begin a1 =  7; end
            12'h59F: begin a1 =  7; end
            12'h5BF: begin a1 =  7; end
            12'h5DF: begin a1 =  7; end
            12'h5FF: begin a1 =  7; end
        endcase

    // // Track 2 -- DRUMS
    //     12'h00F: begin a2 =  7; end
    //     12'h04F: begin a2 =  7; end
    //     12'h06F: begin a2 =  7; end
    //     12'h0AF: begin a2 =  7; end
    //     12'h0CF: begin a2 =  7; end
    //     12'h10F: begin a2 =  7; end
    //     12'h12F: begin a2 =  7; end
    //     12'h18F: begin a2 =  7; end
    //     12'h1CF: begin a2 =  7; end
    //     12'h1EF: begin a2 =  7; end
    //     12'h22F: begin a2 =  7; end
    //     12'h24F: begin a2 =  7; end
    //     12'h28F: begin a2 =  7; end
    //     12'h2AF: begin a2 =  7; end
    //     12'h30F: begin a2 =  7; end
    //     12'h34F: begin a2 =  7; end
    //     12'h36F: begin a2 =  7; end
    //     12'h3AF: begin a2 =  7; end
    //     12'h3CF: begin a2 =  7; end
    //     12'h40F: begin a2 =  7; end
    //     12'h42F: begin a2 =  7; end
    //     12'h48F: begin a2 =  7; end
    //     12'h4CF: begin a2 =  7; end
    //     12'h4EF: begin a2 =  7; end
    //     12'h52F: begin a2 =  7; end
    //     12'h54F: begin a2 =  7; end
    //     12'h54F: begin a2 =  7; end
    //     12'h56F: begin a2 =  7; end
    //     12'h58F: begin a2 =  7; end
    //     12'h5AF: begin a2 =  7; end
    //     12'h5CF: begin a2 =  7; end
    //     12'h5EF: begin a2 =  7; end

        // casez (t[12:1])
        // // Track 2
        //     12'h11F: begin a2 =  7; end
        //     12'h17F: begin a2 =  7; end
        //     12'h29F: begin a2 =  7; end
        //     12'h2FF: begin a2 =  7; end
        //     12'h41F: begin a2 =  7; end
        //     12'h47F: begin a2 =  7; end
        //     12'h59F: begin a2 =  7; end
        //     12'h5FF: begin a2 =  7; end
        // endcase

        // casez (t[12:1])
        // // Track 3
        //     12'h05F: begin a3 =  7; end
        //     12'h0BF: begin a3 =  7; end
        //     12'h11F: begin a3 =  7; end
        //     12'h17F: begin a3 =  7; end
        //     12'h1DF: begin a3 =  7; end
        //     12'h29F: begin a3 =  7; end
        //     12'h35F: begin a3 =  7; end
        //     12'h3BF: begin a3 =  7; end
        //     12'h41F: begin a3 =  7; end
        //     12'h47F: begin a3 =  7; end
        //     12'h4DF: begin a3 =  7; end
        //     12'h59F: begin a3 =  7; end
        //     12'h5FF: begin a3 =  7; end
        // endcase

    end

    // reg [1:0] div3;
    // always @(posedge clk) begin
    //     if (reset)
    //         div3 <= 0;
    //     else if (t[8])
    //         div3 <= (div3==2) ? 0 : div3+1;
    // end

    // assign o1 = o0;
    // assign n1 = n0;
    // assign a1 = 3;//a0;
    // assign d1 = 0;


    // always @(*) begin
    //     n0 = C;
    //     a0 = t[5:3]; // Decay.
    //     d0 = 0;
    //     casez (t[13:2])
    //         12'h?0?: begin o0= 2; end
    //         12'h?1?: begin o0= 2; end
    //         12'h?2?: begin o0= 3; end
    //         12'h?3?: begin o0= 3; a0=7; end
    //         12'h?4?: begin o0= 3; end
    //         12'h?5?: begin o0= 2; end
    //         12'h?6?: begin o0= 2; end
    //         12'h?7?: begin o0= 2; end
    //         12'h?8?: begin o0= 2; a0=7; end
    //         12'h?9?: begin o0= 2; end
    //         12'h?A?: begin o0= 3; end
    //         12'h?B?: begin o0= 3; a0=7; end
    //         12'h?C?: begin o0= 3; end
    //         12'h?D?: begin o0= 2; end
    //         12'h?E?: begin o0= 2; end
    //         12'h?F?: begin o0= 2; end
    //         default: begin o0='X; n0=_; a0='X; end
    //     endcase
    //     o1 = o0;
    //     n1 = n0;
    //     a1 = {1'b0,t[5:4]}+3'd2; //3;//a0;
    //     d1 = 0;
    // end

    // always @(*) begin
    //     n2 = _;
    //     a2 = 0;
    //     d2 = 0;
    //     o2 = 4;

    //     a2 = (t[3:2] == 0 || t[3:2] == 3) ? 2 : 1;

    //     casez (t[13:2])
    //         12'b0010_????_?0??: begin n2=E; end
    //         12'b0010_????_?1??: begin n2=G; end

    //         12'b0011_????_?0??: begin n2=F; end
    //         12'b0011_????_?1??: begin n2=A; end

    //         12'b0100_????_?0??: begin n2=As; end
    //         12'b0100_????_?1??: begin n2=D; end

    //         12'b0101_????_?0??: begin n2=C; end
    //         12'b0101_????_?1??: begin n2=E; end

    //         // Faster scales:

    //         12'b0110_????_?00?: begin n2=C; end
    //         12'b0110_????_?01?: begin n2=E; end
    //         12'b0110_????_?10?: begin n2=G; end
    //         12'b0110_????_?11?: begin n2=C; o2=5; end

    //         12'b0111_????_?00?: begin n2=C; end
    //         12'b0111_????_?01?: begin n2=F; end
    //         12'b0111_????_?10?: begin n2=A; end
    //         12'b0111_????_?11?: begin n2=C; o2=5; end

    //         12'b1000_????_?00?: begin n2=D; end
    //         12'b1000_????_?01?: begin n2=F; end
    //         12'b1000_????_?10?: begin n2=As; end
    //         12'b1000_????_?11?: begin n2=D; o2=5; end

    //         12'b1001_????_?00?: begin n2=C; end
    //         12'b1001_????_?01?: begin n2=E; end
    //         12'b1001_????_?10?: begin n2=G; end
    //         12'b1001_????_?11?: begin n2=C; o2=5; end

    //         12'b1100_????_????: begin n2=C; o2=3; a2=2; end



    //         // 12'b0010_????_????: begin n2=Ds; end
    //         // default: begin n2='X; end
    //     endcase
    // end


    // // always @(*) begin
    // //     n3 = _;
    // //     a3 = 0;
    // //     d3 = 0;
    // //     o3 = 4;
    // //     casez (t[13:2])
    // //         12'b1001_????_????: begin n3=C; o3=6; a3=(t[9:7]>=3) ? {1'b1,~t[9:8]} : 3'b100; end
    // //         12'b1010_????_????: begin n3=C; o3=6; a3=3'b100; end
    // //     endcase
    // //     // casez (t[13:2])
    // //     //     12'b0010_????_????: begin n3=G; end
    // //     //     // 12'b0010_????_????: begin n2=Ds; end
    // //     //     // default: begin n2='X; end
    // //     // endcase
    // // end

    // always @(*) begin
    //     n3 = _;
    //     a3 = 0;
    //     d3 = 0;
    //     o3 = 3;
    //     casez (t[13:2])
    //         12'b1001_???0_????: begin n3=C;  a3=~t[9:7]; end
    //         12'b1010_0_???_????: begin n3=C;  o3=3; end
    //         12'b1010_1_???_????: begin n3=As; o3=2; end
    //         12'b1011_0_???_????: begin n3=Ds; o3=2; end
    //         12'b1011_1_???_????: begin n3=F;  o3=2; end

    //         12'b1100_????_????: begin n3=C;  o3=2; end
    //         12'b1101_????_????: begin n3=C;  o3=2; d3=1; end
    //     endcase
    //     // casez (t[13:2])
    //     //     12'b0010_????_????: begin n3=G; end
    //     //     // 12'b0010_????_????: begin n2=Ds; end
    //     //     // default: begin n2='X; end
    //     // endcase
    // end


    // // always @(*) begin
    // //     casez (t[13:3]) // ~32.54ms granularity, and up to 4096 events: ~133 seconds. NOTE: 32 events is a little over 1 second.
    // //         // 1st 16 notes (0.5s) are C4, and subsequent are just a major scale up to C5:
    // //         11'h?0?: begin o0= 3; n0=C; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?1?: begin o0= 3; n0=D; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?2?: begin o0= 3; n0=E; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?3?: begin o0= 3; n0=F; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?4?: begin o0= 3; n0=G; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?5?: begin o0= 3; n0=A; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?6?: begin o0= 3; n0=B; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         11'h?7?: begin o0= 4; n0=C; a0=0; /* o1='X; n1= R; o2='X; o3='X; n2=R; n3=R;*/ end
    // //         // Then a chord for the rest of the time...
    // //         default: begin o0= 4; n0=C; a0=0; /* o1= 4; n1= R; */ end
    // //         // Because most significant nibble is also covered by '?', the above sequence should also repeat continuously.
    // //     endcase
    // // end

    // // assign d1 = t[10];// & ~t[9];

    // // assign {d0,d2,d3} = 3'b000;

    // // assign o1 = o0;
    // // assign n1 = n0;
    // // assign a1 = 1;

    // // assign n2 = C;
    // // assign o2 = 1;
    // // assign a2 = 0;
    // // assign n3 = C;
    // // assign o3 = 2;
    // // assign a3 = 0;

endmodule

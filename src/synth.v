`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */

module synth (
    input  wire clk,
    input  wire rst,
    output reg  dac_out,
    output reg [15:0] raw_out
);
    reg [14:0] mstimer;         // Tracks clocks in order to increment a millisecond counter.
    reg [19:0] ticks;           // Millisecond counter.
    wire tick_trigger = (mstimer == 25175-1);
    reg square;                 // Simple square wave output.
    reg [15:0] square_counter;  // Counter for square wave frequency.
    reg [33:0] clocks;          // Counts total number of clocks.

    // Count clocks:
    always @(posedge clk) begin
        clocks <= (rst) ? 0 : clocks + 1;
    end

    // Simple counter for square wave: 63775/25175000 = ~2.533ms/phase => 1/(2*2.533ms) = 197.37Hz = ~G3
    // However, that was possibly calculated for a flat 25MHz clock (intending to hit 195.9977Hz)
    // so for that we'd need (25175000/195.9977)/2 = ~64223
    localparam CLOCKS_G3 = 16'd64223; // For 25.175MHz clock.
    // localparam CLOCKS_G3 = 16'd63775 // For 25.000MHz clock.
    always @(posedge clk) begin
        if (rst) begin
            square_counter <= 0;
            square <= 0;
        end else if (square_counter == CLOCKS_G3-1) begin
            square <= ~square; 
            square_counter <= 0;
        end else begin
            square_counter <= square_counter + 1;
        end
    end

    // Count milliseconds (in 'ticks'):
    always @(posedge clk) begin
        if (rst) begin
            mstimer <= 0;
            ticks <= 0;
        end else if (tick_trigger) begin
            mstimer <= 0;
            ticks <= ticks + 1;
        end else begin
            mstimer <= mstimer + 1;
        end
    end

    wire [31:0] vtri0_note;
    wire [31:0] vtri1_note;

    // wire [31:0] tri0_phase_inc = ticks[10] ? PHI_C3 : PHI_C4; //<== switch tones every 1024ms
    // vtri0 is raw 16-bit sample output from 1st triangle voice.
    wire [15:0] vtri0;
    triangle_voice voice_tri0(
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri0_note),
        .sample_out(vtri0)
    );
    // vtri1 is raw 16-bit sample output from 2nd triangle voice.
    wire [15:0] vtri1;
    triangle_voice voice_tri1(
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri1_note),
        .sample_out(vtri1)
    );
    //NOTE: The sample_outs above don't change often (nowhere near 25MHz),
    // because they are baesd on phase accumulators that only consider bits 31:15
    // (bit 31 reflects, i.e. folds 30:15, in order to create triangle from sawtooth)
    // and don't reflect their lowest 15 bits (14:0) in their direct output.


    // 0 = 100%
    // 1 = 50%
    // 2 = 25%
    // ...
    // 14 = silence (NOTE: anything above >>8 is basically silent anyway)
    // 15 = always on
    reg decay0trigger;
    reg [6:0] decay0time; // How many ms we need to count before decaying by 1 step.
    reg [3:0] decay0; // The actual attenuation exponent to apply.
    reg [6:0] decay0counter; // Enough for 128ms/step: 

    always @(posedge clk) begin
        if (rst) begin
            decay0 <= 15;
            decay0counter <= 0;
            decay0time <= 50;
        end else if (tick_trigger) begin
            // A millisecond has triggered.
            if (decay0trigger) begin
                // Start a new decay cycle.
                decay0 <= 0;
                decay0counter <= 0;
                decay0time <= 50;
                decay0trigger <= 0;
            end else if (decay0 >= 14) begin
                // Do nothing: We're in a static state.
            end else begin
                if (decay0counter+1 == decay0time) begin //NOTE: Could be (delay0counter==decay0time), supporting a 1ms rate (i.e. decay0time is actual_delay-1).
                    // We hit the decay counter limit.
                    decay0counter <= 0;
                    decay0 <= decay0 + 1; // Decay by 1 step.
                end else begin
                    // Count up towards decay0time limit:
                    decay0counter <= decay0counter + 1;
                end
            end
        end
    end

    // always @(posedge clk) begin
    //     if (rst) begin
    //         decay0trigger <= 0;
    //     end else if (tick_trigger) begin
    //         if (ticks[7:0]==0) begin
    //             // Trigger a decay cycle every 512ms:
    //             decay0trigger <= 1;
    //         end
    //     // end else begin
    //     //     decay0trigger <= 0;
    //     end
    // end

    sequencer music(
        .clk(clk),
        .rst(rst),
        .tick_trigger(tick_trigger),
        .ticks(ticks),
        .vtri0_note(vtri0_note),
        .vtri1_note(vtri1_note)
    );

    reg [15:0] voice1;
    reg [15:0] voice2;
    // reg [15:0] note;
    always @(*) begin
        voice1 = vtri0;
        voice2 = vtri1;
        // note = 0;
        // if (ticks < 100_000) begin
        //     // For first 10 seconds, do a mix of different effects:
        //     // 1st triangle voice is attenuated by 5-bit PWM to change its volume:
        //     //voice1 = (clocks[4:0] < ticks[11:7]) ? vtri0 : 0;
        //     voice1 = 0;
        //     note = (ticks[10]) ? vtri0 : vtri1;
        //     // Apply exponential decay logic to voice2:
        //     if (decay0 == 15)
        //         voice2 = note; // Stays on.
        //     else if (decay0 == 14)
        //         voice2 = 0; // Silent.
        //     else
        //         voice2 = note >> decay0;
        //     // voice2 = vtri1 >> ticks[9:6];
        // end else if (ticks < 12_000) begin
        //     // Only G3 triangle at 50% volume:
        //     voice1 = vtri0;
        //     voice2 = 0;
        // end else if (ticks < 14_000) begin
        //     // Only G3 square at 50% volume:
        //     voice1 = 0;
        //     voice2 = {16{square}};
        // end else begin
        //     // Both the triangle & square (50% volume each) blended:
        //     voice1 = vtri0;
        //     voice2 = {16{square}};
        // end
    end

    // Chop mixer simply switches between 2 voice samples at 25MHz, effectively mixing them:
    chop_mixer mix(
        .clk(clk),
        .rst(rst),
        .ch0(voice1),
        .ch1(voice2),
        .sample_out(raw_out)
    );

    // assign raw_out = (clocks[0]) ? tri0 : {16{square}}; <== Mix triangle and square waves of (about) the same frequency.

    // Convert final (mixed) raw_out sample to 1-bit PDM using sigma-delta DAC (to dac_out):
    sigmadelta_dac dac(
        .clk(clk),
        .rst(rst),
        .sample_in(raw_out),
        .dac_out(dac_out)
    );

endmodule


/* verilator lint_off DECLFILENAME */
module triangle_voice(
    input wire clk,
    input wire rst,
    input [31:0] phase_inc,
    output [15:0] sample_out
);

    reg  [31:0] phase_acc;
    wire [31:0] phase_next = phase_acc + phase_inc;

    // Triangle wave from the phase accumulator:
    // Use folded sawtooth from phase_next.
    // Range is approximately 0..65535 (unsigned).
    assign sample_out =
        phase_next[31] ? ~phase_next[30:15] : phase_next[30:15];

    always @(posedge clk) begin
        if (rst) begin
            phase_acc <= 32'd0;
        end else begin
            phase_acc <= phase_next;
        end
    end

endmodule


// First-order 1-bit sigma-delta DAC:
// Average output density tracks sample_in / 65536.
module sigmadelta_dac(
    input wire clk,
    input wire rst,
    input [15:0] sample_in,
    output reg dac_out
);
    wire [16:0] sd_sum = {1'b0, sd_err} + {1'b0, sample_in};
    reg  [15:0] sd_err;
    always @(posedge clk) begin
        if (rst) begin
            sd_err <= 0;
            dac_out <= 0;
        end else begin
            sd_err <= sd_sum[15:0];
            dac_out <= sd_sum[16];
        end
    end
endmodule


// Mixes input samples by simply chopping between them as fast as possible
// (based on clk):
module chop_mixer(
    input clk,
    input rst,
    input [15:0] ch0,
    input [15:0] ch1,
    output [15:0] sample_out
);
    reg select;
    always @(posedge clk)
        select <= (rst) ? 0 : ~select;
    assign sample_out = select ? ch1 : ch0;
endmodule


module sequencer(
    input clk,
    input rst,
    input tick_trigger,
    input [19:0] ticks,
    output reg [31:0] vtri0_note,
    output reg [31:0] vtri1_note
    // output reg decay0_trigger
);
/* verilator lint_off UNUSEDPARAM */
    // phase_inc = round(note * 2^32 / 25175000)
    localparam PHI_C2   = 32'd11157;

    // C3 octave
    localparam PHI_C3   = 32'd22314;   // C3  target=130.8128 Hz, actual=130.7937666 Hz
    localparam PHI_CS3  = 32'd23647;   // C#3 target=138.5913 Hz, actual=138.6071614 Hz
    localparam PHI_D3   = 32'd25048;   // D3  target=146.8324 Hz, actual=146.8191389 Hz
    localparam PHI_DS3  = 32'd26527;   // D#3 target=155.5635 Hz, actual=155.4883143 Hz
    localparam PHI_E3   = 32'd28115;   // E3  target=164.8138 Hz, actual=164.7963945 Hz
    localparam PHI_F3   = 32'd29777;   // F3  target=174.6141 Hz, actual=174.5382266 Hz
    localparam PHI_FS3  = 32'd31557;   // F#3 target=184.9972 Hz, actual=184.9717170 Hz
    localparam PHI_G3   = 32'd33441;   // G3  target=195.9977 Hz, actual=196.0148045 Hz
    localparam PHI_GS3  = 32'd35430;   // G#3 target=207.6523 Hz, actual=207.6733508 Hz
    localparam PHI_A3   = 32'd37533;   // A3  target=220.0000 Hz, actual=220.0001094 Hz
    localparam PHI_AS3  = 32'd39768;   // A#3 target=233.0819 Hz, actual=233.1005875 Hz
    localparam PHI_B3   = 32'd42131;   // B3  target=246.9417 Hz, actual=246.9513391 Hz

    // C4 octave
    localparam PHI_C4   = 32'd44657;   // C4  target=261.6256 Hz, actual=261.7575170 Hz
    localparam PHI_CS4  = 32'd47293;   // C#4 target=277.1826 Hz, actual=277.2084612 Hz
    localparam PHI_D4   = 32'd50096;   // D4  target=293.6648 Hz, actual=293.6382778 Hz
    localparam PHI_DS4  = 32'd53053;   // D#4 target=311.1270 Hz, actual=310.9707672 Hz
    localparam PHI_E4   = 32'd56207;   // E4  target=329.6276 Hz, actual=329.4579743 Hz
    localparam PHI_F4   = 32'd59583;   // F4  target=349.2282 Hz, actual=349.2464370 Hz
    localparam PHI_FS4  = 32'd63115;   // F#4 target=369.9944 Hz, actual=369.9492954 Hz
    localparam PHI_G4   = 32'd66882;   // G4  target=391.9954 Hz, actual=392.0296091 Hz
    localparam PHI_GS4  = 32'd70876;   // G#4 target=415.3047 Hz, actual=415.4404858 Hz
    localparam PHI_A4   = 32'd75066;   // A4  target=440.0000 Hz, actual=440.0002188 Hz
    localparam PHI_AS4  = 32'd79536;   // A#4 target=466.1638 Hz, actual=466.2011750 Hz
    localparam PHI_B4   = 32'd84254;   // B4  target=493.8833 Hz, actual=493.8557860 Hz

    // C5 octave
    localparam PHI_C5   = 32'd89314;   // C5  target=523.2511 Hz, actual=523.5150340 Hz
    localparam PHI_CS5  = 32'd94614;   // C#5 target=554.3653 Hz, actual=554.5810447 Hz
    localparam PHI_D5   = 32'd100180;  // D5  target=587.3295 Hz, actual=587.2062175 Hz
    localparam PHI_DS5  = 32'd106160;  // D#5 target=622.2540 Hz, actual=622.2580560 Hz
    localparam PHI_E5   = 32'd112416;  // E5  target=659.2551 Hz, actual=658.9276716 Hz
    localparam PHI_F5   = 32'd119163;  // F5  target=698.4565 Hz, actual=698.4752894 Hz
    localparam PHI_FS5  = 32'd126230;  // F#5 target=739.9888 Hz, actual=739.8985908 Hz
    localparam PHI_G5   = 32'd133770;  // G5  target=783.9909 Hz, actual=784.0943872 Hz
    localparam PHI_GS5  = 32'd141754;  // G#5 target=830.6094 Hz, actual=830.8926946 Hz
    localparam PHI_A5   = 32'd150132;  // A5  target=880.0000 Hz, actual=880.0004376 Hz
    localparam PHI_AS5  = 32'd159072;  // A#5 target=932.3275 Hz, actual=932.4023500 Hz
    localparam PHI_B5   = 32'd168471;  // B5  target=987.7666 Hz, actual=987.4946962 Hz
/* verilator lint_on UNUSEDPARAM */

    // always @(posedge clk) begin
    //     if (tick_trigger) begin
    //         case (ticks>>1)
    //             0:      begin   vtri0_note <= PHI_C3; vtri1_note <= PHI_C4; end
    //             200:    begin   vtri0_note <= PHI_C3; vtri1_note <= PHI_D4; end
    //             400:    begin   vtri0_note <= PHI_C3; vtri1_note <= PHI_E4; end
    //             600:    begin   vtri0_note <= PHI_C3; vtri1_note <= PHI_F4; end
    //             800:    begin   vtri0_note <= PHI_D3; vtri1_note <= PHI_G4; end
    //             1000:   begin   vtri0_note <= PHI_D3; vtri1_note <= PHI_G4; end
    //             1200:   begin   vtri0_note <= PHI_D3; vtri1_note <= PHI_G4; end
    //             1400:   begin   vtri0_note <= PHI_D3; vtri1_note <= PHI_G4; end
    //             1600:   begin   vtri0_note <= PHI_F3; vtri1_note <= PHI_F4; end
    //             1800:   begin   vtri0_note <= PHI_F3; vtri1_note <= PHI_G4; end
    //             2000:   begin   vtri0_note <= PHI_F3; vtri1_note <= PHI_A4; end
    //             2200:   begin   vtri0_note <= PHI_F3; vtri1_note <= PHI_B4; end
    //             2400:   begin   vtri0_note <= PHI_C3; vtri1_note <= PHI_C5; end
    //             // default:
    //                 // Nothing.
    //         endcase
    //     end
    // end


    // 334-4333-34-4333

    wire [12:0] t = ticks[19:7];
    // wire [] tt = t[]

    wire fastarp = ticks[4];
    wire arp = ticks[5];

    always @(posedge clk) begin
        if (tick_trigger) begin
            case (t[3:0])
                0:      vtri0_note <= PHI_C2;
                1:                              vtri0_note <= 0;
                //
                //
                //
                4:      vtri0_note <= PHI_C2;
                5:                              vtri0_note <= 0;
                //
                6:      vtri0_note <= PHI_C3;
                7:                              vtri0_note <= 0;
                //
                //
                //
                10:     vtri0_note <= PHI_C3;
                11:                             vtri0_note <= 0;
                //
                12:     vtri0_note <= PHI_C2;
                13:                             vtri0_note <= 0;
                //
                14:     vtri0_note <= PHI_C2;
                15:                             vtri0_note <= 0;
            endcase

            if (t < 32) begin
                vtri1_note <= 0;
            end else if (t < 64) begin
                vtri1_note <= fastarp ? PHI_DS3 : 0;
            end else if (t < 96) begin
                vtri1_note <= arp ? PHI_DS4 : PHI_G4;
            end else if (t < 128) begin
                vtri1_note <= arp ? PHI_D4 : PHI_F4;
            end else if (t < 160) begin
                vtri1_note <= arp ? PHI_D4 : PHI_F4;
            end else if (t < 192) begin
                vtri1_note <= arp ? PHI_A3 : PHI_F4;
            end else begin
                case (ticks[5:4])
                    0:  vtri1_note <= PHI_C4;
                    1:  vtri1_note <= PHI_G4;
                    2:  vtri1_note <= PHI_DS4;
                    3:  vtri1_note <= PHI_C5;
                endcase
            end
            // case (ticks[19:7])
            //     0:      vtri1_note <= 0;
            //     64:     vtri1_note <= PHI_DS3;
            // endcase
        end
    end

endmodule

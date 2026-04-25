`default_nettype none

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */

module synth_v2 (
    input  wire clk,
    input  wire rst,
    output wire [7:0] sample_out
);

    // ------------------------------------------------------------------------
    // Compact timing state
    // ------------------------------------------------------------------------
    // 25.175 MHz / 25175 = 1 kHz, i.e. 1 ms tick
    localparam [14:0] MS_DIV = 25175;
    reg [14:0] ms_divider;

    wire ms_tick = (ms_divider == MS_DIV-1);

    // Replaces the relevant parts of ticks[]:
    //   sub_ms[6:0]    ~= ticks[6:0]
    //   phrase[8:0]    ~= ticks[15:7]
    reg [7:0] sub_ms;
    reg [8:0] phrase;

    always @(posedge clk) begin
        if (rst) begin
            ms_divider <= 15'd0;
            sub_ms     <= 8'd0;
            phrase     <= 9'd0;
        end else if (ms_tick) begin
            ms_divider <= 15'd0;

            if (sub_ms[6:0] == 7'd127) begin
                // sub_ms <= 8'd0;
                phrase <= phrase + 9'd1;
            end
            sub_ms <= sub_ms + 8'd1;
            // end else begin
            //     sub_ms <= sub_ms + 8'd1;
            // end
        end else begin
            ms_divider <= ms_divider + 15'd1;
        end
    end

    wire fastarp = sub_ms[5];
    wire midarp  = sub_ms[6];
    wire arp     = sub_ms[7];

    // ------------------------------------------------------------------------
    // Note table, reduced to only the notes actually used by this sequence.
    // 24-bit phase increment values.
    //
    // These are approximately the old 32-bit values divided by 256.
    // ------------------------------------------------------------------------
    localparam [23:0] PHI_0   = 24'd0;

    localparam [23:0] PHI_C2  = 24'd44;
    localparam [23:0] PHI_C3  = 24'd87;
    localparam [23:0] PHI_DS3 = 24'd104;
    localparam [23:0] PHI_A3  = 24'd147;

    localparam [23:0] PHI_C4  = 24'd174;
    localparam [23:0] PHI_D4  = 24'd196;
    localparam [23:0] PHI_DS4 = 24'd207;
    localparam [23:0] PHI_F4  = 24'd233;
    localparam [23:0] PHI_G4  = 24'd261;

    localparam [23:0] PHI_C5  = 24'd349;

    // ------------------------------------------------------------------------
    // Combinational sequencer
    // No 32-bit registered note outputs.
    // ------------------------------------------------------------------------
    reg [23:0] vtri0_note;
    reg [23:0] vtri1_note;

    always @(*) begin
        // Voice 0 pattern: derived from old case on t[3:0], where t=ticks[19:7]
        case (phrase[3:0])
            4'd0:  vtri0_note = PHI_C2;
            4'd1:  vtri0_note = PHI_0;
            4'd4:  vtri0_note = PHI_C2;
            4'd5:  vtri0_note = PHI_0;
            4'd6:  vtri0_note = PHI_C3;
            4'd7:  vtri0_note = PHI_0;
            4'd10: vtri0_note = PHI_C3;
            4'd11: vtri0_note = PHI_0;
            4'd12: vtri0_note = PHI_C2;
            4'd13: vtri0_note = PHI_0;
            4'd14: vtri0_note = PHI_C2;
            4'd15: vtri0_note = PHI_0;
            default: vtri0_note = PHI_0;
        endcase

        // Voice 1 pattern: same structure as your old code, but combinational
        if (phrase < 9'd32) begin
            vtri1_note = PHI_0;
        end else if (phrase < 9'd64) begin
            vtri1_note = fastarp ? PHI_C2 : PHI_C2+1; //fastarp ? PHI_DS3 : PHI_0;
        end else if (phrase < 9'd96) begin
            // vtri1_note = arp ? PHI_DS4 : PHI_G4;
            vtri1_note = fastarp ? PHI_DS4 : (PHI_DS4+2);
        end else if (phrase < 9'd128) begin
            // vtri1_note = arp ? PHI_D4 : PHI_F4;
            vtri1_note = fastarp ? PHI_D4 : (PHI_D4+2);
        // end else if (phrase < 9'd129) begin
        //     vtri1_note = 0;
        end else if (phrase < 9'd160) begin
            vtri1_note = arp ? (fastarp ? PHI_D4 : (PHI_D4+2)) : (fastarp ? PHI_F4 : (PHI_F4+2));
        end else if (phrase < 9'd192) begin
            vtri1_note = arp ? PHI_A3 : PHI_F4;
        end else if (phrase < 9'd224) begin
            // case (sub_ms[6:5])
            //     2'd0: vtri1_note = PHI_C4;
            //     2'd1: vtri1_note = PHI_G4;
            //     2'd2: vtri1_note = PHI_DS4;
            //     2'd3: vtri1_note = PHI_C5;
            // endcase
            case (sub_ms[7:6])
                2'd0: vtri1_note = PHI_C4;
                2'd1: vtri1_note = PHI_DS4;
                2'd2: vtri1_note = PHI_C4;
                2'd3: vtri1_note = PHI_G4;
            endcase
        end else begin //if (phrase < 9'd256) begin
            case (sub_ms[7:6])
                2'd0: vtri1_note = PHI_C4;
                2'd1: vtri1_note = PHI_D4;
                2'd2: vtri1_note = PHI_C4;
                2'd3: vtri1_note = PHI_F4;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Two compact triangle voices
    // 24-bit phase accumulator, 8-bit sample output
    // ------------------------------------------------------------------------
    wire [7:0] vtri0;
    wire [7:0] vtri1;

    triangle_voice_24x8_v2 voice0 (
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri0_note),
        .sample_out(vtri0)
    );

    triangle_voice_24x8_v2 voice1 (
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri1_note),
        .sample_out(vtri1)
    );

    // ------------------------------------------------------------------------
    // Cheap mixer: average instead of registered chopping
    // ------------------------------------------------------------------------
    wire [8:0] mix_sum = {1'b0, vtri0} + {1'b0, vtri1};
    assign sample_out = mix_sum[8:1];

endmodule


module triangle_voice_24x8_v2(
    input  wire        clk,
    input  wire        rst,
    input  wire [23:0] phase_inc,
    output wire [7:0]  sample_out
);
    reg  [23:0] phase_acc;
    wire [23:0] phase_next = phase_acc + phase_inc;

    // 8-bit triangle from folded phase
    assign sample_out = phase_next[23] ? ~phase_next[22:15] : phase_next[22:15];

    always @(posedge clk) begin
        if (rst)
            phase_acc <= 24'd0;
        else
            phase_acc <= phase_next;
    end
endmodule

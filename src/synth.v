`default_nettype none

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDSIGNAL */

module synth (
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
    //   phrase[7:0]    ~= ticks[19:7]
    reg [6:0] sub_ms;
    reg [7:0] phrase;

    always @(posedge clk) begin
        if (rst) begin
            ms_divider <= 15'd0;
            sub_ms     <= 7'd0;
            phrase     <= 8'd0;
        end else if (ms_tick) begin
            ms_divider <= 15'd0;

            if (sub_ms == 7'd127) begin
                sub_ms <= 7'd0;
                phrase <= phrase + 8'd1;
            end else begin
                sub_ms <= sub_ms + 7'd1;
            end
        end else begin
            ms_divider <= ms_divider + 15'd1;
        end
    end

    wire fastarp = sub_ms[4];
    wire arp     = sub_ms[5];

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
        if (phrase < 8'd32) begin
            vtri1_note = PHI_0;
        end else if (phrase < 8'd64) begin
            vtri1_note = fastarp ? PHI_DS3 : PHI_0;
        end else if (phrase < 8'd96) begin
            vtri1_note = arp ? PHI_DS4 : PHI_G4;
        end else if (phrase < 8'd128) begin
            vtri1_note = arp ? PHI_D4 : PHI_F4;
        end else if (phrase < 8'd160) begin
            vtri1_note = arp ? PHI_D4 : PHI_F4;
        end else if (phrase < 8'd192) begin
            vtri1_note = arp ? PHI_A3 : PHI_F4;
        end else begin
            case (sub_ms[5:4])
                2'd0: vtri1_note = PHI_C4;
                2'd1: vtri1_note = PHI_G4;
                2'd2: vtri1_note = PHI_DS4;
                2'd3: vtri1_note = PHI_C5;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Two compact triangle voices
    // 24-bit phase accumulator, 8-bit sample output
    // ------------------------------------------------------------------------
    wire [7:0] vtri0;
    wire [7:0] vtri1;

    triangle_voice_24x8 voice0 (
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri0_note),
        .sample_out(vtri0)
    );

    triangle_voice_24x8 voice1 (
        .clk(clk),
        .rst(rst),
        .phase_inc(vtri1_note),
        .sample_out(vtri1)
    );

    // ------------------------------------------------------------------------
    // Cheap mixer: average instead of registered chopping
    // ------------------------------------------------------------------------
    wire [8:0] mix_sum = {1'b0, vtri0} + {1'b0, vtri1};
    wire [7:0] raw_out = mix_sum[8:1];

    assign sample_out = raw_out;

endmodule


module triangle_voice_24x8(
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

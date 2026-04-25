`default_nettype none

/* verilator lint_off DECLFILENAME */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */

module newsynth(
    input clk,
    input reset,
    output [7:0] sample
    // output [31:0] o_t
);
    localparam CLK_HZ = 25175000;
    localparam SAMPLE_RATE = 50350; // Chosen so SAMPLE_DIV is 500.
    //NOTE: We could get slightly simpler logic by using SAMPLE_DIV=512.

    localparam [63:0] FS = 10000; // F_ scaling factor, i.e. frequencies below are 10000x normal (for better precision).
    localparam [63:0] FR = SAMPLE_RATE*FS/2; // F_ rounding factor.

    localparam [63:0] F_C4  = ((2616256 * 65536) + FR) / (SAMPLE_RATE * FS); // C4  target=261.6256 Hz
    localparam [63:0] F_Cs4 = ((2771826 * 65536) + FR) / (SAMPLE_RATE * FS); // C#4 target=277.1826 Hz
    localparam [63:0] F_D4  = ((2936648 * 65536) + FR) / (SAMPLE_RATE * FS); // D4  target=293.6648 Hz
    localparam [63:0] F_Ds4 = ((3111270 * 65536) + FR) / (SAMPLE_RATE * FS); // D#4 target=311.1270 Hz
    localparam [63:0] F_E4  = ((3296276 * 65536) + FR) / (SAMPLE_RATE * FS); // E4  target=329.6276 Hz
    localparam [63:0] F_F4  = ((3492282 * 65536) + FR) / (SAMPLE_RATE * FS); // F4  target=349.2282 Hz
    localparam [63:0] F_Fs4 = ((3699944 * 65536) + FR) / (SAMPLE_RATE * FS); // F#4 target=369.9944 Hz
    localparam [63:0] F_G4  = ((3919954 * 65536) + FR) / (SAMPLE_RATE * FS); // G4  target=391.9954 Hz
    localparam [63:0] F_Gs4 = ((4153047 * 65536) + FR) / (SAMPLE_RATE * FS); // G#4 target=415.3047 Hz
    localparam [63:0] F_A4  = ((4400000 * 65536) + FR) / (SAMPLE_RATE * FS); // A4  target=440.0000 Hz
    localparam [63:0] F_As4 = ((4661638 * 65536) + FR) / (SAMPLE_RATE * FS); // A#4 target=466.1638 Hz
    localparam [63:0] F_B4  = ((4938833 * 65536) + FR) / (SAMPLE_RATE * FS); // B4  target=493.8833 Hz

    initial begin
        $display("F_C4=", F_C4);
    end

    // // Dump the signals to a VCD file. You can view it with gtkwave.
    // initial begin
    //     $dumpfile("tb.fst");
    //     $dumpvars(0, synth);
    //     #1;
    // end

    // Divide clk by SAMPLE_DIV to get sample rate.
    // Anyway, this is the time within which a new 8-bit audio sample is
    // expected to be ready and presented at `sample`.
    localparam [8:0] SAMPLE_DIV = CLK_HZ / SAMPLE_RATE; // 500 typical.
    reg [8:0] sample_div_ctr; // Needs to be sized to hold SAMPLE_DIV-1.
    wire sample_tick = (sample_div_ctr == SAMPLE_DIV-1); // About to roll lover?
    always @(posedge clk) begin
        if (reset)
            sample_div_ctr <= 0;
        else if (sample_tick)
            sample_div_ctr <= 0;    // Rollover.
        else
            sample_div_ctr <= sample_div_ctr+1;
    end

    // Synth master counter, which increments by 1 every SAMPLE_DIV clocks.
    reg [31:0] t;
    always @(posedge clk) begin
        if (reset)
            t <= 0;
        else if (sample_tick)
            t <= t+1;
    end

    wire [7:0] ft = t[7:0];    // Fine time: 25175000/SAMPLE_DIV = ~19.86us (50350kHz)
    wire [23:0] ct = t[31:8];   // Coarse time: 25175000/SAMPLE_DIV/256 = ~5.08ms

    wire [39:0] prod0 = {ct[15:0], ft} * (F_C4<<1);
    wire [39:0] prod1 = {ct[15:0], ft} * (F_E4<<1);
    wire [39:0] prod2 = {ct[15:0], ft} * (F_G4<<1);
    wire [39:0] prod3 = {ct[15:0], ft} * (F_C4<<0);

    function automatic [7:0] tri8;
        input [8:0] ph;
        begin
            if (!ph[8])
                tri8 = ph[7:0];
            else
                tri8 = ~ph[7:0];
        end
    endfunction

    // Sample values computed at sample_tick for each sample_tick:
    wire [9:0] sample_wide =
        {2'b00, tri8(prod0[16:8])} +
        {2'b00, tri8(prod1[16:8])} +
        {2'b00, tri8(prod2[16:8])} +
        {2'b00, tri8(prod3[16:8])};
    assign sample = sample_wide[9:2];

endmodule

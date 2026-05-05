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
    assign uio_out = 0;
    assign uio_oe  = 0;

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

    assign rgb = {
        h[4:3]^v[4:3],
        h[6:5]^v[6:5],
        frame_counter[6:5]
    };

    // List all unused inputs to prevent warnings:
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule

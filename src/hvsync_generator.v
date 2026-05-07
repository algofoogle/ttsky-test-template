`ifndef HVSYNC_GENERATOR_H
`define HVSYNC_GENERATOR_H

// `define V512_SYNC_HACK // Ensure frame is 512 lines high instead of standard 525.

/*
Video sync generator, used to drive a VGA monitor.
Timing from: https://en.wikipedia.org/wiki/Video_Graphics_Array
To use:
- Wire the hsync and vsync signals to top level outputs
- Add a 3-bit (or more) "rgb" output to the top level
*/

module hvsync_generator(clk, reset, hsync, vsync, display_on, hpos, vpos, line_end, frame_end);

    input clk;
    input reset;
    output reg hsync, vsync;
    output display_on;
    output reg [9:0] hpos;
    output reg [9:0] vpos;
    output line_end;
    output frame_end;

    // declarations for TV-simulator sync parameters
    // horizontal constants
    parameter H_DISPLAY       = 640; // horizontal display width
    parameter H_BACK          =  48; // horizontal left border (back porch)
    parameter H_FRONT         =  16; // horizontal right border (front porch)
    parameter H_SYNC          =  96; // horizontal sync width
    // vertical constants
    parameter V_DISPLAY       = 480; // vertical display height
`ifdef V512_SYNC_HACK
    parameter V_TOP           =  20; // vertical top border (HACKED FOR 512 TOTAL V LINES)
`else
    parameter V_TOP           =  33; // vertical top border (STANDARD)
`endif
    parameter V_BOTTOM        =  10; // vertical bottom border
    parameter V_SYNC          =   2; // vertical sync # lines
    // derived constants
    parameter H_SYNC_START    = H_DISPLAY + H_FRONT;
    parameter H_SYNC_END      = H_DISPLAY + H_FRONT + H_SYNC - 1;
    parameter H_MAX           = H_DISPLAY + H_BACK + H_FRONT + H_SYNC - 1;
    parameter V_SYNC_START    = V_DISPLAY + V_BOTTOM;
    parameter V_SYNC_END      = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
    parameter V_MAX           = V_DISPLAY + V_TOP + V_BOTTOM + V_SYNC - 1;

    assign line_end = (hpos == H_MAX);
    wire vposmax = (vpos == V_MAX);
    assign frame_end = line_end && vposmax;

    wire hmaxxed = line_end || reset;	// set when hpos is maximum
    wire vmaxxed = vposmax || reset;	// set when vpos is maximum
    
    // horizontal position counter
    always @(posedge clk)
    begin
        hsync <= ~(hpos>=H_SYNC_START && hpos<=H_SYNC_END);
        if(hmaxxed)
            hpos <= 0;
        else
            hpos <= hpos + 1;
    end

    // vertical position counter
    always @(posedge clk)
    begin
        vsync <= ~(vpos>=V_SYNC_START && vpos<=V_SYNC_END);
        if(hmaxxed)
            if (vmaxxed)
                vpos <= 0;
            else
                vpos <= vpos + 1;
    end
    
    // display_on is set when beam is in "safe" visible frame
    assign display_on = (hpos<H_DISPLAY) && (vpos<V_DISPLAY);

endmodule

`endif

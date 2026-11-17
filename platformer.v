
`default_nettype none


module platformer(CLOCK_50, KEY, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);

    parameter RESOLUTION = "160x120"; // "640x480" "320x240" "160x120"

    // specify the color depth. This design supports depths of 9, 6, and 3
    parameter COLOR_DEPTH = 3; // 9 6 3

    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 8;
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 7;

    

	input [3:0] KEY;
	input wire CLOCK_50;	

	output wire [7:0] VGA_R;
	output wire [7:0] VGA_G;
	output wire [7:0] VGA_B;
	output wire VGA_HS;
	output wire VGA_VS;
	output wire VGA_BLANK_N;
	output wire VGA_SYNC_N;
	output wire VGA_CLK;	
	
    wire Resetn;       
    assign Resetn = KEY[0];

    // The signals below. we need wires for every single new screen we make.
	wire [nX-1:0] go_x;    // x coordinate 
	wire [nY-1:0] go_y;    // y coordinate
	wire [COLOR_DEPTH-1:0] go_color;
	wire go_write, go_done; 

    game_over GO (CLOCK_50, Resetn, 1'b1, go_x, go_y, go_color, go_write, go_done);





    // For game logic, chooser to which one goes into vga adapter, fsm
    wire [7:0] adp_x = go_x;
    wire [6:0] adp_y = go_y;
    wire [COLOR_DEPTH-1:0] adp_color = go_color;
    wire adp_write = go_write;


    // connect to VGA controller
    vga_adapter VGA (
			.resetn(Resetn),
			.clock(CLOCK_50),
			.color(adp_color),
			.x(adp_x),
			.y(adp_y),
			.write(adp_write),
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK_N(VGA_BLANK_N),
			.VGA_SYNC_N(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = RESOLUTION;
        // choose background image according to resolution and color depth
		defparam VGA.BACKGROUND_IMAGE = "./MIF/black.mif";
		defparam VGA.COLOR_DEPTH = COLOR_DEPTH;

endmodule


module game_over (clock, resetn, start, x, y, color, write, done);

    input clock, resetn, start;
    output reg [7:0] x;
    output reg [6:0] y;
    output wire [2:0] color;
    output wire write;
    output reg done;


    always@(posedge clock)
    begin
        if(resetn == 0 || start == 0)
        begin
            x <= 8'd0;
            y <= 7'd0;
            done <= 0;
        end
        else if(done == 0)
        begin
            if(x == 8'd159)
            begin
                x <= 0;
                if(y == 7'd119)
                    done <= 1;
                else 
                    y <= y + 1;
            end
            else    
                x <= x + 1;
        end
    end


    wire letter;
    
    // i am working in 4x4 blocks for the game over letters so i can work on a 40 by 30 grid instead
    wire [5:0] cx = x[7:2];
    wire [4:0] cy = y[6:2]; 


    assign letter =
    // G
    (cy == 5 && cx >= 7 && cx <= 11) || (cx == 7 && cy >= 6 && cy <= 11) || (cy == 11 && cx >= 8 && cx <= 11)
    || (cx == 11 && cy >= 9 && cy <= 10) || (cy == 9 && cx == 10)
    // A
    || (cy == 5 && cx >= 15 && cx <= 17) || (cx == 14 && cy >= 6 && cy <= 11)
    || (cx == 18 && cy >= 6 && cy <= 11) || (cy == 8 && cx >= 14 && cx <= 18)
    // M
    || (cx == 21 && cy >= 5 && cy <= 11) || (cx == 25 && cy >= 5 && cy <= 11)
    || (cy == 6 && cx == 22) || (cy == 6 && cx == 24) || (cy == 7 && cx == 23)
    // E
    || (cx == 28 && cy >= 5 && cy <= 11) || (cy == 5 && cx >= 28 && cx <= 32)
    || (cy == 8 && cx >= 28 && cx <= 30) || (cy == 11 && cx >= 28 && cx <= 32)
    // O
    || (cy == 17 && cx >= 8 && cx <= 10) || (cx == 7 && cy >= 18 && cy <= 22)
    || (cx == 11 && cy >= 18 && cy <= 22) || (cy == 23 && cx >= 8 && cx <= 10)
    // V
    || (cx == 14 && cy >= 17 && cy <= 20) || (cx == 18 && cy >= 17 && cy <= 20)
    || (cx == 15 && cy >= 21 && cy <= 22) || (cx == 17 && cy >= 21 && cy <= 22)
    || (cy == 23 && cx == 16)
    // E 
    || (cx == 21 && cy >= 17 && cy <= 23) || (cy == 17 && cx >= 21 && cx <= 25)
    || (cy == 20 && cx >= 21 && cx <= 23) || (cy == 23 && cx >= 21 && cx <= 25)
    // R
    || (cx == 28 && cy >= 17 && cy <= 23) || (cy == 17 && cx >= 28 && cx <= 31)
    || (cx == 32 && cy >= 18 && cy <= 19) || (cy == 20 && cx >= 28 && cx <= 31)
    || (cy == 21 && cx == 31) || (cx == 32 && cy >= 22 && cy <= 23);

    assign write = ~done & start & resetn;

    assign color = letter ? 3'b111 : 3'b000;

endmodule


// all of these are animated so look at the animate demo and take from there
//module platforms()

//module birds()

//module wall()
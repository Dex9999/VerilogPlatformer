`default_nettype none

module platformer(CLOCK_50, KEY, SW, LEDR, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK, PS2_CLK, PS2_DAT);

    parameter RESOLUTION = "160x120"; // "640x480" "320x240" "160x120"
    parameter COLOR_DEPTH = 3;        // 9 6 3
    parameter nX = 8;
    parameter nY = 7;
	 
	 //keyboard
	 inout wire PS2_CLK;
	 inout wire PS2_DAT;
	 

    // scene layout
    parameter YSCREEN = 120;
    parameter GROUND_HEIGHT = 8;
    parameter BG_COLOR = 3'b001; // blue bg
	 parameter GROUND_COLOR = 3'b110;
	 
    parameter PLAT_COLOR = 3'b011;   // cyan

    localparam GROUND_Y = YSCREEN - GROUND_HEIGHT;   // first ground row (112)
    localparam PLAYER_Y = GROUND_Y - 1 - 6;          // sprite is 13 tall, centred on Y -> bottom row = Y + 6
    
	 // platform list. 0 is ground 
    //   idx : x0..x1   top row
    //    0  : 0..159   112 (ground)
    //    1  : 10..50    96
    //    2  : 40..80    80
    //    3  : 70..110   64
    //    4  : 100..140  48
    // platforms are semisolid: jump up through them, land on top.
    // out of the bird's rows for now
    localparam NPLAT = 5;
    localparam PLAT_H = 3;
    localparam [7:0] GROUND_Y8 = YSCREEN - GROUND_HEIGHT;
    localparam [NPLAT*8-1:0] PLAT_X0 = {8'd100, 8'd70, 8'd40, 8'd10, 8'd0};
    localparam [NPLAT*8-1:0] PLAT_X1 = {8'd140, 8'd110, 8'd80, 8'd50, 8'd159};
    localparam [NPLAT*8-1:0] PLAT_Y  = {8'd48,  8'd64,  8'd80, 8'd96, GROUND_Y8};

    // bird
    parameter BIRD_KK = 19;                      // bird speed: smaller = faster
    localparam [6:0] BIRD_Y = 7'd75;             // row the bird flies on
		// make it hit platform to test erase 
		
    input [3:0] KEY;
    input [9:0] SW;
    output wire [9:0] LEDR;
    input wire CLOCK_50;

    output wire [7:0] VGA_R;
    output wire [7:0] VGA_G;
    output wire [7:0] VGA_B;
    output wire VGA_HS;
    output wire VGA_VS;
    output wire VGA_BLANK_N;
    output wire VGA_SYNC_N;
    output wire VGA_CLK;
	 
	 //player x,y to stop overwrites
	 wire [7:0] pl_x;
    wire [6:0] pl_y;

    // synchronize inputs to stop random pixels bug
    reg [1:0] rst_s, over_s;
    always @(posedge CLOCK_50) begin
        rst_s  <= {rst_s[0],  KEY[0]};
        over_s <= {over_s[0], SW[0]};
    end

    wire Resetn  = rst_s[1];     // active low, now synchronous
    wire sw_over = over_s[1];    // game over mode

    // one-clock pulse whenever the mode changes
    reg [1:0] mode_q;
    always @(posedge CLOCK_50) mode_q <= sw_over;
    wire mode_chg = (sw_over != mode_q);

    // main game scene
    wire [nX-1:0] sc_x;
	 wire [nY-1:0] sc_y;
    wire [COLOR_DEPTH-1:0] sc_color;
    wire sc_write, sc_done;

    wire scene_resetn = Resetn & ~sw_over & ~mode_chg;
    scene_draw #(.GROUND_Y(GROUND_Y), .BG_COLOR(BG_COLOR), .GROUND_COLOR(GROUND_COLOR),
                 .PLAT_COLOR(PLAT_COLOR), .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                 .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) SCENE
        (CLOCK_50, scene_resetn, sc_x, sc_y, sc_color, sc_write, sc_done);

    // game over screen ONLY SW[0] = 1
    wire [nX-1:0] go_x;
    wire [nY-1:0] go_y;
    wire [COLOR_DEPTH-1:0] go_color;
    wire go_write, go_done;

    game_over GO (CLOCK_50, Resetn, sw_over, go_x, go_y, go_color, go_write, go_done);

	 // bus arbiter between player and bird
    wire player_req, player_gnt, bird_req, bird_gnt;
    vga_arbiter ARB (CLOCK_50, Resetn, player_req, bird_req, player_gnt, bird_gnt);

    // Bird: ONLY in bird mode
    wire [7:0] bird_x;
    wire [6:0] bird_y;
    wire [2:0] bird_color;
    wire bird_write;
    wire bird_done, bird_busy;
    wire [nX-1:0] bird_obj_x;
    wire [nY-1:0] bird_obj_y;

    wire bird_resetn = Resetn & ~sw_over & sc_done & ~mode_chg;

    bird_left #(.KK(BIRD_KK), .sky_color(BG_COLOR), .GROUND_Y(GROUND_Y),
                .GROUND_COLOR(GROUND_COLOR), .PLAT_COLOR(PLAT_COLOR),
                .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) BIRD (
        bird_resetn, CLOCK_50, bird_gnt, bird_req, bird_x, bird_y, bird_color, bird_write,
        1'b1, bird_done, bird_busy, BIRD_Y, bird_obj_x, bird_obj_y, pl_x, pl_y);
		  
    wire [7:0] player_x;
    wire [6:0] player_y;
    wire [2:0] player_color;
    wire player_write;

    wire player_resetn = Resetn & sc_done & ~sw_over & ~mode_chg;
	 
	 //keyboard
	 wire [7:0] ps2_byte;       // last byte received
	 wire       ps2_byte_en;    // 1 clock pulse for every new byte

	 PS2_Controller PS2 (
		 .CLOCK_50(CLOCK_50),
		 .reset(~Resetn),
		 .the_command(8'h00),
		 .send_command(1'b0),
		 .PS2_CLK(PS2_CLK),
		 .PS2_DAT(PS2_DAT),
		 .command_was_sent(),
		 .error_communication_timed_out(),
		 .received_data(ps2_byte),
		 .received_data_en(ps2_byte_en));
		 
	 wire kb_left, kb_right, kb_jump;

	 ps2_keys KEYS (
			 .clock(CLOCK_50),
			 .reset(~Resetn),
			 .received_data(ps2_byte),
			 .received_data_en(ps2_byte_en),
			 .left(kb_left),
			 .right(kb_right),
			 .jump(kb_jump));


    // KEY[1] = right, KEY[3] = left, KEY[2] = jump, SW[2] = yell
    player_object #(.YOFFSET(PLAYER_Y), .BG_COLOR(BG_COLOR), .GROUND_Y(GROUND_Y),
                    .GROUND_COLOR(GROUND_COLOR), .PLAT_COLOR(PLAT_COLOR),
                    .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                    .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) PLAYER_INST (
        .Resetn(player_resetn),
        .Clock(CLOCK_50),
        .key_right(~KEY[1] | kb_right),
        .key_left(~KEY[3] | kb_left),
        .yell_pressed(SW[2]), // temp until mic input
        .jump_pressed(~KEY[2] | kb_jump),
        .gnt(player_gnt),
        .req(player_req),
        .VGA_x(player_x),
        .VGA_y(player_y),
        .VGA_color(player_color),
        .VGA_write(player_write),
        .obj_x(pl_x),
        .obj_y(pl_y)
    );

    assign LEDR = SW;

    // Who drives the VGA adapter (first match wins):
    //   game over mode              -> game over screen
    //   scene not finished drawing  -> scene_draw
    //   arbiter granted the bird    -> bird
    //   arbiter granted the player  -> player
	 wire sel_go    = sw_over;
    wire sel_scene = ~sw_over & ~sc_done;

    wire [7:0] adp_x = sel_go ? go_x : (sel_scene ? sc_x : (bird_gnt ? bird_x : player_x));
    wire [6:0] adp_y = sel_go ? go_y : (sel_scene ? sc_y : (bird_gnt ? bird_y : player_y));
    wire [COLOR_DEPTH-1:0] adp_color = sel_go ? go_color : (sel_scene ? sc_color : (bird_gnt ? bird_color : player_color));
    wire adp_write = sel_go ? go_write : (sel_scene ? sc_write :
                     (bird_gnt ? bird_write : (player_gnt ? player_write : 1'b0)));

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
        defparam VGA.BACKGROUND_IMAGE = "./MIF/background.mif";
        defparam VGA.COLOR_DEPTH = COLOR_DEPTH;

endmodule

// give access to the VGA write port to one module at a time. A grant is held for as
// a full erase/draw pass (keep high until done)
module vga_arbiter (clock, resetn, req_p, req_b, gnt_p, gnt_b);
    input wire clock, resetn, req_p, req_b;
    output wire gnt_p, gnt_b;

    reg [1:0] owner;   // 00 = nobody, 01 = player, 10 = bird
    always @(posedge clock)
        if (!resetn)
            owner <= 2'b00;
        else if (owner == 2'b01 && req_p)
            owner <= 2'b01;                 // player keeps bus
        else if (owner == 2'b10 && req_b)
            owner <= 2'b10;                 // bird keeps bus
        else if (req_p)
            owner <= 2'b01;
        else if (req_b)
            owner <= 2'b10;
        else
            owner <= 2'b00;

    assign gnt_p = (owner == 2'b01);
    assign gnt_b = (owner == 2'b10);
endmodule


// Used by scene_draw to paint, and by the player to erase without damaging platforms.
module scene_color (x, y, color);
    parameter GROUND_Y     = 112;
    parameter BG_COLOR     = 3'b000;
    parameter GROUND_COLOR = 3'b110;
    parameter PLAT_COLOR   = 3'b011;
    parameter NPLAT  = 5;
    parameter PLAT_H = 3;
    parameter [NPLAT*8-1:0] PLAT_X0 = 0;
    parameter [NPLAT*8-1:0] PLAT_X1 = 0;
    parameter [NPLAT*8-1:0] PLAT_Y  = 0;

    input  wire [7:0] x;
    input  wire [6:0] y;
    output wire [2:0] color;

    wire [NPLAT*8-1:0] pX0 = PLAT_X0;
    wire [NPLAT*8-1:0] pX1 = PLAT_X1;
    wire [NPLAT*8-1:0] pY  = PLAT_Y;

    integer i;
    reg hit;
    always @(*) begin
        hit = 1'b0;
        for (i = 0; i < NPLAT; i = i + 1)
            if (x >= pX0[i*8 +: 8] && x <= pX1[i*8 +: 8] &&
                y >= pY[i*8 +: 8] && y < pY[i*8 +: 8] + PLAT_H)
                hit = 1'b1;
    end

    assign color = (y >= GROUND_Y) ? GROUND_COLOR : (hit ? PLAT_COLOR : BG_COLOR);
endmodule

// now paints with the sky + ground +platforms
module scene_draw (clock, resetn, x, y, color, write, done);
    parameter GROUND_Y = 112;
    parameter BG_COLOR = 3'b000;
    parameter GROUND_COLOR = 3'b110;
    parameter PLAT_COLOR   = 3'b011;
    parameter NPLAT  = 5;
    parameter PLAT_H = 3;
    parameter [NPLAT*8-1:0] PLAT_X0 = 0;
    parameter [NPLAT*8-1:0] PLAT_X1 = 0;
    parameter [NPLAT*8-1:0] PLAT_Y  = 0;

    input clock, resetn;
    output reg [7:0] x;
    output reg [6:0] y;
    output wire [2:0] color;
    output wire write;
    output reg done;

    always @(posedge clock)
    begin
        if (resetn == 0)
        begin
            x <= 8'd0;
            y <= 7'd0;
            done <= 1'b0;
        end
        else if (done == 0)
        begin
            if (x == 8'd159)
            begin
                x <= 8'd0;
                if (y == 7'd119)
                    done <= 1'b1;
                else
                    y <= y + 1'b1;
            end
            else
                x <= x + 1'b1;
        end
    end

    scene_color #(.GROUND_Y(GROUND_Y), .BG_COLOR(BG_COLOR), .GROUND_COLOR(GROUND_COLOR),
                  .PLAT_COLOR(PLAT_COLOR), .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                  .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) SC (x, y, color);

    assign write = ~done & resetn;
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
    // G  (crossbar fixed: was `cx == 9 && cx == 10`, which can never be true)
    (cy == 5 && cx >= 7 && cx <= 11) || (cx == 7 && cy >= 6 && cy <= 11) || (cy == 11 && cx >= 8 && cx <= 11)
    || (cx == 11 && cy >= 9 && cy <= 10) || (cy == 8 && cx >= 9 && cx <= 11)
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
// implements a moving colored object
module bird_left (resetn, clock, gnt, req, VGA_x, VGA_y, VGA_color, VGA_write, start, done, busy, y_in, obj_x, obj_y, avoid_x, avoid_y);
    parameter RESOLUTION = "160x120"; 
    parameter nX = 8;
    parameter nY = 7;
    parameter COLOR_DEPTH = 3;
    parameter XSCREEN = 160;
    parameter YSCREEN = 120;
    parameter XDIM = 11, YDIM = 7; // object's width and height
    parameter sky_color = 3'b001; 
    parameter KK = 24; // controls animation speed (use 16 for DESim, 5 for ModelSim)
	 
	 // scene info (for erasing properly)
    parameter GROUND_Y     = 112;
    parameter GROUND_COLOR = 3'b110;
    parameter PLAT_COLOR   = 3'b011;
    parameter NPLAT  = 5;
    parameter PLAT_H = 3;
    parameter [NPLAT*8-1:0] PLAT_X0 = 0;
    parameter [NPLAT*8-1:0] PLAT_X1 = 0;
    parameter [NPLAT*8-1:0] PLAT_Y  = 0;
	 
    // state codes
    parameter A = 4'b0000,
              B = 4'b0001,
              C = 4'b0010,
              D = 4'b0011,
              E = 4'b0100,
              F = 4'b0101,
              G = 4'b0110,
              H = 4'b0111,
              I = 4'b1000,
              J = 4'b1001,
              K = 4'b1010,
              L = 4'b1011,
              M = 4'b1100, //done
              N = 4'b1101; //wait for grant before the first draw




    input wire gnt;
    output reg req;
    input wire start;
    input wire [nY-1:0] y_in;      // row to use for this flight (sampled when start = 1)
    output wire busy;              // 1 from start until the FSM is idle again
    output wire [nX-1:0] obj_x;    // current position (valid while busy, holds last value after)
    output wire [nY-1:0] obj_y;
    output reg done;
    input wire resetn, clock;
	 output wire [7:0] VGA_x; 
	 output wire [6:0] VGA_y; 
	 output wire [2:0] VGA_color;  
    output wire VGA_write; 
	 
	 input wire [7:0] avoid_x;   // player box to avoid
    input wire [6:0] avoid_y;   



	wire [7:0] X, XC, X0;    // used to traverse the object's width
	wire [6:0] Y, YC, Y0;    // used to traverse the object's height
    wire [KK-1:0] slow;     // used to synchronize the object's speed using a counter


    reg Lx, Ly, Ex, Lxc, Lyc, Exc, Eyc; // load and enable signals for the object's 
                                        // location (x,y) and the counters that traverse 
                                        // the object's pixels (XC, YC)
    wire sync;    // sync is for the slow counter
    reg erase;    // erase is used to erase the object
    reg [3:0] y_Q, Y_D; // FSM for controlling drawing/erasing of the object
    reg write;          // used to write to a pixel

    //bird colours
    wire is_yellow = (XC == 0 && YC == 4) || (XC == 1 && YC >= 3 && YC <= 4);
    wire is_black = (XC == 2 && YC == 3);
    wire is_white = ( YC == 0 && XC >= 7 && XC <= 9 )
                    || ( YC == 1 && XC >= 6 && XC <= 8 )
                    || ( YC == 2 && ((XC >= 2 && XC <= 3) || (XC >= 5 && XC <= 7)) )
                    || ( YC == 3 && XC >= 3 && XC <= 10 )
                    || ( YC == 4 && XC >= 2 && XC <= 9 )
                    || ( YC == 5 && XC >= 3 && XC <= 7 )
                    || ( YC == 6 && XC >= 4 && XC <= 6 );

    wire px_solid = is_white | is_yellow | is_black;
    wire [2:0] px_color = is_yellow ? 3'b110 : is_black ? 3'b000 : 3'b111;


    assign X0 = XSCREEN - XDIM;   // enters at the right edge
    assign Y0 = y_in;

    assign busy  = (y_Q != A);
    assign obj_x = X;
    assign obj_y = Y;


    wire [7:0] px = X + XC;                         // pixel x coordinate
    wire [6:0] py = Y + YC;                         // pixel y coordinate
    assign VGA_x = px;
    assign VGA_y = py;

    // find what's below this pixel (ground/sky/platform)
    wire [2:0] scene_px;
    scene_color #(.GROUND_Y(GROUND_Y), .BG_COLOR(sky_color), .GROUND_COLOR(GROUND_COLOR),
                  .PLAT_COLOR(PLAT_COLOR), .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                  .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) SCN (px, py, scene_px);
	 assign VGA_color = erase ? scene_px : px_color;
	 
	 // never write inside the player's box
    wire signed [9:0] spx = {2'b00, px};
    wire signed [9:0] spy = {3'b000, py};
    wire signed [9:0] sax = {2'b00, avoid_x};
    wire signed [9:0] say = {3'b000, avoid_y};
    wire in_player = (spx >= sax - 5) && (spx <= sax + 5) &&
                     (spy >= say - 6) && (spy <= say + 6);

    assign VGA_write = write & ~in_player;


        // X moves left: enable = Ex, direction 0 = count down
    UpDn_count U2 (X0, clock, resetn, Ex, Lx, 1'b0, X);
        defparam U2.n = nX;

    // Y only loads: enable tied to 0
    UpDn_count U1 (Y0, clock, resetn, 1'b0, Ly, 1'b0, Y);
        defparam U1.n = nY;

    // pixel counters walk through the sprite box
    UpDn_count U3 ({nX{1'b0}}, clock, resetn, Exc, Lxc, 1'b1, XC);
        defparam U3.n = nX;

    UpDn_count U4 ({nY{1'b0}}, clock, resetn, Eyc, Lyc, 1'b1, YC);
        defparam U4.n = nY;

    // speed counter
    Up_count U6 (clock, resetn, slow);
        defparam U6.n = KK;
    assign sync = (slow == {KK{1'b1}});

    // FSM Algorithm:
    // 1. draw object
    // 2. wait for object's delay time
    // 3. request to draw, wait for grant
    // 4. erase object (maintain request)
    // 5. move object, check for boundary conditions (maintain request)
    // 6. draw object (maintain request)
    // 7. release request, goto 2.

    always @ (*)
        case (y_Q)
            A:  if (start) Y_D = N; else Y_D = A;                    // initialize counters, registers

            N:  if (!gnt) Y_D = N;              // wait for VGA grant before the first draw
                else Y_D = B;

            B:  if (XC != XDIM-1) Y_D = B;      // initial draw, done once
                else Y_D = C;
            C:  if (YC != YDIM-1) Y_D = B;
                else Y_D = D;

            D:  if (!sync) Y_D = D;             // wait for object's delay time
                else Y_D = E;
            E:  if (!gnt) Y_D = E;              // wait for VGA grant
                else Y_D = F;

            F:  if (XC != XDIM-1) Y_D = F;      // erase object
                else Y_D = G;
            G:  if (YC != YDIM-1) Y_D = F;
                else Y_D = H;

            H:  if (X == 0) Y_D = M;  
            else Y_D = I;                      // move the object
            I:  Y_D = J;

            J:  if (XC != XDIM-1) Y_D = J;      // draw the object
                else Y_D = K;
            K:  if (YC != YDIM-1) Y_D = J;
                else Y_D = L;
            L:  Y_D = D;

            M: Y_D = A;

            default: Y_D = A;
        endcase

    always @ (*)
    begin
        // default assignments
        Lx = 1'b0; Ly = 1'b0; Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; done = 1'b0;
        erase = 1'b0; write = 1'b0; Ex = 1'b0; req = 1'b0;
        case (y_Q)
            A:  begin Lx = start; Ly = start; Lxc = 1'b1; Lyc = 1'b1; end // load position only on start

            N:  req = 1'b1; // request the adapter for the first draw

            B:  begin req = 1'b1; Exc = 1'b1; write = px_solid; end   // color a pixel, incr XC
            C:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end     // reload XC, incr YC

            D:  Lyc = 1'b1; // reload YC
            E:  req = 1'b1; // request a drawing cycle

            // erase the object
            F:  begin req = 1'b1; Exc = 1'b1; erase = 1'b1; write = 1'b1; end
            G:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end

            H:  begin req = 1'b1; Lyc = 1'b1; end

            // move the object
            I:  begin req = 1'b1; Ex = 1'b1; end

            // draw the object
            J:  begin req = 1'b1; Exc = 1'b1; write = px_solid; end
            K:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end
            L:  Lyc = 1'b1; // reload YC, and release the request

            M: begin done = 1'b1; end
        endcase
    end

    // FSM FFs 
    always @(posedge clock)
        if (resetn == 0)
            y_Q <= A;
        else
            y_Q <= Y_D;



endmodule

// up/down counter with reset, enable, and load controls
module UpDn_count (R, Clock, Resetn, E, L, UpDn, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Clock, Resetn, E, L, UpDn;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= 0;
        else if (L == 1)
            Q <= R;
        else if (E)
            if (UpDn == 1)
                Q <= Q + 1'b1;
            else
                Q <= Q - 1'b1;
endmodule

// counter
module Up_count (Clock, Resetn, Q);
    parameter n = 8;
    input wire Clock, Resetn;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= 'b0;
        else 
            Q <= Q + 1'b1;
endmodule

// bird right

// implements a moving colored object
module bird_right (resetn, clock, gnt, req, VGA_x, VGA_y, VGA_color, VGA_write, start, done, busy, y_in, obj_x, obj_y, avoid_x, avoid_y);

    parameter RESOLUTION = "160x120"; 
    parameter nX = 8;
    parameter nY = 7;
    parameter COLOR_DEPTH = 3;
    parameter XSCREEN = 160;
    parameter YSCREEN = 120;
    parameter XDIM = 11, YDIM = 7; // object's width and height
    parameter sky_color = 3'b001; 
    parameter KK = 24; // controls animation speed (use 16 for DESim, 5 for ModelSim)
	
	 // scene info (for erasing properly)
    parameter GROUND_Y     = 112;
    parameter GROUND_COLOR = 3'b110;
    parameter PLAT_COLOR   = 3'b011;
    parameter NPLAT  = 5;
    parameter PLAT_H = 3;
    parameter [NPLAT*8-1:0] PLAT_X0 = 0;
    parameter [NPLAT*8-1:0] PLAT_X1 = 0;
    parameter [NPLAT*8-1:0] PLAT_Y  = 0;
	 
    // state codes
    parameter A = 4'b0000,
              B = 4'b0001,
              C = 4'b0010,
              D = 4'b0011,
              E = 4'b0100,
              F = 4'b0101,
              G = 4'b0110,
              H = 4'b0111,
              I = 4'b1000,
              J = 4'b1001,
              K = 4'b1010,
              L = 4'b1011,
              M = 4'b1100, //done
              N = 4'b1101; //wait for grant before the first draw




    input wire gnt;
    output reg req;
    input wire start;
    input wire [nY-1:0] y_in;      // row to use for this flight (sampled when start = 1)
    output wire busy;              // 1 from start until the FSM is idle again
    output wire [nX-1:0] obj_x;    // current position (valid while busy, holds last value after)
    output wire [nY-1:0] obj_y;
    output reg done;
    input wire resetn, clock;
	 output wire [7:0] VGA_x; 
	 output wire [6:0] VGA_y; 
	 output wire [2:0] VGA_color;  
    output wire VGA_write; 
	 
	 input wire [7:0] avoid_x;   // player box to avoid
    input wire [6:0] avoid_y;   



	wire [7:0] X, XC, X0;    // used to traverse the object's width
	wire [6:0] Y, YC, Y0;    // used to traverse the object's height
    wire [KK-1:0] slow;     // used to synchronize the object's speed using a counter


    reg Lx, Ly, Ex, Lxc, Lyc, Exc, Eyc; // load and enable signals for the object's 
                                        // location (x,y) and the counters that traverse 
                                        // the object's pixels (XC, YC)
    wire sync;    // sync is for the slow counter
    reg erase;    // erase is used to erase the object
    reg [3:0] y_Q, Y_D; // FSM for controlling drawing/erasing of the object
    reg write;          // used to write to a pixel

    //bird colours
    wire is_yellow = (XC == 10 && YC == 4) || (XC == 9 && YC >= 3 && YC <= 4);
    wire is_black = (XC == 8 && YC == 3);
    wire is_white = ( YC == 0 && XC >= 1 && XC <= 3 )
                    || ( YC == 1 && XC >= 2 && XC <= 4 )
                    || ( YC == 2 && ((XC >= 3 && XC <= 5) || (XC >= 7 && XC <= 8)) )
                    || ( YC == 3 && XC >= 0 && XC <= 7 )
                    || ( YC == 4 && XC >= 1 && XC <= 8 )
                    || ( YC == 5 && XC >= 3 && XC <= 7 )
                    || ( YC == 6 && XC >= 4 && XC <= 6 );

    wire px_solid = is_white | is_yellow | is_black;
    wire [2:0] px_color = is_yellow ? 3'b110 : is_black ? 3'b000 : 3'b111;


    assign X0 = 8'd0;             // enters at the left edge
    assign Y0 = y_in;

    assign busy  = (y_Q != A);
    assign obj_x = X;
    assign obj_y = Y;


    wire [7:0] px = X + XC;                         // pixel x coordinate
    wire [6:0] py = Y + YC;                         // pixel y coordinate
    assign VGA_x = px;
    assign VGA_y = py;

    // find what's below this pixel (ground/sky/platform)
    wire [2:0] scene_px;
    scene_color #(.GROUND_Y(GROUND_Y), .BG_COLOR(sky_color), .GROUND_COLOR(GROUND_COLOR),
                  .PLAT_COLOR(PLAT_COLOR), .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                  .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) SCN (px, py, scene_px);

    assign VGA_color = erase == 0 ? px_color : scene_px;    // pixel color to draw/erase
	 
	 // never write inside the player's box
    wire signed [9:0] spx = {2'b00, px};
    wire signed [9:0] spy = {3'b000, py};
    wire signed [9:0] sax = {2'b00, avoid_x};
    wire signed [9:0] say = {3'b000, avoid_y};
    wire in_player = (spx >= sax - 5) && (spx <= sax + 5) &&
                     (spy >= say - 6) && (spy <= say + 6);

    assign VGA_write = write & ~in_player;

        // X moves right: enable = Ex, direction 1 = count up
    UpDn_count U2 (X0, clock, resetn, Ex, Lx, 1'b1, X);
        defparam U2.n = nX;

    // Y only loads: enable tied to 0
    UpDn_count U1 (Y0, clock, resetn, 1'b0, Ly, 1'b0, Y);
        defparam U1.n = nY;

    // pixel counters walk through the sprite box
    UpDn_count U3 ({nX{1'b0}}, clock, resetn, Exc, Lxc, 1'b1, XC);
        defparam U3.n = nX;

    UpDn_count U4 ({nY{1'b0}}, clock, resetn, Eyc, Lyc, 1'b1, YC);
        defparam U4.n = nY;

    // speed counter
    Up_count U6 (clock, resetn, slow);
        defparam U6.n = KK;
    assign sync = (slow == {KK{1'b1}});

    // FSM Algorithm:
    // 1. draw object
    // 2. wait for object's delay time
    // 3. request to draw, wait for grant
    // 4. erase object (maintain request)
    // 5. move object, check for boundary conditions (maintain request)
    // 6. draw object (maintain request)
    // 7. release request, goto 2.

    always @ (*)
        case (y_Q)
            A:  if (start) Y_D = N; else Y_D = A;                    // initialize counters, registers

            N:  if (!gnt) Y_D = N;              // wait for VGA grant before the first draw
                else Y_D = B;

            B:  if (XC != XDIM-1) Y_D = B;      // initial draw, done once
                else Y_D = C;
            C:  if (YC != YDIM-1) Y_D = B;
                else Y_D = D;

            D:  if (!sync) Y_D = D;             // wait for object's delay time
                else Y_D = E;
            E:  if (!gnt) Y_D = E;              // wait for VGA grant
                else Y_D = F;

            F:  if (XC != XDIM-1) Y_D = F;      // erase object
                else Y_D = G;
            G:  if (YC != YDIM-1) Y_D = F;
                else Y_D = H;

            H:  if (X >= XSCREEN - XDIM) Y_D = M;  
            else Y_D = I;                      // move the object
            I:  Y_D = J;

            J:  if (XC != XDIM-1) Y_D = J;      // draw the object
                else Y_D = K;
            K:  if (YC != YDIM-1) Y_D = J;
                else Y_D = L;
            L:  Y_D = D;

            M: Y_D = A;

            default: Y_D = A;
        endcase

    always @ (*)
    begin
        // default assignments
        Lx = 1'b0; Ly = 1'b0; Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; done = 1'b0;
        erase = 1'b0; write = 1'b0; Ex = 1'b0; req = 1'b0;
        case (y_Q)
            A:  begin Lx = start; Ly = start; Lxc = 1'b1; Lyc = 1'b1; end // load position only on start

            N:  req = 1'b1; // request the adapter for the first draw

            B:  begin req = 1'b1; Exc = 1'b1; write = px_solid; end   // color a pixel, incr XC
            C:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end     // reload XC, incr YC

            D:  Lyc = 1'b1; // reload YC
            E:  req = 1'b1; // request a drawing cycle

            // erase the object
            F:  begin req = 1'b1; Exc = 1'b1; erase = 1'b1; write = 1'b1; end
            G:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end

            H:  begin req = 1'b1; Lyc = 1'b1; end

            // move the object
            I:  begin req = 1'b1; Ex = 1'b1; end

            // draw the object
            J:  begin req = 1'b1; Exc = 1'b1; write = px_solid; end
            K:  begin req = 1'b1; Lxc = 1'b1; Eyc = 1'b1; end
            L:  Lyc = 1'b1; // reload YC, and release the request

            M: begin done = 1'b1; end
        endcase
    end

    // FSM FFs 
    always @(posedge clock)
        if (resetn == 0)
            y_Q <= A;
        else
            y_Q <= Y_D;



endmodule

//added gravity and jumping, collisions with platforms, update to use arbiter
module player_object (Resetn, Clock, key_right, key_left, yell_pressed, jump_pressed, gnt, req, VGA_x, VGA_y, VGA_color, VGA_write, obj_x, obj_y);
    parameter XOFFSET = 80;
    parameter YOFFSET = 105; // start on ground?
    parameter BOX_SIZE_X = 11;
    parameter BOX_SIZE_Y = 13;
    parameter XSCREEN = 160;
    parameter KK = 20;
    parameter BG_COLOR = 3'b000;
	 
	 parameter GROUND_Y     = 112;
    parameter GROUND_COLOR = 3'b110;
    parameter PLAT_COLOR   = 3'b011;
    parameter NPLAT  = 5;
    parameter PLAT_H = 3;
    parameter [NPLAT*8-1:0] PLAT_X0 = 0;
    parameter [NPLAT*8-1:0] PLAT_X1 = 0;
    parameter [NPLAT*8-1:0] PLAT_Y  = 0;


    // physics (all in pixels, one redraw = 2^KK clocks)
    parameter JUMP_V   = 6;         // upward speed given by a jump (pixels per tick)
    parameter GRAVITY  = 1;         // speed change per tick (pixels per tick^2)
    parameter MAX_FALL = 2;         // max falling speed
    localparam HALF_X  = BOX_SIZE_X >> 1;   // 5
    localparam HALF_Y  = BOX_SIZE_Y >> 1;   // feet row = centre row + HALF of Y
    localparam CEIL_Y  = HALF_Y;            // ceiling check

    parameter A = 3'b000, B = 3'b001, C = 3'b010, D = 3'b011, E = 3'b100,
              F = 3'b101, G = 3'b110, H = 3'b111, I = 4'd8;   // I = wait for grant to write

    input wire Resetn, Clock;
    input wire key_right;     // KEY[1]
    input wire key_left;      // KEY[3]
    input wire yell_pressed;  // remap to SW[2] for now (future mic input)
    input wire jump_pressed;  // KEY[2]
    
	 //arbiter control
	 input wire gnt;
    output wire req;

	 output wire [7:0] VGA_x;
    output wire [6:0] VGA_y;
    output wire [2:0] VGA_color;
    output wire VGA_write;
	 
	 // give access to x and y so bird/platform doesn't overwrite
	 output wire [7:0] obj_x;
    output wire [6:0] obj_y;
    assign obj_x = X;
    assign obj_y = Y;

    wire [7:0] X, X0;
    reg  [6:0] Y;   // centre row (now a register, for gravity physics)
    wire [3:0] XC;
    wire [3:0] YC;
    reg write, Lxc, Lyc, Exc, Eyc;
    reg erase;
    reg Lx, Ex;
    reg [3:0] y_Q, Y_D;

    reg [2:0] obj_color;

    assign X0 = XOFFSET;

    // direction: right = 1, left = 0
    wire move_dir = key_right;

    // clamp at the left/right screen edge
    wire can_right = (X + HALF_X + 1 < XSCREEN);
    wire can_left  = (X > HALF_X);
    wire move_ok = (key_right && can_right) || (key_left && !key_right && can_left);

    
    reg signed [4:0] vy;  // vertical speed in pixels per tick

    // jump latched so short tap between ticks isn't missed
    reg jump_req;
    always @(posedge Clock)
        if (!Resetn)
            jump_req <= 1'b0;
        else if (y_Q == E)
            jump_req <= 1'b0;
        else if (jump_pressed)
            jump_req <= 1'b1; // only update if pressed and cur state != E

	 // platform collision checked every tick
    //   supported : feet on top of a platform
    //   landed    : this tick's fall would cross a platform top
    wire [NPLAT*8-1:0] pX0 = PLAT_X0;
    wire [NPLAT*8-1:0] pX1 = PLAT_X1;
    wire [NPLAT*8-1:0] pY  = PLAT_Y;
	 
    // next velocity / next row for this tick
    reg supported;
    reg signed [4:0] vy_n;
    reg signed [8:0] y_try;
    reg        [6:0] Y_n;
	 
	 integer i;
    integer bnow, btry, ptop, qx0, qx1, land_row;
    reg landed, ovl;

    always @(*) begin
        bnow = Y + HALF_Y;  // current feet row position

        // colliding with platform
        supported = 1'b0;
        for (i = 0; i < NPLAT; i = i + 1) begin
            ptop = pY[i*8 +: 8];
            qx0  = pX0[i*8 +: 8];
            qx1  = pX1[i*8 +: 8];
            if ((X + HALF_X >= qx0) && (X <= qx1 + HALF_X) && (bnow == ptop - 1))
                supported = 1'b1;
        end

        // update velocity 
        if (supported && jump_req)            vy_n = -JUMP_V;          // jumping
        else if (supported && vy >= 0)        vy_n = 0;                // standing
        else if (vy + GRAVITY > MAX_FALL)     vy_n = MAX_FALL;         // max falling speed
        else                                  vy_n = vy + GRAVITY;     // normal gravity

        // update position
        y_try = $signed({2'b00, Y}) + vy_n;
        Y_n   = y_try[6:0];
        btry  = y_try + HALF_Y;

        // landing this tick?
        landed   = 1'b0;
        land_row = 0;
        for (i = 0; i < NPLAT; i = i + 1) begin
            ptop = pY[i*8 +: 8];
            qx0  = pX0[i*8 +: 8];
            qx1  = pX1[i*8 +: 8];
            ovl  = (X + HALF_X >= qx0) && (X <= qx1 + HALF_X);
            if (ovl && vy_n >= 0 && bnow <= ptop - 1 && btry >= ptop - 1) begin
                // take the highest platform reached
                if (!landed || (ptop - 1 - HALF_Y) < land_row)
                    land_row = ptop - 1 - HALF_Y;
                landed = 1'b1;
            end
        end

        if (landed) begin
            Y_n  = land_row[6:0];
            vy_n = 0;
        end
        else if (y_try < CEIL_Y) begin  // hit the ceiling
            Y_n  = CEIL_Y;
            vy_n = 0;
        end
    end

    // apply the physics once per redraw, as X moves in state E
    always @(posedge Clock)
        if (!Resetn) begin
            Y  <= YOFFSET;
            vy <= 0;
        end
        else if (y_Q == E) begin
            Y  <= Y_n;
            vy <= vy_n;
        end
		  
	 wire airborne   = !supported || (vy != 0);
    wire jump_start = jump_req && supported;

    // redraw when: init, horizontal move, yell change, jump, or in the air
    reg first;        // 1 until the first draw has happened
    reg yell_drawn;   // yell state for the current draw (latched in E)
    wire yell_changed = (yell_pressed != yell_drawn);
    wire redraw = first | move_ok | yell_changed | airborne | jump_start;

    UpDn_count UX (X0, Clock, Resetn, Ex, Lx, move_dir, X);
        defparam UX.n = 8;

    UpDn_count U3 (4'd0, Clock, Resetn, Exc, Lxc, 1'b1, XC);
        defparam U3.n = 4;
    UpDn_count U4 (4'd0, Clock, Resetn, Eyc, Lyc, 1'b1, YC);
        defparam U4.n = 4;

    wire [KK-1:0] slow;
    Up_count U_slow (Clock, Resetn, slow);
        defparam U_slow.n = KK;
    wire speed_sync = (slow == {KK{1'b1}});

    //next-state logic
    always @ (*)
        case (y_Q)
            A:  Y_D = B;
            B:  if (redraw && speed_sync) Y_D = I; //ask for bus first
                else Y_D = B;

            // erase old sprite
            C:  if (XC != BOX_SIZE_X-1) Y_D = C;
                else Y_D = D;
            D:  if (YC != BOX_SIZE_Y-1) Y_D = C;
                else Y_D = E;

            // move (X and Y) + reset pixel counters
            E:  Y_D = F;

            // draw new sprite
            F:  if (XC != BOX_SIZE_X-1) Y_D = F;
                else Y_D = G;
            G:  if (YC != BOX_SIZE_Y-1) Y_D = F;
                else Y_D = H;

            H:  Y_D = B;
				I:  if (gnt) Y_D = C;  // wait for VGA grant
                else Y_D = I;

            default: Y_D = A;
        endcase

    // output logic
    always @ (*)
    begin
        Lx = 1'b0; Ex = 1'b0; write = 1'b0;
        Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; erase = 1'b0;
        case (y_Q)
            A:  begin Lx = 1'b1; end
            B:  begin Lxc = 1'b1; Lyc = 1'b1; end
            C:  begin Exc = 1'b1; write = 1'b1; erase = 1'b1; end
            D:  begin Lxc = 1'b1; Eyc = 1'b1; erase = 1'b1; end
            // X moves here (Y is updated in its own always block, also at E);
            // reload both pixel counters so the draw pass starts at (0,0)
            E:  begin Ex = move_ok; Lxc = 1'b1; Lyc = 1'b1; end
            F:  begin Exc = 1'b1; write = 1'b1; end
            G:  begin Lxc = 1'b1; Eyc = 1'b1; end
            H:  ;
				I:  ;
        endcase
    end
	 
	 //hold request until done drawing
	 assign req = (y_Q >= C) && (y_Q <= I);

    always @(posedge Clock)
        if (!Resetn)
            y_Q <= 4'b0;
        else
            y_Q <= Y_D;

    // latch yell state and clear "first" at the move state
    always @(posedge Clock)
        if (!Resetn) begin
            first <= 1'b1;
            yell_drawn <= 1'b0;
        end
        else if (y_Q == E) begin
            first <= 1'b0;
            yell_drawn <= yell_pressed;
        end

    // 11x13 sprite using 3-bit RGB
    wire glasses = (YC == 0) || (YC == 4) ||
                   (YC <= 4 && (XC == 0 || XC == 5 || XC == 10));
    wire eyes = (YC == 2) && (XC == 3 || XC == 7);

    always @(*) begin
        obj_color = 3'b010; // green body fill

        if (yell_drawn) begin
            if (glasses)
                obj_color = 3'b000;
            else if (eyes)
                obj_color = 3'b000;
            else if (YC == 5 && XC >= 4 && XC <= 6)
                obj_color = 3'b111; // white teeth
            else if (YC == 5 && XC == 7)
                obj_color = 3'b100;
            else if (YC >= 5 && YC <= 7 && XC >= 3 && XC <= 7)
                obj_color = 3'b100; // red tongue
            else if (YC == 8 && XC >= 3 && XC <= 7)
                obj_color = 3'b000; // lips
            else if (XC == 2 && YC >= 5 && YC <= 7)
                obj_color = 3'b000;
            else if (XC == 8 && YC >= 5 && YC <= 7)
                obj_color = 3'b000;
        end
        else begin
            if (glasses)
                obj_color = 3'b000;
            else if (eyes)
                obj_color = 3'b000;
            else if (YC == 6 && XC >= 2 && XC <= 8) // mouth
                obj_color = 3'b000;
        end
    end
	 
	 // current screen coords
    wire [7:0] px = X - HALF_X + XC;
    wire [6:0] py = Y - HALF_Y + YC;

    // what colour to erase to (platform/ground/sky)
    wire [2:0] scene_px;
    scene_color #(.GROUND_Y(GROUND_Y), .BG_COLOR(BG_COLOR), .GROUND_COLOR(GROUND_COLOR),
                  .PLAT_COLOR(PLAT_COLOR), .NPLAT(NPLAT), .PLAT_H(PLAT_H),
                  .PLAT_X0(PLAT_X0), .PLAT_X1(PLAT_X1), .PLAT_Y(PLAT_Y)) SCN (px, py, scene_px);


    regn U7 (X - (BOX_SIZE_X >> 1) + XC, Resetn, 1'b1, Clock, VGA_x);
        defparam U7.n = 8;
    regn U8 (Y - (BOX_SIZE_Y >> 1) + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam U8.n = 7;

    regn U9 (write, Resetn, 1'b1, Clock, VGA_write);
        defparam U9.n = 1;

    wire [2:0] color_next = erase ? scene_px : obj_color;
    regn U10 (color_next, Resetn, 1'b1, Clock, VGA_color);
        defparam U10.n = 3;

endmodule

module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Resetn, E, Clock;
    output reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule

// decodes the byte stream from the course PS2_Controller into
// simpler keypressed signals
//
//   received_data / received_data_en   from PS2_Controller
//                                      (received_data_en = 1-clock pulse per byte)
//   left   = A  or  Left arrow
//   right  = D  or  Right arrow
//   jump   = W  or  Space  or  Up arrow
//
// PS/2 scan codes:
//     press:  <code>                 (repeated about 10x/s while the key is held)
//     release:  F0 <code>
//   "extended" keys (arrows) get an E0 prefix:
//     press:  E0 <code>
//     release:  E0 F0 <code>
// decoder remembers whether it has just seen F0 (release) and/or E0
// (extended), then modifies with the NEXT code properly

module ps2_keys (clock, reset, received_data, received_data_en, left, right, jump);

    // scan codes, from Table 7 of PS/2 controller doc
    parameter [7:0] CODE_A     = 8'h1C;
    parameter [7:0] CODE_D     = 8'h23;
    parameter [7:0] CODE_W     = 8'h1D;
    parameter [7:0] CODE_SPACE = 8'h29;
    // extended keys (arrive as E0, then code)
    parameter [7:0] CODE_LEFT_ARROW  = 8'h6B;
    parameter [7:0] CODE_RIGHT_ARROW = 8'h74;
    parameter [7:0] CODE_UP_ARROW    = 8'h75;

    input  wire clock;
    input  wire reset;   // active HIGH like PS2_Controller
    input  wire [7:0] received_data;
    input  wire received_data_en;
    output wire left, right, jump;

    // track prefixes
    reg got_break;      // F0: the next code is a key RELEASE
    reg got_ext;        // E0: the next code is an extended key

    // one flag per physical key: 1 = currently held down
    reg a_dn, d_dn, w_dn, space_dn;
    reg larrow_dn, rarrow_dn, uarrow_dn;

    always @(posedge clock) begin
        if (reset) begin
            got_break <= 1'b0;
            got_ext   <= 1'b0;
            a_dn <= 1'b0; d_dn <= 1'b0; w_dn <= 1'b0; space_dn <= 1'b0;
            larrow_dn <= 1'b0; rarrow_dn <= 1'b0; uarrow_dn <= 1'b0;
        end
        else if (received_data_en) begin
            case (received_data)
                8'hF0: got_break <= 1'b1;     // prefix: next code is release
                8'hE0: got_ext   <= 1'b1;     // prefix: next code is extended key
                default: begin
                    // key is down unless an F0 came first
                    if (!got_ext) begin
                        if (received_data == CODE_A)     a_dn     <= !got_break;
                        if (received_data == CODE_D)     d_dn     <= !got_break;
                        if (received_data == CODE_W)     w_dn     <= !got_break;
                        if (received_data == CODE_SPACE) space_dn <= !got_break;
                    end
                    else begin // arrow is down unless an F0 came first
                        if (received_data == CODE_LEFT_ARROW)  larrow_dn <= !got_break;
                        if (received_data == CODE_RIGHT_ARROW) rarrow_dn <= !got_break;
                        if (received_data == CODE_UP_ARROW)    uarrow_dn <= !got_break;
                    end
                    // forget the prefixes/other codes we don't care about to restart next loop
                    got_break <= 1'b0;
                    got_ext   <= 1'b0;
                end
            endcase
        end
    end

    assign left  = a_dn | larrow_dn; // combine inputs
    assign right = d_dn | rarrow_dn;
    assign jump  = w_dn | space_dn | uarrow_dn;

endmodule
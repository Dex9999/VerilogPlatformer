
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
// implements a moving colored object
module bird_left (resetn, clock, gnt, req, VGA_x, VGA_y, VGA_color, VGA_write, start, done, busy, y_in, obj_x, obj_y);

    parameter RESOLUTION = "160x120"; 
    parameter nX = 8;
    parameter nY = 7;
    parameter COLOR_DEPTH = 3;
    parameter XSCREEN = 160;
    parameter YSCREEN = 120;
    parameter XDIM = 11, YDIM = 7; // object's width and height
    parameter sky_color = 3'b001; 
    parameter KK = 24; // controls animation speed (use 16 for DESim, 5 for ModelSim)

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


    assign VGA_x = X + XC;                          // pixel x coordinate
    assign VGA_y = Y + YC;                          // pixel y coordinate
    assign VGA_color = erase == 0 ? px_color : sky_color;    // pixel color to draw/erase
    assign VGA_write = write;                       // pixel write control


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
module bird_right (resetn, clock, gnt, req, VGA_x, VGA_y, VGA_color, VGA_write, start, done, busy, y_in, obj_x, obj_y);

    parameter RESOLUTION = "160x120"; 
    parameter nX = 8;
    parameter nY = 7;
    parameter COLOR_DEPTH = 3;
    parameter XSCREEN = 160;
    parameter YSCREEN = 120;
    parameter XDIM = 11, YDIM = 7; // object's width and height
    parameter sky_color = 3'b001; 
    parameter KK = 24; // controls animation speed (use 16 for DESim, 5 for ModelSim)

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


    assign VGA_x = X + XC;                          // pixel x coordinate
    assign VGA_y = Y + YC;                          // pixel y coordinate
    assign VGA_color = erase == 0 ? px_color : sky_color;    // pixel color to draw/erase
    assign VGA_write = write;                       // pixel write control


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

//module wall()

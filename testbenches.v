//module to testbench on

module game_fsm (clock, Resetn, start, sc_done, player_fell, bird_hit, sw_death,
                 in_idle, in_play, in_over, show_frame, run_objects);
    input  wire clock, Resetn;
    input  wire start, sc_done, player_fell, bird_hit, sw_death;
    output reg  in_idle, in_play, in_over;
    output wire show_frame, run_objects;

    localparam [1:0] IDLE = 2'd0, GAME_ON = 2'd1, GAME_OVER = 2'd2;

    wire death = sc_done & (player_fell | bird_hit | sw_death);

    reg [1:0] y_Q, Y_D;

    always @(*)
        case (y_Q)
            IDLE:      Y_D = start ? GAME_ON : IDLE;
            GAME_ON:   Y_D = death ? GAME_OVER : GAME_ON;
            GAME_OVER: Y_D = GAME_OVER;
            default:   Y_D = IDLE;
        endcase

    always @(*) begin
        in_idle = 1'b0; in_play = 1'b0; in_over = 1'b0;
        case (y_Q)
            IDLE:      in_idle = 1'b1;
            GAME_ON:   in_play = 1'b1;
            GAME_OVER: in_over = 1'b1;
        endcase
    end

    always @(posedge clock)
        if (!Resetn) y_Q <= IDLE;
        else         y_Q <= Y_D;

    // frozen-frame window
    reg [16:0] idle_cnt;
    always @(posedge clock)
        if (!in_idle || !sc_done)
            idle_cnt <= 17'd0;
        else if (!idle_cnt[16])
            idle_cnt <= idle_cnt + 1'b1;

    assign show_frame  = in_idle & sc_done & ~idle_cnt[16];
    assign run_objects = in_play | show_frame;
endmodule


//tesbench itself 


`timescale 1ns/1ps

module tb_game_fsm;

    reg clock = 1'b0;
    reg Resetn;
    reg start, player_fell, bird_hit, sw_death;
    wire sc_done_w;
    wire in_idle, in_play, in_over, show_frame, run_objects;

    always #10 clock = ~clock;   // 50 MHz

    // ---------------- scene_draw model ----------------
    // scene_draw is held in reset when scene_resetn is low, and asserts
    // sc_done some cycles after it is released (same condition as the top level).
    wire scene_resetn = Resetn & (in_idle | in_play);
    reg  [7:0] sc_cnt;
    reg        sc_done;
    always @(posedge clock)
        if (!scene_resetn) begin sc_cnt <= 8'd0; sc_done <= 1'b0; end
        else if (sc_cnt == 8'd50) sc_done <= 1'b1;
        else sc_cnt <= sc_cnt + 1'b1;

    // ---------------- DUT ----------------
    game_fsm DUT (clock, Resetn, start, sc_done, player_fell, bird_hit, sw_death,
                  in_idle, in_play, in_over, show_frame, run_objects);

    // ---------------- checking helpers ----------------
    integer errors = 0;

    task check;
        input cond;
        input [8*48:1] msg;
        begin
            if (cond) $display("%0t  PASS  %0s", $time, msg);
            else begin
                $display("%0t  FAIL  %0s", $time, msg);
                errors = errors + 1;
            end
        end
    endtask

    task do_reset;
        begin
            Resetn = 1'b0;
            repeat (4) @(posedge clock);
            #1 Resetn = 1'b1;
        end
    endtask

    task wait_scene;     // wait until the scene painter is done
        begin
            while (!sc_done) @(posedge clock);
            @(posedge clock);
        end
    endtask

    task press_start;    // one-cycle start pulse
        begin
            @(posedge clock); #1 start = 1'b1;
            @(posedge clock); #1 start = 1'b0;
            @(posedge clock); #1;
        end
    endtask

    task kill;           // pulse a death source for 3 clocks
        input [1:0] which;   // 0 = fell, 1 = bird, 2 = SW[1]
        begin
            @(posedge clock); #1;
            case (which)
                2'd0: player_fell = 1'b1;
                2'd1: bird_hit    = 1'b1;
                default: sw_death = 1'b1;
            endcase
            repeat (3) @(posedge clock);
            #1 player_fell = 1'b0; bird_hit = 1'b0; sw_death = 1'b0;
            @(posedge clock); #1;
        end
    endtask

    // ---------------- stimulus ----------------
    initial begin
        start = 0; player_fell = 0; bird_hit = 0; sw_death = 0;
        Resetn = 1'b0;
        #100;

        // TEST 1: reset puts FSM in IDLE
        $display("--- TEST 1: reset -> IDLE");
        do_reset;
        check(in_idle && !in_play && !in_over, "IDLE after reset");
        check(!show_frame && !run_objects,     "objects held in reset before sc_done");

        // TEST 2: frozen-frame window
        $display("--- TEST 2: frozen frame window in IDLE");
        wait_scene;
        repeat (100) @(posedge clock);
        check(in_idle,       "still IDLE, no start pressed");
        check(show_frame,    "show_frame high just after scene done");
        check(run_objects,   "objects released to draw first frame");
        repeat (65600) @(posedge clock);
        check(in_idle,       "still IDLE after window");
        check(!show_frame,   "show_frame low after window (frame frozen)");
        check(!run_objects,  "objects back in reset (frame frozen)");

        // TEST 3: start leaves IDLE
        $display("--- TEST 3: start -> GAME_ON");
        press_start;
        check(in_play && !in_idle,  "GAME_ON after start");
        check(run_objects,          "objects running in GAME_ON");
        check(sc_done,              "scene not repainted (sc_done stays high)");

        // TEST 4: no death without a death source
        $display("--- TEST 4: stays in GAME_ON");
        repeat (500) @(posedge clock);
        check(in_play, "GAME_ON holds with no death source");

        // TEST 5: each death source
        $display("--- TEST 5a: player_fell -> GAME_OVER");
        kill(2'd0);
        check(in_over && !in_play,  "GAME_OVER on player_fell");
        check(!run_objects,         "objects stopped in GAME_OVER");

        // TEST 6: GAME_OVER is sticky
        $display("--- TEST 6: GAME_OVER is sticky");
        press_start;
        repeat (200) @(posedge clock);
        check(in_over, "start ignored in GAME_OVER");
        check(!sc_done, "scene painter held in reset in GAME_OVER");

        // TEST 7: reset from GAME_OVER gives the frozen frame
        $display("--- TEST 7: reset from GAME_OVER -> frozen frame");
        do_reset;
        check(in_idle && !in_over, "IDLE after reset from GAME_OVER");
        wait_scene;
        repeat (100) @(posedge clock);
        check(show_frame, "first frame drawn again after reset");
        repeat (65600) @(posedge clock);
        check(in_idle && !show_frame, "frame frozen, waiting for start");

        // TEST 8: bird_hit
        $display("--- TEST 8: bird_hit -> GAME_OVER");
        press_start;
        repeat (50) @(posedge clock);
        kill(2'd1);
        check(in_over, "GAME_OVER on bird_hit");

        // TEST 9: SW[1] fake death
        $display("--- TEST 9: SW[1] -> GAME_OVER");
        do_reset; wait_scene;
        press_start;
        repeat (50) @(posedge clock);
        kill(2'd2);
        check(in_over, "GAME_OVER on SW[1]");

        // TEST 10: death ignored while scene not done
        $display("--- TEST 10: death gated by sc_done");
        do_reset;
        press_start;                    // start right away, sc_done still 0
        check(in_play && !sc_done, "GAME_ON entered before scene done");
        @(posedge clock); #1 player_fell = 1'b1;
        repeat (5) @(posedge clock);
        check(in_play, "death ignored while sc_done = 0");
        #1 player_fell = 1'b0;
        wait_scene;
        repeat (10) @(posedge clock);
        check(in_play, "still GAME_ON once scene finishes");

        // TEST 11: start pressed inside the frame window
        $display("--- TEST 11: start during frame window");
        do_reset; wait_scene;
        repeat (20) @(posedge clock);
        check(show_frame, "inside the window");
        press_start;
        check(in_play && run_objects, "GAME_ON, objects keep running (seamless)");

        // TEST 12: reset in the middle of a game
        $display("--- TEST 12: reset mid-game");
        repeat (100) @(posedge clock);
        do_reset;
        check(in_idle, "IDLE after mid-game reset");

        $display("======================================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("======================================");
        $stop;
    end

    // watchdog
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $stop;
    end

endmodule



// run in modelsim


vlib work
vlog game_fsm.v tb_game_fsm.v
vsim -novopt tb_game_fsm
add wave -divider FSM
add wave -radix unsigned sim:/tb_game_fsm/DUT/y_Q
add wave sim:/tb_game_fsm/clock sim:/tb_game_fsm/Resetn sim:/tb_game_fsm/start
add wave sim:/tb_game_fsm/sc_done sim:/tb_game_fsm/player_fell sim:/tb_game_fsm/bird_hit sim:/tb_game_fsm/sw_death
add wave sim:/tb_game_fsm/in_idle sim:/tb_game_fsm/in_play sim:/tb_game_fsm/in_over
add wave sim:/tb_game_fsm/show_frame sim:/tb_game_fsm/run_objects
run -all

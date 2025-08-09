// Joystick Module - Implements PC-compatible joystick interface with support for:
// - Standard analog joysticks or digital joysticks/gamepads
// - Options to use timed (IBM joystick time formula) or count methods
// - Gravis GamePad Pro (Gravis Interface Protocol (GrIP))

module joystick
(
  input            rst_n,
  input            clk,

  input  [27:0]    clock_rate,

  input [13:0]     dig_1, // joystick_0[13:0] & dig_mask[13:0]
  input [13:0]     dig_2, // status[47] ? 14'd0 : (joystick_1[13:0] & dig_mask[13:0])
  input [15:0]     ana_1, // { ja_1y[7:0], ja_1x[7:0] }
  input [15:0]     ana_2, // { ja_2y[7:0], ja_2x[7:0] }
  input  [1:0]     mode,  // status[13:12] 0=2_Buttons, 1=4_Buttons, 2=Gravis_Pro, 3=None
  input  [1:0]     timed, // status[59:58] 0=Timed, 1=Count_8+141, 2=Count_0+256, 3=Count_6+256
  input  [1:0]     dis,   // joystick_dis[1:0]

  input            read,
  input            write,
  output reg [7:0] readdata
);

localparam signed [7:0] ANALOG_ACTIVITY_THRESHOLD = 8'd60; // threshold used to detect analog input activity
wire ana_1_activity = $signed(ana_1[ 7:0]) < -ANALOG_ACTIVITY_THRESHOLD || ANALOG_ACTIVITY_THRESHOLD < $signed(ana_1[ 7:0]) ||
                      $signed(ana_1[15:8]) < -ANALOG_ACTIVITY_THRESHOLD || ANALOG_ACTIVITY_THRESHOLD < $signed(ana_1[15:8]);
wire ana_2_activity = $signed(ana_2[ 7:0]) < -ANALOG_ACTIVITY_THRESHOLD || ANALOG_ACTIVITY_THRESHOLD < $signed(ana_2[ 7:0]) ||
                      $signed(ana_2[15:8]) < -ANALOG_ACTIVITY_THRESHOLD || ANALOG_ACTIVITY_THRESHOLD < $signed(ana_2[15:8]);

// 20 kHz clock for Gravis Interface Protocol (GrIP)
reg clk_grav;
always @(posedge clk) begin
  reg [27:0] sum_grav = 28'd0;

  sum_grav = sum_grav + 16'd40000;
  if(sum_grav >= clock_rate) begin
    sum_grav = sum_grav - clock_rate;
    clk_grav = ~clk_grav;
  end
end

// 1.1 us tick used for the IBM joystick time formula
// (see the relevant code below for more information)
reg tick_1100ns;
always @(posedge clk) begin
  reg [27:0] sum_timed = 28'd0;

  sum_timed = write ? 28'd0 : sum_timed + 20'd909091; // tick every 1.1 us
  tick_1100ns = 1'b0;
  if(sum_timed >= clock_rate) begin
    sum_timed = sum_timed - clock_rate;
    tick_1100ns = 1'b1;
  end
end

reg [10:0] j1x, j1y, j2x, j2y; // axis measurement countdown value
reg        jb1, jb2, jb3, jb4; // button (active low)

// Allow jb3 and jb4 when:
// - Joystick Type: 4 Buttons
// - Joystick 1:    Enabled
// - Joystick 2:    Disabled
wire dis_jb3_jb4 = dis[1] && ~(mode==2'd1 && dis==2'b10);

// Read data
always @(posedge clk) begin
  readdata <= (mode==2'd3) ? 8'hff : // None
                            {      jb4,    jb3,    jb2,    jb1,   |j2y,   |j2x,   |j1y,   |j1x } |
                            { {2{dis_jb3_jb4}}, dis[0], dis[0], dis[1], dis[1], dis[0], dis[0] }; // disable mask
end

wire JOY1_RIGHT = dig_1[0];
wire JOY1_LEFT  = dig_1[1];
wire JOY1_DOWN  = dig_1[2];
wire JOY1_UP    = dig_1[3];
wire JOY1_BUT1  = dig_1[4];
wire JOY1_BUT2  = dig_1[5];
wire JOY1_BUT3  = dig_1[6];
wire JOY1_BUT4  = dig_1[7];
wire JOY1_START = dig_1[8];
wire JOY1_SEL   = dig_1[9];
wire JOY1_R1    = dig_1[10];
wire JOY1_L1    = dig_1[11];
wire JOY1_R2    = dig_1[12];
wire JOY1_L2    = dig_1[13];

wire JOY2_RIGHT = dig_2[0];
wire JOY2_LEFT  = dig_2[1];
wire JOY2_DOWN  = dig_2[2];
wire JOY2_UP    = dig_2[3];
wire JOY2_BUT1  = dig_2[4];
wire JOY2_BUT2  = dig_2[5];
wire JOY2_BUT3  = dig_2[6];
wire JOY2_BUT4  = dig_2[7];
wire JOY2_START = dig_2[8];
wire JOY2_SEL   = dig_2[9];
wire JOY2_R1    = dig_2[10];
wire JOY2_L1    = dig_2[11];
wire JOY2_R2    = dig_2[12];
wire JOY2_L2    = dig_2[13];

reg read_last;

// Used to auto switch between 0=analog and 1=dpad when input activity is detected
reg use_dpad1, use_dpad2;

// Gravis Interface Protocol (GrIP)
reg       gravis_clk;
reg [1:0] gravis_out;
reg [4:0] gravis_pos;

// Current joystick position value in the range [0,255]
reg [7:0] j1x_pos, j1y_pos, j2x_pos, j2y_pos;

always @(posedge clk) begin : joy_block
  if (!rst_n) begin
    j1x <= 11'd128; // center
    j1y <= 11'd128; // center
    j2x <= 11'd128; // center
    j2y <= 11'd128; // center
    {jb1, jb2, jb3, jb4} <= 4'b1111; // buttons not pressed (active low)

    use_dpad1 <= 1'b1; // d-pad
    use_dpad2 <= 1'b1; // d-pad

    gravis_clk <= 1'b0;
    gravis_out <= 2'b00;
    gravis_pos <= 5'd0;
  end else begin
    // Button assignment
    if (mode==2'd2) begin
      // Gravis Pro
      jb1 <= gravis_clk;
      jb2 <= gravis_out[0];
      jb3 <= gravis_clk;
      jb4 <= gravis_out[1];
    end else begin
      jb1 <= !JOY1_BUT1;
      jb2 <= !JOY1_BUT2;
      jb3 <= (mode==2'd1) ? !JOY1_BUT3 : !JOY2_BUT1;
      jb4 <= (mode==2'd1) ? !JOY1_BUT4 : !JOY2_BUT2;
    end

    // Gravis Interface Protocol (GrIP)
    //
    // Gravis Pro:
    // Gravis Gamepad Pro uses a serial protocol. Button 0 is 20-25khz 50% duty cycle clock for P1, and
    // Button 1 is the data line, with 1 indicating a button is held, and 0 not held. The same applies
    // to Player 2, but with buttons 2 and 3. The analog axis pins appear to be unused, but possibly
    // should be set to either 0 or 1 and left there. I have left them in case there is any variant of
    // this controller that also has an analog input. They seem not to matter. On each falling edge of
    // each B0 clock, the state of B1 is read. Frames are 24 bits long and is formatted as follows:
    //
    //  -----------------------------------------------
    // |0      |1      |1      |1      |1      |1      |
    // |0      |Select |Start  |R2     |Blue   |       |
    // |0      |L2     |Green  |Yellow |Red    |       |
    // |0      |L1     |R1     |Up     |Down   |       |
    // |0      |Right  |Left   |       |       |       |
    //  -----------------------------------------------
    //
    // There is a frame identification header of 0 and then 5 1's, after which the button states are
    // read out in groups of four bits or less, each group preceeded by a 0. Presumptively this format
    // prevents any false positives for frame header detection.
    //
    gravis_clk <= clk_grav;
    if (~gravis_clk & clk_grav) begin
      gravis_pos <= (gravis_pos == 5'd23) ? 5'd0 : gravis_pos + 5'd1;

      case (gravis_pos)
        0, 6, 11, 16, 21:
            gravis_out <= {1'b0,       1'b0};

        1, 2, 3, 4, 5:
            gravis_out <= {1'b1,       1'b1};

         7: gravis_out <= {JOY2_SEL,   JOY1_SEL};
         8: gravis_out <= {JOY2_START, JOY1_START};
         9: gravis_out <= {JOY2_R2,    JOY1_R2};
        10: gravis_out <= {JOY2_BUT4,  JOY1_BUT4};

        12: gravis_out <= {JOY2_L2,    JOY1_L2};
        13: gravis_out <= {JOY2_BUT2,  JOY1_BUT2};
        14: gravis_out <= {JOY2_BUT1,  JOY1_BUT1};
        15: gravis_out <= {JOY2_BUT3,  JOY1_BUT3};

        17: gravis_out <= {JOY2_L1,    JOY1_L1};
        18: gravis_out <= {JOY2_R1,    JOY1_R1};
        19: gravis_out <= {JOY2_UP,    JOY1_UP};
        20: gravis_out <= {JOY2_DOWN,  JOY1_DOWN};

        22: gravis_out <= {JOY2_RIGHT, JOY1_RIGHT};
        23: gravis_out <= {JOY2_LEFT,  JOY1_LEFT};
        default: ;
      endcase
    end

    // Auto switch between analog or dpad input
    // - Analog: when analog activity threshold crossing is detected
    // - D-pad: when digital input is detected and there was no analog activity detected
    if(ana_1_activity)  use_dpad1 <= 1'b0;
    else if(dig_1[3:0]) use_dpad1 <= 1'b1;
    if(ana_2_activity)  use_dpad2 <= 1'b0;
    else if(dig_2[3:0]) use_dpad2 <= 1'b1;

    if (write) begin
      // Get the current joystick position values in the range [0,255] at the start of a measurement.
      
      j1x_pos = ~use_dpad1  ? { ~ana_1[7],  ana_1[6:0] }  : // convert signed [-128,127] => unsigned [0,255]
                 JOY1_LEFT  ? 8'd0   : // d-pad 1 left
                 JOY1_RIGHT ? 8'd255 : // d-pad 1 right
                              8'd128;  // d-pad 1 center

      j1y_pos = ~use_dpad1  ? { ~ana_1[15], ana_1[14:8] } : // convert signed [-128,127] => unsigned [0,255]
                 JOY1_UP    ? 8'd0   : // d-pad 1 up
                 JOY1_DOWN  ? 8'd255 : // d-pad 1 down
                              8'd128;  // d-pad 1 center

      j2x_pos = ~use_dpad2  ? { ~ana_2[7],  ana_2[6:0] }  : // convert signed [-128,127] => unsigned [0,255]
                 JOY2_LEFT  ? 8'd0   : // d-pad 2 left
                 JOY2_RIGHT ? 8'd255 : // d-pad 2 right
                              8'd128;  // d-pad 2 center

      j2y_pos = ~use_dpad2  ? { ~ana_2[15], ana_2[14:8] } : // convert signed [-128,127] => unsigned [0,255]
                 JOY2_UP    ? 8'd0   : // d-pad 2 up
                 JOY2_DOWN  ? 8'd255 : // d-pad 2 down
                              8'd128;  // d-pad 2 center

      // Games often use either a timed method or count method to determine the joystick position.
      // 
      // Timed
      // -----
      // Simulates the charging of a capacitor, as used to measure
      // the resistance value (position) of the potentiometer inside the joystick
      // Note: Uses the IBM joystick time formula (see below)
      // 
      // Count
      // -----
      // The joystick position is determined by the number of reads required
      // before the signal goes low (the number of reads are counted in software)
      // Note: Smaller value ranges allow the joystick position to be determined
      //       more quickly, but with maybe reduced resolution (good for platformers)
      //       (for Jazz Jackrabbit the max count value seems to be 1000)
      // Note: For flight simulators with analog joystick support the Count 256 mode
      //       offers the full analog resolution currently provided
      // Note: This mode might resolve joystick drift issues
      // Note: Count 8+141 mode is compatible with the DOS game Paratrooper,
      //       but can also be used for other games (e.g. platformers)
      case(timed)
        2'd0: begin // Timed
          // IBM Joystick Time = 24.2 us + 0.011 (r) us = 0.011 * (2200 + r) us
          // The typical potentiometer resistor value r seems to be around 100 kOhm
          // Note: The 24.2 us accommodates a 2.2 kOhm resistor in series with the potentiometer
          // 
          // In timed mode this value simulates the time needed to charge a capacitor
          // through the potentiometer of the joytick to determine the position
          // 
          // Map joystick axis position range [0,255] to potentiometer resistance range [0,1000]
          // Note: Potentiometer resistance is divided by 100, so the value 1000 represents a 100 kOhm pot
          // Note: The timed countdown is clocked by tick_1100ns (1.1 us)
          // Note: joy = 22 + (1000 * pos/255) = 22 + 1000/255 * pos
          j1x <= 5'd22 + (j1x_pos == 8'd255 ? 11'd1000 : (j1x_pos << 2) - (j1x_pos >> 4) - (j1x_pos >> 6) - (j1x_pos >> 8));
          j1y <= 5'd22 + (j1y_pos == 8'd255 ? 11'd1000 : (j1y_pos << 2) - (j1y_pos >> 4) - (j1y_pos >> 6) - (j1y_pos >> 8));
          j2x <= 5'd22 + (j2x_pos == 8'd255 ? 11'd1000 : (j2x_pos << 2) - (j2x_pos >> 4) - (j2x_pos >> 6) - (j2x_pos >> 8));
          j2y <= 5'd22 + (j2y_pos == 8'd255 ? 11'd1000 : (j2y_pos << 2) - (j2y_pos >> 4) - (j2y_pos >> 6) - (j2y_pos >> 8));
        end
        2'd1: begin // Count 8+141
          // DOS game Paratrooper compatible mappings:
          // Map [0,255] ->  5 + [0,146]
          // Map [0,255] ->  6 + [0,144]
          // Map [0,255] ->  7 + [0,142]
          // Map [0,255] ->  8 + [0,140]
          // Map [0,255] ->  9 + [0,138]
          // Map [0,255] -> 10 + [0,136]
          // Map [0,255] -> 11 + [0,134]
          // 
          // Map [0,255] -> 8 + [0,140]
          j1x <= 4'd8 + (j1x_pos >> 1) + (j1x_pos >> 4) - (j1x_pos >> 7) - (j1x_pos >> 7);
          j1y <= 4'd8 + (j1y_pos >> 1) + (j1y_pos >> 4) - (j1y_pos >> 7) - (j1y_pos >> 7);
          j2x <= 4'd8 + (j2x_pos >> 1) + (j2x_pos >> 4) - (j2x_pos >> 7) - (j2x_pos >> 7);
          j2y <= 4'd8 + (j2y_pos >> 1) + (j2y_pos >> 4) - (j2y_pos >> 7) - (j2y_pos >> 7);
        end
        2'd2: begin // Count 0+256
          // Map: [0,255] -> [0,255]
          j1x <= j1x_pos;
          j1y <= j1y_pos;
          j2x <= j2x_pos;
          j2y <= j2y_pos;
        end
        2'd3: begin // Count 6+256
          // Map: [0,255] -> 6 + [0,255]
          // TODO: Change this to something more useful for certain games?
          j1x <= 3'd6 + j1x_pos;
          j1y <= 3'd6 + j1y_pos;
          j2x <= 3'd6 + j2x_pos;
          j2y <= 3'd6 + j2y_pos;
        end
        default: ;
      endcase
    end

    read_last <= read;
    if (timed==2'd0 ? tick_1100ns : read_last && ~read) begin
      if (j1x) j1x <= j1x - 1'b1;
      if (j1y) j1y <= j1y - 1'b1;
      if (j2x) j2x <= j2x - 1'b1;
      if (j2y) j2y <= j2y - 1'b1;
    end

  end
end

endmodule

// (C) 2001-2017 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel MegaCore Function License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.

// original file was altera_pll_reconfig_core.v 
// not needed functionality was cut out to reduce ressource consumption

module pll_cfg_hdmi
#(
    parameter 	reconf_width       	= 64,
    parameter 	device_family       	= "Cyclone V"
) ( 

    //input
    input   wire    mgmt_clk,
    input   wire    mgmt_reset,


    //conduits
    output  wire [reconf_width-1:0] reconfig_to_pll,
    input  wire [reconf_width-1:0] reconfig_from_pll,

    // user data (avalon-MM slave interface)
    output  wire        mgmt_waitrequest,
    input   wire [5:0]  mgmt_address,
    input   wire        mgmt_write,
    input   wire [31:0] mgmt_writedata
);
    localparam mode_WR            = 1'b0;
    localparam MODE_REG           = 6'b000000;
    localparam START_REG          = 6'b000010;
    localparam N_REG              = 6'b000011;
    localparam M_REG              = 6'b000100;
    localparam C_COUNTERS_REG     = 6'b000101;
    //localparam DPS_REG            = 6'b000110; // unused
    localparam DSM_REG            = 6'b000111;
    localparam BWCTRL_REG         = 6'b001000; 
    localparam CP_CURRENT_REG     = 6'b001001;
    //localparam ANY_DPRIO          = 6'b100000; // unused
    //localparam CNT_BASE           = 5'b001010; // unused
    //localparam VCO_REG              = 6'b011100; // unused
    
    //C Counters
    localparam number_of_counters = 5'd6;
    //C counter addresses
    localparam C_CNT_0_DIV_ADDR = 5'h00;
    localparam C_CNT_0_DIV_ADDR_DPRIO_1 = 5'h11;
    localparam C_CNT_0_3_BYPASS_EN_ADDR = 5'h15;
    localparam C_CNT_0_3_ODD_DIV_EN_ADDR = 5'h17;
    localparam C_CNT_4_17_BYPASS_EN_ADDR = 5'h14;
    localparam C_CNT_4_17_ODD_DIV_EN_ADDR = 5'h16;
    //N counter addresses
    localparam N_CNT_DIV_ADDR = 5'h13;
    localparam N_CNT_BYPASS_EN_ADDR = 5'h15;
    localparam N_CNT_ODD_DIV_EN_ADDR = 5'h17;
    //M counter addresses
    localparam M_CNT_DIV_ADDR = 5'h12;
    localparam M_CNT_BYPASS_EN_ADDR = 5'h15;
    localparam M_CNT_ODD_DIV_EN_ADDR = 5'h17;
    
    //DSM address
    localparam DSM_K_FRACTIONAL_DIVISION_ADDR_0 = 5'h18;
    localparam DSM_K_FRACTIONAL_DIVISION_ADDR_1 = 5'h19;
    localparam DSM_K_READY_ADDR = 5'h17;
    localparam DSM_K_DITHER_ADDR = 5'h17;
    localparam DSM_OUT_SEL_ADDR = 6'h30;
    
    //Other DSM params
    localparam DSM_K_READY_BIT_INDEX = 4'd11;
    //BWCTRL address
    //Bit 0-3 of addr
    localparam BWCTRL_ADDR = 6'h30;
    //CP_CURRENT address
    //Bit 0-2 of addr
    localparam CP_CURRENT_ADDR = 6'h31;
    
    // VCODIV address
    localparam VCO_ADDR = 5'h17;

    localparam DPRIO_IDLE = 3'd0, ONE = 3'd1, TWO = 3'd2, THREE = 3'd3, FOUR = 3'd4,
               FIVE = 3'd5, SIX = 3'd6, SEVEN = 3'd7, EIGHT = 4'd8, NINE = 4'd9, TEN = 4'd10,
               ELEVEN = 4'd11, TWELVE = 4'd12, THIRTEEN = 4'd13, FOURTEEN = 4'd14, DPRIO_DONE = 4'd15;
    localparam IDLE = 2'b00, WAIT_ON_LOCK = 2'b01, LOCKED = 2'b10;
    
    wire            clk;
    wire            reset;
    wire            gnd;

    wire [5: 0]     slave_address;
    wire            slave_write;
    wire [31: 0]    slave_writedata;

    wire            slave_waitrequest;
    reg             slave_mode;

    assign          clk             = mgmt_clk;

    assign          slave_address       = mgmt_address;    
    assign          slave_write         = mgmt_write;
    assign          slave_writedata     = mgmt_writedata;
    
    // Outputs
    assign          mgmt_waitrequest    = slave_waitrequest; //Read waitrequest asserted in polling mode

    //internal signals
    wire            locked_orig;
    wire            locked;
   
    wire            pll_start;
    wire            pll_start_valid;

    wire            pll_start_asserted;

    reg  [1:0]      current_state;
    reg  [1:0]      next_state;

    reg             status;//0=busy, 1=ready
    //user_mode_init user_mode_init_inst (clk, reset, dprio_mdio_dis, ser_shift_load);
    //declaring the init wires. These will have 0 on them for 64 clk cycles
    wire       [ 5:0]  init_dprio_address;
    wire               init_dprio_read;
    wire       [ 1:0]  init_dprio_byteen;
    wire               init_dprio_write;
    wire       [15:0]  init_dprio_writedata;

    wire               init_atpgmode;
    wire               init_mdio_dis;
    wire               init_scanen;
    wire               init_ser_shift_load;
    wire               dprio_init_done;

    //DPRIO output signals after initialization is done
    wire            dprio_clk;
    reg             avmm_dprio_write;
    reg             avmm_dprio_read;
    reg  [5:0]      avmm_dprio_address;
    reg  [15:0]     avmm_dprio_writedata;
    reg  [1:0]      avmm_dprio_byteen;
    wire            avmm_atpgmode;
    wire            avmm_mdio_dis;
    wire            avmm_scanen;

    //Final output wires that are muxed between the init and avmm wires.
    wire            dprio_init_reset;
    wire [5:0]      dprio_address /*synthesis keep*/;
    wire            dprio_read/*synthesis keep*/;
    wire [1:0]      dprio_byteen/*synthesis keep*/;
    wire            dprio_write/*synthesis keep*/;
    wire [15:0]     dprio_writedata/*synthesis keep*/;
    wire            dprio_mdio_dis/*synthesis keep*/;
    wire            dprio_ser_shift_load/*synthesis keep*/;
    wire            dprio_atpgmode/*synthesis keep*/;
    wire            dprio_scanen/*synthesis keep*/;


    //other PLL signals for dyn ph shift
    wire            phase_done/*synthesis keep*/;
    wire            phase_en/*synthesis keep*/;
    wire            up_dn/*synthesis keep*/;
    wire  [4:0]     cnt_sel;
    
    //DPRIO input signals
    wire  [15:0]     dprio_readdata;

    //internal logic signals
    //storage registers for user sent data
    reg             dprio_temp_read_1;
    reg             dprio_temp_read_2;
    reg             dprio_start;
    wire            usr_valid_changes;
    reg  [3:0]      dprio_cur_state;
    reg  [3:0]      dprio_next_state;
    reg  [15:0]     dprio_temp_m_n_c_readdata_1_d;
    reg  [15:0]     dprio_temp_m_n_c_readdata_2_d;
    reg  [15:0]     dprio_temp_m_n_c_readdata_1_q;
    reg  [15:0]     dprio_temp_m_n_c_readdata_2_q;
	reg 			dprio_write_done;
    //C counters signals
    reg  [7:0]      usr_c_cnt_lo;
    reg  [7:0]      usr_c_cnt_hi;
    reg             usr_c_cnt_bypass_en;
    reg             usr_c_cnt_odd_duty_div_en;
    reg             temp_c_cnt_bypass_en [0:17];
    reg      	    temp_c_cnt_odd_duty_div_en [0:17];
    reg             any_c_cnt_changed;
    reg             all_c_cnt_done_q;
    reg             all_c_cnt_done_d;
    reg  [17:0]     c_cnt_changed;
    reg  [17:0]     c_cnt_done_d;
    reg  [17:0]     c_cnt_done_q;
    //N counter signals
    reg  [7:0]      usr_n_cnt_lo; 
    reg  [7:0]      usr_n_cnt_hi;
    reg             usr_n_cnt_bypass_en;
    reg             usr_n_cnt_odd_duty_div_en;
    reg             n_cnt_changed;
    reg             n_cnt_done_d;
    reg             n_cnt_done_q;
    //M counter signals
    reg  [7:0]      usr_m_cnt_lo; 
    reg  [7:0]      usr_m_cnt_hi;
    reg             usr_m_cnt_bypass_en;
    reg             usr_m_cnt_odd_duty_div_en;
    reg             m_cnt_changed;
    reg             m_cnt_done_d;
    reg             m_cnt_done_q;
    //dyn phase regs
    reg  [15:0]     usr_num_shifts;
    reg  [4:0]      usr_cnt_sel /*synthesis preserve*/;
    reg             usr_up_dn;
    reg             dps_changed;
    wire            dps_changed_valid;
    wire            dps_done;

    //DSM Signals
    reg  [31:0]     usr_k_value;
    reg             dsm_k_changed;
    reg             dsm_k_done_d;
    reg             dsm_k_done_q;
    reg             dsm_k_ready_false_done_d;
    //BW signals 
    reg [3:0]       usr_bwctrl_value;
    reg             bwctrl_changed;
    reg             bwctrl_done_d;
    reg             bwctrl_done_q;
    //CP signals 
    reg [2:0]       usr_cp_current_value;
    reg             cp_current_changed;
    reg             cp_current_done_d;
    reg             cp_current_done_q;
    //VCO signals 
    reg             usr_vco_value;
    reg             vco_changed;
    reg             vco_done_d;
    reg             vco_done_q;
    //Manual DPRIO signals
    reg             manual_dprio_done_q;
    reg             manual_dprio_done_d;
    reg             manual_dprio_changed;
    reg  [5:0]      usr_dprio_address;
    reg  [15:0]     usr_dprio_writedata_0;
    reg             usr_r_w;
	 //keeping track of which operation happened last
	 reg  [5:0]		  operation_address;
    // Address wires for all C_counter DPRIO registers
    // These are outputs of LUTS, changing depending
    // on whether PLL_0 or PLL_1 being used


    //Fitter will tell if FPLL1 is being used 
    wire            fpll_1;

    // MAIN FSM                             

    // Synchronize locked signal
   altera_std_synchronizer #(
        .depth(3)
    ) altera_std_synchronizer_inst (
        .clk(mgmt_clk),
        .reset_n(~mgmt_reset), 
        .din(locked_orig),
        .dout(locked)
    );
   
    always @(posedge clk)
    begin
        if (reset)
        begin
            dprio_cur_state <= DPRIO_IDLE;
            current_state <= IDLE;
        end
        else
        begin
            current_state <= next_state;
            dprio_cur_state <= dprio_next_state;
        end
    end

    always @(*)
     begin
        case(current_state)
          IDLE:
            begin
               if (pll_start & !slave_waitrequest & usr_valid_changes)
                 next_state = WAIT_ON_LOCK;
               else
                 next_state = IDLE;
            end
          WAIT_ON_LOCK:
            begin
               if (locked & dps_done & dprio_write_done)  // received locked high from PLL
                 begin
                    if (slave_mode==mode_WR) //if the mode is waitrequest, then
                                             // goto IDLE state directly
                      next_state = IDLE;
                    else
                      next_state = LOCKED; //otherwise go the locked state
                 end
               else
                  next_state = WAIT_ON_LOCK;
            end
              
          LOCKED:
            begin
               next_state = LOCKED;
            end

          default: next_state = 2'bxx;
          
        endcase
     end


    // ask the pll to start reconfig
    assign pll_start = (pll_start_asserted & (current_state==IDLE))  ;
    assign pll_start_valid = (pll_start & (next_state==WAIT_ON_LOCK))  ;



    // WRITE OPERATIONS
    assign pll_start_asserted = slave_write & (slave_address == START_REG);

    //reading the mode register to determine what mode the slave will operate
    //in.
    always @(posedge clk)
    begin
        if (reset)
          slave_mode <= mode_WR;
        else if (slave_write & (slave_address == MODE_REG) & !slave_waitrequest)
          slave_mode <= slave_writedata[0];
    end

    //record which values user wants to change.

    //reading in the actual values that need to be reconfigged and sending
    //them to the PLL
    always @(posedge clk)
    begin
        if (reset)
        begin
            //reset all regs here
            //BW signals reset
            usr_bwctrl_value <= 0;
            bwctrl_changed <= 0;
            bwctrl_done_q <= 0;
            //CP signals reset
            usr_cp_current_value <= 0;
            cp_current_changed <= 0;
            cp_current_done_q <= 0;
            //VCO signals reset
            usr_vco_value <= 0;
            vco_changed <= 0;
            vco_done_q <= 0;
            //DSM signals reset
            usr_k_value <= 0;
            dsm_k_changed <= 0;
            dsm_k_done_q <= 0;
            //N counter signals reset
            usr_n_cnt_lo <= 0;
            usr_n_cnt_hi <= 0;
            usr_n_cnt_bypass_en <= 0;
            usr_n_cnt_odd_duty_div_en <= 0;
            n_cnt_changed <= 0;
            n_cnt_done_q <= 0;
            //M counter signals reset
            usr_m_cnt_lo <= 0;
            usr_m_cnt_hi <= 0;
            usr_m_cnt_bypass_en <= 0;
            usr_m_cnt_odd_duty_div_en <= 0;
            m_cnt_changed <= 0;
            m_cnt_done_q <= 0;
            //C counter signals reset
            usr_c_cnt_lo <= 0;
            usr_c_cnt_hi <= 0;
            usr_c_cnt_bypass_en <= 0;
            usr_c_cnt_odd_duty_div_en <= 0;
            any_c_cnt_changed <= 0;
            all_c_cnt_done_q <= 0;
            c_cnt_done_q <= 0;
            //generic signals
            dprio_start <= 0;
            dprio_temp_m_n_c_readdata_1_q <= 0;
            dprio_temp_m_n_c_readdata_2_q <= 0;
            c_cnt_done_q <= 0;
            //DPS signals
            usr_up_dn <= 0;
            usr_cnt_sel <= 0;
            usr_num_shifts <= 0;
            dps_changed <= 0;
            //manual DPRIO signals
            manual_dprio_changed <= 0;
            usr_dprio_address <= 0;
            usr_dprio_writedata_0 <= 0;
            usr_r_w <= 0;
	    operation_address <= 0;
        end
        else
        begin
            if (dprio_temp_read_1)
            begin
                dprio_temp_m_n_c_readdata_1_q <= dprio_temp_m_n_c_readdata_1_d; 
            end
            if (dprio_temp_read_2)
            begin
                dprio_temp_m_n_c_readdata_2_q <= dprio_temp_m_n_c_readdata_2_d; 
            end
            if ((dps_done)) dps_changed <= 0;
            if (dsm_k_done_d) dsm_k_done_q <= dsm_k_done_d;
            if (n_cnt_done_d) n_cnt_done_q <= n_cnt_done_d;
            if (m_cnt_done_d) m_cnt_done_q <= m_cnt_done_d;
            if (all_c_cnt_done_d) all_c_cnt_done_q <= all_c_cnt_done_d;
            if (c_cnt_done_d != 0) c_cnt_done_q <= c_cnt_done_q | c_cnt_done_d;
            if (bwctrl_done_d) bwctrl_done_q <= bwctrl_done_d;
            if (cp_current_done_d) cp_current_done_q <= cp_current_done_d;
            if (vco_done_d) vco_done_q <= vco_done_d;
            if (manual_dprio_done_d) manual_dprio_done_q <= manual_dprio_done_d;

            if (dprio_next_state == ONE)
                dprio_start <= 0;
            if (dprio_write_done)
            begin
                bwctrl_done_q <= 0;
                cp_current_done_q <= 0;
                vco_done_q <= 0;
                dsm_k_done_q <= 0;
                dsm_k_done_q <= 0;
                n_cnt_done_q <= 0;
                m_cnt_done_q <= 0;
                all_c_cnt_done_q <= 0;
                c_cnt_done_q <= 0;
                dsm_k_changed <= 0;
                n_cnt_changed <= 0;
                m_cnt_changed <= 0;
                any_c_cnt_changed <= 0;
                bwctrl_changed <= 0;
                cp_current_changed <= 0;
                vco_changed <= 0;
                manual_dprio_changed <= 0;
                manual_dprio_done_q <= 0;

            end
            else 
            begin
                dsm_k_changed <= dsm_k_changed;
                n_cnt_changed <= n_cnt_changed;
                m_cnt_changed <= m_cnt_changed;
                any_c_cnt_changed <= any_c_cnt_changed;
                manual_dprio_changed <= manual_dprio_changed;
            end


            if(slave_write & !slave_waitrequest)
            begin
                case(slave_address)
                   //read in the values here from the user and act on them
                DSM_REG:
                begin
                    operation_address <= DSM_REG;
                    usr_k_value <= slave_writedata[31:0]; 
                    dsm_k_changed <= 1'b1;
                    dsm_k_done_q <= 0;
                    dprio_start <= 1'b1;
                end
                N_REG:
                begin
                    operation_address <= N_REG;
                    usr_n_cnt_lo <= slave_writedata[7:0]; 
                    usr_n_cnt_hi <= slave_writedata[15:8];
                    usr_n_cnt_bypass_en <= slave_writedata[16];
                    usr_n_cnt_odd_duty_div_en <= slave_writedata[17];
                    n_cnt_changed <= 1'b1;
                    n_cnt_done_q <= 0;
                    dprio_start <= 1'b1;
                end
                M_REG:
                begin
                    operation_address <= M_REG;
                    usr_m_cnt_lo <= slave_writedata[7:0]; 
                    usr_m_cnt_hi <= slave_writedata[15:8];
                    usr_m_cnt_bypass_en <= slave_writedata[16];
                    usr_m_cnt_odd_duty_div_en <= slave_writedata[17];
                    m_cnt_changed <= 1'b1;
                    m_cnt_done_q <= 0;
                    dprio_start <= 1'b1;
                end
                //DPS_REG:
                //begin
                //    operation_address <= DPS_REG;
                //    usr_num_shifts <= slave_writedata[15:0];
                //    usr_up_dn <= slave_writedata[21];
                //    dps_changed <= 1;
                //end
                C_COUNTERS_REG:
                begin
						  operation_address <= C_COUNTERS_REG;
                    usr_c_cnt_lo <= slave_writedata[7:0]; 
                    usr_c_cnt_hi <= slave_writedata[15:8];
                    usr_c_cnt_bypass_en <= slave_writedata[16];
                    usr_c_cnt_odd_duty_div_en <= slave_writedata[17];
                    any_c_cnt_changed <= 1'b1;
                    all_c_cnt_done_q <= 0;
                    dprio_start <= 1'b1;
                end
                BWCTRL_REG:
                begin
                    usr_bwctrl_value <= slave_writedata[3:0]; 
                    bwctrl_changed <= 1'b1;
                    bwctrl_done_q <= 0;
                    dprio_start <= 1'b1;
		    	  operation_address <= BWCTRL_REG;
                end
                CP_CURRENT_REG:
                begin
                    usr_cp_current_value <= slave_writedata[2:0]; 
                    cp_current_changed <= 1'b1;
                    cp_current_done_q <= 0;
                    dprio_start <= 1'b1;
		              operation_address <= CP_CURRENT_REG;
                end
                //VCO_REG:
                //begin
                //    usr_vco_value <= slave_writedata[0]; 
                //    vco_changed <= 1'b1;
                //    vco_done_q <= 0;
                //    dprio_start <= 1'b1;
		          //    operation_address <= VCO_REG;
                //end
                //ANY_DPRIO:
                //begin
					 //    operation_address <= ANY_DPRIO;
                //    manual_dprio_changed <= 1'b1;
                //    usr_dprio_address <= slave_writedata[5:0];
                //    usr_dprio_writedata_0 <= slave_writedata[21:6];
                //    usr_r_w <= slave_writedata[22];
                //    manual_dprio_done_q <= 0;
                //    dprio_start <= 1'b1;
                //end          
                endcase
             end
        end 
    end
    //C Counter assigning values to the 2-d array of values for each C counter
   
    reg [4:0] j;
    always @(posedge clk)
    begin

        if (reset)
        begin
            c_cnt_changed[17:0] <= 0;
            for (j = 0; j < number_of_counters; j = j + 1'b1)
            begin : c_cnt_reset
                temp_c_cnt_bypass_en[j] <= 0;
                temp_c_cnt_odd_duty_div_en[j] <= 0;
            end
        end
        else 
        begin
            if (dprio_write_done)
            begin
                c_cnt_changed <= 0;
            end
            if (any_c_cnt_changed && (operation_address == C_COUNTERS_REG))
            begin
                        temp_c_cnt_bypass_en [5] <= usr_c_cnt_bypass_en;
                        temp_c_cnt_odd_duty_div_en [5] <= usr_c_cnt_odd_duty_div_en;
                        c_cnt_changed [5] <= 1'b1;
            end
        end
    end


    //logic to handle which writes the user indicated and wants to start.
    assign usr_valid_changes =dsm_k_changed| any_c_cnt_changed |n_cnt_changed | m_cnt_changed | dps_changed_valid |manual_dprio_changed |cp_current_changed|bwctrl_changed|vco_changed;

     
    //start the reconfig operations by writing to the DPRIO
    reg break_loop;
    reg [4:0] i;
    always @(*)
    begin 
        dprio_temp_read_1 = 0;
        dprio_temp_read_2 = 0;
        dprio_temp_m_n_c_readdata_1_d = 0;
        dprio_temp_m_n_c_readdata_2_d = 0;
        break_loop = 0;
        dprio_next_state = DPRIO_IDLE;
        avmm_dprio_write = 0;
        avmm_dprio_read = 0;
        avmm_dprio_address = 0;
        avmm_dprio_writedata = 0;
        avmm_dprio_byteen = 0;
        dprio_write_done = 1;
        manual_dprio_done_d = 0;
        n_cnt_done_d = 0;
        dsm_k_done_d = 0;
        dsm_k_ready_false_done_d = 0;
        m_cnt_done_d = 0;
        c_cnt_done_d[17:0] = 0;
        all_c_cnt_done_d = 0;
        bwctrl_done_d = 0;
        cp_current_done_d = 0;
        vco_done_d = 0;
        i = 0;
       
        // Deassert dprio_write_done so it doesn't reset mif_reg_asserted (toggled writes) 
        if (dprio_start)
            dprio_write_done = 0;

        if (current_state == WAIT_ON_LOCK)
        begin
            case (dprio_cur_state)
                ONE:
                begin
                    if (n_cnt_changed & !n_cnt_done_q) 
                    begin
			dprio_write_done = 0;
                    	avmm_dprio_write = 1'b1;
                    	avmm_dprio_byteen = 2'b11;
                    	dprio_next_state = TWO;
                        avmm_dprio_address = N_CNT_DIV_ADDR;
                        avmm_dprio_writedata[7:0] = usr_n_cnt_lo;
                        avmm_dprio_writedata[15:8] = usr_n_cnt_hi;
                    end
                    else if (m_cnt_changed & !m_cnt_done_q) 
                    begin
		    	dprio_write_done = 0;
                    	avmm_dprio_write = 1'b1;
                    	avmm_dprio_byteen = 2'b11;
                    	dprio_next_state = TWO;
                        avmm_dprio_address = M_CNT_DIV_ADDR;
                        avmm_dprio_writedata[7:0] = usr_m_cnt_lo;
                        avmm_dprio_writedata[15:8] = usr_m_cnt_hi;
                    end
                    else if (any_c_cnt_changed & !all_c_cnt_done_q)
                    begin

                        for (i = 0; (i < number_of_counters) & !break_loop; i = i + 1'b1)
                        begin : c_cnt_write_hilo
                            if (c_cnt_changed[i] & !c_cnt_done_q[i])
                            begin
				dprio_write_done = 0;
	                    	avmm_dprio_write = 1'b1;
        	            	avmm_dprio_byteen = 2'b11;
                	    	dprio_next_state = TWO;
                                if (fpll_1) avmm_dprio_address = C_CNT_0_DIV_ADDR + C_CNT_0_DIV_ADDR_DPRIO_1 - i;
                                else avmm_dprio_address = C_CNT_0_DIV_ADDR + i;
                                avmm_dprio_writedata[7:0] = usr_c_cnt_lo;
                                avmm_dprio_writedata[15:8] = usr_c_cnt_hi;
                                //To break from the loop, since only one counter
                                //is addressed at a time
                                break_loop = 1'b1;
                            end
                        end
                    end
                    else if (dsm_k_changed & !dsm_k_done_q) 
                    begin
		    	dprio_write_done = 0;
                        avmm_dprio_write = 0;
                        dprio_next_state = TWO;
                    end
                    else if (bwctrl_changed & !bwctrl_done_q) 
                    begin
		    	dprio_write_done = 0;
                        avmm_dprio_write = 0;
                        dprio_next_state = TWO;
                    end
                    else if (cp_current_changed & !cp_current_done_q) 
                    begin
		    	dprio_write_done = 0;		    
                        avmm_dprio_write = 0;
                        dprio_next_state = TWO;
                    end
                    else if (vco_changed & !vco_done_q) 
                    begin
		    	dprio_write_done = 0;		    
                        avmm_dprio_write = 0;
                        dprio_next_state = TWO;
                    end
                    else if (manual_dprio_changed & !manual_dprio_done_q)
                    begin
		    	dprio_write_done = 0;
                    	avmm_dprio_byteen = 2'b11;
                    	dprio_next_state = TWO;		    
                        avmm_dprio_write = usr_r_w;
                        avmm_dprio_address = usr_dprio_address;
                        avmm_dprio_writedata[15:0] = usr_dprio_writedata_0;
                    end
                    else dprio_next_state = DPRIO_IDLE;
                end
            
                TWO:
                begin
                    //handle reading the two setting bits on n_cnt, then
                    //writing them back while preserving other bits.
                    //Issue two consecutive reads then wait; readLatency=3
                    dprio_write_done = 0;
                    dprio_next_state = THREE;
                    avmm_dprio_byteen = 2'b11;
                    avmm_dprio_read = 1'b1;
                    if (n_cnt_changed & !n_cnt_done_q)
                    begin
                        avmm_dprio_address = N_CNT_BYPASS_EN_ADDR;
                    end
                    else if (m_cnt_changed & !m_cnt_done_q)
                    begin
                        avmm_dprio_address = M_CNT_BYPASS_EN_ADDR;
                    end
                   
                    else if (any_c_cnt_changed & !all_c_cnt_done_q)
                    begin
                        for (i = 5; (i < number_of_counters) & !break_loop; i = i + 1'b1)
                        begin : c_cnt_read_bypass
                            if (fpll_1)
                            begin
                                if (i > 13)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_BYPASS_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_BYPASS_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                            else
                            begin
                                if (i < 4)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_BYPASS_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_BYPASS_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                    //reading the K ready 16 bit word. Need to write 0 to it
                    //afterwards to indicate that K has not been done writing
                    else if (dsm_k_changed & !dsm_k_done_q) 
                    begin
                        avmm_dprio_address = DSM_K_READY_ADDR;
                        dprio_next_state = FOUR;
                    end
                    else if (bwctrl_changed & !bwctrl_done_q) 
                    begin
                        avmm_dprio_address = BWCTRL_ADDR;
                        dprio_next_state = FOUR;
                    end
                    else if (cp_current_changed & !cp_current_done_q) 
                    begin
                        avmm_dprio_address = CP_CURRENT_ADDR;
                        dprio_next_state = FOUR;
                    end
                    else if (vco_changed & !vco_done_q) 
                    begin
                        avmm_dprio_address = VCO_ADDR;
                        dprio_next_state = FOUR;
                    end
                    else if (manual_dprio_changed & !manual_dprio_done_q)
                    begin
                        avmm_dprio_read = ~usr_r_w;
                        avmm_dprio_address = usr_dprio_address;
                        dprio_next_state = DPRIO_DONE;
                    end
                    else dprio_next_state = DPRIO_IDLE;
                end       
                THREE:
                begin
                    dprio_write_done = 0;
                    avmm_dprio_byteen = 2'b11;
                    avmm_dprio_read = 1'b1;
                    dprio_next_state = FOUR;
                    if (n_cnt_changed & !n_cnt_done_q)
                    begin
                        avmm_dprio_address = N_CNT_ODD_DIV_EN_ADDR;
                    end
                    else if (m_cnt_changed & !m_cnt_done_q)
                    begin
                        avmm_dprio_address = M_CNT_ODD_DIV_EN_ADDR;
                    end
                    else if (any_c_cnt_changed & !all_c_cnt_done_q)
                    begin
                        for (i = 5; (i < number_of_counters) & !break_loop; i = i + 1'b1)
                        begin : c_cnt_read_odd_div
                            if (fpll_1)
                            begin
                                if (i > 13)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_ODD_DIV_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_ODD_DIV_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                            else
                            begin
                                if (i < 4)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_ODD_DIV_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_ODD_DIV_EN_ADDR;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                        end
                    end   
                    else dprio_next_state = DPRIO_IDLE;
                end
                FOUR:
                begin
                    dprio_temp_read_1 = 1'b1;
                    dprio_write_done = 0;
                    if (vco_changed|cp_current_changed|bwctrl_changed|dsm_k_changed|n_cnt_changed|m_cnt_changed|any_c_cnt_changed)
                    begin
                        dprio_temp_m_n_c_readdata_1_d = dprio_readdata;
                        dprio_next_state = FIVE;
                    end
                    else dprio_next_state = DPRIO_IDLE;
                end
                FIVE:
                begin
                    dprio_write_done = 0;
                    dprio_temp_read_2 = 1'b1;
                    if (vco_changed|cp_current_changed|bwctrl_changed|dsm_k_changed|n_cnt_changed|m_cnt_changed|any_c_cnt_changed)
                    begin
                        //this is where DSM ready value comes.
                        //Need to store in a register to be used later
                        dprio_temp_m_n_c_readdata_2_d = dprio_readdata;
                        dprio_next_state = SIX;
                    end
                    else dprio_next_state = DPRIO_IDLE;
                end
                SIX:
                begin
                    dprio_write_done = 0;
                    avmm_dprio_write = 1'b1;
                    avmm_dprio_byteen = 2'b11;
                    dprio_next_state = SEVEN;
                    avmm_dprio_writedata = dprio_temp_m_n_c_readdata_1_q;
                    if (n_cnt_changed & !n_cnt_done_q)
                    begin
                        avmm_dprio_address = N_CNT_BYPASS_EN_ADDR;
                        avmm_dprio_writedata[5] = usr_n_cnt_bypass_en;
                    end
                    else if (m_cnt_changed & !m_cnt_done_q)
                    begin
                        avmm_dprio_address = M_CNT_BYPASS_EN_ADDR;
                        avmm_dprio_writedata[4] = usr_m_cnt_bypass_en;
                    end
                    else if (any_c_cnt_changed & !all_c_cnt_done_q)
                    begin
                        for (i = 5; (i < number_of_counters) & !break_loop; i = i + 1'b1)
                        begin : c_cnt_write_bypass
                            if (fpll_1)
                            begin
                                if (i > 13)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_BYPASS_EN_ADDR;
                                        avmm_dprio_writedata[i-14] = temp_c_cnt_bypass_en[i];
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_BYPASS_EN_ADDR;
                                        avmm_dprio_writedata[i] = temp_c_cnt_bypass_en[i];
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                            else
                            begin
                                if (i < 4)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_BYPASS_EN_ADDR;
                                        avmm_dprio_writedata[3-i] = temp_c_cnt_bypass_en[i];
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_BYPASS_EN_ADDR;
                                        avmm_dprio_writedata[17-i] = temp_c_cnt_bypass_en[i];
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                        end
                    end    
                    else if (dsm_k_changed & !dsm_k_done_q)
                    begin
                        avmm_dprio_write = 0;
                    end
                    else if (bwctrl_changed & !bwctrl_done_q) 
                    begin
                        avmm_dprio_write = 0;
                    end
                    else if (cp_current_changed & !cp_current_done_q) 
                    begin
                        avmm_dprio_write = 0;
                    end
                    else if (vco_changed & !vco_done_q) 
                    begin
                        avmm_dprio_write = 0;
                    end
                    else dprio_next_state = DPRIO_IDLE;
                end
                SEVEN:
                begin
                    dprio_write_done = 0;
                    dprio_next_state = EIGHT;
                    avmm_dprio_write = 1'b1;
                    avmm_dprio_byteen = 2'b11;
                    avmm_dprio_writedata = dprio_temp_m_n_c_readdata_2_q;
                    if (n_cnt_changed & !n_cnt_done_q)
                    begin
                        avmm_dprio_address = N_CNT_ODD_DIV_EN_ADDR;
                        avmm_dprio_writedata[5] = usr_n_cnt_odd_duty_div_en;
                        n_cnt_done_d = 1'b1;
                    end
                    else if (m_cnt_changed & !m_cnt_done_q)
                    begin
                        avmm_dprio_address = M_CNT_ODD_DIV_EN_ADDR;
                        avmm_dprio_writedata[4] = usr_m_cnt_odd_duty_div_en;
                        m_cnt_done_d = 1'b1;
                    end
                         
                    else if (any_c_cnt_changed & !all_c_cnt_done_q)
                    begin
                        for (i = 5; (i < number_of_counters) & !break_loop; i = i + 1'b1)
                        begin : c_cnt_write_odd_div
                            if (fpll_1)
                            begin
                                if (i > 13)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_ODD_DIV_EN_ADDR;
                                        avmm_dprio_writedata[i-14] = temp_c_cnt_odd_duty_div_en[i];
                                        c_cnt_done_d[i] = 1'b1;
                                        //have to OR the signals to prevent
                                        //overwriting of previous dones
                                        c_cnt_done_d = c_cnt_done_d | c_cnt_done_q;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_ODD_DIV_EN_ADDR;
                                        avmm_dprio_writedata[i] = temp_c_cnt_odd_duty_div_en[i];
                                        c_cnt_done_d[i] = 1'b1;
                                        c_cnt_done_d = c_cnt_done_d | c_cnt_done_q;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                            else
                            begin
                                if (i < 4)
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_0_3_ODD_DIV_EN_ADDR;
                                        avmm_dprio_writedata[3-i] = temp_c_cnt_odd_duty_div_en[i];
                                        c_cnt_done_d[i] = 1'b1;
                                        //have to OR the signals to prevent
                                        //overwriting of previous dones
                                        c_cnt_done_d = c_cnt_done_d | c_cnt_done_q;
                                        break_loop = 1'b1;
                                    end
                                end
                                else
                                begin
                                    if (c_cnt_changed[i] & !c_cnt_done_q[i])
                                    begin
                                        avmm_dprio_address = C_CNT_4_17_ODD_DIV_EN_ADDR;
                                        avmm_dprio_writedata[17-i] = temp_c_cnt_odd_duty_div_en[i];
                                        c_cnt_done_d[i] = 1'b1;
                                        c_cnt_done_d = c_cnt_done_d | c_cnt_done_q;
                                        break_loop = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                    else if (dsm_k_changed & !dsm_k_done_q)
                    begin
                        avmm_dprio_address = DSM_K_READY_ADDR;
                        avmm_dprio_writedata[DSM_K_READY_BIT_INDEX] = 1'b0;
                        dsm_k_ready_false_done_d = 1'b1;
                    end
                    else if (bwctrl_changed & !bwctrl_done_q) 
                    begin
                        avmm_dprio_address = BWCTRL_ADDR;
                        avmm_dprio_writedata[3:0] = usr_bwctrl_value;
                        bwctrl_done_d = 1'b1;
                    end
                    else if (cp_current_changed & !cp_current_done_q) 
                    begin
                        avmm_dprio_address = CP_CURRENT_ADDR;
                        avmm_dprio_writedata[2:0] = usr_cp_current_value;
                        cp_current_done_d = 1'b1;
                    end
                    else if (vco_changed & !vco_done_q) 
                    begin
                        avmm_dprio_address = VCO_ADDR;
                        avmm_dprio_writedata[8] = usr_vco_value;
                        vco_done_d = 1'b1;
                    end

                   
                    //if all C_cnt that were changed are done, then assert all_c_cnt_done
                    if (c_cnt_done_d == c_cnt_changed)
                        all_c_cnt_done_d = 1'b1;
                    if (n_cnt_changed & n_cnt_done_d)
                        dprio_next_state = DPRIO_DONE;
                    if (any_c_cnt_changed & !all_c_cnt_done_d & !all_c_cnt_done_q)
                        dprio_next_state = ONE;
                    else if (m_cnt_changed & !m_cnt_done_d & !m_cnt_done_q)
                        dprio_next_state = ONE;
                    else if (dsm_k_changed & !dsm_k_ready_false_done_d)
                        dprio_next_state = TWO;
                    else if (dsm_k_changed & !dsm_k_done_q)
                        dprio_next_state = EIGHT;
                    else if (bwctrl_changed & !bwctrl_done_d)
                        dprio_next_state = TWO;
                    else if (cp_current_changed & !cp_current_done_d)
                        dprio_next_state = TWO;
                    else if (vco_changed & !vco_done_d)
                        dprio_next_state = TWO;
                    else 
                    begin
                        dprio_next_state = DPRIO_DONE;
                        dprio_write_done = 1'b1;
                    end
                end
                //finish the rest of the DSM reads/writes
                //writing k value, writing k_ready to 1.
                EIGHT: 
                begin
                    dprio_write_done = 0;
                    dprio_next_state = NINE;
                    avmm_dprio_write = 1'b1;
                    avmm_dprio_byteen = 2'b11;
                    if (dsm_k_changed & !dsm_k_done_q)
                    begin
                        avmm_dprio_address = DSM_K_FRACTIONAL_DIVISION_ADDR_0;
                        avmm_dprio_writedata[15:0] = usr_k_value[15:0];
                    end
                end
                NINE: 
                begin
                    dprio_write_done = 0;
                    dprio_next_state = TEN;
                    avmm_dprio_write = 1'b1;
                    avmm_dprio_byteen = 2'b11;
                    if (dsm_k_changed & !dsm_k_done_q)
                    begin
                        avmm_dprio_address = DSM_K_FRACTIONAL_DIVISION_ADDR_1;
                        avmm_dprio_writedata[15:0] = usr_k_value[31:16];
                    end
                end
                TEN:
                begin
                    dprio_write_done = 0;
                    dprio_next_state = ONE;
                    avmm_dprio_write = 1'b1;
                    avmm_dprio_byteen = 2'b11;
                    if (dsm_k_changed & !dsm_k_done_q)
                    begin
                        avmm_dprio_address = DSM_K_READY_ADDR;
                        //already have the readdata for DSM_K_READY_ADDR since we read it
                        //earlier. Just reuse here 
                        avmm_dprio_writedata = dprio_temp_m_n_c_readdata_2_q;
                        avmm_dprio_writedata[DSM_K_READY_BIT_INDEX] = 1'b1;
                        dsm_k_done_d = 1'b1;
                    end
                end
                DPRIO_DONE:
                begin
                    dprio_write_done = 1'b1;
                    if (dprio_start) dprio_next_state = DPRIO_IDLE;
                    else dprio_next_state = DPRIO_DONE;
                end
                DPRIO_IDLE:
                begin
                    if (dprio_start) dprio_next_state = ONE;
                    else dprio_next_state = DPRIO_IDLE;
                end 
                default:    dprio_next_state = 4'bxxxx;
            endcase
        end

    end


    //assert the waitreq signal according to the state of the slave
    assign slave_waitrequest = (slave_mode==mode_WR) ? ((locked === 1'b1) ? (((current_state==WAIT_ON_LOCK) & !dprio_write_done) | !dps_done |reset|!dprio_init_done) : 1'b1) : 1'b0;
        
    
    dyn_phase_shift dyn_phase_shift_inst (
        .clk(clk), 
        .reset(reset),
        .phase_done(phase_done),
        .pll_start_valid(pll_start_valid),
        .dps_changed(dps_changed),
        .dps_changed_valid(dps_changed_valid),
        .dprio_write_done(dprio_write_done),
        .usr_num_shifts(usr_num_shifts),
        .usr_cnt_sel(usr_cnt_sel),
        .usr_up_dn(usr_up_dn),
        .locked(locked),
        .dps_done(dps_done),
        .phase_en(phase_en),
        .up_dn(up_dn),
        .cnt_sel(cnt_sel));
    defparam dyn_phase_shift_inst.device_family = device_family;

    assign dprio_clk = clk;
    self_reset self_reset_inst (mgmt_reset, clk, reset, dprio_init_reset);
    
    dprio_mux dprio_mux_inst (
    .init_dprio_address(init_dprio_address),
    .init_dprio_read(init_dprio_read),
    .init_dprio_byteen(init_dprio_byteen),
    .init_dprio_write(init_dprio_write),
    .init_dprio_writedata(init_dprio_writedata),


    .init_atpgmode(init_atpgmode),
    .init_mdio_dis(init_mdio_dis),
    .init_scanen(init_scanen),
    .init_ser_shift_load(init_ser_shift_load),
    .dprio_init_done(dprio_init_done),

    // Inputs from avmm master
    .avmm_dprio_address(avmm_dprio_address),
    .avmm_dprio_read(avmm_dprio_read),
    .avmm_dprio_byteen(avmm_dprio_byteen),
    .avmm_dprio_write(avmm_dprio_write),
    .avmm_dprio_writedata(avmm_dprio_writedata),

    .avmm_atpgmode(avmm_atpgmode),
    .avmm_mdio_dis(avmm_mdio_dis),
    .avmm_scanen(avmm_scanen),

    // Outputs to fpll
    .dprio_address(dprio_address),
    .dprio_read(dprio_read),
    .dprio_byteen(dprio_byteen),
    .dprio_write(dprio_write),
    .dprio_writedata(dprio_writedata),

    .atpgmode(dprio_atpgmode),
    .mdio_dis(dprio_mdio_dis),
    .scanen(dprio_scanen),
    .ser_shift_load(dprio_ser_shift_load)
    );


    fpll_dprio_init fpll_dprio_init_inst (
    .clk(clk),
    .reset_n(~reset),
    .locked(locked),

    //outputs
    .dprio_address(init_dprio_address),
    .dprio_read(init_dprio_read),
    .dprio_byteen(init_dprio_byteen),
    .dprio_write(init_dprio_write),
    .dprio_writedata(init_dprio_writedata),

    .atpgmode(init_atpgmode),
    .mdio_dis(init_mdio_dis),
    .scanen(init_scanen),
    .ser_shift_load(init_ser_shift_load),
    .dprio_init_done(dprio_init_done));

    //address luts, to be reconfigged by the Fitter
    //FPLL_1 or 0 address lut
    generic_lcell_comb lcell_fpll_0_1 (
		.dataa(1'b0),
        .combout (fpll_1));
    defparam lcell_fpll_0_1.lut_mask = 64'hAAAAAAAAAAAAAAAA;
	 defparam lcell_fpll_0_1.dont_touch = "on";
	 defparam lcell_fpll_0_1.family = device_family;


    wire dprio_read_combout;
     generic_lcell_comb lcell_dprio_read (
		.dataa(fpll_1),
        .datab(dprio_read),
        .datac(1'b0),
        .datad(1'b0),
        .datae(1'b0),
        .dataf(1'b0),
      .combout (dprio_read_combout));
    defparam lcell_dprio_read.lut_mask = 64'hCCCCCCCCCCCCCCCC;
	 defparam lcell_dprio_read.dont_touch = "on";
	 defparam lcell_dprio_read.family = device_family;

   
    


    //assign reconfig_to_pll signals
    assign reconfig_to_pll[0] = dprio_clk;
    assign reconfig_to_pll[1] = ~dprio_init_reset;
    assign reconfig_to_pll[2] = dprio_write;
    assign reconfig_to_pll[3] = dprio_read_combout;
    assign reconfig_to_pll[9:4] = dprio_address;
    assign reconfig_to_pll[25:10] = dprio_writedata;
    assign reconfig_to_pll[27:26] = dprio_byteen;
    assign reconfig_to_pll[28] = dprio_ser_shift_load;
    assign reconfig_to_pll[29] = dprio_mdio_dis;
    assign reconfig_to_pll[30] = phase_en;
    assign reconfig_to_pll[31] = up_dn;
    assign reconfig_to_pll[36:32] = cnt_sel;
    assign reconfig_to_pll[37] = dprio_scanen;
    assign reconfig_to_pll[38] = dprio_atpgmode;
    //assign reconfig_to_pll[40:37] = clken;
    assign reconfig_to_pll[63:39] = 0;

    //assign reconfig_from_pll signals
    assign dprio_readdata = reconfig_from_pll [15:0]; 
    assign locked_orig    = reconfig_from_pll [16];
    assign phase_done     = reconfig_from_pll [17];

endmodule

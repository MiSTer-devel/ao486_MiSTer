--===========================================================================--
--
--  S Y N T H E Z I A B L E    CPU68   C O R E
--
--  www.OpenCores.Org - December 2002
--  This core adheres to the GNU public license  
--
-- File name      : cpu68.vhd
--
-- Purpose        : Implements a 6800 compatible CPU core with some
--                  additional instructions found in the 6801
--                  
-- Dependencies   : ieee.Std_Logic_1164
--                  ieee.std_logic_unsigned
--
-- Author         : John E. Kent      
--
--===========================================================================----
--
-- Revision History:
--
-- Date:          Revision         Author
-- 22 Sep 2002    0.1              John Kent
--
-- 30 Oct 2002    0.2              John Kent
-- made NMI edge triggered
--
-- 30 Oct 2002    0.3              John Kent
-- more corrections to NMI
-- added wai_wait_state to prevent stack overflow on wai.
--
--  1 Nov 2002    0.4              John Kent
-- removed WAI states and integrated WAI with the interrupt service routine
-- replace Data out (do) and Data in (di) register with a single Memory Data (md) reg.
-- Added Multiply instruction states.
-- run ALU and CC out of CPU module for timing measurements.
-- 
--  3 Nov 2002    0.5              John Kent
-- Memory Data Register was not loaded on Store instructions
-- SEV and CLV were not defined in the ALU
-- Overflow Flag on NEG was incorrect
--
-- 16th Feb 2003  0.6              John Kent
-- Rearranged the execution cycle for dual operand instructions
-- so that occurs during the following fetch cycle.
-- This allows the reduction of one clock cycle from dual operand
-- instruction. Note that this also necessitated re-arranging the
-- program counter so that it is no longer incremented in the ALU.
-- The effective address has also been re-arranged to include a 
-- separate added. The STD (store accd) now sets the condition codes.
--
-- 28th Jun 2003 0.7               John Kent
-- Added Hold and Halt signals. Hold is used to steal cycles from the
-- CPU or add wait states. Halt puts the CPU in the inactive state
-- and is only honoured in the fetch cycle. Both signals are active high.
--
-- 9th Jan 2004 0.8						John Kent
-- Clear instruction did an alu_ld8 rather than an alu_clr, so
-- the carry bit was not cleared correctly.
-- This error was picked up by Michael Hassenfratz.
--

library ieee;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity cpu68 is
	port (	
		clk:	    in  std_logic;
		rst:	    in  std_logic;
		rw:	    out std_logic;
		vma:	    out std_logic;
		address:	 out std_logic_vector(15 downto 0);
	   data_in:	 in  std_logic_vector(7 downto 0);
	   data_out: out std_logic_vector(7 downto 0);
		hold:     in  std_logic;
		halt:     in  std_logic;
		irq:      in  std_logic;
		nmi:      in  std_logic
--		test_alu: out std_logic_vector(15 downto 0);
--		test_cc:  out std_logic_vector(7 downto 0)
		);
end;

architecture CPU_ARCH of cpu68 is

  constant SBIT : integer := 7;
  constant XBIT : integer := 6;
  constant HBIT : integer := 5;
  constant IBIT : integer := 4;
  constant NBIT : integer := 3;
  constant ZBIT : integer := 2;
  constant VBIT : integer := 1;
  constant CBIT : integer := 0;

	type state_type is (reset_state, fetch_state, decode_state,
                       extended_state, indexed_state, read8_state, read16_state, immediate16_state,
	                    write8_state, write16_state,
						     execute_state, halt_state, error_state,
						     mul_state, mulea_state, muld_state,
						     mul0_state, mul1_state, mul2_state, mul3_state,
						     mul4_state, mul5_state, mul6_state, mul7_state,
							  jmp_state, jsr_state, jsr1_state,
						     branch_state, bsr_state, bsr1_state, 
							  rts_hi_state, rts_lo_state,
							  int_pcl_state, int_pch_state,
						     int_ixl_state, int_ixh_state,
						     int_cc_state, int_acca_state, int_accb_state,
						     int_wai_state, int_mask_state,
						     rti_state, rti_cc_state, rti_acca_state, rti_accb_state,
						     rti_ixl_state, rti_ixh_state,
						     rti_pcl_state, rti_pch_state,
							  pula_state, psha_state, pulb_state, pshb_state,
						     pulx_lo_state, pulx_hi_state, pshx_lo_state, pshx_hi_state,
							  vect_lo_state, vect_hi_state );
	type addr_type is (idle_ad, fetch_ad, read_ad, write_ad, push_ad, pull_ad, int_hi_ad, int_lo_ad );
	type dout_type is (md_lo_dout, md_hi_dout, acca_dout, accb_dout, ix_lo_dout, ix_hi_dout, cc_dout, pc_lo_dout, pc_hi_dout );
   type op_type is (reset_op, fetch_op, latch_op );
   type acca_type is (reset_acca, load_acca, load_hi_acca, pull_acca, latch_acca );
   type accb_type is (reset_accb, load_accb, pull_accb, latch_accb );
   type cc_type is (reset_cc, load_cc, pull_cc, latch_cc );
	type ix_type is (reset_ix, load_ix, pull_lo_ix, pull_hi_ix, latch_ix );
	type sp_type is (reset_sp, latch_sp, load_sp );
	type pc_type is (reset_pc, latch_pc, load_ea_pc, add_ea_pc, pull_lo_pc, pull_hi_pc, inc_pc );
   type md_type is (reset_md, latch_md, load_md, fetch_first_md, fetch_next_md, shiftl_md );
   type ea_type is (reset_ea, latch_ea, add_ix_ea, load_accb_ea, inc_ea, fetch_first_ea, fetch_next_ea );
	type iv_type is (reset_iv, latch_iv, swi_iv, nmi_iv, irq_iv );
	type nmi_type is (reset_nmi, set_nmi, latch_nmi );
	type left_type is (acca_left, accb_left, accd_left, md_left, ix_left, sp_left );
	type right_type is (md_right, zero_right, plus_one_right, accb_right );
   type alu_type   is (alu_add8, alu_sub8, alu_add16, alu_sub16, alu_adc, alu_sbc, 
                       alu_and, alu_ora, alu_eor,
                       alu_tst, alu_inc, alu_dec, alu_clr, alu_neg, alu_com,
							  alu_inx, alu_dex, alu_cpx,
						     alu_lsr16, alu_lsl16,
						     alu_ror8, alu_rol8,
						     alu_asr8, alu_asl8, alu_lsr8,
						     alu_sei, alu_cli, alu_sec, alu_clc, alu_sev, alu_clv, alu_tpa, alu_tap,
						     alu_ld8, alu_st8, alu_ld16, alu_st16, alu_nop, alu_daa );

	signal op_code:     std_logic_vector(7 downto 0);
  	signal acca:        std_logic_vector(7 downto 0);
  	signal accb:        std_logic_vector(7 downto 0);
   signal cc:          std_logic_vector(7 downto 0);
	signal cc_out:      std_logic_vector(7 downto 0);
	signal xreg:        std_logic_vector(15 downto 0);
	signal sp:          std_logic_vector(15 downto 0);
	signal ea:          std_logic_vector(15 downto 0);
	signal pc:	        std_logic_vector(15 downto 0);
	signal md:          std_logic_vector(15 downto 0);
   signal left:        std_logic_vector(15 downto 0);
   signal right:       std_logic_vector(15 downto 0);
	signal out_alu:     std_logic_vector(15 downto 0);
	signal iv:          std_logic_vector(1 downto 0);
	signal nmi_req:     std_logic;
	signal nmi_ack:     std_logic;

	signal state:       state_type;
	signal next_state:  state_type;
   signal pc_ctrl:     pc_type;
   signal ea_ctrl:     ea_type; 
   signal op_ctrl:     op_type;
	signal md_ctrl:     md_type;
	signal acca_ctrl:   acca_type;
	signal accb_ctrl:   accb_type;
	signal ix_ctrl:     ix_type;
	signal cc_ctrl:     cc_type;
	signal sp_ctrl:     sp_type;
	signal iv_ctrl:     iv_type;
	signal left_ctrl:   left_type;
	signal right_ctrl:  right_type;
   signal alu_ctrl:    alu_type;
   signal addr_ctrl:   addr_type;
   signal dout_ctrl:   dout_type;
   signal nmi_ctrl:    nmi_type;


begin

----------------------------------
--
-- Address bus multiplexer
--
----------------------------------

addr_mux: process( clk, addr_ctrl, pc, ea, sp, iv )
begin
  case addr_ctrl is
    when idle_ad =>
	   address <= "1111111111111111";
		vma     <= '0';
		rw      <= '1';
    when fetch_ad =>
	   address <= pc;
		vma     <= '1';
		rw      <= '1';
	 when read_ad =>
	   address <= ea;
		vma     <= '1';
		rw      <= '1';
    when write_ad =>
	   address <= ea;
		vma     <= '1';
		rw      <= '0';
	 when push_ad =>
	   address <= sp;
		vma     <= '1';
		rw      <= '0';
    when pull_ad =>
	   address <= sp;
		vma     <= '1';
		rw      <= '1';
	 when int_hi_ad =>
	   address <= "1111111111111" & iv & "0";
		vma     <= '1';
		rw      <= '1';
    when int_lo_ad =>
	   address <= "1111111111111" & iv & "1";
		vma     <= '1';
		rw      <= '1';
	 when others =>
	   address <= "1111111111111111";
		vma     <= '0';
		rw      <= '1';
  end case;
end process;

--------------------------------
--
-- Data Bus output
--
--------------------------------
dout_mux : process( clk, dout_ctrl, md, acca, accb, xreg, pc, cc )
begin
    case dout_ctrl is
	 when md_hi_dout => -- alu output
	   data_out <= md(15 downto 8);
	 when md_lo_dout =>
	   data_out <= md(7 downto 0);
	 when acca_dout => -- accumulator a
	   data_out <= acca;
	 when accb_dout => -- accumulator b
	   data_out <= accb;
	 when ix_lo_dout => -- index reg
	   data_out <= xreg(7 downto 0);
	 when ix_hi_dout => -- index reg
	   data_out <= xreg(15 downto 8);
	 when cc_dout => -- condition codes
	   data_out <= cc;
	 when pc_lo_dout => -- low order pc
	   data_out <= pc(7 downto 0);
	 when pc_hi_dout => -- high order pc
	   data_out <= pc(15 downto 8);
	 when others =>
	   data_out <= "00000000";
    end case;
end process;


----------------------------------
--
-- Program Counter Control
--
----------------------------------

pc_mux: process( clk, pc_ctrl, pc, out_alu, data_in, ea, hold )
variable tempof : std_logic_vector(15 downto 0);
variable temppc : std_logic_vector(15 downto 0);
begin
  case pc_ctrl is
  when add_ea_pc =>
	 if ea(7) = '0' then
	   tempof := "00000000" & ea(7 downto 0);
    else
		tempof := "11111111" & ea(7 downto 0);
    end if;
  when inc_pc =>
	 tempof := "0000000000000001";
  when others =>
    tempof := "0000000000000000";
  end case;

  case pc_ctrl is
  when reset_pc =>
	 temppc := "1111111111111110";
  when load_ea_pc =>
	 temppc := ea;
  when pull_lo_pc =>
	 temppc(7 downto 0) := data_in;
	 temppc(15 downto 8) := pc(15 downto 8);
  when pull_hi_pc =>
	 temppc(7 downto 0) := pc(7 downto 0);
	 temppc(15 downto 8) := data_in;
  when others =>
    temppc := pc;
  end case;

  if clk'event and clk = '0' then
    if hold = '1' then
      pc <= pc;
    else
      pc <= temppc + tempof;
	 end if;
  end if;
end process;

----------------------------------
--
-- Effective Address  Control
--
----------------------------------

ea_mux: process( clk, ea_ctrl, ea, out_alu, data_in, accb, xreg, hold )
variable tempind : std_logic_vector(15 downto 0);
variable tempea  : std_logic_vector(15 downto 0);
begin
  case ea_ctrl is
  when add_ix_ea =>
	 tempind := "00000000" & ea(7 downto 0);
  when inc_ea =>
	 tempind := "0000000000000001";
  when others =>
    tempind := "0000000000000000";
  end case;

  case ea_ctrl is
  when reset_ea =>
	 tempea := "0000000000000000";
  when load_accb_ea =>
	 tempea := "00000000" & accb(7 downto 0);
  when add_ix_ea =>
	 tempea := xreg;
  when fetch_first_ea =>
	 tempea(7 downto 0) := data_in;
	 tempea(15 downto 8) := "00000000";
  when fetch_next_ea =>
	 tempea(7 downto 0) := data_in;
	 tempea(15 downto 8) := ea(7 downto 0);
  when others =>
    tempea := ea;
  end case;

  if clk'event and clk = '0' then
    if hold = '1' then
      ea <= ea;
    else
      ea <= tempea + tempind;
	 end if;
  end if;
end process;

--------------------------------
--
-- Accumulator A
--
--------------------------------
acca_mux : process( clk, acca_ctrl, out_alu, acca, data_in, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   acca <= acca;
	 else
    case acca_ctrl is
    when reset_acca =>
	   acca <= "00000000";
	 when load_acca =>
	   acca <= out_alu(7 downto 0);
	 when load_hi_acca =>
	   acca <= out_alu(15 downto 8);
	 when pull_acca =>
	   acca <= data_in;
	 when others =>
--	 when latch_acca =>
	   acca <= acca;
    end case;
	 end if;
  end if;
end process;

--------------------------------
--
-- Accumulator B
--
--------------------------------
accb_mux : process( clk, accb_ctrl, out_alu, accb, data_in, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   accb <= accb;
	 else
    case accb_ctrl is
    when reset_accb =>
	   accb <= "00000000";
	 when load_accb =>
	   accb <= out_alu(7 downto 0);
	 when pull_accb =>
	   accb <= data_in;
	 when others =>
--	 when latch_accb =>
	   accb <= accb;
    end case;
	 end if;
  end if;
end process;

--------------------------------
--
-- X Index register
--
--------------------------------
ix_mux : process( clk, ix_ctrl, out_alu, xreg, data_in, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   xreg <= xreg;
	 else
    case ix_ctrl is
    when reset_ix =>
	   xreg <= "0000000000000000";
	 when load_ix =>
	   xreg <= out_alu(15 downto 0);
	 when pull_hi_ix =>
	   xreg(15 downto 8) <= data_in;
	 when pull_lo_ix =>
	   xreg(7 downto 0) <= data_in;
	 when others =>
--	 when latch_ix =>
	   xreg <= xreg;
    end case;
	 end if;
  end if;
end process;

--------------------------------
--
-- stack pointer
--
--------------------------------
sp_mux : process( clk, sp_ctrl, out_alu, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   sp <= sp;
	 else
    case sp_ctrl is
    when reset_sp =>
	   sp <= "0000000000000000";
	 when load_sp =>
	   sp <= out_alu(15 downto 0);
	 when others =>
--	 when latch_sp =>
	   sp <= sp;
    end case;
	 end if;
  end if;
end process;

--------------------------------
--
-- Memory Data
--
--------------------------------
md_mux : process( clk, md_ctrl, out_alu, data_in, md, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   md <= md;
	 else
    case md_ctrl is
    when reset_md =>
	   md <= "0000000000000000";
	 when load_md =>
	   md <= out_alu(15 downto 0);
	 when fetch_first_md =>
	   md(15 downto 8) <= "00000000";
	   md(7 downto 0) <= data_in;
	 when fetch_next_md =>
	   md(15 downto 8) <= md(7 downto 0);
		md(7 downto 0) <= data_in;
	 when shiftl_md =>
	   md(15 downto 1) <= md(14 downto 0);
		md(0) <= '0';
	 when others =>
--	 when latch_md =>
	   md <= md;
    end case;
	 end if;
  end if;
end process;


----------------------------------
--
-- Condition Codes
--
----------------------------------

cc_mux: process( clk, cc_ctrl, cc_out, cc, data_in, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   cc <= cc;
	 else
    case cc_ctrl is
	 when reset_cc =>
	   cc <= "11000000";
	 when load_cc =>
	   cc <= cc_out;
  	 when pull_cc =>
      cc <= data_in;
	 when others =>
--  when latch_cc =>
      cc <= cc;
    end case;
	 end if;
  end if;
end process;

----------------------------------
--
-- interrupt vector
--
----------------------------------

iv_mux: process( clk, iv_ctrl, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   iv <= iv;
	 else
    case iv_ctrl is
	 when reset_iv =>
	   iv <= "11";		-- 0xFFFE
	 when nmi_iv =>
      iv <= "10";		-- 0xFFFC
  	 when swi_iv =>
      iv <= "01";		-- 0xFFFA
	 when irq_iv =>
      iv <= "00";		-- 0xFFF8
	 when others =>
	   iv <= iv;
    end case;
	 end if;
  end if;
end process;

----------------------------------
--
-- op code fetch
--
----------------------------------

op_fetch: process( clk, data_in, op_ctrl, op_code, hold )
begin
  if clk'event and clk = '0' then
    if hold = '1' then
	   op_code <= op_code;
	 else
    case op_ctrl is
	 when reset_op =>
	   op_code <= "00000001"; -- nop
  	 when fetch_op =>
      op_code <= data_in;
	 when others =>
--	 when latch_op =>
	   op_code <= op_code;
    end case;
	 end if;
  end if;
end process;

----------------------------------
--
-- Left Mux
--
----------------------------------

left_mux: process( left_ctrl, acca, accb, xreg, sp, pc, ea, md )
begin
  case left_ctrl is
	 when acca_left =>
	   left(15 downto 8) <= "00000000";
		left(7 downto 0)  <= acca;
	 when accb_left =>
	   left(15 downto 8) <= "00000000";
		left(7 downto 0)  <= accb;
	 when accd_left =>
	   left(15 downto 8) <= acca;
		left(7 downto 0)  <= accb;
	 when ix_left =>
	   left <= xreg;
	 when sp_left =>
	   left <= sp;
	 when others =>
--	 when md_left =>
	   left <= md;
    end case;
end process;
----------------------------------
--
-- Right Mux
--
----------------------------------

right_mux: process( right_ctrl, data_in, md, accb, ea )
begin
  case right_ctrl is
	 when zero_right =>
	   right <= "0000000000000000";
	 when plus_one_right =>
	   right <= "0000000000000001";
	 when accb_right =>
	   right <= "00000000" & accb;
	 when others =>
--	 when md_right =>
	   right <= md;
    end case;
end process;

----------------------------------
--
-- Arithmetic Logic Unit
--
----------------------------------

mux_alu: process( alu_ctrl, cc, left, right, out_alu, cc_out )
variable valid_lo, valid_hi : boolean;
variable carry_in : std_logic;
variable daa_reg : std_logic_vector(7 downto 0);
begin

  case alu_ctrl is
  	 when alu_adc | alu_sbc |
  	      alu_rol8 | alu_ror8 =>
	   carry_in := cc(CBIT);
  	 when others =>
	   carry_in := '0';
  end case;

  valid_lo := left(3 downto 0) <= 9;
  valid_hi := left(7 downto 4) <= 9;

  if (cc(CBIT) = '0') then
    if( cc(HBIT) = '1' ) then
		if valid_hi then
		  daa_reg := "00000110";
		else
		  daa_reg := "01100110";
	   end if;
    else
		if valid_lo then
		  if valid_hi then
		    daa_reg := "00000000";
		  else
		    daa_reg := "01100000";
		  end if;
		else
	     if( left(7 downto 4) <= 8 ) then
		    daa_reg := "00000110";
		  else
			 daa_reg := "01100110";
		  end if;
		end if;
	 end if;
  else
    if ( cc(HBIT) = '1' )then
		daa_reg := "01100110";
 	 else
		if valid_lo then
		  daa_reg := "01100000";
	   else
		  daa_reg := "01100110";
		end if;
	 end if;
  end if;

  case alu_ctrl is
  	 when alu_add8 | alu_inc |
  	      alu_add16 | alu_inx |
  	      alu_adc =>
		out_alu <= left + right + ("000000000000000" & carry_in);
  	 when alu_sub8 | alu_dec |
  	      alu_sub16 | alu_dex |
  	      alu_sbc | alu_cpx =>
	   out_alu <= left - right - ("000000000000000" & carry_in);
  	 when alu_and =>
	   out_alu   <= left and right; 	-- and/bit
  	 when alu_ora =>
	   out_alu   <= left or right; 	-- or
  	 when alu_eor =>
	   out_alu   <= left xor right; 	-- eor/xor
  	 when alu_lsl16 | alu_asl8 | alu_rol8 =>
	   out_alu   <= left(14 downto 0) & carry_in; 	-- rol8/asl8/lsl16
  	 when alu_lsr16 | alu_lsr8 =>
	   out_alu   <= carry_in & left(15 downto 1); 	-- lsr
  	 when alu_ror8 =>
	   out_alu   <= "00000000" & carry_in & left(7 downto 1); 	-- ror
  	 when alu_asr8 =>
	   out_alu   <= "00000000" & left(7) & left(7 downto 1); 	-- asr
  	 when alu_neg =>
	   out_alu   <= right - left; 	-- neg (right=0)
  	 when alu_com =>
	   out_alu   <= not left;
  	 when alu_clr | alu_ld8 | alu_ld16 =>
	   out_alu   <= right; 	         -- clr, ld
	 when alu_st8 | alu_st16 =>
	   out_alu   <= left;
	 when alu_daa =>
	   out_alu   <= left + ("00000000" & daa_reg);
	 when alu_tpa =>
	   out_alu <= "00000000" & cc;
  	 when others =>
	   out_alu   <= left; -- nop
    end case;

	 --
	 -- carry bit
	 --
    case alu_ctrl is
  	 when alu_add8 | alu_adc  =>
      cc_out(CBIT) <= (left(7) and right(7)) or
		                (left(7) and not out_alu(7)) or
						   (right(7) and not out_alu(7));
  	 when alu_sub8 | alu_sbc =>
      cc_out(CBIT) <= ((not left(7)) and right(7)) or
		                ((not left(7)) and out_alu(7)) or
						         (right(7) and out_alu(7));
  	 when alu_add16  =>
      cc_out(CBIT) <= (left(15) and right(15)) or
		                (left(15) and not out_alu(15)) or
						   (right(15) and not out_alu(15));
  	 when alu_sub16 =>
      cc_out(CBIT) <= ((not left(15)) and right(15)) or
		                ((not left(15)) and out_alu(15)) or
						         (right(15) and out_alu(15));
	 when alu_ror8 | alu_lsr16 | alu_lsr8 | alu_asr8 =>
	   cc_out(CBIT) <= left(0);
	 when alu_rol8 | alu_asl8 =>
	   cc_out(CBIT) <= left(7);
	 when alu_lsl16 =>
	   cc_out(CBIT) <= left(15);
	 when alu_com =>
	   cc_out(CBIT) <= '1';
	 when alu_neg | alu_clr =>
	   cc_out(CBIT) <= out_alu(7) or out_alu(6) or out_alu(5) or out_alu(4) or
		                out_alu(3) or out_alu(2) or out_alu(1) or out_alu(0); 
    when alu_daa =>
	   if ( daa_reg(7 downto 4) = "0110" ) then
		  cc_out(CBIT) <= '1';
		else
		  cc_out(CBIT) <= '0';
	   end if;
  	 when alu_sec =>
      cc_out(CBIT) <= '1';
  	 when alu_clc =>
      cc_out(CBIT) <= '0';
    when alu_tap =>
      cc_out(CBIT) <= left(CBIT);
  	 when others => -- carry is not affected by cpx
      cc_out(CBIT) <= cc(CBIT);
    end case;
	 --
	 -- Zero flag
	 --
    case alu_ctrl is
  	 when alu_add8 | alu_sub8 |
	      alu_adc | alu_sbc |
  	      alu_and | alu_ora | alu_eor |
  	      alu_inc | alu_dec | 
			alu_neg | alu_com | alu_clr |
			alu_rol8 | alu_ror8 | alu_asr8 | alu_asl8 | alu_lsr8 |
		   alu_ld8  | alu_st8 =>
      cc_out(ZBIT) <= not( out_alu(7)  or out_alu(6)  or out_alu(5)  or out_alu(4)  or
	                        out_alu(3)  or out_alu(2)  or out_alu(1)  or out_alu(0) );
  	 when alu_add16 | alu_sub16 |
  	      alu_lsl16 | alu_lsr16 |
  	      alu_inx | alu_dex |
		   alu_ld16  | alu_st16 | alu_cpx =>
      cc_out(ZBIT) <= not( out_alu(15) or out_alu(14) or out_alu(13) or out_alu(12) or
	                        out_alu(11) or out_alu(10) or out_alu(9)  or out_alu(8)  or
  	                        out_alu(7)  or out_alu(6)  or out_alu(5)  or out_alu(4)  or
	                        out_alu(3)  or out_alu(2)  or out_alu(1)  or out_alu(0) );
    when alu_tap =>
      cc_out(ZBIT) <= left(ZBIT);
  	 when others =>
      cc_out(ZBIT) <= cc(ZBIT);
    end case;

    --
	 -- negative flag
	 --
    case alu_ctrl is
  	 when alu_add8 | alu_sub8 |
	      alu_adc | alu_sbc |
	      alu_and | alu_ora | alu_eor |
  	      alu_rol8 | alu_ror8 | alu_asr8 | alu_asl8 | alu_lsr8 |
  	      alu_inc | alu_dec | alu_neg | alu_com | alu_clr |
			alu_ld8  | alu_st8 =>
      cc_out(NBIT) <= out_alu(7);
	 when alu_add16 | alu_sub16 |
	      alu_lsl16 | alu_lsr16 |
			alu_ld16 | alu_st16 | alu_cpx =>
		cc_out(NBIT) <= out_alu(15);
    when alu_tap =>
      cc_out(NBIT) <= left(NBIT);
  	 when others =>
      cc_out(NBIT) <= cc(NBIT);
    end case;

    --
	 -- Interrupt mask flag
    --
    case alu_ctrl is
  	 when alu_sei =>
		cc_out(IBIT) <= '1';               -- set interrupt mask
  	 when alu_cli =>
		cc_out(IBIT) <= '0';               -- clear interrupt mask
	 when alu_tap =>
      cc_out(IBIT) <= left(IBIT);
  	 when others =>
		cc_out(IBIT) <= cc(IBIT);             -- interrupt mask
    end case;

    --
    -- Half Carry flag
	 --
    case alu_ctrl is
  	 when alu_add8 | alu_adc =>
      cc_out(HBIT) <= (left(3) and right(3)) or
                     (right(3) and not out_alu(3)) or 
                      (left(3) and not out_alu(3));
    when alu_tap =>
      cc_out(HBIT) <= left(HBIT);
  	 when others =>
		cc_out(HBIT) <= cc(HBIT);
    end case;

    --
    -- Overflow flag
	 --
    case alu_ctrl is
  	 when alu_add8 | alu_adc =>
      cc_out(VBIT) <= (left(7)  and      right(7)  and (not out_alu(7))) or
                 ((not left(7)) and (not right(7)) and      out_alu(7));
	 when alu_sub8 | alu_sbc =>
      cc_out(VBIT) <= (left(7)  and (not right(7)) and (not out_alu(7))) or
                 ((not left(7)) and      right(7)  and      out_alu(7));
  	 when alu_add16 =>
      cc_out(VBIT) <= (left(15)  and      right(15)  and (not out_alu(15))) or
                 ((not left(15)) and (not right(15)) and      out_alu(15));
	 when alu_sub16 | alu_cpx =>
      cc_out(VBIT) <= (left(15)  and (not right(15)) and (not out_alu(15))) or
                 ((not left(15)) and      right(15) and       out_alu(15));
	 when alu_inc =>
	   cc_out(VBIT) <= ((not left(7)) and left(6) and left(5) and left(4) and
		                      left(3)  and left(2) and left(1) and left(0));
	 when alu_dec | alu_neg =>
	   cc_out(VBIT) <= (left(7)  and (not left(6)) and (not left(5)) and (not left(4)) and
		            (not left(3)) and (not left(2)) and (not left(1)) and (not left(0)));
	 when alu_asr8 =>
	   cc_out(VBIT) <= left(0) xor left(7);
	 when alu_lsr8 | alu_lsr16 =>
	   cc_out(VBIT) <= left(0);
	 when alu_ror8 =>
      cc_out(VBIT) <= left(0) xor cc(CBIT);
    when alu_lsl16 =>
      cc_out(VBIT) <= left(15) xor left(14);
	 when alu_rol8 | alu_asl8  =>
      cc_out(VBIT) <= left(7) xor left(6);
    when alu_tap =>
      cc_out(VBIT) <= left(VBIT);
	 when alu_and | alu_ora | alu_eor | alu_com |
	      alu_st8 | alu_st16 | alu_ld8 | alu_ld16 |
		   alu_clv =>
      cc_out(VBIT) <= '0';
    when alu_sev =>
	   cc_out(VBIT) <= '1';
  	 when others =>
		cc_out(VBIT) <= cc(VBIT);
    end case;

	 case alu_ctrl is
	 when alu_tap =>
      cc_out(XBIT) <= cc(XBIT) and left(XBIT);
      cc_out(SBIT) <= left(SBIT);
	 when others =>
      cc_out(XBIT) <= cc(XBIT) and left(XBIT);
	   cc_out(SBIT) <= cc(SBIT);
	 end case;

--	 test_alu <= out_alu;
--	 test_cc  <= cc_out;
end process;

------------------------------------
--
-- Detect Edge of NMI interrupt
--
------------------------------------

nmi_handler : process( clk, rst, nmi, nmi_ack )
begin
  if clk'event and clk='0' then
    if hold = '1' then
	   nmi_req <= nmi_req;
	 else
    if rst='1' then
	   nmi_req <= '0';
    else
	   if (nmi='1') and (nmi_ack='0') then
	     nmi_req <= '1';
	   else
		  if (nmi='0') and (nmi_ack='1') then
	       nmi_req <= '0';
	     else
	       nmi_req <= nmi_req;
		  end if;
		end if;
	 end if;
	 end if;
  end if;
end process;

------------------------------------
--
-- Nmi mux
--
------------------------------------

nmi_mux: process( clk, nmi_ctrl, nmi_ack, hold )
begin
  if clk'event and clk='0' then
    if hold = '1' then
	   nmi_ack <= nmi_ack;
	 else
    case nmi_ctrl is
	 when set_nmi =>
      nmi_ack <= '1';
	 when reset_nmi =>
	   nmi_ack <= '0';
	 when others =>
--  when latch_nmi =>
	   nmi_ack <= nmi_ack;
	 end case;
	 end if;
  end if;
end process;

------------------------------------
--
-- state sequencer
--
------------------------------------
process( state, op_code, cc, ea, irq, nmi_req, nmi_ack, hold, halt )
  	begin
		  case state is
          when reset_state =>        --  released from reset
			    -- reset the registers
             op_ctrl    <= reset_op;
				 acca_ctrl  <= reset_acca;
				 accb_ctrl  <= reset_accb;
				 ix_ctrl    <= reset_ix;
		       sp_ctrl    <= reset_sp;
		       pc_ctrl    <= reset_pc;
	 		    ea_ctrl    <= reset_ea;
				 md_ctrl    <= reset_md;
				 iv_ctrl    <= reset_iv;
				 nmi_ctrl   <= reset_nmi;
				 -- idle the ALU
             left_ctrl  <= acca_left;
				 right_ctrl <= zero_right;
				 alu_ctrl   <= alu_nop;
             cc_ctrl    <= reset_cc;
				 -- idle the bus
				 dout_ctrl  <= md_lo_dout;
             addr_ctrl  <= idle_ad;
	 	       next_state <= vect_hi_state;

			 --
			 -- Jump via interrupt vector
			 -- iv holds interrupt type
			 -- fetch PC hi from vector location
			 --
          when vect_hi_state =>
			    -- default the registers
             op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             md_ctrl    <= latch_md;
             ea_ctrl    <= latch_ea;
             iv_ctrl    <= latch_iv;
				 -- idle the ALU
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
				 -- fetch pc low interrupt vector
		       pc_ctrl    <= pull_hi_pc;
             addr_ctrl  <= int_hi_ad;
             dout_ctrl  <= pc_hi_dout;
	 	       next_state <= vect_lo_state;
			 --
			 -- jump via interrupt vector
			 -- iv holds vector type
			 -- fetch PC lo from vector location
			 --
          when vect_lo_state =>
			    -- default the registers
             op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             md_ctrl    <= latch_md;
             ea_ctrl    <= latch_ea;
             iv_ctrl    <= latch_iv;
				 -- idle the ALU
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
				 -- fetch the vector low byte
		       pc_ctrl    <= pull_lo_pc;
             addr_ctrl  <= int_lo_ad;
             dout_ctrl  <= pc_lo_dout;
	 	       next_state <= fetch_state;

			 --
			 -- Here to fetch an instruction
			 -- PC points to opcode
			 -- Should service interrupt requests at this point
			 -- either from the timer
			 -- or from the external input.
			 --
          when fetch_state =>
			      case op_code(7 downto 4) is
				   when "0000" |
	                 "0001" |
	                 "0010" |  -- branch conditional
	                 "0011" |
	                 "0100" |  -- acca single op
	                 "0101" |  -- accb single op
	                 "0110" |  -- indexed single op
	                 "0111" => -- extended single op
					  -- idle ALU
                 left_ctrl  <= acca_left;
					  right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  cc_ctrl    <= latch_cc;
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;

	            when "1000" | -- acca immediate
	                 "1001" | -- acca direct
	                 "1010" | -- acca indexed
                    "1011" => -- acca extended
				     case op_code(3 downto 0) is
					  when "0000" => -- suba
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sub8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0001" => -- cmpa
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sub8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0010" => -- sbca
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sbc;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0011" => -- subd
					    left_ctrl   <= accd_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sub16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_hi_acca;
						 accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0100" => -- anda
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_and;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0101" => -- bita
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_and;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0110" => -- ldaa
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ld8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0111" => -- staa
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_st8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1000" => -- eora
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_eor;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1001" => -- adca
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_adc;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1010" => -- oraa
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ora;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1011" => -- adda
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_add8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1100" => -- cpx
					    left_ctrl   <= ix_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_cpx;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1101" => -- bsr / jsr
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_nop;
						 cc_ctrl     <= latch_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1110" => -- lds
					    left_ctrl   <= sp_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ld16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
						 sp_ctrl     <= load_sp;
					  when "1111" => -- sts
					    left_ctrl   <= sp_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_st16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when others =>
					    left_ctrl   <= acca_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_nop;
						 cc_ctrl     <= latch_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  end case;
	            when "1100" | -- accb immediate
	                 "1101" | -- accb direct
	                 "1110" | -- accb indexed
                    "1111" => -- accb extended
				     case op_code(3 downto 0) is
					  when "0000" => -- subb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sub8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0001" => -- cmpb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sub8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0010" => -- sbcb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_sbc;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0011" => -- addd
					    left_ctrl   <= accd_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_add16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_hi_acca;
						 accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0100" => -- andb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_and;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0101" => -- bitb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_and;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0110" => -- ldab
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ld8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "0111" => -- stab
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_st8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1000" => -- eorb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_eor;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1001" => -- adcb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_adc;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1010" => -- orab
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ora;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1011" => -- addb
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_add8;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1100" => -- ldd
					    left_ctrl   <= accd_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ld16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= load_hi_acca;
                   accb_ctrl   <= load_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1101" => -- std
					    left_ctrl   <= accd_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_st16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when "1110" => -- ldx
					    left_ctrl   <= ix_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_ld16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= load_ix;
						 sp_ctrl     <= latch_sp;
					  when "1111" => -- stx
					    left_ctrl   <= ix_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_st16;
						 cc_ctrl     <= load_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  when others =>
					    left_ctrl   <= accb_left;
					    right_ctrl  <= md_right;
					    alu_ctrl    <= alu_nop;
						 cc_ctrl     <= latch_cc;
					    acca_ctrl   <= latch_acca;
                   accb_ctrl   <= latch_accb;
                   ix_ctrl     <= latch_ix;
                   sp_ctrl     <= latch_sp;
					  end case;
	            when others =>
					  left_ctrl   <= accd_left;
					  right_ctrl  <= md_right;
					  alu_ctrl    <= alu_nop;
					  cc_ctrl     <= latch_cc;
					  acca_ctrl   <= latch_acca;
                 accb_ctrl   <= latch_accb;
                 ix_ctrl     <= latch_ix;
                 sp_ctrl     <= latch_sp;
              end case;
             md_ctrl    <= latch_md;
				 -- fetch the op code
			    op_ctrl    <= fetch_op;
             ea_ctrl    <= reset_ea;
             addr_ctrl  <= fetch_ad;
             dout_ctrl  <= md_lo_dout;
		  	    iv_ctrl    <= latch_iv;
				 if halt = '1' then
               pc_ctrl    <= latch_pc;
				   nmi_ctrl   <= latch_nmi;
			      next_state <= halt_state;
				 -- service non maskable interrupts
			    elsif (nmi_req = '1') and (nmi_ack = '0') then
               pc_ctrl    <= latch_pc;
				   nmi_ctrl   <= set_nmi;
			      next_state <= int_pcl_state;
				 -- service maskable interrupts
			    else
				   --
					-- nmi request is not cleared until nmi input goes low
					--
				   if(nmi_req = '0') and (nmi_ack='1') then
				     nmi_ctrl <= reset_nmi;
					else
					  nmi_ctrl <= latch_nmi;
					end if;
					--
					-- IRQ is level sensitive
					--
				   if (irq = '1') and (cc(IBIT) = '0') then
                 pc_ctrl    <= latch_pc;
			        next_state <= int_pcl_state;
               else
				   -- Advance the PC to fetch next instruction byte
                 pc_ctrl    <= inc_pc;
			        next_state <= decode_state;
               end if;
				 end if;
			 --
			 -- Here to decode instruction
			 -- and fetch next byte of intruction
			 -- whether it be necessary or not
			 --
          when decode_state =>
				 -- fetch first byte of address or immediate data
             ea_ctrl    <= fetch_first_ea;
             addr_ctrl  <= fetch_ad;
             dout_ctrl  <= md_lo_dout;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             iv_ctrl    <= latch_iv;
			    case op_code(7 downto 4) is
				 when "0000" =>
				   md_ctrl    <= fetch_first_md;
               sp_ctrl    <= latch_sp;
               pc_ctrl    <= latch_pc;
  	            case op_code(3 downto 0) is
		         when "0001" => -- nop
					  left_ctrl  <= accd_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "0100" => -- lsrd
					  left_ctrl  <= accd_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_lsr16;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_hi_acca;
					  accb_ctrl  <= load_accb;
					  ix_ctrl    <= latch_ix;
		         when "0101" => -- lsld
					  left_ctrl  <= accd_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_lsl16;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_hi_acca;
					  accb_ctrl  <= load_accb;
					  ix_ctrl    <= latch_ix;
		         when "0110" => -- tap
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_tap;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "0111" => -- tpa
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_tpa;
                 cc_ctrl    <= latch_cc;
					  acca_ctrl  <= load_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1000" => -- inx
					  left_ctrl  <= ix_left;
	              right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_inx;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= load_ix;
		         when "1001" => -- dex
					  left_ctrl  <= ix_left;
	              right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_dex;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= load_ix;
		         when "1010" => -- clv
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_clv;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1011" => -- sev
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_sev;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1100" => -- clc
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_clc;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1101" => -- sec
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_sec;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1110" => -- cli
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_cli;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         when "1111" => -- sei
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_sei;
                 cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
               when others =>
					  left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= latch_accb;
					  ix_ctrl    <= latch_ix;
		         end case;
					next_state <= fetch_state;
				 -- acca / accb inherent instructions
	          when "0001" =>
				   md_ctrl    <= fetch_first_md;
               ix_ctrl    <= latch_ix;
               sp_ctrl    <= latch_sp;
               pc_ctrl    <= latch_pc;
					left_ctrl  <= acca_left;
	            right_ctrl <= accb_right;
	            case op_code(3 downto 0) is
		         when "0000" => -- sba
					  alu_ctrl   <= alu_sub8;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_acca;
                 accb_ctrl  <= latch_accb;
		         when "0001" => -- cba
					  alu_ctrl   <= alu_sub8;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
		         when "0110" => -- tab
					  alu_ctrl   <= alu_st8;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= latch_acca;
					  accb_ctrl  <= load_accb;
		         when "0111" => -- tba
					  alu_ctrl   <= alu_ld8;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_acca;
                 accb_ctrl  <= latch_accb;
		         when "1001" => -- daa
					  alu_ctrl   <= alu_daa;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_acca;
                 accb_ctrl  <= latch_accb;
		         when "1011" => -- aba
					  alu_ctrl   <= alu_add8;
					  cc_ctrl    <= load_cc;
					  acca_ctrl  <= load_acca;
                 accb_ctrl  <= latch_accb;
		         when others =>
					  alu_ctrl   <= alu_nop;
					  cc_ctrl    <= latch_cc;
					  acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
		         end case;
					next_state <= fetch_state;
	          when "0010" => -- branch conditional
				   md_ctrl    <= fetch_first_md;
					acca_ctrl  <= latch_acca;
               accb_ctrl  <= latch_accb;
               ix_ctrl    <= latch_ix;
               sp_ctrl    <= latch_sp;
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
					-- increment the pc
               pc_ctrl    <= inc_pc;
               case op_code(3 downto 0) is
		         when "0000" => -- bra
                 next_state <= branch_state;
		         when "0001" => -- brn
					  next_state <= fetch_state;
		         when "0010" => -- bhi
					  if (cc(CBIT) or cc(ZBIT)) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "0011" => -- bls
					  if (cc(CBIT) or cc(ZBIT)) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "0100" => -- bcc/bhs
					  if cc(CBIT) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "0101" => -- bcs/blo
					  if cc(CBIT) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "0110" => -- bne
					  if cc(ZBIT) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "0111" => -- beq
					  if cc(ZBIT) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1000" => -- bvc
					  if cc(VBIT) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1001" => -- bvs
					  if cc(VBIT) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1010" => -- bpl
					  if cc(NBIT) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1011" => -- bmi
					  if cc(NBIT) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1100" => -- bge
					  if (cc(NBIT) xor cc(VBIT)) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1101" => -- blt
					  if (cc(NBIT) xor cc(VBIT)) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1110" => -- bgt
					  if (cc(ZBIT) or (cc(NBIT) xor cc(VBIT))) = '0' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when "1111" => -- ble
					  if (cc(ZBIT) or (cc(NBIT) xor cc(VBIT))) = '1' then
					    next_state <= branch_state;
					  else
					    next_state <= fetch_state;
					  end if;
		         when others =>
					  next_state <= fetch_state;
		         end case;
				 --
				 -- Single byte stack operators
				 -- Do not advance PC
				 --
	          when "0011" =>
				   md_ctrl    <= fetch_first_md;
					acca_ctrl  <= latch_acca;
               accb_ctrl  <= latch_accb;
               pc_ctrl    <= latch_pc;
	            case op_code(3 downto 0) is
		         when "0000" => -- tsx
		            left_ctrl  <= sp_left;
		            right_ctrl <= plus_one_right;
						alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= load_ix;
                  sp_ctrl    <= latch_sp;
						next_state <= fetch_state;
		         when "0001" => -- ins
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= fetch_state;
		         when "0010" => -- pula
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= pula_state;
		         when "0011" => -- pulb
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= pulb_state;
		         when "0100" => -- des
                  -- decrement sp
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_sub16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= fetch_state;
		         when "0101" => -- txs
		            left_ctrl  <= ix_left;
		            right_ctrl <= plus_one_right;
						alu_ctrl   <= alu_sub16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= load_sp;
						next_state <= fetch_state;
		         when "0110" => -- psha
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= psha_state;
		         when "0111" => -- pshb
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= pshb_state;
		         when "1000" => -- pulx
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= pulx_hi_state;
		         when "1001" => -- rts
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= rts_hi_state;
		         when "1010" => -- abx
		            left_ctrl  <= ix_left;
		            right_ctrl <= accb_right;
						alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= load_ix;
                  sp_ctrl    <= latch_sp;
						next_state <= fetch_state;
		         when "1011" => -- rti
                  left_ctrl  <= sp_left;
                  right_ctrl <= plus_one_right;
                  alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
                  sp_ctrl    <= load_sp;
						next_state <= rti_cc_state;
		         when "1100" => -- pshx
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= pshx_lo_state;
		         when "1101" => -- mul
		            left_ctrl  <= acca_left;
		            right_ctrl <= accb_right;
						alu_ctrl   <= alu_add16;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= mul_state;
		         when "1110" => -- wai
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= int_pcl_state;
		         when "1111" => -- swi
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= int_pcl_state;
		         when others =>
		            left_ctrl  <= sp_left;
		            right_ctrl <= zero_right;
						alu_ctrl   <= alu_nop;
					   cc_ctrl    <= latch_cc;
						ix_ctrl    <= latch_ix;
						sp_ctrl    <= latch_sp;
						next_state <= fetch_state;
		         end case;
				 --
				 -- Accumulator A Single operand
				 -- source = Acc A dest = Acc A
				 -- Do not advance PC
				 --
	          when "0100" => -- acca single op
				   md_ctrl    <= fetch_first_md;
               accb_ctrl  <= latch_accb;
               pc_ctrl    <= latch_pc;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
		         left_ctrl  <= acca_left;
	            case op_code(3 downto 0) is
		         when "0000" => -- neg
					  right_ctrl <= zero_right;
					  alu_ctrl   <= alu_neg;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
 	            when "0011" => -- com
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_com;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "0100" => -- lsr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_lsr8;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "0110" => -- ror
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_ror8;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "0111" => -- asr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_asr8;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "1000" => -- asl
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_asl8;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "1001" => -- rol
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_rol8;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "1010" => -- dec
		           right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_dec;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "1011" => -- undefined
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  acca_ctrl  <= latch_acca;
					  cc_ctrl    <= latch_cc;
		         when "1100" => -- inc
		           right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_inc;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when "1101" => -- tst
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_st8;
					  acca_ctrl  <= latch_acca;
					  cc_ctrl    <= load_cc;
		         when "1110" => -- jmp
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  acca_ctrl  <= latch_acca;
					  cc_ctrl    <= latch_cc;
		         when "1111" => -- clr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_clr;
					  acca_ctrl  <= load_acca;
					  cc_ctrl    <= load_cc;
		         when others =>
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  acca_ctrl  <= latch_acca;
					  cc_ctrl    <= latch_cc;
		         end case;
				   next_state <= fetch_state;
				 --
				 -- single operand acc b
				 -- Do not advance PC
				 --
	          when "0101" =>
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
               pc_ctrl    <= latch_pc;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
		         left_ctrl  <= accb_left;
	            case op_code(3 downto 0) is
		         when "0000" => -- neg
					  right_ctrl <= zero_right;
					  alu_ctrl   <= alu_neg;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
 	            when "0011" => -- com
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_com;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "0100" => -- lsr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_lsr8;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "0110" => -- ror
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_ror8;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "0111" => -- asr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_asr8;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "1000" => -- asl
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_asl8;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "1001" => -- rol
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_rol8;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "1010" => -- dec
		           right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_dec;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "1011" => -- undefined
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  accb_ctrl  <= latch_accb;
					  cc_ctrl    <= latch_cc;
		         when "1100" => -- inc
		           right_ctrl <= plus_one_right;
					  alu_ctrl   <= alu_inc;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when "1101" => -- tst
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_st8;
					  accb_ctrl  <= latch_accb;
					  cc_ctrl    <= load_cc;
		         when "1110" => -- jmp
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  accb_ctrl  <= latch_accb;
					  cc_ctrl    <= latch_cc;
		         when "1111" => -- clr
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_clr;
					  accb_ctrl  <= load_accb;
					  cc_ctrl    <= load_cc;
		         when others =>
		           right_ctrl <= zero_right;
					  alu_ctrl   <= alu_nop;
					  accb_ctrl  <= latch_accb;
					  cc_ctrl    <= latch_cc;
		         end case;
				   next_state <= fetch_state;
				 --
				 -- Single operand indexed
				 -- Two byte instruction so advance PC
				 -- EA should hold index offset
				 --
	          when "0110" => -- indexed single op
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc 
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= indexed_state;
             --
				 -- Single operand extended addressing
				 -- three byte instruction so advance the PC
				 -- Low order EA holds high order address
				 --
	          when "0111" => -- extended single op
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= extended_state;

	          when "1000" => -- acca immediate
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
				   -- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
					case op_code(3 downto 0) is
               when "0011" | -- subdd #
					     "1100" | -- cpx #
					     "1110" => -- lds #
					  next_state <= immediate16_state;
					when "1101" => -- bsr
					  next_state <= bsr_state;
					when others =>
				     next_state <= fetch_state;
               end case;

	          when "1001" => -- acca direct
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               pc_ctrl    <= inc_pc;
					case op_code(3 downto 0) is
					when "0111" =>  -- staa direct
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st8;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1111" => -- sts direct
                 left_ctrl  <= sp_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st16;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= load_md;
				     next_state <= write16_state;
					when "1101" => -- jsr direct
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= fetch_first_md;
					  next_state <= jsr_state;
					when others =>
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= fetch_first_md;
				     next_state <= read8_state;
               end case;

	          when "1010" => -- acca indexed
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= indexed_state;

             when "1011" => -- acca extended
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= extended_state;

	          when "1100" => -- accb immediate
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
					case op_code(3 downto 0) is
               when "0011" | -- addd #
					     "1100" | -- ldd #
					     "1110" => -- ldx #
					  next_state <= immediate16_state;
					when others =>
				     next_state <= fetch_state;
               end case;

	          when "1101" => -- accb direct
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               pc_ctrl    <= inc_pc;
					case op_code(3 downto 0) is
					when "0111" =>  -- stab direct
                 left_ctrl  <= accb_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st8;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1101" => -- std direct
                 left_ctrl  <= accd_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st16;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= load_md;
					  next_state <= write16_state;
					when "1111" => -- stx direct
                 left_ctrl  <= ix_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st16;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= load_md;
				     next_state <= write16_state;
					when others =>
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
					  cc_ctrl    <= latch_cc;
				     md_ctrl    <= fetch_first_md;
				     next_state <= read8_state;
               end case;

	          when "1110" => -- accb indexed
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= indexed_state;

             when "1111" => -- accb extended
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- increment the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
					cc_ctrl    <= latch_cc;
               pc_ctrl    <= inc_pc;
				   next_state <= extended_state;

	          when others =>
				   md_ctrl    <= fetch_first_md;
               acca_ctrl  <= latch_acca;
					accb_ctrl  <= latch_accb;
				   ix_ctrl    <= latch_ix;
				   sp_ctrl    <= latch_sp;
					-- idle the pc
               left_ctrl  <= acca_left;
               right_ctrl <= zero_right;
               alu_ctrl   <= alu_nop;
  					cc_ctrl    <= latch_cc;
               pc_ctrl    <= latch_pc;
 		         next_state <= fetch_state;
             end case;

			  when immediate16_state =>
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
			    op_ctrl    <= latch_op;
             iv_ctrl    <= latch_iv;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment pc
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
             pc_ctrl    <= inc_pc;
				 -- fetch next immediate byte
			    md_ctrl    <= fetch_next_md;
             addr_ctrl  <= fetch_ad;
             dout_ctrl  <= md_lo_dout;
				 next_state <= fetch_state;
           --
			  -- ea holds 8 bit index offet
			  -- calculate the effective memory address
			  -- using the alu
			  --
           when indexed_state =>
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
				 -- calculate effective address from index reg
             -- index offest is not sign extended
             ea_ctrl    <= add_ix_ea;
				 -- idle the bus
             addr_ctrl  <= idle_ad;
             dout_ctrl  <= md_lo_dout;
				 -- work out next state
				 case op_code(7 downto 4) is
				 when "0110" => -- single op indexed
               md_ctrl    <= latch_md;
			      left_ctrl  <= acca_left;
				   right_ctrl <= zero_right;
				   alu_ctrl   <= alu_nop;
               cc_ctrl    <= latch_cc;
	            case op_code(3 downto 0) is
		         when "1011" => -- undefined
					  next_state <= fetch_state;
		         when "1110" => -- jmp
					  next_state <= jmp_state;
		         when others =>
					  next_state <= read8_state;
		         end case;
	          when "1010" => -- acca indexed
				   case op_code(3 downto 0) is
					when "0111" =>  -- staa
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st8;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1101" => -- jsr
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= jsr_state;
					when "1111" => -- sts
			        left_ctrl  <= sp_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write16_state;
					when others =>
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= read8_state;
					end case;
	          when "1110" => -- accb indexed
				   case op_code(3 downto 0) is
					when "0111" =>  -- stab direct
			        left_ctrl  <= accb_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st8;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1101" => -- std direct
			        left_ctrl  <= accd_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
					  next_state <= write16_state;
					when "1111" => -- stx direct
			        left_ctrl  <= ix_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write16_state;
					when others =>
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= read8_state;
					end case;
			    when others =>
               md_ctrl    <= latch_md;
			      left_ctrl  <= acca_left;
				   right_ctrl <= zero_right;
				   alu_ctrl   <= alu_nop;
               cc_ctrl    <= latch_cc;
					next_state <= fetch_state;
			    end case;
           --
			  -- ea holds the low byte of the absolute address
			  -- Move ea low byte into ea high byte
			  -- load new ea low byte to for absolute 16 bit address
			  -- advance the program counter
			  --
			  when extended_state => -- fetch ea low byte
               acca_ctrl  <= latch_acca;
               accb_ctrl  <= latch_accb;
               ix_ctrl    <= latch_ix;
               sp_ctrl    <= latch_sp;
               iv_ctrl    <= latch_iv;
			      op_ctrl    <= latch_op;
				   nmi_ctrl   <= latch_nmi;
					-- increment pc
               pc_ctrl    <= inc_pc;
					-- fetch next effective address bytes
					ea_ctrl    <= fetch_next_ea;
               addr_ctrl  <= fetch_ad;
					dout_ctrl  <= md_lo_dout;
					-- work out the next state
				 case op_code(7 downto 4) is
				 when "0111" => -- single op extended
               md_ctrl    <= latch_md;
			      left_ctrl  <= acca_left;
				   right_ctrl <= zero_right;
				   alu_ctrl   <= alu_nop;
               cc_ctrl    <= latch_cc;
	            case op_code(3 downto 0) is
		         when "1011" => -- undefined
					  next_state <= fetch_state;
		         when "1110" => -- jmp
					  next_state <= jmp_state;
		         when others =>
					  next_state <= read8_state;
		         end case;
	          when "1011" => -- acca extended
				   case op_code(3 downto 0) is
					when "0111" =>  -- staa
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st8;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1101" => -- jsr
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= jsr_state;
					when "1111" => -- sts
			        left_ctrl  <= sp_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write16_state;
					when others =>
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= read8_state;
					end case;
	          when "1111" => -- accb extended
				   case op_code(3 downto 0) is
					when "0111" =>  -- stab
			        left_ctrl  <= accb_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st8;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write8_state;
					when "1101" => -- std
			        left_ctrl  <= accd_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
					  next_state <= write16_state;
					when "1111" => -- stx
			        left_ctrl  <= ix_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
				     next_state <= write16_state;
					when others =>
			        left_ctrl  <= acca_left;
				     right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= latch_md;
					  next_state <= read8_state;
					end case;
			    when others =>
               md_ctrl    <= latch_md;
			      left_ctrl  <= acca_left;
				   right_ctrl <= zero_right;
				   alu_ctrl   <= alu_nop;
               cc_ctrl    <= latch_cc;
					next_state <= fetch_state;
			    end case;
           --
			  -- here if ea holds low byte (direct page)
			  -- can enter here from extended addressing
			  -- read memory location
			  -- note that reads may be 8 or 16 bits
			  --
			  when read8_state => -- read data
               acca_ctrl  <= latch_acca;
               accb_ctrl  <= latch_accb;
               ix_ctrl    <= latch_ix;
               sp_ctrl    <= latch_sp;
               pc_ctrl    <= latch_pc;
               iv_ctrl    <= latch_iv;
			      op_ctrl    <= latch_op;
				   nmi_ctrl   <= latch_nmi;
					--
               addr_ctrl  <= read_ad;
					dout_ctrl  <= md_lo_dout;
					case op_code(7 downto 4) is
					  when "0110" | "0111" => -- single operand
 					      left_ctrl  <= acca_left;
					      right_ctrl <= zero_right;
					      alu_ctrl   <= alu_nop;
                     cc_ctrl    <= latch_cc;
				         md_ctrl    <= fetch_first_md;
					      ea_ctrl    <= latch_ea;
					      next_state <= execute_state;

	              when "1001" | "1010" | "1011" => -- acca
				       case op_code(3 downto 0) is
					    when "0011" |  -- subd
					         "1110" |  -- lds
					         "1100" => -- cpx
 					      left_ctrl  <= acca_left;
					      right_ctrl <= zero_right;
					      alu_ctrl   <= alu_nop;
                     cc_ctrl    <= latch_cc;
				         md_ctrl    <= fetch_first_md;
				         -- increment the effective address in case of 16 bit load
					      ea_ctrl    <= inc_ea;
					      next_state <= read16_state;
--					    when "0111" =>   -- staa
-- 					      left_ctrl  <= acca_left;
--					      right_ctrl <= zero_right;
--					      alu_ctrl   <= alu_st8;
--                     cc_ctrl    <= latch_cc;
--				         md_ctrl    <= load_md;
-- 					      ea_ctrl    <= latch_ea;
--					      next_state <= write8_state;
--					    when "1101" => -- jsr
--			            left_ctrl  <= acca_left;
--				         right_ctrl <= zero_right;
--				         alu_ctrl   <= alu_nop;
--                     cc_ctrl    <= latch_cc;
--                     md_ctrl    <= latch_md;
-- 					      ea_ctrl    <= latch_ea;
--					      next_state <= jsr_state;
--					    when "1111" =>  -- sts
-- 					      left_ctrl  <= sp_left;
--					      right_ctrl <= zero_right;
--					      alu_ctrl   <= alu_st16;
--                     cc_ctrl    <= latch_cc;
--				         md_ctrl    <= load_md;
--					      ea_ctrl    <= latch_ea;
--					      next_state <= write16_state;
					    when others =>
 					      left_ctrl  <= acca_left;
					      right_ctrl <= zero_right;
					      alu_ctrl   <= alu_nop;
                     cc_ctrl    <= latch_cc;
				         md_ctrl    <= fetch_first_md;
 					      ea_ctrl    <= latch_ea;
					      next_state <= fetch_state;
					    end case;

	              when "1101" | "1110" | "1111" => -- accb
				       case op_code(3 downto 0) is
					    when "0011" |  -- addd
					         "1100" |  -- ldd
					         "1110" => -- ldx
 					      left_ctrl  <= acca_left;
					      right_ctrl <= zero_right;
					      alu_ctrl   <= alu_nop;
                     cc_ctrl    <= latch_cc;
				         md_ctrl    <= fetch_first_md;
				         -- increment the effective address in case of 16 bit load
					      ea_ctrl    <= inc_ea;
					      next_state <= read16_state;
--					    when "0111" =>   -- stab
-- 					      left_ctrl  <= accb_left;
--					      right_ctrl <= zero_right;
--					      alu_ctrl   <= alu_st8;
--                     cc_ctrl    <= latch_cc;
--				         md_ctrl    <= load_md;
--					      ea_ctrl    <= latch_ea;
--					      next_state <= write8_state;
--					    when "1101" => -- std
--			            left_ctrl  <= accd_left;
--				         right_ctrl <= zero_right;
--				         alu_ctrl   <= alu_st16;
--                     cc_ctrl    <= latch_cc;
--                     md_ctrl    <= load_md;
-- 					      ea_ctrl    <= latch_ea;
--					      next_state <= write16_state;
--					    when "1111" =>  -- stx
-- 					      left_ctrl  <= ix_left;
--					      right_ctrl <= zero_right;
--					      alu_ctrl   <= alu_st16;
--                     cc_ctrl    <= latch_cc;
--				         md_ctrl    <= load_md;
--					      ea_ctrl    <= latch_ea;
--					      next_state <= write16_state;
					    when others =>
 					      left_ctrl  <= acca_left;
					      right_ctrl <= zero_right;
					      alu_ctrl   <= alu_nop;
                     cc_ctrl    <= latch_cc;
				         md_ctrl    <= fetch_first_md;
					      ea_ctrl    <= latch_ea;
					      next_state <= execute_state;
					    end case;
					  when others =>
 					    left_ctrl  <= acca_left;
					    right_ctrl <= zero_right;
					    alu_ctrl   <= alu_nop;
                   cc_ctrl    <= latch_cc;
				       md_ctrl    <= fetch_first_md;
					    ea_ctrl    <= latch_ea;
					    next_state <= fetch_state;
					  end case;

			   when read16_state => -- read second data byte from ea
                 -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  -- idle the effective address
                 ea_ctrl    <= latch_ea;
					  -- read the low byte of the 16 bit data
				     md_ctrl    <= fetch_next_md;
                 addr_ctrl  <= read_ad;
                 dout_ctrl  <= md_lo_dout;
					  next_state <= fetch_state;
           --
			  -- 16 bit Write state
			  -- write high byte of ALU output.
			  -- EA hold address of memory to write to
			  -- Advance the effective address in ALU
			  --
			  when write16_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
				 -- increment the effective address
				 left_ctrl  <= acca_left;
				 right_ctrl <= zero_right;
				 alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
			    ea_ctrl    <= inc_ea;
 				 -- write the ALU hi byte to ea
             addr_ctrl  <= write_ad;
             dout_ctrl  <= md_hi_dout;
				 next_state <= write8_state;
           --
			  -- 8 bit write
			  -- Write low 8 bits of ALU output
			  --
			  when write8_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- idle the ALU
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
				 -- write ALU low byte output
             addr_ctrl  <= write_ad;
             dout_ctrl  <= md_lo_dout;
				 next_state <= fetch_state;

				when jmp_state =>
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- load PC with effective address
                 left_ctrl  <= acca_left;
					  right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  pc_ctrl    <= load_ea_pc;
					  -- idle the bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
                 next_state <= fetch_state;

				when jsr_state => -- JSR
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
                 -- decrement sp
                 left_ctrl  <= sp_left;
                 right_ctrl <= plus_one_right;
                 alu_ctrl   <= alu_sub16;
                 cc_ctrl    <= latch_cc;
                 sp_ctrl    <= load_sp;
					  -- write pc low
                 addr_ctrl  <= push_ad;
					  dout_ctrl  <= pc_lo_dout; 
                 next_state <= jsr1_state;

				when jsr1_state => -- JSR
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 pc_ctrl    <= latch_pc;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
                 -- decrement sp
                 left_ctrl  <= sp_left;
                 right_ctrl <= plus_one_right;
                 alu_ctrl   <= alu_sub16;
                 cc_ctrl    <= latch_cc;
                 sp_ctrl    <= load_sp;
					  -- write pc hi
                 addr_ctrl  <= push_ad;
					  dout_ctrl  <= pc_hi_dout; 
                 next_state <= jmp_state;

				when branch_state => -- Bcc
				     -- default registers
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- calculate signed branch
					  left_ctrl  <= acca_left;
					  right_ctrl <= zero_right;
				     alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  pc_ctrl    <= add_ea_pc;
					  -- idle the bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
                 next_state <= fetch_state;

				when bsr_state => -- BSR
				     -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 pc_ctrl    <= latch_pc;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
                 -- decrement sp
                 left_ctrl  <= sp_left;
                 right_ctrl <= plus_one_right;
                 alu_ctrl   <= alu_sub16;
                 cc_ctrl    <= latch_cc;
                 sp_ctrl    <= load_sp;
					  -- write pc low
                 addr_ctrl  <= push_ad;
					  dout_ctrl  <= pc_lo_dout; 
                 next_state <= bsr1_state;

				when bsr1_state => -- BSR
				     -- default registers
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 pc_ctrl    <= latch_pc;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
                 -- decrement sp
                 left_ctrl  <= sp_left;
                 right_ctrl <= plus_one_right;
                 alu_ctrl   <= alu_sub16;
                 cc_ctrl    <= latch_cc;
                 sp_ctrl    <= load_sp;
					  -- write pc hi
                 addr_ctrl  <= push_ad;
					  dout_ctrl  <= pc_hi_dout; 
                 next_state <= branch_state;

				 when rts_hi_state => -- RTS
				     -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 pc_ctrl    <= latch_pc;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- increment the sp
                 left_ctrl  <= sp_left;
                 right_ctrl <= plus_one_right;
                 alu_ctrl   <= alu_add16;
                 cc_ctrl    <= latch_cc;
                 sp_ctrl    <= load_sp;
                 -- read pc hi
					  pc_ctrl    <= pull_hi_pc;
                 addr_ctrl  <= pull_ad;
                 dout_ctrl  <= pc_hi_dout;
                 next_state <= rts_lo_state;

				when rts_lo_state => -- RTS1
				     -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 md_ctrl    <= latch_md;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- idle the ALU
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  -- read pc low
					  pc_ctrl    <= pull_lo_pc;
                 addr_ctrl  <= pull_ad;
                 dout_ctrl  <= pc_lo_dout;
                 next_state <= fetch_state;

				 when mul_state =>
				     -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- move acca to md
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_st16;
                 cc_ctrl    <= latch_cc;
                 md_ctrl    <= load_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mulea_state;

				 when mulea_state =>
				     -- default
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 md_ctrl    <= latch_md;
					  -- idle ALU
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_nop;
                 cc_ctrl    <= latch_cc;
					  -- move accb to ea
                 ea_ctrl    <= load_accb_ea;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= muld_state;

				 when muld_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
                 md_ctrl    <= latch_md;
					  -- clear accd
                 left_ctrl  <= acca_left;
                 right_ctrl <= zero_right;
                 alu_ctrl   <= alu_ld8;
                 cc_ctrl    <= latch_cc;
                 acca_ctrl  <= load_hi_acca;
                 accb_ctrl  <= load_accb;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul0_state;

				 when mul0_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 0 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(0) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul1_state;

				 when mul1_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 1 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(1) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul2_state;

				 when mul2_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 2 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(2) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul3_state;

				 when mul3_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 3 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(3) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul4_state;

				 when mul4_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 4 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(4) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul5_state;

				 when mul5_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 5 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(5) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul6_state;

				 when mul6_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 6 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(6) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= mul7_state;

				 when mul7_state =>
				     -- default
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
			        op_ctrl    <= latch_op;
				     nmi_ctrl   <= latch_nmi;
                 ea_ctrl    <= latch_ea;
					  -- if bit 7 of ea set, add accd to md
                 left_ctrl  <= accd_left;
                 right_ctrl <= md_right;
                 alu_ctrl   <= alu_add16;
					  if ea(7) = '1' then
                   cc_ctrl    <= load_cc;
                   acca_ctrl  <= load_hi_acca;
                   accb_ctrl  <= load_accb;
					  else
                   cc_ctrl    <= latch_cc;
                   acca_ctrl  <= latch_acca;
                   accb_ctrl  <= latch_accb;
					  end if;
                 md_ctrl    <= shiftl_md;
					  -- idle bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
				     next_state <= fetch_state;

			    when execute_state => -- execute single operand instruction
				   -- default
			      op_ctrl    <= latch_op;
				   nmi_ctrl   <= latch_nmi;
			      case op_code(7 downto 4) is
	            when "0110" | -- indexed single op
	                 "0111" => -- extended single op
                 acca_ctrl  <= latch_acca;
                 accb_ctrl  <= latch_accb;
                 ix_ctrl    <= latch_ix;
                 sp_ctrl    <= latch_sp;
                 pc_ctrl    <= latch_pc;
                 iv_ctrl    <= latch_iv;
                 ea_ctrl    <= latch_ea;
					  -- idle the bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
                 left_ctrl  <= md_left;
	              case op_code(3 downto 0) is
		           when "0000" => -- neg
					    right_ctrl <= zero_right;
					    alu_ctrl   <= alu_neg;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
 	              when "0011" => -- com
		             right_ctrl <= zero_right;
					    alu_ctrl   <= alu_com;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "0100" => -- lsr
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_lsr8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "0110" => -- ror
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_ror8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "0111" => -- asr
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_asr8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "1000" => -- asl
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_asl8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "1001" => -- rol
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_rol8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "1010" => -- dec
		             right_ctrl <= plus_one_right;
					    alu_ctrl   <= alu_dec;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "1011" => -- undefined
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_nop;
					    cc_ctrl    <= latch_cc;
				       md_ctrl    <= latch_md;
				       next_state <= fetch_state;
		           when "1100" => -- inc
		             right_ctrl <= plus_one_right;
					    alu_ctrl   <= alu_inc;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when "1101" => -- tst
		             right_ctrl <= zero_right;
					    alu_ctrl   <= alu_st8;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= latch_md;
				       next_state <= fetch_state;
		           when "1110" => -- jmp
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_nop;
					    cc_ctrl    <= latch_cc;
				       md_ctrl    <= latch_md;
				       next_state <= fetch_state;
		           when "1111" => -- clr
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_clr;
					    cc_ctrl    <= load_cc;
				       md_ctrl    <= load_md;
				       next_state <= write8_state;
		           when others =>
						 right_ctrl <= zero_right;
					    alu_ctrl   <= alu_nop;
					    cc_ctrl    <= latch_cc;
				       md_ctrl    <= latch_md;
				       next_state <= fetch_state;
		           end case;

	            when others =>
					  left_ctrl   <= accd_left;
					  right_ctrl  <= md_right;
					  alu_ctrl    <= alu_nop;
					  cc_ctrl     <= latch_cc;
					  acca_ctrl   <= latch_acca;
                 accb_ctrl   <= latch_accb;
                 ix_ctrl     <= latch_ix;
                 sp_ctrl     <= latch_sp;
                 pc_ctrl     <= latch_pc;
                 md_ctrl     <= latch_md;
                 iv_ctrl     <= latch_iv;
                 ea_ctrl     <= latch_ea;
					  -- idle the bus
                 addr_ctrl  <= idle_ad;
                 dout_ctrl  <= md_lo_dout;
		           next_state <= fetch_state;
              end case;

			  when psha_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write acca
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= acca_dout; 
             next_state <= fetch_state;

			  when pula_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- idle sp
             left_ctrl  <= sp_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= latch_sp;
				 -- read acca
				 acca_ctrl  <= pull_acca;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= acca_dout;
             next_state <= fetch_state;

			  when pshb_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write accb
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= accb_dout; 
             next_state <= fetch_state;

			  when pulb_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- idle sp
             left_ctrl  <= sp_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= latch_sp;
				 -- read accb
				 accb_ctrl  <= pull_accb;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= accb_dout;
             next_state <= fetch_state;

			  when pshx_lo_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write ix low
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= ix_lo_dout; 
             next_state <= pshx_hi_state;

			  when pshx_hi_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write ix hi
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= ix_hi_dout; 
             next_state <= fetch_state;

		  	  when pulx_hi_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- pull ix hi
				 ix_ctrl    <= pull_hi_ix;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= ix_hi_dout;
             next_state <= pulx_lo_state;

		  	  when pulx_lo_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- idle sp
             left_ctrl  <= sp_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= latch_sp;
				 -- read ix low
				 ix_ctrl    <= pull_lo_ix;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= ix_lo_dout;
             next_state <= fetch_state;

           --
			  -- return from interrupt
			  -- enter here from bogus interrupts
			  --
			  when rti_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             sp_ctrl    <= load_sp;
				 -- idle address bus
             cc_ctrl    <= latch_cc;
             addr_ctrl  <= idle_ad;
             dout_ctrl  <= cc_dout;
             next_state <= rti_cc_state;

			  when rti_cc_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             sp_ctrl    <= load_sp;
				 -- read cc
             cc_ctrl    <= pull_cc;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= cc_dout;
             next_state <= rti_accb_state;

			  when rti_accb_state =>
				 -- default registers
             acca_ctrl  <= latch_acca;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- read accb
				 accb_ctrl  <= pull_accb;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= accb_dout;
             next_state <= rti_acca_state;

			  when rti_acca_state =>
				 -- default registers
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- read acca
				 acca_ctrl  <= pull_acca;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= acca_dout;
             next_state <= rti_ixh_state;

			  when rti_ixh_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- read ix hi
				 ix_ctrl    <= pull_hi_ix;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= ix_hi_dout;
             next_state <= rti_ixl_state;

			  when rti_ixl_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- read ix low
				 ix_ctrl    <= pull_lo_ix;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= ix_lo_dout;
             next_state <= rti_pch_state;

			  when rti_pch_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
	          -- increment sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_add16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- pull pc hi
				 pc_ctrl    <= pull_hi_pc;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= pc_hi_dout;
             next_state <= rti_pcl_state;

			  when rti_pcl_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- idle sp
             left_ctrl  <= sp_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= latch_sp;
	          -- pull pc low
				 pc_ctrl    <= pull_lo_pc;
             addr_ctrl  <= pull_ad;
             dout_ctrl  <= pc_lo_dout;
             next_state <= fetch_state;

			  --
			  -- here on interrupt
			  -- iv register hold interrupt type
			  --
			  when int_pcl_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write pc low
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= pc_lo_dout; 
             next_state <= int_pch_state;

			  when int_pch_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write pc hi
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= pc_hi_dout; 
             next_state <= int_ixl_state;

			  when int_ixl_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write ix low
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= ix_lo_dout; 
             next_state <= int_ixh_state;

			  when int_ixh_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write ix hi
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= ix_hi_dout; 
             next_state <= int_acca_state;

			  when int_acca_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write acca
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= acca_dout; 
             next_state <= int_accb_state;


			  when int_accb_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write accb
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= accb_dout; 
             next_state <= int_cc_state;

			  when int_cc_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
             -- decrement sp
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_sub16;
             cc_ctrl    <= latch_cc;
             sp_ctrl    <= load_sp;
				 -- write cc
             addr_ctrl  <= push_ad;
			    dout_ctrl  <= cc_dout;
				 nmi_ctrl   <= latch_nmi;
				 --
				 -- nmi is edge triggered
				 -- nmi_req is cleared when nmi goes low.
				 --
			    if nmi_req = '1' then
		  			iv_ctrl    <= nmi_iv;
			      next_state <= vect_hi_state;
			    else
					--
					-- IRQ is level sensitive
					--
				   if (irq = '1') and (cc(IBIT) = '0') then
		  			  iv_ctrl    <= irq_iv;
			        next_state <= int_mask_state;
               else
					  case op_code is
					  when "00111110" => -- WAI (wait for interrupt)
                   iv_ctrl    <= latch_iv;
	                next_state <= int_wai_state;
					  when "00111111" => -- SWI (Software interrupt)
                   iv_ctrl    <= swi_iv;
	                next_state <= vect_hi_state;
					  when others => -- bogus interrupt (return)
                   iv_ctrl    <= latch_iv;
	                next_state <= rti_state;
					  end case;
					end if;
				 end if;

			  when int_wai_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
			    op_ctrl    <= latch_op;
             ea_ctrl    <= latch_ea;
             -- enable interrupts
             left_ctrl  <= sp_left;
             right_ctrl <= plus_one_right;
             alu_ctrl   <= alu_cli;
             cc_ctrl    <= load_cc;
             sp_ctrl    <= latch_sp;
				 -- idle bus
             addr_ctrl  <= idle_ad;
			    dout_ctrl  <= cc_dout; 
			    if (nmi_req = '1') and (nmi_ack='0') then
		  			iv_ctrl    <= nmi_iv;
				   nmi_ctrl   <= set_nmi;
			      next_state <= vect_hi_state;
			    else
				   --
					-- nmi request is not cleared until nmi input goes low
					--
				   if (nmi_req = '0') and (nmi_ack='1') then
				     nmi_ctrl <= reset_nmi;
					else
					  nmi_ctrl <= latch_nmi;
					end if;
					--
					-- IRQ is level sensitive
					--
				   if (irq = '1') and (cc(IBIT) = '0') then
		  			  iv_ctrl    <= irq_iv;
			        next_state <= int_mask_state;
               else
                 iv_ctrl    <= latch_iv;
	              next_state <= int_wai_state;
					end if;
				 end if;

			  when int_mask_state =>
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- Mask IRQ
             left_ctrl  <= sp_left;
             right_ctrl <= zero_right;
			    alu_ctrl   <= alu_sei;
				 cc_ctrl    <= load_cc;
             sp_ctrl    <= latch_sp;
				 -- idle bus cycle
             addr_ctrl  <= idle_ad;
             dout_ctrl  <= md_lo_dout;
             next_state <= vect_hi_state;

			  when halt_state => -- halt CPU.
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- do nothing in ALU
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
				 -- idle bus cycle
             addr_ctrl  <= idle_ad;
             dout_ctrl  <= md_lo_dout;
				 if halt = '1' then
			      next_state <= halt_state;
				 else
				   next_state <= fetch_state;
				 end if;

			  when others => -- error state halt on undefine states
				 -- default
             acca_ctrl  <= latch_acca;
             accb_ctrl  <= latch_accb;
             ix_ctrl    <= latch_ix;
             sp_ctrl    <= latch_sp;
             pc_ctrl    <= latch_pc;
             md_ctrl    <= latch_md;
             iv_ctrl    <= latch_iv;
			    op_ctrl    <= latch_op;
				 nmi_ctrl   <= latch_nmi;
             ea_ctrl    <= latch_ea;
				 -- do nothing in ALU
             left_ctrl  <= acca_left;
             right_ctrl <= zero_right;
             alu_ctrl   <= alu_nop;
             cc_ctrl    <= latch_cc;
				 -- idle bus cycle
             addr_ctrl  <= idle_ad;
             dout_ctrl  <= md_lo_dout;
				 next_state <= error_state;
		  end case;
end process;

--------------------------------
--
-- state machine
--
--------------------------------

change_state: process( clk, rst, state, hold )
begin
  if clk'event and clk = '0' then
    if rst = '1' then
 	   state <= reset_state;
    elsif hold = '1' then
	   state <= state;
	 else
      state <= next_state;
	 end if;
  end if;
end process;
	-- output
	
end CPU_ARCH;
	

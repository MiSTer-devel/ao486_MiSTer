--------------------------------------------------------------------------------
-- HDMI PLL Adjust
--------------------------------------------------------------------------------

-- Changes the HDMI PLL frequency according to the scaler suggestions.
--------------------------------------------
-- LLTUNE :
--  15   : Toggle
--  14   : Unused
--  13   : Sign phase difference
--  12:8 : Phase difference. Log (0=Large 31=Small)
--  7:6  : Unused
--  5    : Sign period difference.
--  4:0  : Period difference. Log (0=Large 31=Small)

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY pll_hdmi_adj IS
  PORT (
    -- Scaler
    llena         : IN  std_logic; -- 0=Disabled 1=Enabled
    lltune        : IN  unsigned(15 DOWNTO 0); -- Outputs from scaler
    
    -- Signals from reconfig commands
    i_waitrequest : OUT std_logic;
    i_write       : IN  std_logic;
    i_address     : IN  unsigned(5 DOWNTO 0);
    i_writedata   : IN  unsigned(31 DOWNTO 0);

    -- Outputs to PLL_HDMI_CFG
    o_waitrequest : IN  std_logic;
    o_write       : OUT std_logic;
    o_address     : OUT unsigned(5 DOWNTO 0);
    o_writedata   : OUT unsigned(31 DOWNTO 0);
    
    ------------------------------------
    clk           : IN  std_logic;
    reset_na      : IN  std_logic
    );

BEGIN

  
END ENTITY pll_hdmi_adj;

--##############################################################################

ARCHITECTURE rtl OF pll_hdmi_adj IS
  SIGNAL pwrite : std_logic;
  SIGNAL paddress : unsigned(5 DOWNTO 0);
  SIGNAL pdata    : unsigned(31 DOWNTO 0);
  TYPE enum_state IS (sIDLE,sW1,sW2,sW3);
  SIGNAL state : enum_state;
  SIGNAL lltune_sync,lltune_sync2,lltune_sync3 : unsigned(15 DOWNTO 0);
  SIGNAL mfrac,mfrac_mem : unsigned(31 DOWNTO 0);
  SIGNAL sign,sign_pre : std_logic;
  SIGNAL up,modo,phm,dir : std_logic;
  SIGNAL fcpt : natural RANGE 0 TO 3;
  SIGNAL cptx : natural RANGE 0 TO 3;
  SIGNAL cpt : natural RANGE 0 TO 4095;
  SIGNAL phcor : natural RANGE 0 TO 3;
  SIGNAL diff : unsigned(31 DOWNTO 0);

  TYPE enum_tstate IS (sWAIT,sADJ,sADJ2);
  SIGNAL tstate : enum_tstate;
BEGIN
  ----------------------------------------------------------------------------
  -- 000010 : Start reg "Write either 0 or 1 to start fractional PLL reconf.
  -- 000111 : M counter Fractional Value
  
  Comb:PROCESS(i_write,i_address,
               i_writedata,pwrite,paddress,pdata) IS
  BEGIN
    IF i_write='1' THEN
      o_write      <=i_write;
      o_address    <=i_address;
      o_writedata  <=i_writedata;
    ELSE
      o_write    <=pwrite;
      o_address  <=paddress;
      o_writedata<=pdata;
    END IF;
  END PROCESS Comb;
  
  i_waitrequest<=o_waitrequest WHEN state=sIDLE ELSE '0';
    
  ----------------------------------------------------------------------------
  Schmurtz:PROCESS(clk,reset_na) IS
    VARIABLE off,ofp : natural RANGE 0 TO 63;
    VARIABLE dif : unsigned(31 DOWNTO 0);
  BEGIN
    IF reset_na='0' THEN
      modo<='0';
      state<=sIDLE;
    ELSIF rising_edge(clk) THEN
      IF i_address="000111" AND i_write='1' THEN
        mfrac<=i_writedata;
        mfrac_mem<=i_writedata;
        modo<='1';
      END IF;
      
      lltune_sync<=lltune; -- <ASYNC>
      lltune_sync2<=lltune_sync;
      lltune_sync3<=lltune_sync2;
      
      off:=to_integer('0' & lltune_sync(4 DOWNTO 0));
      ofp:=to_integer('0' & lltune_sync(12 DOWNTO 8));

      IF lltune_sync(15)/=lltune_sync2(15) THEN
        fcpt<=fcpt+1;
        IF fcpt=2 THEN fcpt<=0; END IF;
      END IF;

      CASE tstate IS
        WHEN sWAIT =>
          cpt<=0;
          IF lltune_sync3(15)/=lltune_sync2(15) AND llena='1' THEN

            IF llena='0' THEN 
              -- Recover original freq when disabling low lag mode
              phm<='0';
              IF modo='1' THEN
                mfrac<=mfrac_mem;
                up<='1';
                modo<='0';
              END IF;
              
            ELSIF phm='0' AND fcpt=2 THEN
              -- Frequency adjust
              IF off<10 THEN off:=10; END IF;
				  dif:=shift_right(mfrac,off + 1);
              diff<=dif;
              sign<=lltune_sync(5);
              IF off>=18 THEN
                phm<='1';
              ELSE
                tstate<=sADJ;
              END IF;
              cptx<=0;
              
            ELSIF phm='1' THEN
              -- Phase adjust
              IF ofp<5 THEN ofp:=5; END IF;
				  dif:=shift_right(mfrac,ofp + 3  + 1);
              IF (ofp>=18 OR off<16) AND fcpt=2 AND phcor=0 THEN
                phm<='0';
              END IF;
              IF phcor=0 THEN
                IF cptx=0 THEN
                  sign<=NOT lltune_sync(13);
                  sign_pre<=sign;
                  diff<=dif;
                  IF sign_pre/=NOT lltune_sync(13) THEN
                    diff<='0' & dif(31 DOWNTO 1);
                  END IF;
                END IF;
                cptx<=cptx+1;
                IF cptx=2 THEN
                  cptx<=0;
                  sign<=NOT sign;
                  phcor<=1;
                END IF;
                tstate<=sADJ;
              ELSIF phcor=1 THEN
                cptx<=cptx+1;
                IF cptx=2 THEN
                  cptx<=0;
                  phcor<=2;
                  tstate<=sADJ;
                END IF;
              ELSIF fcpt=2 THEN
                phcor<=0;
                cptx<=0;
              END IF;
            END IF;
          END IF;
          
        WHEN sADJ =>
          IF sign='0' THEN
            mfrac<=mfrac + diff(31 DOWNTO 8);
          ELSE
            mfrac<=mfrac - diff(31 DOWNTO 8);
          END IF;
          IF up='0' THEN
            up<='1';
            tstate<=sADJ2;
          END IF;
          
        WHEN sADJ2 =>
          cpt<=cpt+1;
          IF cpt=1023 THEN
            tstate<=sWAIT;
          ELSE
            tstate<=sADJ;
          END IF;
          
      END CASE;
      
      ------------------------------------------------------
      CASE state IS
        WHEN sIDLE =>
          pwrite<='0';
          IF up='1' THEN
            up<='0';
            state<=sW1;
            pdata<=mfrac;
            paddress<="000111";
            pwrite<='1';
          END IF;
          
        WHEN sW1 =>
          IF pwrite='1' AND o_waitrequest='0' THEN
            state<=sW2;
            pwrite<='0';
          END IF;
          
        WHEN sW2 =>
          pdata<=x"0000_0001";
          paddress<="000010";
          pwrite<='1';
          state<=sW3;
          
        WHEN sW3 =>
          IF pwrite='1' AND o_waitrequest='0' THEN
            pwrite<='0';
            state<=sIDLE;
          END IF;
      END CASE;

    END IF;
  END PROCESS Schmurtz;
  
  ----------------------------------------------------------------------------

  
END ARCHITECTURE rtl;


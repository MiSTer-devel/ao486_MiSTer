--------------------------------------------------------------------------------
-- AVALON SCALER
--------------------------------------------------------------------------------
-- TEMLIB 10/2018
--------------------------------------------------------------------------------
-- This code can be freely distributed and used for any purpose, but, if you
-- find any bug, or want to suggest an enhancement, you ought to send a mail
-- to info@temlib.org.
--------------------------------------------------------------------------------

-- Features :
--  - Arbitrary output video format
--  - Autodetect input image size or fixed window
--  - Progressive and interleaved frames
--  - Interpolation
--    Upscaling   : Nearest, Bilinear, Sharp Bilinear, Bicubic, Polyphase
--    Downscaling : Nearest, Bilinear
--  - Avalon bus interface with 128 or 64 bits DATA
--  - Optional triple buffering

--------------------------------------------
-- 4 asynchronous clock domains :
--  i_xxx    : Input video
--  o_xxx    : Output video
--  avl_xxx  : Avalon memory bus
--  poly_xxx : Polyphase filters memory

--------------------------------------------
-- Mode 24bits

--------------------------------------------
-- Image header. When HEADER = TRUE
-- Header Address = RAMBASE
-- Image Address  = RAMBASE + HEADER_SIZE

-- Header (Bytes. Big Endian.)
--  0    : Type = 1
--  1    : Pixel format
--         1 : 24 bits/pixel, packed RGB. Big Endian

--  3:2  : Header size : Offset to start of picture (= N_BURST)
--  5:4  : Attributes. TBD
--         b0 ; Interleaved
--         b1 : Field number
--         b2 : Horizontal downscaled
--         b3 : Vertical downscaled
--  7:6  : Image width. Pixels.
--  9:8  : Image height. Pixels.
-- 11:10 : Line length. Bytes.
-- 13:12 : TBD.
-- 15:14 : TBD.
--------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- MODE[2:0]
-- 000 : Nearest
-- 001 : Bilinear
-- 010 : Sharp Bilinear
-- 011 : Bicubic
-- 100 : Polyphase
-- 101 : TBD
-- 110 : TBD
-- 111 : TEST

-- MODE[3]
-- 0 : Direct. Single framebuffer.
-- 1 : Triple buffering

-- MODE[4]
-- 0 : Normal
-- 1 : Low Latency mode. Output vertical frequency locked on input signal.

-- MASK      : Enable / Disable selected interpoler
--             0:Nearest 1:Bilinear 2:SharpBilinear 3:Bicubic 4:Polyphase
-- RAMBASE   : RAM base address for framebuffer
-- RAMSIZE   : RAM allocated for one framebuffer (needs x3 if triple-buffering)
--             Must be a power of two
-- INTER     : True=Autodetect interleaved video False=Force progressive scan
-- HEADER    : True=Add image properties header
-- SYNCHRO   : True=Support synchronized mode False=Force disabled
-- DOWNSCALE : True=Support downscaling False=Downscaling disabled
-- FRAC      : Fractional bits, subpixel resolution
-- FORMAT    : TBD <TODO>
-- OHRES     : Max. output horizontal resolution. Must be a power of two.
--             (Used for sizing line buffers)
-- IHRES     : Max. input horizontal resolution. Must be a power of two.
--             (Used for sizing line buffers)
-- N_DW      : Avalon data bus width
-- N_AW      : Avalon address bus width
-- N_BURST   : Burst size in bytes. Power of two.

ENTITY ascal IS
  GENERIC (
    MASK      : unsigned(0 TO 7) :=x"FF";
    RAMBASE   : unsigned(31 DOWNTO 0);
    RAMSIZE   : unsigned(31 DOWNTO 0) := x"0080_0000"; -- =8MB
    INTER     : boolean := true;
    HEADER    : boolean := true;
    SYNCHRO   : boolean := true;
    DOWNSCALE : boolean := true;
    FRAC      : natural RANGE 4 TO 6 :=4;
    FORMAT    : natural RANGE 1 TO 8 :=1;
    OHRES     : natural RANGE 1 TO 2048 :=2048;
    IHRES     : natural RANGE 1 TO 2048 :=2048;
    N_DW      : natural RANGE 64 TO 128 := 128;
    N_AW      : natural RANGE 8 TO 32 := 32;
    N_BURST   : natural := 256 -- 256 bytes per burst
    );
  PORT (
    ------------------------------------
    -- Input video
    i_r   : IN  unsigned(7 DOWNTO 0);
    i_g   : IN  unsigned(7 DOWNTO 0);
    i_b   : IN  unsigned(7 DOWNTO 0);
    i_hs  : IN  std_logic; -- H sync
    i_vs  : IN  std_logic; -- V sync
    i_fl  : IN  std_logic; -- Interlaced field
    i_de  : IN  std_logic; -- Display Enable
    i_ce  : IN  std_logic; -- Clock Enable
    i_clk : IN  std_logic; -- Input clock
    
    ------------------------------------
    -- Output video
    o_r   : OUT unsigned(7 DOWNTO 0);
    o_g   : OUT unsigned(7 DOWNTO 0);
    o_b   : OUT unsigned(7 DOWNTO 0);
    o_hs  : OUT std_logic; -- H sync
    o_vs  : OUT std_logic; -- V sync
    o_de  : OUT std_logic; -- Display Enable
    o_ce  : IN  std_logic; -- Clock Enable
    o_clk : IN  std_logic; -- Output clock
    
    ------------------------------------
    -- Input video parameters
    iauto : IN std_logic; -- 1=Autodetect image size 0=Choose window
    himin : IN natural RANGE 0 TO 4095; -- MIN < MAX, MIN >=0, MAX < DISP
    himax : IN natural RANGE 0 TO 4095;
    vimin : IN natural RANGE 0 TO 4095;
    vimax : IN natural RANGE 0 TO 4095;
    
    -- Output video parameters
    run    : IN std_logic; -- 1=Enable output image. 0=No image
    freeze : IN std_logic; -- 1=Disable framebuffer writes
    mode   : IN unsigned(4 DOWNTO 0);
    -- SYNC  |________________________/"""""""""\______|
    -- DE    |""""""""""""""""""\______________________|
    -- RGB   |    <#IMAGE#>     ^HDISP                 |
    --            ^HMIN   ^HMAX       ^HSSTART  ^HSEND ^HTOTAL
    htotal  : IN natural RANGE 0 TO 4095;
    hsstart : IN natural RANGE 0 TO 4095;
    hsend   : IN natural RANGE 0 TO 4095;
    hdisp   : IN natural RANGE 0 TO 4095;
    hmin    : IN natural RANGE 0 TO 4095;
    hmax    : IN natural RANGE 0 TO 4095; -- 0 <= hmin < hmax < hdisp
    vtotal  : IN natural RANGE 0 TO 4095;
    vsstart : IN natural RANGE 0 TO 4095;
    vsend   : IN natural RANGE 0 TO 4095;
    vdisp   : IN natural RANGE 0 TO 4095;
    vmin    : IN natural RANGE 0 TO 4095;
    vmax    : IN natural RANGE 0 TO 4095; -- 0 <= vmin < vmax < vdisp
    
    ------------------------------------
    -- Polyphase filter coefficients
    poly_clk : IN std_logic;
    poly_dw  : IN unsigned(8 DOWNTO 0);
    poly_a   : IN unsigned(FRAC+2 DOWNTO 0);
    poly_wr  : IN std_logic;
    -- Order :
    --   [Horizontal] [Vertical]
    --   [0]...[2**FRAC-1]
    --   [-1][0][1][2]
    
    ------------------------------------
    -- Avalon
    avl_clk            : IN    std_logic; -- Avalon clock
    avl_waitrequest    : IN    std_logic;
    avl_readdata       : IN    std_logic_vector(N_DW-1 DOWNTO 0);
    avl_readdatavalid  : IN    std_logic;
    avl_burstcount     : OUT   std_logic_vector(7 DOWNTO 0);
    avl_writedata      : OUT   std_logic_vector(N_DW-1 DOWNTO 0);
    avl_address        : OUT   std_logic_vector(N_AW-1 DOWNTO 0);
    avl_write          : OUT   std_logic;
    avl_read           : OUT   std_logic;
    avl_byteenable     : OUT   std_logic_vector(N_DW/8-1 DOWNTO 0);

    ------------------------------------
    reset_na           : IN    std_logic
    );

BEGIN
  ASSERT N_DW=64 OR N_DW=128 REPORT "DW" SEVERITY failure;
  
END ENTITY ascal;

--##############################################################################

ARCHITECTURE rtl OF ascal IS
  
  CONSTANT MASK_NEAREST        : natural :=0;
  CONSTANT MASK_BILINEAR       : natural :=1;
  CONSTANT MASK_SHARP_BILINEAR : natural :=2;
  CONSTANT MASK_BICUBIC        : natural :=3;
  CONSTANT MASK_POLY           : natural :=4;
  
  ----------------------------------------------------------
  FUNCTION ilog2 (CONSTANT v : natural) RETURN natural IS
    VARIABLE r : natural := 1;
    VARIABLE n : natural := 0;
  BEGIN
    WHILE v>r LOOP
      n:=n+1;
      r:=r*2;
    END LOOP;
    RETURN n;
  END FUNCTION ilog2;
  FUNCTION to_std_logic (a : boolean) RETURN std_logic IS
  BEGIN
    IF a THEN RETURN '1';
         ELSE RETURN '0';
    END IF;
  END FUNCTION to_std_logic;
  
  ----------------------------------------------------------
  CONSTANT NB_BURST : natural :=ilog2(N_BURST);
  CONSTANT NB_LA : natural :=ilog2(N_DW/8); -- Low address bits
  CONSTANT BLEN : natural :=N_BURST / N_DW * 8; -- Burst length
  CONSTANT NP : natural :=24;

  ----------------------------------------------------------
  TYPE arr_dw IS  ARRAY (natural RANGE <>) OF unsigned(N_DW-1 DOWNTO 0);
  
  TYPE type_pix IS RECORD
    r,g,b : unsigned(7 DOWNTO 0); -- 0.8
  END RECORD;
  TYPE arr_pix IS ARRAY (natural RANGE <>) OF type_pix;
  ATTRIBUTE ramstyle : string;

  SUBTYPE uint12 IS natural RANGE 0 TO 4095;
  
  ----------------------------------------------------------
  -- Input image
  SIGNAL i_freeze : std_logic;
  SIGNAL i_hsize,i_hmin,i_hmax,i_hcpt : uint12;
  SIGNAL i_hrsize,i_vrsize : uint12;
  SIGNAL i_himax,i_vimax : uint12;
  SIGNAL i_vsize,i_vmin,i_vmax,i_vimaxc,i_vcpt : uint12;
  SIGNAL i_iauto : std_logic;
  SIGNAL i_mode : unsigned(4 DOWNTO 0);
  SIGNAL i_ven,i_sof : std_logic;
  SIGNAL i_wr : std_logic;
  SIGNAL i_de_pre,i_hs_pre,i_vs_pre,i_fl_pre : std_logic;
  SIGNAL i_hs_delay : natural RANGE 0 TO 15;
  SIGNAL i_intercnt : natural RANGE 0 TO 7;
  SIGNAL i_inter,i_flm : std_logic;
  SIGNAL i_write,i_write_pre,i_walt : std_logic;
  SIGNAL i_push,i_pushend,i_pushend2,i_eol,i_eol2,i_eol3,i_eol4 : std_logic;
  SIGNAL i_pushhead,i_hbfix : std_logic;
  SIGNAL i_hburst,i_hbcpt : natural RANGE 0 TO 31;
  SIGNAL i_shift : unsigned(0 TO 119) := (OTHERS =>'0');
  SIGNAL i_head : unsigned(127 DOWNTO 0);
  SIGNAL i_acpt : natural RANGE 0 TO 15;
  SIGNAL i_dpram : arr_dw(0 TO BLEN*2-1);
  ATTRIBUTE ramstyle OF i_dpram : SIGNAL IS "no_rw_check";
  SIGNAL i_endframe,i_syncline : std_logic;
  SIGNAL i_wad : natural RANGE  0 TO BLEN*2-1;
  SIGNAL i_dw : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL i_adrs,i_adrsi : unsigned(31 DOWNTO 0); -- Avalon address
  SIGNAL i_reset_na : std_logic;
  SIGNAL i_hnp,i_vnp : std_logic;
  SIGNAL i_line : arr_pix(0 TO IHRES-1); -- Downscale line buffer
  ATTRIBUTE ramstyle OF i_line : SIGNAL IS "no_rw_check";
  SIGNAL i_ohsize,i_ovsize : uint12;
  SIGNAL i_hdivi,i_vdivi   : unsigned(11 DOWNTO 0);
  SIGNAL i_hdivr,i_vdivr   : unsigned(23 DOWNTO 0);
  SIGNAL i_hdiv,i_v_frac   : unsigned(11 DOWNTO 0);
  SIGNAL i_hacc,i_vacc     : uint12;
  SIGNAL i_hdown,i_vdown   : std_logic;
  SIGNAL i_divcpt : natural RANGE 0 TO 36;
  SIGNAL i_divstart : std_logic;
  SIGNAL i_divrun : std_logic;
  SIGNAL i_lwad,i_lrad : natural RANGE 0 TO OHRES-1;
  SIGNAL i_lwr : std_logic;
  SIGNAL i_lpush,i_bil : std_logic;
  SIGNAL i_ldw,i_ldrm : type_pix;
  SIGNAL i_h_frac2,i_h_fracn2 : unsigned(FRAC DOWNTO 0);
  SIGNAL i_v_frac2,i_v_fracn2 : unsigned(FRAC DOWNTO 0);
  SIGNAL i_hpixp,i_hpix0,i_hpix1,i_hpix2 : type_pix;
  SIGNAL i_hpix,i_pix : type_pix;
  SIGNAL i_hnp1,i_hnp2,i_hnp3,i_hnp4 : std_logic;
  SIGNAL i_ven1,i_ven2,i_ven3,i_ven4,i_ven5 : std_logic;

  SIGNAL i_htotal,i_hsstart,i_hsend : uint12;
  SIGNAL i_vtotal,i_vsstart,i_vsend : uint12;
  
  ----------------------------------------------------------
  -- Avalon
  TYPE type_avl_state IS (sIDLE,sWRITE,sREAD);
  SIGNAL avl_state : type_avl_state;
  SIGNAL avl_mode : unsigned(4 DOWNTO 0);
  SIGNAL avl_write_i,avl_write_sync,avl_write_sync2 : std_logic;
  SIGNAL avl_read_i,avl_read_sync,avl_read_sync2 : std_logic;
  SIGNAL avl_read_pulse,avl_write_pulse : std_logic;
  SIGNAL avl_reading : std_logic;
  SIGNAL avl_read_sr,avl_write_sr,avl_read_clr,avl_write_clr : std_logic;
  SIGNAL avl_rad,avl_rad_c,avl_wad : natural RANGE 0 TO 2*BLEN-1;
  SIGNAL avl_walt : std_logic;
  SIGNAL avl_dw,avl_dr : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL avl_wr : std_logic;
  SIGNAL avl_readack : std_logic;
  SIGNAL avl_radrs,avl_wadrs : unsigned(31 DOWNTO 0);
  SIGNAL avl_rbib : std_logic;
  SIGNAL avl_i_offset,avl_o_offset : unsigned(31 DOWNTO 0);
  SIGNAL avl_reset_na : std_logic;
  SIGNAL avl_o_vs_sync,avl_o_vs : std_logic;
  
  FUNCTION buf_next(a,b : natural RANGE 0 TO 2) RETURN natural IS
  BEGIN
    IF (a=0 AND b=1) OR (a=1 AND b=0) THEN RETURN 2; END IF;
    IF (a=1 AND b=2) OR (a=2 AND b=1) THEN RETURN 0; END IF;
    RETURN 1;                              
  END FUNCTION;
  FUNCTION buf_offset(b : natural RANGE 0 TO 2) RETURN unsigned IS
  BEGIN
    IF b=1 THEN RETURN RAMSIZE; END IF;
    IF b=2 THEN RETURN RAMSIZE(30 DOWNTO 0) & '0'; END IF;
    RETURN x"00000000"; 
  END FUNCTION;
  
  ----------------------------------------------------------
  -- Output
  SIGNAL o_run : std_logic;
  SIGNAL o_mode,o_hmode,o_vmode : unsigned(4 DOWNTO 0);
  SIGNAL o_htotal,o_hsstart,o_hsend : uint12;
  SIGNAL o_hmin,o_hmax,o_hdisp : uint12;
  SIGNAL o_hsize,o_vsize : uint12;
  SIGNAL o_vtotal,o_vsstart,o_vsend : uint12;
  SIGNAL o_vmin,o_vmax,o_vdisp : uint12;
  SIGNAL o_divcpt : natural RANGE 0 TO 36;
  SIGNAL o_divstart : std_logic;
  SIGNAL o_divrun : std_logic;
  SIGNAL o_iendframe,o_iendframe2,o_bufup : std_logic;
  SIGNAL o_ibuf,o_obuf : natural RANGE 0 TO 2;
  TYPE type_o_state IS (sDISP,sHSYNC,sREAD,sWAITREAD);
  SIGNAL o_state : type_o_state;
  SIGNAL o_copy,o_readack,o_readack_sync,o_readack_sync2 : std_logic;
  SIGNAL o_copyw,o_copy1,o_copy2,o_copy3,o_copy4,o_copy5,o_copy6 : std_logic;
  SIGNAL o_adrs : unsigned(31 DOWNTO 0); -- Avalon address
  SIGNAL o_adrs_pre : natural RANGE 0 TO 32*4096-1;
  SIGNAL o_ad : natural RANGE 0 TO 2*BLEN-1;
  SIGNAL o_adturn : std_logic;
  SIGNAL o_dr : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL o_shift : unsigned(0 TO N_DW+15);
  SIGNAL o_sh : std_logic;
  SIGNAL o_reset_na : std_logic;
  SIGNAL o_dpram : arr_dw(0 TO BLEN*2-1);
  ATTRIBUTE ramstyle OF o_dpram : SIGNAL IS "no_rw_check";
  SIGNAL o_line0,o_line1,o_line2,o_line3 : arr_pix(0 TO OHRES-1);
  ATTRIBUTE ramstyle OF o_line0 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line1 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line2 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line3 : SIGNAL IS "no_rw_check";
  SIGNAL o_wadl,o_radl : natural RANGE 0 TO OHRES-1;
  SIGNAL o_ldw,o_ldr0,o_ldr1,o_ldr2,o_ldr3 : type_pix;
  SIGNAL o_wr : unsigned(3 DOWNTO 0);
  SIGNAL o_hcpt,o_vcpt,o_vcpt_pre,o_vcpt_pre2,o_vcpt_pre3 : uint12;
  SIGNAL o_hdelta,o_vdelta : unsigned(23 DOWNTO 0);
  SIGNAL o_ihsize,o_ivsize : uint12;
  SIGNAL o_hdivi,o_vdivi   : unsigned(11 DOWNTO 0);
  SIGNAL o_hdivr,o_vdivr   : unsigned(35 DOWNTO 0);

--pragma synthesis_off
  SIGNAL xxx_o_hpos,xxx_o_vpos : real;
--pragma synthesis_on
  
  SIGNAL o_hpos,o_hpos_next : unsigned(23 DOWNTO 0);
  SIGNAL o_vpos,o_vpos_next : unsigned(23 DOWNTO 0); -- [23:12].[11.0]
  SIGNAL o_hpos1,o_hpos2,o_hpos3,o_hpos4,o_hpos5 : unsigned(23 DOWNTO 0);
  SIGNAL o_hacc,o_vacc : uint12;
  SIGNAL xxx_vposi : uint12;
  SIGNAL o_hsp,o_hs0,o_hs1,o_hs2,o_hs3,o_hs4,o_hs5 : std_logic;
  SIGNAL o_vs0,o_vs1,o_vs2,o_vs3,o_vs4,o_vs5 : std_logic;
  SIGNAL o_de0,o_de1,o_de2,o_de3,o_de4,o_de5 : std_logic;
  SIGNAL o_pe0,o_pe1,o_pe2,o_pe3,o_pe4,o_pe5 : std_logic;
  SIGNAL o_read,o_read_pre : std_logic;
  SIGNAL o_readlev,o_copylev : natural RANGE 0 TO 2;
  SIGNAL o_hburst,o_hbcpt : natural RANGE 0 TO 31;
  SIGNAL o_fload : natural RANGE 0 TO 3;
  SIGNAL o_acpt,o_acpt1 : natural RANGE 0 TO 15; -- Alternance pixels FIFO
  SIGNAL o_dshi : natural RANGE 0 TO 3;
  SIGNAL o_first,o_last,o_last1,o_last2 : std_logic;
  SIGNAL o_alt : unsigned(3 DOWNTO 0);
  SIGNAL o_hdown,o_vdown : std_logic;
  SIGNAL o_primv,o_lastv ,o_bibv : unsigned(0 TO 2);
  SIGNAL o_bibu,o_bib : std_logic :='0';
  SIGNAL o_dcpt,o_dcpt1,o_dcpt2,o_dcpt3,o_dcpt4,o_dcpt5,o_dcpt6 : uint12;
  SIGNAL o_hpix0,o_hpix1,o_hpix2,o_hpix3 : type_pix;
  SIGNAL o_hpix01,o_hpix11,o_hpix21,o_hpix31 : type_pix;
  SIGNAL o_hpix02,o_hpix12,o_hpix22,o_hpix32 : type_pix;
  SIGNAL o_hpix03,o_hpix13,o_hpix23,o_hpix33 : type_pix;
  SIGNAL o_hpix14,o_hpix24 : type_pix;

  SIGNAL o_vpixm2,o_vpix02,o_vpix12,o_vpix22 : type_pix;
  SIGNAL o_vpixm3,o_vpix03,o_vpix13,o_vpix23 : type_pix;
  SIGNAL o_vpix04,o_vpix14,o_vpix05,o_vpix15 : type_pix;

  SIGNAL o_isyncline,o_isyncline2 : std_logic;
  SIGNAL o_dosync,o_msync,o_msync2,o_syncpend : std_logic;
  SIGNAL o_vpe : std_logic;
  SIGNAL o_div : unsigned(11 DOWNTO 0); --uint12;
  SIGNAL o_dir : unsigned(11 DOWNTO 0);
  SIGNAL o_vdivi2 : unsigned(11 DOWNTO 0);
  SIGNAL o_vdivr2 : unsigned(23 DOWNTO 0);
  SIGNAL o_vpos_lob   : unsigned(11 DOWNTO 0);
  SIGNAL o_vpos_b,o_vpos_a : unsigned(23 DOWNTO 0);
  SIGNAL o_divcpt2 : natural RANGE 0 TO 36;
  SIGNAL o_divstart2 : std_logic;
  SIGNAL o_divrun2 : std_logic;
  SIGNAL o_hacpt,o_hacpt1,o_vacpt : unsigned(11 DOWNTO 0);
  SIGNAL o_phacc : boolean := false; -- <TEST> False=Delta True=Phase acc.

  -----------------------------------------------------------------------------
  -- ACPT 012345678901234---  128bits DATA
  --  0   ...............RGB
  --  1   ............RGBrgb
  --  2   .........RGBrgbRGB
  --  3   ......RGBrgbRGBrgb
  --  4   ...RGBrgbRGBrgbRGB
  --  5   RGBrgbRGBrgbRGBrgb => PUSH RGBrgbRGBrgbRGBr
  --  6   .............gbRGB
  --  7   ..........gbRGBrgb
  --  8   .......gbRGBrgbRGB
  --  9   ....gbRGBrgbRGBrgb
  -- 10   .gbRGBrgbRGBrgbRGB => PUSH gbRGBrgbRGBrgbRG
  -- 11   ..............Brgb
  -- 12   ...........BrgbRGB
  -- 13   ........BrgbRGBrgb
  -- 14   .....BrgbRGBrgbRGB
  -- 15   ..BrgbRGBrgbRGBrgb => PUSH BrgbRGBrgbRGBrgb
  
  -- ACPT 012345678901234---  64bits DATA
  --  0   ...............RGB
  --  1   ............RGBrgb
  --  2   .........RGBrgbRGB => PUSH RGBrgbRG
  --  3   ..............Brgb
  --  4   ...........BrgbRGB
  --  5   ........BrgbRGBrgb => PUSH BrgbRGBr
  --  6   .............gbRGB
  --- 7   ..........gbRGBrgb => PUSH gbRGBrgb
  
  FUNCTION shift24_ipack(i_dw : unsigned(N_DW-1 DOWNTO 0);
                         acpt : natural RANGE 0 TO 15;
                         shift : unsigned(0 TO 119);
                         pix : type_pix) RETURN unsigned IS
    VARIABLE dw : unsigned(N_DW-1 DOWNTO 0);
  BEGIN
    IF N_DW=128 THEN
      IF    acpt=5 THEN   dw:=shift(0 TO 119) & pix.r;
      ELSIF acpt=10 THEN  dw:=shift(8 TO 119) & pix.r & pix.g;
      ELSIF acpt=15 THEN  dw:=shift(16 TO 119) & pix.r & pix.g & pix.b;
      ELSE                dw:=i_dw;
      END IF;
    ELSE -- N_DW=64
      IF    (acpt MOD 8)=2 THEN  dw:=shift(72 TO 119) & pix.r & pix.g;
      ELSIF (acpt MOD 8)=5 THEN  dw:=shift(64 TO 119) & pix.r;
      ELSIF (acpt MOD 8)=7 THEN  dw:=shift(80 TO 119) & pix.r & pix.g & pix.b;
      ELSE                       dw:=i_dw;
      END IF;
    END IF;
    RETURN dw;
  END FUNCTION;
  
  FUNCTION shift24_inext (acpt : natural RANGE 0 TO 15) RETURN boolean IS
  BEGIN
    IF N_DW=128 THEN
      RETURN (acpt=5 OR acpt=10 OR acpt=15);
    ELSE -- N_DW=64
      RETURN ((acpt MOD 8)=2 OR (acpt MOD 8)=5 OR (acpt MOD 8)=7);
    END IF;
  END FUNCTION;
  
  ----------------------
  -- ACPT 0123456789012345   128bits DATA
  --  0  >RGBrgbRGBrgbRGBr
  --  1   rgbRGBrgbRGBr
  --  2   RGBrgbRGBr
  --  3   rgbRGBr
  --  4   RGBr
  --  5  >r gbRGBrgbRGBrgbRG
  --  6   RGBrgbRGBrgbRG
  --  7   rgbRGBrgbRG
  --  8   RGBrgbRG
  --  9   rgbRG
  --  10 >RG BrgbRGBrgbRGBrgb
  --  11  rgbRGBrgbRGBrgb
  --  12  RGBrgbRGBrgb
  --  13  rgbRGBrgb
  --  14  RGBrgb
  --  15  rgb

  -- ACPT 01234567   64bits DATA
  --  0  >RGBrgbRG
  --  1   rgbRG
  --  2  >RG BrgbRGBr
  --  3   rgbRGBr
  --  4   RGBr
  --  5  >r gbRGBrgb
  --  6   RGBrgb
  --  7   rgb
  
  FUNCTION shift24_opack(acpt : natural RANGE 0 TO 15;
                         shift : unsigned(0 TO N_DW+15);
                         dr : unsigned(N_DW-1 DOWNTO 0)) RETURN unsigned IS
    VARIABLE shift_v : unsigned(0 TO N_DW+15);
  BEGIN
    IF N_DW=128 THEN
      IF acpt=0 THEN
        shift_v:=dr & dr(15 DOWNTO 0);
      ELSIF acpt=5 THEN
        shift_v:=shift(24 TO 31) & dr & dr(7 DOWNTO 0);
      ELSIF acpt=10 THEN
        shift_v:=shift(24 TO 39) & dr;
      ELSE
        shift_v:=shift(24 TO N_DW+15) & dr(23 DOWNTO 0);
      END IF;
    ELSE -- N_DW=64
      IF (acpt MOD 8)=0 THEN
        shift_v:=dr & dr(15 DOWNTO 0);
      ELSIF (acpt MOD 8)=2 THEN
        shift_v:=shift(24 TO 39) & dr;
      ELSIF (acpt MOD 8)=5 THEN
        shift_v:=shift(24 TO 31) & dr & dr(7 DOWNTO 0);
      ELSE
        shift_v:=shift(24 TO N_DW+15) & dr(23 DOWNTO 0);
      END IF;
    END IF;
    RETURN shift_v;
  END FUNCTION;
  
  FUNCTION shift24_onext (acpt : natural RANGE 0 TO 15) RETURN boolean IS
  BEGIN
    IF N_DW=128 THEN
      RETURN (acpt=0 OR acpt=5 OR acpt=10);
    ELSE -- N_DW=64
      RETURN ((acpt MOD 8)=0 OR (acpt MOD 8)=2 OR (acpt MOD 8)=5);
    END IF;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  FUNCTION altx (a : unsigned(1 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    CASE a IS
      WHEN "00"   => RETURN "0001";
      WHEN "01"   => RETURN "0010";
      WHEN "10"   => RETURN "0100";
      WHEN OTHERS => RETURN "1000";
    END CASE;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  FUNCTION bound(a : unsigned;
                 s : natural) RETURN unsigned IS
  BEGIN
    IF a(a'left)='1' THEN
      RETURN x"00";
    ELSIF a(a'left DOWNTO s)/=0 THEN
      RETURN x"FF";
    ELSE
      RETURN a(s-1 DOWNTO s-8);
    END IF;
  END FUNCTION bound;
  
  -----------------------------------------------------------------------------
  -- Nearest
  FUNCTION near_frac(f : unsigned) RETURN unsigned IS
    VARIABLE x : unsigned(FRAC-1 DOWNTO 0);
  BEGIN
    x:=(OTHERS =>f(f'left));
    RETURN x;
  END FUNCTION;
  
  SIGNAL o_h_frac2,o_v_frac : unsigned(FRAC-1 DOWNTO 0);
  SIGNAL o_h_frac3,o_h_fracn3,o_v_frac2,o_v_fracn2 : unsigned(FRAC DOWNTO 0);
  SIGNAL o_h_bil_pix,o_v_bil_pix : type_pix;
  
  -----------------------------------------------------------------------------
  -- Nearest + Bilinear + Sharp Bilinear
  FUNCTION bil_frac(f : unsigned) RETURN unsigned IS
  BEGIN
    RETURN f(f'left DOWNTO f'left+1-FRAC);
  END FUNCTION;
  
  FUNCTION bil_calc(f :unsigned(FRAC DOWNTO 0);
                    g :unsigned(FRAC DOWNTO 0);
                    p0,p1 : type_pix) RETURN type_pix IS
    VARIABLE u : unsigned(8+FRAC DOWNTO 0);
    VARIABLE x : type_pix;
    CONSTANT Z : unsigned(FRAC-1 DOWNTO 0):=(OTHERS =>'0');
  BEGIN
    u:=p1.r * f + p0.r * g;
    x.r:=bound(u,8+FRAC);
    u:=p1.g * f + p0.g * g;
    x.g:=bound(u,8+FRAC);
    u:=p1.b * f + p0.b * g;
    x.b:=bound(u,8+FRAC);
    RETURN x;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  -- Sharp Bilinear
  --  <0.5 : x*x*x*4
  --  >0.5 : 1 - (1-x)*(1-x)*(1-x)*4
  
  TYPE type_sbil_tt IS RECORD
    f : unsigned(FRAC-1 DOWNTO 0);
    s : unsigned(FRAC-1 DOWNTO 0);
  END RECORD;
  
  SIGNAL o_h_sbil_t,o_v_sbil_t : type_sbil_tt;
  
  FUNCTION sbil_frac1(f : unsigned(11 DOWNTO 0)) RETURN type_sbil_tt IS
    VARIABLE u : unsigned(FRAC-1 DOWNTO 0);
    VARIABLE v : unsigned(2*FRAC-1 DOWNTO 0);
    VARIABLE x : type_sbil_tt;
  BEGIN
    IF f(11)='0' THEN
      u:=f(11 DOWNTO 12-FRAC);
    ELSE
      u:=NOT f(11 DOWNTO 12-FRAC);
    END IF;
    v:=u*u;
    x.f:=u;
    x.s:=v(2*FRAC-2 DOWNTO FRAC-1);
    RETURN x;  
  END FUNCTION;
  
  FUNCTION sbil_frac2(f : unsigned(11 DOWNTO 0);
                      t : type_sbil_tt) RETURN unsigned IS
    VARIABLE v : unsigned(2*FRAC-1 DOWNTO 0);
  BEGIN
    v:=t.f*t.s;
    IF f(11)='0' THEN
      RETURN v(2*FRAC-2 DOWNTO FRAC-1);
    ELSE
      RETURN NOT v(2*FRAC-2 DOWNTO FRAC-1);
    END IF;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  -- Bicubic
  TYPE type_bic_abcd IS RECORD
    a  : unsigned(7 DOWNTO 0);  --  0.8
    b  : signed(8 DOWNTO 0);  --  0.9
    c  : signed(11 DOWNTO 0); -- 3.9
    d  : signed(10 DOWNTO 0); -- 2.9
    xx : signed(8 DOWNTO 0); -- X.X 1.8
  END RECORD;
  TYPE type_bic_pix_abcd IS RECORD
    r,g,b : type_bic_abcd;
  END RECORD;
  TYPE type_bic_tt1 IS RECORD -- Intermediate result
    r_bx,g_bx,b_bx    : signed(8 DOWNTO 0);  -- B.X 1.8
    r_cxx,g_cxx,b_cxx : signed(11 DOWNTO 0); -- C.XX 3.9
    r_dxx,g_dxx,b_dxx : signed(10 DOWNTO 0); -- D.XX 2.9
  END RECORD;
  TYPE type_bic_tt2 IS RECORD -- Intermediate result
    r_abxcxx,g_abxcxx,b_abxcxx : signed(9 DOWNTO 0); --  A + B.X + C.XX 2.8
    r_dxxx,g_dxxx,b_dxxx : signed(9 DOWNTO 0); -- D.X.X.X 2.8
  END RECORD;
  
  ----------------------------------------------------------
  -- Y = A + B.X + C.X.X + D.X.X.X = A + X.(B + X.(C + X.D))
  -- A = Y(0)                                       0 .. 1    unsigned
  -- B = Y(1)/2 - Y(-1)/2                        -1/2 .. +1/2 signed
  -- C = Y(-1) - 5*Y(0)/2 + 2*Y(1) - Y(2)/2        -3 .. +3   signed
  -- D = -Y(-1)/2 + 3*Y(0)/2 - 3*Y(1)/2 + Y(2)/2   -2 .. +2   signed
  
  FUNCTION bic_calc0(f : unsigned(11 DOWNTO 0);
                     pm,p0,p1,p2 : unsigned(7 DOWNTO 0)) RETURN type_bic_abcd IS
    VARIABLE xx : signed(2*FRAC+1 DOWNTO 0); -- 2.(2*FRAC)
  BEGIN
    xx := signed('0' & f(11 DOWNTO 12-FRAC)) *
          signed('0' & f(11 DOWNTO 12-FRAC)); -- 2.(2*FRAC)
    RETURN type_bic_abcd'(
      a=>p0,-- 0.8
      b=>signed(('0' & p1) - ('0' & pm)), -- 0.9
      c=>signed(("000" & pm & '0') - ("00" & p0 & "00") - ("0000" & p0) +
                ("00" & p1 & "00") - ("0000" & p2)), -- 3.9
      d=>signed(("00" & p0 & '0') - ("00" & p1 & '0') - ("000" & p1) +
                ("000" & p0) + ("000" & p2) - ("000" & pm)), -- 2.9
      xx=>xx(2*FRAC DOWNTO 2*FRAC-8)); -- 1.8
  END FUNCTION;
  FUNCTION bic_calc0(f    : unsigned(11 DOWNTO 0);
                     pm,p0,p1,p2 : type_pix) RETURN type_bic_pix_abcd IS
  BEGIN
    RETURN type_bic_pix_abcd'(r=>bic_calc0(f,pm.r,p0.r,p1.r,p2.r),
                              g=>bic_calc0(f,pm.g,p0.g,p1.g,p2.g),
                              b=>bic_calc0(f,pm.b,p0.b,p1.b,p2.b));
  END FUNCTION;
  
  ----------------------------------------------------------
  -- Calc : B.X, C.XX, D.XX
  FUNCTION bic_calc1(f    : unsigned(11 DOWNTO 0);
                     abcd : type_bic_pix_abcd) RETURN type_bic_tt1 IS
    VARIABLE t : type_bic_tt1;
    VARIABLE bx : signed(9+FRAC DOWNTO 0); -- 1.(FRAC+9)
    VARIABLE cxx : signed(20 DOWNTO 0); -- 4.17
    VARIABLE dxx : signed(19 DOWNTO 0); -- 3.17
  BEGIN
    bx := abcd.r.b * signed('0' & f(11 DOWNTO 12-FRAC)); -- 1.(FRAC+9)
    t.r_bx:=bx(9+FRAC DOWNTO 9+FRAC-8); -- 1.8
    cxx:= abcd.r.c * abcd.r.xx; -- 3.9 * 1.8 = 4.17
    t.r_cxx:=cxx(19 DOWNTO 8); -- 3.9
    dxx:= abcd.r.d * abcd.r.xx; -- 2.9 * 1.8 = 3.17
    t.r_dxx:=dxx(18 DOWNTO 8); -- 2.9
    bx := abcd.g.b * signed('0' & f(11 DOWNTO 12-FRAC)); -- 1.(FRAC+9)
    t.g_bx:=bx(9+FRAC DOWNTO 9+FRAC-8); -- 1.8
    cxx:= abcd.g.c * abcd.g.xx; -- 3.9 * 1.8 = 4.17
    t.g_cxx:=cxx(19 DOWNTO 8); -- 3.9
    dxx:= abcd.g.d * abcd.g.xx; -- 2.9 * 1.8 = 3.17
    t.g_dxx:=dxx(18 DOWNTO 8); -- 2.9
    bx := abcd.b.b * signed('0' & f(11 DOWNTO 12-FRAC)); -- 1.(FRAC+9)
    t.b_bx:=bx(9+FRAC DOWNTO 9+FRAC-8); -- 1.8
    cxx:= abcd.b.c * abcd.b.xx; -- 3.9 * 1.8 = 4.17
    t.b_cxx:=cxx(19 DOWNTO 8); -- 3.9
    dxx:= abcd.b.d * abcd.b.xx; -- 2.9 * 1.8 = 3.17
    t.b_dxx:=dxx(18 DOWNTO 8); -- 2.9
    RETURN t;
  END FUNCTION;
  
  ----------------------------------------------------------
  -- Calc A + BX + CXX , X.DXX
  FUNCTION bic_calc2(f    : unsigned(11 DOWNTO 0);
                     t    : type_bic_tt1;
                     abcd : type_bic_pix_abcd) RETURN type_bic_tt2 IS
    VARIABLE u : type_bic_tt2;
    VARIABLE x : signed(11+FRAC DOWNTO 0); -- 3.(9+FRAC)
  BEGIN
    u.r_abxcxx:=(t.r_bx(8) & t.r_bx) + ("00" & signed(abcd.r.a)) + t.r_cxx(10 DOWNTO 1); -- 2.8
    u.g_abxcxx:=(t.g_bx(8) & t.g_bx) + ("00" & signed(abcd.g.a)) + t.g_cxx(10 DOWNTO 1); -- 2.8
    u.b_abxcxx:=(t.b_bx(8) & t.b_bx) + ("00" & signed(abcd.b.a)) + t.b_cxx(10 DOWNTO 1); -- 2.8

    x:=t.r_dxx *  signed('0' & f(11 DOWNTO 12-FRAC)); --2.9 * 1.FRAC =3.(9+FRAC)
    u.r_dxxx:=x(10+FRAC DOWNTO 9+FRAC-8); -- 2.8
    x:=t.g_dxx *  signed('0' & f(11 DOWNTO 12-FRAC)); --2.9 * 1.FRAC =3.(9+FRAC)
    u.g_dxxx:=x(10+FRAC DOWNTO 9+FRAC-8); -- 2.8
    x:=t.b_dxx *  signed('0' & f(11 DOWNTO 12-FRAC)); --2.9 * 1.FRAC =3.(9+FRAC)
    u.b_dxxx:=x(10+FRAC DOWNTO 9+FRAC-8); -- 2.8
    RETURN u;
  END FUNCTION;
  
  ----------------------------------------------------------
  -- Calc  (A + BX + CXX) + (DXXX)
  FUNCTION bic_calc3(f    : unsigned(11 DOWNTO 0);
                     t    : type_bic_tt2;
                     abcd : type_bic_pix_abcd) RETURN type_pix IS
    VARIABLE x : type_pix;
    VARIABLE v : signed(9 DOWNTO 0); -- 2.8
  BEGIN
    v:=t.r_abxcxx + t.r_dxxx;
    x.r:=bound(unsigned(v),8);
    v:=t.g_abxcxx + t.g_dxxx;
    x.g:=bound(unsigned(v),8);
    v:=t.b_abxcxx + t.b_dxxx;
    x.b:=bound(unsigned(v),8);
    RETURN x;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  SIGNAL o_h_bic_pix,o_v_bic_pix : type_pix;
  SIGNAL o_h_bic_abcd,o_h_bic_abcd1,o_h_bic_abcd2 : type_bic_pix_abcd;
  SIGNAL o_v_bic_abcd,o_v_bic_abcd1,o_v_bic_abcd2 : type_bic_pix_abcd;
  SIGNAL o_h_bic_tt1,o_v_bic_tt1 : type_bic_tt1;
  SIGNAL o_h_bic_tt2,o_v_bic_tt2 : type_bic_tt2;
  
  -----------------------------------------------------------------------------
  -- Polyphase
  
  TYPE arr_uv36 IS ARRAY (natural RANGE <>) OF unsigned(35 DOWNTO 0); -- 9/9/9/9
  TYPE arr_integer IS ARRAY (natural RANGE <>) OF integer;
  CONSTANT POLY16 : arr_integer := (
    -24,-20,-16,-11,-6,-1,2,5,6,6,5,4,2,1,0,0,
    176,174,169,160,147,129,109,84,58,22,3,-12,-20,-25,-26,-25,
    -24,-26,-26,-23,-16,-4,11,32,58,96,119,140,154,165,172,175,
    0,0,1,2,3,4,6,7,6,4,1,-4,-8,-13,-18,-22);
  
  CONSTANT POLY32 : arr_integer := (
    -24,-22,-20,-18,-16,-13,-11,-8,-6,-3,-1,0,2,3,5,5,6,6,6,5,5,4,4,3,2,1,1,0,0,0,0,0,
    176,175,174,172,169,164,160,153,147,138,129,119,109,96,84,71,58,40,22,12,3,-4,-12,-16,-20,-22,-25,-25,-26,-25,-25,-25,
    -24,-25,-26,-26,-26,-24,-23,-19,-16,-10,-4,4,11,22,32,45,58,77,96,108,119,129,140,147,154,159,165,168,172,173,175,175,
    0,0,0,0,1,1,2,2,3,3,4,5,6,7,7,7,6,5,4,3,1,-1,-4,-6,-8,-10,-13,-15,-18,-20,-22,-22);
  
  FUNCTION init_poly RETURN arr_uv36 IS
    VARIABLE m : arr_uv36(0 TO 2**FRAC-1) :=(OTHERS =>x"000000000");
  BEGIN
    IF FRAC=4 THEN
      FOR i IN 0 TO 15 LOOP
        m(i):=unsigned(to_signed(POLY16(i),9)    & to_signed(POLY16(i+16),9) &
                       to_signed(POLY16(i+32),9) & to_signed(POLY16(i+48),9));
      END LOOP;
    ELSIF FRAC=5 THEN
      FOR i IN 0 TO 31 LOOP
        m(i):=unsigned(to_signed(POLY32(i),9)    & to_signed(POLY32(i+32),9) &
                       to_signed(POLY32(i+64),9) & to_signed(POLY32(i+96),9));
      END LOOP;
    END IF;
    RETURN m;
  END FUNCTION;
  
  SIGNAL o_h_poly : arr_uv36(0 TO 2**FRAC-1):=init_poly;
  SIGNAL o_v_poly : arr_uv36(0 TO 2**FRAC-1):=init_poly;
  ATTRIBUTE ramstyle OF o_h_poly : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_v_poly : SIGNAL IS "no_rw_check";
  SIGNAL o_h_poly_a,o_v_poly_a : integer RANGE 0 TO 2**FRAC-1;
  SIGNAL o_h_poly_dr,o_v_poly_dr : unsigned(35 DOWNTO 0);
  SIGNAL o_h_poly_pix,o_v_poly_pix : type_pix;
  SIGNAL o_poly_round : std_logic;
  SIGNAL poly_h_wr,poly_v_wr : std_logic;
  SIGNAL poly_tdw : unsigned(35 DOWNTO 0);
  SIGNAL poly_a2 : unsigned(FRAC-1 DOWNTO 0);
  
  TYPE type_poly_t IS RECORD
    r0,r1,b0,b1,g0,g1 : signed(17 DOWNTO 0);
  END RECORD;
  TYPE type_poly_t2 IS RECORD
    r,g,b : unsigned(17 DOWNTO 0);
  END RECORD;
  
  SIGNAL o_h_poly_t,o_v_poly_t   : type_poly_t;
  SIGNAL o_h_poly_t2,o_v_poly_t2 : type_poly_t2;
  
  FUNCTION poly_calc1(fi : unsigned(35 DOWNTO 0);
                      pm,p0,p1,p2 : type_pix) RETURN type_poly_t IS
    VARIABLE t : type_poly_t;
  BEGIN
    -- 2.7 * 1.8 = 3.15 
    t.r0:=(signed(fi(35 DOWNTO 27)) * signed('0' & pm.r) +
           signed(fi(26 DOWNTO 18)) * signed('0' & p0.r));
    t.r1:=(signed(fi(17 DOWNTO  9)) * signed('0' & p1.r) +
           signed(fi( 8 DOWNTO  0)) * signed('0' & p2.r));
    t.g0:=(signed(fi(35 DOWNTO 27)) * signed('0' & pm.g) +
           signed(fi(26 DOWNTO 18)) * signed('0' & p0.g));
    t.g1:=(signed(fi(17 DOWNTO  9)) * signed('0' & p1.g) +
           signed(fi( 8 DOWNTO  0)) * signed('0' & p2.g));
    t.b0:=(signed(fi(35 DOWNTO 27)) * signed('0' & pm.b) +
           signed(fi(26 DOWNTO 18)) * signed('0' & p0.b));
    t.b1:=(signed(fi(17 DOWNTO  9)) * signed('0' & p1.b) +
           signed(fi( 8 DOWNTO  0)) * signed('0' & p2.b));
    RETURN t;
  END FUNCTION;
  
  FUNCTION poly_calc2(pt : type_poly_t) RETURN type_poly_t2 IS
    VARIABLE p : type_poly_t2;
    VARIABLE t : signed(17 DOWNTO 0); -- 3.15
  BEGIN
    p.r:=unsigned(pt.r0+pt.r1);
    p.g:=unsigned(pt.g0+pt.g1);
    p.b:=unsigned(pt.b0+pt.b1);
    RETURN p;
  END FUNCTION;
  
  FUNCTION poly_calc3(t : type_poly_t2) RETURN type_pix IS
    VARIABLE p : type_pix;
  BEGIN
    p.r:=bound(unsigned(t.r),15);
    p.g:=bound(unsigned(t.g),15);
    p.b:=bound(unsigned(t.b),15);
    RETURN p;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  -- DEBUG
  
  SIGNAL o_debug_set : std_logic;
  SIGNAL o_debug_col : unsigned(7 DOWNTO 0);
  SIGNAL o_debug_vin0 : unsigned(0 TO 32*5-1) :=(OTHERS =>'0');
  SIGNAL o_debug_vin1 : unsigned(0 TO 32*5-1) :=(OTHERS =>'0');
  SIGNAL o_debug_hcpt2,o_debug_hcpt3,o_debug_hcpt4 : uint12;
  SIGNAL o_debug_hcpt5,o_debug_hcpt6 : uint12;
  
  SIGNAL o_debug_char : unsigned(4 DOWNTO 0);
  SIGNAL o_debug_hchar : natural RANGE 0 TO 255;
  
  FUNCTION CC(i : character) RETURN unsigned IS
  BEGIN
    CASE i IS
      WHEN '0' => RETURN "00000";
      WHEN '1' => RETURN "00001";
      WHEN '2' => RETURN "00010";
      WHEN '3' => RETURN "00011";
      WHEN '4' => RETURN "00100";
      WHEN '5' => RETURN "00101";
      WHEN '6' => RETURN "00110";
      WHEN '7' => RETURN "00111";
      WHEN '8' => RETURN "01000";
      WHEN '9' => RETURN "01001";
      WHEN 'A' => RETURN "01010";
      WHEN 'B' => RETURN "01011";
      WHEN 'C' => RETURN "01100";
      WHEN 'D' => RETURN "01101";
      WHEN 'E' => RETURN "01110";
      WHEN 'F' => RETURN "01111";
      WHEN ' ' => RETURN "10000";
      WHEN '=' => RETURN "10001";
      WHEN '+' => RETURN "10010";
      WHEN '-' => RETURN "10011";
      WHEN '<' => RETURN "10100";
      WHEN '>' => RETURN "10101";
      WHEN '^' => RETURN "10110";
      WHEN 'v' => RETURN "10111";
      WHEN '(' => RETURN "11000";
      WHEN ')' => RETURN "11001";
      WHEN ':' => RETURN "11010";
      WHEN '.' => RETURN "11011";
      WHEN ',' => RETURN "11100";
      WHEN '?' => RETURN "11101";
      WHEN '|' => RETURN "11110";
      WHEN '#' => RETURN "11111";
      WHEN OTHERS => RETURN "10000";
    END CASE;
  END FUNCTION CC;
  FUNCTION CS(s : string) RETURN unsigned IS
    VARIABLE r : unsigned(0 TO s'length*5-1);
    VARIABLE j : natural :=0;
  BEGIN
    FOR i IN s'RANGE LOOP
      r(j TO j+4) :=CC(s(i));
      j:=j+5;
    END LOOP;
    RETURN r;
  END FUNCTION CS;
  FUNCTION CN(v : unsigned) RETURN unsigned IS
    VARIABLE t : unsigned(0 TO v'length-1);
    VARIABLE o : unsigned(0 TO v'length/4*5-1);
  BEGIN
    t:=v;
    FOR i IN 0 TO v'length/4-1 LOOP
      o(i*5 TO i*5+4):='0' & t(i*4 TO i*4+3);
    END LOOP;
    RETURN o;
  END FUNCTION CN;
  
BEGIN
  
  -----------------------------------------------------------------------------
  i_reset_na<='0'   WHEN reset_na='0' ELSE '1' WHEN rising_edge(i_clk);
  o_reset_na<='0'   WHEN reset_na='0' ELSE '1' WHEN rising_edge(o_clk);
  avl_reset_na<='0' WHEN reset_na='0' ELSE '1' WHEN rising_edge(avl_clk);
  
  -----------------------------------------------------------------------------
  -- Input pixels FIFO and shreg
  InAT:PROCESS(i_clk,i_reset_na) IS
    CONSTANT Z : unsigned(FRAC-1 DOWNTO 0):=(OTHERS =>'0');
    VARIABLE frac_v : unsigned(23 DOWNTO 0);
    VARIABLE frac2_v : unsigned(FRAC-1 DOWNTO 0);
  BEGIN
    IF i_reset_na='0' THEN
      i_write_pre<='0';
      
    ELSIF rising_edge(i_clk) THEN
      i_push<='0';
      i_eol<='0'; -- End Of Line
      i_freeze <=freeze; -- <ASYNC>
      i_iauto<=iauto; -- <ASYNC> ?
      
      ------------------------------------------------------
      i_head(127 DOWNTO 120)<=x"01"; -- Header type
      i_head(119 DOWNTO 112)<=x"01"; -- 24bits/pixels, packed RGB, big endian
      i_head(111 DOWNTO 96)<=to_unsigned(N_BURST,16); -- Header size
      i_head(95 DOWNTO 80)<=x"0000"; -- Attributes. TBD
      i_head(80)<=i_inter;
      i_head(81)<=i_fl;
      i_head(82)<=i_hdown;
      i_head(83)<=i_vdown;
      i_head(79 DOWNTO 64)<=to_unsigned(i_hrsize,16); -- Image width
      i_head(63 DOWNTO 48)<=to_unsigned(i_vrsize,16); -- Image height
      i_head(47 DOWNTO 32)<=
        to_unsigned(N_BURST * i_hburst,16); -- Line Length. Bytes
      i_head(31 DOWNTO  0)<=x"0000_0000"; -- TBD
      
      ------------------------------------------------------
      IF i_ce='1' THEN
        ----------------------------------------------------
        i_hs_pre<=i_hs;
        i_vs_pre<=i_vs;
        i_de_pre<=i_de;
        i_fl_pre<=i_fl;
        
        ----------------------------------------------------
        -- Detect interleaved video
        IF NOT INTER THEN
          i_intercnt<=0;
        ELSIF i_fl/=i_fl_pre THEN
          i_intercnt<=7;
        ELSIF i_vs='1' AND i_vs_pre='0' AND i_intercnt>0 THEN
          i_intercnt<=i_intercnt-1;
        END IF;
        i_inter<=to_std_logic(i_intercnt>0);
        
        ----------------------------------------------------
        IF i_vs='1' AND i_vs_pre='0' THEN
          i_sof<='1';
        END IF;
        
        IF i_de='1' AND i_sof='1' THEN
          i_sof<='0';
          i_vcpt<=0;
          IF i_inter='1' AND i_flm='1' AND INTER THEN
            i_adrsi<=to_unsigned(N_BURST * i_hburst,32) +
                     to_unsigned(N_BURST * to_integer(
                       unsigned'("00") & to_std_logic(HEADER)),32);
          ELSE
            i_adrsi<=to_unsigned(N_BURST * to_integer(
                       unsigned'("00") & to_std_logic(HEADER)),32);
          END IF;
        END IF;
        
        IF i_de='1' THEN
          i_flm<=NOT i_fl;
        END IF;
        
        i_ven<=to_std_logic(i_hcpt>=i_hmin AND i_hcpt<=i_hmax+1 AND
                            i_vcpt>=i_vmin AND i_vcpt<=i_vmax AND i_de='1');
        
        -- Detects end of frame for triple buffering.
        -- Waits for second frame of interleaved video
        i_endframe<=to_std_logic(i_vcpt=i_vmax + 1 AND
                     (i_inter='0' OR i_fl='1'));
        -- Detects third line for synchronized mode.
        i_syncline<=to_std_logic(i_vcpt=i_vmin + 3);
        
        ----------------------------------------------------
        IF i_de='1' AND i_de_pre='0' THEN
          i_vimaxc<=i_vcpt;
          i_hcpt<=0;
        ELSE
          i_hcpt<=(i_hcpt+1) MOD 4096;
        END IF;
        
        IF i_de='0' AND i_de_pre='1' THEN
          i_himax<=i_hcpt;
        END IF;
        
        IF i_vs='1' THEN
          i_vimax<=i_vimaxc;
        END IF;
        
        IF i_iauto='1' THEN
          -- Auto-size
          i_hmin<=0;
          i_hmax<=i_himax;
          i_vmin<=0;
          IF i_inter='0' OR i_fl='0' THEN
            i_vmax<=i_vimax;
          END IF;
        ELSE
          -- Forced image
          i_hmin<=himin; -- <ASYNC>
          i_hmax<=himax; -- <ASYNC>
          i_vmin<=vimin; -- <ASYNC>
          i_vmax<=vimax; -- <ASYNC>
        END IF;
        
        ----------------------------------------------------
        -- TEST : Scan image properties
        IF i_hs='1' AND i_hs_pre='0' AND i_vcpt=1 THEN i_hsstart<=i_hcpt+1; END IF;
        IF i_hs='0' AND i_hs_pre='1' AND i_vcpt=1 THEN i_hsend<=i_hcpt+1;   END IF;
        IF i_de='1' AND i_de_pre='0' AND i_vcpt=1 THEN i_htotal<=i_hcpt+1;  END IF;
        
        IF i_vs='1' AND i_vs_pre='0' THEN i_vsstart<=i_vcpt;  END IF;
        IF i_vs='0' AND i_vs_pre='1' THEN i_vsend<=i_vcpt;    END IF;
        IF i_de='1' AND i_sof='1'    THEN i_vtotal<=i_vcpt;   END IF;
        
        ----------------------------------------------------
        i_mode<=mode; -- <ASYNC>
        
        -- Downscaling : Nearest or bilinear
        i_bil<=to_std_logic(i_mode(2 DOWNTO 0)/="000" AND DOWNSCALE);
        
        i_hdown<=to_std_logic(i_hsize>i_ohsize AND DOWNSCALE); --H downscale
        i_vdown<=to_std_logic(i_vsize>i_ovsize AND DOWNSCALE); --V downscale
        
        -- If downscaling, export to the output part the downscaled size
        IF i_hdown='0' THEN i_hrsize<=i_hsize;
                       ELSE i_hrsize<=i_ohsize;  END IF;
        IF i_vdown='0' THEN i_vrsize<=i_vsize;
                       ELSE i_vrsize<=i_ovsize;  END IF;
        
        ----------------------------------------------------
        i_hsize<=(4096+i_hmax-i_hmin+1) MOD 4096;
        
        IF i_inter='0' THEN
          i_vsize<=(4096+i_vmax-i_vmin+1) MOD 4096;
        ELSE
          -- Interlaced : Double image height
          i_vsize<=2*((4096+i_vmax-i_vmin+1) MOD 4096);
        END IF;
        
        i_ohsize<=o_hsize; -- <ASYNC>
        i_ovsize<=o_vsize; -- <ASYNC>
        
        ----------------------------------------------------
        -- Downscaling vertical
        i_divstart<='0';
        IF i_hs_delay=14 THEN
          IF i_vacc + i_ovsize < i_vsize THEN
            i_vacc<=(i_vacc + i_ovsize) MOD 4096;
            i_vnp<='0';
          ELSE
            i_vacc<=(i_vacc + i_ovsize - i_vsize + 4096) MOD 4096;
            i_vnp<='1';
          END IF;
          i_divstart<='1';
          
          IF i_vcpt=i_vmin THEN
            i_vacc<=i_ovsize/2 + i_vsize/2;
            i_vnp<='0'; -- <AVOIR>
          END IF;
        END IF;
        
        IF i_vdown='0' THEN
          i_vnp<='1';
        END IF;
        
        -- Downscaling horizontal
        IF i_ven='1' THEN
          IF i_hacc + i_ohsize < i_hsize THEN
            i_hacc<=(i_hacc + i_ohsize) MOD 4096;
            i_hnp<='0';
          ELSE
            i_hacc<=(i_hacc + i_ohsize - i_hsize + 4096) MOD 4096;
            i_hnp<='1';
          END IF;
        END IF;
        IF i_hdown='0' THEN
          i_hnp<='1';
        END IF;
        
        ----------------------------------------------------
        -- Downscaling interpolation
        i_hpixp<=(i_r,i_g,i_b);
        i_hpix0<=i_hpixp;
        i_hpix1<=i_hpix0;
        i_hpix2<=i_hpix1;
        
        i_hnp1<=i_hnp; i_hnp2<=i_hnp1; --i_hnp3<=i_hnp2; i_hnp4<=i_hnp3; 
        i_ven1<=i_ven; i_ven2<=i_ven1; i_ven3<=i_ven2; i_ven4<=i_ven3;
        i_ven5<=i_ven4;
        
        -- C1 : Frac
        frac_v:=i_hacc * i_hdiv; -- 12 * 0.12
        
        -- C2 : Horizontal Bilinear
        IF i_bil='0' THEN
          frac2_v:=near_frac(frac_v(11 DOWNTO 0));
        ELSE
          frac2_v:=bil_frac(frac_v(11 DOWNTO 0));
        END IF;
        
        i_h_frac2 <='0' & frac2_v;
        i_h_fracn2<=('1' & Z) - ('0' & frac2_v);
        
        i_hpix<=bil_calc(i_h_frac2,i_h_fracn2,i_hpix1,i_hpix2);
        IF i_hdown='0' THEN
          i_hpix<=i_hpix2;
        END IF;
        
        -- C3 : Vertical Bilinear
        IF i_bil='0' THEN
          frac2_v:=near_frac(i_v_frac(11 DOWNTO 0));
        ELSE
          frac2_v:=bil_frac(i_v_frac(11 DOWNTO 0));
        END IF;
        
        i_v_frac2 <='0' & frac2_v;
        i_v_fracn2<=('1' & Z) - ('0' & frac2_v);
        
        i_pix<=bil_calc(i_v_frac2,i_v_fracn2,i_hpix,i_ldrm);
        IF i_vdown='0' THEN
          i_pix<=i_hpix;
        END IF;
        
        ----------------------------------------------------
        -- VNP : Vert. downscaling line enable
        -- HNP : Horiz. downscaling pix. enable
        -- VEN : Enable pixel within displayed window
        
        IF (i_hnp2='1' AND i_ven4='1') OR i_pushend='1' THEN
          i_shift<=i_shift(24 TO 119) & i_pix.r & i_pix.g & i_pix.b;
          i_dw<=shift24_ipack(i_dw,i_acpt,i_shift,i_pix);
          IF i_pushhead='1' THEN
            i_dw<=i_head;
          END IF;
          
          IF shift24_inext(i_acpt) AND i_vnp='1' THEN
            i_push<='1';
            i_pushend<='0';
          END IF;
          i_acpt<=(i_acpt+1) MOD 16;
        END IF;
        
        IF i_ven4='1' AND i_ven3='0' AND i_vnp='1' THEN
          i_pushend<='1';
        END IF;
        i_pushend2<=i_pushend;
        
        IF ((i_ven4='0' AND i_ven5='1') OR i_pushend2='1')AND i_pushend='0' THEN
          i_eol<='1';
        END IF;
        
        -- Delay I_HS raising for a few cycles, finish ongoing mem. access
        IF i_hs='1' AND i_hs_pre='0' THEN
          i_hs_delay<=0;
        ELSIF i_hs_delay<15 THEN
          i_hs_delay<=i_hs_delay+1;
        END IF;
        
        IF i_hs_delay=14 THEN -- i_hs='1' AND i_hs_pre='0' THEN
          i_acpt<=0;
          i_hacc<=i_ohsize/2 + i_hsize/2;
          i_lwad<=0;
          i_lrad<=0;
          i_wad<=2*BLEN-1;
          i_vcpt<=i_vcpt+1;
          i_hbcpt<=0; -- Bursts per line counter
          IF i_vnp='1' AND i_hbcpt>0 AND i_hbfix='0' THEN
            i_hburst<=i_hbcpt;
            i_hbfix<='1';
          END IF;
        END IF;
        
        IF i_vs='0' AND i_vs_pre='1' THEN
          i_vacc<=i_ovsize/2 + i_vsize/2;
          -- Push header
          i_pushhead<=to_std_logic(HEADER);
          i_hbfix<='0';
        END IF;
        
      END IF; -- IF i_ce='1'
      
      ------------------------------------------------------
      -- Push pixels to downscaling line buffer
      i_lwr<=i_hnp2 AND i_ven3;
      IF i_lwr='1' THEN
        i_lwad<=(i_lwad+1) MOD OHRES;
      END IF;
      i_ldw<=i_hpix;
      
      IF i_hnp1='1' AND i_ven2='1' THEN
        i_lrad<=(i_lrad+1) MOD OHRES;
      END IF;
      
      ------------------------------------------------------
      -- Push pixels to DPRAM
      i_wr<='0';
      
      IF i_push='1' AND i_freeze='0' THEN
        i_wr<='1';
        i_wad<=(i_wad+1) MOD (BLEN*2);
        IF ((i_wad+1) MOD BLEN=BLEN-1) THEN
          i_hbcpt<=(i_hbcpt+1) MOD 32;
          i_write_pre<=NOT i_write_pre;
          IF (i_wad+1)/BLEN=0 THEN
            i_walt<='0';
          ELSE
            i_walt<='1';
          END IF;
          i_adrs<=i_adrsi;
          i_adrsi<=i_adrsi+N_BURST;
        END IF;
      END IF;
      
      IF i_pushhead='1' AND i_freeze='0' THEN
        i_wr<='1';
        i_wad<=0;
        i_write_pre<=NOT i_write;
        i_walt<='0';
        i_adrs<=(OTHERS =>'0');
        i_pushhead<='0';
      END IF;
      
      -- Delay a bit EOL : Async. AVL/I clocks...
      i_eol2<=i_eol; i_eol3<=i_eol2; i_eol4<=i_eol3;
      
      -- End of line
      IF i_eol4='1' AND i_freeze='0' THEN
        IF (i_wad MOD BLEN)/=BLEN-1 THEN
          -- Some pixels are in the partially filled buffer
          i_hbcpt<=(i_hbcpt+1) MOD 32;
          i_write_pre<=NOT i_write_pre;
          IF i_wad/BLEN=0 THEN
            i_walt<='0';
          ELSE
            i_walt<='1';
          END IF;
          i_adrs<=i_adrsi;
          IF i_inter='1' THEN
            -- Skip every other line for interlaced video
            i_adrsi<=i_adrsi + N_BURST * (i_hburst + 1);
          ELSE
            i_adrsi<=i_adrsi + N_BURST;
          END IF;
        ELSE
          IF i_inter='1' THEN
            -- Skip every other line for interlaced video
            i_adrsi<=i_adrsi + N_BURST * i_hburst;
          END IF;
        END IF;
      END IF;
      i_write<=i_write_pre AND NOT i_freeze;
      
    END IF;
  END PROCESS;
  
  -----------------------------------------------------------------------------
  -- Input Dividers. For downscaling.
  
  -- Hdiv = 1 / IHsize    1.12 / 12 --> 0.12
  -- Vfrac = IVacc / IVsize 12 / 12 --> 12
  
  -- Division
  IDividers:PROCESS (i_clk,i_reset_na) IS
  BEGIN
    IF i_reset_na='0' THEN
--pragma synthesis_off
      i_hdiv<=x"000"; -- Simu !
      i_v_frac<=x"000";
--pragma synthesis_on
      NULL;
    ELSIF rising_edge(i_clk) THEN
      i_hdivi<=to_unsigned(i_hsize,12);
      i_vdivi<=to_unsigned(i_vsize,12);
      i_hdivr<=to_unsigned(4096,24);
      i_vdivr<=to_unsigned(i_vacc*4096,24);
      
      ------------------------------------------------------
      IF i_divstart='1' THEN
        i_divcpt<=0;
        i_divrun<='1';
        
      ELSIF i_divrun='1' THEN
        ----------------------------------------------------
        IF i_divcpt=12 THEN
          i_divrun<='0';
          i_hdiv<=i_hdivr(10 DOWNTO 0) & NOT i_hdivr(23);
          i_v_frac<=i_vdivr(10 DOWNTO 0) & NOT i_vdivr(23);
        ELSE
          i_divcpt<=i_divcpt+1;
        END IF;
        
        ----------------------------------------------------
        IF i_hdivr(23)='0' THEN
          i_hdivr(23 DOWNTO 12)<=i_hdivr(22 DOWNTO 11) - i_hdivi;
        ELSE
          i_hdivr(23 DOWNTO 12)<=i_hdivr(22 DOWNTO 11) + i_hdivi;
        END IF;
        i_hdivr(11 DOWNTO 0)<=i_hdivr(10 DOWNTO 0) & NOT i_hdivr(23);
        
        IF i_vdivr(23)='0' THEN
          i_vdivr(23 DOWNTO 12)<=i_vdivr(22 DOWNTO 11) - i_vdivi;
        ELSE
          i_vdivr(23 DOWNTO 12)<=i_vdivr(22 DOWNTO 11) + i_vdivi;
        END IF;
        i_vdivr(11 DOWNTO 0)<=i_vdivr(10 DOWNTO 0) & NOT i_vdivr(23);
        
        ----------------------------------------------------
      END IF;
    END IF;
  END PROCESS IDividers;

  -----------------------------------------------------------------------------
  -- DPRAM INPUT
  
  PROCESS (i_clk) IS
  BEGIN
    IF rising_edge(i_clk) THEN
      IF i_wr='1' THEN
        i_dpram(i_wad)<=i_dw;
      END IF;
    END IF;
  END PROCESS;
  
  avl_dr<=i_dpram(avl_rad_c) WHEN rising_edge(avl_clk);
  
  -- Line buffer for downscaling with interpolation
  DownLine:IF DOWNSCALE GENERATE
    ILBUF:PROCESS(i_clk) IS
    BEGIN
      IF rising_edge(i_clk) THEN
        IF i_lwr='1' THEN
          i_line(i_lwad)<=i_ldw;
        END IF;
        
        i_ldrm<=i_line(i_lrad);
      END IF;
    END PROCESS ILBUF;
  END GENERATE DownLine;
  
  -----------------------------------------------------------------------------
  -- AVALON interface
  Avaloir:PROCESS(avl_clk,avl_reset_na) IS
  BEGIN
    IF avl_reset_na='0' THEN
      avl_reading<='0';
      avl_state<=sIDLE;
      avl_write_sr<='0';
      avl_read_sr<='0';
      avl_readack<='0';
      
    ELSIF rising_edge(avl_clk) THEN
      ----------------------------------
      --avl_mode<=mode; -- <ASYNC> ?
      avl_write_sync<=i_write; -- <ASYNC>
      avl_write_sync2<=avl_write_sync;
      avl_write_pulse<=avl_write_sync XOR avl_write_sync2;
      avl_wadrs <=i_adrs AND (RAMSIZE - 1); -- <ASYNC>
      avl_walt  <=i_walt; -- <ASYNC>
      
      ----------------------------------
      avl_read_sync<=o_read; -- <ASYNC>
      avl_read_sync2<=avl_read_sync;
      avl_read_pulse<=avl_read_sync XOR avl_read_sync2;
      avl_rbib  <=o_bib;
      avl_radrs <=o_adrs AND (RAMSIZE - 1); -- <ASYNC>
      
      --------------------------------------------
      avl_o_offset<=buf_offset(o_obuf);  -- <ASYNC>
      avl_i_offset<=buf_offset(o_ibuf);  -- <ASYNC>
      
      avl_o_vs_sync<=o_vs0; -- <SYNC>
      avl_o_vs<=avl_o_vs_sync;
      
      --------------------------------------------
      avl_dw<=unsigned(avl_readdata);
      avl_read_i<='0';
      avl_write_i<='0';
      
      avl_write_sr<=(avl_write_sr OR avl_write_pulse) AND NOT avl_write_clr;
      avl_read_sr <=(avl_read_sr OR avl_read_pulse) AND NOT avl_read_clr;
      avl_write_clr<='0';
      avl_read_clr <='0';
      
      avl_rad<=avl_rad_c;
      
      --------------------------------------------
      CASE avl_state IS
        WHEN sIDLE =>
          IF avl_o_vs='0' AND avl_o_vs_sync='1' THEN
            avl_wad<=0;
          END IF;
          IF avl_write_sr='1' THEN
            avl_state<=sWRITE;
            avl_write_clr<='1';
            IF avl_walt='0' THEN
              avl_rad<=0;
            ELSE
              avl_rad<=BLEN;
            END IF;
          ELSIF avl_read_sr='1' AND avl_reading='0' THEN
            IF avl_rbib='0' THEN
              avl_wad<=2*BLEN-1;
            ELSE
              avl_wad<=BLEN-1;
            END IF;
            avl_state<=sREAD;
            avl_read_clr<='1';
          END IF;
          
        WHEN sWRITE =>
          avl_address<=std_logic_vector(RAMBASE(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_wadrs(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_i_offset(N_AW+NB_LA-1 DOWNTO NB_LA));
          avl_write_i<='1';
          IF avl_write_i='1' AND avl_waitrequest='0' THEN
            IF (avl_rad MOD BLEN)=BLEN-1 THEN
              avl_write_i<='0';
              avl_state<=sIDLE;
            END IF;
          END IF;
          
        WHEN sREAD =>
          avl_address<=std_logic_vector(RAMBASE(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_radrs(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_o_offset(N_AW+NB_LA-1 DOWNTO NB_LA));
          avl_read_i<='1';
          avl_reading<='1';
          IF avl_read_i='1' AND avl_waitrequest='0' THEN
            avl_state<=sIDLE;
            avl_read_i<='0';
          END IF;
      END CASE;
      
      --------------------------------------------
      -- Pipelined data read
      avl_wr<='0';
      IF avl_readdatavalid='1' THEN
        avl_wr<='1';
        avl_wad<=(avl_wad+1) MOD (2*BLEN);
        IF (avl_wad MOD BLEN)=BLEN-2 THEN
          avl_reading<='0';
          avl_readack<=NOT avl_readack;
        END IF;
      END IF;
      
      --------------------------------------------
    END IF;
  END PROCESS Avaloir;
  
  avl_read<=avl_read_i;
  avl_write<=avl_write_i;
  avl_writedata<=std_logic_vector(avl_dr);
  avl_burstcount<=std_logic_vector(to_unsigned(BLEN,8));
  avl_byteenable<=(OTHERS =>'1');
  
  avl_rad_c<=(avl_rad+1) MOD (2*BLEN)
              WHEN avl_write_i='1' AND avl_waitrequest='0' ELSE avl_rad;
  
  -----------------------------------------------------------------------------
  -- DPRAM OUTPUT
  PROCESS (avl_clk) IS
  BEGIN
    IF rising_edge(avl_clk) THEN
      IF avl_wr='1' THEN
        o_dpram(avl_wad)<=avl_dw;
      END IF;
    END IF;
  END PROCESS;
      
  o_dr<=o_dpram(o_ad) WHEN rising_edge(o_clk);

  -----------------------------------------------------------------------------
  -- Dividers
  
  -- Hdelta = IHsize / OHsize
  -- Vdelta = IVsize / OVsize

  -- Division : 12 / 12 --> 12.12
  
  ODividers:PROCESS (o_clk,o_reset_na) IS
  BEGIN
    IF o_reset_na='0' THEN
--pragma synthesis_off
      o_hdelta<=x"001000"; -- Simu !
      o_vdelta<=x"001000";
--pragma synthesis_on
      NULL;
    ELSIF rising_edge(o_clk) THEN
      o_hdivi<=to_unsigned(o_hsize,12);
      o_vdivi<=to_unsigned(o_vsize,12);
      o_hdivr<=to_unsigned(o_ihsize * 4096,36);
      o_vdivr<=to_unsigned(o_ivsize * 4096,36);

      ------------------------------------------------------
      IF o_divstart='1' THEN
        o_divcpt<=0;
        o_divrun<='1';
        
      ELSIF o_divrun='1' THEN
        ----------------------------------------------------
        IF o_divcpt=24 THEN
          o_divrun<='0';
          o_hdelta<=o_hdivr(22 DOWNTO 0) & NOT o_hdivr(35);
          o_vdelta<=o_vdivr(22 DOWNTO 0) & NOT o_vdivr(35);
        ELSE
          o_divcpt<=o_divcpt+1;
        END IF;
        
        ----------------------------------------------------
        IF o_hdivr(35)='0' THEN
          o_hdivr(35 DOWNTO 24)<=o_hdivr(34 DOWNTO 23) - o_hdivi;
        ELSE
          o_hdivr(35 DOWNTO 24)<=o_hdivr(34 DOWNTO 23) + o_hdivi;
        END IF;
        o_hdivr(23 DOWNTO 0)<=o_hdivr(22 DOWNTO 0) & NOT o_hdivr(35);
        
        IF o_vdivr(35)='0' THEN
          o_vdivr(35 DOWNTO 24)<=o_vdivr(34 DOWNTO 23) - o_vdivi;
        ELSE
          o_vdivr(35 DOWNTO 24)<=o_vdivr(34 DOWNTO 23) + o_vdivi;
        END IF;
        o_vdivr(23 DOWNTO 0)<=o_vdivr(22 DOWNTO 0) & NOT o_vdivr(35);
        
        ----------------------------------------------------
      END IF;
    END IF;
  END PROCESS ODividers;

  o_vpos_b<=o_vacpt & o_vpos_lob;

  -- Output Dividers. For phase accumulator mode
  
  -- Hdiv = 1 / IHsize   1.12 / 12 --> 0.12
  -- Vfrac = IVacc / IVsize 12 / 12 --> 12

  -- Division
  ODividers2:PROCESS (o_clk,o_reset_na) IS
  BEGIN
    IF o_reset_na='0' THEN
--pragma synthesis_off
      o_vpos_lob<=x"000";
--pragma synthesis_on
      
    ELSIF rising_edge(o_clk) THEN
      o_vdivi2<=to_unsigned(o_vsize,12);
      o_vdivr2<=to_unsigned(o_vacc*4096,24);
      
      ------------------------------------------------------
      IF o_divstart2='1' THEN
        o_divcpt2<=0;
        o_divrun2<='1';
        
      ELSIF o_divrun2='1' THEN
        ----------------------------------------------------
        IF o_divcpt2=12 THEN
          o_divrun2<='0';
          o_vpos_lob<=o_vdivr2(10 DOWNTO 0) & NOT o_vdivr2(23);
        ELSE
          o_divcpt2<=o_divcpt2+1;
        END IF;
        
        ----------------------------------------------------
        IF o_vdivr2(23)='0' THEN
          o_vdivr2(23 DOWNTO 12)<=o_vdivr2(22 DOWNTO 11) - o_vdivi2;
        ELSE
          o_vdivr2(23 DOWNTO 12)<=o_vdivr2(22 DOWNTO 11) + o_vdivi2;
        END IF;
        o_vdivr2(11 DOWNTO 0)<=o_vdivr2(10 DOWNTO 0) & NOT o_vdivr2(23);
        
        ----------------------------------------------------
      END IF;
    END IF;
  END PROCESS ODividers2;
  
  -----------------------------------------------------------------------------
  Scalaire:PROCESS (o_clk,o_reset_na) IS
    VARIABLE mul_v : unsigned(47 DOWNTO 0);
    VARIABLE lev_inc_v,lev_dec_v : std_logic;
    VARIABLE prim_v,last_v,bib_v : std_logic;
    VARIABLE shift_v : unsigned(0 TO N_DW+15);
    VARIABLE hcarry_v,vcarry_v : boolean;
  BEGIN
    IF o_reset_na='0' THEN
      o_copy<='0';
      o_state<=sDISP;
      o_read_pre<='0';
      o_readlev<=0;
      o_copylev<=0;
      o_hsp<='0';
      
    ELSIF rising_edge(o_clk) THEN
      ------------------------------------------------------
      o_mode   <=mode; -- <ASYNC> ?
      o_run    <=run; -- <ASYNC> ?
      
      o_htotal <=htotal; -- <ASYNC> ?
      o_hsstart<=hsstart; -- <ASYNC> ?
      o_hsend  <=hsend; -- <ASYNC> ?
      o_hdisp  <=hdisp; -- <ASYNC> ?
      o_hmin   <=hmin; -- <ASYNC> ?
      o_hmax   <=hmax; -- <ASYNC> ?

      o_vtotal <=vtotal; -- <ASYNC> ?
      o_vsstart<=vsstart; -- <ASYNC> ?
      o_vsend  <=vsend; -- <ASYNC> ?
      o_vdisp  <=vdisp; -- <ASYNC> ?
      o_vmin   <=vmin; -- <ASYNC> ?
      o_vmax   <=vmax; -- <ASYNC> ?
      
      o_hsize  <=o_hmax - o_hmin + 1;
      o_vsize  <=o_vmax - o_vmin + 1;
      
      --------------------------------------------
      -- Triple buffering.
      -- Input : Toggle buffer at end of input frame
      o_iendframe<=i_endframe; -- <ASYNC>
      o_iendframe2<=o_iendframe;
      IF o_iendframe='1' AND o_iendframe2='0' THEN
        o_ibuf<=buf_next(o_ibuf,o_obuf);
        o_bufup<='1';
      END IF;

      -- Output : Change framebuffer, and image properties, at VS falling edge
      IF o_vs1='1' AND o_vs0='0' AND o_bufup='1' THEN
        o_obuf<=buf_next(o_obuf,o_ibuf);
        o_bufup<='0';
        o_hburst <=i_hburst; -- <ASYNC> Bursts per line
        o_ihsize<=i_hrsize; -- <ASYNC>
        o_ivsize<=i_vrsize; -- <ASYNC>
        o_hdown<=i_hdown; -- <ASYNC>
        o_vdown<=i_vdown; -- <ASYNC>
      END IF;
      
      -- Triple buffer disabled
      IF o_mode(3)='0' THEN
        o_obuf<=0;
        o_ibuf<=0;
      END IF;

      ------------------------------------------------------
      o_hmode<=o_mode; 
      IF o_hdown='1' AND DOWNSCALE THEN
        -- Force nearest if downscaling : Downscaled framebuffer
        o_hmode(2 DOWNTO 0)<="000";
      END IF;
      
      o_vmode<=o_mode;
      IF o_vdown='1' AND DOWNSCALE THEN
        -- Force nearest if downscaling : Downscaled framebuffer
        o_vmode(2 DOWNTO 0)<="000";
      END IF;
      
      o_poly_round<=to_std_logic(o_mode(2 DOWNTO 0)="101"); -- <TEST> Rounding
      o_phacc     <=(o_mode(2 DOWNTO 0)="110"); -- <TEST> Phase accumulator mode
      
      ------------------------------------------------------
      -- End DRAM READ
      o_readack_sync<=avl_readack; -- <ASYNC>
      o_readack_sync2<=o_readack_sync;
      o_readack<=o_readack_sync XOR o_readack_sync2;
      
      o_divstart<=o_vs1 AND NOT o_vs0;
      
      ------------------------------------------------------
      lev_inc_v:='0';
      lev_dec_v:='0';
      
      -- acpt : Pixel position within current data word
      -- dcpt : Destination image position
      -- hpos : Source image position, fixed point 12.12
      
      -- Force preload 2 lines at top of screen
      IF o_hs0='1' AND o_hs1='0' THEN
        IF o_vcpt_pre3=o_vmin THEN
          o_fload<=2;
        END IF;
        o_hsp<='1';
      END IF;
      
      o_vpe<=to_std_logic(o_vcpt_pre<o_vmax AND o_vcpt_pre>=o_vmin);
      o_divstart2<='0';
      
      CASE o_state IS
          --------------------------------------------------
        WHEN sDISP =>
          IF o_hsp='1' THEN
            o_state<=sHSYNC;
            o_hsp<='0';
          END IF;
          
          --------------------------------------------------
        WHEN sHSYNC =>
          o_vpos_a<=o_vpos_next;
          o_vpos_next<=o_vpos_next+o_vdelta;
          
          IF o_vacc + o_ivsize < o_vsize THEN
            o_vacc<=(o_vacc + o_ivsize) MOD 4096;
            vcarry_v:=false;
          ELSE
            o_vacc<=(o_vacc + o_ivsize - o_vsize + 4096) MOD 4096;
            vcarry_v:=true;
          END IF;
          o_divstart2<='1';
          IF o_vcpt_pre2=o_vmin THEN --pe='0' THEN
            o_vpos_a   <=x"000800" - ('0' & o_vdelta(23 DOWNTO 1));
            o_vpos_next<=x"000800" + ('0' & o_vdelta(23 DOWNTO 1));
            o_vacc <=(o_vsize/2 - o_ivsize/2 + 4096) MOD 4096;
            o_vacpt<=x"000";
            vcarry_v:=false;
          END IF;

          IF vcarry_v THEN
            o_vacpt<=o_vacpt+1;
          END IF;
          IF NOT o_phacc THEN
            vcarry_v:=(o_vpos_a(12)/=o_vpos_next(12));
          END IF;
          o_hbcpt<=0; -- Clear burst counter on line
          IF (o_vpe='1' AND vcarry_v) OR o_fload>0 THEN
            o_state<=sREAD;
          ELSE
            o_state<=sDISP;
          END IF;
          
        WHEN sREAD =>
          -- Read a block
          IF o_readlev<2 THEN
            lev_inc_v:='1';
            o_read_pre<=NOT o_read_pre;
            o_state <=sWAITREAD;
            o_bibu<=NOT o_bibu;
          END IF;
          prim_v:=to_std_logic(o_hbcpt=0);
          last_v:=to_std_logic(o_hbcpt=o_hburst-1);
          bib_v :=o_bibu;
          o_bib <=o_bibu;
          
          IF o_fload=2 THEN
            o_adrs_pre<=0;
            o_alt<="1111";
          ELSIF o_fload=1 THEN
            o_adrs_pre<=o_hburst;
            o_alt<="0100";
          ELSE
            o_adrs_pre<=to_integer(o_vpos(23 DOWNTO 12)) * o_hburst + o_hburst;
            o_alt<=altx(o_vpos(13 DOWNTO 12) + 2);
          END IF;
          
        WHEN sWAITREAD =>
          IF o_readack='1' THEN
            o_hbcpt<=o_hbcpt+1;
            IF o_hbcpt<o_hburst-1 THEN
              -- If not finshed line, read more
              o_state<=sREAD;
            ELSE
              o_state<=sDISP;
              IF o_fload>=1 THEN
                o_fload<=o_fload-1;
              END IF;
            END IF;
          END IF;
          
          --------------------------------------------------
      END CASE;
      
      IF HEADER THEN
        o_adrs<=to_unsigned((o_adrs_pre + o_hbcpt + 1) * N_BURST,32);
      ELSE
        o_adrs<=to_unsigned((o_adrs_pre + o_hbcpt) * N_BURST,32);
      END IF;
      o_read<=o_read_pre AND o_run;
      
      ------------------------------------------------------

      o_sh<='0';
      ------------------------------------------------------
      -- Copy from buffered memory to pixel lines
      IF o_copy='0' THEN
        o_copyw<='0';
        IF o_copylev>0 AND o_copyw='0' THEN
          o_copy<='1';
        END IF;
        o_adturn<='0';
        
        IF o_primv(0)='1' THEN
          -- First memcopy of a horizontal line, carriage return !
          -- HPOS starts at 1 for the first input image pix,to keep it positive
          o_hpos     <=x"000800" + ('0' & o_hdelta(23 DOWNTO 1));
          o_hpos_next<=x"000800" + ('0' & o_hdelta(23 DOWNTO 1)) + o_hdelta;
          o_hacc     <=(o_hsize/2 + o_ihsize/2 + 4096) MOD 4096;
          o_hacpt    <=x"000";
          o_dcpt<=0;
          IF o_hpos(11)='0' THEN
            o_dshi<=3;
          ELSE
            o_dshi<=2;
          END IF;
          o_acpt<=0;
          o_first<='1';
        END IF;
        
        IF o_bibv(0)='0' THEN
          o_ad<=0;
        ELSE
          o_ad<=BLEN;
        END IF;
      ELSE
        -- dshi : Force shift first two or three pixels of each line
        IF o_dshi=0  THEN
          o_hpos_next<=o_hpos_next+o_hdelta;
          o_hpos<=o_hpos_next;
          
          IF o_hacc + o_ihsize < o_hsize THEN
            o_hacc<=(o_hacc + o_ihsize) MOD 4096;
            hcarry_v:=false;
          ELSE
            o_hacc<=(o_hacc + o_ihsize - o_hsize + 4096) MOD 4096;
            hcarry_v:=true;
          END IF;
          
          o_dcpt<=(o_dcpt+1) MOD 4096;
        ELSE
          o_dshi<=o_dshi-1;
          hcarry_v:=false;
        END IF;
        IF o_dshi<=1 THEN
          o_copyw<='1';
        END IF;
        IF hcarry_v THEN
          o_hacpt<=o_hacpt+1;
        END IF;
        
        IF NOT o_phacc THEN
          hcarry_v:=(o_hpos_next(12)/=o_hpos(12));
        END IF;
        
        IF hcarry_v OR o_dshi>0 THEN
          o_sh<='1';
          o_acpt<=(o_acpt+1) MOD 16;
          IF to_integer(o_hpos_next(23 DOWNTO 12))>=o_ihsize-1 THEN
            o_last<='1';
          ELSE
            o_last<='0';
          END IF;
          
          -- Shift two more pixels to the right before ending line.
          o_last1<=o_last;
          o_last2<=o_last1;
          
          IF shift24_onext(o_acpt) THEN
            o_ad<=(o_ad+1) MOD (2*BLEN);
          END IF;
          
          IF o_adturn='1' AND (shift24_onext((o_acpt+1) MOD 16)) AND
            (((o_ad MOD BLEN=0) AND o_lastv(0)='0') OR o_last2='1')  THEN
            o_copy<='0';
            lev_dec_v:='1';
          END IF;
          
          IF o_ad MOD BLEN=4 THEN
            o_adturn<='1';
          END IF;
        END IF;
      END IF;
      
      ------------------------------------------------------
      IF o_sh='1' THEN
        shift_v:=shift24_opack(o_acpt1,o_shift,o_dr);
        o_shift<=shift_v;
        
        o_hpix0<=(r=>shift_v(0 TO 7),g=>shift_v(8 TO 15),b=>shift_v(16 TO 23));
        o_hpix1<=o_hpix0;
        o_hpix2<=o_hpix1;
        o_hpix3<=o_hpix2;
        
        IF o_first='1' THEN
          -- Left edge. Duplicate first pixel
          o_hpix1<=(r=>shift_v(0 TO 7),g=>shift_v(8 TO 15),b=>shift_v(16 TO 23));
          o_hpix2<=(r=>shift_v(0 TO 7),g=>shift_v(8 TO 15),b=>shift_v(16 TO 23));         
          o_first<='0';
        END IF;
        IF o_last='1' THEN
          -- Right edge. Keep last pixel.
          o_hpix0<=o_hpix0;
        END IF;
      END IF;
      
      ------------------------------------------------------
      -- READLEV : Number of ongoing Avalon Reads
      IF lev_dec_v='1' AND lev_inc_v='0' THEN
        o_readlev<=o_readlev-1;
      ELSIF lev_dec_v='0' AND lev_inc_v='1' THEN
        o_readlev<=o_readlev+1;
      END IF;
      
      -- COPYLEV : Number of ongoing copies to line buffers
      IF lev_dec_v='1' AND o_readack='0' THEN
        o_copylev<=o_copylev-1;
      ELSIF lev_dec_v='0' AND o_readack='1' THEN
        o_copylev<=o_copylev+1;
      END IF;
      
      -- FIFOs
      IF lev_dec_v='1' THEN
        o_primv(0 TO 1)<=o_primv(1 TO 2); -- First buffer of line
        o_lastv(0 TO 1)<=o_lastv(1 TO 2); -- Last buffer of line
        o_bibv (0 TO 1)<=o_bibv (1 TO 2); -- Double buffer select
      END IF;
      
      IF lev_inc_v='1' THEN
        IF o_readlev=0 OR (o_readlev=1 AND lev_dec_v='1') THEN
          o_primv(0)<=prim_v;
          o_lastv(0)<=last_v;
          o_bibv (0)<=bib_v;
        ELSIF (o_readlev=1 AND lev_dec_v='0') OR
              (o_readlev=2 AND lev_dec_v='1') THEN
          o_primv(1)<=prim_v;
          o_lastv(1)<=last_v;
          o_bibv (1)<=bib_v;
        END IF;
        o_primv(2)<=prim_v;
        o_lastv(2)<=last_v;
        o_bibv (2)<=bib_v;
      END IF;
      
      ------------------------------------------------------
    END IF;
  END PROCESS Scalaire;
  
  o_vpos<=o_vpos_b WHEN o_phacc ELSE o_vpos_a;
  
  --o_h_poly_a<=to_integer(o_hpos1(11 DOWNTO 12-FRAC));
  --o_v_poly_a<=to_integer(o_vpos(11 DOWNTO 12-FRAC));

  -- <TEST> Test phase rounding
  Round:PROCESS(o_hpos2,o_vpos,o_poly_round) IS
    VARIABLE t : unsigned(FRAC+1 DOWNTO 0);
  BEGIN
    IF o_poly_round='1' THEN
      t:=('0' & o_hpos2(11 DOWNTO 11-FRAC)) + 1;
      IF t(FRAC+1)='1' THEN
        t:=('0' & o_hpos2(11 DOWNTO 11-FRAC));
      END IF;
      o_h_poly_a<=to_integer(t(FRAC DOWNTO 1));

      t:=('0' & o_vpos(11 DOWNTO 11-FRAC)) + 1;
      IF t(FRAC+1)='1' THEN
        t:=('0' & o_vpos(11 DOWNTO 11-FRAC));
      END IF;
      o_v_poly_a<=to_integer(t(FRAC DOWNTO 1));
      
    ELSE
      o_h_poly_a<=to_integer(o_hpos2(11 DOWNTO 12-FRAC));
      o_v_poly_a<=to_integer(o_vpos(11 DOWNTO 12-FRAC));
    END IF;
    
  END PROCESS Round;
  
--pragma synthesis_off
  xxx_o_hpos<=real(to_integer(o_hpos)) / 4096.0;
  xxx_o_vpos<=real(to_integer(o_vpos)) / 4096.0;
--pragma synthesis_on
  
  -----------------------------------------------------------------------------
  -- Polyphase ROMs
  o_h_poly_dr<=o_h_poly(o_h_poly_a) WHEN rising_edge(o_clk);
  o_v_poly_dr<=o_v_poly(o_v_poly_a) WHEN rising_edge(o_clk);
  
  Polikarpov:PROCESS(poly_clk) IS
  BEGIN
    IF rising_edge(poly_clk) THEN
      IF poly_wr='1' THEN
        poly_tdw(8+9*(3-to_integer(poly_a(1 DOWNTO 0))) DOWNTO
                   9*(3-to_integer(poly_a(1 DOWNTO 0))))<=poly_dw;
      END IF;
      
      poly_h_wr<=poly_wr AND NOT poly_a(FRAC+2);
      poly_v_wr<=poly_wr AND poly_a(FRAC+2);
      poly_a2<=poly_a(FRAC+1 DOWNTO 2);
      
      IF poly_h_wr='1' THEN
        o_h_poly(to_integer(poly_a2))<=poly_tdw;
      END IF;
      IF poly_v_wr='1' THEN
        o_v_poly(to_integer(poly_a2))<=poly_tdw;
      END IF;
    END IF;
  END PROCESS Polikarpov;
  
  -----------------------------------------------------------------------------
  -- Horizontal Scaler
  HSCAL:PROCESS(o_clk) IS
    CONSTANT Z : unsigned(FRAC-1 DOWNTO 0):=(OTHERS =>'0');
    VARIABLE div_v,divt_v : unsigned(11 DOWNTO 0); --uint12;
    VARIABLE dir_v : unsigned(11 DOWNTO 0);
  BEGIN
    IF rising_edge(o_clk) THEN
      -- Pipeline signals
      o_hpos1<=o_hpos;
      o_hpos2<=o_hpos1;
      o_hacpt1<=o_hacpt;
      
      -----------------------------------
      -- Pipelined 5 bits divider. Cycle 1
      dir_v:=x"000";
      div_v:=to_unsigned(o_hacc,12);

      divt_v:=div_v-o_hsize/2;
      dir_v(11):=NOT divt_v(11);
      IF divt_v(11)='0' THEN div_v:=divt_v; END IF;
      divt_v:=div_v-o_hsize/4;
      dir_v(10):=NOT divt_v(11);
      IF divt_v(11)='0' THEN div_v:=divt_v; END IF;
      divt_v:=div_v-o_hsize/8;
      dir_v( 9):=NOT divt_v(11);
      IF divt_v(11)='0' THEN div_v:=divt_v; END IF;
      
      o_div<=div_v;
      o_dir<=dir_v;

      -- Cycle 2
      div_v:=o_div;
      dir_v:=o_dir;
      divt_v:=div_v-o_hsize/16;
      dir_v( 8):=NOT divt_v(11);
      IF divt_v(11)='0' THEN div_v:=divt_v; END IF;
      divt_v:=div_v-o_hsize/32;
      dir_v( 7):=NOT divt_v(11);
      IF divt_v(11)='0' THEN div_v:=divt_v; END IF;
      
      -----------------------------------
      IF o_phacc THEN
        o_hpos2(11 DOWNTO 0) <=dir_v;
        o_hpos2(23 DOWNTO 12)<=o_hacpt1;
      END IF;
      
      o_hpos3<=o_hpos2; o_hpos4<=o_hpos3; o_hpos5<=o_hpos4;
      o_copy1<=o_copyw; o_copy2<=o_copy1; o_copy3<=o_copy2; o_copy4<=o_copy3; o_copy5<=o_copy4;
      o_copy6<=o_copy5;
      
      o_dcpt1<=o_dcpt;
      IF o_dcpt1>o_hsize THEN
        o_copy2<='0';
      END IF;
      o_dcpt2<=o_dcpt1 MOD OHRES;
      o_dcpt3<=o_dcpt2; o_dcpt4<=o_dcpt3; o_dcpt5<=o_dcpt4; o_dcpt6<=o_dcpt5;
      o_acpt1<=o_acpt;
      
      o_hpix01<=o_hpix3;  o_hpix11<=o_hpix2;  o_hpix21<=o_hpix1;  o_hpix31<=o_hpix0;
      o_hpix02<=o_hpix01; o_hpix12<=o_hpix11; o_hpix22<=o_hpix21; o_hpix32<=o_hpix31;
      --o_hpix03<=o_hpix02;
		o_hpix13<=o_hpix12; o_hpix23<=o_hpix22; --o_hpix33<=o_hpix32;
      o_hpix14<=o_hpix13; o_hpix24<=o_hpix23;
      
      -- NEAREST / BILINEAR / SHARP BILINEAR ---------------
      -- C1 : Pre-calc Sharp Bilinear
      o_h_sbil_t<=sbil_frac1(o_hpos2(11 DOWNTO 0));
      
      -- C2 : Select
      o_h_frac2<=(OTHERS =>'0');
      CASE o_hmode(1 DOWNTO 0) IS
        WHEN "00" => -- Nearest
          IF MASK(MASK_NEAREST)='1' THEN
            o_h_frac2<=near_frac(o_hpos3(11 DOWNTO 0));
          END IF;
        WHEN "01" => -- Bilinear
          IF MASK(MASK_BILINEAR)='1' THEN
            o_h_frac2<=bil_frac(o_hpos3(11 DOWNTO 0));
          END IF;
        WHEN "10" => -- Sharp Bilinear
          IF MASK(MASK_SHARP_BILINEAR)='1' THEN
            o_h_frac2<=sbil_frac2(o_hpos3(11 DOWNTO 0),o_h_sbil_t);
          END IF;
        WHEN OTHERS =>
          NULL;
      END CASE;
      
      -- C3 : Opposite frac
      o_h_frac3 <='0' & o_h_frac2;
      o_h_fracn3<=('1' & Z) - ('0' & o_h_frac2);
      
      -- C4 : Nearest / Bilinear / Sharp Bilinear
      o_h_bil_pix<=bil_calc(o_h_frac3,o_h_fracn3,o_hpix14,o_hpix24);
      
      -- BICUBIC -------------------------------------------
      -- C1 : Bicubic coefficients A,B,C,D
      o_h_bic_abcd<=bic_calc0(o_hpos2(11 DOWNTO 0),o_hpix01,o_hpix11,o_hpix21,o_hpix31);
      
      -- C2 : Bicubic calc T1 = X.D + C
      o_h_bic_abcd1<=o_h_bic_abcd;
      o_h_bic_tt1<=bic_calc1(o_hpos3(11 DOWNTO 0),o_h_bic_abcd);

      -- C3 : Bicubic calc T2 = X.T1 + B
      o_h_bic_abcd2<=o_h_bic_abcd1;
      o_h_bic_tt2<=bic_calc2(o_hpos4(11 DOWNTO 0),o_h_bic_tt1,o_h_bic_abcd1);
      
      -- C4 : Bicubic final Y = X.T2 + A
      o_h_bic_pix<=bic_calc3(o_hpos5(11 DOWNTO 0),o_h_bic_tt2,o_h_bic_abcd2);
      
      -- POLYPHASE -----------------------------------------
      -- C1 : Read memory
      
      -- C2 : Filter calc
      o_h_poly_t<=poly_calc1(o_h_poly_dr,o_hpix02,o_hpix12,o_hpix22,o_hpix32);
      
      -- C3 : Add
      o_h_poly_t2<=poly_calc2(o_h_poly_t);

      -- C4 : Bounding
      o_h_poly_pix<=poly_calc3(o_h_poly_t2);
      
      -- C4 : Select interpoler ----------------------------
      o_wadl<=o_dcpt6;
      o_wr<=o_alt AND (o_copy6 & o_copy6 & o_copy6 & o_copy6);
      o_ldw<=(x"00",x"00",x"00");
      
      CASE o_hmode(2 DOWNTO 0) IS
        WHEN "000" | "001" | "010" => -- Nearest | Bilinear | Sharp Bilinear
          IF MASK(MASK_NEAREST)='1' OR
             MASK(MASK_BILINEAR)='1' OR
             MASK(MASK_SHARP_BILINEAR)='1' THEN
            o_ldw<=o_h_bil_pix;
         END IF;
        WHEN "011" => -- BiCubic
          IF MASK(MASK_BICUBIC)='1' THEN
            o_ldw<=o_h_bic_pix;
          END IF;
        WHEN OTHERS => -- PolyPhase
          IF MASK(MASK_POLY)='1' THEN
            o_ldw<=o_h_poly_pix;
          END IF;
      END CASE;
      ------------------------------------------------------
    END IF;
  END PROCESS HSCAL;
  
  -----------------------------------------------------------------------------
  -- Line buffers 4 x OHSIZE x (R+G+B)
  OLBUF:PROCESS(o_clk) IS
  BEGIN
    IF rising_edge(o_clk) THEN
      -- WRITES
      IF o_wr(0)='1' THEN o_line0(o_wadl)<=o_ldw; END IF;
      IF o_wr(1)='1' THEN o_line1(o_wadl)<=o_ldw; END IF;
      IF o_wr(2)='1' THEN o_line2(o_wadl)<=o_ldw; END IF;
      IF o_wr(3)='1' THEN o_line3(o_wadl)<=o_ldw; END IF;
      
      -- READS
      o_ldr0<=o_line0(o_radl);
      o_ldr1<=o_line1(o_radl);
      o_ldr2<=o_line2(o_radl);
      o_ldr3<=o_line3(o_radl);
    END IF;
  END PROCESS OLBUF;
  
  o_radl<=(o_hcpt-o_hmin+OHRES) MOD OHRES;
  --xxx_vposi<=to_integer(o_vpos(23 DOWNTO 12)); -- Simu!
  
  -----------------------------------------------------------------------------
  -- Output video sweep
  OSWEEP:PROCESS(o_clk) IS
  BEGIN
    IF rising_edge(o_clk) THEN
      IF o_ce='1' THEN
        -- Output pixels count
        IF o_hcpt<o_htotal-1 THEN
          o_hcpt<=(o_hcpt+1) MOD 4096;
        ELSE
          o_hcpt<=0;
          IF (o_vcpt_pre3>=o_vtotal-1) OR (o_dosync='1' AND SYNCHRO) THEN
            o_vcpt_pre3<=0;
            o_dosync<='0';
          ELSE
            o_vcpt_pre3<=(o_vcpt_pre3+1) MOD 4096;
          END IF;
          o_vcpt_pre2<=o_vcpt_pre3;
          o_vcpt_pre<=o_vcpt_pre2;
          o_vcpt<=o_vcpt_pre;
        END IF;
        
        o_de0<=to_std_logic(o_hcpt<o_hdisp AND o_vcpt<o_vdisp);
        o_pe0<=to_std_logic(o_hcpt>=o_hmin AND o_hcpt<=o_hmax AND
                            o_vcpt>=o_vmin AND o_vcpt<=o_vmax);
        o_hs0<=to_std_logic(o_hcpt>=o_hsstart AND o_hcpt<o_hsend);
        o_vs0<=to_std_logic((o_vcpt=o_vsstart AND o_hcpt>=o_hsstart) OR
                            (o_vcpt>o_vsstart AND o_vcpt<o_vsend) OR
                            (o_vcpt=o_vsend   AND o_hcpt<o_hsstart));
        
        IF o_run='0' THEN
          o_de0<='0';
          o_pe0<='0';
          o_hs0<='0';
          o_vs0<='0';
        END IF;
        
        ----------------------------------------------------
        -- SYNCHRONIZED LOW LATENCY MODE
        -- Trigger start of output frame after third line of input frame.
        o_isyncline<=i_syncline; -- <ASYNC>
        --o_isyncline2<=o_isyncline;

        o_msync<=o_mode(4);
        o_msync2<=o_msync;
        IF o_msync='1' AND o_msync2='0' THEN
          o_syncpend<='1';
        END IF;
        IF o_syncpend='1' AND o_isyncline='1' THEN
          o_syncpend<='0';
          o_dosync<='1';
        END IF;
        
      END IF;
    END IF;
    
  END PROCESS OSWEEP;
  
  -----------------------------------------------------------------------------
  -- Vertical Scaler
  VSCAL:PROCESS(o_clk) IS
    CONSTANT Z : unsigned(FRAC-1 DOWNTO 0):=(OTHERS =>'0');
    VARIABLE pixm_v,pix0_v,pix1_v,pix2_v : type_pix;
  BEGIN
    IF rising_edge(o_clk) THEN
      IF o_ce='1' THEN
        -- Pipeline signals
        o_hs1<=o_hs0; o_hs2<=o_hs1; o_hs3<=o_hs2; o_hs4<=o_hs3; o_hs5<=o_hs4; 
        o_vs1<=o_vs0; o_vs2<=o_vs1; o_vs3<=o_vs2; o_vs4<=o_vs3; o_vs5<=o_vs4; 
        o_de1<=o_de0; o_de2<=o_de1; o_de3<=o_de2; o_de4<=o_de3; o_de5<=o_de4; 
        o_pe1<=o_pe0; o_pe2<=o_pe1; o_pe3<=o_pe2; o_pe4<=o_pe3; o_pe5<=o_pe4; 
        
        -- CYCLE 1 -----------------------------------------
        -- Read mem
        
        -- CYCLE 2 -----------------------------------------
        -- Lines reordering
        CASE o_vpos(13 DOWNTO 12) IS
          WHEN "01" =>
            pixm_v:=o_ldr0;
            pix0_v:=o_ldr1;
            pix1_v:=o_ldr2;
            pix2_v:=o_ldr3;
          WHEN "10" =>
            pixm_v:=o_ldr1;
            pix0_v:=o_ldr2;
            pix1_v:=o_ldr3;
            pix2_v:=o_ldr0;
          WHEN "11" =>
            pixm_v:=o_ldr2;
            pix0_v:=o_ldr3;
            pix1_v:=o_ldr0;
            pix2_v:=o_ldr1;
          WHEN OTHERS =>
            pixm_v:=o_ldr3;
            pix0_v:=o_ldr0;
            pix1_v:=o_ldr1;
            pix2_v:=o_ldr2;
        END CASE;
        
        o_vpixm2<=pixm_v;
        o_vpix02<=pix0_v;
        o_vpix12<=pix1_v;
        o_vpix22<=pix2_v;

        -- Bottom edge : replicate last line
        IF (to_integer(o_vpos(23 DOWNTO 12))+1)=o_ivsize THEN
          o_vpix22<=pix1_v;
        END IF;
        IF (to_integer(o_vpos(23 DOWNTO 12)))>=o_ivsize THEN
          o_vpix22<=pix0_v;
          o_vpix12<=pix0_v;
        END IF;
        
        -- CYCLE 3 -----------------------------------------
        o_vpixm3<=o_vpixm2;
        o_vpix03<=o_vpix02; o_vpix04<=o_vpix03; o_vpix05<=o_vpix04;
        o_vpix13<=o_vpix12; o_vpix14<=o_vpix13; o_vpix15<=o_vpix14;
        o_vpix23<=o_vpix22;
        
        -- NEAREST / BILINEAR / SHARP BILINEAR -------------
        -- C3 : Pre-calc Sharp Bilinear
        o_v_sbil_t<=sbil_frac1(o_vpos(11 DOWNTO 0));
        
        -- C4 : Select
        o_v_frac<=(OTHERS =>'0');
        CASE o_vmode(1 DOWNTO 0) IS
          WHEN "00" => -- Nearest
            IF MASK(MASK_NEAREST)='1' THEN
              o_v_frac<=near_frac(o_vpos(11 DOWNTO 0));
            END IF;
          WHEN "01" => -- Bilinear
            IF MASK(MASK_BILINEAR)='1' THEN
              o_v_frac<=bil_frac(o_vpos(11 DOWNTO 0));
            END IF;
          WHEN "10" => -- Sharp Bilinear
            IF MASK(MASK_SHARP_BILINEAR)='1' THEN
              o_v_frac<=sbil_frac2(o_vpos(11 DOWNTO 0),o_v_sbil_t);
            END IF;
          WHEN OTHERS => NULL;
        END CASE;
        
        o_v_frac2 <='0' & o_v_frac;
        o_v_fracn2<=('1' & Z) - ('0' & o_v_frac);
        
        -- C6 : Nearest / Bilinear / Sharp Bilinear
        o_v_bil_pix<=bil_calc(o_v_frac2,o_v_fracn2,o_vpix05,o_vpix15);
        
        -- BICUBIC -----------------------------------------
        -- C3 : Bicubic coefficients A,B,C,D
        o_v_bic_abcd<=bic_calc0(o_vpos(11 DOWNTO 0),o_vpixm2,o_vpix02,o_vpix12,o_vpix22);
        
        -- C4 : Bicubic calc T1 = X.D + C
        o_v_bic_abcd1<=o_v_bic_abcd;
        o_v_bic_tt1<=bic_calc1(o_vpos(11 DOWNTO 0),o_v_bic_abcd);
        
        -- C5 : Bicubic calc T2 = X.T1 + B
        o_v_bic_abcd2<=o_v_bic_abcd1;
        o_v_bic_tt2<=bic_calc2(o_vpos(11 DOWNTO 0),o_v_bic_tt1,o_v_bic_abcd1);
        
        -- C6 : Bicubic final Y = X.T2 + A
        o_v_bic_pix<=bic_calc3(o_vpos(11 DOWNTO 0),o_v_bic_tt2,o_v_bic_abcd2);
        
        -- POLYPHASE ---------------------------------------
        -- C3 : Read memory
        
        -- C4 : Filter calc
        o_v_poly_t<=poly_calc1(o_v_poly_dr,o_vpixm3,o_vpix03,o_vpix13,o_vpix23);
        
        -- C5 : Add
        o_v_poly_t2<=poly_calc2(o_v_poly_t);
        
        -- C6 : Bounding
        o_v_poly_pix<=poly_calc3(o_v_poly_t2);
        
        -- CYCLE 6 -----------------------------------------
        o_hs<=o_hs5;
        o_vs<=o_vs5;
        o_de<=o_de5;
        o_r<=x"00";
        o_g<=x"00";
        o_b<=x"00";
            
        CASE o_vmode(2 DOWNTO 0) IS
          WHEN "000" | "001" | "010" => -- Nearest | Bilinear | Sharp Bilinear
            IF MASK(MASK_NEAREST)='1' OR
               MASK(MASK_BILINEAR)='1' OR
               MASK(MASK_SHARP_BILINEAR)='1' THEN
              o_r<=o_v_bil_pix.r;
              o_g<=o_v_bil_pix.g;
              o_b<=o_v_bil_pix.b;
            END IF;
          WHEN "011" => -- BiCubic
            IF MASK(MASK_BICUBIC)='1' THEN
              o_r<=o_v_bic_pix.r;
              o_g<=o_v_bic_pix.g;
              o_b<=o_v_bic_pix.b;
            END IF;
            
          WHEN OTHERS => -- Polyphase
            IF MASK(MASK_POLY)='1' THEN
              o_r<=o_v_poly_pix.r;
              o_g<=o_v_poly_pix.g;
              o_b<=o_v_poly_pix.b;
            END IF;
        END CASE;
        
        IF o_pe5='0' THEN
          o_r<=x"00"; -- Border colour
          o_g<=x"00";
          o_b<=x"00";
        END IF;
        
        IF o_mode(2 DOWNTO 0)="111" AND o_vcpt<2*8 THEN
          o_r<=(OTHERS => o_debug_set);
          o_g<=(OTHERS => o_debug_set);
          o_b<=(OTHERS => o_debug_set);
        END IF;
        
        ----------------------------------------------------
      END IF;
    END IF;

  END PROCESS VSCAL;
  
  -----------------------------------------------------------------------------
  -- DEBUG
  Debug:PROCESS(o_clk) IS
    TYPE arr_uv8 IS ARRAY (natural RANGE <>) OF unsigned(7 DOWNTO 0);
    CONSTANT CHARS : arr_uv8 :=(
      x"3E", x"63", x"73", x"7B", x"6F", x"67", x"3E", x"00",  -- 0
      x"0C", x"0E", x"0C", x"0C", x"0C", x"0C", x"3F", x"00",  -- 1
      x"1E", x"33", x"30", x"1C", x"06", x"33", x"3F", x"00",  -- 2
      x"1E", x"33", x"30", x"1C", x"30", x"33", x"1E", x"00",  -- 3
      x"38", x"3C", x"36", x"33", x"7F", x"30", x"78", x"00",  -- 4
      x"3F", x"03", x"1F", x"30", x"30", x"33", x"1E", x"00",  -- 5
      x"1C", x"06", x"03", x"1F", x"33", x"33", x"1E", x"00",  -- 6
      x"3F", x"33", x"30", x"18", x"0C", x"0C", x"0C", x"00",  -- 7
      x"1E", x"33", x"33", x"1E", x"33", x"33", x"1E", x"00",  -- 8
      x"1E", x"33", x"33", x"3E", x"30", x"18", x"0E", x"00",  -- 9
      x"0C", x"1E", x"33", x"33", x"3F", x"33", x"33", x"00",  -- A
      x"3F", x"66", x"66", x"3E", x"66", x"66", x"3F", x"00",  -- B
      x"3C", x"66", x"03", x"03", x"03", x"66", x"3C", x"00",  -- C
      x"1F", x"36", x"66", x"66", x"66", x"36", x"1F", x"00",  -- D
      x"7F", x"46", x"16", x"1E", x"16", x"46", x"7F", x"00",  -- E
      x"7F", x"46", x"16", x"1E", x"16", x"06", x"0F", x"00",  -- F
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",  --' ' 10
      x"00", x"00", x"3F", x"00", x"00", x"3F", x"00", x"00",  -- =  11
      x"00", x"0C", x"0C", x"3F", x"0C", x"0C", x"00", x"00",  -- +  12
      x"00", x"00", x"00", x"3F", x"00", x"00", x"00", x"00",  -- -  13
      x"18", x"0C", x"06", x"03", x"06", x"0C", x"18", x"00",  -- <  14
      x"06", x"0C", x"18", x"30", x"18", x"0C", x"06", x"00",  -- >  15
      x"08", x"1C", x"36", x"63", x"41", x"00", x"00", x"00",  -- ^  16
      x"08", x"1C", x"36", x"63", x"41", x"00", x"00", x"00",  -- v  17
      x"18", x"0C", x"06", x"06", x"06", x"0C", x"18", x"00",  -- (  18
      x"06", x"0C", x"18", x"18", x"18", x"0C", x"06", x"00",  -- )  19
      x"00", x"0C", x"0C", x"00", x"00", x"0C", x"0C", x"00",  -- :  1A
      x"00", x"00", x"00", x"00", x"00", x"0C", x"0C", x"00",  -- .  1B
      x"00", x"00", x"00", x"00", x"00", x"0C", x"0C", x"06",  -- ,  1C
      x"1E", x"33", x"30", x"18", x"0C", x"00", x"0C", x"00",  -- ?  1D
      x"18", x"18", x"18", x"00", x"18", x"18", x"18", x"00",  -- |  1E
      x"36", x"36", x"7F", x"36", x"7F", x"36", x"36", x"00"); -- #  1F
    
    VARIABLE vin_v  : unsigned(0 TO 32*5-1);
  BEGIN
    IF rising_edge(o_clk) THEN
      IF o_ce='1' THEN
        o_debug_hcpt2<=o_hcpt;
        o_debug_hcpt3<=o_debug_hcpt2;
        o_debug_hcpt4<=o_debug_hcpt3;
        o_debug_hcpt5<=o_debug_hcpt4;
        o_debug_hcpt6<=o_debug_hcpt5;
        IF (o_vcpt/8) MOD 2=0 THEN
          vin_v:=o_debug_vin0;
        ELSE
          vin_v:=o_debug_vin1;
        END IF;
        o_debug_hchar<=((o_debug_hcpt2/8)*5) MOD 256;
        IF o_debug_hcpt3<32 * 8 AND o_vcpt<2 * 8 THEN
          o_debug_char<=vin_v(o_debug_hchar TO o_debug_hchar+4);
        ELSE
          o_debug_char<="10000"; -- " " : Blank character
        END IF;
        
        o_debug_col<=CHARS(to_integer(o_debug_char)*8+(o_vcpt MOD 8));
        
        IF o_debug_col(o_debug_hcpt6 MOD 8)='1' THEN
          o_debug_set<='1';
        ELSE
          o_debug_set<='0';
        END IF;
      END IF;
    END IF;
  END PROCESS Debug;

  ----------------------------------------------------------
  o_debug_vin0<=
    CN(to_unsigned(i_himax  ,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_hsstart,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_hsend  ,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_htotal ,12)) & -- 3
    "1001" & NOT i_inter &
    CN(to_unsigned(i_vimax  ,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_vsstart,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_vsend  ,12)) & -- 3
    CC(' ') &
    CN(to_unsigned(i_vtotal ,12)) & -- 3
    CC(' ');
    
  o_debug_vin1<=
    CC(' ') & -- 1
    "0000" & i_inter & -- 1
    CC(',') & -- 1
    CN(o_hdelta(11 DOWNTO 0)) & -- 3
    CC(' ') & -- 1
    CN(o_vdelta(11 DOWNTO 0)) & -- 3
    CC('|') & -- 1
    CN(to_unsigned(o_hburst,8)) & -- 2
    CC(' ') & -- 1
    CN(to_unsigned(i_intercnt,4)) & -- 1
    CC(' ') & -- 1
    CN(to_unsigned(o_ibuf,4)) & -- 1
    CN(to_unsigned(o_obuf,4)) & -- 1
    CS("       ") &
    CS("       ");
  ----------------------------------------------------------------------------  
END ARCHITECTURE rtl;

// license:GPL-2.0+
// copyright-holders:Jarek Burczynski

#define OPL3_SAMPLE_BITS 16

#define TL_RES_LEN      (256)   /* 8 bits addressing (real chip) */
#define TL_TAB_LEN (13*2*TL_RES_LEN)

/* sinwave entries */
#define SIN_BITS        10
#define SIN_LEN         (1<<SIN_BITS)
#define SIN_MASK        (SIN_LEN-1)
#define RATE_STEPS (8)

/* Envelope Generator phases */
#define EG_ATT          4
#define EG_DEC          3
#define EG_SUS          2
#define EG_REL          1
#define EG_OFF          0

#define MAX_ATT_INDEX   ((1<<(ENV_BITS-1))-1) /*511*/
#define MIN_ATT_INDEX   (0)

/* envelope output entries */
#define ENV_BITS        10

typedef unsigned char   uint8_t;   /* unsigned  8bit */
typedef unsigned short  uint16_t;  /* unsigned 16bit */
typedef unsigned long    uint32_t;  /* unsigned 32bit */
typedef signed char     int8_t;    /* signed  8bit   */
typedef signed short    int16_t;   /* signed 16bit   */
typedef signed long      int32_t;   /* signed 32bit   */

typedef int16_t OPL3SAMPLE;
typedef void (*OPL3_TIMERHANDLER)(void *param,int timer,const uint16_t period);
typedef void (*OPL3_IRQHANDLER)(void *param, int irq);
typedef void (*OPL3_UPDATEHANDLER)(void *param, int min_interval_us);

/* 36 operators, 8 waveforms */
#pragma pack(1)
typedef struct _OPL3_SLOT	// 44 bytes
{
	uint8_t  ar;          /* 0 - attack rate: AR<<2           */
	uint8_t  dr;          /* 1 - decay rate:  DR<<2           */
	uint8_t  rr;          /* 2 - release rate:RR<<2           */
	uint8_t pad1;		  /* 3 */
						  /* Phase Generator */
	uint32_t  Cnt;        /* 4 - frequency counter            */
	uint32_t  Incr;       /* 8 - frequency counter step       */
	int16_t   op1_out[2]; /* 12 - slot1 output for feedback    */
	uint8_t  TL;          /* 16 - total level: TL << 2         */
	uint8_t   CON;        /* 17 - connection (algorithm) type  */
						  /* Envelope Generator */
	uint8_t   state;      /* 18 - phase type                   */
	uint8_t   eg_type;	  /* 19 - bool - percussive/non-percussive mode */
	uint16_t  AMmask_TLL; /* 20 - bit15 = LFO Amplitude Modulation enable mask, bit 8..0 = adjusted now TL */
	int16_t   volume;     /* 22 - envelope counter             */
	uint8_t	  FB;         /* 24 - feedback shift value         */
	uint8_t   wavetable;  /* 25 */
	uint8_t   KSR;        /* 26 - key scale rate               */
	uint8_t   ksl;        /* 27 - keyscale level               */
	uint8_t   ksr;        /* 28 - key scale rate: kcode>>KSR   */
	uint8_t  key;         /* 29 - 0 = KEY OFF, >0 = KEY ON     */
	uint16_t   mul;       /* 30 - multiple: mul_tab[ML]        */
	uint16_t  sl;         /* 32 - sustain level: sl_tab[SL]    */
	uint8_t   vib;		  /* 34 - bool - LFO Phase Modulation enable flag (active high)*/
	uint8_t   waveform_number; /* 35 */
	int16_t   connect;    /* 36 - slot output pointer          */
	uint8_t   eg_sh_ar;   /* 38 - (attack state)               */
	uint8_t   eg_sel_ar;  /* 39 - (attack state)               */
	uint8_t   eg_sh_dr;   /* 40 - (decay state)                */
	uint8_t   eg_sel_dr;  /* 41 - (decay state)                */
	uint8_t   eg_sh_rr;   /* 42 - (release state)              */
	uint8_t   eg_sel_rr;  /* 43 - (release state)              */
} OPL3_SLOT;

typedef struct _OPL3_CH // 96 bytes
{
	OPL3_SLOT SLOT0;	  /* 0 */
	uint16_t  block_fnum; /* 44 - block+fnum                   */
	int16_t chanout;	  /* 46 */
						  /*
						  there are 12 2-operator channels which can be combined in pairs
						  to form six 4-operator channel, they are:
						  0 and 3,
						  1 and 4,
						  2 and 5,
						  9 and 12,
						  10 and 13,
						  11 and 14
						  */
	OPL3_SLOT SLOT1;	  /* 48 */

	uint8_t   extended;   /* SLOT1+44 - bool - set to 1 if this channel forms up a 4op channel with another channel(only used by first of pair of channels, ie 0,1,2 and 9,10,11) */
	uint8_t  ksl_base;    /* 45 - KeyScaleLevel Base step      */
	uint8_t   kcode;      /* 46 - key code (for key scaling)   */
	uint8_t pad;		  /* 47 */
} OPL3_CH;

/* OPL3 state */
typedef struct _OPL3
{
	OPL3_CH P_CH[18];            /* OPL3 chips have 18 channels  */
	int16_t phase_modulation;    /* 0 - phase modulation input (SLOT 2) */
	int16_t phase_modulation2;   /* 2 - phase modulation input (SLOT 3 in 4 operator channels) */
	uint32_t  panA;              /* 4 - channels output masks */
	uint32_t  panB;              /* 8 - channels output masks */
								 /* LFO */
	uint8_t   lfo_am_depth;		 /* 12 - bool */
	uint8_t   lfo_pm_depth_range;/* 13 */
	uint8_t   OPL3_mode;         /* 14 - bool - OPL3 extension enable flag   */
	uint8_t   rhythm;            /* 15 - bool - Rhythm mode                  */
	uint16_t  address;           /* 16 - address register             */
	uint8_t   nts;               /* 20 - NTS (note select)            */
} OPL3;


void OPL3ResetChip();
void OPL3Write(uint8_t a, uint8_t v);



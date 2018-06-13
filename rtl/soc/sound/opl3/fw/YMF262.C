// license:GPL-2.0+
// copyright-holders:Jarek Burczynski
/*
**
** File: ymf262.c - software implementation of YMF262
**                  FM sound generator type OPL3
**
** Copyright Jarek Burczynski
**
** Version 0.2
**

Revision History:

03-03-2003: initial release
 - thanks to Olivier Galibert and Chris Hardy for YMF262 and YAC512 chips
 - thanks to Stiletto for the datasheets

   Features as listed in 4MF262A6 data sheet:
    1. Registers are compatible with YM3812 (OPL2) FM sound source.
    2. Up to six sounds can be used as four-operator melody sounds for variety.
    3. 18 simultaneous melody sounds, or 15 melody sounds with 5 rhythm sounds (with two operators).
    4. 6 four-operator melody sounds and 6 two-operator melody sounds, or 6 four-operator melody
       sounds, 3 two-operator melody sounds and 5 rhythm sounds (with four operators).
    5. 8 selectable waveforms.
    6. 4-channel sound output.
    7. YMF262 compabile DAC (YAC512) is available.
    8. LFO for vibrato and tremolo effedts.
    9. 2 programable timers.
   10. Shorter register access time compared with YM3812.
   11. 5V single supply silicon gate CMOS process.
   12. 24 Pin SOP Package (YMF262-M), 48 Pin SQFP Package (YMF262-S).


differences between OPL2 and OPL3 not documented in Yamaha datahasheets:
- sinus table is a little different: the negative part is off by one...

- in order to enable selection of four different waveforms on OPL2
  one must set bit 5 in register 0x01(test).
  on OPL3 this bit is ignored and 4-waveform select works *always*.
  (Don't confuse this with OPL3's 8-waveform select.)

- Envelope Generator: all 15 x rates take zero time on OPL3
  (on OPL2 15 0 and 15 1 rates take some time while 15 2 and 15 3 rates
  take zero time)

- channel calculations: output of operator 1 is in perfect sync with
  output of operator 2 on OPL3; on OPL and OPL2 output of operator 1
  is always delayed by one sample compared to output of operator 2


differences between OPL2 and OPL3 shown in datasheets:
- YMF262 does not support CSM mode


*/

//#include "stdafx.h"
#include <string.h>
#include <sys.h>
#include "ymf262.h"

#define PITCH_COEF	1154
//#define PITCH_COEF	 1024

#define FREQ_SH         16  /* 16.16 fixed point (frequency calculations) */
#define EG_SH           16  /* 16.16 fixed point (EG timing)              */
#define TIMER_SH        16  /* 16.16 fixed point (timers calculations)    */

#define FREQ_MASK       ((1<<FREQ_SH)-1)

OPL3 chip = {0xcc, 0xcd};

/* mapping of register number (offset) to slot number used by the emulator */
static const int8_t slot_array[32] = { 0, 2, 4, 1, 3, 5,-1,-1, 6, 8,10, 7, 9,11,-1,-1, 12,14,16,13,15,17,-1,-1, -1,-1,-1,-1,-1,-1,-1,-1 }; 
static const uint8_t ksl_tab[8 * 16] = { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,12,16,20,24,28,32,0,0,0,0,0,12,20,28,32,40,44,48,52,56,60,64,0,0,0,20,32,44,52,60,64,72,76,80,84,88,92,96,0,0,32,52,64,76,84,92,96,104,108,112,116,120,124,128,0,32,64,84,96,108,116,124,128,136,140,144,148,152,156,160,0,64,96,116,128,140,148,156,160,168,172,176,180,184,188,192,0,96,128,148,160,172,180,188,192,200,204,208,212,216,220,224 };
static const uint8_t ksl_shift[4] = { 31, 1, 2, 0 };
static const uint8_t sl_tab[16] = { 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 248 };

static const uint8_t eg_rate_select[16 + 64 + 16] = { 112,112,112,112,112,112,112,112,112,112,112,112,112,112,112,112,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,0,8,16,24,32,40,48,56,64,72,80,88,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96,96 };
static const uint8_t eg_rate_shift[16 + 64 + 16] = { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,12,12,12,11,11,11,11,10,10,10,10,9,9,9,9,8,8,8,8,7,7,7,7,6,6,6,6,5,5,5,5,4,4,4,4,3,3,3,3,2,2,2,2,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 };
static const uint8_t mul_tab[16]= {	1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30 }; /* multiple table */


static void FM_KEYON(OPL3_SLOT *SLOT, uint8_t key_set)
{
	if( !SLOT->key )
	{
		SLOT->Cnt = 0; /* restart Phase Generator */
		SLOT->state = EG_ATT; /* phase -> Attack */
	}
	SLOT->key |= key_set;
}

static void FM_KEYOFF(OPL3_SLOT *SLOT, uint8_t key_clr)
{
	if( SLOT->key )
	{
		SLOT->key &= key_clr;
		if( !SLOT->key ) 
			if (SLOT->state>EG_REL) SLOT->state = EG_REL; /* phase -> Release */
	}
}

/* update phase increment counter of operator (also update the EG rates if necessary) */
static void CALC_FCSLOT(OPL3_CH *CH, OPL3_SLOT *SLOT)
{
	uint8_t ksr;

	/* (frequency) phase increment counter */
	uint8_t shift = 7 - (CH->block_fnum >> 10);
	SLOT->Incr = ((CH->block_fnum & 0x03ff) * (uint32_t)SLOT->mul << 2) >> shift;
	ksr = CH->kcode >> SLOT->KSR;

	if( SLOT->ksr != ksr )
	{
		SLOT->ksr = ksr;
		ksr += SLOT->ar;
		/* calculate envelope generator rates */
		if (ksr < 16+60)
		{
			SLOT->eg_sh_ar  = eg_rate_shift [ksr];
			SLOT->eg_sel_ar = eg_rate_select[ksr];
		}
		else
		{
			SLOT->eg_sh_ar  = 0;
			SLOT->eg_sel_ar = 13*RATE_STEPS;
		}
		ksr = SLOT->dr + SLOT->ksr;
		SLOT->eg_sh_dr  = eg_rate_shift [ksr];
		SLOT->eg_sel_dr = eg_rate_select[ksr];
		ksr = SLOT->rr + SLOT->ksr;
		SLOT->eg_sh_rr  = eg_rate_shift [ksr];
		SLOT->eg_sel_rr = eg_rate_select[ksr];
	}
}

/* set multi,am,vib,EG-TYP,KSR,mul */
static void set_mul(uint8_t slot, uint8_t v)
{
	OPL3_CH   *CH   = &chip.P_CH[slot >> 1];
	OPL3_SLOT *SLOT = (slot & 1) ? &CH->SLOT1 : &CH->SLOT0;

	SLOT->mul     = PITCH_COEF*mul_tab[v & 0x0f];
	SLOT->KSR     = (v & 0x10) ? 0 : 2;
	SLOT->eg_type = !!(v & 0x20);
	SLOT->vib     = !!(v & 0x40);
	SLOT->AMmask_TLL = ((uint16_t)(v & 0x80) << 8) + (SLOT->AMmask_TLL & 0x7fff);

	if (chip.OPL3_mode)
	{
		int8_t chan_no = slot >> 1;

		switch(chan_no)
		{
		case 0: case 1: case 2:
		case 9: case 10: case 11:
			if (CH->extended) CALC_FCSLOT(CH,SLOT); /* normal */
			else CALC_FCSLOT(CH,SLOT); /* normal */
		break;
		case 3: case 4: case 5:
		case 12: case 13: case 14:
			if ((CH-3)->extended) CALC_FCSLOT(CH-3,SLOT); /* update this SLOT using frequency data for 1st channel of a pair */
			else CALC_FCSLOT(CH,SLOT); /* normal */
		break;
		default: 
			CALC_FCSLOT(CH,SLOT); /* normal */
			break;
		}
	}
	else CALC_FCSLOT(CH,SLOT); /* in OPL2 mode */
}

/* set ksl & tl */
static void set_ksl_tl(uint8_t slot, uint8_t v)
{
	OPL3_CH   *CH   = &chip.P_CH[slot >> 1];
	OPL3_SLOT *SLOT = (slot & 1)  ? &CH->SLOT1 : &CH->SLOT0;

	SLOT->ksl = ksl_shift[v >> 6];
	SLOT->TL  = (v & 0x3f) << (ENV_BITS-1-7); /* 7 bits TL (bit 6 = always 0) */
	SLOT->AMmask_TLL = SLOT->TL + (CH->ksl_base >> SLOT->ksl) + (SLOT->AMmask_TLL & 0x8000);

	if (chip.OPL3_mode)
	{
		uint8_t chan_no = slot >> 2;

		switch(chan_no)
		{
			case 3: case 4: case 5:
			case 12: case 13: case 14:
				if ((CH-3)->extended) SLOT->AMmask_TLL = SLOT->TL + ((CH-3)->ksl_base>>SLOT->ksl) + (SLOT->AMmask_TLL & 0x8000); /* update this SLOT using frequency data for 1st channel of a pair */
			break;
		}
	}
}

/* set attack rate & decay rate  */
static void set_ar_dr(uint8_t slot, uint8_t v)
{
	OPL3_CH   *CH   = &chip.P_CH[slot >> 1];
	OPL3_SLOT *SLOT = (slot & 1) ? &CH->SLOT1 : &CH->SLOT0;
	uint8_t ksr;
	SLOT->ar = (v & 0xf0) ? 16 + ((v & 0xf0) >> 2) : 0;

	ksr = SLOT->ar + SLOT->ksr;
	if (ksr < 16+60) /* verified on real YMF262 - all 15 x rates take "zero" time */
	{
		SLOT->eg_sh_ar  = eg_rate_shift [ksr];
		SLOT->eg_sel_ar = eg_rate_select[ksr];
	}
	else
	{
		SLOT->eg_sh_ar  = 0;
		SLOT->eg_sel_ar = 13*RATE_STEPS;
	}
	
	SLOT->dr    = (v&0x0f) ? 16 + ((v&0x0f)<<2) : 0;
	ksr = SLOT->dr + SLOT->ksr;
	SLOT->eg_sh_dr  = eg_rate_shift [ksr];
	SLOT->eg_sel_dr = eg_rate_select[ksr];
}

/* set sustain level & release rate */
static void set_sl_rr(uint8_t slot, uint8_t v)
{
	OPL3_CH   *CH   = &chip.P_CH[slot >> 1];
	OPL3_SLOT *SLOT = (slot & 1) ? &CH->SLOT1 : &CH->SLOT0;
	uint8_t ksr = SLOT->ksr;
	SLOT->sl  = (uint16_t)sl_tab[ v>>4 ] << 1;
	SLOT->rr  = (v&0x0f) ? 16 + ((v&0x0f)<<2) : 0;
	ksr += SLOT->rr;
	SLOT->eg_sh_rr  = eg_rate_shift [ksr];
	SLOT->eg_sel_rr = eg_rate_select[ksr];
}

void fn_a0(uint16_t r, uint8_t v, uint8_t ch_offset)
{
	OPL3_CH *CH;
	uint16_t block_fnum;

	if (r == 0xbd)          /* am depth, vibrato depth, r,bd,sd,tom,tc,hh */
	{
		if (ch_offset != 0) return; /* 0xbd register is present in set #1 only */

		chip.lfo_am_depth = !!(v & 0x80);
		chip.lfo_pm_depth_range = (v & 0x40) ? 8 : 0;
		chip.rhythm = !!(v & 0x20);

		if (chip.rhythm)
		{
			/* BD key on/off */
			if (v & 0x10)
			{
				FM_KEYON(&chip.P_CH[6].SLOT0, 2);
				FM_KEYON(&chip.P_CH[6].SLOT1, 2);
			}
			else
			{
				FM_KEYOFF(&chip.P_CH[6].SLOT0, ~2);
				FM_KEYOFF(&chip.P_CH[6].SLOT1, ~2);
			}
			/* HH key on/off */
			if (v & 0x01) FM_KEYON(&chip.P_CH[7].SLOT0, 2);
			else       FM_KEYOFF(&chip.P_CH[7].SLOT0, ~2);
			/* SD key on/off */
			if (v & 0x08) FM_KEYON(&chip.P_CH[7].SLOT1, 2);
			else       FM_KEYOFF(&chip.P_CH[7].SLOT1, ~2);
			/* TOM key on/off */
			if (v & 0x04) FM_KEYON(&chip.P_CH[8].SLOT0, 2);
			else       FM_KEYOFF(&chip.P_CH[8].SLOT0, ~2);
			/* TOP-CY key on/off */
			if (v & 0x02) FM_KEYON(&chip.P_CH[8].SLOT1, 2);
			else       FM_KEYOFF(&chip.P_CH[8].SLOT1, ~2);
		}
		else
		{
			/* BD key off */
			FM_KEYOFF(&chip.P_CH[6].SLOT0, ~2);
			FM_KEYOFF(&chip.P_CH[6].SLOT1, ~2);
			/* HH key off */
			FM_KEYOFF(&chip.P_CH[7].SLOT0, ~2);
			/* SD key off */
			FM_KEYOFF(&chip.P_CH[7].SLOT1, ~2);
			/* TOM key off */
			FM_KEYOFF(&chip.P_CH[8].SLOT0, ~2);
			/* TOP-CY off */
			FM_KEYOFF(&chip.P_CH[8].SLOT1, ~2);
		}
		return;
	}

	/* keyon,block,fnum */
	if ((r & 0x0f) > 8) return;
	CH = &chip.P_CH[(r & 0x0f) + ch_offset];

	if (!(r & 0x10)) block_fnum = (CH->block_fnum & 0x1f00) | v; /* a0-a8 */
	else
	{   /* b0-b8 */
		block_fnum = ((v & 0x1f) << 8) | (CH->block_fnum & 0xff);

		if (chip.OPL3_mode)
		{
			uint8_t chan_no = (r & 0x0f) + ch_offset;
			switch (chan_no)
			{
			case 0: case 1: case 2:
			case 9: case 10: case 11:
				if (CH->extended)
				{
					if (v & 0x20)
					{
						FM_KEYON(&CH->SLOT0, 1);
						FM_KEYON(&CH->SLOT1, 1);
						FM_KEYON(&(CH + 3)->SLOT0, 1);
						FM_KEYON(&(CH + 3)->SLOT1, 1);
					}
					else
					{
						FM_KEYOFF(&CH->SLOT0, ~1);
						FM_KEYOFF(&CH->SLOT1, ~1);
						FM_KEYOFF(&(CH + 3)->SLOT0, ~1);
						FM_KEYOFF(&(CH + 3)->SLOT1, ~1);
					}
				}
				else
				{
					if (v & 0x20)
					{
						FM_KEYON(&CH->SLOT0, 1);
						FM_KEYON(&CH->SLOT1, 1);
					}
					else
					{
						FM_KEYOFF(&CH->SLOT0, ~1);
						FM_KEYOFF(&CH->SLOT1, ~1);
					}
				}
				break;

			case 3: case 4: case 5:
			case 12: case 13: case 14:
				if ((CH - 3)->extended)
				{
					//if this is 2nd channel forming up 4-op channel just do nothing
				}
				else
				{
					if (v & 0x20)
					{
						FM_KEYON(&CH->SLOT0, 1);
						FM_KEYON(&CH->SLOT1, 1);
					}
					else
					{
						FM_KEYOFF(&CH->SLOT0, ~1);
						FM_KEYOFF(&CH->SLOT1, ~1);
					}
				}
				break;

			default:
				if (v & 0x20)
				{
					FM_KEYON(&CH->SLOT0, 1);
					FM_KEYON(&CH->SLOT1, 1);
				}
				else
				{
					FM_KEYOFF(&CH->SLOT0, ~1);
					FM_KEYOFF(&CH->SLOT1, ~1);
				}
				break;
			}
		}
		else
		{
			if (v & 0x20)
			{
				FM_KEYON(&CH->SLOT0, 1);
				FM_KEYON(&CH->SLOT1, 1);
			}
			else
			{
				FM_KEYOFF(&CH->SLOT0, ~1);
				FM_KEYOFF(&CH->SLOT1, ~1);
			}
		}
	}
	/* update */
	if (CH->block_fnum != block_fnum)
	{
		CH->block_fnum = block_fnum;
		CH->ksl_base = ksl_tab[block_fnum >> 6];

		/* BLK 2,1,0 bits -> bits 3,2,1 of kcode */
		CH->kcode = (CH->block_fnum & 0x1c00) >> 9;

		/* the info below is actually opposite to what is stated in the Manuals (verifed on real YMF262) */
		/* if notesel == 0 -> lsb of kcode is bit 10 (MSB) of fnum  */
		/* if notesel == 1 -> lsb of kcode is bit 9 (MSB-1) of fnum */
		if (chip.nts & 0x40) CH->kcode |= (CH->block_fnum >> 8) & 1; /* notesel == 1 */
		else CH->kcode |= (CH->block_fnum >> 9) & 1; /* notesel == 0 */

		if (chip.OPL3_mode)
		{
			uint8_t chan_no = (r & 0x0f) + ch_offset;
			switch (chan_no)
			{
				case 0: case 1: case 2:
				case 9: case 10: case 11:
					if (CH->extended)
					{
						/* refresh Total Level in FOUR SLOTs of this channel and channel+3 using data from THIS channel */
						(CH + 3)->SLOT0.AMmask_TLL = (CH + 3)->SLOT0.TL + (CH->ksl_base >> (CH + 3)->SLOT0.ksl) + ((CH + 3)->SLOT0.AMmask_TLL & 0x8000);
						(CH + 3)->SLOT1.AMmask_TLL = (CH + 3)->SLOT1.TL + (CH->ksl_base >> (CH + 3)->SLOT1.ksl) + ((CH + 3)->SLOT1.AMmask_TLL & 0x8000);

						/* refresh frequency counter in FOUR SLOTs of this channel and channel+3 using data from THIS channel */
						CALC_FCSLOT(CH, &(CH + 3)->SLOT0);
						CALC_FCSLOT(CH, &(CH + 3)->SLOT1);
					}
					break;

				case 3: case 4: case 5:
				case 12: case 13: case 14:
					if ((CH - 3)->extended) return;  //if this is 2nd channel forming up 4-op channel just do nothing
					break;
			}
		}
		/* in OPL2 mode */
		/* refresh Total Level in both SLOTs of this channel */
		CH->SLOT0.AMmask_TLL = CH->SLOT0.TL + (CH->ksl_base >> CH->SLOT0.ksl) + (CH->SLOT0.AMmask_TLL & 0x8000);
		CH->SLOT1.AMmask_TLL = CH->SLOT1.TL + (CH->ksl_base >> CH->SLOT1.ksl) + (CH->SLOT1.AMmask_TLL & 0x8000);

		/* refresh frequency counter in both SLOTs of this channel */
		CALC_FCSLOT(CH, &CH->SLOT0);
		CALC_FCSLOT(CH, &CH->SLOT1);
	}
}

uint16_t packptr16(void *ptr)
{
	uint16_t v;
	uint16_t i = (uint8_t*)ptr - (uint8_t*)&chip;
	uint8_t j;
	for (j = 0; i >= 96; i -= 96, j++);
	v = (uint16_t)j << 7;
	j = i & 0xff;
	if (j >= 48) j -= 48, v |= 64;
	return v | j;
}

/* write a value v to register r on OPL chip */
static void OPL3WriteReg(uint16_t r, uint8_t v)
{
	OPL3_CH *CH;
	uint8_t ch_offset = 0, base;
	int8_t slot;
	uint32_t mask;

	if(r & 0x100)
	{
		switch(r)
		{
		case 0x101: return; /* test register */

		case 0x104: /* 6 channels enable */
			{
				CH = &chip.P_CH[0];    /* channel 0 */
				CH->extended = v & 1;
				CH++;                   /* channel 1 */
				CH->extended = (v>>=1) & 1;
				CH++;                   /* channel 2 */
				CH->extended = (v>>=1) & 1;
				CH = &chip.P_CH[9];    /* channel 9 */
				CH->extended = (v>>=1) & 1;
				CH++;                   /* channel 10 */
				CH->extended = (v>>=1) & 1;
				CH++;                   /* channel 11 */
				CH->extended = (v>>1) & 1;
			}
			return;

		case 0x105: /* OPL3 extensions enable register */
			chip.OPL3_mode = v & 0x01;   /* OPL3 mode when bit0=1 otherwise it is OPL2 mode */
			return;
		}
		ch_offset = 9;  /* register page #2 starts from channel 9 (counting from 0) */
	}

	r &= 0xff; /* adjust bus to 8 bits */

	switch(r & 0xe0)
	{
	case 0x00:  /* 00-1f:control */
		switch(r & 0x1f)
		{
		case 0x01:  /* test register */
		break;
		case 0x02:  /* Timer 1 */
		break;
		case 0x03:  /* Timer 2 */
		break;
		case 0x04:  /* IRQ clear / mask and Timer enable */
		break;
		case 0x08:  /* x,NTS,x,x, x,x,x,x */
			chip.nts = v;
			break;
		}
		break;
	case 0x20:  /* am ON, vib ON, ksr, eg_type, mul */
		slot = slot_array[r & 0x1f];
		if(slot < 0) return;
		set_mul(slot + ch_offset*2, v);
	break;
	case 0x40:
		slot = slot_array[r & 0x1f];
		if(slot < 0) return;
		set_ksl_tl(slot + ch_offset*2, v);
	break;
	case 0x60:
		slot = slot_array[r&0x1f];
		if(slot < 0) return;
		set_ar_dr(slot + ch_offset*2, v);
	break;
	case 0x80:
		slot = slot_array[r&0x1f];
		if(slot < 0) return;
		set_sl_rr(slot + ch_offset*2, v);
	break;
	case 0xa0:
		fn_a0(r, v, ch_offset);
		break;

	case 0xc0:
		/* CH.D, CH.C, CH.B, CH.A, FB(3bits), C */
		if( (r & 0xf) > 8) return;
		CH = &chip.P_CH[(r & 0xf) + ch_offset];
		base = (r & 0xf) + ch_offset;
		mask = 1l << base;

		if (chip.OPL3_mode) /* OPL3 mode */
		{
			chip.panA = (chip.panA & ~mask) | ((uint32_t)((v & 0x10) >> 4) << base);
			chip.panB = (chip.panB & ~mask) | ((uint32_t)((v & 0x20) >> 5) << base);
//			chip.pan[ base    ] = (v & 0x10) != 0; /* ch.A */
//			chip.pan[ base +1 ] = (v & 0x20) != 0; /* ch.B */
//			chip.pan[ base +2 ] = (v & 0x40) != 0; /* ch.C */
//			chip.pan[ base +3 ] = (v & 0x80) != 0; /* ch.D */
		}
		else /* OPL2 mode - always enabled */
		{
			chip.panA |= mask;
			chip.panB |= mask;
//			chip.pan[ base    ] = 1;      /* ch.A */
//			chip.pan[ base +1 ] = 1;      /* ch.B */
//			chip.pan[ base +2 ] = 1;      /* ch.C */
//			chip.pan[ base +3 ] = 1;      /* ch.D */
		}
		CH->SLOT0.FB  = (v & 0xe) ? 9 - ((v & 0xe) >> 1) : 0;
		CH->SLOT0.CON = v & 1;

		if( chip.OPL3_mode )
		{
			uint8_t chan_no = (r & 0x0f) + ch_offset;

			switch(chan_no)
			{
			case 0: case 1: case 2:
			case 9: case 10: case 11:
				if (CH->extended)
				{
					uint8_t conn = (CH->SLOT0.CON << 1) | (CH+3)->SLOT0.CON;
					switch(conn)
					{
					case 0:
						/* 1 -> 2 -> 3 -> 4 - out */
						CH->SLOT0.connect = packptr16(&chip.phase_modulation);
						CH->SLOT1.connect = packptr16(&chip.phase_modulation2);
						(CH+3)->SLOT0.connect = packptr16(&chip.phase_modulation);
						(CH + 3)->SLOT1.connect = packptr16(&chip.P_CH[chan_no + 3].chanout);// chanout[chan_no + 3];
					break;
					case 1:
						/* 1 -> 2 -\
						   3 -> 4 -+- out */
						CH->SLOT0.connect = packptr16(&chip.phase_modulation);
						CH->SLOT1.connect = packptr16(&chip.P_CH[chan_no].chanout); // chanout[chan_no];
						(CH+3)->SLOT0.connect = packptr16(&chip.phase_modulation);
						(CH+3)->SLOT1.connect = packptr16(&chip.P_CH[chan_no + 3].chanout);
					break;
					case 2:
						/* 1 -----------\
						   2 -> 3 -> 4 -+- out */
						CH->SLOT0.connect = packptr16(&chip.P_CH[chan_no].chanout);
						CH->SLOT1.connect = packptr16(&chip.phase_modulation2);
						(CH+3)->SLOT0.connect = packptr16(&chip.phase_modulation);
						(CH+3)->SLOT1.connect = packptr16(&chip.P_CH[chan_no + 3].chanout);
					break;
					case 3:
						/* 1 ------\
						   2 -> 3 -+- out
						   4 ------/     */
						CH->SLOT0.connect = packptr16(&chip.P_CH[chan_no].chanout);
						CH->SLOT1.connect = packptr16(&chip.phase_modulation2);
						(CH+3)->SLOT0.connect = packptr16(&chip.P_CH[chan_no + 3].chanout);
						(CH+3)->SLOT1.connect = packptr16(&chip.P_CH[chan_no + 3].chanout);
					break;
					}
				}
				else
				{
					/* 2 operators mode */
					CH->SLOT0.connect = packptr16(CH->SLOT0.CON ? &chip.P_CH[(r & 0xf) + ch_offset].chanout : &chip.phase_modulation);
					CH->SLOT1.connect = packptr16(&chip.P_CH[(r & 0xf) + ch_offset].chanout);
				}
			break;

			case 3: case 4: case 5:
			case 12: case 13: case 14:
				if ((CH-3)->extended)
				{
					uint8_t conn = ((CH-3)->SLOT0.CON << 1) | CH->SLOT0.CON;
					switch(conn)
					{
					case 0:
						/* 1 -> 2 -> 3 -> 4 - out */
						(CH-3)->SLOT0.connect = packptr16(&chip.phase_modulation);
						(CH-3)->SLOT1.connect = packptr16(&chip.phase_modulation2);
						CH->SLOT0.connect = packptr16(&chip.phase_modulation);
						CH->SLOT1.connect = packptr16(&chip.P_CH[ chan_no ].chanout);
					break;
					case 1:
						/* 1 -> 2 -\
						   3 -> 4 -+- out */
						(CH-3)->SLOT0.connect = packptr16(&chip.phase_modulation);
						(CH-3)->SLOT1.connect = packptr16(&chip.P_CH[ chan_no - 3 ].chanout);
						CH->SLOT0.connect = packptr16(&chip.phase_modulation);
						CH->SLOT1.connect = packptr16(&chip.P_CH[ chan_no ].chanout);
					break;
					case 2:
						/* 1 -----------\
						   2 -> 3 -> 4 -+- out */
						(CH-3)->SLOT0.connect = packptr16(&chip.P_CH[ chan_no - 3 ].chanout);
						(CH-3)->SLOT1.connect = packptr16(&chip.phase_modulation2);
						CH->SLOT0.connect = packptr16(&chip.phase_modulation);
						CH->SLOT1.connect = packptr16(&chip.P_CH[ chan_no ].chanout);
					break;
					case 3:
						/* 1 ------\
						   2 -> 3 -+- out
						   4 ------/     */
						(CH-3)->SLOT0.connect = packptr16(&chip.P_CH[ chan_no - 3 ].chanout);
						(CH-3)->SLOT1.connect = packptr16(&chip.phase_modulation2);
						CH->SLOT0.connect = packptr16(&chip.P_CH[ chan_no ].chanout);
						CH->SLOT1.connect = packptr16(&chip.P_CH[ chan_no ].chanout);
					break;
					}
				}
				else
				{
					/* 2 operators mode */
					CH->SLOT0.connect = packptr16(CH->SLOT0.CON ? &chip.P_CH[(r & 0xf) + ch_offset].chanout : &chip.phase_modulation);
					CH->SLOT1.connect = packptr16(&chip.P_CH[(r & 0xf)+ch_offset].chanout);
				}
			break;

			default:
					/* 2 operators mode */
					CH->SLOT0.connect = packptr16(CH->SLOT0.CON ? &chip.P_CH[(r & 0xf) + ch_offset].chanout : &chip.phase_modulation);
					CH->SLOT1.connect = packptr16(&chip.P_CH[(r & 0xf) + ch_offset].chanout);
			break;
			}
		}
		else
		{
			/* OPL2 mode - always 2 operators mode */
			CH->SLOT0.connect = packptr16(CH->SLOT0.CON ? &chip.P_CH[(r&0xf)+ch_offset].chanout : &chip.phase_modulation);
			CH->SLOT1.connect = packptr16(&chip.P_CH[(r&0xf)+ch_offset].chanout);
		}
	break;

	case 0xe0: /* waveform select */
		slot = slot_array[r&0x1f];
		if(slot < 0) return;

		slot += ch_offset*2;
		CH = &chip.P_CH[slot >> 1];

		/* store 3-bit value written regardless of current OPL2 or OPL3 mode... (verified on real YMF262) */
		v &= 7;
		if(slot & 1) CH->SLOT1.waveform_number = v;
		else CH->SLOT0.waveform_number = v;

		/* ... but select only waveforms 0-3 in OPL2 mode */
		if( !chip.OPL3_mode ) v &= 3; /* we're in OPL2 mode */
		if(slot & 1) CH->SLOT1.wavetable = v;
		else CH->SLOT0.wavetable = v;
	break;
	}
}

void OPL3ResetChip()
{
	uint16_t c;

//	eg_cnt   = 0;
//	noise_rng = 1;    /* noise shift register */
	memset(&chip, 0, sizeof(chip));
	for(c = 0xff ; c >= 0x20 ; c-- ) OPL3WriteReg(c, 0);
	for(c = 0x1ff ; c >= 0x120 ; c-- ) OPL3WriteReg(c, 0);

	/* reset operator parameters */
	for( c = 0 ; c < 9*2 ; c++ )
	{
		OPL3_CH *CH       = &chip.P_CH[c];
		CH->SLOT0.state   = EG_OFF;
		CH->SLOT0.volume  = MAX_ATT_INDEX;
		CH->SLOT1.state	  = EG_OFF;
		CH->SLOT1.volume  = MAX_ATT_INDEX;
	}
	
	c = (uint16_t)&chip;
	outp(0, (uint8_t)c);
	outp(1, (uint8_t)(c>>8));
}

/* YMF262 I/O interface */
void OPL3Write(uint8_t a, uint8_t v)
{
	switch(a&3)
	{
	case 0: /* address port 0 (register set #1) */
		chip.address = v;
		break;

	case 1: /* data port - ignore A1 */
	case 3: /* data port - ignore A1 */
//		if(chip->UpdateHandler) chip->UpdateHandler(chip->UpdateParam,0);
		OPL3WriteReg(chip.address, v);
	break;

	case 2: /* address port 1 (register set #2) */
		if( chip.OPL3_mode ) chip.address = v | 0x100; /* OPL3 mode */
		else
		{
			if( v==5 ) chip.address = v | 0x100; /* in OPL2 mode the only accessible in set #2 is register 0x05 */
			else chip.address = v;  /* verified range: 0x01, 0x04, 0x20-0xef(set #2 becomes set #1 in opl2 mode) */
		}
		break;
	}
}

#define READY 1
#define QEMPTY 2

int main()
{
	uint8_t c;
	OPL3ResetChip();

	while(1)
	{
		c = inp(0);
		if((c & 3) == READY) OPL3Write((c >> 2) & 3, inp(1));
	}
}

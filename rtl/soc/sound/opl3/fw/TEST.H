#define delay(x) Sleep(x)

const //List of FNumbers
uint16_t FNr[12] = {
	/*C*/     343,
	/*C#/Db*/ 363,
	/*D*/     385,
	/*D#/Eb*/ 408,
	/*E*/     432,
	/*F*/     458,
	/*F#/Gb*/ 485,
	/*G*/     514,
	/*G#/Ab*/ 544,
	/*A*/     577,
	/*A#/Bb*/ 611,
	/*B*/     647 };

//Flat              Whole         Sharp}
#define C  0 
#define CSharp  1
#define DFlat  1 
#define D  2 
#define DSharp  3
#define EFlat  3 
#define E  4
#define F  5 
#define FSharp  6
#define GFlat  6 
#define G  7 
#define GSharp  8
#define AFlat  8 
#define A  9 
#define ASharp  10
#define BFlat  10 
#define B  11


struct Operator {
	uint8_t
		//Tremolo
		Tremolo,
		//Vibrato
		Vibrato,
		//Envelop generator type
		EGType,
		//KSR
		KSR,
		//Frequency multiplier
		Multi,
		//Key scaling level
		KSL,
		//Volume
		TotalLevel,
		//Shape of the wave envelop
		Attack, Decay, Sustain, Release,
		//Type of wave
		WaveShape;
};

struct Instrument {
	struct Operator Modulator, Carrier;

	uint8_t
		//Feedback strength
		Feedback,
		//Synthesis type
		SynType;
};


struct Instrument   Flute, Piano, Harp;
uint8_t       CurNote, CurBlock;

/**************************************************************************
** Writes a value to a specified index register on the FM card           **
**************************************************************************/
void WriteFM(uint8_t Register, uint8_t Value)
{
	OPL3Write(0, Register);
	OPL3Write(1, Value);

//	unsigned char Counter;

	//Select register
//	outportb(0x388, Register);
	//Wait for card to accept value
//	for (Counter = 1; Counter < 25; Counter++) { inportb(0x388); }
	//Send value
//	outportb(0x389, Value);
	//Wait for card to accept value
//	for (Counter = 1; Counter < 100; Counter++) { inportb(0x388); }
}

/**************************************************************************
** Checks for the presence of an FM card                                 **
**************************************************************************/
uint8_t FMInstalled()
{

//	unsigned char A, B;

//	WriteFM(1, 0);
//	WriteFM(4, 0x60);
//	WriteFM(4, 0x80);
//	A = inportb(0x388);
//	A = OPL3Read(0);
//	WriteFM(2, 0xFF);
//	WriteFM(4, 0x21);
//	B = inportb(0x388);
//	OPL3TimerOver(0);
//	B = OPL3Read(0);
//	WriteFM(4, 0x60);
//	WriteFM(4, 0x80);
//	if ((A & 0xE0) == 0 && (B & 0xE0) == 0xC0) {
		return (1);
//	}
//	else {
//		return (0);
//	}
}

/**************************************************************************
** Activates a voice on the FM card                                      **
***************************************************************************
** Voice selects one of the 9 FM voices                                  **
** FNumber selects the note to be played                                 **
** Block selects the octave for the specified note                       **
**************************************************************************/
void NoteOn(uint8_t Voice, uint8_t Note, uint8_t Block)
{
	WriteFM(0xA0 + Voice, FNr[Note] & 0xFF);
	WriteFM(0xB0 + Voice, (FNr[Note] >> 8) + (Block << 2) + 32);
}

/**************************************************************************
** Deactivates a voice on the FM card                                    **
***************************************************************************
** Make sure to give the same values for Note and Block or this will     **
** sound very odd.                                                       **
**************************************************************************/
void NoteOff(uint8_t Voice, uint8_t Note, uint8_t Block)
{
	WriteFM(0xA0 + Voice, FNr[Note] & 0xFF);
	WriteFM(0xB0 + Voice, (FNr[Note] >> 8) + (Block << 2));
}

/**************************************************************************
** Sets instrument settings for a voice on the FM card                   **
**************************************************************************/
const static unsigned char OpAdr[9] = { 0, 1, 2, 8, 9, 10, 16, 17, 18 }; //Addresses of the operators used to form voice data
void SetInstrument(uint8_t Voice, struct Instrument *Instr)
{
	uint8_t Value;

	//Set up voice modulator
	Value = Instr->Modulator.Tremolo << 8
		| Instr->Modulator.Vibrato << 7
		| Instr->Modulator.EGType << 6
		| Instr->Modulator.KSR << 5
		| Instr->Modulator.Multi;
	WriteFM(0x20 + OpAdr[Voice], Value);

	Value = Instr->Modulator.KSL << 7
		| Instr->Modulator.TotalLevel;
	WriteFM(0x40 + OpAdr[Voice], Value);

	Value = Instr->Modulator.Attack << 4
		| Instr->Modulator.Decay;
	WriteFM(0x60 + OpAdr[Voice], Value);

	Value = Instr->Modulator.Sustain << 4
		| Instr->Modulator.Release;
	WriteFM(0x80 + OpAdr[Voice], Value);

	WriteFM(0xE0 + OpAdr[Voice], Instr->Modulator.WaveShape);

	Value = Instr->Feedback << 1
		| Instr->SynType;
	WriteFM(0xC0 + OpAdr[Voice], Value);

	//Set up voice carrier
	Value = Instr->Carrier.Tremolo << 8
		| Instr->Carrier.Vibrato << 7
		| Instr->Carrier.EGType << 6
		| Instr->Carrier.KSR << 5
		| Instr->Carrier.Multi;
	WriteFM(0x23 + OpAdr[Voice], Value);

	Value = Instr->Carrier.KSL << 7
		| Instr->Carrier.TotalLevel;
	WriteFM(0x43 + OpAdr[Voice], Value);

	Value = Instr->Carrier.Attack << 4
		| Instr->Carrier.Decay;
	WriteFM(0x63 + OpAdr[Voice], Value);

	Value = Instr->Carrier.Sustain << 4
		| Instr->Carrier.Release;
	WriteFM(0x83 + OpAdr[Voice], Value);

	WriteFM(0xE3 + OpAdr[Voice], Instr->Carrier.WaveShape);
}

void test()
{
	//	clrscr();
again:
	printf("Demonstration of programming a FM sound card [AdLib, SB and compatibles]\n");
	printf("--------------------------------------------------------------------------\n");

	//Check to see if an FM sound card is present
/*	if (FMInstalled()) {
		printf("AdLib/SB or compatible FM sound card found.\n");
	}
	else {
		//If not, end the programme
		printf("AdLib/SB or compatible FM sound card not found.\n");
		return;
	}
*/
	//Set up voices 0 - 3 to a "harp" - note, only the values other than 0 are set
	Harp.Modulator.Attack = 15;
	Harp.Modulator.Decay = 5;
	Harp.Modulator.Sustain = 8;
	Harp.Modulator.Release = 5;
	Harp.Modulator.Multi = 2;
	Harp.Modulator.TotalLevel = 41;

	Harp.Carrier.Attack = 15;
	Harp.Carrier.Decay = 2;
	Harp.Carrier.Release = 3;
	Harp.Carrier.Multi = 1;
	Harp.Carrier.KSL = 2;
	Harp.Carrier.TotalLevel = 3;

	SetInstrument(0, &Harp);
	SetInstrument(1, &Harp);
	SetInstrument(2, &Harp);

	//Play C chord using Harp
	printf("Playing C chord.\n");

	NoteOn(0, C, 4);
	NoteOn(1, E, 4);
	NoteOn(2, G, 4);
	delay(1000); //Wait 1 second
	NoteOff(0, C, 4);
	NoteOff(1, E, 4);
	NoteOff(2, G, 4);
	//Wait a while
	delay(500);

	//Set up voice 3 to a "piano" - this doesn't really sound like a piano,
	//but that's what they call it!
	Piano.Modulator.Attack = 15;
	Piano.Modulator.Decay = 1;
	Piano.Modulator.Sustain = 10;
	Piano.Modulator.Release = 3;
	Piano.Modulator.Multi = 1;
	Piano.Modulator.KSL = 1;
	Piano.Modulator.TotalLevel = 16;

	Piano.Carrier.Attack = 13;
	Piano.Carrier.Decay = 2;
	Piano.Carrier.Sustain = 8;
	Piano.Carrier.Release = 4;
	Piano.Carrier.Multi = 1;
	Piano.Carrier.TotalLevel = 0;
	Piano.Carrier.KSR = 1;

	Piano.Feedback = 3;

	SetInstrument(3, &Piano);

	//Play all notes in octave 4 for .1 seconds using piano [voice 3]
	printf("Playing all notes in octave four.\n");
	CurBlock = 4;
	for (CurNote = 0; CurNote < 12; CurNote++) {
		NoteOn(3, CurNote, CurBlock);
		delay(100); //Wait .1 seconds
		NoteOff(3, CurNote, CurBlock);
	}

	//Wait a while
	delay(500);
	//Set up voice 4 to a "flute"
	Flute.Modulator.Attack = 6;
	Flute.Modulator.Decay = 14;
	Flute.Modulator.Sustain = 7;
	Flute.Modulator.Release = 15;
	Flute.Modulator.Vibrato = 1;
	Flute.Modulator.Tremolo = 1;
	Flute.Modulator.EGType = 1;
	Flute.Modulator.KSL = 3;
	Flute.Modulator.TotalLevel = 44;

	Flute.Carrier.Attack = 6;
	Flute.Carrier.Decay = 5;
	Flute.Carrier.Sustain = 13;
	Flute.Carrier.Release = 10;
	Flute.Carrier.Vibrato = 1;
	Flute.Carrier.EGType = 1;
	Flute.Carrier.Multi = 1;
	Flute.Carrier.TotalLevel = 0;

	Flute.Feedback = 7;
	Flute.SynType = 3;

	SetInstrument(4, &Flute);

	//Play short tune using Flute [voice 4] as primary, Harp [voice 0] as secondary voice
	printf("Playing short tune.\n");

	NoteOn(4, C, 5); NoteOn(0, C, 3);
	delay(250);
	NoteOff(4, C, 5);
	NoteOn(4, E, 5);
	delay(250);
	NoteOff(4, E, 5); NoteOff(0, C, 3);

	NoteOn(4, C, 5); NoteOn(0, G, 3);
	delay(250);
	NoteOff(4, C, 5);
	NoteOn(4, G, 4);
	delay(250);
	NoteOff(4, G, 4); NoteOff(0, G, 3);

	NoteOn(4, E, 4); NoteOn(0, C, 4);
	delay(250);
	NoteOff(4, E, 4);
	NoteOn(4, G, 4);
	delay(250);
	NoteOff(4, G, 4); NoteOff(0, C, 4);

	NoteOn(4, E, 4); NoteOn(0, G, 3);
	delay(250);
	NoteOff(4, E, 4);
	NoteOn(4, D, 4);
	delay(250);
	NoteOff(4, D, 4); NoteOff(0, G, 3);

	NoteOn(4, C, 4); NoteOn(0, C, 3);
	delay(2000);
	NoteOff(4, C, 4); NoteOff(0, C, 3);
	goto again;
}

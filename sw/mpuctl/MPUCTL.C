#include <stdio.h>
#include <conio.h>
#include <string.h>

#define mpu(x) outp(0x330, x)

int main(int argc, char **argv)
{
  if(argc<2)
  {
    printf("usage: mpuctl <reset|clear|munt|fluid> [n]\n");
    printf("  reset - reset MT32-pi\n");
    printf("  clear - reset hanging notes\n");
    printf("  munt  - switch to MUNT synth\n");
    printf("  fluid - switch to FluidSynth\n");
    printf("  n     - (optional) either MUNT ROM or FluidSynth soundfont number\n");
    return -1;
  }
  
  outp(0x331, 0x3F);
  inp(0x330);
  
  if(!strcasecmp(argv[1], "reset"))
  {
	  mpu(0xF0);
	  mpu(0x7D);
	  mpu(0x00);
	  mpu(0xF7);
  }
  else if(!strcasecmp(argv[1], "munt"))
  {
	  mpu(0xF0);
	  mpu(0x7D);
	  mpu(0x03);
	  mpu(0x00);
	  mpu(0xF7);
	  
	  
	  if(argc > 2)
	  {
		  int arg = 0;
		  sscanf(argv[2],"%x", &arg);

		  mpu(0xF0);
		  mpu(0x7D);
		  mpu(0x01);
		  mpu(arg);
		  mpu(0xF7);
	  }
  }
  else if(!strcasecmp(argv[1], "fluid"))
  {
	  mpu(0xF0);
	  mpu(0x7D);
	  mpu(0x03);
	  mpu(0x01);
	  mpu(0xF7);

	  if(argc > 2)
	  {
		  int arg = 0;
		  sscanf(argv[2],"%x", &arg);

		  mpu(0xF0);
		  mpu(0x7D);
		  mpu(0x02);
		  mpu(arg);
		  mpu(0xF7);
	  }
  }
  else if(!strcasecmp(argv[1], "clear"))
  {
	  mpu(0xFF);
	  mpu(0xF0);
	  mpu(0x41);
	  mpu(0x10);
	  mpu(0x16);
	  mpu(0x12);
	  mpu(0x7F);
	  mpu(0x00);
	  mpu(0x00);
	  mpu(0x01);
	  mpu(0xF7);
  }
  else if(!strcasecmp(argv[1], "test"))
  {
	  mpu('m');
	  mpu('p');
	  mpu('u');
	  mpu(' ');
	  mpu('e');
	  mpu('c');
	  mpu('h');
	  mpu('o');
	  mpu(' ');
	  mpu('t');
	  mpu('e');
	  mpu('s');
	  mpu('t');
	  mpu('\r');
	  mpu('\n');
  }

  return 0;
}

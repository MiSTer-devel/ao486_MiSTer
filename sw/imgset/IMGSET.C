#include <stdio.h>
#include <conio.h>
#include <string.h>

char buf[512];

int main(int argc, char **argv)
{
	int i;
	int port = 0x1F0, drv = 0, head = 0;

	if(argc < 3)
	{
		if(argc == 2 && !strcasecmp(argv[1], "r"))
		{
			outp(0x92, 1);
			return 0;
		}

		printf("imgset <drv> <image_path>\n");
		printf("  drv: fdd0,fdd1,ide00,ide01,ide10,ide11\n");
		printf("  image_path: relative to ao486 home path\n");
		printf("\n");
		printf("imgset r\n");
		printf("  reset and insert pending HDD images\n");
		return -1;
	}

	     if(!strcasecmp(argv[1],"fdd0" )) head = 1;
	else if(!strcasecmp(argv[1],"fdd1" )) head = 2;
	else if(!strcasecmp(argv[1],"ide01")) drv = 1;
	else if(!strcasecmp(argv[1],"ide10")) port = 0x170;
	else if(!strcasecmp(argv[1],"ide11"))
	{
		port = 0x170;
		drv = 1;
	}

	_asm { cli }

	outp(port+1, 0);
	outp(port+2, 1);
	outp(port+3, 0);
	outp(port+4, 0);
	outp(port+5, 0);
	outp(port+6, (drv << 4) | head);
	outp(port+7, 0xFA);

	while(inp(port+7) & 0x80);

	i = 0;
	while((i < 511) && argv[2][i]) buf[i++] = argv[2][i];
	while(i < 512) buf[i++] = 0;

	for(i = 0; i < 256; i++) outpw(port, *(unsigned short*)&buf[i*2]);

	while(inp(port+7) & 0x80);

	_asm { sti }

	return 0;
}

#include <stdio.h>
#include <conio.h>
#include <string.h>

#define D90MHZ   0x00
#define D56MHZ   0x03
#define D30MHZ   0x02
#define D15MHZ   0x01
#define DL1CACHE 0x10
#define DL2CACHE 0x20
#define DMENU    0x80

static int _argc;
static char **_argv;

int chk_arg_opt(char * option)
{
    int index;
    for(index = 1; index < _argc; index++)
	if(strcmpi(_argv[index], option) == 0)
	    return index;
    return 0;
}

int main(int argc, char **argv)
{
    int arg = D90MHZ;
    char * argv0;
    char * bs;

    if(argc < 2)
    {
	printf("MiSTer SYSCTL+ 1.0\n");
	printf("USAGE:\n");
	bs = strrchr(argv[0], '\\');
	if(bs == NULL)
	    argv0 = argv[0];
	else
	    argv0 = ++bs;
	printf("%s SYS/MENU 90Mhz/56Mhz/30Mhz/15Mhz L1+/L1- L2+/L2-\n", argv0);
	return -1;
    }

    _argc = argc;
    _argv = argv;

    if (chk_arg_opt("90Mhz") || chk_arg_opt("90"))
	arg = D90MHZ;
    else if (chk_arg_opt("56Mhz") || chk_arg_opt("56"))
	arg = D56MHZ;
    else if (chk_arg_opt("30Mhz") || chk_arg_opt("30"))
	arg = D30MHZ;
    else if (chk_arg_opt("15Mhz") || chk_arg_opt("15"))
	arg = D15MHZ;

    if (chk_arg_opt("SYS") || chk_arg_opt("SYSCTL"))
	arg |= DMENU;
    else if (chk_arg_opt("MENU"))
	arg &= ~DMENU;

    if (chk_arg_opt("L1-"))
	arg |= DL1CACHE;
    else if (chk_arg_opt("L1+"))
	arg &= ~DL1CACHE;

    if (chk_arg_opt("L2-"))
	arg |= DL2CACHE;
    else if (chk_arg_opt("L2+"))
	arg &= ~DL2CACHE;

    outpw(0x8888, 0xA100 | (arg & 0xFF));

    printf("Settings  --> %s\n", (DMENU & arg)?"SYSCTL":"MENU");

    printf("CPU Speed --> ");
    switch(arg & 0x03)
    {
    case D90MHZ:
	printf("90Mhz");
	break;
    case D56MHZ:
	printf("56Mhz");
	break;
    case D30MHZ:
	printf("30Mhz");
	break;
    case D15MHZ:
	printf("15Mhz");
	break;
    default:
	printf("??Mhz");
    }

    printf("\nL1 Cache  --> %s\n", (DL1CACHE & arg)?"OFF":"ON");
    printf("L2 Cache  --> %s\n", (DL2CACHE & arg)?"OFF":"ON");

    return 0;
}

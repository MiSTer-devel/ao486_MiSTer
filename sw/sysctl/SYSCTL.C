#include <stdio.h>
#include <conio.h>

int main(int argc, char **argv)
{
  int arg = 0;

  if(argc<2)
  {
    printf("argument is missing.\n");
    return -1;
  }

  sscanf(argv[1],"%x", &arg);
  outpw(0x8888, 0xA100 | (arg & 0xFF));
  return 0;
}

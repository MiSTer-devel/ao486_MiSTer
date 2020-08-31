#include <stdio.h>
#include <string.h>
#include <conio.h>

int main(int argc, char **argv)
{
  int i;

  if(argc<2)
  {
      printf("argument is missing.\n");
      return -1;
  }

  for(i = 1; i<argc; i++)
  {
     if(!strcasecmp(argv[i], "H5"))
     {
         outpw(0x224, 0x2281);
         continue;
     }

     if(!strcasecmp(argv[i], "H1"))
     {
         outpw(0x224, 0x0281);
         continue;
     }

     if(!strcasecmp(argv[i], "I5"))
     {
         outpw(0x224, 0x0280);
         continue;
     }

     if(!strcasecmp(argv[i], "I7"))
     {
         outpw(0x224, 0x0480);
         continue;
     }
        
     if(!strcasecmp(argv[i], "I10"))
     {
         outpw(0x224, 0x0880);
         continue;
     }
     
     if(!strcasecmp(argv[i], "T4"))
     {
         outpw(0x224, 0xAD80);
         continue;
     }

     if(!strcasecmp(argv[i], "T6"))
     {
         outpw(0x224, 0xAE80);
         continue;
     }

     printf("Invalid parameter. Supported: I5,I7,I10,H5,H1,T4,T6\n");
     return -1;
  }
  return 0;
}

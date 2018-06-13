#include <stdlib.h>
#include <stdio.h>

int main()
{
	int c1,c2,d=1,i;
	FILE *in = fopen("opl3.com", "rb");
	
	for(i=0; i<4096; i++)
	{
		if(i<128)
		{
			switch(i)
			{
				case 0:   printf("00C3\n"); break;
				case 1:   printf("0001\n"); break;
				case 2:   printf("C300\n"); break;
				case 3:   printf("00FF\n"); break;
				case 127: printf("C900\n"); break;
				default:  printf("0000\n"); break;
			}
		}
 		else if(d)
		{
			c1 = fgetc(in);
			if(c1 == -1) 
			{
				d = 0;
				c1 = 0;
				c2 = 0;
			}
			else
			{
				c2 = fgetc(in);
				if(c2 == -1) 
				{
					d = 0;
					c2 = 0;
				}
			}
			printf("%02X%02X\n", c2&0xff, c1&0xff);
		}
		else
		{
			printf("0000\n");
		}
	}
	fclose(in);
}

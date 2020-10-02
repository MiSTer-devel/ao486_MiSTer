all: imgset.exe

imgset.exe: imgset.c
	wcl -q -y -4 -s -d0 -lr -ms -we -wx -k1024 -os imgset.c -fe=imgset.exe

clean:
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak

all: mpuctl.exe

mpuctl.exe: mpuctl.c
	wcl -q -y -4 -s -d0 -lr -ms -we -wx -k1024 -os mpuctl.c -fe=mpuctl.exe

clean:
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak
	if exist *.exe del *.exe

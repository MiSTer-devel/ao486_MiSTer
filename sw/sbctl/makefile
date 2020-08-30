all: sbctl.exe

sbctl.exe: sbctl.c
	wcl -q -y -4 -s -d0 -lr -ms -we -wx -k1024 -os sbctl.c -fe=sbctl.exe

clean:
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak

all: sysctl.exe

sysctl.exe: sysctl.c
	wcl -q -y -4 -s -d0 -lr -ms -we -wx -k1024 -os sysctl.c -fe=sysctl.exe

clean:
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak

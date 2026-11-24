all: ne2ktest.exe

ne2ktest.exe: ne2ktest.c
	wcl -q -y -4 -s -d0 -lr -ms -we -wx -k1024 -os ne2ktest.c -fe=ne2ktest.exe

clean:
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak
	if exist *.exe del *.exe

#
# Makefile for MiSTerFS, requires Open Watcom v2.0
# Copyright (C) 2017 Mateusz Viste
# Copyright (c) 2020 Michael Ortmann
# Copyright (c) 2020 Alexey Melnikov
#

all: misterfs.exe

genmsg.exe: genmsg.c version.h
	wcl386 -q -y -os genmsg.c -fe=genmsg.exe

chint.obj: chint086.asm
	wasm -q -0 chint086.asm -fo=chint.obj -ms

misterfs.exe: genmsg.exe misterfs.c chint.obj dosstruc.h globals.h version.h
	@if not exist msg mkdir msg
	genmsg.exe
	wcl -q -y -0 -s -d0 -lr -ms -we -wx -k1024 -fm=misterfs.map -os chint.obj misterfs.c -fe=misterfs.exe
	upx -9 --8086 misterfs.exe

clean:
#	if exist misterfs.exe del misterfs.exe
	if exist genmsg.exe del genmsg.exe
	if exist *.obj del *.obj
	if exist *.map del *.map
	if exist *.bak del *.bak
	if exist msg rmdir /s /q msg

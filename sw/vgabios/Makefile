#
#  Copyright (C) 2001-2020 The LGPL VGABios developers Team
#

SHELL = /bin/sh

CC      = gcc
CFLAGS  = -g -O2 -Wall -Wstrict-prototypes
LDFLAGS = 

GCC = gcc
BCC = bcc
AS86 = as86

RELEASE = `pwd | sed "s-.*/--"`
RELDATE = `date '+%d %b %Y'`
RELVERS = `pwd | sed "s-.*/--" | sed "s/vgabios//" | sed "s/-//"`

VGABIOS_DATE = "-DVGABIOS_DATE=\"$(RELDATE)\""

all: bios

bios: vgabios.bin

clean:
	rm -f  biossums biossums.exe vbetables-gen vbetables-gen.exe vbetables.h *.o *.s *.ld86 \
          temp.awk.* vgabios*.orig _vgabios_* _vgabios-debug_* core vgabios*.bin vgabios*.txt *.bin *.bak *.rom

# source files
VGA_FILES := vgabios.c vgabios.h vgafonts.h vgatables.h
VBE_FILES := vbe.h vbe.c vbetables.h

# build flags
#vgabios.bin              : VGAFLAGS := -DVBE

# dist names
vgabios.bin              : DISTNAME := boot1.rom

# dependencies
vgabios.bin              : $(VGA_FILES) $(VBE_FILES) biossums

# build rule
%.bin:
	$(GCC) -E -P vgabios.c $(VGABIOS_VERS) $(VGAFLAGS) $(VGABIOS_DATE) > _$*_.c
	$(BCC) -o $*.s -C-c -D__i86__ -S -0 _$*_.c
	sed -e 's/^\.text//' -e 's/^\.data//' $*.s > _$*_.s
	$(AS86) _$*_.s -b $*.bin -u -w- -g -0 -j -O -l $*.txt
	rm -f _$*_.s _$*_.c $*.s
	mv $*.bin $(DISTNAME)
	./biossums $(DISTNAME)
	ls -l $(DISTNAME)

biossums: biossums.c
	$(CC) -o biossums biossums.c

vbetables-gen: vbetables-gen.c
	$(CC) -o vbetables-gen vbetables-gen.c

vbetables.h: vbetables-gen
	./vbetables-gen > $@

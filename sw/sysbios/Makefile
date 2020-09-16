# Copyright (C) 2001  MandrakeSoft S.A.
#
#   MandrakeSoft S.A.
#   43, rue d'Aboukir
#   75002 Paris - France
#   http://www.linux-mandrake.com/
#   http://www.mandrakesoft.com/
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

# Makefile for the BIOS component of bochs

BCC = bcc
GCC = gcc -m32 -fno-stack-protector
AS86 = as86

BUILDDATE = `date '+%m/%d/%y'`
BIOS_BUILD_DATE = "-DBIOS_BUILD_DATE=\"$(BUILDDATE)\""

bios: biossums boot0.rom

clean:
	rm -f  *.o *.a *.s *.rom _rombios*_.c rombios*.txt rombios*.sym
	rm -f  biossums biossums.exe

boot0.rom: rombios.c apmbios.S biossums rombios.h
	$(GCC) $(BIOS_BUILD_DATE) -DLEGACY -E -P $< > _rombiosl_.c
	$(BCC) -o rombiosl.s -C-c -D__i86__ -0 -S _rombiosl_.c
	sed -e 's/^\.text//' -e 's/^\.data//' rombiosl.s > _rombiosl_.s
	$(AS86) _rombiosl_.s -b $@ -u- -w- -g -0 -j -O -l rombiosl.txt
	./biossums $@
	rm -f  _rombiosl_.s

biossums: biossums.o

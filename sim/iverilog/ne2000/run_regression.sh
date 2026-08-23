#!/bin/sh
# NE2000 regression suite for the ao486 core.
#
# Runs every bench in regression/ (converted from the Minimig suite, driving
# ne2000_core through its native host port) plus every local tb_*.v.
#
# Exit status: 0 when every bench matches its expected result, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${ROOT:-$HERE/../../..}
RTL=${RTL:-$ROOT/rtl/soc/ne2000}
BUILD=${BUILD:-$HERE/build}

RTL_FILES="$RTL/ne2000_core.v $RTL/ne2000_packet_ram.v $RTL/ne2000_isa.v
$RTL/ne2000_shm_probe.v $RTL/ne2000_ddr_mailbox.v $RTL/ne2000_avalon_arbiter.v
$RTL/ne2000_dma_addr_map.v"

# Benches that fail in the device model as imported.
# See NE2000_AO486_PLAN.md, Phase 0 baseline findings, finding BF-1.
KNOWN_FAIL="ethernet_tb"

in_list() {
	for _e in $2; do [ "$1" = "$_e" ] && return 0; done
	return 1
}

mkdir -p "$BUILD"
pass=0; fail=0; xfail=0; unexpected=0

for tb in "$HERE"/regression/*_tb.v "$HERE"/tb_*.v; do
	[ -e "$tb" ] || continue
	name=$(basename "$tb" .v)

	if ! iverilog -g2012 -y "$ROOT/rtl/soc" -y "$RTL" -o "$BUILD/$name.vvp" "$tb" $RTL_FILES >"$BUILD/$name.compile.log" 2>&1; then
		printf 'CFAIL   %s : %s\n' "$name" "$(head -1 "$BUILD/$name.compile.log")"
		fail=$((fail + 1)); unexpected=$((unexpected + 1))
		continue
	fi

	( cd "$BUILD" && vvp "$name.vvp" ) >"$BUILD/$name.run.log" 2>&1
	if grep -qiE '(^|[^a-z])(FAIL|FATAL|ERROR)' "$BUILD/$name.run.log"; then
		result=FAIL
	else
		result=PASS
	fi

	if in_list "$name" "$KNOWN_FAIL"; then
		if [ "$result" = FAIL ]; then
			printf 'XFAIL   %s : %s\n' "$name" "$(grep -iE 'FAIL' "$BUILD/$name.run.log" | head -1)"
			xfail=$((xfail + 1))
		else
			printf 'XPASS   %s (known-fail now passes -- update KNOWN_FAIL)\n' "$name"
			unexpected=$((unexpected + 1))
		fi
	elif [ "$result" = PASS ]; then
		printf 'PASS    %s\n' "$name"
		pass=$((pass + 1))
	else
		printf 'FAIL    %s : %s\n' "$name" "$(grep -iE 'FAIL|ERROR' "$BUILD/$name.run.log" | head -1)"
		fail=$((fail + 1)); unexpected=$((unexpected + 1))
	fi
done

printf '\n%s\n' "-------------------------------------------"
printf 'pass=%d xfail=%d fail=%d\n' "$pass" "$xfail" "$fail"

if [ "$unexpected" -ne 0 ]; then
	printf 'RESULT: REGRESSION (%d bench(es) differ from expected)\n' "$unexpected"
	exit 1
fi

printf 'RESULT: all expected\n'
exit 0

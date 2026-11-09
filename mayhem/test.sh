#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer tests for the package/utils firmware tools (oseama, osafeloader,
# fritz_tffs_read, fritz_cal_extract, libnvram) built by mayhem/build.sh with normal flags.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/obj-test"
FX="$SRC/mayhem/fixtures"
T="$(mktemp -d "${TMPDIR:-/tmp}/lede-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
for b in oseama osafeloader fritz_tffs_read fritz_cal_extract nvram_selftest; do
  [ -x "$BIN/$b" ] || { echo "missing $BIN/$b (mayhem/build.sh must build it)" >&2; emit_ctrf "lede-tools" 0 1 0; exit 1; }
done

passed=0; failed=0
# check <name> <expected text> <actual text>
check() {
  if [ "$2" == "$3" ]; then passed=$((passed+1)); echo "PASS $1"
  else failed=$((failed+1)); echo "FAIL $1"; printf '  expected: %q\n  actual:   %q\n' "$2" "$3"; fi
}
# check_file <name> <expected file> <actual file>
check_file() {
  if [ -s "$3" ] && cmp -s "$2" "$3"; then passed=$((passed+1)); echo "PASS $1"
  else failed=$((failed+1)); echo "FAIL $1 ($3 differs from $2)"; fi
}
tab=$'\t'

# ---- oseama: Seama container with a seal and two entities
check "oseama info" \
"Meta size:${tab}20
Image size:${tab}0
Meta entry:${tab}signature=wrgac01

Entity offset:${tab}32
Entity size:${tab}104
Meta size:${tab}12
Image size:${tab}64
Meta entry:${tab}type=kernel

Entity offset:${tab}136
Entity size:${tab}124
Meta size:${tab}12
Image size:${tab}84
Meta entry:${tab}type=rootfs" \
"$("$BIN/oseama" info "$FX/seama.bin" 2>/dev/null)"
check "oseama info -e 1" \
"Entity offset:${tab}136
Entity size:${tab}124
Meta size:${tab}12
Image size:${tab}84
Meta entry:${tab}type=rootfs" \
"$("$BIN/oseama" info "$FX/seama.bin" -e 1 2>/dev/null)"
"$BIN/oseama" extract "$FX/seama.bin" -e 1 -o "$T/e1" 2>/dev/null
check_file "oseama extract entity 1" "$FX/seama.entity1.bin" "$T/e1"
"$BIN/oseama" extract "$FX/seama.bin" -e 0 -o "$T/e0" 2>/dev/null
check_file "oseama extract entity 0" "$FX/seama.entity0.bin" "$T/e0"
"$BIN/oseama" entity "$T/ent" -m type=kernel -f "$FX/seama.payload.bin" 2>/dev/null
check_file "oseama entity (header + md5 + padded meta)" "$FX/seama.entity.expected.bin" "$T/ent"

# ---- osafeloader: TP-Link SafeLoader image with md5 + partition table
check "osafeloader info" \
"Image size: 4640
       MD5: d4b09d3989d199dc154893229033ef71
 Partition: fs-uboot (0x100 - 0x110)
 Partition: os-image (0x200 - 0x220)" \
"$("$BIN/osafeloader" info "$FX/safeloader.bin" 2>/dev/null)"
"$BIN/osafeloader" extract "$FX/safeloader.bin" -p os-image -o "$T/os" 2>/dev/null
check_file "osafeloader extract os-image" "$FX/safeloader.os-image.expected" "$T/os"
"$BIN/osafeloader" extract "$FX/safeloader.bin" -p fs-uboot -o "$T/fs" 2>/dev/null
check_file "osafeloader extract fs-uboot" "$FX/safeloader.fs-uboot.expected" "$T/fs"

# ---- fritz_tffs_read: AVM TFFS key/value store (little-endian and byte-swapped images)
check "fritz_tffs_read -l" "firmware_version
macwlan
wlan_key" "$("$BIN/fritz_tffs_read" -i "$FX/tffs.bin" -l 2>/dev/null)"
check "fritz_tffs_read -a" "firmware_version=7.10
macwlan=00:11:22:33:44:55
wlan_key=secret" "$("$BIN/fritz_tffs_read" -i "$FX/tffs.bin" -a 2>/dev/null)"
check "fritz_tffs_read -n macwlan" "00:11:22:33:44:55" "$("$BIN/fritz_tffs_read" -i "$FX/tffs.bin" -n macwlan 2>/dev/null)"
check "fritz_tffs_read -b -n wlan_key (byte-swapped)" "secret" "$("$BIN/fritz_tffs_read" -b -i "$FX/tffs.be.bin" -n wlan_key 2>/dev/null)"

# ---- fritz_cal_extract: zlib calibration data behind an entry table
"$BIN/fritz_cal_extract" -s 4 -e 0x1001 -o "$T/cal" "$FX/cal.bin" 2>/dev/null
check_file "fritz_cal_extract entry 0x1001" "$FX/cal.plain" "$T/cal"
check "fritz_cal_extract -l 7" "CALDATA" "$("$BIN/fritz_cal_extract" -s 4 -e 0x1001 -l 7 "$FX/cal.bin" 2>/dev/null)"

# ---- libnvram: parse a partition image, edit, commit (CRC8), reopen
cp "$FX/nvram.bin" "$T/nvram.img" && truncate -s 32768 "$T/nvram.img"
check "libnvram open/get/set/unset/commit/reopen" \
"offset=0 len=152
boardtype=0x048e
lan_ipaddr=192.168.1.1
sdram_config=0x0062
sdram_init=0x0003
sdram_ncdl=0x0
sdram_refresh=0x0000
wan_proto=dhcp
committed len=148 crc=0x73 stored=0x73
reopened
boardtype=0x048e
lan_ipaddr=10.0.0.1
new_var=xyz
sdram_config=0x0062
sdram_init=0x0003
sdram_ncdl=0x0
sdram_refresh=0x0000" \
"$("$BIN/nvram_selftest" "$T/nvram.img" 2>/dev/null)"

emit_ctrf "lede-tools-kat" "$passed" "$failed" 0

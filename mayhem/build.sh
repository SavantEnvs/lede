#!/usr/bin/env bash
#
# mayhem/build.sh — build this repo's fuzz harness(es). EDIT per repo.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Each fuzz target #includes one package/utils tool's real source (main renamed), so the code under
# test is compiled with the sanitizers + SanCov in the harness TU itself; the only other upstream
# object is the tool's own md5.c where it has one. Everything is built out of tree into obj*/ (ignored).
TOOLS=package/utils
TARGETS="fuzz_oseama fuzz_osafeloader fuzz_fritz_tffs_read fuzz_fritz_cal_extract fuzz_nvram"
LIBS_fuzz_fritz_cal_extract="-lz"
MD5_fuzz_oseama="$TOOLS/oseama/src/md5.c"
MD5_fuzz_osafeloader="$TOOLS/osafeloader/src/md5.c"
DBG="$DEBUG_FLAGS -gdwarf-3"
WARN="-Wno-everything"

rm -rf obj obj-test
mkdir -p obj obj-test

# 1) lsan_off hook (linked into every fuzz + standalone binary)
$CXX $SANITIZER_FLAGS $DBG -c mayhem/lsan_off.cc -o obj/lsan_off.o

for t in $TARGETS; do
  md5var="MD5_$t"; md5src="${!md5var:-}"; libvar="LIBS_$t"; libs="${!libvar:-}"
  extra=()
  if [ -n "$md5src" ]; then
    $CC -O1 $SANITIZER_FLAGS $DBG $WARN -fsanitize=fuzzer-no-link -c "$md5src" -o "obj/$t.md5.o"
    $CC -O1 $SANITIZER_FLAGS $DBG $WARN -c "$md5src" -o "obj/$t.md5.sa.o"
    extra=("obj/$t.md5.o")
    extra_sa=("obj/$t.md5.sa.o")
  else
    extra_sa=()
  fi
  # fuzz binary: SanCov-instrumented harness (+ included tool source) linked against libFuzzer
  $CC -O1 $SANITIZER_FLAGS $DBG $WARN -fsanitize=fuzzer-no-link -c "mayhem/$t.c" -o "obj/$t.o"
  $CC $SANITIZER_FLAGS $DBG $LIB_FUZZING_ENGINE "obj/$t.o" "${extra[@]}" obj/lsan_off.o $libs -o "/mayhem/$t"
  # standalone reproducer: same code, run-once driver, no libFuzzer runtime
  $CC -O1 $SANITIZER_FLAGS $DBG $WARN -c "mayhem/$t.c" -o "obj/$t.sa.o"
  $CC $SANITIZER_FLAGS $DBG "$STANDALONE_FUZZ_MAIN" "obj/$t.sa.o" "${extra_sa[@]}" obj/lsan_off.o $libs -o "/mayhem/$t-standalone"
done

# 3) the tools themselves, NORMAL flags (no sanitizers, no coverage), for mayhem/test.sh
TEST_CFLAGS="-O2 $WARN $COVERAGE_FLAGS"
$CC $TEST_CFLAGS "$TOOLS/oseama/src/oseama.c" "$TOOLS/oseama/src/md5.c" -o obj-test/oseama
$CC $TEST_CFLAGS "$TOOLS/osafeloader/src/osafeloader.c" "$TOOLS/osafeloader/src/md5.c" -o obj-test/osafeloader
$CC $TEST_CFLAGS "$TOOLS/fritz-tools/src/fritz_tffs_read.c" -o obj-test/fritz_tffs_read
$CC $TEST_CFLAGS "$TOOLS/fritz-tools/src/fritz_cal_extract.c" -lz -o obj-test/fritz_cal_extract
$CC $TEST_CFLAGS mayhem/nvram_selftest.c -o obj-test/nvram_selftest

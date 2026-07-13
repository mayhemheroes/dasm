#!/usr/bin/env bash
#
# mayhem/build.sh — build DASM's fuzz target AND its test suite.
#
# The `dasm` Mayhem target is the real assembler CLI (same file-input code path as the original,
# proven target), built with sanitizers (ASan+UBSan, halting) + DWARF but NO extra fuzzer
# instrumentation: Mayhem drives coverage on the plain sanitized ELF with its own engine (the way the
# original uninstrumented target reached 46k edges). Compile-time AFL/SanCov instrumentation made
# Mayhem's dynamic_analysis phase fail (0 edges), so we deliberately do NOT afl-clang the target.
# Each fuzz input runs in a fresh forked process, so DASM's heavy global assembler state resets every
# run and its exit()/panic paths are harmless — unlike an in-process libFuzzer harness, which would
# carry state across iterations (DASM's permalloc arena never frees) and false-crash on exit().
#
# Contract (base ENV — use, don't redefine): CC, SANITIZER_FLAGS (ASan+UBSan, halting), DEBUG_FLAGS
# (-g -gdwarf-3, DWARF<4), SRC=/mayhem. Build the PROJECT with $SANITIZER_FLAGS+$DEBUG_FLAGS so the
# fuzzed code is instrumented AND carries DWARF symbols; build the TEST suite with the project's
# NORMAL flags (clean, independent) so mayhem/test.sh stays an honest functional oracle.
set -euo pipefail

# clang rejects an empty SOURCE_DATE_EPOCH — unset it if blank.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# The assembler translation units (from src/Makefile SRCS), excluding ftohex (a separate tool).
DASM_SRCS="main ops globals exp symbols errors util mne6303 mne6502 mne65c02 mne68705 mne6811 mnef8 mne68908"
srclist=""
for s in $DASM_SRCS; do srclist="$srclist $SRC/src/$s.c"; done

# 1) FUZZ TARGET `dasm`: sanitized (ASan+UBSan, halting) + DWARF, plain clang — NO fuzzer
#    instrumentation (Mayhem instruments/executes the ELF itself). mayhem/asan_default_options.c bakes
#    detect_leaks=0 (weak) so DASM's permalloc arena doesn't trip LeakSanitizer at exit on every run.
#    Mayhem's runtime owns the rest of ASAN_OPTIONS.
echo ">> building sanitized fuzz target: dasm ($CC)"
# shellcheck disable=SC2086
"$CC" -std=c11 $SANITIZER_FLAGS $DEBUG_FLAGS \
  $srclist "$SRC/mayhem/asan_default_options.c" -o "$SRC/dasm"

# 2) TEST SUITE: build the assembler + ftohex with the project's NORMAL flags (no sanitizers/AFL) so
#    the functional oracle is a clean, independent build. The upstream root Makefile builds src/ and
#    copies the binaries to bin/ (where test/Makefile's ../bin/dasm expects them); it also builds the
#    src/ unit-test binaries (test_errors, test_util). test.sh only RUNS these — it never compiles.
echo ">> building test-oracle binaries (normal flags): bin/dasm, bin/ftohex, unit tests"
make -C "$SRC" build CC="$CC" CFLAGS="$COVERAGE_FLAGS" -j"$MAYHEM_JOBS"
make -C "$SRC/src" test_errors test_util CC="$CC" CFLAGS="$COVERAGE_FLAGS" -j"$MAYHEM_JOBS"

echo ">> build.sh done"
ls -la "$SRC/dasm" "$SRC/bin/dasm" "$SRC/bin/ftohex" "$SRC/src/test_errors" "$SRC/src/test_util"

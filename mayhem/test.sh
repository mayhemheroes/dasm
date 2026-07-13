#!/usr/bin/env bash
#
# mayhem/test.sh — run DASM's ENTIRE upstream test suite and report it as CTRF.
#
# This runs the project's own, UNMODIFIED oracles — it never re-implements them:
#   1. Unit tests   : src/test_errors, src/test_util  (upstream `make -C src check`)
#   2. Functional   : test/run_tests.sh               (upstream `make -C test test`) — assembles every
#                     *.asm and byte-compares the produced binary against the committed *.bin.ref
#                     golden, and checks every *.fail case exits with its expected error_level.
#
# Both oracles are BEHAVIORAL: neutering dasm to exit(0) yields no output binary (functional golden
# comparison fails) and the unit binaries stop printing their "all N tests passed." marker — so this
# adapter reports failures, satisfying the anti-reward-hacking gate.
#
# It only RUNS artifacts built by mayhem/build.sh; it never compiles. It fails loudly if an expected
# prebuilt binary is missing. Emits a CTRF one-liner and exits nonzero iff any test failed.
set -uo pipefail

SRC="${SRC:-/mayhem}"
cd "$SRC"

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
    "$tool" "$tests" "$passed" "$failed" "$skipped" "$pending" "$other"
  [ "$failed" -eq 0 ]
}

fail_loud() { echo "test.sh: FATAL — $*" >&2; emit_ctrf "dasm" 0 1 0; exit 1; }

passed=0
failed=0

# ---- 1. unit tests (src/test_errors, src/test_util) --------------------------------
# Each binary prints "<name>: all N tests passed." on success or "<name>: F/N tests FAILED." on
# failure, and exits accordingly. We require the PASS marker — a neutered binary that just exit(0)s
# with no marker is counted as a failure (behavioral).
run_unit() {
  local bin="$1" name; name="$(basename "$bin")"
  [ -x "$bin" ] || fail_loud "expected prebuilt unit-test binary missing: $bin (did build.sh run?)"
  local out rc
  out="$("$bin" 2>&1)"; rc=$?
  echo "$out"
  local n f
  if n=$(sed -nE "s/.*: all ([0-9]+) tests passed\..*/\1/p" <<<"$out") && [ -n "$n" ] && [ "$rc" -eq 0 ]; then
    passed=$(( passed + n ))
  elif f=$(sed -nE "s#.*: ([0-9]+)/([0-9]+) tests FAILED\..*#\1#p" <<<"$out") && [ -n "$f" ]; then
    local total; total=$(sed -nE "s#.*: ([0-9]+)/([0-9]+) tests FAILED\..*#\2#p" <<<"$out")
    failed=$(( failed + f )); passed=$(( passed + total - f ))
  else
    echo "test.sh: $name produced no recognizable result marker (rc=$rc) — counting as failed" >&2
    failed=$(( failed + 1 ))
  fi
}
run_unit "$SRC/src/test_errors"
run_unit "$SRC/src/test_util"

# ---- 2. functional / golden tests (test/run_tests.sh) ------------------------------
# run_tests.sh assembles every *.asm, byte-compares against *.bin.ref, and validates every *.fail's
# error_level. It prints "executed N tests, X OK, Y failed, result: ..." and exits with Y.
[ -x "$SRC/bin/dasm" ]   || fail_loud "expected prebuilt binary missing: bin/dasm (did build.sh run?)"
[ -x "$SRC/bin/ftohex" ] || fail_loud "expected prebuilt binary missing: bin/ftohex (did build.sh run?)"
[ -x "$SRC/test/run_tests.sh" ] || fail_loud "upstream functional runner missing: test/run_tests.sh"

func_out="$(cd "$SRC/test" && ./run_tests.sh 2>&1)"
echo "$func_out"
sumline="$(grep -E "^executed [0-9]+ tests," <<<"$func_out" | tail -1)"
if [ -z "$sumline" ]; then
  echo "test.sh: functional runner emitted no summary line — counting the whole functional suite as failed" >&2
  failed=$(( failed + 1 ))
else
  fN=$(sed -nE "s/^executed ([0-9]+) tests, ([0-9]+) OK, ([0-9]+) failed.*/\1/p" <<<"$sumline")
  fOK=$(sed -nE "s/^executed ([0-9]+) tests, ([0-9]+) OK, ([0-9]+) failed.*/\2/p" <<<"$sumline")
  fF=$(sed -nE "s/^executed ([0-9]+) tests, ([0-9]+) OK, ([0-9]+) failed.*/\3/p" <<<"$sumline")
  passed=$(( passed + fOK ))
  failed=$(( failed + fF ))
fi

# skipped=0: both upstream suites (unit + functional) are integrated and run in full.
emit_ctrf "dasm" "$passed" "$failed" 0

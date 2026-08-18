#!/usr/bin/env bash
# Real, live verification run -- prints a clean, condensed summary of the
# four real suites this project's own claims are grounded in. Run it from
# anywhere; it resolves its own location.
#
# THE ROOT USED TO BE HARDWIRED TO /home/prabhu/makerchip/rva23-core, and that
# was wrong in two ways at once. rva23-core is a FROZEN sibling project this
# line is not entitled to depend on or write into, and the suites it invokes
# WRITE build artifacts -- so the one command this repo offers as "run this to
# verify" would have built into someone else's tree, and would have verified
# whatever vintage of the sources happened to be sitting there rather than
# this checkout. Same class as the toolchain path rundiff.sh already had to
# stop reaching across for (R29).
#
# R46(b) -- THIS AGGREGATOR COULD NOT FAIL. It captured each suite's output
# into a variable, printed a number scraped out of it, and exited 0 no matter
# what any suite returned. It was measured returning exit 0 while the ENTIRE
# cross-layer differential suite had not run at all (R46(a): rundiff.sh took
# iverilog from the caller's PATH, so all 21 probes returned exit 2 and the
# summary line read "0/21 as expected" -- which scans as a result rather than
# as an outage).
#
# That is the same defect rundiff.sh itself has a comment about, one level up:
# "a comparator that cannot fail". Fixed the same way -- THE EXIT CODE IS THE
# VERDICT -- plus a second, independent guard the exit code cannot give:
# every suite must report a nonzero total. A suite that dies before running
# anything exits 0 in some harnesses; a suite that ran zero programs has not
# verified anything, and this script now says so out loud.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$ROOT"

# ═══ R54 -- TWO RUNS AT ONCE CORRUPT EACH OTHER ═══════════════════════════
# The four suites write into fixed paths -- rtl/sim/*.vvp, *.hex, and the
# difftest artifact directory -- with no interlock, so a second concurrent run
# is not a SLOW run, it is a WRONG one, in either direction. Measured: two runs
# started by mistake, one reporting "RTL 51/51, diff 5/24, NOT VERIFIED" while
# the other reported the true 98/98 and 24/24 and passed.
#
# R46's exit-code discipline is what refused to certify the corrupted one, and
# that is the fix working. But VISIBLE is weaker than IMPOSSIBLE. A measurement
# taken while another process mutates the same tree is not a measurement --
# this project's own rule, applied from the writer's side.
LOCK="$ROOT/veda-core/.verification.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "FATAL: another verification run holds $LOCK." >&2
  echo "  The four suites share rtl/sim/ and the difftest artifacts, so two runs" >&2
  echo "  overwrite each other's .vvp/.hex/.sig files and BOTH results become" >&2
  echo "  fiction. Wait for it to finish, or kill it, then re-run." >&2
  ps -eo pid,etime,cmd | grep '[v]erification.sh' >&2 || true
  exit 7
fi

FAILED=()
note_fail() { FAILED+=("$1"); }

echo "=================================================="
echo "  Veda-Core — Real Verification Run"
echo "  $(date '+%Y-%m-%d %H:%M %Z')"
echo "=================================================="
echo

echo "--> Sail formal self-check suite"
SAIL_OUT=$(veda-core/sail_tests/run_veda_selfcheck_tests.sh 2>&1); SAIL_RC=$?
echo "$SAIL_OUT" | tail -3
SAIL_N=$(echo "$SAIL_OUT" | grep -oE '[0-9]+/[0-9]+ passed' | tail -1)
[ "$SAIL_RC" -eq 0 ] || note_fail "Sail self-check exited $SAIL_RC"
[ -n "$SAIL_N" ] && [ "${SAIL_N%%/*}" -gt 0 ] || note_fail "Sail self-check ran nothing"
echo

echo "--> RTL milestone regression suite"
RTL_OUT=$(veda-core/rtl/run_veda_smoke_test.sh 2>&1); RTL_RC=$?
RTL_PASS=$(echo "$RTL_OUT" | grep -c "TEST PASSED")
RTL_FAIL=$(echo "$RTL_OUT" | grep -c "TEST FAILED")
echo "$((RTL_PASS + RTL_FAIL)) programs run — ${RTL_PASS} passed, ${RTL_FAIL} failed"
# This suite has no aggregate exit code of its own (its last statement is a
# bare `vvp`), so the string count IS the verdict here -- which is exactly why
# the zero-total guard matters: an iverilog outage would silently shrink the
# count rather than fail, and a total of 0 would otherwise print as a clean
# "0 programs run".
[ "$RTL_FAIL" -eq 0 ] || note_fail "RTL milestones: ${RTL_FAIL} failed"
[ "$RTL_PASS" -gt 0 ] || note_fail "RTL milestones ran nothing"
echo

echo "--> Cross-layer differential suite (Sail vs RTL, probe by probe)"
DIFF_OUT=$(veda-core/difftest/run_difftests.sh 2>&1); DIFF_RC=$?
echo "$DIFF_OUT" | tail -1
DIFF_N=$(echo "$DIFF_OUT" | grep -oE '[0-9]+/[0-9]+ as expected' | tail -1)
[ "$DIFF_RC" -eq 0 ] || note_fail "Cross-layer differential exited $DIFF_RC"
[ -n "$DIFF_N" ] && [ "${DIFF_N%%/*}" -gt 0 ] || note_fail "Cross-layer differential ran nothing"
echo

echo "--> RISC-V International ACT4 RV64I conformance suite"
ACT4_OUT=$(veda-core/rtl/run_act4_tests.sh 2>&1); ACT4_RC=$?
echo "$ACT4_OUT" | tail -1
ACT4_N=$(echo "$ACT4_OUT" | tail -1 | grep -oE '[0-9]+/[0-9]+ passed')
[ "$ACT4_RC" -eq 0 ] || note_fail "ACT4 conformance exited $ACT4_RC"
[ -n "$ACT4_N" ] && [ "${ACT4_N%%/*}" -gt 0 ] || note_fail "ACT4 conformance ran nothing"
echo

echo "=================================================="
echo "  Summary"
echo "=================================================="
echo "  Sail self-check   : ${SAIL_N:-DID NOT RUN}"
echo "  RTL milestones    : ${RTL_PASS}/$((RTL_PASS + RTL_FAIL)) passed"
echo "  ACT4 conformance  : ${ACT4_N:-DID NOT RUN}"
echo "  Cross-layer diff  : ${DIFF_N:-DID NOT RUN}"
echo "=================================================="
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "  VERDICT: all four suites ran and passed."
  exit 0
fi
echo "  VERDICT: NOT VERIFIED -- ${#FAILED[@]} problem(s):"
for f in "${FAILED[@]}"; do echo "    - $f"; done
echo "=================================================="
exit 1

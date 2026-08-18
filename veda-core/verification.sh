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
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$ROOT"

echo "=================================================="
echo "  Veda-Core — Real Verification Run"
echo "  $(date '+%Y-%m-%d %H:%M %Z')"
echo "=================================================="
echo

echo "--> Sail formal self-check suite"
SAIL_OUT=$(veda-core/sail_tests/run_veda_selfcheck_tests.sh 2>&1)
echo "$SAIL_OUT" | tail -3
echo

echo "--> RTL milestone regression suite"
RTL_OUT=$(veda-core/rtl/run_veda_smoke_test.sh 2>&1)
RTL_PASS=$(echo "$RTL_OUT" | grep -c "TEST PASSED")
RTL_FAIL=$(echo "$RTL_OUT" | grep -c "TEST FAILED")
echo "$((RTL_PASS + RTL_FAIL)) programs run — ${RTL_PASS} passed, ${RTL_FAIL} failed"
echo

echo "--> Cross-layer differential suite (Sail vs RTL, probe by probe)"
DIFF_OUT=$(veda-core/difftest/run_difftests.sh 2>&1)
echo "$DIFF_OUT" | tail -1
echo

echo "--> RISC-V International ACT4 RV64I conformance suite"
ACT4_OUT=$(veda-core/rtl/run_act4_tests.sh 2>&1)
echo "$ACT4_OUT" | tail -1
echo

echo "=================================================="
echo "  Summary"
echo "=================================================="
echo "  Sail self-check   : $(echo "$SAIL_OUT" | grep -oE '[0-9]+/[0-9]+ passed')"
echo "  RTL milestones    : ${RTL_PASS}/$((RTL_PASS + RTL_FAIL)) passed"
echo "  ACT4 conformance  : $(echo "$ACT4_OUT" | tail -1 | grep -oE '[0-9]+/[0-9]+ passed')"
echo "  Cross-layer diff  : $(echo "$DIFF_OUT" | grep -oE '[0-9]+/[0-9]+ as expected')"
echo "=================================================="

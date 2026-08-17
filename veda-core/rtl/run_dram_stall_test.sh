#!/usr/bin/env bash
# R21 -- THE PROVING RUN FOR FIX 1, AT DRAM_EXTRA_CYCLES != 0.
#
# WHY THIS IS A SEPARATE SCRIPT. The bug is unreachable in the shipped build:
# DRAM_EXTRA_CYCLES = 0 makes $veda_dram_busy a structural constant 0. So the
# ordinary suite CANNOT exercise it, and a test living in that suite would pass
# for the wrong reason forever -- which is exactly how this survived Milestone 24,
# whose stall verification was a POSITIVE LATENCY TEST ONLY.
#
# THE MOST IMPORTANT MUTANT HERE IS NOT A CODE MUTATION. It is E = 0, which must
# make this run ERROR OR SKIP, never silently pass. That is enforced below by
# refusing to run at E = 0 at all, with a nonzero exit, rather than by an
# assertion inside a testbench that could be satisfied vacuously.
#
# The script edits the localparam, transpiles, runs, and ALWAYS restores -- the
# restore is on a trap so an interrupted run cannot leave the tree at nonzero E.
set -uo pipefail
cd "$(dirname "$0")"
E="${1:-10}"
TLV=veda_core.tlv
BACKUP="$(mktemp)"

if [ "$E" -eq 0 ]; then
  echo "REFUSING: DRAM_EXTRA_CYCLES=0 makes \$veda_dram_busy a structural constant 0," >&2
  echo "  so the stall path is unreachable and this test would pass without testing." >&2
  echo "  That is the exact shape that let R21 survive Milestone 24. Pass a nonzero E." >&2
  exit 2
fi

cp "$TLV" "$BACKUP"
restore() { cp "$BACKUP" "$TLV"; rm -f "$BACKUP"; }
trap restore EXIT INT TERM

python3 - "$TLV" "$E" <<'PY'
import sys, re
f, e = sys.argv[1], int(sys.argv[2])
s = open(f).read()
a = "   localparam int DRAM_EXTRA_CYCLES = 0;"
assert s.count(a) == 1, "anchor moved -- refusing to edit"
open(f, 'w').write(s.replace(a, f"   localparam int DRAM_EXTRA_CYCLES = {e};"))
PY
[ $? -ne 0 ] && { echo "FAILED to set DRAM_EXTRA_CYCLES" >&2; exit 2; }

echo "==> DRAM_EXTRA_CYCLES = $E"
./run_veda_smoke_test.sh > /tmp/dram_stall_E${E}.log 2>&1
rc=$?
pass=$(grep -c 'TEST PASSED' /tmp/dram_stall_E${E}.log)
fail=$(grep -c 'TEST FAILED' /tmp/dram_stall_E${E}.log)
trip=$(grep -c 'FATAL: a PC redirect' /tmp/dram_stall_E${E}.log)

echo "    smoke: $pass passed, $fail failed   (runner exit $rc)"
echo "    R21 tripwire firings: $trip"
echo "    full log: /tmp/dram_stall_E${E}.log"

# THE TRIPWIRE IS THE MEASUREMENT. If a redirect ever coincides with the start of
# a stall, FIX 2 becomes reachable and this run must say so loudly.
if [ "$trip" -ne 0 ]; then
  echo "RESULT: R21 FIX 2 IS NOW REACHABLE at E=$E -- the tripwire fired." >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL -- $fail tests broke at E=$E." >&2
  exit 1
fi
echo "RESULT: PASS -- at E=$E every test still passes and no redirect ever"
echo "        coincided with the start of a stall, which is FIX 1 holding and"
echo "        FIX 2 remaining unreachable."

#!/bin/bash
# Milestone V-C: batch runner for Veda-Core's self-checking Sail-model
# tests. Mirrors this project's own real rtl/run_act4_tests.sh pattern
# (assemble, link, run, collect PASS/FAIL, print a summary table) but
# targets sail_riscv_sim directly instead of the RTL testbench, using
# sail_riscv_sim's own real, built-in HTIF support (confirmed working
# this pass: "SUCCESS"/exit 0 on tohost=1, "FAILURE"/exit 1 on tohost=3)
# rather than a custom watcher.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$(dirname "$0")"

TC=$REPO_ROOT/toolchain/riscv-collab-gcc/riscv/bin
AS=$TC/riscv64-unknown-elf-as
LD=$TC/riscv64-unknown-elf-ld
SIM=$REPO_ROOT/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=./veda_test_sail.json
LDS=./veda_selfcheck.ld

# A missing toolchain used to surface as "0/86 passed" -- every test
# reporting ASM-FAIL, which reads as a catastrophic regression rather than
# an absent prerequisite. That cost a real debugging cycle. Fail loudly and
# say exactly what to run instead.
for tool in "$AS" "$LD" "$SIM"; do
  if [ ! -x "$tool" ]; then
    echo "FATAL: required tool not found: $tool" >&2
    echo "  The Veda-Core line is self-contained: run ./toolchain/setup.sh gnu-toolchain" >&2
    echo "  (toolchain/sail-riscv is a deliberate symlink to the Sail fork -- see setup.sh)" >&2
    exit 2
  fi
done

# ═══ R88 -- NO DARK TESTS. A .S FILE HERE MUST BE ACCOUNTED FOR ═══════════
#
# This runner globs `vc_*.S`. FOURTEEN files in this very directory were named
# `veda_*.S` -- an earlier convention -- so the glob never matched them, and they
# sat here for months looking exactly like coverage: in the tests directory,
# named as tests, naming CSeal, CUnseal, CSetBounds, OCA, NMC-add, the atomics,
# the query family and the ODT lifecycle. Three were sampled and all three
# FAILED. Nobody ran them and nobody missed them.
#
# That is the same shape R87 found one level down, where the SHIPPED SWITCHER was
# built by nothing and had drifted five separate ways. The lesson is not "rename
# fourteen files" -- that fixes fourteen and prevents nothing. It is that a test
# directory must not be able to hold a file nobody accounts for.
#
# difftest/run_difftests.sh ALREADY SOLVES THIS CLASS, and has for a while: it
# FATALs when a probe exists and is not in its expected table, saying a dropped
# entry "becomes a test nobody runs and nobody misses." That guard existed for
# probes and for nothing else. This is the same guard, here.
#
# FOUR WAYS A FILE MAY LIVE IN THIS DIRECTORY, and there is no fifth:
#   vc_*.S                 a test, and it is run
#   poc_*.S                a probe that must NOT be run, because a PASS in it
#                          means an escalation works
#   included by a test     a fragment, not a test (veda_selfcheck_macros.S)
#   pending/               parked, with the reason written where it is parked
# Anything else is a hard error, before a single test runs.
declare -a dark
for f in *.S; do
  case "$f" in
    vc_*.S|poc_*.S) continue ;;
  esac
  # a fragment that some test .include's is not a test
  if grep -ql "\.include \"$f\"" vc_*.S poc_*.S 2>/dev/null; then continue; fi
  dark+=("$f")
done
if [ "${#dark[@]}" -ne 0 ]; then
  echo "FATAL: ${#dark[@]} file(s) in sail_tests/ are neither run, nor poc_, nor included:" >&2
  for f in "${dark[@]}"; do echo "  $f" >&2; done
  echo "  Rename to vc_* to run it, poc_* if a PASS would mean an escalation works," >&2
  echo "  move it to pending/ with a written reason, or delete it. R88." >&2
  exit 2
fi

pass_count=0
fail_count=0
declare -a results

for src in vc_*.S; do
  name="${src%.S}"
  obj="/tmp/${name}.o"
  elf="/tmp/${name}.elf"

  if ! "$AS" -march=rv64i_zicsr -I. -o "$obj" "$src" 2>/tmp/"${name}".aserr; then
    results+=("ASM-FAIL  $name")
    fail_count=$((fail_count+1))
    continue
  fi
  if ! "$LD" -T "$LDS" -o "$elf" "$obj" 2>/tmp/"${name}".lderr; then
    results+=("LD-FAIL   $name")
    fail_count=$((fail_count+1))
    continue
  fi

  # A livelocking test must FAIL, not hang the suite. Recorded as needed
  # after an earlier sweep was killed by one; proven necessary again when a
  # bind-authority change turned a legitimate test into an infinite
  # trap/mret loop and the runner sat on it for two and a half hours instead
  # of reporting anything. --inst-limit is deterministic and
  # machine-independent, which a wall-clock timeout is not.
  out=$("$SIM" --config "$CFG" --inst-limit 2000000 "$elf" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && echo "$out" | grep -q "SUCCESS"; then
    results+=("PASS      $name")
    pass_count=$((pass_count+1))
  else
    results+=("FAIL      $name  (exit=$code)")
    fail_count=$((fail_count+1))
  fi
done

echo "=== Veda-Core Milestone V-C self-check results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass_count/$((pass_count+fail_count)) passed"

[ "$fail_count" -eq 0 ]

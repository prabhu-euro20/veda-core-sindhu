#!/usr/bin/env bash
# Cross-layer differential harness.
# One probe program, both layers, one signature format, one diff.
# Divergence is the finding: Sail and RTL are two independent implementations
# of one specification, so any behavioural difference is a bug in one of them.
set -uo pipefail
# EXIT CODE IS THE VERDICT. This harness used to end both branches in an echo
# with no -e, so it returned 0 on a divergence it had just printed in full -- a
# comparator that cannot fail. Nothing invoked it either (one line in a README),
# so a divergence was only ever a finding if a human happened to read the output.
# Now: 0 = agree, 1 = diverge, 2 = infrastructure failure. run_difftests.sh is
# the thing that runs them all and holds the expected verdicts.
D="$(cd "$(dirname "$0")" && pwd)"
SRC="$1"; NAME="$(basename "${SRC%.S}")"
# R29: the project's OWN toolchain, resolved from this file's location. The
# hand-wired path this replaced reached into rva23-core, a frozen sibling
# project, so this harness only ran on one machine.
TC="$(cd "$D/../.." && pwd)/toolchain/riscv-collab-gcc/riscv/bin"
SIM=/home/prabhu/veda-core-sindhu/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
# R24 (open half): the harness gets its OWN config, and that is the whole point.
# The Sail-side fixture switch lives in a JSON, and the suites and this harness
# cannot share one file if one needs fixtures ON and the other OFF. Sharing it
# was exactly the drift channel the adversarial pass on this design named. Two
# files, two values, and this harness -- which can now fail and is actually run
# (R31) -- is what would notice them drifting.
CFG="$D/veda_diff_sail.json"
RTLSIM=/home/prabhu/veda-core-sindhu/veda-core/rtl/sim

"$TC/riscv64-unknown-elf-as" -march=rv64i_zicsr -o "$D/$NAME.o" "$SRC" 2>"$D/$NAME.aserr" || { echo "ASM-FAIL $NAME"; cat "$D/$NAME.aserr"; exit 2; }
"$TC/riscv64-unknown-elf-ld" -T "$D/diff.ld" -o "$D/$NAME.elf" "$D/$NAME.o" 2>/dev/null || { echo "LD-FAIL $NAME"; exit 2; }
"$TC/riscv64-unknown-elf-objcopy" -O verilog "$D/$NAME.elf" "$D/$NAME.hex"

# STALENESS, ONE LEVEL UP. Rebuilding sim_diff.vvp from veda_core.sv every run
# is not enough: veda_core.sv is SandPiper OUTPUT, and only run_veda_smoke_test.sh
# regenerates it. Land a change in veda_core.tlv, skip the smoke script, run this
# -- and Sail reports the new behaviour while the RTL reports the old, so the
# harness invents a divergence that is history rather than a defect. Refuse
# instead of measuring two different vintages.
TLV="$(cd "$D/../rtl" && pwd)/veda_core.tlv"
if [ ! -f "$RTLSIM/veda_core.sv" ]; then
  echo "FATAL: $RTLSIM/veda_core.sv does not exist -- run ../rtl/run_veda_smoke_test.sh first" >&2; exit 2
fi
if [ "$TLV" -nt "$RTLSIM/veda_core.sv" ]; then
  echo "FATAL: veda_core.tlv is newer than the transpiled veda_core.sv." >&2
  echo "  This harness would compare a current Sail model against stale RTL." >&2
  echo "  Run ../rtl/run_veda_smoke_test.sh to re-transpile, then re-run." >&2
  exit 2
fi

"$SIM" --config "$CFG" --inst-limit 2000000 --test-signature "$D/$NAME.sail.sig" "$D/$NAME.elf" >"$D/$NAME.sail.out" 2>&1
# R29 again, and it bites harder here: sim_diff.vvp was a committed binary that
# nothing rebuilt, so this harness could compare a CURRENT Sail model against an
# RTL image built from whatever veda_core.sv happened to exist when the file was
# last made by hand. A differential harness measuring two different vintages
# reports divergences that are history, not defects. Rebuild it every run.
iverilog -g2012 -I "$RTLSIM" -o "$D/sim_diff.vvp" "$RTLSIM/veda_core.sv" "$D/tb_diff.sv" || { echo "IVERILOG-FAIL"; exit 2; }
vvp "$D/sim_diff.vvp" +elf_hex="$D/$NAME.hex" +sigout="$D/$NAME.rtl.sig" >"$D/$NAME.rtl.out" 2>&1

# COMPARE OVER THE REAL SIGNATURE LENGTH, not a fixed 192 words.
# The fixed head -192 was a defect with the same shape as everything else this
# harness got wrong: the Sail simulator emits exactly the words between
# begin_signature and end_signature (16 for most probes), while the RTL
# testbench always dumps its full 192-word window. Comparing 192 against 16
# therefore compared 176 words of Sail EOF against 176 words of RTL X, so EVERY
# probe reported DIVERGE -- which is exactly as useless as every probe
# reporting AGREE, and drowned two real divergences in padding noise. Sail
# derives its length from the real linker symbols, so its line count is the
# authoritative one.
N=$(wc -l < "$D/$NAME.sail.sig")
if [ "$N" -lt 8 ]; then echo "FATAL: $NAME produced only $N signature words -- probe did not run" >&2; exit 2; fi
head -"$N" "$D/$NAME.sail.sig" > "$D/$NAME.s8"; head -"$N" "$D/$NAME.rtl.sig" > "$D/$NAME.r8"
if diff -q "$D/$NAME.s8" "$D/$NAME.r8" >/dev/null 2>&1; then
  echo "AGREE     $NAME"
  exit 0
else
  echo "DIVERGE   $NAME"
  paste "$D/$NAME.s8" "$D/$NAME.r8" | awk 'BEGIN{printf "  %-4s %-10s %-10s\n","word","sail","rtl"} {m=($1==$2)?"":"   <-- DIFFERS"; printf "  %-4d %-10s %-10s%s\n", NR-1, $1, $2, m}'

  exit 1
fi

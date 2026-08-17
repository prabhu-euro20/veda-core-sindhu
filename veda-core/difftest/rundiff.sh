#!/usr/bin/env bash
# Cross-layer differential harness.
# One probe program, both layers, one signature format, one diff.
# Divergence is the finding: Sail and RTL are two independent implementations
# of one specification, so any behavioural difference is a bug in one of them.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
SRC="$1"; NAME="$(basename "${SRC%.S}")"
# R29: the project's OWN toolchain, resolved from this file's location. The
# hand-wired path this replaced reached into rva23-core, a frozen sibling
# project, so this harness only ran on one machine.
TC="$(cd "$D/../.." && pwd)/toolchain/riscv-collab-gcc/riscv/bin"
SIM=/home/prabhu/veda-core-sindhu/toolchain/sail-riscv/build/c_emulator/sail_riscv_sim
CFG=/home/prabhu/veda-core-sindhu/veda-core/sail_tests/veda_test_sail.json
RTLSIM=/home/prabhu/veda-core-sindhu/veda-core/rtl/sim

"$TC/riscv64-unknown-elf-as" -march=rv64i_zicsr -o "$D/$NAME.o" "$SRC" 2>"$D/$NAME.aserr" || { echo "ASM-FAIL $NAME"; cat "$D/$NAME.aserr"; exit 2; }
"$TC/riscv64-unknown-elf-ld" -T "$D/diff.ld" -o "$D/$NAME.elf" "$D/$NAME.o" 2>/dev/null || { echo "LD-FAIL $NAME"; exit 2; }
"$TC/riscv64-unknown-elf-objcopy" -O verilog "$D/$NAME.elf" "$D/$NAME.hex"

"$SIM" --config "$CFG" --inst-limit 2000000 --test-signature "$D/$NAME.sail.sig" "$D/$NAME.elf" >"$D/$NAME.sail.out" 2>&1
# R29 again, and it bites harder here: sim_diff.vvp was a committed binary that
# nothing rebuilt, so this harness could compare a CURRENT Sail model against an
# RTL image built from whatever veda_core.sv happened to exist when the file was
# last made by hand. A differential harness measuring two different vintages
# reports divergences that are history, not defects. Rebuild it every run.
iverilog -g2012 -I "$RTLSIM" -o "$D/sim_diff.vvp" "$RTLSIM/veda_core.sv" "$D/tb_diff.sv" || { echo "IVERILOG-FAIL"; exit 2; }
vvp "$D/sim_diff.vvp" +elf_hex="$D/$NAME.hex" +sigout="$D/$NAME.rtl.sig" >"$D/$NAME.rtl.out" 2>&1

head -192 "$D/$NAME.sail.sig" > "$D/$NAME.s8"; head -192 "$D/$NAME.rtl.sig" > "$D/$NAME.r8"
if diff -q "$D/$NAME.s8" "$D/$NAME.r8" >/dev/null 2>&1; then
  echo "AGREE     $NAME"
else
  echo "DIVERGE   $NAME"
  paste "$D/$NAME.s8" "$D/$NAME.r8" | awk 'BEGIN{printf "  %-4s %-10s %-10s\n","word","sail","rtl"} {m=($1==$2)?"":"   <-- DIFFERS"; printf "  %-4d %-10s %-10s%s\n", NR-1, $1, $2, m}'
fi

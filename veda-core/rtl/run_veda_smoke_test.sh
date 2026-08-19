#!/usr/bin/env bash
# Transpile veda_core.tlv -> SystemVerilog (SandPiper) and simulate with
# Icarus Verilog, loading a real ELF via the +elf_hex plusarg (the same
# real mechanism the base core's own ACT4 mode already uses) and dumping
# a cycle trace for manual review -- mirrors rtl/run_smoke_test.sh's own
# proven structure, adapted for ELF loading instead of the hand-assembled
# ROM[] path (Veda-Core's own OCL/OCS only access elfmem, which is only
# populated in act4_mode).
set -euo pipefail

# R49: resolved BEFORE the cd below, because the coverage guard at the end of
# this file has to read this file, and after `cd "$(dirname "$0")"` a relative
# $0 no longer resolves. The guard silently reported all 96 images unrun on its
# first attempt for exactly that reason -- a check that fails open reads the
# same as a check that fails closed until you look at the number.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"

# R49: AND THIS RUNNER COULD NOT FAIL EITHER. Its verdicts are strings printed
# by 96 separate testbenches; its own exit code was whatever the last `vvp`
# returned, which is 0 even when a testbench printed *** TEST FAILED ***. It
# was measured doing exactly that: exit 0 with veda_smoke_m16_neg red.
# verification.sh counts the strings and so would have caught it at the
# aggregator (R46), but a suite runner that returns success on a failing suite
# is the same defect one level down, and anyone invoking this script directly
# -- which every RTL increment on this project does -- got a clean exit.
# Every vvp below tees into $RUNLOG and the verdict is taken from it at the end.
RUNLOG="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/sim/run.log"

cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.local/bin"

if ! command -v iverilog >/dev/null 2>&1; then
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
  conda activate base
fi

SIM=sim
TLV=veda_core.tlv
STRIPPED=$SIM/_novz.tlv
mkdir -p "$SIM"

python3 - "$TLV" "$STRIPPED" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.readlines()
viz = next(i for i, l in enumerate(lines) if '\\viz_js' in l)
tail = next(i for i, l in enumerate(lines) if 'PASS / FAIL' in l)
with open(dst, 'w') as f:
    f.writelines(lines[:viz] + lines[tail-1:])
EOF

cat > "$SIM/sp_m4out.vh" <<'VHEOF'
module pseudo_rand #(parameter WIDTH = 1) (input clk, input reset, output logic [WIDTH-1:0] out);
  assign out = '0;
endmodule
VHEOF

cat > "$SIM/sandpiper_gen.vh" <<'VHEOF'
VHEOF

echo "==> Transpiling TL-Verilog -> SystemVerilog (SandPiper cloud service)"
# RTL-5: delete any previous output FIRST. Exit code 1 from sandpiper-saas
# means "warnings, proceed", but a transient cloud failure can also exit 1
# while writing no new veda_core.sv -- in which case every step below would
# silently run against the PREVIOUS build's SystemVerilog. That is not
# hypothetical: it contaminated an entire RTL-5 mutation sweep, reporting a
# mutant as killed when it was really the previous mutant still in place.
# With the file removed up front, a transpile that produces nothing fails
# loudly at iverilog instead of measuring the wrong design.
rm -f "$SIM/veda_core.sv"
set +e
sandpiper-saas -i "$STRIPPED" -o veda_core.sv --outdir "$SIM" -p m4out
sp_status=$?
set -e
if [ "$sp_status" -gt 1 ]; then
  echo "SandPiper transpile failed (exit $sp_status)" >&2
  exit "$sp_status"
fi
if [ ! -f "$SIM/veda_core.sv" ]; then
  echo "SandPiper exited $sp_status but produced no veda_core.sv -- refusing to run against stale output" >&2
  exit 3
fi

# Assemble every smoke test from source. This step did not exist: sim/*.hex is
# gitignored (.gitignore:38) and NOTHING in the repository rebuilt it, so the
# whole suite ran only on a machine where the hex files happened to survive
# from a hand-typed gcc invocation. On a fresh clone every vvp below would have
# failed for want of an input the tree cannot produce -- 87 tests that could not
# be reproduced by anyone else, which for a security corpus is the same as not
# having them.
#
# The toolchain is the project's OWN, resolved the same way sail_tests/
# run_veda_selfcheck_tests.sh resolves it. The hand-typed invocations that had
# been keeping this going reached into a DIFFERENT project's tree
# (rva23-core/toolchain), which is frozen and is not a dependency this line is
# entitled to have.
TC="$(cd ../.. && pwd)/toolchain/riscv-collab-gcc/riscv/bin"
GCC="$TC/riscv64-unknown-elf-gcc"
OBJCOPY="$TC/riscv64-unknown-elf-objcopy"
if [ ! -x "$GCC" ]; then
  echo "FATAL: project toolchain not found at $GCC" >&2
  echo "  The Veda-Core line is self-contained: run ./toolchain/setup.sh gnu-toolchain" >&2
  exit 2
fi
mkdir -p "$(dirname "$RUNLOG")"; : > "$RUNLOG"
echo "==> Assembling smoke tests from source"
asm_fail=0
for src in "$SIM"/veda_smoke_*.S; do
  base="${src%.S}"
  # The preprocessor stays ON, which is what a .S extension selects. Both
  # settings were MEASURED rather than reasoned about, and each breaks a
  # different set: with cpp OFF, 41 tests fail because the corpus writes its
  # comments with // and only the preprocessor strips those. With cpp ON,
  # exactly three failed on prose that happens to parse as C -- an "# if Offset
  # would land >= Length" read as a directive, and two headers naming
  # rtl/sim/*.S, where sim/* opens a C comment that never closes. Three comment
  # lines were reworded; 34 sources were not. sail_tests/ invokes `as` directly
  # and so never had either problem.
  # -T sim/veda_smoke_test.ld, NOT a bare -Ttext=0x80000000. The script was
  # already in the tree, unreferenced by anything, and the difference is not
  # cosmetic: -Ttext alone lets the linker page-align .data, which lands it a
  # full 0x1000 past the end of .text, while the script places it immediately
  # after. FIVE tests fail with the gap and pass without it -- the paging,
  # scheduler, cross-thread and two syscall0 tests, which are exactly the five
  # in this corpus with a non-empty .data. Found by rebuilding every image from
  # source for the first time and watching those five go red.
  if ! "$GCC" -march=rv64i_zicsr -mabi=lp64 -nostdlib -nostartfiles \
       -T "$SIM/veda_smoke_test.ld" -o "$base.elf" "$src" 2>"$base.aserr"; then
    echo "  ASM-FAIL $(basename "$src")"; sed 's/^/    /' "$base.aserr" | head -5
    asm_fail=$((asm_fail+1)); continue
  fi
  "$OBJCOPY" -O verilog "$base.elf" "$base.hex"
done
if [ "$asm_fail" -ne 0 ]; then
  echo "FATAL: $asm_fail smoke test(s) failed to assemble -- refusing to run a partial suite" >&2
  exit 4
fi
echo "    $(ls "$SIM"/veda_smoke_*.hex | wc -l) images built"

# R22/R9: the timing rule's premise, checked rather than assumed. Runs before
# anything is built, because it is a structural invariant over the source and
# costs nothing.
echo "==> Checking the timing-rule coupling (R22)"
( cd .. && ./check_timing_coupling.sh ) || { echo "FATAL: the adopted timing rule's premise no longer holds" >&2; exit 5; }

echo "==> Compiling with Icarus Verilog (positive test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke.sv"
echo "==> Simulating (positive test)"
vvp "$SIM/sim.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_test.hex" | tee -a "$RUNLOG"

echo "==> Compiling with Icarus Verilog (negative control)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_neg.sv"
echo "==> Simulating (negative control)"
vvp "$SIM/sim_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 2: Compiling (OCA + NMC_ADD + Veda-Atomic, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2.sv"
echo "==> Simulating (Milestone 2 positive)"
vvp "$SIM/sim_m2.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m2.hex" | tee -a "$RUNLOG"

echo "==> Milestone 2: Compiling (NMC_ADD missing Permit_NMC_Compute, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2_neg.sv"
echo "==> Simulating (Milestone 2 negative: permission)"
vvp "$SIM/sim_m2neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m2_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 2: Compiling (OCA out-of-bounds soft-fail, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ocaneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oca_neg.sv"
echo "==> Simulating (Milestone 2 negative: OCA soft-fail)"
vvp "$SIM/sim_ocaneg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_oca_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 3: Compiling (query family + CSetBounds, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m3.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m3.sv"
echo "==> Simulating (Milestone 3 positive)"
vvp "$SIM/sim_m3.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m3.hex" | tee -a "$RUNLOG"

echo "==> Milestone 3: Compiling (CSetBounds out-of-window, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_csbneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_csetbounds_neg.sv"
echo "==> Simulating (Milestone 3 negative)"
vvp "$SIM/sim_csbneg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_csetbounds_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 4: Compiling (privilege gate + ODT-Populate/Destroy lifecycle, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4.sv"
echo "==> Simulating (Milestone 4 positive)"
vvp "$SIM/sim_m4.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m4.hex" | tee -a "$RUNLOG"

echo "==> Milestone 4: Compiling (dropped-privilege ODT-Populate, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4_neg.sv"
echo "==> Simulating (Milestone 4 negative)"
vvp "$SIM/sim_m4neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m4_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 5: Compiling (NMC_ADD.W + 8 untested Veda-Atomic ops, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m5.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m5.sv"
echo "==> Simulating (Milestone 5)"
vvp "$SIM/sim_m5.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m5.hex" | tee -a "$RUNLOG"

echo "==> Milestone 6: Compiling (CSeal/CUnseal + sealed-capability enforcement, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m6.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m6.sv"
echo "==> Simulating (Milestone 6)"
vvp "$SIM/sim_m6.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m6.hex" | tee -a "$RUNLOG"

echo "==> Milestone 7: Compiling (OCL.C/OCS.C capability-width memory access, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m7.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m7.sv"
echo "==> Simulating (Milestone 7)"
vvp "$SIM/sim_m7.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m7.hex" | tee -a "$RUNLOG"

echo "==> Milestone 8: Compiling (Rebind, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8.sv"
echo "==> Simulating (Milestone 8 positive)"
vvp "$SIM/sim_m8.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m8.hex" | tee -a "$RUNLOG"

echo "==> Milestone 8: Compiling (Rebind sealed/ODT-miss/reserved-mode, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8_neg.sv"
echo "==> Simulating (Milestone 8 negative)"
vvp "$SIM/sim_m8neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m8_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 9: Compiling (Zicsr-lite + real trap-and-resume, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m9.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m9.sv"
echo "==> Simulating (Milestone 9 positive)"
vvp "$SIM/sim_m9.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m9.hex" | tee -a "$RUNLOG"

# Milestone 1/2/6's own negative/sealed-use tests (built earlier above)
# were upgraded in-place to a real trap-handler pattern as part of
# Milestone 9 -- no separate re-run needed here, their earlier
# build/run (near Milestones 1/2/6's own sections above) already
# exercises the upgraded .S/.sv content.

echo "==> Milestone 10: Compiling (OCInvoke, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10.sv"
echo "==> Simulating (Milestone 10 positive)"
vvp "$SIM/sim_m10.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m10.hex" | tee -a "$RUNLOG"

echo "==> Milestone 10: Compiling (OCInvoke Type/Permit_Execute Violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10_neg.sv"
echo "==> Simulating (Milestone 10 negative)"
vvp "$SIM/sim_m10neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m10_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 11: Compiling (OSpecialRW + ODA-authorized ODT-Populate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11.sv"
echo "==> Simulating (Milestone 11 positive)"
vvp "$SIM/sim_m11.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m11.hex" | tee -a "$RUNLOG"

echo "==> Milestone 11: Compiling (dropped privilege + unauthorized ODA, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11_neg.sv"
echo "==> Simulating (Milestone 11 negative)"
vvp "$SIM/sim_m11neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m11_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 12: Compiling (owner-hart ODT enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12.sv"
echo "==> Simulating (Milestone 12 positive)"
vvp "$SIM/sim_m12.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m12.hex" | tee -a "$RUNLOG"

echo "==> Milestone 12: Compiling (wrong-owner hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12_neg.sv"
echo "==> Simulating (Milestone 12 negative)"
vvp "$SIM/sim_m12neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m12_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 13: Compiling (plain Bind object-not-found hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m13neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m13_neg.sv"
echo "==> Simulating (Milestone 13 negative)"
vvp "$SIM/sim_m13neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m13_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 14: Compiling (PCC compartment bounding, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14.sv"
echo "==> Simulating (Milestone 14 positive)"
vvp "$SIM/sim_m14.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m14.hex" | tee -a "$RUNLOG"

echo "==> Milestone 14: Compiling (compartment escape hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14_neg.sv"
echo "==> Simulating (Milestone 14 negative)"
vvp "$SIM/sim_m14neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m14_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 18: Compiling (VEDA_ODT_POPULATE_FAST + veda_attr CSR, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18.sv"
echo "==> Simulating (Milestone 18 positive)"
vvp "$SIM/sim_m18.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m18.hex" | tee -a "$RUNLOG"

echo "==> Milestone 18: Compiling (veda_attr-sourced Length bounds enforcement, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18_neg.sv"
echo "==> Simulating (Milestone 18 negative)"
vvp "$SIM/sim_m18neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m18_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 19: Compiling (Veda-Purecap Enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19.sv"
echo "==> Simulating (Milestone 19 positive)"
vvp "$SIM/sim_m19.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m19.hex" | tee -a "$RUNLOG"

echo "==> Milestone 19: Compiling (global purecap bit blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg.sv"
echo "==> Simulating (Milestone 19 negative 1)"
vvp "$SIM/sim_m19neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m19_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 19: Compiling (OCInvoke compartment blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg2.sv"
echo "==> Simulating (Milestone 19 negative 2)"
vvp "$SIM/sim_m19neg2.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m19_neg2.hex" | tee -a "$RUNLOG"

echo "==> Milestone 20: Compiling (compartment-state CSR gate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20.sv"
echo "==> Simulating (Milestone 20 positive)"
vvp "$SIM/sim_m20.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m20.hex" | tee -a "$RUNLOG"

echo "==> Milestone 20: Compiling (veda_pcc_length self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg.sv"
echo "==> Simulating (Milestone 20 negative 1)"
vvp "$SIM/sim_m20neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m20_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 20: Compiling (veda_mode self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg2.sv"
echo "==> Simulating (Milestone 20 negative 2)"
vvp "$SIM/sim_m20neg2.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m20_neg2.hex" | tee -a "$RUNLOG"

echo "==> Compiling (Veda-Atomic aq/rl invariance)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_aqrl.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_aqrl_invariance.sv"
echo "==> Simulating (aq/rl invariance)"
vvp "$SIM/sim_aqrl.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_aqrl_invariance.hex" | tee -a "$RUNLOG"

echo "==> Milestone 22: Compiling (OCJALR compartment-boundary scope, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m22.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m22.sv"
echo "==> Simulating (Milestone 22)"
vvp "$SIM/sim_m22.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m22.hex" | tee -a "$RUNLOG"

echo "==> Minimal OS kernel Milestone A: Compiling (TSC round-trip via OSpecialRW selector, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosA_tsc.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosA_tsc.sv"
echo "==> Simulating (minimal OS kernel Milestone A)"
vvp "$SIM/sim_mosA_tsc.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_mosA_tsc.hex" | tee -a "$RUNLOG"

echo "==> Minimal OS kernel Milestone B: Compiling (CSealEntry + OCRETURN, positive, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry.sv"
echo "==> Simulating (minimal OS kernel Milestone B positive)"
vvp "$SIM/sim_mosB_sentry.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_mosB_sentry.hex" | tee -a "$RUNLOG"

echo "==> Minimal OS kernel Milestone B: Compiling (CSeal forgery blocked + OCRETURN tag violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry_neg.sv"
echo "==> Simulating (minimal OS kernel Milestone B negative)"
vvp "$SIM/sim_mosB_sentry_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_mosB_sentry_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 23: Compiling (real ECALL support, baseline unbounded context)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall.sv"
echo "==> Simulating (Milestone 23 ECALL baseline)"
vvp "$SIM/sim_m23_ecall.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m23_ecall.hex" | tee -a "$RUNLOG"

echo "==> Milestone 23: Compiling (real ECALL support, from inside a live OCInvoke compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall_compartment.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall_compartment.sv"
echo "==> Simulating (Milestone 23 ECALL compartment)"
vvp "$SIM/sim_m23_ecall_compartment.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m23_ecall_compartment.hex" | tee -a "$RUNLOG"

echo "==> Milestone 23: Compiling (RTL mirror of Sail Milestone C: real cooperative scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_scheduler.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_scheduler.sv"
echo "==> Simulating (Milestone 23 cooperative scheduler)"
vvp "$SIM/sim_m23_scheduler.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m23_scheduler.hex" | tee -a "$RUNLOG"

echo "==> SSC: Compiling (Stack-Spill Capability round-trip, third SCR independent of ODA/TSC)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_roundtrip.sv"
echo "==> Simulating (SSC roundtrip)"
vvp "$SIM/sim_ssc_roundtrip.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_ssc_roundtrip.hex" | tee -a "$RUNLOG"

echo "==> SSC: Compiling (OCInvoke clears SSC on every compartment-boundary crossing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_ocinvoke_clear.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_ocinvoke_clear.sv"
echo "==> Simulating (SSC OCInvoke clear)"
vvp "$SIM/sim_ssc_ocinvoke_clear.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_ssc_ocinvoke_clear.hex" | tee -a "$RUNLOG"

echo "==> SSC: Compiling (real spill/reload sequence inside a compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_spill_reload.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_spill_reload.sv"
echo "==> Simulating (SSC spill/reload)"
vvp "$SIM/sim_ssc_spill_reload.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_ssc_spill_reload.hex" | tee -a "$RUNLOG"

echo "==> SSC: Compiling (out-of-bounds access, real Bounds Violation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_oob.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_oob.sv"
echo "==> Simulating (SSC OOB)"
vvp "$SIM/sim_ssc_oob.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_ssc_oob.hex" | tee -a "$RUNLOG"

echo "==> SSC: Compiling (cross-thread isolation via the real scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_cross_thread.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_cross_thread.sv"
echo "==> Simulating (SSC cross-thread isolation)"
vvp "$SIM/sim_ssc_cross_thread.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_ssc_cross_thread.hex" | tee -a "$RUNLOG"

echo "==> Milestone 24: Compiling (real DRAM-latency stall FSM, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24lat.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_latency.sv"
echo "==> Simulating (Milestone 24 latency)"
vvp "$SIM/sim_m24lat.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m24_latency.hex" | tee -a "$RUNLOG"

echo "==> Milestone 24 Stage 2: Compiling (TCM ODT tier, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24odttcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_odt_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 2 ODT TCM tier)"
vvp "$SIM/sim_m24odttcm.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m24_odt_tcm.hex" | tee -a "$RUNLOG"

echo "==> Milestone 24 Stage 3: Compiling (TCM capability-spill scratch, OCL.C/OCS.C address-range mux)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24ocsctcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_ocsc_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 3 OCL.C/OCS.C TCM scratch)"
vvp "$SIM/sim_m24ocsctcm.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m24_ocsc_tcm.hex" | tee -a "$RUNLOG"

echo "==> RTL M21-restore mirror: Compiling (automatic PCC restore-on-mret, 3 real properties)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_pcc_restore.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_pcc_restore_on_mret.sv"
echo "==> Simulating (RTL M21-restore mirror)"
vvp "$SIM/sim_pcc_restore.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_pcc_restore_on_mret.hex" | tee -a "$RUNLOG"

echo "==> RTL M27-mtvec-gate mirror: Compiling (mtvec self-escape from a live compartment must hard-trap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mtvec_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mtvec_escape_neg.sv"
echo "==> Simulating (RTL M27-mtvec-gate mirror)"
vvp "$SIM/sim_mtvec_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_mtvec_escape_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL Part C (Task #297 mirror): Compiling (real KERNEL ecall dispatcher, sys_write/sys_exit)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0k.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel.sv"
echo "==> Simulating (RTL Part C: syscall0 kernel)"
vvp "$SIM/sim_s0k.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_syscall0_kernel.hex" | tee -a "$RUNLOG"

echo "==> RTL Part D (Task #299 mirror): Compiling (forged, never-populated Object_ID negative test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0kneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel_forged_neg.sv"
echo "==> Simulating (RTL Part D: syscall0 kernel forged-Object_ID negative)"
vvp "$SIM/sim_s0kneg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_syscall0_kernel_forged_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-2a: Compiling (32-byte tag granule -- plain store into byte 16 destroys a stored capability's tag)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_granule_tamper.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap_granule_tamper.sv"
echo "==> Simulating (RTL-2a granule tamper)"
vvp "$SIM/sim_granule_tamper.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_cap_granule_tamper.hex" | tee -a "$RUNLOG"

echo "==> RTL-2a: Compiling (32-byte alignment -- misaligned OCS.C hard-traps, cause 0x08)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_misaligned.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap_misaligned_neg.sv"
echo "==> Simulating (RTL-2a misaligned)"
vvp "$SIM/sim_misaligned.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_cap_misaligned_neg.hex" | tee -a "$RUNLOG"

echo "==> CAndPerm: Compiling (rights attenuation, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_candperm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_candperm.sv"
echo "==> Simulating (CAndPerm positive)"
vvp "$SIM/sim_candperm.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_candperm.hex" | tee -a "$RUNLOG"

echo "==> CAndPerm: Compiling (sealed source soft-fails, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_candperm_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_candperm_neg.sv"
echo "==> Simulating (CAndPerm negative)"
vvp "$SIM/sim_candperm_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_candperm_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-2b: Compiling (256-bit capability -- every field exact across a memory round-trip)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cap256.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap256_roundtrip.sv"
echo "==> Simulating (RTL-2b 256-bit round-trip)"
vvp "$SIM/sim_cap256.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_cap256_roundtrip.hex" | tee -a "$RUNLOG"

echo "==> RTL-4 DESIGN_08: Compiling (global uniqueness across regions + dereference re-check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_unique.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_unique.sv"
echo "==> Simulating (RTL-4 region uniqueness)"
vvp "$SIM/sim_region_unique.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_region_unique.hex" | tee -a "$RUNLOG"

echo "==> RTL-4 DESIGN_08: Compiling (CRBR fast path -- fixed-shape read count)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fastpath.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fastpath.sv"
echo "==> Simulating (RTL-4 CRBR fast path)"
vvp "$SIM/sim_region_fastpath.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_region_fastpath.hex" | tee -a "$RUNLOG"

echo "==> RTL-4 DESIGN_08: Compiling (explicit REGION_FAULT, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fault_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fault_neg.sv"
echo "==> Simulating (RTL-4 region fault)"
vvp "$SIM/sim_region_fault_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_region_fault_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-4 DESIGN_08: Compiling (REGION_FAULT covers all bind modes, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fault_modes_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fault_modes_neg.sv"
echo "==> Simulating (RTL-4 region fault, all bind modes)"
vvp "$SIM/sim_region_fault_modes_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_region_fault_modes_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-5 R10: Compiling (CRBR round-trip across invoke/trap/mret/return)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r10_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r10_crbr_roundtrip.sv"
echo "==> Simulating (RTL-5 R10 CRBR round-trip)"
vvp "$SIM/sim_r10_roundtrip.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r10_crbr_roundtrip.hex" | tee -a "$RUNLOG"

echo "==> RTL-5 R10: Compiling (crossing into a paged-out domain, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r10_fault_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r10_crossing_fault_neg.sv"
echo "==> Simulating (RTL-5 R10 crossing fault)"
vvp "$SIM/sim_r10_fault_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r10_crossing_fault_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-6: Compiling (object residency gate, all three bind modes)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency.sv"
echo "==> Simulating (RTL-6 object residency gate)"
vvp "$SIM/sim_residency.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_residency.hex" | tee -a "$RUNLOG"

echo "==> RTL-6: Compiling (residency cause ordering, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency_order_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency_order_neg.sv"
echo "==> Simulating (RTL-6 residency cause ordering)"
vvp "$SIM/sim_residency_order_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_residency_order_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-6b: Compiling (dereference-side residency, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency_deref_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency_deref_neg.sv"
echo "==> Simulating (RTL-6b dereference-side residency)"
vvp "$SIM/sim_residency_deref_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_residency_deref_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-6c: Compiling (page-out/page-in cycle + preservation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_paging.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_paging.sv"
echo "==> Simulating (RTL-6c paging cycle)"
vvp "$SIM/sim_paging.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_paging.hex" | tee -a "$RUNLOG"

echo "==> RTL-6c: Compiling (paging refusals, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_paging_refusals_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_paging_refusals_neg.sv"
echo "==> Simulating (RTL-6c paging refusals)"
vvp "$SIM/sim_paging_refusals_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_paging_refusals_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-7: Compiling (R11 crossing revalidation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r11_crossing_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r11_crossing_neg.sv"
echo "==> Simulating (RTL-7 R11 crossing revalidation)"
vvp "$SIM/sim_r11_crossing_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r11_crossing_neg.hex" | tee -a "$RUNLOG"

echo "==> R24: Compiling (capability register file reset state)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r24.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r24_crf_reset.sv"
echo "==> Simulating (R24 CRF reset / rebind into an untouched register)"
vvp "$SIM/sim_r24.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r24_crf_reset.hex" | tee -a "$RUNLOG"

echo "==> R36: Compiling (privilege on a trap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r36.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r36_priv_trap.sv"
echo "==> Simulating (R36 privilege model)"
vvp "$SIM/sim_r36.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r36_priv_trap.hex" | tee -a "$RUNLOG"

echo "==> R35: Compiling (veda_attr privilege term)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r35.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r35_attr_priv.sv"
echo "==> Simulating (R35 veda_attr privilege)"
vvp "$SIM/sim_r35.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r35_attr_priv.hex" | tee -a "$RUNLOG"

echo "==> R26: Compiling (compartment authority follows the NAME, not the bound)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r26.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r26_authority.sv"
echo "==> Simulating (R26 sentinel-Length compartment escape)"
vvp "$SIM/sim_r26.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r26_authority.hex" | tee -a "$RUNLOG"

echo "==> R27: Compiling (privilege gate on the PCC/MEPCC CSRs)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r27.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r27_csr_priv.sv"
echo "==> Simulating (R27 CSR privilege gate)"
vvp "$SIM/sim_r27.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r27_csr_priv.hex" | tee -a "$RUNLOG"

echo "==> PCA: Compiling (load permission, alignment, copy-on-write -- isolated)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_pca.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_perm_cow_align.sv"
echo "==> Simulating (perm/align/cow isolated)"
vvp "$SIM/sim_pca.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_perm_cow_align.hex" | tee -a "$RUNLOG"

echo "==> GUARDS: Compiling (sealed on six paths + bounds as a trap decision)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_guards.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_deref_guards.sv"
echo "==> Simulating (deref guards: sealed, bounds-as-trap)"
vvp "$SIM/sim_guards.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_deref_guards.hex" | tee -a "$RUNLOG"

echo "==> UAF: Compiling (use-after-free on all six dereference paths)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_uaf.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_uaf.sv"
echo "==> Simulating (temporal safety: stale capability, reused slot)"
vvp "$SIM/sim_uaf.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_uaf.hex" | tee -a "$RUNLOG"

echo "==> R19-1: Compiling (dereference cause ORDER, all five cow-bearing chains)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_chkorder.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_check_order.sv"
echo "==> Simulating (R19-1 check order)"
vvp "$SIM/sim_chkorder.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_check_order.hex" | tee -a "$RUNLOG"

echo "==> R23: Compiling (32-byte capability bounds + Rebind cow attenuation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r23.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r23.sv"
echo "==> Simulating (R23 bounds width + rebind cow mask)"
vvp "$SIM/sim_r23.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r23.hex" | tee -a "$RUNLOG"

echo "==> RTL-19: Compiling (copy-on-write repaired end to end)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cow_repair.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cow_repair.sv"
echo "==> Simulating (RTL-19 COW repair)"
vvp "$SIM/sim_cow_repair.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_cow_repair.hex" | tee -a "$RUNLOG"

echo "==> RTL-18: Compiling (copy-on-write)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cow_fault.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cow_fault.sv"
echo "==> Simulating (RTL-18 copy-on-write)"
vvp "$SIM/sim_cow_fault.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_cow_fault.hex" | tee -a "$RUNLOG"

echo "==> RTL-17b: Compiling (per-object bind authority, enforced)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bind_domain_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bind_domain_neg.sv"
echo "==> Simulating (RTL-17b bind authority)"
vvp "$SIM/sim_bind_domain_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_bind_domain_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-17: Compiling (the ODT policy write path)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_odt_set_domain.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_odt_set_domain.sv"
echo "==> Simulating (RTL-17 policy write path)"
vvp "$SIM/sim_odt_set_domain.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_odt_set_domain.hex" | tee -a "$RUNLOG"

echo "==> RTL-16 (R18): Compiling (the bounds check must not wrap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bounds_wrap_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bounds_wrap_neg.sv"
echo "==> Simulating (RTL-16 bounds wrap)"
vvp "$SIM/sim_bounds_wrap_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_bounds_wrap_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-14: Compiling (a failed bind must leak nothing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bind_leak_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bind_leak_neg.sv"
echo "==> Simulating (RTL-14 failed-bind leak)"
vvp "$SIM/sim_bind_leak_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_bind_leak_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-12: Compiling (rights attenuation enforced on all store paths)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_perm_enforce_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_perm_enforce_neg.sv"
echo "==> Simulating (RTL-12 permission enforcement)"
vvp "$SIM/sim_perm_enforce_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_perm_enforce_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-10 (R13): Compiling (aliased Destroy must not clear a foreign slot)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r13_alias_destroy_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r13_alias_destroy_neg.sv"
echo "==> Simulating (RTL-10 R13 aliased destroy)"
vvp "$SIM/sim_r13_alias_destroy_neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r13_alias_destroy_neg.hex" | tee -a "$RUNLOG"

echo "==> RTL-9 (R11b): Compiling (executing-object pin)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r11b_pin.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r11b_pin.sv"
echo "==> Simulating (RTL-9 R11b executing-object pin)"
vvp "$SIM/sim_r11b_pin.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r11b_pin.hex" | tee -a "$RUNLOG"

echo "==> RTL-8 (R12): Compiling (poison + deny on an unreconstructible unwind)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r12_poison.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r12_poison.sv"
echo "==> Simulating (RTL-8 R12 poison/deny)"
vvp "$SIM/sim_r12_poison.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r12_poison.hex" | tee -a "$RUNLOG"

# ═══ R49 -- SEVEN PROGRAMS WERE BUILT AND NEVER SIMULATED ══════════════════
# This script assembles EVERY veda_smoke_*.S in sim/ (96 of them) and printed
# "96 images built" -- then ran 90. Five of the missing seven had complete,
# committed testbenches and no reference anywhere in any runner
# (m15, m15_neg, m16, m16_neg, mscratch_roundtrip); the other two (m17,
# m17_neg) were referenced only by run_security_trap.sh, a demo, never by the
# regression. Nobody compared the two numbers, so the suite reported 90/90 and
# read as complete.
#
# These are not scratch files. Milestone 15 is the copy-on-write RTL mirror,
# Milestone 16 is CGetObjectID plus the end-to-end COW repair, Milestone 17 is
# the OCJALR stack-frame work. Every one of them is a security mechanism, and
# every one of them went dark across roughly twenty subsequent increments --
# R30's decode inversion, R33's base-ISA narrowing, R36/R39's privilege model,
# R38's COW eligibility split, R40, R41, R45, R47. Whether they still pass is
# a measurement, not an assumption, and it is taken below.
#
# Same family as R46 one level up: a harness that looks complete because the
# number it prints is the number it chose to print.
echo "==> Milestone 15: Compiling (copy-on-write mirror, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m15.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m15.sv"
echo "==> Simulating (Milestone 15 positive)"
vvp "$SIM/sim_m15.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m15.hex" | tee -a "$RUNLOG"

echo "==> Milestone 15: Compiling (copy-on-write mirror, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m15neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m15_neg.sv"
echo "==> Simulating (Milestone 15 negative)"
vvp "$SIM/sim_m15neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m15_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 16: Compiling (CGetObjectID + COW repair, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m16.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m16.sv"
echo "==> Simulating (Milestone 16 positive)"
vvp "$SIM/sim_m16.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m16.hex" | tee -a "$RUNLOG"

echo "==> Milestone 16: Compiling (CGetObjectID + COW repair, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m16neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m16_neg.sv"
echo "==> Simulating (Milestone 16 negative)"
vvp "$SIM/sim_m16neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m16_neg.hex" | tee -a "$RUNLOG"

echo "==> Milestone 17: Compiling (OCJALR stack frames, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m17.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m17.sv"
echo "==> Simulating (Milestone 17 positive)"
vvp "$SIM/sim_m17.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m17.hex" | tee -a "$RUNLOG"

echo "==> Milestone 17: Compiling (OCJALR stack frames, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m17neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m17_neg.sv"
echo "==> Simulating (Milestone 17 negative)"
vvp "$SIM/sim_m17neg.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_m17_neg.hex" | tee -a "$RUNLOG"

echo "==> mscratch: Compiling (mscratch round-trip)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mscratch.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mscratch_roundtrip.sv"
echo "==> Simulating (mscratch round-trip)"
vvp "$SIM/sim_mscratch.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_mscratch_roundtrip.hex" | tee -a "$RUNLOG"

echo "==> R48: Compiling (the ODA is cleared at every compartment crossing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r48.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r48_oda_crossing.sv"
echo "==> Simulating (R48 ODA crossing clear)"
vvp "$SIM/sim_r48.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r48_oda_crossing.hex" | tee -a "$RUNLOG"

echo "==> R59: Compiling (Populate/Destroy reset owner_hart)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r59.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r59_owner_reset.sv"
echo "==> Simulating (R59 owner_hart reset)"
vvp "$SIM/sim_r59.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r59_owner_reset.hex" | tee -a "$RUNLOG"

echo "==> D5: Compiling (OCRETURN releases the CRBR saved shadow)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_d5.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_d5_crbr_shadow_leak.sv"
echo "==> Simulating (D5 CRBR shadow release)"
vvp "$SIM/sim_d5.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_d5_crbr_shadow_leak.hex" | tee -a "$RUNLOG"

echo "==> R62: Compiling (set.domain must name a principal that exists)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r62.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r62_domain_nameable.sv"
echo "==> Simulating (R62 domain nameable)"
vvp "$SIM/sim_r62.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r62_domain_nameable.hex" | tee -a "$RUNLOG"

echo "==> R63: Compiling (a Populate must name a region that exists)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r63.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r63_region_write_alias.sv"
echo "==> Simulating (R63 region write alias)"
vvp "$SIM/sim_r63.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r63_region_write_alias.hex" | tee -a "$RUNLOG"

echo "==> R64: Compiling (the bind-side fault-identification channel, CSR 0x7C9)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r64.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r64_fault_object.sv"
echo "==> Simulating (R64 fault object channel)"
vvp "$SIM/sim_r64.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r64_fault_object.hex" | tee -a "$RUNLOG"

echo "==> R65: Compiling (no policy write against a Base the object has left)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r65.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r65_stale_base.sv"
echo "==> Simulating (R65 stale-base authority)"
vvp "$SIM/sim_r65.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r65_stale_base.hex" | tee -a "$RUNLOG"

echo "==> R66: Compiling (a Populate must be able to deliver a fresh generation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r66.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r66_gen_collision.sv"
echo "==> Simulating (R66 generation collision)"
vvp "$SIM/sim_r66.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r66_gen_collision.hex" | tee -a "$RUNLOG"

echo "==> R67: Compiling (a callee must not consume the caller's trap frame)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r67.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r67_frame_owner.sv"
echo "==> Simulating (R67 trap frame owner)"
vvp "$SIM/sim_r67.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r67_frame_owner.hex" | tee -a "$RUNLOG"

echo "==> R43: Compiling (Rebind must refresh an already-bound register)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r43.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r43_rebind_identity.sv"
echo "==> Simulating (R43 rebind identity)"
vvp "$SIM/sim_r43.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r43_rebind_identity.hex" | tee -a "$RUNLOG"

echo "==> R68: Compiling (no ODT write authorized against a Base the object has left)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r68.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r68_populate_stale.sv"
echo "==> Simulating (R68 populate stale base)"
vvp "$SIM/sim_r68.vvp" +veda_fixtures +elf_hex="$SIM/veda_smoke_r68_populate_stale.hex" | tee -a "$RUNLOG"

echo "==> Regression: base RV64I 81-instruction smoke test (unmodified)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_base.vvp" "$SIM/veda_core.sv" "$SIM/tb_smoke.sv"
vvp "$SIM/sim_base.vvp" +veda_fixtures | tee -a "$RUNLOG"

# ═══ R49 GUARD -- an image that is built and never simulated is a hole ═════
# The count above ("N images built") and the number of programs actually run
# were never compared, and seven drifted apart unnoticed. This is not a count
# for a human to eyeball: it is an invariant this script now enforces on
# itself, and it fails the run. Same discipline R46 put on verification.sh --
# the check has to be able to fail, or it is decoration.
echo "==> Coverage guard: every assembled image must be simulated"
unrun=0
for hex in "$SIM"/veda_smoke_*.hex; do
  b="$(basename "$hex")"
  if ! grep -q "elf_hex=\"\$SIM/$b\"" "$SELF"; then
    echo "  NEVER SIMULATED: $b"
    unrun=$((unrun+1))
  fi
done
if [ "$unrun" -ne 0 ]; then
  echo "FATAL: $unrun assembled image(s) are never simulated by this script." >&2
  echo "  A test program that is built and not run is worse than one that does not" >&2
  echo "  exist: the corpus count says it is covered." >&2
  exit 5
fi
echo "    all $(ls "$SIM"/veda_smoke_*.hex | wc -l) images are simulated"

# ═══ R49 -- THE EXIT CODE IS THE VERDICT ══════════════════════════════════
n_pass=$(grep -c 'TEST PASSED' "$RUNLOG" || true)
n_fail=$(grep -c 'TEST FAILED' "$RUNLOG" || true)
echo "==> ${n_pass} passed, ${n_fail} failed"
if [ "$n_fail" -ne 0 ]; then
  echo "FATAL: ${n_fail} testbench(es) reported *** TEST FAILED ***" >&2
  grep -B1 'TEST FAILED' "$RUNLOG" >&2
  exit 6
fi
if [ "$n_pass" -eq 0 ]; then
  echo "FATAL: no testbench reported a verdict at all" >&2
  exit 6
fi

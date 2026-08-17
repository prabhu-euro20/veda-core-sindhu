#!/usr/bin/env bash
# Transpile veda_core.tlv -> SystemVerilog (SandPiper) and simulate with
# Icarus Verilog, loading a real ELF via the +elf_hex plusarg (the same
# real mechanism the base core's own ACT4 mode already uses) and dumping
# a cycle trace for manual review -- mirrors rtl/run_smoke_test.sh's own
# proven structure, adapted for ELF loading instead of the hand-assembled
# ROM[] path (Veda-Core's own OCL/OCS only access elfmem, which is only
# populated in act4_mode).
set -euo pipefail

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

echo "==> Compiling with Icarus Verilog (positive test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke.sv"
echo "==> Simulating (positive test)"
vvp "$SIM/sim.vvp" +elf_hex="$SIM/veda_smoke_test.hex"

echo "==> Compiling with Icarus Verilog (negative control)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_neg.sv"
echo "==> Simulating (negative control)"
vvp "$SIM/sim_neg.vvp" +elf_hex="$SIM/veda_smoke_neg.hex"

echo "==> Milestone 2: Compiling (OCA + NMC_ADD + Veda-Atomic, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2.sv"
echo "==> Simulating (Milestone 2 positive)"
vvp "$SIM/sim_m2.vvp" +elf_hex="$SIM/veda_smoke_m2.hex"

echo "==> Milestone 2: Compiling (NMC_ADD missing Permit_NMC_Compute, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m2neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m2_neg.sv"
echo "==> Simulating (Milestone 2 negative: permission)"
vvp "$SIM/sim_m2neg.vvp" +elf_hex="$SIM/veda_smoke_m2_neg.hex"

echo "==> Milestone 2: Compiling (OCA out-of-bounds soft-fail, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ocaneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_oca_neg.sv"
echo "==> Simulating (Milestone 2 negative: OCA soft-fail)"
vvp "$SIM/sim_ocaneg.vvp" +elf_hex="$SIM/veda_smoke_oca_neg.hex"

echo "==> Milestone 3: Compiling (query family + CSetBounds, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m3.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m3.sv"
echo "==> Simulating (Milestone 3 positive)"
vvp "$SIM/sim_m3.vvp" +elf_hex="$SIM/veda_smoke_m3.hex"

echo "==> Milestone 3: Compiling (CSetBounds out-of-window, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_csbneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_csetbounds_neg.sv"
echo "==> Simulating (Milestone 3 negative)"
vvp "$SIM/sim_csbneg.vvp" +elf_hex="$SIM/veda_smoke_csetbounds_neg.hex"

echo "==> Milestone 4: Compiling (privilege gate + ODT-Populate/Destroy lifecycle, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4.sv"
echo "==> Simulating (Milestone 4 positive)"
vvp "$SIM/sim_m4.vvp" +elf_hex="$SIM/veda_smoke_m4.hex"

echo "==> Milestone 4: Compiling (dropped-privilege ODT-Populate, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m4neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m4_neg.sv"
echo "==> Simulating (Milestone 4 negative)"
vvp "$SIM/sim_m4neg.vvp" +elf_hex="$SIM/veda_smoke_m4_neg.hex"

echo "==> Milestone 5: Compiling (NMC_ADD.W + 8 untested Veda-Atomic ops, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m5.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m5.sv"
echo "==> Simulating (Milestone 5)"
vvp "$SIM/sim_m5.vvp" +elf_hex="$SIM/veda_smoke_m5.hex"

echo "==> Milestone 6: Compiling (CSeal/CUnseal + sealed-capability enforcement, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m6.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m6.sv"
echo "==> Simulating (Milestone 6)"
vvp "$SIM/sim_m6.vvp" +elf_hex="$SIM/veda_smoke_m6.hex"

echo "==> Milestone 7: Compiling (OCL.C/OCS.C capability-width memory access, positive+negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m7.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m7.sv"
echo "==> Simulating (Milestone 7)"
vvp "$SIM/sim_m7.vvp" +elf_hex="$SIM/veda_smoke_m7.hex"

echo "==> Milestone 8: Compiling (Rebind, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8.sv"
echo "==> Simulating (Milestone 8 positive)"
vvp "$SIM/sim_m8.vvp" +elf_hex="$SIM/veda_smoke_m8.hex"

echo "==> Milestone 8: Compiling (Rebind sealed/ODT-miss/reserved-mode, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m8neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m8_neg.sv"
echo "==> Simulating (Milestone 8 negative)"
vvp "$SIM/sim_m8neg.vvp" +elf_hex="$SIM/veda_smoke_m8_neg.hex"

echo "==> Milestone 9: Compiling (Zicsr-lite + real trap-and-resume, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m9.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m9.sv"
echo "==> Simulating (Milestone 9 positive)"
vvp "$SIM/sim_m9.vvp" +elf_hex="$SIM/veda_smoke_m9.hex"

# Milestone 1/2/6's own negative/sealed-use tests (built earlier above)
# were upgraded in-place to a real trap-handler pattern as part of
# Milestone 9 -- no separate re-run needed here, their earlier
# build/run (near Milestones 1/2/6's own sections above) already
# exercises the upgraded .S/.sv content.

echo "==> Milestone 10: Compiling (OCInvoke, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10.sv"
echo "==> Simulating (Milestone 10 positive)"
vvp "$SIM/sim_m10.vvp" +elf_hex="$SIM/veda_smoke_m10.hex"

echo "==> Milestone 10: Compiling (OCInvoke Type/Permit_Execute Violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m10neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m10_neg.sv"
echo "==> Simulating (Milestone 10 negative)"
vvp "$SIM/sim_m10neg.vvp" +elf_hex="$SIM/veda_smoke_m10_neg.hex"

echo "==> Milestone 11: Compiling (OSpecialRW + ODA-authorized ODT-Populate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11.sv"
echo "==> Simulating (Milestone 11 positive)"
vvp "$SIM/sim_m11.vvp" +elf_hex="$SIM/veda_smoke_m11.hex"

echo "==> Milestone 11: Compiling (dropped privilege + unauthorized ODA, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m11neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m11_neg.sv"
echo "==> Simulating (Milestone 11 negative)"
vvp "$SIM/sim_m11neg.vvp" +elf_hex="$SIM/veda_smoke_m11_neg.hex"

echo "==> Milestone 12: Compiling (owner-hart ODT enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12.sv"
echo "==> Simulating (Milestone 12 positive)"
vvp "$SIM/sim_m12.vvp" +elf_hex="$SIM/veda_smoke_m12.hex"

echo "==> Milestone 12: Compiling (wrong-owner hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m12neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m12_neg.sv"
echo "==> Simulating (Milestone 12 negative)"
vvp "$SIM/sim_m12neg.vvp" +elf_hex="$SIM/veda_smoke_m12_neg.hex"

echo "==> Milestone 13: Compiling (plain Bind object-not-found hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m13neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m13_neg.sv"
echo "==> Simulating (Milestone 13 negative)"
vvp "$SIM/sim_m13neg.vvp" +elf_hex="$SIM/veda_smoke_m13_neg.hex"

echo "==> Milestone 14: Compiling (PCC compartment bounding, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14.sv"
echo "==> Simulating (Milestone 14 positive)"
vvp "$SIM/sim_m14.vvp" +elf_hex="$SIM/veda_smoke_m14.hex"

echo "==> Milestone 14: Compiling (compartment escape hard-trap, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m14neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m14_neg.sv"
echo "==> Simulating (Milestone 14 negative)"
vvp "$SIM/sim_m14neg.vvp" +elf_hex="$SIM/veda_smoke_m14_neg.hex"

echo "==> Milestone 18: Compiling (VEDA_ODT_POPULATE_FAST + veda_attr CSR, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18.sv"
echo "==> Simulating (Milestone 18 positive)"
vvp "$SIM/sim_m18.vvp" +elf_hex="$SIM/veda_smoke_m18.hex"

echo "==> Milestone 18: Compiling (veda_attr-sourced Length bounds enforcement, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m18neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m18_neg.sv"
echo "==> Simulating (Milestone 18 negative)"
vvp "$SIM/sim_m18neg.vvp" +elf_hex="$SIM/veda_smoke_m18_neg.hex"

echo "==> Milestone 19: Compiling (Veda-Purecap Enforcement, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19.sv"
echo "==> Simulating (Milestone 19 positive)"
vvp "$SIM/sim_m19.vvp" +elf_hex="$SIM/veda_smoke_m19.hex"

echo "==> Milestone 19: Compiling (global purecap bit blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg.sv"
echo "==> Simulating (Milestone 19 negative 1)"
vvp "$SIM/sim_m19neg.vvp" +elf_hex="$SIM/veda_smoke_m19_neg.hex"

echo "==> Milestone 19: Compiling (OCInvoke compartment blocks ordinary ld/sd, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m19neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m19_neg2.sv"
echo "==> Simulating (Milestone 19 negative 2)"
vvp "$SIM/sim_m19neg2.vvp" +elf_hex="$SIM/veda_smoke_m19_neg2.hex"

echo "==> Milestone 20: Compiling (compartment-state CSR gate, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20.sv"
echo "==> Simulating (Milestone 20 positive)"
vvp "$SIM/sim_m20.vvp" +elf_hex="$SIM/veda_smoke_m20.hex"

echo "==> Milestone 20: Compiling (veda_pcc_length self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg.sv"
echo "==> Simulating (Milestone 20 negative 1)"
vvp "$SIM/sim_m20neg.vvp" +elf_hex="$SIM/veda_smoke_m20_neg.hex"

echo "==> Milestone 20: Compiling (veda_mode self-escape, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m20neg2.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m20_neg2.sv"
echo "==> Simulating (Milestone 20 negative 2)"
vvp "$SIM/sim_m20neg2.vvp" +elf_hex="$SIM/veda_smoke_m20_neg2.hex"

echo "==> Compiling (Veda-Atomic aq/rl invariance)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_aqrl.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_aqrl_invariance.sv"
echo "==> Simulating (aq/rl invariance)"
vvp "$SIM/sim_aqrl.vvp" +elf_hex="$SIM/veda_smoke_aqrl_invariance.hex"

echo "==> Milestone 22: Compiling (OCJALR compartment-boundary scope, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m22.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m22.sv"
echo "==> Simulating (Milestone 22)"
vvp "$SIM/sim_m22.vvp" +elf_hex="$SIM/veda_smoke_m22.hex"

echo "==> Minimal OS kernel Milestone A: Compiling (TSC round-trip via OSpecialRW selector, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosA_tsc.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosA_tsc.sv"
echo "==> Simulating (minimal OS kernel Milestone A)"
vvp "$SIM/sim_mosA_tsc.vvp" +elf_hex="$SIM/veda_smoke_mosA_tsc.hex"

echo "==> Minimal OS kernel Milestone B: Compiling (CSealEntry + OCRETURN, positive, RTL parity with Sail)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry.sv"
echo "==> Simulating (minimal OS kernel Milestone B positive)"
vvp "$SIM/sim_mosB_sentry.vvp" +elf_hex="$SIM/veda_smoke_mosB_sentry.hex"

echo "==> Minimal OS kernel Milestone B: Compiling (CSeal forgery blocked + OCRETURN tag violation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mosB_sentry_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mosB_sentry_neg.sv"
echo "==> Simulating (minimal OS kernel Milestone B negative)"
vvp "$SIM/sim_mosB_sentry_neg.vvp" +elf_hex="$SIM/veda_smoke_mosB_sentry_neg.hex"

echo "==> Milestone 23: Compiling (real ECALL support, baseline unbounded context)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall.sv"
echo "==> Simulating (Milestone 23 ECALL baseline)"
vvp "$SIM/sim_m23_ecall.vvp" +elf_hex="$SIM/veda_smoke_m23_ecall.hex"

echo "==> Milestone 23: Compiling (real ECALL support, from inside a live OCInvoke compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_ecall_compartment.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_ecall_compartment.sv"
echo "==> Simulating (Milestone 23 ECALL compartment)"
vvp "$SIM/sim_m23_ecall_compartment.vvp" +elf_hex="$SIM/veda_smoke_m23_ecall_compartment.hex"

echo "==> Milestone 23: Compiling (RTL mirror of Sail Milestone C: real cooperative scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m23_scheduler.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m23_scheduler.sv"
echo "==> Simulating (Milestone 23 cooperative scheduler)"
vvp "$SIM/sim_m23_scheduler.vvp" +elf_hex="$SIM/veda_smoke_m23_scheduler.hex"

echo "==> SSC: Compiling (Stack-Spill Capability round-trip, third SCR independent of ODA/TSC)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_roundtrip.sv"
echo "==> Simulating (SSC roundtrip)"
vvp "$SIM/sim_ssc_roundtrip.vvp" +elf_hex="$SIM/veda_smoke_ssc_roundtrip.hex"

echo "==> SSC: Compiling (OCInvoke clears SSC on every compartment-boundary crossing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_ocinvoke_clear.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_ocinvoke_clear.sv"
echo "==> Simulating (SSC OCInvoke clear)"
vvp "$SIM/sim_ssc_ocinvoke_clear.vvp" +elf_hex="$SIM/veda_smoke_ssc_ocinvoke_clear.hex"

echo "==> SSC: Compiling (real spill/reload sequence inside a compartment)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_spill_reload.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_spill_reload.sv"
echo "==> Simulating (SSC spill/reload)"
vvp "$SIM/sim_ssc_spill_reload.vvp" +elf_hex="$SIM/veda_smoke_ssc_spill_reload.hex"

echo "==> SSC: Compiling (out-of-bounds access, real Bounds Violation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_oob.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_oob.sv"
echo "==> Simulating (SSC OOB)"
vvp "$SIM/sim_ssc_oob.vvp" +elf_hex="$SIM/veda_smoke_ssc_oob.hex"

echo "==> SSC: Compiling (cross-thread isolation via the real scheduler)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_ssc_cross_thread.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_ssc_cross_thread.sv"
echo "==> Simulating (SSC cross-thread isolation)"
vvp "$SIM/sim_ssc_cross_thread.vvp" +elf_hex="$SIM/veda_smoke_ssc_cross_thread.hex"

echo "==> Milestone 24: Compiling (real DRAM-latency stall FSM, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24lat.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_latency.sv"
echo "==> Simulating (Milestone 24 latency)"
vvp "$SIM/sim_m24lat.vvp" +elf_hex="$SIM/veda_smoke_m24_latency.hex"

echo "==> Milestone 24 Stage 2: Compiling (TCM ODT tier, no-op-at-E=0 regression check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24odttcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_odt_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 2 ODT TCM tier)"
vvp "$SIM/sim_m24odttcm.vvp" +elf_hex="$SIM/veda_smoke_m24_odt_tcm.hex"

echo "==> Milestone 24 Stage 3: Compiling (TCM capability-spill scratch, OCL.C/OCS.C address-range mux)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_m24ocsctcm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_m24_ocsc_tcm.sv"
echo "==> Simulating (Milestone 24 Stage 3 OCL.C/OCS.C TCM scratch)"
vvp "$SIM/sim_m24ocsctcm.vvp" +elf_hex="$SIM/veda_smoke_m24_ocsc_tcm.hex"

echo "==> RTL M21-restore mirror: Compiling (automatic PCC restore-on-mret, 3 real properties)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_pcc_restore.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_pcc_restore_on_mret.sv"
echo "==> Simulating (RTL M21-restore mirror)"
vvp "$SIM/sim_pcc_restore.vvp" +elf_hex="$SIM/veda_smoke_pcc_restore_on_mret.hex"

echo "==> RTL M27-mtvec-gate mirror: Compiling (mtvec self-escape from a live compartment must hard-trap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_mtvec_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_mtvec_escape_neg.sv"
echo "==> Simulating (RTL M27-mtvec-gate mirror)"
vvp "$SIM/sim_mtvec_neg.vvp" +elf_hex="$SIM/veda_smoke_mtvec_escape_neg.hex"

echo "==> RTL Part C (Task #297 mirror): Compiling (real KERNEL ecall dispatcher, sys_write/sys_exit)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0k.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel.sv"
echo "==> Simulating (RTL Part C: syscall0 kernel)"
vvp "$SIM/sim_s0k.vvp" +elf_hex="$SIM/veda_smoke_syscall0_kernel.hex"

echo "==> RTL Part D (Task #299 mirror): Compiling (forged, never-populated Object_ID negative test)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_s0kneg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_syscall0_kernel_forged_neg.sv"
echo "==> Simulating (RTL Part D: syscall0 kernel forged-Object_ID negative)"
vvp "$SIM/sim_s0kneg.vvp" +elf_hex="$SIM/veda_smoke_syscall0_kernel_forged_neg.hex"

echo "==> RTL-2a: Compiling (32-byte tag granule -- plain store into byte 16 destroys a stored capability's tag)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_granule_tamper.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap_granule_tamper.sv"
echo "==> Simulating (RTL-2a granule tamper)"
vvp "$SIM/sim_granule_tamper.vvp" +elf_hex="$SIM/veda_smoke_cap_granule_tamper.hex"

echo "==> RTL-2a: Compiling (32-byte alignment -- misaligned OCS.C hard-traps, cause 0x08)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_misaligned.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap_misaligned_neg.sv"
echo "==> Simulating (RTL-2a misaligned)"
vvp "$SIM/sim_misaligned.vvp" +elf_hex="$SIM/veda_smoke_cap_misaligned_neg.hex"

echo "==> CAndPerm: Compiling (rights attenuation, positive)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_candperm.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_candperm.sv"
echo "==> Simulating (CAndPerm positive)"
vvp "$SIM/sim_candperm.vvp" +elf_hex="$SIM/veda_smoke_candperm.hex"

echo "==> CAndPerm: Compiling (sealed source soft-fails, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_candperm_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_candperm_neg.sv"
echo "==> Simulating (CAndPerm negative)"
vvp "$SIM/sim_candperm_neg.vvp" +elf_hex="$SIM/veda_smoke_candperm_neg.hex"

echo "==> RTL-2b: Compiling (256-bit capability -- every field exact across a memory round-trip)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cap256.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cap256_roundtrip.sv"
echo "==> Simulating (RTL-2b 256-bit round-trip)"
vvp "$SIM/sim_cap256.vvp" +elf_hex="$SIM/veda_smoke_cap256_roundtrip.hex"

echo "==> RTL-4 DESIGN_08: Compiling (global uniqueness across regions + dereference re-check)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_unique.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_unique.sv"
echo "==> Simulating (RTL-4 region uniqueness)"
vvp "$SIM/sim_region_unique.vvp" +elf_hex="$SIM/veda_smoke_region_unique.hex"

echo "==> RTL-4 DESIGN_08: Compiling (CRBR fast path -- fixed-shape read count)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fastpath.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fastpath.sv"
echo "==> Simulating (RTL-4 CRBR fast path)"
vvp "$SIM/sim_region_fastpath.vvp" +elf_hex="$SIM/veda_smoke_region_fastpath.hex"

echo "==> RTL-4 DESIGN_08: Compiling (explicit REGION_FAULT, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fault_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fault_neg.sv"
echo "==> Simulating (RTL-4 region fault)"
vvp "$SIM/sim_region_fault_neg.vvp" +elf_hex="$SIM/veda_smoke_region_fault_neg.hex"

echo "==> RTL-4 DESIGN_08: Compiling (REGION_FAULT covers all bind modes, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_region_fault_modes_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_region_fault_modes_neg.sv"
echo "==> Simulating (RTL-4 region fault, all bind modes)"
vvp "$SIM/sim_region_fault_modes_neg.vvp" +elf_hex="$SIM/veda_smoke_region_fault_modes_neg.hex"

echo "==> RTL-5 R10: Compiling (CRBR round-trip across invoke/trap/mret/return)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r10_roundtrip.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r10_crbr_roundtrip.sv"
echo "==> Simulating (RTL-5 R10 CRBR round-trip)"
vvp "$SIM/sim_r10_roundtrip.vvp" +elf_hex="$SIM/veda_smoke_r10_crbr_roundtrip.hex"

echo "==> RTL-5 R10: Compiling (crossing into a paged-out domain, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r10_fault_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r10_crossing_fault_neg.sv"
echo "==> Simulating (RTL-5 R10 crossing fault)"
vvp "$SIM/sim_r10_fault_neg.vvp" +elf_hex="$SIM/veda_smoke_r10_crossing_fault_neg.hex"

echo "==> RTL-6: Compiling (object residency gate, all three bind modes)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency.sv"
echo "==> Simulating (RTL-6 object residency gate)"
vvp "$SIM/sim_residency.vvp" +elf_hex="$SIM/veda_smoke_residency.hex"

echo "==> RTL-6: Compiling (residency cause ordering, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency_order_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency_order_neg.sv"
echo "==> Simulating (RTL-6 residency cause ordering)"
vvp "$SIM/sim_residency_order_neg.vvp" +elf_hex="$SIM/veda_smoke_residency_order_neg.hex"

echo "==> RTL-6b: Compiling (dereference-side residency, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_residency_deref_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_residency_deref_neg.sv"
echo "==> Simulating (RTL-6b dereference-side residency)"
vvp "$SIM/sim_residency_deref_neg.vvp" +elf_hex="$SIM/veda_smoke_residency_deref_neg.hex"

echo "==> RTL-6c: Compiling (page-out/page-in cycle + preservation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_paging.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_paging.sv"
echo "==> Simulating (RTL-6c paging cycle)"
vvp "$SIM/sim_paging.vvp" +elf_hex="$SIM/veda_smoke_paging.hex"

echo "==> RTL-6c: Compiling (paging refusals, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_paging_refusals_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_paging_refusals_neg.sv"
echo "==> Simulating (RTL-6c paging refusals)"
vvp "$SIM/sim_paging_refusals_neg.vvp" +elf_hex="$SIM/veda_smoke_paging_refusals_neg.hex"

echo "==> RTL-7: Compiling (R11 crossing revalidation, negative)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r11_crossing_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r11_crossing_neg.sv"
echo "==> Simulating (RTL-7 R11 crossing revalidation)"
vvp "$SIM/sim_r11_crossing_neg.vvp" +elf_hex="$SIM/veda_smoke_r11_crossing_neg.hex"

echo "==> R24: Compiling (capability register file reset state)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r24.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r24_crf_reset.sv"
echo "==> Simulating (R24 CRF reset / rebind into an untouched register)"
vvp "$SIM/sim_r24.vvp" +elf_hex="$SIM/veda_smoke_r24_crf_reset.hex"

echo "==> R26: Compiling (compartment authority follows the NAME, not the bound)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r26.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r26_authority.sv"
echo "==> Simulating (R26 sentinel-Length compartment escape)"
vvp "$SIM/sim_r26.vvp" +elf_hex="$SIM/veda_smoke_r26_authority.hex"

echo "==> R27: Compiling (privilege gate on the PCC/MEPCC CSRs)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r27.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r27_csr_priv.sv"
echo "==> Simulating (R27 CSR privilege gate)"
vvp "$SIM/sim_r27.vvp" +elf_hex="$SIM/veda_smoke_r27_csr_priv.hex"

echo "==> PCA: Compiling (load permission, alignment, copy-on-write -- isolated)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_pca.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_perm_cow_align.sv"
echo "==> Simulating (perm/align/cow isolated)"
vvp "$SIM/sim_pca.vvp" +elf_hex="$SIM/veda_smoke_perm_cow_align.hex"

echo "==> GUARDS: Compiling (sealed on six paths + bounds as a trap decision)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_guards.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_deref_guards.sv"
echo "==> Simulating (deref guards: sealed, bounds-as-trap)"
vvp "$SIM/sim_guards.vvp" +elf_hex="$SIM/veda_smoke_deref_guards.hex"

echo "==> UAF: Compiling (use-after-free on all six dereference paths)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_uaf.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_uaf.sv"
echo "==> Simulating (temporal safety: stale capability, reused slot)"
vvp "$SIM/sim_uaf.vvp" +elf_hex="$SIM/veda_smoke_uaf.hex"

echo "==> R19-1: Compiling (dereference cause ORDER, all five cow-bearing chains)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_chkorder.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_check_order.sv"
echo "==> Simulating (R19-1 check order)"
vvp "$SIM/sim_chkorder.vvp" +elf_hex="$SIM/veda_smoke_check_order.hex"

echo "==> R23: Compiling (32-byte capability bounds + Rebind cow attenuation)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r23.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r23.sv"
echo "==> Simulating (R23 bounds width + rebind cow mask)"
vvp "$SIM/sim_r23.vvp" +elf_hex="$SIM/veda_smoke_r23.hex"

echo "==> RTL-19: Compiling (copy-on-write repaired end to end)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cow_repair.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cow_repair.sv"
echo "==> Simulating (RTL-19 COW repair)"
vvp "$SIM/sim_cow_repair.vvp" +elf_hex="$SIM/veda_smoke_cow_repair.hex"

echo "==> RTL-18: Compiling (copy-on-write)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_cow_fault.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_cow_fault.sv"
echo "==> Simulating (RTL-18 copy-on-write)"
vvp "$SIM/sim_cow_fault.vvp" +elf_hex="$SIM/veda_smoke_cow_fault.hex"

echo "==> RTL-17b: Compiling (per-object bind authority, enforced)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bind_domain_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bind_domain_neg.sv"
echo "==> Simulating (RTL-17b bind authority)"
vvp "$SIM/sim_bind_domain_neg.vvp" +elf_hex="$SIM/veda_smoke_bind_domain_neg.hex"

echo "==> RTL-17: Compiling (the ODT policy write path)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_odt_set_domain.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_odt_set_domain.sv"
echo "==> Simulating (RTL-17 policy write path)"
vvp "$SIM/sim_odt_set_domain.vvp" +elf_hex="$SIM/veda_smoke_odt_set_domain.hex"

echo "==> RTL-16 (R18): Compiling (the bounds check must not wrap)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bounds_wrap_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bounds_wrap_neg.sv"
echo "==> Simulating (RTL-16 bounds wrap)"
vvp "$SIM/sim_bounds_wrap_neg.vvp" +elf_hex="$SIM/veda_smoke_bounds_wrap_neg.hex"

echo "==> RTL-14: Compiling (a failed bind must leak nothing)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_bind_leak_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_bind_leak_neg.sv"
echo "==> Simulating (RTL-14 failed-bind leak)"
vvp "$SIM/sim_bind_leak_neg.vvp" +elf_hex="$SIM/veda_smoke_bind_leak_neg.hex"

echo "==> RTL-12: Compiling (rights attenuation enforced on all store paths)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_perm_enforce_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_perm_enforce_neg.sv"
echo "==> Simulating (RTL-12 permission enforcement)"
vvp "$SIM/sim_perm_enforce_neg.vvp" +elf_hex="$SIM/veda_smoke_perm_enforce_neg.hex"

echo "==> RTL-10 (R13): Compiling (aliased Destroy must not clear a foreign slot)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r13_alias_destroy_neg.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r13_alias_destroy_neg.sv"
echo "==> Simulating (RTL-10 R13 aliased destroy)"
vvp "$SIM/sim_r13_alias_destroy_neg.vvp" +elf_hex="$SIM/veda_smoke_r13_alias_destroy_neg.hex"

echo "==> RTL-9 (R11b): Compiling (executing-object pin)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r11b_pin.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r11b_pin.sv"
echo "==> Simulating (RTL-9 R11b executing-object pin)"
vvp "$SIM/sim_r11b_pin.vvp" +elf_hex="$SIM/veda_smoke_r11b_pin.hex"

echo "==> RTL-8 (R12): Compiling (poison + deny on an unreconstructible unwind)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_r12_poison.vvp" "$SIM/veda_core.sv" "$SIM/tb_veda_smoke_r12_poison.sv"
echo "==> Simulating (RTL-8 R12 poison/deny)"
vvp "$SIM/sim_r12_poison.vvp" +elf_hex="$SIM/veda_smoke_r12_poison.hex"

echo "==> Regression: base RV64I 81-instruction smoke test (unmodified)"
iverilog -g2012 -I "$SIM" -o "$SIM/sim_base.vvp" "$SIM/veda_core.sv" "$SIM/tb_smoke.sv"
vvp "$SIM/sim_base.vvp"

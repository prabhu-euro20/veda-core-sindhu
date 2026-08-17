#!/usr/bin/env bash
# Cross-layer differential suite.
#
# WHY THIS FILE EXISTS. rundiff.sh could not fail -- both its branches ended in
# an echo under `set -uo pipefail` with no -e, so it returned 0 on a divergence
# it had just printed -- and nothing invoked it: one line in a README was its
# entire caller. A comparator that cannot fail and that nobody runs is not
# verification, it is a script. This is the caller, and it holds the verdicts.
#
# EXPECTED VERDICTS ARE RECORDED, NOT ASSUMED GREEN. A probe that is KNOWN to
# diverge is listed as DIVERGE with the reason. That is deliberate: hiding a real
# divergence behind an all-must-agree suite would be the same mistake as a green
# suite measuring the wrong artifact. Either direction is a failure -- an
# expected-AGREE probe that diverges, and an expected-DIVERGE probe that either
# agrees (the open item closed, update this file) or diverges DIFFERENTLY.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D"

# probe                 expected   why
EXPECTED="
probe0.S                AGREE      smoke: the harness itself
p1_queries.S            AGREE      the metadata query family
p2_derive.S             AGREE      CSetBounds / CAndPerm derivation -- R30 CLOSED, so its
p3_faults.S             DIVERGE    R24 open half, second sighting: word 6 is mtval from
p4_cow.S                AGREE      copy-on-write attenuation and the COW fault
p5_reserved.S           AGREE      R30 CLOSED: three classes of unallocated encoding, all
p6_overbroad.S          AGREE      R30 CLOSED: the four over-broad decoders are narrowed
p7_csr_space.S          AGREE      R32 CLOSED: undefined CSR addresses and read-only
p8_reserved_bits.S      AGREE      R30(b) CLOSED: reserved-zero fields inside allocated
p9_tag_destroy.S        DIVERGE    R33a CLOSED the capability kill; the remaining word is
p_reset_crf.S           DIVERGE    R24 open half: c10-c14 only. Both layers seed TEST
"
#                                  FIXTURES inside the architectural reset, at
#                                  different indices with different contents. c0-c9
#                                  and c15 converged when Sail gained veda_reset_crf().
#                                  Getting the fixtures out of reset is its own
#                                  increment -- see DESIGN_07 R24.
#
# p2_derive word 12 is the trap counter: Sail 1, RTL 0. The instruction is
# custom-0/funct3=000/funct7=0001010, which is NOT a defined encoding -- that
# space holds only 0000011 Populate, 0000100 Populate-Fast, 0000101 page-in.
# Sail raises Illegal_Instruction, correctly. The RTL silently executes nothing:
# $veda_illegal_instr is a list of specific refusals with no catch-all for
# unrecognised encodings in the Veda opcodes. A core that silently ignores
# instructions it does not know is a NOP sled through anything the model refuses.
# The probe's author meant to write OCA (which is custom-2/funct3=001) and typed
# the wrong opcode; the typo found a real defect. See DESIGN_07 R30.
#
# p3_faults word 6 is mtval: Sail 0x162 = (c11<<5)|0x02, RTL 0x16a =
# (c11<<5)|0x0A. The instruction dereferences c11 -- a FIXTURE register. Sail's
# c11 is a sealed region-2 capability whose generation is stale; the RTL's is
# the residency fixture. Same root cause as p_reset_crf, seen through a second
# probe, and it closes when the fixtures leave the architectural reset.
#
# p5_reserved measures three DISTINCT classes of unallocated encoding, all
# retired as no-ops here and all refused by Sail:
#   veda.bind mode 0b11 -- NOT merely undefined. veda_bind_insts.sail:276 maps
#     VEDA_BIND_RESERVED to Illegal_Instruction() BY NAME, and veda_core.tlv
#     decodes only modes 00/01/10 with no arm for 11 at all.
#   custom-0 funct3=000 funct7=0001010 -- 125 of 128 funct7 values unallocated.
#   custom-2 funct3=111 -- the whole funct3 is unallocated.
# Its control proves a LEGAL encoding still does not trap, so a layer that
# simply refused everything could not pass it.
#
# p6_overbroad is the worse half, and it is NOT about no-ops. Here the RTL
# decodes encodings the architecture never allocated and executes them AS A
# DEFINED INSTRUCTION. Measured:
#   veda.bind with imm[11:2] != 0 MINTS A CAPABILITY on this layer -- cgettag
#     reads 1 -- while Sail refuses the instruction outright. 1023 of 1024
#     upper-immediate patterns, on the capability-minting path.
#   OSpecialRW with an SCR selector outside {ODA,TSC,SSC} performs the ODA swap.
#     Machine-mode only, so NOT an unprivileged escalation -- an unallocated
#     encoding operating an authority register, which is bad enough.
#   droppriv ignores funct3 entirely, so all 8 values clear $priv.
#   the atomic op-select case is the one the RTL already guards, and the probe
#     records that too rather than assuming it alongside the others.
#
# ALL FOUR NOW AGREE -- the catch-all landed and these four lines are the
# evidence. They were recorded as DIVERGE first, deliberately, so that closing
# the finding had to come back through this file: an expected-DIVERGE probe that
# starts agreeing FAILS the suite until someone updates the verdict, which is how
# a fix gets noticed rather than assumed. p2_derive is the sharpest of the four:
# its own header records a draft where a wrong funct3 "decodes as nothing -- and
# the probe still reported AGREE, because BOTH layers did the same no-op." That
# encoding now traps on both, so the probe is a real derivation test again.
# DESIGN_07 R30 and R32.
#
# p8_reserved_bits covers the layer BELOW opcode/funct3/funct7 granularity. Every
# capability operand is a 4-bit field inside a 5-bit RISC-V register slot,
# because the capability register file has sixteen entries -- so the spare bit is
# reserved, and it is the extension budget. Ignored, `cseal c2, c1, c17` uses c1
# as the sealing AUTHORITY here while a 32-register successor would use c17:
# register-index aliasing, which in a capability machine means the wrong
# authority. Five classes measured separately -- bit19 above vcap rs1, bit11
# above vcap rd, bit24 above vcap rs2, a nonzero rd on an instruction with no
# destination, a nonzero rs2 on a slot pinned to zero -- with a control proving
# the same instructions at their legal encodings still do not trap.
#
# The seven ODT instructions have ALL-GPR operands and therefore NO reserved
# bits. That distinction was derived by parsing every encdec clause's field
# roles, not assumed, and applying the terms uniformly would have broken them.
#
# p9_tag_destroy is the base ISA, not Veda's space, and it found the sharpest
# thing in this whole sweep. The store block gates its DATA write on an
# if/else-if chain over the four widths with no else -- so an unallocated store
# writes nothing and looks harmless -- while the TAG INVALIDATION is a separate
# if gated only on the $is_store umbrella, which was `$op_is_store`, opcode only.
# A store with funct3 in {100,101,110,111} therefore CLEARED THE CAPABILITY TAG
# and wrote no data: a silent capability kill from an instruction RV64I does not
# define. Measured, then closed by narrowing the umbrella to the OR of the four
# width terminals. Its control proves a LEGAL store clears the tag on both
# layers, so the probe is not merely observing that stores clear tags.
#
# It stays DIVERGE on ONE word -- the trap count. R33a closed the destructive
# side effect; the catch-all that makes the encoding actually TRAP is R33b, kept
# separate on purpose because the two halves have opposite risk signatures.
# R33a is behaviour-identical for every legitimate instruction (ACT4 51/51 and
# smoke 88/88 unchanged, as predicted); R33b is a behaviour change by design.
# Merging them would destroy the ability to attribute a red suite to one of
# them. DESIGN_07 R33.
#
# p7_csr_space is a SEPARATE surface and the encoding catch-all cannot reach it.
# Sail is fail-closed for CSR addresses by the same construction it uses for
# encodings -- postlude/csr_end.sail:11 is a last wildcard
# `is_CSR_accessible(_) = false` -- and veda_regs.sail declares 0x7C0..0x7C8
# only. The RTL has NO address-validity term anywhere: $csr_rdata's default arm
# is 64'b0. Measured: csrrw on 0x7C9 traps on Sail and reads ZERO here, silently.
# Zero is worse than a no-op, because it is a value software can act on. An
# opcode-keyed catch-all cannot help: a CSR access is opcode 1110011, not one of
# the four custom opcodes. Two fail-open surfaces, two fixes. DESIGN_07 R32.

pass=0; fail=0; results=()
while read -r probe expected _rest; do
  [ -z "${probe:-}" ] && continue
  out="$(./rundiff.sh "probes/$probe" 2>&1)"; rc=$?
  case $rc in
    0) got=AGREE ;;
    1) got=DIVERGE ;;
    *) got=ERROR ;;
  esac
  if [ "$got" = "$expected" ]; then
    if [ "$got" = "DIVERGE" ]; then
      # An expected divergence must stay the SAME divergence. Pin the word list.
      name="${probe%.S}"
      sig="$(diff "$name.s8" "$name.r8" | md5sum | cut -c1-12)"
      if [ -f "$name.divergence" ]; then
        if [ "$sig" != "$(cat "$name.divergence")" ]; then
          results+=("FAIL      $probe -- diverges, but DIFFERENTLY than recorded"); fail=$((fail+1)); continue
        fi
      else
        echo "$sig" > "$name.divergence"
        results+=("BASELINE  $probe -- recorded the known divergence"); pass=$((pass+1)); continue
      fi
    fi
    results+=("ok        $probe ($got)"); pass=$((pass+1))
  else
    results+=("FAIL      $probe -- expected $expected, got $got"); fail=$((fail+1))
    echo "$out" | head -30
  fi
done <<< "$EXPECTED"

echo "=== cross-layer differential results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass/$((pass+fail)) as expected"
[ "$fail" -eq 0 ] || exit 1

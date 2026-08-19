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
p3_faults.S             AGREE      the dereference fault causes -- its c11 divergence was the
p4_cow.S                AGREE      copy-on-write attenuation and the COW fault
p5_reserved.S           AGREE      R30 CLOSED: three classes of unallocated encoding, all
p6_overbroad.S          AGREE      R30 CLOSED: the four over-broad decoders are narrowed
p7_csr_space.S          AGREE      R32 CLOSED: undefined CSR addresses and read-only
p8_reserved_bits.S      AGREE      R30(b) CLOSED: reserved-zero fields inside allocated
p10_ebreak.S            AGREE      R33d: EBREAK is mcause 3 with mtval = the faulting PC
p11_csr_forms.S         AGREE      R33c: all six Zicsr forms, and R32 now sees them
p9_tag_destroy.S        AGREE      R33 CLOSED: the capability kill AND the trap
p12_ambient_boot.S      AGREE      R34: the boot context has AMBIENT authority. Both
p_reset_crf.S           AGREE      R24 CLOSED: all 16 capability registers agree at reset
p13_scr_reset.S         AGREE      R37 CLOSED: the three Special Capability Registers
p14_cow_eligibility.S   AGREE      R38: the COW fault asks WHETHER, never WHO. Both layers
p15_priv_model.S        AGREE      R36/R39 CLOSED: the two layers finally share a privilege
p16_populate_policy_reset.S AGREE  R41 CLOSED: a Populate mints a NEW object, so the previous
p17_cap_perm_flow.S     AGREE      R40 CLOSED: PERM_LOAD_CAPABILITY and PERM_STORE_CAPABILITY are
p18_cow_not_pageable.S  AGREE      R38(b) CLOSED: page.out refuses on a copy-on-write object
p19_bind_reserved_mode.S AGREE     R44 CLOSED: bind mode 0b11 refused at DECODE on both layers
p20_oda_scope.S         AGREE      R47 CLOSED: the ODA's window is load-bearing on the delegated path
p22_csetbounds_width.S  AGREE      R53 CLOSED: CSetBounds is computed at the widened widths on both layers
p23_oclear.S            AGREE      R50 increment 1: OCLEAR zeroes the VALUE, keeps otype UNSEALED
p21_oda_crossing.S      AGREE      R48 CLOSED cross-layer: the ODA is cleared at every crossing
p24_mtvec_mode.S        AGREE      R80 CLOSED: mtvec MODE is read-only zero on both layers. Before
p25_privilege_drop_root.S AGREE    R79 CLOSED: ambient root is Machine-or-ODA only, so User code entered
p26_oda_bind_window.S   AGREE      R81 CLOSED: the ODA's window bounds what it BINDS, not only what it creates
"
#                                  occupant's cow and owner_domain must not attach to it. Plain
#                                  Populate carried both on Sail and cleared both on the RTL, and
#                                  the two Sail populate variants disagreed with each other.
#                                  Measured before the fix: w0 Sail 0x04 / RTL 0x0C, w1 Sail 1 trap
#                                  / RTL 0 -- on Sail the freshly minted object was born unwritable,
#                                  because R38 made cow decide who may write and an object born cow
#                                  has no principal who held store when it became cow. No probe had
#                                  ever composed Populate with set.cow, which is how a two-field
#                                  divergence sat inside a harness reporting 16/16.
#
# p17_cap_perm_flow: enforced on both layers at OCL.C/OCS.C -- the only two
# instructions that move AUTHORITY through memory. Before R40 a delegation
# attenuated to data-only with CAndPerm could still lift a live, tagged
# capability out of the bytes it was allowed to read, gaining authority over an
# object it was never given. The probe carries a positive control (the owner CAN
# spill and reload) so a layer that simply refused OCL.C outright could not pass
# it, and it records the refusal's cap_idx as the DEREFERENCED capability rather
# than the destination -- the distinction that a bisection caught in the first
# draft of the Sail test's expected value.
#
# p18_cow_not_pageable: R38 put the copy-on-write split right in the live
# capabilities that predate set.cow, and page.out exists to destroy exactly those
# -- it bumps the generation while carrying `cow` across, so one round trip left
# an object nobody could ever split. Clearing `cow` is NOT the recovery it looks
# like: on a genuinely shared object it lets every sharer write the same object,
# which is the isolation copy-on-write was providing. The refusal therefore sits
# at the instruction that destroys the evidence. The probe's w2 is the whole
# increment -- the entitlement is still there afterwards -- and w3 is the control
# that a NON-cow object still pages out and back in cleanly.
#                                  mechanism, so privileged behaviour can be compared at all
#                                  -- p13's own header recorded that it could not be. MPP,
#                                  the U-mode CSR refusal and its cause, MRET-below-Machine,
#                                  and the ecall cause, with an arithmetic control so that
#                                  "both layers trapped everything" cannot pass as agreement.
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
# p10_ebreak and p11_csr_forms are the class-B debts, and they had to close
# BEFORE the catch-all. Both are ALLOCATED in the claimed ISA and were missing,
# so a catch-all would have turned a missing FEATURE into illegal-instruction --
# a different wrong answer, and one no test here could have caught. EBREAK wants
# mcause 3 with mtval = the faulting PC, both MEASURED against this project's own
# Sail config rather than assumed, since the breakpoint mtval is policy-
# controlled. The four CSR forms want a real read-modify-write, including the
# rule that a SET or CLEAR with a zero source is a pure read that must not write
# -- which is what `csrr` expands to and what every trap handler here depends on.
#
# The CSR forms also completed R32, which had already shipped: $veda_csr_undef
# is gated on $is_csr_access, and that was the OR of CSRRW and CSRRS only, so a
# csrrci to a nonexistent CSR was doubly silent. p11 w10 pins that.
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

# ═══ R49/R51 GUARD -- a probe that exists and is not listed is a dark test ══
# p21_oda_crossing.S measured nothing and reported AGREE, and the only reason
# that was caught is that its signature was read word by word rather than
# trusted. Its successor failure mode would have been quieter still: leave the
# file in probes/ and drop it from the table, and it becomes a test nobody runs
# and nobody misses. Refuse instead.
for f in "$D"/probes/*.S; do
  b="$(basename "$f")"
  if ! echo "$EXPECTED" | grep -q "^$b"; then
    echo "FATAL: $b exists in probes/ but has no expected verdict -- it would never run." >&2
    echo "  Add it to the EXPECTED table, or move it to difftest/blocked/ with a reason." >&2
    exit 2
  fi
done

echo "=== cross-layer differential results ==="
for r in "${results[@]}"; do echo "$r"; done
echo "---"
echo "$pass/$((pass+fail)) as expected"
[ "$fail" -eq 0 ] || exit 1

# p19_bind_reserved_mode -- R44. veda.bind mode 0b11 is VEDA_BIND_RESERVED, an
# encoding the architecture never allocated. On Sail it used to reach its
# Illegal_Instruction arm only AFTER three state-dependent traps had had their
# chance -- region residency, the per-object domain gate, and object residency --
# so the refusal CAUSE for an unallocated encoding was a function of ODT and
# region state the instruction was never entitled to consult. Unprivileged code
# could issue reserved-mode binds and read the cause as an ODT ORACLE. The RTL
# always refused at decode.
#
# MEASURED BEFORE THE FIX: w0 mcause Sail 0x18 vs RTL 0x02; w1 mtval Sail 0x49,
# which is (c2 << 5) | 0x09 REGION_FAULT, vs the RTL's raw instruction word.
# AFTER: 0x02 and the raw word on both.
#
# w2 is the control -- Object_ID 1, region 0, resident -- and it is exactly the
# only case p5_reserved.S ever exercised. That probe also never read mcause at
# all, so it reported AGREE throughout while the layers disagreed. Both blind
# spots are closed: p5 now records the cause of each of its three refusals.

# p20_oda_scope -- R47. veda_oda_authorized() is three terms wide on both layers
# (tag, otype, Perms[7]); Base, Length, Offset and Object_ID -- 196 of the ODA's
# 256 bits -- were consulted by none of the seven instructions it authorizes. So
# the delegated authority to write the Object Descriptor Table was a bearer
# token over ALL of memory: any ODA holder could mint a descriptor naming any
# Base with any Perms, Bind it, and dereference it.
#
# THE MEASUREMENT WAS ALREADY IN THE RTL SUITE, PASSING. rtl/sim/veda_smoke_m11.S
# installed an ODA whose window is [0x80011000, 0x80011040), dropped to User, and
# from User minted object 41 at Base 0x80012000 -- four kilobytes outside it --
# then Bound it and read back its Base as proof. Its own comment calls that "the
# real proof" the ODA path works, and it is; it was also the escape, pinned as
# the contract by a green test. That file now mints INSIDE its window and the
# refusal half lives here, where both layers must agree.
#
# MEASURED AFTER: w0 0x02 / w1 0 (outside-window Populate refused AND nothing
# minted), w2 1 / w3 0x80011000 (in-window Populate still works), w4 0x02
# (outside-window Destroy refused too -- Destroy bumps the generation of any slot
# it touches, so an unscoped delegate could burn the temporal-safety counter of
# every object in the machine), w5 2 traps, w6 0 (in-window Destroy still works),
# w7 0x80012000 (Machine holds the ODA and is still not scoped by it).
#
# w2, w6 and w7 are the three over-refusal controls, and they are not decoration:
# without w2/w6 a layer that refused EVERY delegated ODT write would produce the
# right answer for w0/w1/w4, and without w7 a fix that scoped both halves of the
# `Machine | oda_authorized()` OR would pass everything else while breaking the
# machine.

# p21_oda_crossing -- R48. OCInvoke narrows PCC, installs a fresh IDC, reloads
# the CRBR and clears the SSC; it left veda_oda untouched. The argument against
# that was already written down for the SSC, INSIDE the OCInvoke clause, naming
# "ODA/TSC's own untouched-by-OCInvoke convention" as the thing an SSC must not
# follow. Nobody turned it back on the ODA.
#
# Pre-R47 it was moot -- an unscoped ODA reached all of memory from anywhere.
# R47 gave it a window, and inheriting a window is inheriting mint authority
# over the caller's memory. MEASURED on Sail before the fix: a User compartment
# holding nothing but a code and a data capability destroyed the caller's object
# AND minted a fresh descriptor over the caller's window, ZERO traps, mcause
# 0x00. And VEDA_OSPECIALRW is Machine-only for read and write, so the caller
# had no instruction with which to drop its own ODA before calling -- there was
# no software discipline to fall back on.
#
# w3 and w5 are the over-refusal controls and they are the point: w3 is the
# callee doing its own legitimate work through the IDC it was handed (a layer
# that broke OCInvoke, or trapped everything after any crossing, gets w0/w1
# right and fails here), and w5 is Machine re-delegating and User minting again
# -- the only word that shows the clear is a clear rather than a poisoning.

# p22_csetbounds_width -- R53. The RTL computed CSetBounds at the PRE-WIDENING
# widths: $veda_csetbounds_new_base[31:0] and _new_length[15:0], while its own
# operands are 56 and 40 bits and its results feed $base[55:0] and $length[39:0].
# A site increment 3's capability-format widening missed. A THIRD site was worse
# -- the window check itself validated the truncated request, so a request above
# 0xFFFF passed as zero and stored zero, silently minting a useless capability
# instead of refusing.
#
# MEASURED BEFORE THE FIX: a CSetBounds requesting Length 0x10000 on an
# unbounded parent gave w0 = 0x00010000 on Sail and 0x00000000 on the RTL. Its
# two controls -- a request of 0x40, and the parent's own Length read before any
# derivation -- AGREED on both layers throughout, so the probe measures the width
# and not a broken CSetBounds. The RTL half was fail-closed (a zero Length grants
# nothing), so this was a correctness divergence rather than an escape; the BASE
# half is not fail-closed, and above 4 GiB the sum would wrap, but this
# testbench's memory map cannot reach 2^32 so that half is recorded UNMEASURED.
#
# Twenty increments of a differential suite missed it because no probe had ever
# exercised CSetBounds above 16 bits. The window check is now 65 bits wide --
# offset is 40 and the request is 64, so at 64 bits a huge request wraps to a
# small sum and PASSES. Sail is immune because its integers are unbounded.
#
# p23_oclear -- R50 increment 1. There was NO instruction on this machine that
# reliably zeroed a capability register's value: every soft-fail in the
# derivation family clears the tag and carries the source's fields verbatim, and
# veda.bind.notrap on a live openly-bindable slot SUCCEEDS and installs a full
# capability instead of clearing. So CHERI's answer to R50 -- a trusted switcher
# clears what it does not pass -- was a duty this architecture had assigned and
# shipped no tool for.
#
# w2 is why the clear writes VALUES and not just tags: the query family is
# deliberately un-gated, so a tag-only clear still answers cgetbase with the raw
# physical Base (RTL-14's lesson). w3 is why the cleared otype is 0xFFFF and not
# zero: isSealedCap tests otype != UNSEALED_OTYPE and Rebind tests it on its
# DESTINATION with no tag conjunct, so an all-zeros clear would leave every
# cleared register permanently un-Rebindable while its tag read 0 either way and
# every tag assertion stayed green -- R24 re-created. w6 proves that choice is
# load-bearing. w4 and w5 are the over-refusal controls: a layer that wiped the
# whole file on this opcode gets w1-w3 right and fails both.
#
# The first draft of this probe gave the dereferenced object Perms 0x0004 (Load
# only) and then stored through it. Both layers AGREED on that failure -- w5 was
# 0 on Sail and x on the RTL, w7 counted a trap -- and the verdict line still
# said AGREE. Caught by reading the signature word by word. Eighth instance.

# p21_oda_crossing -- R48, and READ ITS HISTORY BEFORE TRUSTING ANY DIAGNOSIS OF
# IT. This probe first reported AGREE while both layers wrote EIGHT ZERO WORDS,
# and the reason recorded for that at the time was WRONG. The recorded reason was
# that the differential harness runs with test_fixtures false so no region is
# resident and every OCInvoke REGION_FAULTs. That is false at source:
# veda_regs.sail seeds the region table at :1231-1242, ABOVE the
# `if veda_test_fixtures` guard that only opens at :1530, so regions 0 and 1 are
# valid and resident here regardless of the switch.
#
# The real cause was one immediate in this file. callee_entry lands at
# 0x8000010c and the compartment's terminating ecall at 0x8000014c -- exactly
# ONE WORD past the 0x40 window the code object declared, so it could never be
# fetched. Its sibling vc_r10_crbr_invoke_trap_return.S sizes its compartment
# 0x200 and says why. Corrected to 0x200, this probe measures.
#
# w3 and w5 are the over-refusal controls and they are the point: w3 is the
# callee doing its own legitimate work through the IDC it was handed (a layer
# that broke OCInvoke, or trapped everything after any crossing, gets w0/w1 right
# and fails here), and w5 is Machine re-delegating and User minting again -- the
# only word that shows the clear is a clear rather than a poisoning.
#
# THE COMPARTMENT CROSSING HAD NEVER BEEN DIFFERENTIALLY TESTED BEFORE THIS
# PROBE RAN. That part of the original diagnosis was right, and it was true for
# the mundane reason that nobody had written a probe that crossed -- not for the
# architectural reason recorded alongside it.

.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R26 -- AUTHORITY IS A NAME, NOT A BOUND.
    #
    # Seven sites in this model answered "does this code hold machine
    # authority?" by testing veda_pcc_length == VEDA_PCC_UNBOUNDED. Length is a
    # NUMBER SOFTWARE CHOOSES. Enter a compartment on a code object whose Length
    # IS the sentinel and every one of those sites reads true at once, so the
    # compartment can widen its own execution bounds, forge the saved bounds a
    # trap return will trust, turn enforcement off, and capture every future
    # trap. The fix asks the PCC's OBJECT instead: VEDA_OBJECT_NONE is
    # structurally unreachable, because no capability bearing that name can
    # cross a domain boundary in the first place.
    #
    # WHY THIS TEST AND NOT THE ONES ALREADY HERE. vc_pcc_csr_escape_neg.S,
    # vc_pcc_csr_escape_mepcc_neg.S and vc_pcc_mtvec_escape_neg.S all build
    # their CODE object with Length = 0x0040 -- a NARROW compartment. Every one
    # of them is refused by the OLD length predicate alone and passes unchanged
    # on the unfixed model. They cannot see this hole. This is the same attack
    # with one field changed.
    #
    # They also could not have been written this way: those tests use the packed
    # descriptor form of Populate, whose Length field is 16 bits wide and cannot
    # express a 40-bit sentinel. This one uses POPULATE_FAST, where Length comes
    # from veda_attr[55..16] and all 40 bits are reachable.
    #
    # SIX SITES, NOT ONE. The RTL fuses all six CSRs into a single OR-list, so
    # one comparator there covers them all and one mutant proves it. This layer
    # has them as SIX SEPARATE write_CSR clauses (0x7C0, 0x7C1, 0x7C2, 0x7C3 and
    # 0x7C5 in veda_regs.sail, plus mtvec in the access predicate), so a test
    # that exercised only one would leave five unmeasured -- and an edit applied
    # to four of five has slipped through this corpus twice already.
    #
    # SINGLE-TERM DISCRIMINATOR, which is the whole point. x24 pins
    # veda_pcc_length INSIDE the compartment and x25 pins it OUTSIDE, and the
    # test demands they be EQUAL and both the sentinel. The length term reads
    # identically in both halves and cannot be what refuses. Only the object
    # differs. Without that pin this test would still pass if the compartment
    # had merely narrowed its own bounds, which proves nothing about R26.
    #
    # x23 is the anti-vacuity pin, and it is not hypothetical: the RTL twin of
    # this test first FELL THROUGH -- the OCInvoke trapped, the handler stepped
    # over it, and execution reached the landing pad in a straight line without
    # ever entering the compartment. Every later check then ran OUTSIDE, where
    # the saved-bounds CSR legitimately still holds the sentinel, so the test
    # would have reported PASS while proving nothing whatsoever.
    la   x5, trap_handler
    csrw mtvec, x5
    li   x12, 0                     # "some write LANDED" accumulator
    li   x16, 0                     # trap count
    li   x17, 0                     # "some trap had the wrong cause" accumulator

    # ---- positive control: OUTSIDE, this very write must LAND ----
    # Without it the test would also pass with 0x7C3 wired permanently shut.
    li   x6, 0x40
    csrw 0x7c3, x6
    csrr x27, 0x7c3                 # must read 0x40 -- checked at the end
    li   x6, 0xFFFFFFFFFF
    csrw 0x7c3, x6                  # restore the sentinel
    csrr x25, 0x7c1                 # PCC Length out here -- the baseline

    # ---- the sealing authority ----
    # Length MUST be non-zero: CSeal demands cs2.Offset < cs2.Length, because
    # the otype it mints IS the authority's Offset and an authority may only
    # mint otypes inside its own range. An authority of Length 0 authorises
    # nothing -- and CSeal still writes every OTHER field while taking only the
    # TAG from the authorisation result, so the failure presents as a capability
    # that looks correct in every field and is merely untagged.
    li   x7, 0x40
    slli x7, x7, 16
    ori  x7, x7, 0x0300             # Permit_Seal | Permit_Unseal
    csrw 0x7c4, x7
    li   x10, 62
    li   x11, 0x80010800
    .insn r 0x0b, 0x0, 0x04, x5, x10, x11   # populate.fast 62

    # ---- the CODE object: Length = THE SENTINEL ----
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402             # EXECUTE | INVOKE
    csrw 0x7c4, x7
    li   x10, 60
    la   x11, landing_pad
    .insn r 0x0b, 0x0, 0x04, x5, x10, x11   # populate.fast 60

    # ---- the DATA object: INVOKE but NO execute ----
    # OCInvoke refuses a data capability carrying EXECUTE, so the two operands
    # cannot be the same capability passed twice.
    li   x7, 0x40
    slli x7, x7, 16
    ori  x7, x7, 0x0400             # INVOKE only
    csrw 0x7c4, x7
    li   x10, 61
    li   x11, 0x80010700
    .insn r 0x0b, 0x0, 0x04, x5, x10, x11   # populate.fast 61

    li   x10, 60
    .insn i 0x0b, 0x5, x0, x10, 0   # bind c0, 60   CODE
    li   x10, 61
    .insn i 0x0b, 0x5, x1, x10, 0   # bind c1, 61   DATA
    li   x10, 62
    .insn i 0x0b, 0x5, x2, x10, 0   # bind c2, 62   authority

    # both sealed by the SAME authority at the same Offset, so the otypes match
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4

landing_pad:
    li   x23, 0xA11E                # entry is now a FACT, not an assumption
    csrr x24, 0x7c1                 # PCC Length in here -- must equal x25

    # ---- site 1: 0x7C0, the LIVE execution base ----
    # Junk is 0x1000, deliberately LOW rather than arbitrary: if the write lands
    # on an unfixed model the PCC becomes [0x1000, +Length) which still covers
    # this code, so the mutant reports a clean FAIL instead of fetching out of
    # bounds and trap-looping until the run is killed. A hang is a far worse
    # failure mode than a wrong answer -- it reads as infrastructure trouble,
    # and this runner has lost hours to exactly that once already.
    csrr x13, 0x7c0
    li   x14, 0x1000
    csrw 0x7c0, x14
    csrr x15, 0x7c0
    beq  x13, x15, 1f
    li   x12, 1
1:
    # ---- site 2: 0x7C1, the LIVE execution length ----
    # Junk is the sentinel minus one for the same reason: distinguishable from
    # 0xFFFFFFFFFF, yet still large enough to keep every later fetch in bounds
    # even when combined with a landed base of 0x1000.
    csrr x13, 0x7c1
    li   x14, 0xFFFFFFFFFE
    csrw 0x7c1, x14
    csrr x15, 0x7c1
    beq  x13, x15, 2f
    li   x12, 1
2:
    # ---- site 3: 0x7C2, the SAVED base a trap return will trust ----
    csrr x13, 0x7c2
    li   x14, 0x2000
    csrw 0x7c2, x14
    csrr x15, 0x7c2
    beq  x13, x15, 3f
    li   x12, 1
3:
    # ---- site 4: 0x7C3, the SAVED length ----
    csrr x13, 0x7c3
    li   x14, 0x2000
    csrw 0x7c3, x14
    csrr x15, 0x7c3
    beq  x13, x15, 4f
    li   x12, 1
4:
    # ---- site 5: 0x7C5, enforcement itself ----
    csrr x13, 0x7c5
    li   x14, 1
    csrw 0x7c5, x14
    csrr x15, 0x7c5
    beq  x13, x15, 5f
    li   x12, 1
5:
    # UNCONDITIONAL restore, and it is load-bearing on the mutant path rather
    # than cosmetic: RVMODEL_HALT_PASS/FAIL end in ordinary `sw` stores to
    # tohost. If purecap actually came on above, those stores fault, tohost is
    # never written, and the harness sees a HANG instead of a FAIL. This write
    # is itself refused on a correct model, which simply costs one more trap.
    csrw 0x7c5, x0

    # ---- site 6: mtvec, the vector every future fault goes through ----
    csrr x13, mtvec
    la   x14, hijacked
    csrw mtvec, x14
    csrr x15, mtvec
    beq  x13, x15, 6f
    li   x12, 1
6:
    # Same reasoning as the purecap restore: if mtvec really moved, put it back
    # so the tail of this test still reaches a verdict rather than diverging.
    la   x14, trap_handler
    csrw mtvec, x14
    j    verdict

hijacked:
    # Reached only if the vector capture succeeded AND a later fault occurred.
    li   x12, 1
    j    verdict

trap_handler:
    addi x16, x16, 1                # one refusal
    csrr x28, mcause
    li   x29, 2                     # illegal instruction, as every refused CSR is
    beq  x28, x29, 7f
    li   x17, 1
7:
    csrr x30, mepc
    addi x30, x30, 4
    csrw mepc, x30
    mret

verdict:
    li   x21, 0xDEAD
    li   x22, 0xDEAD

    bne  x23, x0, 8f                # the landing pad must actually have run
    j    done
8:
    li   x7, 0xFFFFFFFFFF           # inside and outside must BOTH be the sentinel
    bne  x24, x7, done
    bne  x25, x7, done
    bne  x24, x25, done

    li   x7, 0x40                   # the positive control must have LANDED
    bne  x27, x7, done

    bne  x12, x0, done              # no attacked CSR may have changed
    bne  x17, x0, done              # every refusal was an illegal instruction

    li   x7, 8                      # six attacks + two restores, all refused
    bne  x16, x7, done

    li   x21, 0x600D
    li   x22, 0x900D

done:
    li   x7, 0x600D
    bne  x21, x7, real_fail
    li   x7, 0x900D
    bne  x22, x7, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL

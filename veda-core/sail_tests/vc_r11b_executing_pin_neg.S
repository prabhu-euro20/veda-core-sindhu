.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R11(b) (DESIGN_07 Tier H) -- YOU MAY NOT EVICT THE CODE YOU ARE RUNNING.
#
# R11(a) closed one execute-after-free window: ENTERING an object that was
# evicted while you were away. It structurally could not close the other --
# eviction of the object you are CURRENTLY EXECUTING -- because instruction
# fetch compares the PC against PCC's cached bounds and never re-reads the
# ODT. PCC held Base and Length and no name, so the hardware could not even
# say which object backed the running compartment.
#
# R11(b) gives PCC a name and lets eviction REFUSE on it. The cost lands on
# the rare event (an eviction) instead of on every fetch -- the same
# principle that settled DESIGN_02's cached-Base decision.
#
# WHAT EACH PART PROVES, and why none of them is redundant:
#
# PART A1 -- page-out of the running object is refused (the live PCC pin).
# PART A2 -- destroy likewise. Both eviction paths need their own coverage:
#            they are separate instructions with separate gates, and this
#            increment has twice been bitten by a fix that spanned several
#            sites and got tested at one of them.
# PART A3 -- and A2 quietly proves something else. It runs AFTER a trap
#            round-trip, so the name it refuses on can only be there if
#            mret RESTORED the identity along with the bounds. Drop that
#            restore and A2 starts succeeding.
# PART B  -- the SAVED name is pinned too: in the handler PCC belongs to no
#            object, yet 180 still cannot be evicted, because a return to
#            it is owed. Without this an evicted object would be handed
#            back to a compartment at mret, which is the same hole one
#            level removed.
# PART C  -- THE RELEASE, and the reason this design is acceptable at all.
#            Pinning the saved name was rejected earlier for a real reason:
#            a scheduler that permanently abandons a compartment would pin
#            its code object forever with nothing left to release it. R12's
#            OCRETURN-abandon dissolved that objection, and this part is
#            the proof -- the SAME instruction on the SAME object that was
#            refused in PART B SUCCEEDS once the frame is abandoned. A pin
#            that never released would be a denial-of-revocation bug, so
#            this is a security assertion, not a convenience one.
# PART D  -- the over-refusal control. An unrelated object is still
#            evictable while a compartment runs. Without it, a core that
#            refused every eviction outright would pass everything above.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0                            # trap counter

    # ---- CODE attr: Length UNBOUNDED, Permit_Execute|Permit_Invoke
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast -- CODE, compartment
    la   x7, after_pad
    li   x1, 184
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast -- CODE, PART C landing

    # ---- DATA attr for the invoke handoff: Permit_Invoke, NOT executable
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0400
    csrw 0x7C4, x6
    la   x7, data_pad
    li   x1, 181
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7
    la   x7, victim_pad
    li   x1, 183
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # the PART D control object

    # ---- type authority: Permit_Seal|Permit_Unseal
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0300
    csrw 0x7C4, x6
    la   x7, auth_pad
    li   x1, 182
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7

    # A control taken BEFORE entering: 180 is evictable right now, because
    # nothing is executing it. Page it back in so the crossing still works.
    # This is what makes PART A1 a statement about EXECUTION rather than
    # about object 180 being special.
    #
    # IT HAS TO HAPPEN HERE, ahead of the binds. Page-out BUMPS generation
    # (the Option A contract), so a capability minted before this round-trip
    # is already dead by the time it is used -- the first version of this
    # test sealed c3 first and the OCInvoke below trapped 0x02 instead of
    # entering. The eviction is deliberately placed where the capabilities
    # that outlive it do not yet exist.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 180 -- must SUCCEED
    bne  x20, x0, fail                     # and must not trap
    la   x7, compartment
    li   x1, 180
    .insn r 0x0b, 0x0, 0x05, x5, x1, x7    # page.in 180 -- resident again
    bne  x20, x0, fail
    li   x19, 0x600D

    li   x1, 180
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, 180  -- CODE
    li   x1, 181
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, 181  -- DATA
    li   x1, 182
    .insn i 0x0b, 0x5, x2, x1, 0           # veda.bind c2, 182  -- authority
    li   x1, 184
    .insn i 0x0b, 0x5, x8, x1, 0           # veda.bind c8, 184  -- CODE
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    # cseal c3, c0, c2   -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    # cseal c4, c1, c2   -- sealed DATA
    .insn r 0x5b, 0x1, 0x15, x13, x8, x0   # csealentry c13, c8 -- PART C sentry

    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # ocinvoke c3, c4 -- ENTER 180
    j    fail

.balign 4
compartment:
    # PCC now names object 180.

    # ═══ PART A1: page out our own code object. MUST REFUSE. ═══
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 180 -- REFUSED (trap 1)
    li   x9, 1
    bne  x20, x9, fail
    li   x9, 2
    bne  x21, x9, fail                     # mcause 2 = Illegal_Instruction

    # ═══ PART A2/A3: destroy our own code object. MUST REFUSE. ═══
    # Reached only after mret restored PCC -- so this also proves the
    # identity came back with the bounds.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    # destroy 180 -- REFUSED (trap 2)
    li   x9, 2
    bne  x20, x9, fail
    bne  x22, x9, fail

    # ═══ PART A4: REPOPULATE our own code object. MUST REFUSE. ═══
    # The bypass, and the reason the other two refusals are not decorative.
    # Populate on a still-valid slot bumps generation AND repoints Base, so
    # it does everything Destroy does and more -- an authority refused a
    # Destroy here could otherwise just re-populate instead.
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, victim_pad
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast 180 -- REFUSED (3)
    li   x9, 3
    bne  x20, x9, fail
    li   x9, 2
    bne  x26, x9, fail
    li   x23, 0x600D

    # ═══ PART D: an UNRELATED live object is still evictable. ═══
    li   x1, 183
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 183 -- must SUCCEED
    li   x9, 3
    bne  x20, x9, fail                     # no new trap
    li   x24, 0x600D

    # ---- hand control to the handler with a return to 180 still owed
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x11, x5, x10  # ocl.d c11 -- untagged, TRAPS (4)
    j    fail

.balign 4
# Scratch is x9/x14/x15 and raw x-numbered registers throughout. t5/t6 are
# x30/x31 and both are result registers here; naming the ABI alias hides
# that collision one table away, which has cost this project four
# debugging cycles.
trap_handler:
    addi x20, x20, 1
    li   x9, 1
    beq  x20, x9, rec_a1
    li   x9, 2
    beq  x20, x9, rec_a2
    li   x9, 3
    beq  x20, x9, rec_a4
    li   x9, 5
    beq  x20, x9, rec_b1
    li   x9, 6
    beq  x20, x9, rec_b2
    li   x9, 7
    beq  x20, x9, rec_b3
    li   x9, 8
    beq  x20, x9, rec_b4
    li   x9, 4
    bne  x20, x9, fail

    # ═══ trap 4: inside the handler. depth is 1, PCC belongs to NO object,
    #     and the saved name is 180. ═══
    csrr x9, mcause
    li   x14, 0x18
    bne  x9, x14, fail                     # the deliberate Veda trap

    # ═══ PART B: the saved name is pinned. Both evictions must refuse even
    #     though nothing is executing 180 right now. ═══
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 180 -- REFUSED (trap 5)
    li   x1, 180
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    # destroy 180 -- REFUSED (trap 6)
    la   x7, victim_pad
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast 180 -- REFUSED (7)
    # PLAIN populate is a SEPARATE Sail clause from populate.fast, with its
    # own copy of the gate -- so it needs its own refusal, or exactly one of
    # the four sites goes untested. Enumerated from the decoder, not from
    # what came to mind while writing.
    li   x2, 0x8001100000400400            # packed descriptor
    li   x1, 180
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 180 -- REFUSED (8)
    li   x9, 8
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail
    bne  x27, x9, fail
    bne  x28, x9, fail
    bne  x17, x9, fail
    li   x29, 0x600D

    # ═══ PART C: abandon the frame. OCRETURN into a DIFFERENT object drops
    #     the trap frame, which must release 180's pin. ═══
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0   # ocreturn c13 -- lands in 184
    j    fail

rec_a1:
    csrr x21, mcause
    j    resume
rec_a2:
    csrr x22, mcause
    j    resume
rec_a4:
    csrr x26, mcause
    j    resume
rec_b1:
    csrr x25, mcause
    j    resume
rec_b2:
    csrr x27, mcause
    j    resume
rec_b3:
    csrr x28, mcause
    j    resume
rec_b4:
    csrr x17, mcause
    j    resume
resume:
    csrr x14, mepc
    addi x14, x14, 4
    csrw mepc, x14
    mret

.balign 4
after_pad:
    # Reached only by PART C's OCRETURN. PCC now names 184, the frame is
    # gone, and 180 is owed to nobody.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 180 -- must SUCCEED NOW
    li   x9, 8
    bne  x20, x9, fail                     # still exactly eight traps
    li   x28, 0x600D

    li   x9, 0x600D
    bne  x19, x9, fail
    bne  x23, x9, fail
    bne  x24, x9, fail
    bne  x29, x9, fail
    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
data_pad:
    .zero 0x100
.balign 32
victim_pad:
    .zero 0x100
.balign 32
auth_pad:
    .zero 0x100

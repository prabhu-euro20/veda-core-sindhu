.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R68 -- R65's rule reaches five sites, not two.
#
# veda_oda_denies tests old_entry.Base, and page-out preserves that Base as a
# value the model's own comment calls "stale, and unreachable". So for a
# NON-RESIDENT object the window test asks about the frame the object has LEFT.
# R65 installed veda_stale_authority at set.cow and set.domain and stopped there
# -- the same test authorizes at SEVEN sites.
#
# MEASURED BEFORE THE FIX, by instruction trace, from User with an ODA covering
# only the frame the victim had left:
#   [53] [U] veda.odt.populate on the PAGED-OUT victim  ->  ACCEPTED, retired
#   [56] [U] the same instruction, out-of-window object ->  REFUSED   (control)
# After the fix the same binary shows [53] [U] populate -> [54] [M] trap_handler.
#
# The harm is worse than R65's. R65 rewrites a victim's POLICY; this retargets
# the victim's IDENTITY into attacker memory with attacker Perms, and page-in
# then refuses a resident entry, so the evicted contents can never be restored.
#
# POPULATE-FAST IS NOT EXEMPT, and the sentence that would have exempted it is
# itself an expired justification -- exactly the class the sweep that found this
# was hunting. DESIGN_02's mechanism-1 sketch says the handler "allocates
# physical Base (ODT-Populate-Fast)", and that same document's later decision
# supersedes it: "Page-in therefore CANNOT be plain ODT-Populate ... a distinct,
# generation-preserving page-in path is required." The repair path is
# veda.odt.page.in, deliberately left for its own pass with page.out.
#
# Every register by number. x27 traps, x26 mtval, x17 handler temp, x16 phase.
.equ VICTIM, 510
.equ ODAOBJ, 511
.equ OUTOBJ, 512
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x16, 0
    li   x18, 0
    li   x19, 0
    li   x20, 0

    # ---- M: the victim object, living in victim_frame
    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x0040000C                     # Len 64, Load|Store
    or   x2, x6, x7
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, fail

    # ---- M: a SECOND object living OUTSIDE the attacker's window, as the control
    la   x6, other_frame
    slli x6, x6, 32
    li   x7, 0x0040000C
    or   x2, x6, x7
    li   x1, OUTOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, fail

    # ---- M: the delegated authority, scoped to victim_frame ONLY
    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x00400080                     # Len 64, PERM_ACCESS_SYSTEM_REGISTERS
    or   x2, x6, x7
    li   x1, ODAOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, ODAOBJ
    .insn i 0x0b, 0x5, x1, x1, 0            # bind c1
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0     # ospecialrw c2, c1 -- ODA := c1
    bne  x27, x0, fail

    # ---- M: evict the victim. Base stays victim_frame and is now, by the
    #        model's own comment, "stale, and unreachable".
    li   x1, VICTIM
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0     # page.out VICTIM
    bne  x27, x0, fail
    li   x18, 0x600D

    # ---- drop to User, the architected way (R36)
    li   x7, 0x1800
    csrc mstatus, x7
    la   x8, umode
    csrw mepc, x8
    mret
.balign 4
umode:
    # ---- THE MEASUREMENT: retarget the policy of an object that is NOT THERE,
    #      authorized by a window test on the frame it used to occupy.
    li   x1, VICTIM
    li   x4, 1
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # POPULATE the victim at the frame it left
    mv   x19, x27                            # 0 = the write was ACCEPTED

    # ---- CONTROL: the same actor, the same instruction, an object whose Base
    #      its ODA does not cover. This must be REFUSED, or the gate is simply
    #      absent and the measurement above means nothing.
    li   x1, OUTOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    mv   x20, x27
    li   x16, 1
    ecall                                    # back to M
.balign 4
mphase2:
    # ---- M: the pager restores the victim to a DIFFERENT frame -- one the
    #      attacker's ODA never covered.
    la   x9, new_frame
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x05, x5, x1, x9     # page.in VICTIM at new_frame
    mv   x21, x27
    li   x1, VICTIM
    .insn i 0x0b, 0x5, x3, x1, 0            # bind c3, VICTIM
    .insn r 0x5b, 0x0, 0x00, x22, x3, x0    # cgetbase -- new_frame?
    la   x23, new_frame
    xor  x24, x22, x23
    seqz x24, x24
check:
    li   x10, 1
    bne  x19, x10, fail                     # THE FINDING: the User populate over
                                            # the PAGED-OUT victim must TRAP.
                                            # Before the fix this was 0.
    li   x10, 2
    bne  x20, x10, fail                     # CONTROL: the out-of-window populate
                                            # is still refused, so the R47 gate
                                            # that was already there is untouched
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    li   x17, 1
    beq  x16, x17, back_to_m
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
back_to_m:
    li   x16, 0
    li   x17, 0x1800
    csrs mstatus, x17                        # MPP := M
    la   x17, mphase2
    csrw mepc, x17
    mret
.section .data
.balign 64
victim_frame:
    .space 64
other_frame:
    .space 64
new_frame:
    .space 64

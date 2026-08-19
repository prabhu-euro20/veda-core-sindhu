.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R50 INCREMENT 1 -- OCLEAR
    #
    # R50 measured that the capability register file crosses a compartment
    # boundary intact. The conventional answer -- CHERI's -- is that a trusted
    # switcher clears the registers it is not passing.
    #
    # THIS MACHINE COULD NOT DO THAT, and that is the finding this instruction
    # closes. No instruction reliably zeroed a capability register's VALUE.
    # Every soft-fail in the derivation family (OCA, CSetBounds, CAndPerm,
    # Rebind-on-sealed) clears the tag and carries the source's fields verbatim;
    # the only writes of zero_capability outside reset are Bind's two MISS arms,
    # and on a live, resident, openly-bindable slot that instruction SUCCEEDS
    # and installs a fully-permissioned capability instead of clearing.
    # veda.bind.notrap is a probe whose failure mode happens to look like a
    # clear. The architecture had assigned a duty and shipped no tool for it.
    #
    # Four properties, each asserted rather than described:
    #   A. the clear zeroes the VALUE, not just the tag -- because the query
    #      family is deliberately un-gated, so an untagged register still
    #      answers cgetbase with the raw physical Base (RTL-14's lesson)
    #   B. otype stays 0xFFFF, so a cleared register is still REBINDABLE. An
    #      all-zeros clear reads as SEALED and Rebind tests isSealedCap on its
    #      DESTINATION with no tag conjunct -- every cleared register would be
    #      permanently dead while its tag read 0 and every tag assertion in the
    #      corpus stayed green. That is R24 re-created.
    #   C. it is UNPRIVILEGED -- proven from User mode. Dropping authority you
    #      already hold is monotone, and requiring privilege to give something
    #      up is exactly what made R48 unclosable in software.
    #   D. THE OVER-REFUSAL CONTROLS: an unmasked register is untouched and
    #      still dereferenceable, and a zero mask clears nothing at all. A
    #      machine that simply wiped the whole file on this opcode passes A-C
    #      and fails both of these.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0                      # trap count
    li   s1, 0                      # last mcause

    # two ordinary objects, both Load|Store
    la   t0, obj_a
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 140
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 140
    la   t0, obj_b
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 141
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 141

    # R79 -- THIS FILE REBUILDS c5 FROM THE NAME 140 *AT USER*, AFTER THE DROP,
    # having crossed no compartment boundary and holding no ODA. That used to
    # work because arm 2 of veda_bind_domain_ok gave the ambient sentinel
    # identity the ROOT, and a privilege drop leaves the identity at that
    # sentinel (veda_pcc_restore_on_xret's body sits entirely inside
    # `if veda_trap_depth != zeros()`, and a boot-time drop happens at depth 0).
    # Ambient root is now Machine-or-ODA only, so the rebuild is refused unless
    # object 140 is DECLARED shareable -- which is R52's own doctrine: sharing is
    # a declaration, one set.domain per object, exactly what a loader does at
    # load time. The subject of this file is OCLEAR, not the bind gate, so the
    # declaration is the minimal honest change and it states the new rule out
    # loud rather than hiding it.
    li   a1, 140
    li   a2, 0xFFFFF                        # VEDA_DOMAIN_ANY
    .insn r 0x0b, 0x1, 0x06, x5, a1, a2     # set.domain 140 -> ANY (at Machine)
    li   a1, 140
    .insn i 0x0b, 0x5, x5, a1, 0            # veda.bind c5, 140
    li   a1, 141
    .insn i 0x0b, 0x5, x6, a1, 0            # veda.bind c6, 141

    # both genuinely work before anything is cleared
    li   t1, 0
    li   t2, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, t2, x5, t1     # ocs.d c5, t1, t2
    li   t2, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, t2, x6, t1     # ocs.d c6, t1, t2
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0     # cgettag t3, c5
    li   t4, 1
    bne  t3, t4, check_fail
    .insn r 0x5b, 0x0, 0x00, s2, x5, x0     # cgetbase s2, c5  -- remember the real Base
    beqz s2, check_fail                     # it must be nonzero, or part A proves nothing

    # ─── drop to User: OCLEAR must work here (property C) ─────────────────
    li   t1, 0x1800
    csrc mstatus, t1
    la   t2, umode
    csrw mepc, t2
    mret

umode:
    # ═══ IDENTITY CONTROL -- a zero mask clears nothing ═══════════════════
    li   t0, 0
    .insn r 0x5b, 0x1, 0x18, x0, x0, t0     # oclear x0  -- mask 0
    bne  s0, x0, check_fail                 # and it is not privileged: no trap
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0     # cgettag t3, c5
    li   t4, 1
    bne  t3, t4, check_fail                 # c5 still live

    # ═══ THE CLEAR -- c5 only ═════════════════════════════════════════════
    li   t0, 0x0020                         # bit 5 -> c5
    .insn r 0x5b, 0x1, 0x18, x0, x0, t0     # oclear t0
    bne  s0, x0, check_fail                 # still unprivileged, still no trap

    # A. value, not just tag
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0     # cgettag  t3, c5  -> 0
    bne  t3, x0, check_fail
    .insn r 0x5b, 0x0, 0x00, t3, x5, x0     # cgetbase t3, c5  -> 0, NOT the real Base
    bne  t3, x0, check_fail
    .insn r 0x5b, 0x0, 0x01, t3, x5, x0     # cgetlen  t3, c5  -> 0
    bne  t3, x0, check_fail
    .insn r 0x5b, 0x0, 0x02, t3, x5, x0     # cgetperm t3, c5  -> 0
    bne  t3, x0, check_fail
    .insn r 0x5b, 0x0, 0x07, t3, x5, x0     # cgetobjectid t3, c5 -> 0
    bne  t3, x0, check_fail

    # B. otype is UNSEALED, so the register is still usable as a destination
    .insn r 0x5b, 0x0, 0x04, t3, x5, x0     # cgettype t3, c5 -> 0xFFFF
    li   t4, 0xFFFF
    bne  t3, t4, check_fail

    # ═══ OVER-REFUSAL CONTROL 1 -- c6 was NOT in the mask ═════════════════
    # This is the load-bearing word. A machine that wiped the whole register
    # file on this opcode satisfies everything above and fails here.
    .insn r 0x5b, 0x0, 0x03, t3, x6, x0     # cgettag t3, c6 -> 1
    li   t4, 1
    bne  t3, t4, check_fail
    li   t1, 0
    li   t3, 0
    .insn r 0x0b, 0x3, 0x00, t3, x6, t1     # ocl.d t3, t1, c6  -- still dereferenceable
    li   t4, 0xBEEF
    bne  t3, t4, check_fail
    bne  s0, x0, check_fail                 # and none of that trapped

    # ═══ OVER-REFUSAL CONTROL 2 -- a cleared register is still REBINDABLE ══
    # This is the assertion that catches an all-zeros implementation, and it
    # catches it in the one place a tag assertion cannot: under `write zeros`,
    # otype 0 reads as SEALED and Rebind soft-fails forever, while cgettag
    # reads 0 either way and every tag check in this file still passes.
    # R43 REMOVED THIS CONTROL'S DISCRIMINATOR, and the honest replacement is
    # smaller. The comment above is exact about why Rebind was chosen: under
    # `write zeros` otype 0 reads as SEALED and Rebind soft-fails forever. R43
    # made Rebind check the tag first, and verification showed it was the last
    # untagged sealedness read in the machine -- so an all-zeros OCLEAR is now
    # BEHAVIOURALLY IDENTICAL to one that writes the unsealed sentinel, and this
    # control was protecting a distinction that no longer exists.
    #
    # What still matters, and what this now asserts: a cleared register is tag 0
    # and the machine can rebuild a usable capability in it. An implementation
    # that corrupted more than the tag still fails here.
    li   a1, 140
    .insn i 0x0b, 0x5, x5, a1, 0            # veda.bind c5, 140
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0     # cgettag t3, c5 -> 1
    li   t4, 1
    bne  t3, t4, check_fail
    li   t1, 0
    li   t3, 0
    .insn r 0x0b, 0x3, 0x00, t3, x5, t1     # ocl.d t3, t1, c5
    li   t4, 0xC0FFEE
    bne  t3, t4, check_fail

    # ═══ a multi-bit mask, since the single-bit case cannot show the loop ══
    li   t0, 0x0060                         # bits 5 and 6
    .insn r 0x5b, 0x1, 0x18, x0, x0, t0     # oclear t0
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0
    bne  t3, x0, check_fail
    .insn r 0x5b, 0x0, 0x03, t3, x6, x0
    bne  t3, x0, check_fail
    bne  s0, x0, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi s0, s0, 1
    csrr s1, mcause
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret

.section .data
.balign 32
obj_a:
    .space 32
.balign 32
obj_b:
    .space 32

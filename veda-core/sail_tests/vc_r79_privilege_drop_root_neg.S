.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R79 -- THE AMBIENT ROOT HAD THREE OCCUPANTS AND ONLY ONE OF THEM IS BOOT.
#
# veda_pcc_object has exactly FOUR writers per layer -- reset, trap entry, the
# xret restore, and the two crossings -- and only the crossings install a NAME.
# So VEDA_OBJECT_NONE, which R75/R76 increment 1 turned into the root of all
# authority, is reachable in exactly three states:
#
#   boot                              Machine   INTENDED (R34 accepted it)
#   a trap handler                    Machine   R77 -- still open, not this
#   User code after a privilege drop  User      THIS ONE
#
# The third is the worst because it is NOT trusted code. It is the ordinary
# shape of an operating system: a kernel writes mstatus.MPP = User and mrets
# into a process. That process crossed no compartment boundary, so
# veda_pcc_restore_on_xret never touched its identity -- the whole body of that
# function sits inside `if veda_trap_depth != zeros()` and a boot-time drop
# happens at depth 0 -- and veda.bind has no privilege gate of its own anywhere
# in veda_bind_insts.sail. So it held the ambient root and could mint a full
# capability to ANY object in the machine from the NAME alone.
#
# FOUR ROWS, and rows B and C are what stop a core that simply refuses every
# User-mode bind from passing row A for the wrong reason.
#
#   A  User, no ODA, boot-owned object   -> REFUSED   (the escalation)
#   B  User, no ODA, ANY-declared object -> ALLOWED   (anti-vacuity: not a ban)
#   C  Machine, boot-owned object        -> ALLOWED   (anti-vacuity: boot intact)
#   D  User, WITH an ODA, boot-owned     -> ALLOWED   (the ODA arm is live, and
#                                                      R81 records that it is
#                                                      broader than the window)
#
# Every register by NUMBER. bind.notrap (mode 1) throughout, so a refusal is a
# tag-0 soft-fail and the trap ledger stays clean and readable.
.equ SECRET, 220
.equ PUBLIC, 221
.equ AUTH,   222
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0

    la   x6, secret
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, SECRET
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # boot populates -> owner_domain BOOT

    la   x6, public
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, PUBLIC
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, PUBLIC
    li   x2, 0xFFFFF                        # VEDA_DOMAIN_ANY -- declared public
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    la   x6, secret                         # the ODA's own window covers SECRET
    slli x6, x6, 32
    li   x7, 0x00200080                     # PERM_ACCESS_SYSTEM_REGISTERS
    or   x2, x6, x7
    li   x1, AUTH
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # ═══ ROW C -- ANTI-VACUITY: boot itself is untouched ═════════════════════
    li   x1, SECRET
    .insn i 0x0b, 0x5, x9, x1, 1
    .insn r 0x5b, 0x0, 0x03, x20, x9, x0    # cgettag -> MUST be 1
    li   x11, 1
    bne  x20, x11, fail
    bnez x27, fail                          # and quietly

    # ─── drop to User the architected way (R36): MPP = 0b00, then mret ───────
    li   x12, 0x1800
    csrc mstatus, x12
    la   x13, umode
    csrw mepc, x13
    mret

.balign 4
umode:
    # ═══ ROW A -- THE ESCALATION. No crossing, no ODA, a boot-owned object ═══
    li   x1, SECRET
    .insn i 0x0b, 0x5, x10, x1, 1
    .insn r 0x5b, 0x0, 0x03, x21, x10, x0   # cgettag -> MUST be 0
    bnez x21, fail
    bnez x27, fail                          # notrap soft-fails, no trap

    # ═══ ROW B -- ANTI-VACUITY: a DECLARED-public object still binds ═════════
    li   x1, PUBLIC
    .insn i 0x0b, 0x5, x14, x1, 1
    .insn r 0x5b, 0x0, 0x03, x22, x14, x0   # cgettag -> MUST be 1
    li   x11, 1
    bne  x22, x11, fail
    bnez x27, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.balign 64
secret:
    .space 64
public:
    .space 64

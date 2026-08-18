# ═══ BLOCKED, NOT DELETED -- AND THE REASON IS ITSELF A FINDING (R51) ═══════
#
# This probe measured NOTHING and reported AGREE. Both layers wrote eight zero
# words, because neither ever reached the stores: the OCInvoke at its centre
# cannot succeed in this harness at all.
#
# WHY. VEDA_OCINVOKE requires the target domain's region to be RT-resident
# (R10). The region table is written by exactly one thing in the entire model
# -- veda_test_seed_odt(), the TEST FIXTURE function. There is no RT-Populate
# instruction; DESIGN_08's region mechanism has NO SOFTWARE-VISIBLE WRITE PATH.
# The differential harness deliberately runs with test_fixtures FALSE (R24, so
# that the suites and the harness cannot share a drift channel), so no region
# is ever valid or resident here, and every OCInvoke REGION_FAULTs.
#
# CONSEQUENCE, and it is bigger than this file: THE COMPARTMENT CROSSING HAS
# NEVER BEEN DIFFERENTIALLY TESTED. This probe is the first in the suite's
# history to attempt an OCInvoke -- verified by grepping every probe for the
# encoding. The architecture's central isolation mechanism has no cross-layer
# coverage, and could not have any until the region table is writable by
# something other than a fixture.
#
# IT IS KEPT, NOT DELETED, because it is ready to run the day that changes --
# and because a probe that reports AGREE on eight zero words is exactly the
# blindness this project has now found six times (p5_reserved counting traps
# without reading mcause; veda_smoke_m11 pinning an escape as its contract).
# Leaving it in probes/ unlisted would have made it a dark test, which is R49.
# run_difftests.sh now REFUSES to run if any file in probes/ is missing from
# its expected-verdict table, so neither failure mode can recur silently.
#
# R48's evidence lives instead in sail_tests/vc_r48_oda_inherit_neg.S (Sail,
# fixtures on) and rtl/sim/veda_smoke_r48_oda_crossing.S (RTL, fixtures on).
#
.section .text
.global _start
# R48 -- A CALLEE COMPARTMENT INHERITED THE CALLER'S ODA ACROSS OCInvoke.
#
# OCInvoke narrows PCC to the callee's bounds, installs a fresh IDC, reloads the
# CRBR for the entered domain and CLEARS the SSC. It left veda_oda untouched --
# and the argument against that was already written down, for the SSC, inside
# the OCInvoke clause itself: applying "ODA/TSC's own untouched-by-OCInvoke
# convention" to the SSC "would have left the caller's entire stack region
# reachable from the callee."
#
# Pre-R47 the point was moot: the ODA had no window, so it reached all of memory
# from anywhere and a crossing changed nothing. R47 gave it a window. MEASURED
# on Sail before the fix: a User compartment holding nothing but a code and a
# data capability DESTROYED the caller's object and MINTED a fresh descriptor
# over the caller's window, with ZERO traps and mcause 0x00.
#
# And the caller cannot defend itself: VEDA_OSPECIALRW is Machine-only for read
# AND write of all three SCRs, so a User caller has no instruction with which to
# drop its own ODA before calling.
#
#   w0  mcause of the callee's ODT-Populate -- 0x02 on both layers
#   w1  tag of a Bind against the id the callee tried to mint -- 0. The refusal
#       PREVENTED the mint; it did not trap after writing.
#   w2  tag of the object the CALLER minted BEFORE the crossing -- 1. The clear
#       must not retroactively undo the caller's own delegated work.
#   w3  what the callee read back through the IDC it was legitimately handed --
#       0x5A5A. THE OVER-REFUSAL CONTROL: a layer that broke OCInvoke outright,
#       or that trapped everything after any crossing, gets w0/w1 right and
#       fails here.
#   w4  trap count -- 1, so nothing else fired
#   w5  after Machine re-delegates an ODA and returns to User, User mints again
#       -- 1. The clear is a clear, not a poisoning, and this is the only word
#       that proves the documented recovery path exists at all.
#   w6  final trap count -- 1. The recovery path added none.
#
# The Machine-is-untouched control lives in sail_tests/vc_r48_oda_inherit_neg.S
# rather than here: a second OCInvoke re-enters the same code object, so it
# cannot be expressed as a distinct arm in one straight-line probe.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0                            # trap count
    li   x28, 0                            # last mcause

    # ─── Machine: authority object 120 over W = [0x80011000, 0x80011040) ──
    li   x1, 120
    li   x2, 0x8001100000400080            # Perms 0x0080 = PERM_ACCESS_SYSTEM_REGISTERS
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 120
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, 120
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0    # ospecialrw c2, ODA, c1

    # ─── the compartment fixture ──────────────────────────────────────────
    la   x3, callee_entry
    slli x3, x3, 32
    li   x4, 0x00400402                    # Len 0x40, Perms EXECUTE|INVOKE
    or   x2, x3, x4
    li   x1, 122
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # CODE
    li   x1, 123
    li   x2, 0x800107000040040C            # DATA  Perms LOAD|STORE|INVOKE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 124
    li   x2, 0x8001080000400300            # type authority
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 122
    .insn i 0x0b, 0x5, x5, x1, 0           # c5 = code
    li   x1, 123
    .insn i 0x0b, 0x5, x6, x1, 0           # c6 = data
    li   x1, 124
    .insn i 0x0b, 0x5, x7, x1, 0           # c7 = type authority
    .insn r 0x5b, 0x1, 0x10, x8, x5, x7    # cseal c8, c5, c7
    .insn r 0x5b, 0x1, 0x10, x9, x6, x7    # cseal c9, c6, c7

    li   x1, 0x1800
    csrc mstatus, x1
    la   x3, u_caller
    csrw mepc, x3
    mret

.balign 4
u_caller:
    # the caller's own delegated mint, INSIDE its window, BEFORE the crossing
    li   x1, 121
    li   x2, 0x800110000020000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9    # ocinvoke c8, c9

.balign 4
callee_entry:
    # bounded PCC, still User. No ordinary load/store may appear here: the
    # purecap rule refuses every one of them inside a live compartment. Verdicts
    # are carried out in registers and stored after the ecall escape.
    li   x1, 125
    li   x2, 0x800110000010000C            # inside the CALLER's window
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # must refuse now
    mv   x20, x28                          # its mcause

    # the callee's own legitimate work, through the IDC OCInvoke handed it
    li   x21, 0x5A5A
    li   x22, 0
    .insn r 0x0b, 0x3, 0x01, x21, x15, x22 # ocs.d c15, x22, x21
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x23, x15, x22 # ocl.d c15, x22, x23
    li   x25, 1                            # phase: the handler needs to tell
    ecall                                  #        the two escapes apart

.balign 4
trap_handler:
    csrr x27, mcause
    li   x26, 8
    beq  x27, x26, escape
    li   x26, 11
    beq  x27, x26, escape
    addi x29, x29, 1
    mv   x28, x27
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
    mret
escape:
    li   x26, 2
    beq  x25, x26, verdict2
    j    verdict

.balign 4
verdict:
    sd   x20, 0(x31)                       # w0 -- the callee's mcause
    li   x1, 125
    .insn i 0x0b, 0x5, x10, x1, 1
    .insn r 0x5b, 0x0, 0x03, x24, x10, x0
    sd   x24, 8(x31)                       # w1 -- nothing was minted
    li   x1, 121
    .insn i 0x0b, 0x5, x11, x1, 1
    .insn r 0x5b, 0x0, 0x03, x24, x11, x0
    sd   x24, 16(x31)                      # w2 -- the caller's earlier mint survived
    sd   x23, 24(x31)                      # w3 -- the callee still worked
    sd   x29, 32(x31)                      # w4 -- one trap

    # RECOVERY: Machine re-delegates, returns to User, User mints again. This
    # is the word that shows the clear is a clear and not a poisoning.
    li   x1, 120
    .insn i 0x0b, 0x5, x1, x1, 0           # re-bind c1 from the authority object
    .insn r 0x5b, 0x1, 0x13, x13, x1, x0   # ospecialrw c13, ODA, c1
    li   x25, 2
    li   x1, 0x1800
    csrc mstatus, x1
    la   x3, u_again
    csrw mepc, x3
    mret

.balign 4
u_again:
    li   x1, 126
    li   x2, 0x800110000010000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # User mints again -- recovery works
    ecall

.balign 4
verdict2:
    li   x1, 126
    .insn i 0x0b, 0x5, x14, x1, 1
    .insn r 0x5b, 0x0, 0x03, x24, x14, x0
    sd   x24, 40(x31)                      # w5 -- recovery
    sd   x29, 48(x31)                      # w6 -- final trap count

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.section .data
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 8, 8, 0
.global end_signature
end_signature:

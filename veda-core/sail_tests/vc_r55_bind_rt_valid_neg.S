.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R55 -- veda.bind MINTED FROM A REGION THAT WAS NEVER CONFIGURED
    #
    # This model carries TWO region-residency predicates, and they did not
    # agree:
    #     veda_region_rt_resident  = rt_valid & region_resident   <- OCInvoke/OCReturn
    #     veda_region_is_resident  =           region_resident    <- veda.bind
    #
    # The comment on the first says rt_valid "gains its first-ever consumer
    # here: a slot that has never been configured must fail closed even if its
    # resident bit were somehow set." It gained that consumer at the CROSSINGS
    # and not on the MINTING path -- and minting is where a missing gate turns
    # into a capability.
    #
    # Region 3 is R10's own gate fixture, {rt_valid = false, region_resident =
    # true}, built to catch exactly this. MEASURED before the fix:
    #     bind into region 3  ->  0 traps, TAG 1   (minted)
    #     bind into region 2  ->  1 trap,  tag 0   (refused)
    # so the predicate looked at region_resident and not at rt_valid.
    #
    # THE RTL WAS ALREADY RIGHT ($veda_region_resident reads rt_valid &&
    # rt_resident), so this was a SAIL-ONLY divergence in which THE
    # SPECIFICATION WAS MORE PERMISSIVE THAN THE HARDWARE. On a Sail-first
    # project that is the worse direction, and it is closed in the RTL's.
    #
    # REGISTER CHOICE IS NOT INCIDENTAL: c10..c14 are SEEDED by the capability
    # fixtures (wC(Vcapno(10..14))), so reading cgettag on one of them measures
    # the SEED and not the bind. The first attempt to measure this did exactly
    # that and reported both the finding and its control as tag 1. c3..c7 are
    # unseeded, and every step below also records the trap count, so a refusal
    # that traps is distinguishable from a soft-fail.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0

    # Seed one object in each region under test. Populate does not consult the
    # region table at all -- only veda_odt_index's window bounds -- so all three
    # of these succeed regardless of rt_valid or residency, and that is what
    # makes the Bind results below attributable to the Bind gate alone.
    la   t0, arena
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   s9, t0, t1

    li   a1, 50331655                       # {region=3, local=7}
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 33554439                       # {region=2, local=7}
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 16777225                       # {region=1, local=9}
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 77                             # {region=0, local=77} -- the current region
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    bne  s0, x0, check_fail                 # none of the populates may trap

    # ═══ THE FINDING: region 3, never configured, resident bit set ════════
    # A REGION FAULT IS A HARD TRAP FOR EVERY BIND MODE, .notrap included --
    # veda_bind_insts.sail says so in as many words, and the first version of
    # this file asserted zero traps here and failed for that reason rather than
    # for a real one. So each refusal is expected to trap, and the count is
    # asserted exactly rather than as "nonzero".
    li   a1, 50331655
    .insn i 0x0b, 0x5, x3, a1, 1            # veda.bind.notrap c3
    .insn r 0x5b, 0x0, 0x03, t3, x3, x0     # cgettag
    bne  t3, x0, check_fail                 # MUST be 0 -- it was 1 before the fix
    li   t4, 1
    bne  s0, t4, check_fail                 # and it must have TRAPPED, exactly once

    # ═══ CONTROL 1: region 2 is configured but NOT resident -- also refused.
    # Proves the predicate still consults region_resident, so the fix did not
    # merely replace one missing term with another.
    li   a1, 33554439
    .insn i 0x0b, 0x5, x4, a1, 1            # veda.bind.notrap c4
    .insn r 0x5b, 0x0, 0x03, t3, x4, x0
    bne  t3, x0, check_fail
    li   t4, 2
    bne  s0, t4, check_fail                 # the second refusal, and no more

    # ═══ CONTROL 2 -- THE LOAD-BEARING ONE: region 1 is configured AND
    # resident, and a bind into it MUST STILL SUCCEED. Without this word a
    # machine that refused every cross-region bind outright passes everything
    # above. This is the control the register has had to add seven times.
    li   a1, 16777225
    .insn i 0x0b, 0x5, x5, a1, 0            # veda.bind c5 -- plain, must not trap
    .insn r 0x5b, 0x0, 0x03, t3, x5, x0
    li   t4, 1
    bne  t3, t4, check_fail
    li   t4, 2
    bne  s0, t4, check_fail                 # and it added NO trap of its own

    # ═══ CONTROL 3: the intra-region fast path. Region 0 is the current
    # region, whose first arm returns true unconditionally -- a different code
    # path from the two above, and it must keep working.
    li   a1, 77
    .insn i 0x0b, 0x5, x6, a1, 0
    .insn r 0x5b, 0x0, 0x03, t3, x6, x0
    li   t4, 1
    bne  t3, t4, check_fail

    # ═══ CONTROL 4: the capability from region 1 is genuinely USABLE, not
    # merely tagged. A tag without a working dereference would satisfy CONTROL
    # 2 while the object was unreachable.
    li   t1, 0
    li   t2, 0x1234
    .insn r 0x0b, 0x3, 0x01, t2, x5, t1     # ocs.d c5
    li   t3, 0
    .insn r 0x0b, 0x3, 0x00, t3, x5, t1     # ocl.d  c5
    li   t4, 0x1234
    bne  t3, t4, check_fail
    li   t4, 2
    bne  s0, t4, check_fail                 # still exactly the two refusals

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi s0, s0, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.section .data
.balign 32
arena:
    .space 32

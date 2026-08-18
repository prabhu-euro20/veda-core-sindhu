.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R45 -- TWO Object_IDs MAY NAME THE SAME MEMORY, AND THE EXECUTING PIN
    # COMPARES NAMES WHILE THE PROPERTY IT PROTECTS IS ABOUT MEMORY.
    #
    # This test exists because R45 was DERIVED FROM SOURCE and not measured. The
    # standing discipline on this project is that a finding is reproduced before it
    # is acted on, and R45 had not met it. Everything below is what the machine
    # actually does today, not what the reading predicted.
    #
    # PART 1 -- THE ROOT. There is no disjointness check anywhere: Populate and
    # Populate-Fast take Base verbatim, and a grep for overlap/disjoint/intersect
    # across the Veda model, veda_core.tlv and VEDA_CORE_SPEC.md finds nothing.
    # Two names are populated at the SAME Base, both bound, and a store through one
    # is read back through the other.
    #
    # PART 2 -- THE CONSEQUENCE. R11(b) pinned the executing object so that an
    # authority cannot pull the ground out from under running code. But the pin is
    #     veda_object_is_executing(id) = (id == veda_pcc_object) | ...
    # an identity test on the NAME. From inside a live compartment this populates a
    # SECOND name at the running code's own Base and pages THAT out. The pin
    # compares 811 against 810 and passes. The control immediately after shows the
    # pin working correctly on the name it does know.
    #
    #   x21  PART 1: the alias is created without refusal
    #   x22  PART 1: a store through one name is visible through the other
    #   x23  PART 2: an alias set up BEFORE entry -- the real attack order -- can no
    #        longer be evicted from inside the compartment. The pin sees the WINDOW.
    #   x22/x28  PART 2: minting a fresh alias at the running Base is still ALLOWED,
    #        and evicting it is REFUSED -- creation is free, the handle is useless
    #   x24  PART 2 CONTROL B: a DISJOINT object still evicts cleanly
    #   x25  PART 2 CONTROL A: the pin still refuses the object's OWN name
    #   x27  PART 2 CONTROL B: a DISJOINT object still pages out cleanly, so the
    #        window arm refuses overlap and not everything
    #   x20  traps
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x25, 0

    # ═══ PART 1: two names, one arena ═══
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x000C                    # Length 0x100, Perms Load|Store
    csrw 0x7C4, x6
    la   x7, arena
    li   x1, 800
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast 800 at arena
    la   x7, arena
    li   x1, 801
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast 801 at THE SAME arena
    bne  x20, x0, fail                     # neither populate was refused
    li   x21, 0x600D

    li   x1, 800
    .insn i 0x0b, 0x5, x1, x1, 0           # bind c1, 800
    li   x1, 801
    .insn i 0x0b, 0x5, x2, x1, 0           # bind c2, 801
    li   x3, 0
    li   x4, 0xA11A5
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3    # ocs.d through c1 (name 800)
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x2, x3   # ocl.d through c2 (name 801)
    li   x9, 0xA11A5
    bne  x10, x9, fail                     # SAME MEMORY, two names, no refusal
    bne  x20, x0, fail
    li   x22, 0x600D

    # ═══ PART 2: enter a compartment, then alias its code object ═══
    # A BOUNDED code object, deliberately. The corpus's other pin test uses
    # Length UNBOUNDED as a convenience, and an unbounded PCC describes no region
    # of memory at all -- the window arm is gated off in that state and only the
    # name pin applies. A real compartment has real bounds, which is what makes
    # "the memory the CPU is executing from" a well-defined thing to protect.
    li   x6, 0x200
    slli x6, x6, 16
    ori  x6, x6, 0x0402                    # Length 0x200 -- tight, so .data is genuinely OUTSIDE the window
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 810
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # CODE object 810

    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0400                    # Invoke only, not executable
    csrw 0x7C4, x6
    la   x7, data_pad
    li   x1, 811
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # DATA handoff, id 811 (re-pointed later)

    li   x6, 0x40
    slli x6, x6, 16
    ori  x6, x6, 0x0300                    # Seal|Unseal type authority
    csrw 0x7C4, x6
    la   x7, auth_pad
    li   x1, 812
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7

    # THE ATTACKER'S SETUP, done BEFORE entry -- which is the order that matters.
    # No compartment is live here, so veda_pcc_object is NONE and the window arm
    # correctly does not fire: minting an alias is legal, and stays legal. It is
    # EVICTING one while it backs running code that is now refused.
    li   x6, 0x200
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 813
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # 813 aliases the CODE object 810
    # and a DISJOINT object, for the over-refusal control
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x000C
    csrw 0x7C4, x6
    la   x7, far_pad
    li   x1, 814
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7
    bne  x20, x0, fail

    li   x1, 810
    .insn i 0x0b, 0x5, x0, x1, 0           # bind c0, 810 -- CODE
    li   x1, 811
    .insn i 0x0b, 0x5, x11, x1, 0          # bind c11, 811 -- DATA
    li   x1, 812
    .insn i 0x0b, 0x5, x12, x1, 0          # bind c12, 812 -- authority
    .insn r 0x5b, 0x1, 0x10, x13, x0, x12  # cseal c13, c0, c12
    .insn r 0x5b, 0x1, 0x10, x14, x11, x12 # cseal c14, c11, c12
    .insn r 0x5b, 0x1, 0x12, x0, x13, x14  # ocinvoke -- ENTER 810
    j    fail

.balign 4
compartment:
    # PCC now names object 810 and is BOUNDED to it.
    #
    # NOTHING IN HERE MAY BRANCH OUT OR HALT, and that is a real constraint this
    # corpus had never hit. The purecap rule refuses every ordinary load and store
    # while veda_pcc_length != UNBOUNDED, and RVMODEL_HALT_PASS stores to tohost --
    # so halting from inside a bounded compartment traps forever. The other pin
    # test never met this because its compartment is UNBOUNDED, which is the single
    # structural difference between the two files. So this body only RECORDS, and
    # every assertion is made after the escape below.
    li   x27, 0                            # trap count on entry

    # THE ATTACK: evict the alias set up before entry. The pin used to compare 813
    # against veda_pcc_object 810 and pass. It compares WINDOWS now.
    li   x1, 813
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 813 -- must be REFUSED
    mv   x21, x20                          # traps after: want 1

    # MINTING a fresh alias at the running Base is STILL ALLOWED, and that is the
    # line this increment deliberately draws. An earlier draft of this test
    # asserted the mint would be refused; it was not, and the fix is not what was
    # wrong -- the assertion was. Object 815 does not exist yet, so there is no
    # window to compare, and creating a second name for memory harms nothing by
    # itself. Aliasing has to stay legal in any case: SLAB-CARVE mints children
    # INSIDE a parent's window by construction, so a machine that refused overlap
    # outright could never carve.
    li   x6, 0x200
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 815
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast 815 at 810's Base -- ALLOWED
    mv   x22, x20                          # want 1 -- no new trap

    # ...AND THE MOMENT IT NAMES MEMORY, EVICTING IT IS REFUSED. This is the loop
    # closed: creation is free, and the alias is useless as an eviction handle.
    li   x1, 815
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 815 -- REFUSED
    mv   x28, x20                          # want 2

    # CONTROL A: the name arm still refuses the object's own name.
    li   x1, 810
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 810 -- REFUSED
    mv   x23, x20                          # want 3

    # CONTROL B, and the test is worthless without it: a DISJOINT object still
    # evicts cleanly. The window arm must refuse OVERLAP, not everything -- the
    # first draft of this fix refused every eviction on the machine and the other
    # pin test's own over-refusal control caught it on the first run.
    li   x1, 814
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out 814 -- must SUCCEED
    mv   x24, x20                          # want 3 still

    ecall                                  # the escape -- see the handler

.balign 4
all_done:
    # Outside the compartment again: ordinary stores work, so assertions can halt.
    li   x9, 1
    bne  x21, x9, fail
    li   x9, 1
    bne  x22, x9, fail                     # minting the alias took NO trap
    li   x9, 2
    bne  x28, x9, fail                     # evicting it did
    li   x9, 3
    bne  x23, x9, fail
    bne  x24, x9, fail                     # CONTROL B took no new trap
    li   x9, 2
    bne  x26, x9, fail                     # every refusal was Illegal_Instruction
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    # mcause lands in a scratch first, and only a REAL refusal is recorded. The
    # escape below is our own ecall, and an earlier draft let it overwrite x26 --
    # so the final "every refusal was Illegal_Instruction" check compared 0x0B
    # against 2 and failed. The escape must not look like the thing being measured.
    csrr x9, mcause
    li   x30, 0x0B
    beq  x9, x30, escape                   # our own ecall -- leave the compartment
    mv   x26, x9
    addi x20, x20, 1
    csrr x9, mepc
    addi x9, x9, 4
    csrw mepc, x9
    mret
escape:
    # Clear the saved frame's bound before returning, or the automatic
    # restore-on-mret re-narrows PCC to the compartment and the very next fetch
    # outside it faults. The same explicit clear the M21 restore test documents.
    li   x9, 0xFFFFFFFFFF
    csrw 0x7c3, x9
    la   x9, all_done
    csrw mepc, x9
    mret

.section .data
.balign 32
arena:
    .zero 0x100
.balign 32
data_pad:
    .zero 0x100
.balign 32
auth_pad:
    .zero 0x40
.balign 32
far_pad:
    .zero 0x100

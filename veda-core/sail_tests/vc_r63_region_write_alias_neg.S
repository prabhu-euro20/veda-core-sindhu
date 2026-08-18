.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R63 -- the region half of an Object_ID was an IDENTITY on the read path and a
# bare INDEX on the write path.
#
# R10 states the region field is "the unforgeable domain identity". R55 made
# that true for veda.bind. VEDA_ODT_POPULATE's gates are Machine-or-ODA, the
# executing pin, the ODA window and `retired` -- not one of them reads rt_valid
# or region_resident -- so a Populate could name ANY in-window region, and
# regions 4..7 are seeded region_odt_base = 0, which IS region 0's base.
#
# MEASURED before the fix, on the shipped model, by instruction trace:
#   populate {region 5, local 200}  ->  0 traps, ACCEPTED
#   bind     {region 0, local 200}  ->  tag 1, CGetBase = the prober's arena
#   bind     {region 5, local 200}  ->  trap, cause 0x09 REGION_FAULT
# A descriptor written under a name its own author was then refused to read.
#
# This CORRECTS R56, which named the barrier as rt_resident[4] == false and
# concluded the escape needed a future RT-Populate to set it. No new instruction
# was ever required.
#
# Not an escalation: every ODT writer is already bounded by the ODA window
# (R47), and an actor that can write {5,L} can write {0,L} with the identical
# check. What it breaks is namespace integrity -- one slot, several
# legitimate-looking names.
#
# Local 200 rather than a larger number so the RTL twin measures the same slot:
# the RTL indexes with $veda_local[7:0].
.equ ALIAS_ID, (5 << 24) | 200
.equ PLAIN_ID, 200
.equ REAL_ID,  (1 << 24) | 200
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0                             # trap counter. NOT t4 -- t4 IS x29.
    li   x26, 0

    # CONTROL 1: slot 200 starts empty, so the plain name must be refused, and
    # refused for the RIGHT reason.
    li   x1, PLAIN_ID
    .insn i 0x0b, 0x5, x3, x1, 0
    li   t3, 1
    bne  x27, t3, fail
    andi t3, x26, 0x1f
    li   t5, 0x05
    bne  t3, t5, fail                       # OBJECT_NOT_FOUND

    # THE FINDING: populate under a region that has never been configured.
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C                     # Len 0x20, Perms Load|Store
    or   x2, x6, x7
    li   x1, ALIAS_ID
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   t3, 2
    bne  x27, t3, fail                      # must trap. Before the fix: accepted.
    li   x20, 0x600D

    # CONTROL 2: and it wrote NOTHING. The plain name is still empty, still for
    # the same reason -- so the refusal above was a refusal, not a redirect.
    li   x1, PLAIN_ID
    .insn i 0x0b, 0x5, x4, x1, 0
    li   t3, 3
    bne  x27, t3, fail
    andi t3, x26, 0x1f
    li   t5, 0x05
    bne  t3, t5, fail
    .insn r 0x5b, 0x0, 0x03, x21, x4, x0    # cgettag -- must be 0
    bnez x21, fail
    li   x22, 0x600D

    # CONTROL 3: a REAL region still works. Region 1 is configured and resident.
    # Without this a machine that refused every cross-region populate would be
    # indistinguishable from one that got this right.
    li   x1, REAL_ID
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   t3, 3
    bne  x27, t3, fail                      # no new trap
    li   x1, REAL_ID
    .insn i 0x0b, 0x5, x6, x1, 0
    li   t3, 3
    bne  x27, t3, fail
    .insn r 0x5b, 0x0, 0x03, x23, x6, x0    # cgettag -- must be 1
    li   t5, 1
    bne  x23, t5, fail
    .insn r 0x5b, 0x0, 0x00, x24, x6, x0    # cgetbase -- must be the arena
    la   x25, arena
    bne  x24, x25, fail
    li   x28, 0x600D

    li   t5, 0x600D
    bne  x20, t5, fail
    bne  x22, t5, fail
    bne  x28, t5, fail
    RVMODEL_HALT_PASS
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
fail:
    RVMODEL_HALT_FAIL
.section .data
.balign 64
arena:
    .space 64

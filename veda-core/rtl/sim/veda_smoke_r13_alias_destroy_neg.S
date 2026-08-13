.section .text
.global _start
// RTL-10 (R13, DESIGN_07 Tier H): DESTROY MAY NOT CLEAR A SLOT IT DOES NOT
// OWN.
//
// Milestone 15 found and fixed low-byte aliasing: Object_ID 32 and Object_ID
// 288 (32 + 256) share a slot in this core's 256-entry model, and before that
// fix a Bind for 32 issued after 288 was populated silently returned 288's
// object. The fix stores the full Object_ID in the slot and requires it to
// match -- but only on the two READ paths.
//
// Destroy is an access too, and it had no such tag check. So an authorized
// actor could clear a LIVE object's descriptor by naming any alias of it:
// `veda.odt.destroy 288` lands on slot 32 and wipes object 32.
//
// This bug cannot exist on the Sail model, which indexes with the FULL 24-bit
// local (2^20 per region) -- there 32 and 288 are genuinely different entries
// and destroying one cannot touch the other. It is reachable only in this
// truncated model, which is exactly the class of thing that has to be found
// and tested HERE rather than inherited from the model.
//
// PART A -- destroy the ALIAS. Object 32 must survive: still Bindable, still
//           reading back its own Base and its own data.
// PART B -- the control. Destroying object 32 BY ITS OWN NAME must still work,
//           or the gate above would be over-refusing and PART A would pass for
//           the wrong reason -- a core that ignored every Destroy would pass
//           PART A trivially.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0                            // trap counter

    // ---- populate Object_ID 32 -> array_a (Length 8, Load|Store)
    la   x5, array_a
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 32
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // veda.odt.populate

    li   x1, 32
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 32
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2    // ocl.d -- sanity read
    li   x9, 0xAAAA
    bne  x8, x9, fail
    li   x21, 0x600D

    // ═══ PART A: destroy the ALIAS 288. Object 32 must be untouched. ═══
    li   x1, 288
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0    // veda.odt.destroy 288
    bne  x20, x0, fail                     // no trap: 288 simply is not here

    // Re-Bind 32 from scratch. A cleared valid bit would make this trap
    // (cause 0x05), and a bumped generation would kill the capability.
    li   x1, 32
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, 32
    bne  x20, x0, fail
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x10, x1, x2   // ocl.d through the FRESH cap
    li   x9, 0xAAAA
    bne  x10, x9, fail                     // still object 32's own data
    li   x22, 0x600D

    // The ORIGINAL capability must still work too -- proving the generation
    // was not bumped underneath it by the aliased Destroy.
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x11, x0, x2   // ocl.d through the OLD cap c0
    li   x9, 0xAAAA
    bne  x11, x9, fail
    li   x23, 0x600D

    // ═══ PART B: destroying 32 BY ITS OWN NAME must still work. ═══
    // Without this, a core that refused every Destroy would pass PART A.
    li   x1, 32
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0    // veda.odt.destroy 32
    bne  x20, x0, fail

    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, 32 -- must TRAP now
    li   x9, 1
    bne  x20, x9, fail                     // exactly one trap
    li   x24, 0x600D

    li   x9, 0x600D
    bne  x21, x9, fail
    bne  x22, x9, fail
    bne  x23, x9, fail
    bne  x24, x9, fail
    li   x30, 0xD09E
    j    done

.balign 4
// Scratch is x16/x17 -- raw x-numbered registers. t5/t6 are x30/x31 and x30
// is the result register here.
trap_handler:
    addi x20, x20, 1
    csrr x25, mcause
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x30, 0xBAD
done:
    j    done

.section .data
.balign 32
array_a:
    .dword 0xAAAA
    .dword 0xAAAA

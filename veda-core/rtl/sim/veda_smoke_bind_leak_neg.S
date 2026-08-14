.section .text
.global _start
// RTL-14: A FAILED BIND MUST HAND BACK NOTHING.
//
// veda.bind.notrap is the deliberately SILENT probe -- it soft-fails instead of
// trapping. That is exactly what made this leak worse than a noisy one: there
// was no fault for anyone to notice.
//
// On failure this core used to write the resolved slot's Base, Length, Perms
// and Object_ID into the destination and clear only the Tag. The comment there
// called those fields "dead either way once Tag=0". They are not dead -- the
// capability query family is deliberately NOT tag-gated, so cgetbase after a
// failed probe returned the RAW PHYSICAL BASE of whatever live object happens
// to occupy that slot.
//
// That is a direct breach of the address-less pillar: software is never
// supposed to see a physical address at all, and here any program could read
// one for an object it does not own, by guessing a number, silently.
//
// Sail writes zero_capability on the same failure, so this was also a
// divergence -- the model was right and the hardware leaked.
//
// PART A -- probe a NEVER-POPULATED Object_ID whose slot is occupied by a live
//           object (50 aliases nothing; 257 aliases region-1 slot 1, which IS
//           populated at reset). Tag must be 0 AND every field must read 0.
// PART B -- the positive control: a real bind still returns real values, so
//           PART A cannot pass by the query being broken for everyone.
_start:
    li   x20, 0

    // ═══ PART B first: object 1 is reset-seeded, Base 0x80010000 ═══
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 1
    .insn r 0x5b, 0x0, 0x03, x21, x0, x0   // cgettag  x21, c0 -- expect 1
    .insn r 0x5b, 0x0, 0x00, x22, x0, x0   // cgetbase x22, c0 -- expect real
    li   x9, 1
    bne  x21, x9, fail
    beqz x22, fail                         // a real bind must return a real Base

    // ═══ PART A: silent probe of an Object_ID that aliases a LIVE slot ═══
    // 257 = region 1, local 1. Region 1's local 1 is seeded at reset, so the
    // slot is occupied -- but this hart may not simply name it and read it.
    li   x1, 257
    .insn i 0x0b, 0x5, x5, x1, 1           // veda.bind.notrap c5, 257
    .insn r 0x5b, 0x0, 0x03, x23, x5, x0   // cgettag  x23, c5 -- must be 0
    .insn r 0x5b, 0x0, 0x00, x24, x5, x0   // cgetbase x24, c5 -- must be 0
    .insn r 0x5b, 0x0, 0x01, x25, x5, x0   // cgetlen  x25, c5 -- must be 0
    .insn r 0x5b, 0x0, 0x02, x26, x5, x0   // cgetperm x26, c5 -- must be 0
    bnez x23, fail                         // tag was already correct before
    bnez x24, fail                         // THIS is the leak: raw Base
    bnez x25, fail
    bnez x26, fail

    // ═══ and a never-populated one, for the plain not-found path ═══
    li   x1, 50
    .insn i 0x0b, 0x5, x6, x1, 1           // veda.bind.notrap c6, 50
    .insn r 0x5b, 0x0, 0x00, x27, x6, x0   // cgetbase x27, c6 -- must be 0
    bnez x27, fail

    li   x30, 0xD09E
    j    done
fail:
    li   x30, 0xBAD
done:
    j    done

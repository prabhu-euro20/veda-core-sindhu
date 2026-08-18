#include "veda_priv_macros.h"
.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 11: OSpecialRW + capability-authority-
    # gated ODT-Populate/ODT-Destroy (NEXT_STEPS_ROADMAP.md §2.5,
    # VEDA_CORE_SPEC.md's own "a real capability-permission-gated
    # version would need Veda-Core's own privileged-capability model
    # designed first" -- that model is the ODA, now real).
    #
    # This is the one, genuinely real proof Sail's own test could NOT
    # provide (this project's own Sail test config has S/U-mode
    # disabled, so privilege can never actually drop below Machine
    # there) -- RTL's own real `veda.droppriv` (Milestone 4) lets this
    # test prove the ODA authorization path works genuinely
    # independently of ordinary privilege, not just alongside it.
    #
    # Object_ID=40: a real "ODT-manager" authority object,
    # Perms=0x0080 (Permit_Access_System_Registers, bit 7).
    # ─────────────────────────────────────────────────────────────
    li   x1, 40
    li   x2, 0x8001100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 40
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- the authority capability, unsealed

    # -- OSpecialRW's own atomic read-then-write, exercised twice. --
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0  # ospecialrw c2, c1  -- c2 = ODA's OLD value (expect Tag=0); ODA := c1
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag x10, c2    -- expect 0

    .insn r 0x5b, 0x1, 0x13, x3, x1, x0  # ospecialrw c3, c1  -- c3 = ODA's OLD value (now c1); ODA := c1 again
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag  x11, c3   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x12, x3, x0  # cgetbase x12, c3   -- expect 0x80011000 (c1's own real Base)

    # -- The real proof: drop ordinary privilege entirely, then attempt
    #    ODT-Populate -- it must STILL succeed, purely via the ODA path,
    #    with zero ordinary-privilege help. --
    VEDA_DROP_TO_USER(x28, x29)   // R36: the architected drop -- mstatus.MPP=U then mret

    # ═══ R47 CHANGED THIS LINE, AND THE OLD ONE WAS THE ESCAPE ═══════════
    # This test used to mint object 41 at Base 0x80012000 -- FOUR KILOBYTES
    # OUTSIDE its own authority object's window, which is object 40 at
    # [0x80011000, 0x80011040) as populated at the top of this file. It passed,
    # and its comment above calls that "the real proof" the ODA path works.
    # It is that. It was also a demonstration that a User-mode holder of an ODA
    # could mint a descriptor over memory the ODA never named, Bind it, and
    # dereference it -- and by passing, it pinned the escape as the contract.
    #
    # veda_oda_authorized() reads three bits of a 256-bit capability: tag,
    # otype, Perms[7]. Base and Length were carried through every OSpecialRW
    # and every trap and read by nothing. R47 makes them load-bearing on the
    # DELEGATED path only; Machine still needs no ODA and is untouched.
    #
    # So the mint now lands INSIDE the window -- Base 0x80011000, Length 0x20 --
    # which is what a correctly delegated allocator does, and the test's own
    # subject (ODT-Populate succeeding on ODA authority alone, with ordinary
    # privilege fully dropped) is unchanged and still proven. The refusal half
    # lives in difftest/probes/p20_oda_scope.S, where both layers are compared.
    li   x1, 41
    li   x2, 0x8001100000200300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- must succeed via ODA alone (!$priv now)

    li   x1, 41
    .insn i 0x0b, 0x5, x4, x1, 0  # veda.bind c4, x1
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  # cgettag  x13, c4   -- expect 1 (a real ODT entry really was created)
    .insn r 0x5b, 0x0, 0x00, x14, x4, x0  # cgetbase x14, c4   -- expect 0x80011000 (R47: inside the ODA's window)
1:
    j 1b

.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R39 -- the generic CSR privilege check, pinned in the suite that runs on
    # every change to the model.
    #
    # The model was NOT modified by this increment; it was already right. This
    # test exists because the RTL was wrong for a long time and nothing in this
    # suite said what the contract was, so there was nothing for the RTL to be
    # measured against short of reading Sail source -- which is exactly how the
    # RTL's own R27 test came to assert a trap count of ZERO for unprivileged CSR
    # access and call it Sail parity. It had read the inner Veda write_CSR clause
    # and missed check_CSR_priv, which runs above every one of them:
    #
    #     csrPriv(csr)           = csr[9..8]                    (sys_control.sail:19)
    #     check_CSR_priv(csr, p) = privLevel_to_CSR_privbits(p) >=_u csrPriv(csr)
    #
    # Every CSR this design implements sits at 0x3xx or 0x7Cx, so csrPriv is 0b11
    # for all of them and User's own bits are 0b00: the access is illegal before
    # any dispatch. Three properties, each asserted rather than described.
    #
    #   1. a Machine-only CSR READ from User raises Illegal_Instruction, and
    #      leaves rd untouched -- the trap is not allowed to also deliver the
    #      value, which is the whole of what gating reads buys.
    #   2. MRET below Machine is illegal. Without it, unprivileged code writes
    #      mstatus.MPP and returns itself into Machine.
    #   3. ECALL from User reports 0x08, not 0x0B -- the handler is entitled to
    #      know who called it.
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0                      # trap count
    li   s1, 0                      # cause of the most recent trap

    # drop to User the architected way: MPP = 0b00, then mret
    li   t1, 0x1800
    csrc mstatus, t1
    la   t2, umode
    csrw mepc, t2
    mret

umode:
    li   a0, 0xBAD
csr_read_site:
    csrr a0, 0x7c1                  # Machine-only CSR, read, from User
    li   t3, 0xBAD
    bne  a0, t3, check_fail         # rd must be UNTOUCHED, not merely trapped
    li   t3, 0x02
    bne  s1, t3, check_fail
    li   t3, 1
    bne  s0, t3, check_fail

mret_site:
    mret                            # illegal below Machine
    li   t3, 0x02
    bne  s1, t3, check_fail
    li   t3, 2
    bne  s0, t3, check_fail

    ecall
    li   t3, 0x08                   # E_U_EnvCall, not E_M_EnvCall
    bne  s1, t3, check_fail
    li   t3, 3
    bne  s0, t3, check_fail

    # CONTROL: ordinary unprivileged work still runs, so a model that simply
    # refused everything after the drop could not pass this test.
    li   t3, 7
    addi t3, t3, 3
    li   t4, 10
    bne  t3, t4, check_fail

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

.section .text
.global _start
# R24 -- the CAPABILITY REGISTER FILE RESET STATE, measured before anything
# touches it. Sixteen registers x six queries = 96 observations, taken as the
# FIRST instructions after reset, before any bind.
#
# This probe exists because a proposal to fix the rebind divergence by
# requiring a tagged destination was REFUTED: it would have converted a
# 13-register divergence into a 2-register divergence of identical shape,
# because c11 and c12 are seeded TAGGED on both layers and would pass the new
# check. The divergence was never about rebind. `cgettype x3, c0` on a reset
# machine already returns 0x0000 on Sail and 0xFFFF on the RTL -- one
# instruction, no rebind, and the query family is deliberately ungated.
#
# So the question is not "what should rebind refuse" but "what does a
# capability register CONTAIN at reset", and neither layer's answer is written
# down anywhere. This probe is the measurement that must precede the decision.
_start:
    li   x31, 0x80070000
    .insn r 0x5b, 0x0, 0x03, x28, x0, x0   # cgettag c0
    sd   x28, 0(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x0, x0   # cgettype c0
    sd   x28, 8(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x0, x0   # cgetperm c0
    sd   x28, 16(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x0, x0   # cgetbase c0
    sd   x28, 24(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x0, x0   # cgetlen c0
    sd   x28, 32(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x0, x0   # cgetoffset c0
    sd   x28, 40(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x1, x0   # cgettag c1
    sd   x28, 48(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x1, x0   # cgettype c1
    sd   x28, 56(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x1, x0   # cgetperm c1
    sd   x28, 64(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x1, x0   # cgetbase c1
    sd   x28, 72(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x1, x0   # cgetlen c1
    sd   x28, 80(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x1, x0   # cgetoffset c1
    sd   x28, 88(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x2, x0   # cgettag c2
    sd   x28, 96(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x2, x0   # cgettype c2
    sd   x28, 104(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x2, x0   # cgetperm c2
    sd   x28, 112(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x2, x0   # cgetbase c2
    sd   x28, 120(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x2, x0   # cgetlen c2
    sd   x28, 128(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x2, x0   # cgetoffset c2
    sd   x28, 136(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x3, x0   # cgettag c3
    sd   x28, 144(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x3, x0   # cgettype c3
    sd   x28, 152(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x3, x0   # cgetperm c3
    sd   x28, 160(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x3, x0   # cgetbase c3
    sd   x28, 168(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x3, x0   # cgetlen c3
    sd   x28, 176(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x3, x0   # cgetoffset c3
    sd   x28, 184(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x4, x0   # cgettag c4
    sd   x28, 192(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x4, x0   # cgettype c4
    sd   x28, 200(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x4, x0   # cgetperm c4
    sd   x28, 208(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x4, x0   # cgetbase c4
    sd   x28, 216(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x4, x0   # cgetlen c4
    sd   x28, 224(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x4, x0   # cgetoffset c4
    sd   x28, 232(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x5, x0   # cgettag c5
    sd   x28, 240(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x5, x0   # cgettype c5
    sd   x28, 248(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x5, x0   # cgetperm c5
    sd   x28, 256(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x5, x0   # cgetbase c5
    sd   x28, 264(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x5, x0   # cgetlen c5
    sd   x28, 272(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x5, x0   # cgetoffset c5
    sd   x28, 280(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x6, x0   # cgettag c6
    sd   x28, 288(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x6, x0   # cgettype c6
    sd   x28, 296(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x6, x0   # cgetperm c6
    sd   x28, 304(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x6, x0   # cgetbase c6
    sd   x28, 312(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x6, x0   # cgetlen c6
    sd   x28, 320(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x6, x0   # cgetoffset c6
    sd   x28, 328(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x7, x0   # cgettag c7
    sd   x28, 336(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x7, x0   # cgettype c7
    sd   x28, 344(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x7, x0   # cgetperm c7
    sd   x28, 352(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x7, x0   # cgetbase c7
    sd   x28, 360(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x7, x0   # cgetlen c7
    sd   x28, 368(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x7, x0   # cgetoffset c7
    sd   x28, 376(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x8, x0   # cgettag c8
    sd   x28, 384(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x8, x0   # cgettype c8
    sd   x28, 392(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x8, x0   # cgetperm c8
    sd   x28, 400(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x8, x0   # cgetbase c8
    sd   x28, 408(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x8, x0   # cgetlen c8
    sd   x28, 416(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x8, x0   # cgetoffset c8
    sd   x28, 424(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x9, x0   # cgettag c9
    sd   x28, 432(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x9, x0   # cgettype c9
    sd   x28, 440(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x9, x0   # cgetperm c9
    sd   x28, 448(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x9, x0   # cgetbase c9
    sd   x28, 456(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x9, x0   # cgetlen c9
    sd   x28, 464(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x9, x0   # cgetoffset c9
    sd   x28, 472(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x10, x0   # cgettag c10
    sd   x28, 480(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x10, x0   # cgettype c10
    sd   x28, 488(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x10, x0   # cgetperm c10
    sd   x28, 496(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x10, x0   # cgetbase c10
    sd   x28, 504(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x10, x0   # cgetlen c10
    sd   x28, 512(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x10, x0   # cgetoffset c10
    sd   x28, 520(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x11, x0   # cgettag c11
    sd   x28, 528(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x11, x0   # cgettype c11
    sd   x28, 536(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x11, x0   # cgetperm c11
    sd   x28, 544(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x11, x0   # cgetbase c11
    sd   x28, 552(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x11, x0   # cgetlen c11
    sd   x28, 560(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x11, x0   # cgetoffset c11
    sd   x28, 568(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x12, x0   # cgettag c12
    sd   x28, 576(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x12, x0   # cgettype c12
    sd   x28, 584(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x12, x0   # cgetperm c12
    sd   x28, 592(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x12, x0   # cgetbase c12
    sd   x28, 600(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x12, x0   # cgetlen c12
    sd   x28, 608(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x12, x0   # cgetoffset c12
    sd   x28, 616(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x13, x0   # cgettag c13
    sd   x28, 624(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x13, x0   # cgettype c13
    sd   x28, 632(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x13, x0   # cgetperm c13
    sd   x28, 640(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x13, x0   # cgetbase c13
    sd   x28, 648(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x13, x0   # cgetlen c13
    sd   x28, 656(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x13, x0   # cgetoffset c13
    sd   x28, 664(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x14, x0   # cgettag c14
    sd   x28, 672(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x14, x0   # cgettype c14
    sd   x28, 680(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x14, x0   # cgetperm c14
    sd   x28, 688(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x14, x0   # cgetbase c14
    sd   x28, 696(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x14, x0   # cgetlen c14
    sd   x28, 704(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x14, x0   # cgetoffset c14
    sd   x28, 712(x31)
    .insn r 0x5b, 0x0, 0x03, x28, x15, x0   # cgettag c15
    sd   x28, 720(x31)
    .insn r 0x5b, 0x0, 0x04, x28, x15, x0   # cgettype c15
    sd   x28, 728(x31)
    .insn r 0x5b, 0x0, 0x02, x28, x15, x0   # cgetperm c15
    sd   x28, 736(x31)
    .insn r 0x5b, 0x0, 0x00, x28, x15, x0   # cgetbase c15
    sd   x28, 744(x31)
    .insn r 0x5b, 0x0, 0x01, x28, x15, x0   # cgetlen c15
    sd   x28, 752(x31)
    .insn r 0x5b, 0x0, 0x06, x28, x15, x0   # cgetoffset c15
    sd   x28, 760(x31)
    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.section .tohost, "aw", @progbits
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 96, 8, 0
.global end_signature
end_signature:

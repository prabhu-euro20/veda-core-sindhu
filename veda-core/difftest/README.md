# Cross-layer differential harness

Sail and the RTL are two independent implementations of one specification.
**Any behavioural difference between them is a bug in one of them** -- and until
this harness existed, nothing compared them. The two corpora are not even the
same programs.

That gap was not theoretical. Three RTL-only defects were found in this project
by a human reading code, none by a test: the aliasing write path (R13), the
capability bounds width (R23a), and the Rebind copy-on-write mask (R23b). This
harness finds that class mechanically.

## How it works

One probe program, assembled once, run on both layers, compared byte for byte.

The shared observable is the **official RISC-V arch-test signature mechanism**:
the probe writes its observations to a `.signature` section at `0x8007_0000`,
`sail_riscv_sim --test-signature` dumps it, and `tb_diff.sv` dumps the same
range out of `elfmem[]` in the identical 32-bit little-endian format.

    ./rundiff.sh probes/p3_faults.S
    AGREE     p3_faults
    DIVERGE   p4_cow
      word sail       rtl
      4    00000000   00001004     <-- DIFFERS

**THAT SENTENCE USED TO SAY "It asserts nothing. Divergence is the finding, not
failure." IT IS NO LONGER TRUE, AND THE CHANGE IS THE POINT.** `rundiff.sh`'s exit
code is now the verdict -- 0 agree, 1 diverge, 2 infrastructure failure -- because
a comparator that could not fail, and that nothing invoked, was a script rather
than verification (R31).

## The entry point, which this file never named

    ./run_difftests.sh

**That** is what runs the suite. It holds the EXPECTED VERDICT for every probe and
fails in both directions: an expected-AGREE probe that diverges, and an
expected-DIVERGE probe that starts agreeing without anyone updating the record. A
probe known to diverge is listed as DIVERGE with its reason rather than hidden
behind an all-must-agree suite. Current state: **25/25 as expected.**

`./rundiff.sh probes/<name>.S` runs one probe and prints the word-by-word
comparison above -- useful while writing one, not the suite.

## Building the RTL side -- you do not

`rundiff.sh` rebuilds `sim_diff.vvp` from `veda_core.sv` on every run, and it
**hard-refuses with FATAL** if `veda_core.sv` is missing or older than
`veda_core.tlv`. Hand-building it is work the harness undoes, and worse, a reader
can take a successful hand-build as a substitute for re-running the smoke runner --
which is exactly the staleness the guard exists to prevent. If the harness tells
you the transpiled output is stale, run `../rtl/run_veda_smoke_test.sh`; do not
build around it.

## Writing a probe -- one hard constraint

**CLOSED BY R24, AND LEAVING THIS SECTION AS IT WAS WOULD BE THE MOST HARMFUL LINE
IN THE FILE.** It used to read: "The two layers seed DIFFERENT capability registers
at reset... treat any divergence involving c10-c14 as suspect until the fixtures
are reconciled." That told probe authors to **discount exactly the class of
divergence that would today be a real defect.**

Both layers now have a defined architectural reset -- `veda_reset_crf()` zeroes all
sixteen registers and clears the tags -- and the seeded fixtures are gated OFF that
reset on both sides, off by default, with this harness passing neither. `p_reset_crf.S`
records the agreement probe by probe.

**So the constraint for a probe author is the opposite one now:** a divergence in
any capability register, c10-c14 included, is a finding until proven otherwise.
Probes should still bind what they need rather than lean on reset state, because a
probe that depends on a fixture is measuring the fixture -- a mistake this corpus
has made three times, most recently in a draft that read a seeded tag and drew the
opposite conclusion.

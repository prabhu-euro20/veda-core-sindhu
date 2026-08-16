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

It asserts nothing. **Divergence is the finding, not failure.**

## Building the RTL side

    iverilog -g2012 -I ../rtl/sim -o sim_diff.vvp ../rtl/sim/veda_core.sv tb_diff.sv

`veda_core.sv` is the SandPiper output; regenerate it with the smoke runner
first if `veda_core.tlv` has changed.

## Writing a probe -- one hard constraint

**The two layers seed DIFFERENT capability registers at reset.** Sail seeds
c10-c14; the RTL seeds a different set with different contents. A probe that
reads a seeded register is not comparing the same thing on both sides, and will
report a divergence that is a fixture difference rather than a defect. Probes
should bind what they need, and treat any divergence involving c10-c14 as
suspect until the fixtures are reconciled.

Reconciling those fixtures is worth doing on its own: two layers that do not
agree on their reset state cannot be compared on any test that touches it.

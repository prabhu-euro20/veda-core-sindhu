# `sail_tests/pending/` -- reproductions that assert a contract not yet taken

A test in this directory **is red on purpose**. It reproduces a measured finding and asserts the
behaviour the architecture *will* owe once a decision is made -- not the behaviour it has today.

It lives here rather than in `sail_tests/` because the runner globs `vc_*.S` there and a red test
would fail the suite; and it lives here rather than nowhere because **R49 measured what happens to a
test nobody runs**: seven programs sat in `rtl/sim/` for twenty increments, one of them asserting the
opposite of the architecture, and nothing said so.

Neither is it allowed to become a dark directory. Every file here must be named in the table below
with the finding it belongs to and the decision that would let it move up one level.

| file | finding | what has to be decided before it can move |
|---|---|---|
| `vc_r52_bind_by_name_neg.S` | DESIGN_07 **R52**, second half | **The creation-time default LANDED** -- objects created inside a compartment now belong to that compartment's domain, and `sail_tests/vc_r52_creation_domain.S` demonstrates a region-1 compartment's object being refused to a region-0 one, with the R17 return path intact. **This file is still red, and correctly so**: both of its compartments live in **region 0**, so they are **one domain**, and `veda_bind_domain_ok` compares `owner_domain` against `veda_pcc_object[43 .. 24]` -- the REGION. Two compartments in one region are one principal *by design* (R10 makes the region field the unforgeable domain identity). What this file now waits on is the **re-graining of the gate's subject from region to object**, which is a separate decision and needs a field wider than `owner_domain`'s 20 bits to hold a 44-bit identity. |

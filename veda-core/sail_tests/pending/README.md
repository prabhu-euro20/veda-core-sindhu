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
| `vc_r52_bind_by_name_neg.S` | DESIGN_07 **R52** | the object-creation binding policy. Today `veda_bind_domain_ok` returns true whenever `owner_domain == VEDA_DOMAIN_ANY`, and that is what every Populate writes -- so a callee that knows an Object_ID re-binds it and reads the caller's object with **zero traps**, even after the caller untags its own register. The gate is sound (with `owner_domain` actually set: 2 traps, nothing read); only its default is open. Deferred deliberately -- `odt_entry`'s own comment says "mechanism first, policy second" -- and the previous attempt, R17, was **retracted the same day** for making compartments one-way. |

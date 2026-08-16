# Mutation census -- the trap-decision layer

**22 of 54 mutants SURVIVED. 41% of the trap-decision layer is unverified.**

## What was measured

Every dereference path decides two separate things:

- `$veda_*_violation` -- an OR of terms, deciding **whether a trap fires at all**
- `$veda_*_cause` -- a ternary chain, deciding **which number a handler reads**

The cause chain is only consulted when the violation expression is true, so the
violation expression is the actual enforcement layer. This census removed **one
term at a time** from all seven of them -- 54 mutants -- and ran the full
82-test suite against each. A survivor is a check **no test in the corpus can
see**: it is present and correct today, and nothing would notice if it were
deleted tomorrow.

Pristine restored byte-identical, 82/82, and re-verified by diff.

## The three shapes

### 1. The two most security-critical checks are the least verified

| check | chains where removing it breaks NOTHING |
|---|---|
| `$veda_sealed` | **6 of 7** |
| `$veda_gen_stale` | **6 of 7** |

`$veda_gen_stale` **is temporal safety.** It is the entire use-after-free
defence: an object's generation is bumped on Destroy and on page-out, and this
term is what refuses a capability whose generation no longer matches. Delete it
on six of seven dereference paths and **a stale capability reads and writes
freed memory with no trap**, and the suite stays green.

This is not hypothetical for this codebase. The CAndPerm defect was exactly
this: a derivation carried neither Object_ID nor generation, and the two
existing tests inspected the result with CGetPerm instead of dereferencing
through it. Same area, same blind spot, already burned once.

### 2. Coverage falls off as the path gets less ordinary

| chain | unverified |
|---|---|
| `ocl`  (plain load)  | 1/6 |
| `ocs`  (plain store) | 2/7 |
| `ocsc` (capability store) | 3/8 |
| `atomic` | 3/8 |
| `nmc_add_d` | 4/9 |
| `oclc` (capability load) | 4/7 |
| `nmc_add_w` | **5/9** |

The corpus tests the ordinary load and store paths well and the capability,
near-memory-compute and atomic paths poorly -- and those are precisely the paths
where this project has already found real defects (R15 wrote memory with no
store permission; R23a bounds-checked 16 bytes for a 32-byte access).

### 3. A test of my own passes for the right reason on one axis and the wrong one on another

`veda_smoke_check_order.S` phases P3/P4/P5 drive `nmc_add_d`, `nmc_add_w` and
`atomic` through a **Length-0 capability**, and assert the cause is BOUNDS. Yet
the bounds term survives its own mutant on all three chains.

The reason is worth writing down. In that test the object is **also
copy-on-write**, so with the bounds term removed from the violation expression
`$veda_cow_write` still fires the trap -- and the cause chain, where bounds
correctly precedes cow, still reports 0x01. The assertion holds for a reason the
test did not intend.

**So P3/P4/P5 verify the cause ORDER and not the trap DECISION.** Closing this
needs a Length-0 capability to a **non-cow** object, which nothing currently
exercises. A hand-written test could not have found this; the census did.

## The work list, in priority order

1. `$veda_gen_stale` on ocl, ocs, oclc, ocsc, nmc_add_w, nmc_add_d -- temporal
   safety, and the area with a prior defect of exactly this shape.
2. `$veda_sealed` on ocs, oclc, ocsc, nmc_add_w, nmc_add_d, atomic.
3. `!$veda_perm_load_ok` on oclc, nmc_add_w, nmc_add_d.
4. Bounds as a **trap decision** on nmc_add_w, nmc_add_d, atomic -- needs a
   Length-0 capability to a non-cow object.
5. `$veda_cow_write` as a trap decision on ocsc, nmc_add_w, atomic.
6. `$veda_capmem_misaligned` on oclc.

## What this census did NOT cover

Only the seven dereference violation expressions. Not covered: the bind path,
the ODT write path, the domain crossings, the capability-manipulation
instructions, the trap-save machinery, or any Sail-side term. Each is its own
census and each should be run before that area is trusted.

## Raw results

    census: 54 mutants
    killed    M1  $veda_ocl_violation  term[0] = $is_veda_ocl && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M2  $veda_ocl_violation  term[1] = $veda_gen_stale
    killed    M3  $veda_ocl_violation  term[2] = $veda_sealed   -> Milestone 6
    killed    M4  $veda_ocl_violation  term[3] = !$veda_perm_load_ok   -> RTL-12 permission enforcement
    killed    M5  $veda_ocl_violation  term[4] = !$veda_bounds_ok   -> RTL-16 bounds wrap
    killed    M6  $veda_ocl_violation  term[5] = $veda_deref_nonresident)   -> ?
    killed    M7  $veda_ocs_violation  term[0] = $is_veda_ocs && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M8  $veda_ocs_violation  term[1] = $veda_gen_stale
    SURVIVED  M9  $veda_ocs_violation  term[2] = $veda_sealed
    killed    M10  $veda_ocs_violation  term[3] = $veda_cow_write   -> RTL-18 copy-on-write
    killed    M11  $veda_ocs_violation  term[4] = !$veda_perm_store_ok   -> RTL-12 permission enforcement
    killed    M12  $veda_ocs_violation  term[5] = !$veda_bounds_ok   -> RTL-16 bounds wrap
    killed    M13  $veda_ocs_violation  term[6] = $veda_deref_nonresident)   -> ?
    killed    M14  $veda_oclc_violation  term[0] = $is_veda_ocl_c && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M15  $veda_oclc_violation  term[1] = $veda_gen_stale
    SURVIVED  M16  $veda_oclc_violation  term[2] = $veda_sealed
    SURVIVED  M17  $veda_oclc_violation  term[3] = !$veda_perm_load_ok
    killed    M18  $veda_oclc_violation  term[4] = !$veda_oclc_bounds_ok   -> RTL-16 bounds wrap
    SURVIVED  M19  $veda_oclc_violation  term[5] = $veda_capmem_misaligned
    killed    M20  $veda_oclc_violation  term[6] = $veda_deref_nonresident)   -> ?
    killed    M21  $veda_ocsc_violation  term[0] = $is_veda_ocs_c && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M22  $veda_ocsc_violation  term[1] = $veda_gen_stale
    SURVIVED  M23  $veda_ocsc_violation  term[2] = $veda_sealed
    SURVIVED  M24  $veda_ocsc_violation  term[3] = $veda_cow_write
    killed    M25  $veda_ocsc_violation  term[4] = !$veda_perm_store_ok   -> RTL-12 permission enforcement
    killed    M26  $veda_ocsc_violation  term[5] = !$veda_oclc_bounds_ok   -> R23 bounds width + rebind cow mask
    killed    M27  $veda_ocsc_violation  term[6] = $veda_capmem_misaligned   -> RTL-2a misaligned
    killed    M28  $veda_ocsc_violation  term[7] = $veda_deref_nonresident)   -> ?
    killed    M29  $veda_nmc_add_w_violation  term[0] = $is_veda_nmc_add_w && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M30  $veda_nmc_add_w_violation  term[1] = $veda_gen_stale
    SURVIVED  M31  $veda_nmc_add_w_violation  term[2] = $veda_sealed
    killed    M32  $veda_nmc_add_w_violation  term[3] = !$veda_perm_nmc_ok   -> Milestone 5
    SURVIVED  M33  $veda_nmc_add_w_violation  term[4] = !$veda_perm_load_ok
    SURVIVED  M34  $veda_nmc_add_w_violation  term[5] = $veda_cow_write
    killed    M35  $veda_nmc_add_w_violation  term[6] = !$veda_perm_store_ok   -> RTL-12 permission enforcement
    SURVIVED  M36  $veda_nmc_add_w_violation  term[7] = !$veda_nmc_bounds_ok_w
    killed    M37  $veda_nmc_add_w_violation  term[8] = $veda_deref_nonresident)   -> ?
    killed    M38  $veda_nmc_add_d_violation  term[0] = $is_veda_nmc_add_d && (!$veda_rs1cap_tag   -> ?
    SURVIVED  M39  $veda_nmc_add_d_violation  term[1] = $veda_gen_stale
    SURVIVED  M40  $veda_nmc_add_d_violation  term[2] = $veda_sealed
    killed    M41  $veda_nmc_add_d_violation  term[3] = !$veda_perm_nmc_ok   -> Milestone 2 negative: permission
    SURVIVED  M42  $veda_nmc_add_d_violation  term[4] = !$veda_perm_load_ok
    killed    M43  $veda_nmc_add_d_violation  term[5] = $veda_cow_write   -> RTL-18 copy-on-write
    killed    M44  $veda_nmc_add_d_violation  term[6] = !$veda_perm_store_ok   -> RTL-12 permission enforcement
    SURVIVED  M45  $veda_nmc_add_d_violation  term[7] = !$veda_nmc_bounds_ok_d
    killed    M46  $veda_nmc_add_d_violation  term[8] = $veda_deref_nonresident)   -> ?
    killed    M47  $veda_atomic_violation  term[0] = $is_veda_atomic && (!$veda_rs1cap_tag   -> ?
    killed    M48  $veda_atomic_violation  term[1] = $veda_gen_stale   -> Milestone 8 positive
    SURVIVED  M49  $veda_atomic_violation  term[2] = $veda_sealed
    killed    M50  $veda_atomic_violation  term[3] = !$veda_perm_load_ok   -> RTL-12 permission enforcement
    SURVIVED  M51  $veda_atomic_violation  term[4] = $veda_cow_write
    killed    M52  $veda_atomic_violation  term[5] = !$veda_perm_store_ok   -> RTL-12 permission enforcement
    SURVIVED  M53  $veda_atomic_violation  term[6] = !$veda_nmc_bounds_ok_d
    killed    M54  $veda_atomic_violation  term[7] = $veda_deref_nonresident)   -> ?
    PRISTINE RESTORED: 82/82  identical=YES
    SURVIVORS: 22 / 54

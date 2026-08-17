#!/usr/bin/env bash
# R22/R9 -- THE COUPLING BETWEEN `cgetbase` AND TIER SELECTION, AS A CHECK RATHER
# THAN A PARAGRAPH.
#
# THE ADOPTED TIMING RULE (DESIGN_07 R22, second bullet):
#   "Tier selection must not depend on any value software cannot already read
#    architecturally."
#
# It holds TODAY, and it holds for a reason that is not permanent. Both tier
# tests are pure functions of values software itself chose at Populate time:
#   $veda_odt_tcm_hit    = intra_region && (local < TCM_ODT_ENTRIES)
#   $veda_capmem_tcm_hit = (real_addr >= TCM_SCRATCH_BASE) && (real_addr < ...)
# A principal holding a capability can read those values directly via cgetbase /
# cgetaddr / cgetobjectid, which are deliberately UNGATED. So the latency it
# observes tells it nothing it could not already read.
#
# THE MOMENT cgetbase IS GATED, THAT ARGUMENT DIES and tier selection becomes a
# channel that leaks placement to a principal no longer allowed to read it. R22
# predicted exactly this and said the narrowing must land "in the same commit".
#
# A comment cannot enforce "in the same commit". This can. It fails the build if
# the query family grows an authority gate while tier selection still reads Base
# or the local ID -- so whoever gates cgetbase is told, by a red suite, that they
# owe the other half.
#
# It is NOT a timing measurement and makes no performance claim. It is a
# structural invariant over the source, which is the only thing that can be
# checked without letting a throughput number decide a security question.
set -uo pipefail
cd "$(dirname "$0")"
TLV=rtl/veda_core.tlv
SAIL=/home/prabhu/veda-core-sail-riscv/model/extensions/Veda/veda_cap_insts.sail
rc=0

# (1) Is the query family still ungated? VEDA_CAPQUERY's execute clause must not
#     consult privilege, the ODA, purecap, or the compartment state.
q_start=$(grep -n 'function clause execute VEDA_CAPQUERY' "$SAIL" | cut -d: -f1)
if [ -z "$q_start" ]; then echo "FAIL: cannot find VEDA_CAPQUERY in $SAIL" >&2; exit 2; fi
q_body=$(awk -v s="$q_start" 'NR>=s && NR<=s+40' "$SAIL")
gated=$(echo "$q_body" | grep -cE 'cur_privilege|veda_oda_authorized|veda_mode|veda_pcc_object|veda_pcc_length')

# (2) Does tier selection still read a placement value?
tier_reads=$(grep -cE '\$veda_odt_tcm_hit *=.*veda_local|\$veda_capmem_tcm_hit *=.*veda_real_addr' "$TLV")

echo "cgetbase/cgetaddr family gated : $gated  (0 = ungated, the assumption the rule rests on)"
echo "tier selection reads placement : $tier_reads  (2 = both tiers key on software-chosen values)"

if [ "$gated" -ne 0 ] && [ "$tier_reads" -ne 0 ]; then
  echo >&2
  echo "FAIL: the capability-query family has been GATED while tier selection still" >&2
  echo "  keys on Base / local ID. The adopted timing rule is now VIOLATED: latency" >&2
  echo "  discloses placement to a principal that may no longer read it." >&2
  echo "  Narrow tier selection in this same commit, or record an explicit exception" >&2
  echo "  in DESIGN_07 R22 and update this check." >&2
  rc=1
fi

# (3) The other half of the invariant: the tier must stay history-free. A cache
#     buys throughput with access history, and history is the channel. Anything
#     with tags, fill-on-miss or a replacement policy is a cache whatever it is
#     called, so the words are banned outside comments.
# Substring match, NOT \b-bounded. The first draft used word boundaries and a
# mutant walked straight through it: `_` is a word character, so `\blru\b` does
# not match inside `$veda_odt_lru_victim`, which is exactly how such a signal
# would be named here. The check passed on a design that had just grown a
# replacement policy. Found by mutating the check rather than trusting it.
hw_repl=$(grep -vE '^\s*//' "$TLV" | grep -ciE 'lru|victim|refill|fill_on_miss|way_select|tag_array')
echo "hardware replacement policy    : $hw_repl  (0 = the tier is a static decode, not a cache)"
if [ "$hw_repl" -ne 0 ]; then
  echo >&2
  echo "FAIL: a replacement policy has appeared in the RTL. Tier hit/miss would then" >&2
  echo "  depend on ACCESS HISTORY rather than on software-declared placement, which" >&2
  echo "  is precisely the covert channel the cache-less pillar exists to remove." >&2
  rc=1
fi

[ "$rc" -eq 0 ] && echo "PASS: the timing rule's premise still holds on both halves."
exit $rc

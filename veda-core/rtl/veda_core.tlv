\m4_TLV_version 1d: tl-x.org
\SV
   // ═══════════════════════════════════════════════════════════════════
   //  Veda-Core RTL — Phase 1 Milestone 1 (Capability Register File,
   //  Object-Bind, OCL.D/OCS.D). Seeded from the already-verified RVA23
   //  base core (rtl/rv64i_core.tlv, 51/51 real ACT4 RV64I conformance),
   //  which is untouched below except for the new Veda-Core additions --
   //  see veda-core/rtl/MILESTONE_PLAN.md for the full scope decision and
   //  the three real architectural calls this milestone required (the ODT
   //  is memory-mapped, not a register array; violations suppress writes
   //  rather than trap, since this core has no privileged/trap
   //  infrastructure at all yet; the generation-staleness check is
   //  included from the start rather than reproducing a known, already-
   //  fixed Sail V-A gap).
   //
   //  All 50 RV64I encodings implemented (unchanged from the base core):
   //  the 38 RV32I-equivalent instructions (incl. FENCE and, as of RTL
   //  Milestone 23, ECALL; EBREAK still excl./deferred) plus the 12
   //  RV64-only *W encodings.
   //
   //  Waveform signals to watch (add in Makerchip waveform panel):
   //    |cpu @0  $pc, $instr, $opcode, $funct3, $funct7, $reg_write,
   //             $alu_result, $branch_taken, $pc_src, $wr_data,
   //             $is_load, $is_store, $mem_addr
   //    |cpu @0  $is_veda_bind, $is_veda_ocl, $is_veda_ocs, $veda_violation
   //    /xreg[1..31] $val   — register file values
   //    /dmem[0..63] $val   — data memory (64 doublewords, byte addr 0-511)
   //    /vreg[0..15] $tag, $base, $length, $offset, $perms, $otype — CRF
   // ═══════════════════════════════════════════════════════════════════
   m4_makerchip_module

   // ───────────────────────────────────────────────────────────────────
   //  VEDA-CORE: Object Descriptor Table — memory-mapped, not a register
   //  array (VEDA_CORE_SPEC.md Section 5.1's own design intent, made
   //  concrete for the first time in real RTL — see MILESTONE_PLAN.md
   //  item 1 for the full reasoning). Same byte-addressable-array
   //  convention already used for elfmem/dmem below, not a new idiom.
   //
   //  RTL-6 CORRECTION. Everything this header used to say about the entry
   //  layout was three increments stale and actively dangerous: it claimed
   //  256 entries of 16 bytes, owner_hart at "+10", and "88 bits used of
   //  128 available". The real values are 768 entries of 32 bytes with
   //  owner_hart at +18, and the bytes it advertised as spare (+11..+13)
   //  are Length[39:24] and Perms. A reader hunting for spare space
   //  top-down would have written into every object's bounds and
   //  permissions, silently. Deleted rather than patched, because the
   //  authoritative layout belongs in ONE place and duplicating it here is
   //  how it went stale in the first place.
   //
   //  The layout of record is the byte map at the Populate write
   //  enumeration (search ODT_OFF_RESIDENT), with the sizing arithmetic at
   //  ODT_ENTRY_BYTES and the entry count at ODT_ENTRIES below.
   // ───────────────────────────────────────────────────────────────────
   localparam bit [31:0] ODT_BASE = 32'h9000_0000;
   // RTL-4 (DESIGN_08, mirrors Sail 1fef6e3d): 256 -> 512. The table is now
   // PARTITIONED into region windows of ODT_REGION_ENTRIES each, exactly as
   // Sail partitions its own flat modeled array (veda_regs.sail:457-467:
   // 8 x 2^20 = 2^23 "exactly, so existing region-0 objects keep their old
   // indices and the whole prior corpus is unaffected").
   //
   // GROW, do not shrink -- a deliberate decision with real evidence behind
   // it, not a convenience. Holding the total at 256 and shrinking the
   // per-region window to 128 would narrow the index to local[6:0], which
   // leaves bit [7] checked by NEITHER the index NOR the id_hi tag ([43:8]).
   // The corpus really does contain the colliding pairs (2,130) (3,131)
   // (5,133) (6,134) (72,200) (73,201) (82,210) -- a Bind of Object_ID 2
   // would silently return Object_ID 130's descriptor. No test binds both
   // members of any pair, so the entire suite would still report PASS: a
   // live confused-deputy bug with ZERO test signal. odt_mem[] is a
   // simulation byte array, not silicon; 8 KiB -> 16 KiB costs no area, no
   // timing, and no memory map (elfmem ends 0x8007_FFFF, TCM scratch starts
   // 0xA000_0000, so 0x9000_2000..0x9000_5FFF is unallocated).
   //
   // THREE windows (768), not two. A non-resident region provably never
   // reaches the array, so on pure architectural grounds region 2 needs no
   // storage -- but giving it a real window makes the REGION_FAULT test
   // strictly sharper, which is why it gets one. With region 2's object
   // genuinely seeded and valid (mirroring Sail, veda_regs.sail:685-693), a
   // MISSING residency gate makes the bind SUCCEED, so the test fails
   // unmistakably. Without the seed, a missing gate would still trap -- with
   // cause 0x05, object-not-found -- and a test that only asserted "it
   // trapped" would pass over the hole. The fixture is chosen so the failure
   // mode is loud, not so the table is minimal.
   localparam int ODT_ENTRIES = 768;
   // Entries per region window. Kept at 256 so region 0's index stays
   // local[7:0] == Object_ID[7:0] and its byte address is byte-for-byte what
   // the pre-RTL-4 formula produced -- the whole regression argument. It also
   // keeps the index bits [7:0] and the id_hi tag bits [43:8] exactly
   // complementary and jointly total over all 44 bits (proof at the
   // $veda_odt_id_hi comment below), so the tag question stays closed.
   localparam int ODT_REGION_ENTRIES = 256;
   // Region Table size -- mirrors Sail's VEDA_REGION_MODELED (veda_regs.sail
   // :466). A region at or above this is OUT OF WINDOW: not modeled, and
   // therefore not resident (veda_regs.sail:503). Only regions that are both
   // resident and actually bound need ODT storage, and Sail seeds exactly
   // two resident regions, so 8 RT entries over 2 ODT windows covers every
   // reachable modeled state -- 8 windows would be dead storage.
   localparam int RT_ENTRIES = 8;
   // RTL-3: 32 bytes. This is arithmetic, not preference -- the respec's
   // fields need Base56+Length40+Perms16+gen24+valid1+owner8+retired1+
   // id_hi36 = 182 bits even bit-packed, well over the 128 a 16-byte entry
   // holds; dropping id_hi entirely still needs 146. Every field is
   // byte-aligned (26 B used, 6 spare after RTL-6) so the hand-written
   // enumerations of this layout stay mechanically diffable.
   localparam int ODT_ENTRY_BYTES = 32;
   // ═══════════════════════════════════════════════════════════════════
   //  RTL-6 (DESIGN_02 Phase 2, increment 1): the per-OBJECT residency
   //  byte, mirroring Sail's odt_entry.resident (veda_types.sail:301).
   //
   //  WHY THIS ONE FIELD GETS A NAMED CONSTANT WHEN NO OTHER DOES, which
   //  is a deliberate departure from the surrounding literal-offset style
   //  and is recorded here rather than left to look like an accident.
   //  The layout is hand-written in SIX places with no shared macro: the
   //  five reset seeds below, the Bind-side read, the dereference-side
   //  read, the Populate/Populate-Fast write, the Destroy write, and the
   //  owner-claim write. (The comment at the write enumeration says
   //  "three copies" -- it undercounts; that has been corrected there.)
   //  A field added at +25 in five of six sites and +26 in the sixth
   //  compiles clean, elaborates clean, simulates, and produces a
   //  permanently non-resident or permanently resident object with no
   //  diagnostic anywhere. That is precisely RTL-3's Mutation W hazard
   //  class, and the existing mitigation for it -- ODT_ENTRY_BYTES
   //  replacing the bare literal 32 in both stride computations -- is the
   //  direct precedent for doing the same to a field offset.
   //
   //  The 1=resident polarity is also load-bearing, not cosmetic: odt_mem
   //  is pre-zeroed at reset, so an omitted seed write reads 0. With
   //  1=resident that omission traps every Bind in the corpus, which is
   //  loud and unmissable. With 0=resident the identical omission would
   //  make every never-written slot read resident and the gate a silent
   //  no-op. Matches valid (+17) and retired (+19), whose set-state is 1.
   localparam int ODT_OFF_RESIDENT = 25;
   //  RTL-17: owner_domain, 20 bits at +26..+28 -- WHO MAY BIND THIS OBJECT.
   //
   //  A NAMED constant for the same reason resident got one: this layout is
   //  hand-written in six places, and a field placed at +26 in five of them and
   //  +27 in the sixth compiles clean and produces permanently wrong policy.
   //
   //  POLICY, NOT IDENTITY. Base, Length and generation say what an object IS,
   //  and changing them makes it a different object -- which is why only
   //  Populate and Destroy touch them and both bump the generation, killing
   //  every outstanding capability. owner_domain says how it may be USED, so
   //  changing it must NOT kill capabilities. That distinction is the whole
   //  reason veda.odt.set.domain exists.
   localparam int ODT_OFF_OWNER_DOMAIN = 26;
   //  RTL-18: cow, 1 bit at +29 -- DESIGN_02 Mechanism 2, copy-on-write.
   //  The SECOND policy field, and it obeys the same contract as the first:
   //  setting it must not bump the generation, because marking an object
   //  copy-on-write is not making it a different object. If it bumped, fork()
   //  would kill every capability held by both parent and child at the exact
   //  moment it tried to share them.
   //
   //  No explicit seed write is needed, unlike resident and owner_domain: the
   //  reset pre-zero IS the correct value here (0 = not copy-on-write). Stated
   //  so the absence is deliberate -- resident documented the opposite trap,
   //  where 0 was the WRONG default and every seed had to set it by hand.
   localparam int ODT_OFF_COW = 29;
   //  "any domain may bind this" -- the value every object is created with, so
   //  the field changes nothing until software deliberately narrows an object.
   //  Note the reset pre-zero is NOT this value: zero is domain 0, a REAL
   //  domain, so every seeded object must set this EXPLICITLY or it silently
   //  becomes domain-0-only. Exactly the trap resident documented at its own
   //  declaration.
   localparam bit [19:0] VEDA_DOMAIN_ANY = 20'hFFFFF;
   // MILESTONE 24 (TCM_FAST_PATH_DESIGN.md): the first real DRAM-latency
   // number this core has ever modeled -- every prior milestone's own
   // cycle counts assumed odt_mem[]/elfmem[] access is always 1 cycle,
   // which CRF_ARCHITECTURE_ALIGNMENT_VERDICT.md's own addendum found is
   // only true because no latency was ever modeled, not because it's
   // architecturally free. Swept {0,10,50} in verification
   // (DRAM_TCM_LATENCY_STUDY.md's own real, DDR4-grounded range).
   //
   // Committed default is 0, NOT a nonzero value -- a real, deliberate
   // correction found empirically this milestone, not assumed: every one
   // of the 46 pre-existing RTL smoke tests uses Object-Bind (often
   // several times, for compartment-entry setup), sharing ONE compiled
   // veda_core.sv per run_veda_smoke_test.sh invocation, against fixed
   // repeat(N) testbench cycle budgets as tight as repeat(12) (confirmed
   // by direct grep before deciding this, e.g. tb_veda_smoke.sv:23) --
   // shipping a nonzero default here would silently break most of that
   // corpus via budget exhaustion, not any real logic defect. The stall
   // mechanism itself is fully built and verified working correctly at a
   // nonzero value via a dedicated new test with a properly-sized budget
   // (veda_smoke_m24_latency.S) -- widening the pre-existing 46 tests'
   // own budgets so a nonzero default is safe to ship globally is real,
   // separate, mechanical follow-up work, named honestly as not done in
   // this milestone, not silently assumed away.
   localparam int DRAM_EXTRA_CYCLES = 0;
   // MILESTONE 24 Stage 2 (TCM_FAST_PATH_DESIGN.md Part B): a fixed, LOW
   // Object_ID range that never pays the DRAM-tier stall on Bind/Bind-
   // NoTrap/Rebind. Real, deliberate simplification: odt_mem[] itself
   // does NOT get physically split into a separate array -- the "TCM"
   // property here is purely about latency classification (Object_ID <
   // TCM_ODT_ENTRIES never stalls), not physical placement, since
   // odt_mem[] is already a same-cycle-combinational SystemVerilog array
   // with no memory-technology distinction in simulation. 32 entries =
   // 512 bytes of the real, existing 16-byte ODT_ENTRY_BYTES layout --
   // comfortably inside real Cortex-M/R TCM budgets (4KB-64KB) already
   // cited in DRAM_TCM_LATENCY_STUDY.md. Placement is STATIC and
   // software-declared (whichever Object_ID a program chooses to
   // ODT-Populate below this threshold), never automatically promoted
   // based on observed access frequency -- the real, cited security
   // constraint from TCM_FAST_PATH_DESIGN.md Section 1 (GhostRider,
   // ASPLOS 2015): placement must be independent of secret-correlated
   // runtime data, which a fixed, compile-time-chosen range satisfies by
   // construction. Per-hart-private: safe as a single, unpartitioned
   // range only because MHARTID is fixed at 0 below -- if/when a real
   // multi-hart Veda-Core is ever built, this must be revisited (per-hart
   // banks, or a real static time-partitioned arbiter per Wang/
   // Ferraiuolo/Suh HPCA 2014) before this same code can be trusted for
   // the same security property -- written down, not silently assumed.
   localparam int TCM_ODT_ENTRIES = 32;
   // RTL MILESTONE 12: this single-core RTL's own fixed hart identity --
   // no real MHARTID CSR/concept existed anywhere in this file before
   // now (a genuine new architectural constant, not a repurposed one).
   // Fixed at 0, the real, standard RISC-V single-hart convention
   // (mirrors Sail's own veda_test_sail.json single-hart config, which
   // also fixes mhartid=0) -- extendable to a real per-instance value if
   // this core is ever replicated into an actual multi-hart system
   // (NEXT_STEPS_ROADMAP.md §2.7's own still-open, explicitly deferred
   // item), not attempted here.
   localparam bit [7:0] MHARTID = 8'h00;
   // Sentinel for "no live owner yet" -- matches Sail's own
   // VEDA_OWNER_UNOWNED (veda_types.sail) byte-for-byte, not re-chosen.
   localparam bit [7:0] VEDA_OWNER_UNOWNED = 8'hFF;
   // RTL-9 (R11(b), DESIGN_07 Tier H): "this belongs to no object". Out of
   // band by construction -- its region field (bits 43:24) is all ones, and
   // no region table window can resolve 20'hFFFFF, so it cannot collide
   // with a real Object_ID. Same discipline as Sail's VEDA_REGION_NONE.
   localparam bit [43:0] VEDA_OBJECT_NONE = 44'hFFFFFFFFFFF;
   logic [7:0] odt_mem [ODT_BASE : ODT_BASE + (ODT_ENTRIES * ODT_ENTRY_BYTES) - 1];
   // ───────────────────────────────────────────────────────────────────
   //  RTL-4: the Region Table (RT). DESIGN_08's outer level -- flat,
   //  always-resident, one entry per modeled protection domain. Mirrors
   //  Sail's `register veda_region_table : vector(8, region_entry)`
   //  (veda_regs.sail:470) and the region_entry struct's field set
   //  (veda_types.sail:318-322), as five parallel arrays because this file
   //  has no struct idiom (odt_mem is a flat byte array for the same reason).
   //
   //  UNIT CONVENTION, and it is load-bearing: rt_odt_base is an ENTRY
   //  INDEX, not a byte address. Sail computes `idx = unsigned(
   //  veda_odt_base_of(region)) + lu` (veda_regs.sail:519) -- the base is
   //  added to `local` in ENTRY units and the ODT_ENTRY_BYTES stride is
   //  applied exactly ONCE, afterwards. Storing a byte address here instead
   //  would shift every non-zero-base region by 32x. That produces no
   //  compile error, no warning, and no failure on the entire region-0
   //  corpus -- precisely the silent-truncation class that cost RTL-3 four
   //  bugs, so the convention is stated here rather than inferred.
   //
   //  rt_backing and rt_generation are declared for field parity with the
   //  Sail struct and are genuinely UNUSED this increment -- said out loud
   //  rather than omitted, because veda_types.sail:313-317 and DESIGN_08
   //  both record that a stale or corrupt region_odt_base has region-WIDE
   //  blast radius (strictly larger than any single ODT entry's), which is
   //  what those two fields exist to bound later.
   logic        rt_valid      [0:RT_ENTRIES-1];
   logic        rt_resident   [0:RT_ENTRIES-1];
   logic [31:0] rt_odt_base   [0:RT_ENTRIES-1];  // ENTRY index, NOT bytes
   logic [55:0] rt_backing    [0:RT_ENTRIES-1];  // unused this increment
   logic [23:0] rt_generation [0:RT_ENTRIES-1];  // unused this increment
   initial begin
      // RTL-4: seed the RT FIRST, before any object seed. Ordering is real,
      // not cosmetic: a cross-region object seed resolves its byte offset
      // through the RT, the identical reason Sail seeds its region table
      // before its objects (veda_regs.sail:555-558).
      for (int veda_r = 0; veda_r < RT_ENTRIES; veda_r = veda_r + 1) begin
         rt_valid[veda_r]      = 1'b0;
         rt_resident[veda_r]   = 1'b0;
         rt_odt_base[veda_r]   = 32'b0;
         rt_backing[veda_r]    = 56'b0;
         rt_generation[veda_r] = 24'b0;
      end
      // Region 0 -- the running domain. Base = entry 0, so every
      // pre-DESIGN_08 object (the entire 88-Object_ID corpus, all of which
      // have Object_ID[43:24] == 0) keeps its exact prior slot.
      rt_valid[0] = 1'b1;  rt_resident[0] = 1'b1;  rt_odt_base[0] = 32'd0;
      // Region 1 -- a SECOND resident domain, base = entry 256. Exists to
      // prove global uniqueness: {region=1,local=k} is a different object
      // than {region=0,local=k}. Mirrors veda_regs.sail:567.
      rt_valid[1] = 1'b1;  rt_resident[1] = 1'b1;  rt_odt_base[1] = 32'd256;
      // Region 2 -- a NON-RESIDENT domain (its ODT is paged out). The
      // fixture for the explicit REGION_FAULT. Mirrors veda_regs.sail:568,
      // including giving it a REAL base: Sail's own odt_write resolves seed
      // (B) through this entry, so the object genuinely exists and is valid
      // even though its domain is not resident. That is the whole point --
      // the gate must fire BEFORE and INSTEAD OF a lookup that would
      // otherwise have succeeded.
      rt_valid[2] = 1'b1;  rt_resident[2] = 1'b0;  rt_odt_base[2] = 32'd512;
      // RTL-5 (R10): region 3 is the rt_valid FAIL-CLOSED fixture --
      // deliberately the contradictory state {rt_valid = 0, resident = 1}:
      // a slot that was never configured but whose resident bit reads true
      // (garbage, or a half-torn write). The residency check must consult
      // rt_valid FIRST and refuse, so a crossing into region 3 REGION_FAULTs
      // even though its resident bit says otherwise. Without a slot in
      // exactly this state, dropping the rt_valid conjunct would be an
      // unobservable mutation -- rt_valid is otherwise write-only in this
      // file, so nothing else would notice its absence.
      rt_valid[3] = 1'b0;  rt_resident[3] = 1'b1;  rt_odt_base[3] = 32'd0;
      // Regions 4..7 stay rt_valid = 0 and non-resident; regions >=
      // RT_ENTRIES are out of window. All REGION_FAULT.
      // Milestone 1 test scaffold, explicitly temporary -- mirrors Sail
      // Milestone V-A's own veda_test_seed_odt() field-for-field, same
      // real reason: no ODT-Populate instruction exists yet in RTL
      // (deferred to a later RTL milestone, matching the Sail V-A -> V-B
      // sequencing already used and documented in MILESTONE_PLAN.md).
      for (int veda_i = 0; veda_i < (ODT_ENTRIES * ODT_ENTRY_BYTES); veda_i = veda_i + 1)
         odt_mem[ODT_BASE + veda_i] = 8'h00;
      // Object_ID=1 -> region 0, local 1 -> entry (rt_odt_base[0]=0)+1 = 1
      // -> byte offset 1*ODT_ENTRY_BYTES = 1*32 = 32 from ODT_BASE. (The
      // "1*16" in this comment before RTL-4 was stale from RTL-2; the
      // literal 32 below was already correct, the derivation was not.)
      // Base=0x80010000
      // (inside the same ELF-loaded RAM region ACT4/elfmem uses),
      // Length=0x40, Perms=0x100C (Permit_Load|Permit_Store|
      // Permit_NMC_Compute -- the last bit isn't consumed by anything
      // built this milestone, set now so it doesn't need revisiting),
      // generation=0, valid=1.
      {odt_mem[ODT_BASE+32+3], odt_mem[ODT_BASE+32+2], odt_mem[ODT_BASE+32+1], odt_mem[ODT_BASE+32+0]} = 32'h8001_0000;
      {odt_mem[ODT_BASE+32+8], odt_mem[ODT_BASE+32+7]} = 16'h0040;
      {odt_mem[ODT_BASE+32+13], odt_mem[ODT_BASE+32+12]} = 16'h100C;
      odt_mem[ODT_BASE+32+14] = 8'h00;
      odt_mem[ODT_BASE+32+17] = 8'h01;
      // Milestone 12 addition: reset-seeded objects start genuinely
      // unowned (matches Sail's own veda_test_seed_odt() field-for-
      // field), not owned by hart 0 by default -- Bind's own real claim
      // logic (below) is what's actually under test, not a fixture that
      // pre-empts it.
      odt_mem[ODT_BASE+32+18] = VEDA_OWNER_UNOWNED;
      // RTL-6: resident=1. Every seeded object needs this EXPLICITLY --
      // the pre-zero above leaves it 0, and 0 is non-resident, so an
      // omission here traps every Bind of this fixture (23 .S files) with
      // RESIDENCY_FAULT. Loud by design, per the polarity argument at the
      // ODT_OFF_RESIDENT declaration.
      odt_mem[ODT_BASE+32+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+32+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+32+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+32+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      // Milestone 2 addition: a second seeded object, deliberately
      // *without* Permit_NMC_Compute (Perms = 0x000C, Load+Store only),
      // so a real negative-control test can confirm NMC_ADD's own
      // permission gate actually fires -- the identical real reason and
      // identical field values already used for this exact purpose in
      // the Sail test scaffold (veda_regs.sail's own Object_ID=2 entry).
      // Object_ID=2 -> region 0, local 2 -> entry 0+2 -> byte offset
      // 2*32 = 64 from ODT_BASE (the "2*16=32" here was likewise stale).
      {odt_mem[ODT_BASE+64+3], odt_mem[ODT_BASE+64+2], odt_mem[ODT_BASE+64+1], odt_mem[ODT_BASE+64+0]} = 32'h8001_0100;
      {odt_mem[ODT_BASE+64+8], odt_mem[ODT_BASE+64+7]} = 16'h0040;
      {odt_mem[ODT_BASE+64+13], odt_mem[ODT_BASE+64+12]} = 16'h000C;
      odt_mem[ODT_BASE+64+14] = 8'h00;
      odt_mem[ODT_BASE+64+17] = 8'h01;
      odt_mem[ODT_BASE+64+18] = VEDA_OWNER_UNOWNED;
      odt_mem[ODT_BASE+64+ODT_OFF_RESIDENT] = 8'h01;   // RTL-6
      {odt_mem[ODT_BASE+64+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+64+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+64+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      // Milestone 12 addition: Object_ID=60 -> region 0, local 60 -> entry
      // 0+60 -> byte offset 60*32 = 1920 from ODT_BASE ("60*16=960" was the
      // third stale RTL-2 derivation; 1920 below was already right), a
      // THIRD seeded object, pre-claimed by owner_hart=0x63 (99 decimal)
      // -- a stand-in "other hart," since this single-core RTL testbench
      // has no real second hart to own anything with (mirrors Sail's own
      // identical Milestone 12 fixture, veda_regs.sail's Object_ID=5
      // entry, same real reason: direct ODT-state injection is the only
      // way this project's own single-hart test environments can prove
      // a wrong-owner outcome at all). Object_ID=60 chosen specifically
      // because it's the one value genuinely unused anywhere else in
      // this project's own existing RTL test corpus (confirmed by
      // grepping every veda_smoke_*.S file before picking it -- Object_
      // ID=3 was tried first and found to collide with Milestone 4's own
      // "never seeded at reset" fresh-mint precondition, a real bug
      // caught by that pre-existing test, not a hypothetical one).
      // Base=0x80010200, Length=0x40, Perms=0x000C (Load+Store), so this
      // fixture is also usable as an ordinary-looking object in every
      // respect except ownership.
      {odt_mem[ODT_BASE+1920+3], odt_mem[ODT_BASE+1920+2], odt_mem[ODT_BASE+1920+1], odt_mem[ODT_BASE+1920+0]} = 32'h8001_0200;
      {odt_mem[ODT_BASE+1920+8], odt_mem[ODT_BASE+1920+7]} = 16'h0040;
      {odt_mem[ODT_BASE+1920+13], odt_mem[ODT_BASE+1920+12]} = 16'h000C;
      odt_mem[ODT_BASE+1920+14] = 8'h00;
      odt_mem[ODT_BASE+1920+17] = 8'h01;
      odt_mem[ODT_BASE+1920+18] = 8'h63;
      // RTL-6: this fixture MUST stay resident. Its whole job is to prove
      // Bind reports OWNER_VIOLATION (0x06) for a live object owned
      // elsewhere. Seeded non-resident it would report RESIDENCY_FAULT
      // (0x0A) instead -- the residency gate outranks the mode match --
      // and m12/m12_neg would fail on a cause they never meant to test.
      // Sail carries the identical note at veda_regs.sail's own seed.
      odt_mem[ODT_BASE+1920+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+1920+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+1920+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+1920+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      // ────────────────────────────────────────────────────────────────
      //  RTL-4 (DESIGN_08): two CROSS-REGION seeds, mirroring Sail's own
      //  two at veda_regs.sail:665-693 field-for-field.
      //
      //  (A) region=1, local=1 -> Object_ID = (1<<24)|1 = 16777217
      //      = 0x0100_0001. Entry = rt_odt_base[1] + local[7:0] = 256+1
      //      = 257 -> byte offset 257*32 = 8224. Deliberately given a
      //      DIFFERENT Base (0x8002_0000) from region-0 local-1 (Object_ID
      //      1, Base 0x8001_0000 above) so a test can prove GLOBAL
      //      UNIQUENESS: {region=1,local=1} and {region=0,local=1} are
      //      different objects, not two names for one.
      //
      //  CRITICAL, and unlike all three seeds above: this one MUST write
      //  the id_hi bytes +20..+24 explicitly. The region-0 seeds have
      //  id_hi = Object_ID[43:8] = 0 and get it free from the array
      //  pre-zero; this one's id_hi is 0x0001_0000. Omit the write and the
      //  stored tag (0) will not match the expected tag, so the seed reads
      //  as OBJECT_NOT_FOUND -- valid, silent, and indistinguishable from
      //  "regions do not work". Byte shape copied from the real populate
      //  write path below: +20 <= id[15:8], +21 <= id[23:16],
      //  +22 <= id[31:24], +23 <= id[39:32], +24 <= {4'b0, id[43:40]}.
      {odt_mem[ODT_BASE+8224+3], odt_mem[ODT_BASE+8224+2], odt_mem[ODT_BASE+8224+1], odt_mem[ODT_BASE+8224+0]} = 32'h8002_0000;
      {odt_mem[ODT_BASE+8224+8], odt_mem[ODT_BASE+8224+7]} = 16'h0008;
      {odt_mem[ODT_BASE+8224+13], odt_mem[ODT_BASE+8224+12]} = 16'h0004;  // Permit_Load only, matching Sail
      odt_mem[ODT_BASE+8224+14] = 8'h00;
      odt_mem[ODT_BASE+8224+17] = 8'h01;
      odt_mem[ODT_BASE+8224+18] = VEDA_OWNER_UNOWNED;
      odt_mem[ODT_BASE+8224+ODT_OFF_RESIDENT] = 8'h01;   // RTL-6
      {odt_mem[ODT_BASE+8224+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+8224+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+8224+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      odt_mem[ODT_BASE+8224+20] = 8'h00;  // Object_ID[15:8]
      odt_mem[ODT_BASE+8224+21] = 8'h00;  // Object_ID[23:16]
      odt_mem[ODT_BASE+8224+22] = 8'h01;  // Object_ID[31:24]  <- the region
      odt_mem[ODT_BASE+8224+23] = 8'h00;  // Object_ID[39:32]
      odt_mem[ODT_BASE+8224+24] = 8'h00;  // {4'b0, Object_ID[43:40]}
      //  (B) region=2, local=7 -> Object_ID = (2<<24)|7 = 33554439
      //      = 0x0200_0007. Entry = rt_odt_base[2] + 7 = 512+7 = 519 ->
      //      byte offset 519*32 = 16608. Region 2 is NON-RESIDENT, so this
      //      entry is a valid object in a paged-out domain: any Object-Bind
      //      of it must raise an explicit REGION_FAULT rather than resolve.
      //      Seeding it VALID is what makes that test load-bearing -- with
      //      a missing residency gate the bind would succeed outright, not
      //      merely report a different cause.
      {odt_mem[ODT_BASE+16608+3], odt_mem[ODT_BASE+16608+2], odt_mem[ODT_BASE+16608+1], odt_mem[ODT_BASE+16608+0]} = 32'h8003_0000;
      {odt_mem[ODT_BASE+16608+8], odt_mem[ODT_BASE+16608+7]} = 16'h0008;
      {odt_mem[ODT_BASE+16608+13], odt_mem[ODT_BASE+16608+12]} = 16'h0004;  // Permit_Load only, matching Sail
      odt_mem[ODT_BASE+16608+14] = 8'h00;
      odt_mem[ODT_BASE+16608+17] = 8'h01;
      odt_mem[ODT_BASE+16608+18] = VEDA_OWNER_UNOWNED;
      // RTL-6: resident=1, and that is the point. This object lives in a
      // NON-RESIDENT REGION. Region residency and object residency are
      // different questions with different causes (0x09 vs 0x0A), and the
      // region one wins. Seeding this object non-resident would make the
      // test pass for the wrong reason and stop proving the region gate
      // fires at all -- tb_veda_smoke_region_fault_neg's expected mtval
      // would silently move from 0x69 to 0x6A.
      odt_mem[ODT_BASE+16608+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+16608+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+16608+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+16608+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      odt_mem[ODT_BASE+16608+20] = 8'h00;  // Object_ID[15:8]
      odt_mem[ODT_BASE+16608+21] = 8'h00;  // Object_ID[23:16]
      odt_mem[ODT_BASE+16608+22] = 8'h02;  // Object_ID[31:24]  <- the region
      odt_mem[ODT_BASE+16608+23] = 8'h00;  // Object_ID[39:32]
      odt_mem[ODT_BASE+16608+24] = 8'h00;  // {4'b0, Object_ID[43:40]}
      // ────────────────────────────────────────────────────────────────
      //  RTL-6 (DESIGN_02 Phase 2, increment 1): the RESIDENCY_FAULT
      //  fixture -- Object_ID=104 -> region 0, local 104 -> entry 104 ->
      //  byte offset 104*32 = 3328. VALID but NOT RESIDENT, in a RESIDENT
      //  region, so the object gate (0x0A) is the only thing that can
      //  fire on it.
      //
      //  WHY A SEED AND NOT A RUNTIME SEQUENCE, stated plainly because it
      //  is a real limitation and not a convenience. Once page-out exists
      //  (RTL-6c) a program CAN reach {valid, non-resident} at runtime --
      //  but page-out also BUMPS generation, by design, so any capability
      //  held across it fails the generation check (0x02) before residency
      //  is ever consulted. That is the correct architecture and it is
      //  exactly why the dereference-side residency term needs a fixture
      //  the architecture itself cannot produce. Sail records the same
      //  limitation against its own equivalent seed.
      //
      //  CONSEQUENCE, and it must not be forgotten: this object is NOT a
      //  legitimate page-in input. Its non-residency was injected, not
      //  produced by a page-out, so nothing was ever evicted and no
      //  generation was ever spent. Paging it in would install a Base for
      //  contents that were never written anywhere.
      //
      //  Object_ID=104 chosen from the free region-0 low bytes. Collision
      //  in this design is by SLOT (rt_odt_base[region] + Object_ID[7:0]),
      //  NOT by Object_ID, so the check that matters is the low byte:
      //  the corpus occupies 88 distinct region-0 low bytes and 103..109
      //  are unoccupied. Sail's own equivalent fixtures (600/611/614) were
      //  deliberately NOT copied here -- their low bytes are 88/99/102,
      //  all three taken by existing RTL tests. They would still have
      //  worked, but only because the 36-bit id_hi tag makes a same-slot
      //  different-Object_ID lookup read as not-found. Resting three
      //  fixtures on that single check is not a dependency worth taking.
      {odt_mem[ODT_BASE+3328+3], odt_mem[ODT_BASE+3328+2], odt_mem[ODT_BASE+3328+1], odt_mem[ODT_BASE+3328+0]} = 32'h8001_0300;
      {odt_mem[ODT_BASE+3328+8], odt_mem[ODT_BASE+3328+7]} = 16'h0040;
      {odt_mem[ODT_BASE+3328+13], odt_mem[ODT_BASE+3328+12]} = 16'h100C;  // Load+Store+NMC
      odt_mem[ODT_BASE+3328+14] = 8'h00;                    // generation 0
      odt_mem[ODT_BASE+3328+17] = 8'h01;                    // valid   = 1
      odt_mem[ODT_BASE+3328+18] = VEDA_OWNER_UNOWNED;
      // resident deliberately LEFT AT THE PRE-ZERO 0. Written explicitly
      // anyway: an omitted write and an intentional zero are the same
      // bytes but not the same claim, and the next reader deserves to see
      // which one this is.
      odt_mem[ODT_BASE+3328+ODT_OFF_RESIDENT] = 8'h00;      // NOT resident
      {odt_mem[ODT_BASE+3328+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+3328+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+3328+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      //  RTL-6 ORDERING FIXTURE A -- Object_ID=105 -> entry 105 -> byte
      //  offset 3360. Valid, NOT resident, and owned by hart 0x63.
      //
      //  Its only job is to pin 0x0A ABOVE 0x06. Sail's residency gate
      //  precedes the mode match that produces the owner verdict, so a
      //  paged-out object owned by another hart must report RESIDENCY, not
      //  WRONG_OWNER. Without this fixture the cause-arm could be placed
      //  after $veda_bind_trap and nothing in the suite would notice --
      //  every other residency fixture is unowned, so the two orderings
      //  agree everywhere except here.
      //
      //  The distinction is not academic. WRONG_OWNER tells the handler to
      //  give up; RESIDENCY tells it to page the object in and retry. An
      //  object that is both is serviceable, and reporting the permanent
      //  condition when a recoverable one is also true loses the recovery.
      {odt_mem[ODT_BASE+3360+3], odt_mem[ODT_BASE+3360+2], odt_mem[ODT_BASE+3360+1], odt_mem[ODT_BASE+3360+0]} = 32'h8001_0400;
      {odt_mem[ODT_BASE+3360+8], odt_mem[ODT_BASE+3360+7]} = 16'h0040;
      {odt_mem[ODT_BASE+3360+13], odt_mem[ODT_BASE+3360+12]} = 16'h000C;
      odt_mem[ODT_BASE+3360+14] = 8'h00;
      odt_mem[ODT_BASE+3360+17] = 8'h01;                    // valid
      odt_mem[ODT_BASE+3360+18] = 8'h63;                    // owned by hart 99
      odt_mem[ODT_BASE+3360+ODT_OFF_RESIDENT] = 8'h00;      // NOT resident
      {odt_mem[ODT_BASE+3360+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+3360+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+3360+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      //  RTL-6 ORDERING FIXTURE B -- Object_ID = (2<<24)|8 = 33554440,
      //  region 2, local 8 -> entry rt_odt_base[2] + 8 = 512+8 = 520 ->
      //  byte offset 520*32 = 16640. Valid, NOT resident, in region 2,
      //  which is itself NOT resident.
      //
      //  Its only job is to pin 0x09 ABOVE 0x0A -- both faults true at
      //  once, and the REGION one must win. The existing region-fault
      //  fixture cannot prove this: it is seeded resident, so 0x0A is
      //  false for it and either ordering yields 0x09.
      //
      //  The reason region wins is not precedence-by-convention. If the
      //  domain's table is paged out you have no business having read the
      //  object's entry at all -- the residency byte the RTL would consult
      //  is a byte it cannot trust. Reporting 0x0A here would answer a
      //  question that was never legitimately asked, and would send the
      //  handler to page in one object when what is missing is the entire
      //  table that object is described by.
      {odt_mem[ODT_BASE+16640+3], odt_mem[ODT_BASE+16640+2], odt_mem[ODT_BASE+16640+1], odt_mem[ODT_BASE+16640+0]} = 32'h8003_0100;
      {odt_mem[ODT_BASE+16640+8], odt_mem[ODT_BASE+16640+7]} = 16'h0008;
      {odt_mem[ODT_BASE+16640+13], odt_mem[ODT_BASE+16640+12]} = 16'h0004;
      odt_mem[ODT_BASE+16640+14] = 8'h00;
      odt_mem[ODT_BASE+16640+17] = 8'h01;                   // valid
      odt_mem[ODT_BASE+16640+18] = VEDA_OWNER_UNOWNED;
      odt_mem[ODT_BASE+16640+20] = 8'h00;  // Object_ID[15:8]
      odt_mem[ODT_BASE+16640+21] = 8'h00;  // Object_ID[23:16]
      odt_mem[ODT_BASE+16640+22] = 8'h02;  // Object_ID[31:24]  <- the region
      odt_mem[ODT_BASE+16640+23] = 8'h00;  // Object_ID[39:32]
      odt_mem[ODT_BASE+16640+24] = 8'h00;  // {4'b0, Object_ID[43:40]}
      odt_mem[ODT_BASE+16640+ODT_OFF_RESIDENT] = 8'h00;     // NOT resident
      {odt_mem[ODT_BASE+16640+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+16640+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+16640+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      // ────────────────────────────────────────────────────────────────
      //  RTL-6c PAGING FIXTURES. `generation` is architecturally
      //  UNREADABLE by design -- there is no CGet for it -- so the only
      //  way to observe it is indirectly, through the saturation refusal.
      //  Both fixtures below exist to make that observation possible, and
      //  their DISTANCE from the ceiling is the load-bearing detail.
      //
      //  Object_ID=106 -> entry 106 -> byte offset 3392. generation
      //  0xFFFFFE, ONE step below the ceiling. Page-out bumps it to
      //  0xFFFFFF (allowed), and the NEXT page-out must refuse.
      {odt_mem[ODT_BASE+3392+3], odt_mem[ODT_BASE+3392+2], odt_mem[ODT_BASE+3392+1], odt_mem[ODT_BASE+3392+0]} = 32'h8001_0500;
      {odt_mem[ODT_BASE+3392+8], odt_mem[ODT_BASE+3392+7]} = 16'h0040;
      {odt_mem[ODT_BASE+3392+13], odt_mem[ODT_BASE+3392+12]} = 16'h000C;
      odt_mem[ODT_BASE+3392+14] = 8'hFE;   // generation = 0x00FFFFFE
      odt_mem[ODT_BASE+3392+15] = 8'hFF;
      odt_mem[ODT_BASE+3392+16] = 8'hFF;
      odt_mem[ODT_BASE+3392+17] = 8'h01;
      odt_mem[ODT_BASE+3392+18] = VEDA_OWNER_UNOWNED;
      odt_mem[ODT_BASE+3392+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+3392+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+3392+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+3392+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      //  Object_ID=108 -> entry 108 -> byte offset 3456. generation
      //  0xFFFFFD, TWO steps below the ceiling, and the second step is the
      //  whole point.
      //
      //  A page-in that WRONGLY bumped generation is indistinguishable
      //  from a correct one at ONE step below: the wrong bump would
      //  saturate to 0xFFFFFF, which looks exactly like correct
      //  preservation, because the mutation hides inside the saturation.
      //  Two steps down the behaviours separate into something countable:
      //  preserving gives TWO successful page-outs before the refusal
      //  (FD->FE, FE->FF, refuse), bumping gives ONE (FD->FE, page-in
      //  bumps to FF, refuse). Counting the refusal boundary is the only
      //  observable this architecture offers for an unreadable field.
      {odt_mem[ODT_BASE+3456+3], odt_mem[ODT_BASE+3456+2], odt_mem[ODT_BASE+3456+1], odt_mem[ODT_BASE+3456+0]} = 32'h8001_0600;
      {odt_mem[ODT_BASE+3456+8], odt_mem[ODT_BASE+3456+7]} = 16'h0040;
      {odt_mem[ODT_BASE+3456+13], odt_mem[ODT_BASE+3456+12]} = 16'h000C;
      odt_mem[ODT_BASE+3456+14] = 8'hFD;   // generation = 0x00FFFFFD
      odt_mem[ODT_BASE+3456+15] = 8'hFF;
      odt_mem[ODT_BASE+3456+16] = 8'hFF;
      odt_mem[ODT_BASE+3456+17] = 8'h01;
      odt_mem[ODT_BASE+3456+18] = VEDA_OWNER_UNOWNED;
      odt_mem[ODT_BASE+3456+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+3456+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+3456+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+3456+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
      //  Object_ID=109 -> entry 109 -> byte offset 3488. Live, resident,
      //  and OWNED BY HART 0x63. Page-out is gated on ODA authority, NOT
      //  on ownership, so a pager may legitimately evict an object it does
      //  not own -- which means page-in must PRESERVE owner_hart or any
      //  hart could claim the object afterwards. That is object theft by
      //  triggering a page fault: invisible in a single-hart model except
      //  through Bind's own 0x06 refusal, which is what makes ownership
      //  observable here at all.
      {odt_mem[ODT_BASE+3488+3], odt_mem[ODT_BASE+3488+2], odt_mem[ODT_BASE+3488+1], odt_mem[ODT_BASE+3488+0]} = 32'h8001_0700;
      {odt_mem[ODT_BASE+3488+8], odt_mem[ODT_BASE+3488+7]} = 16'h0040;
      {odt_mem[ODT_BASE+3488+13], odt_mem[ODT_BASE+3488+12]} = 16'h000C;
      odt_mem[ODT_BASE+3488+14] = 8'h00;
      odt_mem[ODT_BASE+3488+17] = 8'h01;
      odt_mem[ODT_BASE+3488+18] = 8'h63;   // owned by hart 99
      odt_mem[ODT_BASE+3488+ODT_OFF_RESIDENT] = 8'h01;
      {odt_mem[ODT_BASE+3488+ODT_OFF_OWNER_DOMAIN+2], odt_mem[ODT_BASE+3488+ODT_OFF_OWNER_DOMAIN+1], odt_mem[ODT_BASE+3488+ODT_OFF_OWNER_DOMAIN]} = {4'b0, VEDA_DOMAIN_ANY};
   end

   // ═══════════════════════════════════════════════════════════════════
   //  INSTRUCTION ENCODER — computes real RV64I 32-bit encodings at
   //  elaboration time. Field layouts verified directly against the
   //  RISC-V ISA manual (R/I/S/B/U/J-type formats, base opcode map,
   //  Zaamo-adjacent shift-immediate conventions for RV64).
   //  Store mnemonics follow real assembly operand order: SB(rs2,rs1,imm)
   //  means "store rs2's value to address rs1+imm" (sb rs2, imm(rs1)).
   // ═══════════════════════════════════════════════════════════════════

   // ── R-type (OP, 0x33) ──
   function automatic logic [31:0] ADD(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SUB(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLL(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLT(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b010, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SLTU(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b011, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] XOR(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b100, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SRL(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] SRA(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] OR(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b110, rd[4:0], 7'b0110011};
   endfunction
   function automatic logic [31:0] AND(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b111, rd[4:0], 7'b0110011};
   endfunction

   // ── I-type ALU (OP-IMM, 0x13) ──
   function automatic logic [31:0] ADDI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SLTI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b010, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SLTIU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b011, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] XORI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b100, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] ORI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b110, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] ANDI(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b111, rd[4:0], 7'b0010011};
   endfunction
   // RV64 shift-immediates use a 6-bit shamt (instr[25:20]); instr[31:26]
   // discriminates SLLI/SRLI (000000) from SRAI (010000).
   function automatic logic [31:0] SLLI(int rd, int rs1, int shamt6);
      return {6'b000000, shamt6[5:0], rs1[4:0], 3'b001, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SRLI(int rd, int rs1, int shamt6);
      return {6'b000000, shamt6[5:0], rs1[4:0], 3'b101, rd[4:0], 7'b0010011};
   endfunction
   function automatic logic [31:0] SRAI(int rd, int rs1, int shamt6);
      return {6'b010000, shamt6[5:0], rs1[4:0], 3'b101, rd[4:0], 7'b0010011};
   endfunction

   // ── Branches (BRANCH, 0x63, B-type) ──
   function automatic logic [31:0] BEQ(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b000, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BNE(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b001, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BLT(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b100, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BGE(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b101, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BLTU(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b110, imm13[4:1], imm13[11], 7'b1100011};
   endfunction
   function automatic logic [31:0] BGEU(int rs1, int rs2, int imm13);
      return {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], 3'b111, imm13[4:1], imm13[11], 7'b1100011};
   endfunction

   // ── Jumps ──
   function automatic logic [31:0] JAL(int rd, int imm21);
      return {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd[4:0], 7'b1101111};
   endfunction
   function automatic logic [31:0] JALR(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b1100111};
   endfunction

   // ── Upper immediate (U-type) ──
   function automatic logic [31:0] LUI(int rd, int imm20);
      return {imm20[19:0], rd[4:0], 7'b0110111};
   endfunction
   function automatic logic [31:0] AUIPC(int rd, int imm20);
      return {imm20[19:0], rd[4:0], 7'b0010111};
   endfunction

   // ── Loads (LOAD, 0x03, I-type) ──
   function automatic logic [31:0] LB(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LH(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b001, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LW(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b010, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LD(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b011, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LBU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b100, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LHU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b101, rd[4:0], 7'b0000011};
   endfunction
   function automatic logic [31:0] LWU(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b110, rd[4:0], 7'b0000011};
   endfunction

   // ── Stores (STORE, 0x23, S-type) ──
   function automatic logic [31:0] SB(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b000, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SH(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b001, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SW(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b010, imm12[4:0], 7'b0100011};
   endfunction
   function automatic logic [31:0] SD(int rs2, int rs1, int imm12);
      return {imm12[11:5], rs2[4:0], rs1[4:0], 3'b011, imm12[4:0], 7'b0100011};
   endfunction

   // ── RV64-only *W word ops (OP-IMM-32=0x1B, OP-32=0x3B) ──
   function automatic logic [31:0] ADDIW(int rd, int rs1, int imm12);
      return {imm12[11:0], rs1[4:0], 3'b000, rd[4:0], 7'b0011011};
   endfunction
   // *W shift-immediates use a 5-bit shamt (instr[24:20]); instr[31:25]
   // discriminates SLLIW/SRLIW (0000000) from SRAIW (0100000).
   function automatic logic [31:0] SLLIW(int rd, int rs1, int shamt5);
      return {7'b0000000, shamt5[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] SRLIW(int rd, int rs1, int shamt5);
      return {7'b0000000, shamt5[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] SRAIW(int rd, int rs1, int shamt5);
      return {7'b0100000, shamt5[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0011011};
   endfunction
   function automatic logic [31:0] ADDW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SUBW(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b000, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SLLW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SRLW(int rd, int rs1, int rs2);
      return {7'b0000000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0111011};
   endfunction
   function automatic logic [31:0] SRAW(int rd, int rs1, int rs2);
      return {7'b0100000, rs2[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0111011};
   endfunction

   // ── FENCE (MISC-MEM, 0x0F) — implemented as a functional NOP (see
   // decode below): no operands needed for that treatment, so pred/succ/
   // fm/rd/rs1 are all just zeroed.
   function automatic logic [31:0] FENCE();
      return {4'b0000, 4'b0000, 4'b0000, 5'b00000, 3'b000, 5'b00000, 7'b0001111};
   endfunction

   // ═══════════════════════════════════════════════════════════════════
   //  THE PROGRAM — hand-assembled, touches all 50 RV64I encodings at
   //  least once. Branch/jump offsets are computed as ROM-index
   //  differences times 4 (byte size), so they are correct by
   //  construction rather than hand-computed hex. Expected values for
   //  every instruction are documented inline for the manual trace
   //  review required by Milestone B's done criteria.
   // ═══════════════════════════════════════════════════════════════════
   localparam int ROM_SIZE = 81;
   logic [31:0] ROM [0:ROM_SIZE-1];
   initial begin
      // ── Phase 1: ALU reg-imm + reg-reg (x1=10, x2=20 held constant
      // throughout the whole program for the branch-comparator tests) ──
      ROM[0]  = ADDI(1, 0, 10);      // x1 = 10
      ROM[1]  = ADDI(2, 0, 20);      // x2 = 20
      ROM[2]  = ADD (3, 1, 2);       // x3 = 30
      ROM[3]  = SUB (4, 2, 1);       // x4 = 10
      ROM[4]  = SLTI (7, 1, 100);    // x7 = 1
      ROM[5]  = SLTIU(8, 1, 100);    // x8 = 1
      ROM[6]  = XORI (9, 1, 15);     // x9 = 5
      ROM[7]  = ORI  (10, 1, 5);     // x10 = 15
      ROM[8]  = ANDI (11, 1, 6);     // x11 = 2
      ROM[9]  = SLLI (12, 1, 2);     // x12 = 40
      ROM[10] = SRLI (13, 12, 2);    // x13 = 10
      ROM[11] = SRAI (14, 12, 2);    // x14 = 10
      ROM[12] = SLL  (15, 1, 11);    // x15 = 40 (10 << x11=2)
      ROM[13] = SLT  (16, 1, 2);     // x16 = 1
      ROM[14] = SLTU (17, 1, 2);     // x17 = 1
      ROM[15] = XOR  (18, 1, 2);     // x18 = 30
      ROM[16] = SRL  (19, 12, 11);   // x19 = 10 (40 >> x11=2)
      ROM[17] = SRA  (20, 12, 11);   // x20 = 10
      ROM[18] = OR   (21, 1, 2);     // x21 = 30
      ROM[19] = AND  (22, 1, 2);     // x22 = 0

      // ── Phase 2: branches, each taken, skipping exactly one decoy
      // (offset = +8 bytes = 2 instructions ahead) ──
      ROM[20] = BNE (1, 2, (22-20)*4);  // 10!=20 taken -> ROM[22]
      ROM[21] = ADDI(23, 0, 999);       // decoy, skipped
      ROM[22] = ADDI(23, 0, 1);         // x23 = 1
      ROM[23] = BLT (1, 2, (25-23)*4);  // 10<20 signed taken -> ROM[25]
      ROM[24] = ADDI(24, 0, 999);       // decoy, skipped
      ROM[25] = ADDI(24, 0, 1);         // x24 = 1 (transient, reused later)
      ROM[26] = BGE (2, 1, (28-26)*4);  // 20>=10 signed taken -> ROM[28]
      ROM[27] = ADDI(25, 0, 999);       // decoy, skipped
      ROM[28] = ADDI(25, 0, 1);         // x25 = 1 (transient, reused later)
      ROM[29] = BLTU(1, 2, (31-29)*4);  // 10<20 unsigned taken -> ROM[31]
      ROM[30] = ADDI(26, 0, 999);       // decoy, skipped
      ROM[31] = ADDI(26, 0, 1);         // x26 = 1 (transient, reused later)
      ROM[32] = BGEU(2, 1, (34-32)*4);  // 20>=10 unsigned taken -> ROM[34]
      ROM[33] = ADDI(27, 0, 999);       // decoy, skipped
      ROM[34] = ADDI(27, 0, 1);         // x27 = 1 (transient, reused later)
      ROM[35] = BEQ (1, 1, (37-35)*4);  // 10==10 taken -> ROM[37]
      ROM[36] = ADDI(28, 0, 999);       // decoy, skipped (x28 stays 0)

      // ── Phase 3: JAL (link register + forward jump) ──
      ROM[37] = JAL (29, (39-37)*4);    // x29 = link = addr(37)+4 = 152; -> ROM[39]
      ROM[38] = ADDI(29, 0, 999);       // decoy, skipped (JAL always taken)
      ROM[39] = ADDI(30, 0, 1);         // x30 = 1 (JAL landing confirmed)

      // ── Phase 4: LUI / AUIPC ──
      ROM[40] = AUIPC(7, 0);            // x7 = pc(this instr) = 160 -- verify against trace's own pc column
      ROM[41] = LUI  (8, 1);            // x8 = 0x1000 = 4096
      ROM[42] = ADDI (9, 0, 64);        // x9 = 64 (memory test base address)

      // ── Phase 5: load/store byte-lane round trips ──
      ROM[43] = ADDI(10, 0, -1);        // x10 = -1 (all-ones, 0xFFFF...FFFF)
      ROM[44] = SD  (10, 9, 0);         // mem[64] (doubleword) = all-ones
      ROM[45] = LD  (11, 9, 0);         // x11 = -1 (full doubleword round trip)
      ROM[46] = ADDI(12, 0, 2047);      // x12 = 2047 (0x7FF)
      ROM[47] = SW  (12, 9, 8);         // mem word @72 = 2047
      ROM[48] = LW  (13, 9, 8);         // x13 = 2047 (sign-extend path, positive)
      ROM[49] = LWU (14, 9, 8);         // x14 = 2047 (zero-extend path)
      ROM[50] = ADDI(15, 0, -100);      // x15 = -100 (transient, reused later)
      ROM[51] = SH  (15, 9, 16);        // mem halfword @80 = 0xFF9C
      ROM[52] = LH  (16, 9, 16);        // x16 = -100 (sign-extend path)
      ROM[53] = LHU (17, 9, 16);        // x17 = 65436 (zero-extend path, =0xFF9C unsigned)
      ROM[54] = ADDI(18, 0, -5);        // x18 = -5
      ROM[55] = SB  (18, 9, 24);        // mem byte @88 = 0xFB
      ROM[56] = LB  (19, 9, 24);        // x19 = -5 (sign-extend path)
      ROM[57] = LBU (20, 9, 24);        // x20 = 251 (zero-extend path)
      // Unaligned, same-doubleword-different-byte-lane round trip: byte
      // @91 shares word_idx=11 with byte @88 (written above at offset 0
      // within that word) but at byte_off=3 -- proves byte-lane write
      // masking updates only its own lane without clobbering byte 0.
      ROM[58] = ADDI(21, 0, 42);        // x21 = 42
      ROM[59] = SB  (21, 9, 27);        // mem byte @91 (same word as @88, byte_off 3) = 42
      ROM[60] = LB  (22, 9, 27);        // x22 = 42 (readback of the just-written byte)
      ROM[61] = LB  (31, 9, 24);        // x31 = -5 again (re-check byte @88/byte_off 0 unclobbered)

      // ── Phase 6: RV64-only *W ops. x24 = 0x80000000 (2^31) is the key
      // operand: as a *W (32-bit) op, adding 1 to it overflows the 32-bit
      // sign bit, giving a large NEGATIVE 64-bit result after sign
      // extension -- dramatically different from a plain 64-bit ADD on
      // the same bit pattern, which stays a small POSITIVE number. This
      // is the required spot-check proving *W truncate+sign-extend is
      // real and distinct from the non-W path. ──
      ROM[62] = ADDI(24, 0, 1);
      ROM[63] = SLLI(24, 24, 31);       // x24 = 1<<31 = 0x0000000080000000 (2147483648)
      ROM[64] = ADDI(25, 0, 1);         // x25 = 1
      ROM[65] = ADDW(26, 24, 25);       // x26 = sign-extend32(0x80000001) = -2147483647
      ROM[66] = ADD (27, 24, 25);       // x27 = 0x0000000080000001 = +2147483649 (DIFFERS from x26)
      ROM[67] = SUBW(28, 25, 24);       // x28 = sign-extend32(1-0x80000000 mod 2^32) = -2147483647 (cross-check vs x26)
      ROM[68] = SLLIW(5, 25, 31);       // x5 = sign-extend32(1<<31 truncated) = -2147483648 (INT32_MIN)
      ROM[69] = SRLIW(6, 24, 4);        // x24[31:0]=0x80000000 >>logical 4 = 0x08000000, sign-extend positive = 134217728
      ROM[70] = SRAIW(8, 24, 4);        // x24[31:0]=0x80000000 >>arith 4 = 0xF8000000, sign-extend negative = -134217728
      ROM[71] = ADDIW(9, 24, 1);        // x24[31:0]+1 = 0x80000001, sign-extend = -2147483647 (matches x26/x28)
      ROM[72] = SLLW(10, 1, 25);        // x1=10, shift by x25[4:0]=1 -> 20 (32-bit, sign-extend positive)
      ROM[73] = SRLW(11, 24, 25);       // x24[31:0]=0x80000000 >>logical 1 = 0x40000000, sign-extend positive = 1073741824
      ROM[74] = SRAW(12, 24, 25);       // x24[31:0]=0x80000000 >>arith 1 = 0xC0000000, sign-extend negative = -1073741824

      // ── Phase 7: JALR (rs1=x0, so target = imm12 directly = an
      // absolute address -- valid since the whole program fits well
      // within the +-2047 range of a 12-bit signed immediate) ──
      ROM[75] = JALR(13, 0, 77*4);      // x13 = link = addr(75)+4 = 304; jump to ROM[77]
      ROM[76] = ADDI(14, 0, 999);       // decoy, skipped
      ROM[77] = ADDI(15, 0, 1);         // x15 = 1 (JALR landing confirmed)

      // ── Phase 8: FENCE (functional NOP) ──
      ROM[78] = FENCE();
      ROM[79] = ADDI(16, 0, 1);         // x16 = 1 (confirms execution continued normally past FENCE)

      // ── Final: jump to self, freezes state for the PASS assertion ──
      ROM[80] = JAL(0, 0);
   end

   // ═══════════════════════════════════════════════════════════════════
   //  MILESTONE C: ACT4 ELF-loaded memory. A real ACT4 test ELF places
   //  code, data, signature region, and tohost/fromhost all in one
   //  unified 0x80000000-based address space (confirmed via readelf on
   //  a real generated ELF: .text.init@0x80000000, .data@0x8000c000,
   //  .tohost shifting per-test e.g. 0x80037920/0x80025310/0x8003a6f0
   //  depending on each test's own signature-table size). This is
   //  structurally different from the small, hand-assembled, Harvard-
   //  style ROM[]/dmem[] used above for Milestones A/B, so it is added
   //  as a parallel, independently-selected memory rather than altering
   //  that already-verified path. Sized 512KiB (0x80000), comfortably
   //  covering real ELF footprints observed (~208KiB for I-add-00).
   //  The array's own index range is declared to match real ELF byte
   //  addresses directly (0x80000000..0x8007FFFF) so objcopy -O verilog
   //  output -- confirmed empirically to emit byte-level data with
   //  absolute-address @-annotations -- loads via $readmemh with no
   //  address translation needed in the datapath logic below.
   // ═══════════════════════════════════════════════════════════════════
   localparam bit [31:0] ELFMEM_BASE = 32'h8000_0000;
   localparam bit [31:0] ELFMEM_SIZE = 32'h0008_0000;
   logic [7:0] elfmem [ELFMEM_BASE : ELFMEM_BASE + ELFMEM_SIZE - 1];

   // ─────────────────────────────────────────────────────────────────
   //  VEDA-CORE RTL MILESTONE 7: real, out-of-band capability Tag store
   //  for OCL.C/OCS.C -- mirrors the real Sail-side implementation
   //  field-for-field (toolchain/sail-riscv/model/core/mem_metadata.sail,
   //  mem_meta redefined from unit to bool): one bit per 16-byte
   //  (128-bit) granule, scoped to exactly the same real, ELF-loadable
   //  RAM region elfmem[] already covers -- the same honest, bounded-
   //  scope discipline already used for the ODT (256 real RTL entries,
   //  not Sail's 8.4M) and now for the tag store too. Only OCL.C/OCS.C
   //  ever touch this array; plain OCL/OCS/NMC_ADD/Atomic accesses to the
   //  same bytes never do, matching CHERI's own real separation between
   //  ordinary data access and capability load/store.
   // ─────────────────────────────────────────────────────────────────
   logic tag_mem [0 : (ELFMEM_SIZE/32) - 1];
   initial begin
      for (int veda_tm_i = 0; veda_tm_i < (ELFMEM_SIZE/32); veda_tm_i = veda_tm_i + 1)
         tag_mem[veda_tm_i] = 1'b0;
   end

   // ─────────────────────────────────────────────────────────────────
   //  MILESTONE 24 Stage 3 (TCM_FAST_PATH_DESIGN.md Part C, "Mechanism
   //  A"): the TCM capability-spill scratch region -- generalizes the
   //  already-decided OCS.C/OCL.C software-managed spill/restore pattern
   //  (already used for the scheduler save-area) into a real, reusable
   //  fast destination, distinct from elfmem[]. A genuinely SEPARATE
   //  physical array (mirroring the real, existing odt_mem[]-vs-elfmem[]
   //  precedent above -- two distinct base-address ranges, not a
   //  carved-out sub-range of an existing array), at a real, deliberately
   //  small, bounded size (4KiB, sized for the scheduler's own real
   //  save_area_0/save_area_1 relocation -- 3 dwords=24 bytes each today
   //  -- plus real headroom for a handful of future Mechanism-A spill
   //  targets, without being large enough to become a second general-
   //  purpose DRAM-equivalent region, which would blur the "small,
   //  deterministic TCM" security framing the whole feature rests on).
   //  tcm_scratch_tag[] mirrors tag_mem[]'s own real, out-of-band-tag
   //  discipline exactly -- only OCL.C/OCS.C ever touch it, plain
   //  OCL.D/OCS.D against a TCM-scratch address are explicitly out of
   //  this milestone's own scope (they would fall outside elfmem[]'s own
   //  declared bounds if ever attempted against 0xA0000000+, the same
   //  natural, pre-existing out-of-range behavior any address outside
   //  elfmem[] already has -- not a new gap this milestone introduces).
   // ─────────────────────────────────────────────────────────────────
   localparam bit [31:0] TCM_SCRATCH_BASE = 32'hA000_0000;
   localparam bit [31:0] TCM_SCRATCH_SIZE = 32'h0000_1000;
   logic [7:0] tcm_scratch [TCM_SCRATCH_BASE : TCM_SCRATCH_BASE + TCM_SCRATCH_SIZE - 1];
   logic tcm_scratch_tag [0 : (TCM_SCRATCH_SIZE/32) - 1];
   initial begin
      for (int veda_ts_i = 0; veda_ts_i < (TCM_SCRATCH_SIZE/32); veda_ts_i = veda_ts_i + 1)
         tcm_scratch_tag[veda_ts_i] = 1'b0;
   end

   logic act4_mode;
   initial begin
      string elf_hex_path;
      act4_mode = 1'b0;
      if ($value$plusargs("elf_hex=%s", elf_hex_path)) begin
         $readmemh(elf_hex_path, elfmem);
         act4_mode = 1'b1;
      end
   end

\TLV

   |cpu
      @0
         // ─────────────────────────────────────────────────────────
         //  RESET
         // ─────────────────────────────────────────────────────────
         $reset = *reset;

         // ─────────────────────────────────────────────────────────
         //  CYCLE COUNTER
         // ─────────────────────────────────────────────────────────
         $cyc_cnt[31:0] = $reset ? 32'b0 : >>1$cyc_cnt + 32'd1;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 4: minimal real privilege state.
         //  Resets to 1 (privileged), matching real RISC-V's own "harts
         //  reset into the highest privilege level" convention. One-way:
         //  only `veda.droppriv` (decoded below) can clear it; nothing
         //  raises it back (MILESTONE_PLAN.md's own Milestone 4 addendum
         //  has the full reasoning). Same simple stateful-signal idiom
         //  already used for $cyc_cnt above, not a new one.
         // ─────────────────────────────────────────────────────────
         $priv = $reset ? 1'b1 : (>>1$is_veda_droppriv ? 1'b0 : >>1$priv);

         // ─────────────────────────────────────────────────────────
         //  PROGRAM COUNTER — same one-extra-cycle-after-reset handling
         //  as Milestone A / arm_single_cycle.tlv.
         // ─────────────────────────────────────────────────────────
         $reset_just_released = >>1$reset && !$reset;
         // MILESTONE 24: >>1$veda_dram_busy (PREVIOUS cycle's busy state,
         // never this cycle's own combinational value -- see the stall
         // FSM's own header comment above for why this specific ordering
         // matters) takes priority over >>1$pc_src -- a DRAM-tier access
         // that also happens to be the last instruction before a branch
         // must finish its own extra wait before the branch's own
         // redirect is honored; nothing in this core freezes $pc today
         // outside of this new condition (Milestone 14's own PCC-
         // violation check forces $instr to NOP but never freezes $pc --
         // confirmed by direct read before writing this).
         $pc[63:0] =
            ($reset || $reset_just_released) ? (act4_mode ? {32'b0, ELFMEM_BASE} : 64'b0) :
            >>1$veda_dram_busy               ? >>1$pc :
            >>1$pc_src                       ? >>1$alt_pc :
                                                >>1$pc + 64'd4;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 14 (Sail mirror, veda-core/MILESTONE_14_RESULTS.md
         //  / PCC_COMPARTMENT_DESIGN.md): PCC compartment bounding --
         //  bounding execution inside an OCInvoke-entered compartment.
         //  $veda_pcc_base/$veda_pcc_length (defined further below,
         //  alongside $mtvec/$mepc -- SandPiper's own combinational-
         //  elaboration-is-order-independent pattern already used
         //  throughout this file, e.g. $veda_trap_taken referenced here
         //  before its own definition too) hold the currently-active
         //  compartment's own bounds, narrowed away from
         //  VEDA_PCC_UNBOUNDED (40'hFFFFFFFFFF as of RTL-3 -- all-ones in the
         //  widened 40-bit Length field, the reset/no-compartment
         //  sentinel) only by a successful OCInvoke. This check is
         //  genuinely unconditional, every cycle, against the CURRENT
         //  $pc -- distinct in kind from every other check in this file,
         //  none of which are gated on a decoded opcode; Sail's own
         //  mirror (postlude/step_ext.sail's ext_fetch_check_pc) is
         //  identically unconditional, called before every fetch.
         // ─────────────────────────────────────────────────────────
         $veda_pcc_violation = ($veda_pcc_length != 40'hFFFFFFFFFF) &&
                                (({24'b0, $pc[31:0]} < $veda_pcc_base) ||
                                 ({24'b0, $pc[31:0]} >= ($veda_pcc_base + {16'b0, $veda_pcc_length})));

         // ─────────────────────────────────────────────────────────
         //  INSTRUCTION MEMORY — Milestone A/B hand-assembled ROM[]
         //  (pc[8:2] gives a 7-bit index, 0-127, byte addresses 0-508,
         //  comfortably covering ROM_SIZE=81), or Milestone C's
         //  ELF-loaded elfmem[] (little-endian 4-byte read at $pc, real
         //  absolute address), selected by act4_mode.
         // ─────────────────────────────────────────────────────────
         $instr_rom[31:0]  = ROM[($pc[8:2] >= ROM_SIZE) ? ROM_SIZE - 1 : $pc[8:2]];
         $instr_elf[31:0]  = {elfmem[$pc[31:0]+3], elfmem[$pc[31:0]+2], elfmem[$pc[31:0]+1], elfmem[$pc[31:0]+0]};
         // RTL Milestone 14: on a PCC bounds violation, $instr is forced
         // to a real, standard NOP encoding (0x00000013 = ADDI x0,x0,0)
         // rather than whatever arbitrary bytes happen to live at the
         // out-of-bounds $pc -- the single, minimal change that
         // correctly suppresses every possible downstream GPR/capability
         // -register/memory write path this cycle (a NOP targeting x0
         // triggers no real write anywhere in the file), matching Sail's
         // own real behavior of never reaching decode/execute at all on
         // a failed fetch, without needing to individually audit and
         // gate every one of this file's many independent write paths.
         // The real trap itself (mcause/mepc/mtval/PC-redirect) is still
         // delivered via $veda_pcc_violation joining $veda_trap_taken
         // below, entirely independent of what $instr decodes to.
         //
         // MILESTONE 24: >>1$veda_dram_busy composed alongside the
         // existing PCC-violation term, same literal NOP-substitution
         // idiom -- this is the ONE piece of Milestone 14 that is
         // genuinely reused verbatim here (M14 itself provides no
         // stall/freeze mechanism to reuse, only this literal encoding
         // trick -- see the stall FSM's own header comment above).
         // Using >>1 here (not this cycle's own $veda_dram_busy) is what
         // keeps this acyclic: the triggering instruction's REAL decode
         // this cycle is never touched (>>1busy was 0 the cycle a fresh
         // DRAM-tier access is first attempted), only the SUBSEQUENT
         // DRAM_EXTRA_CYCLES cycles at the same (frozen) $pc are forced
         // to NOP here.
         $instr[31:0] = ($veda_pcc_violation || >>1$veda_dram_busy) ? 32'h00000013 :
                        act4_mode                                   ? $instr_elf :
                                                                       $instr_rom;

         // ─────────────────────────────────────────────────────────
         //  DECODE
         // ─────────────────────────────────────────────────────────
         $opcode[6:0] = $instr[6:0];
         $funct3[2:0] = $instr[14:12];
         $funct7[6:0] = $instr[31:25];
         // RV64I's 6-bit-shamt SLLI/SRLI/SRAI use instr[25:20] as a
         // 6-bit shamt (needed to encode shifts up to 63) -- meaning
         // bit 25 is part of the *shamt*, not the opcode discriminator,
         // for these three instructions specifically. The real
         // discriminator is funct6 = instr[31:26] (6 bits: 000000 for
         // SLLI/SRLI, 010000 for SRAI), verified against the RISC-V ISA
         // manual's own RV64I shift-immediate encoding. Using the full
         // 7-bit $funct7 (as the *W shift-immediates correctly do, since
         // those only need a 5-bit shamt and bit 25 is genuinely part of
         // their discriminator) would misdecode any SLLI/SRLI/SRAI whose
         // shift amount is >=32 as an unrecognized instruction, since
         // bit 25 (shamt[5]) would then be 1, not matching funct7==0.
         $funct6[5:0] = $instr[31:26];
         $rd[4:0]     = $instr[11:7];
         $rs1[4:0]    = $instr[19:15];
         $rs2[4:0]    = $instr[24:20];
         $shamt6[5:0] = $instr[25:20];
         $shamt5[4:0] = $instr[24:20];

         $op_is_load   = ($opcode == 7'b0000011);
         $op_is_imm    = ($opcode == 7'b0010011);
         $op_is_auipc  = ($opcode == 7'b0010111);
         $op_is_store  = ($opcode == 7'b0100011);
         $op_is_reg    = ($opcode == 7'b0110011);
         $op_is_lui    = ($opcode == 7'b0110111);
         $op_is_branch = ($opcode == 7'b1100011);
         $op_is_jalr   = ($opcode == 7'b1100111);
         $op_is_jal    = ($opcode == 7'b1101111);
         $op_is_immw   = ($opcode == 7'b0011011);
         $op_is_regw   = ($opcode == 7'b0111011);
         $op_is_fence  = ($opcode == 7'b0001111);
         $op_is_system = ($opcode == 7'b1110011);

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: a minimal, real Zicsr-lite + trap-taken
         //  control flow -- the largest remaining Sail/RTL architectural
         //  divergence named in NEXT_STEPS_ROADMAP.md §2.4 ("Sail's own
         //  security model (hard trap, exact mcause/mtval) is not
         //  actually what the RTL currently enforces"). Real, standard
         //  RISC-V encoding throughout (Zicsr's I-type CSR shape,
         //  SYSTEM opcode), not an invented mechanism.
         //
         //  Deliberate scope reduction, stated plainly rather than
         //  silently narrowed: only CSRRW/CSRRS are decoded this pass
         //  (CSRRC/CSRRWI/CSRRSI/CSRRCI deferred -- this core's own
         //  trap handlers only ever need "install a value" (CSRRW, for
         //  mtvec) and "read a value" (CSRRS with rs1=x0, the real
         //  `csrr` pseudo-instruction's own expansion), matching every
         //  trap-handler pattern already proven in this project's own
         //  Sail-side tests). Only 5 CSR addresses are recognized --
         //  the real, standard RISC-V M-mode addresses for mtvec/mscratch/
         //  mepc/mcause/mtval (0x305/0x340/0x341/0x342/0x343) -- any other
         //  address reads/writes as a hardwired 0, matching real RISC-V's
         //  own WARL convention for an unimplemented CSR rather than
         //  inventing new fault behavior for it. mscratch (RTL Milestone
         //  25 mirror) was added later than the other four, needed by the
         //  full-GPR-context-save scheduler's own mscratch-based trap-
         //  entry bootstrap (sail_tests/vc_scheduler_cooperative_yield.S)
         //  -- a byte-for-byte structural copy of mtvec's own pattern
         //  below, since mscratch shares mtvec's exact profile: nothing
         //  but software CSRRW ever writes it, no hardware-capture logic
         //  needed.
         // ─────────────────────────────────────────────────────────
         $csr_addr[11:0] = $instr[31:20];
         $is_csrrw = $op_is_system && ($funct3 == 3'b001);
         $is_csrrs = $op_is_system && ($funct3 == 3'b010);
         $is_csr_access = $is_csrrw || $is_csrrs;
         $csr_is_mtvec   = ($csr_addr == 12'h305);
         $csr_is_mscratch = ($csr_addr == 12'h340);
         $csr_is_mepc    = ($csr_addr == 12'h341);
         $csr_is_mcause  = ($csr_addr == 12'h342);
         $csr_is_mtval   = ($csr_addr == 12'h343);
         // RTL Milestone 14: four new CSRs, the real, standard RISC-V
         // "Machine-level Custom read/write" address range (riscv-spec.pdf
         // Table 91, p.664, 0x7C0-0x7FF) -- verified against the real
         // spec, the same real range convention already trusted once for
         // mtvec/mscratch/mepc/mcause/mtval above, and the identical four
         // addresses already chosen and verified on the Sail side
         // (veda_regs.sail).
         $csr_is_veda_pcc_base     = ($csr_addr == 12'h7C0);
         $csr_is_veda_pcc_length   = ($csr_addr == 12'h7C1);
         $csr_is_veda_mepcc_base   = ($csr_addr == 12'h7C2);
         $csr_is_veda_mepcc_length = ($csr_addr == 12'h7C3);
         // RTL Milestone 18: reusable Length/Perms template for
         // VEDA_ODT_POPULATE_FAST below -- same real 0x7C0-0x7FF custom
         // range, next free slot after Milestone 14's four, matching the
         // already-verified Sail-side choice (veda_regs.sail).
         $csr_is_veda_attr         = ($csr_addr == 12'h7C4);
         // RTL Milestone 19 (Sail mirror, MILESTONE_19_RESULTS.md /
         // veda-core/rtl/MILESTONE_19_RESULTS.md): veda_mode, bit 0 =
         // veda_purecap. Next free slot after Milestone 18's 0x7C4,
         // matching the already-verified Sail-side choice
         // (veda_regs.sail) -- confirmed collision-free against every
         // $csr_is_veda_* address already decoded above before adopting
         // it.
         $csr_is_veda_mode         = ($csr_addr == 12'h7C5);
         // RTL-5 (R10): read-only observability for the CRBR and its saved
         // shadow, mirroring Sail's 0x7C6/0x7C7. The whole reason R10 was a
         // SILENT escape is that nothing ever observed the current region --
         // so exposing it is the honest fix for that gap, and it is what
         // lets a test assert the load / trap-save / mret-restore cycle
         // directly instead of only inferring it.
         //
         // STRICTLY READ-ONLY, and deliberately so: these appear in the
         // $csr_rdata mux below but get NO arm in any write path. A WRITABLE
         // CRBR would be a Milestone-19/20-class self-escape -- a live
         // compartment that can CSRRW its own ODT base re-points its entire
         // object namespace at another domain's table, which is exactly the
         // vector $veda_csr_escape_violation exists to close for 0x7C0-0x7C5.
         // Read access needs no gate, matching this file's established
         // "capability metadata is always inspectable" principle: code
         // already knows which domain it is running in.
         $csr_is_veda_current_region = ($csr_addr == 12'h7C6);
         $csr_is_veda_saved_region   = ($csr_addr == 12'h7C7);
         // R12: read-only trap-nesting status, {poison, depth}. No write
         // decode anywhere -- software can already forge the saved mepcc
         // VALUE via 0x7C2/0x7C3, and must not additionally be able to
         // forge the OCCUPANCY, or the mechanism is defeated by the very
         // software it constrains. It is also the only channel by which a
         // handler can learn WHY a return was denied.
         $csr_is_veda_trap_status    = ($csr_addr == 12'h7C8);

         // MRET: the one, fixed 32-bit encoding (funct12=0b001100000010,
         // rs1=rd=0, funct3=0, opcode=SYSTEM) -- matched as a single
         // literal comparison rather than field-by-field decode, the
         // simplest, least-ambiguous way to recognize one specific,
         // fully-fixed instruction word (no operand fields to extract at
         // all, unlike CSRRW/CSRRS). This core has no privilege-level
         // stack to restore (it's always effectively M-mode, matching
         // $priv's own existing one-way-drop model) -- MRET here means
         // exactly "PC = mepc", not a full mstatus.MPP/MPIE restore.
         $is_mret = ($instr == 32'h30200073);

         // RTL MILESTONE 23: ECALL -- the same fixed-literal idiom as
         // MRET above (funct12=0, rs1=rd=0, funct3=0, opcode=SYSTEM;
         // the full 32-bit word is 0x00000073, distinct from EBREAK's
         // 0x00100073 -- differs only in bit 20 -- and from MRET's
         // 0x30200073). Closes a gap this project's own Milestone 21
         // explicitly named and pre-scoped: "if and when a future
         // milestone adds ecall... that work must wire its own new
         // violation signal into the existing $veda_trap_taken
         // OR-chain... Doing so would automatically and correctly get
         // PCC-reset for free, by construction" (MILESTONE_21_RESULTS.md).
         // EBREAK remains deferred -- not added here.
         $is_ecall = ($instr == 32'h00000073);

         $is_lb  = $op_is_load && ($funct3 == 3'b000);
         $is_lh  = $op_is_load && ($funct3 == 3'b001);
         $is_lw  = $op_is_load && ($funct3 == 3'b010);
         $is_ld  = $op_is_load && ($funct3 == 3'b011);
         $is_lbu = $op_is_load && ($funct3 == 3'b100);
         $is_lhu = $op_is_load && ($funct3 == 3'b101);
         $is_lwu = $op_is_load && ($funct3 == 3'b110);
         $is_load = $op_is_load;

         $is_addi  = $op_is_imm && ($funct3 == 3'b000);
         $is_slti  = $op_is_imm && ($funct3 == 3'b010);
         $is_sltiu = $op_is_imm && ($funct3 == 3'b011);
         $is_xori  = $op_is_imm && ($funct3 == 3'b100);
         $is_ori   = $op_is_imm && ($funct3 == 3'b110);
         $is_andi  = $op_is_imm && ($funct3 == 3'b111);
         $is_slli  = $op_is_imm && ($funct3 == 3'b001) && ($funct6 == 6'b000000);
         $is_srli  = $op_is_imm && ($funct3 == 3'b101) && ($funct6 == 6'b000000);
         $is_srai  = $op_is_imm && ($funct3 == 3'b101) && ($funct6 == 6'b010000);

         $is_auipc = $op_is_auipc;

         $is_sb = $op_is_store && ($funct3 == 3'b000);
         $is_sh = $op_is_store && ($funct3 == 3'b001);
         $is_sw = $op_is_store && ($funct3 == 3'b010);
         $is_sd = $op_is_store && ($funct3 == 3'b011);
         $is_store = $op_is_store;

         $is_add  = $op_is_reg && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_sub  = $op_is_reg && ($funct3 == 3'b000) && ($funct7 == 7'b0100000);
         $is_sll  = $op_is_reg && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_slt  = $op_is_reg && ($funct3 == 3'b010) && ($funct7 == 7'b0000000);
         $is_sltu = $op_is_reg && ($funct3 == 3'b011) && ($funct7 == 7'b0000000);
         $is_xor  = $op_is_reg && ($funct3 == 3'b100) && ($funct7 == 7'b0000000);
         $is_srl  = $op_is_reg && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sra  = $op_is_reg && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);
         $is_or   = $op_is_reg && ($funct3 == 3'b110) && ($funct7 == 7'b0000000);
         $is_and  = $op_is_reg && ($funct3 == 3'b111) && ($funct7 == 7'b0000000);

         $is_lui = $op_is_lui;

         $is_beq  = $op_is_branch && ($funct3 == 3'b000);
         $is_bne  = $op_is_branch && ($funct3 == 3'b001);
         $is_blt  = $op_is_branch && ($funct3 == 3'b100);
         $is_bge  = $op_is_branch && ($funct3 == 3'b101);
         $is_bltu = $op_is_branch && ($funct3 == 3'b110);
         $is_bgeu = $op_is_branch && ($funct3 == 3'b111);

         $is_jalr = $op_is_jalr;
         $is_jal  = $op_is_jal;

         $is_addiw = $op_is_immw && ($funct3 == 3'b000);
         $is_slliw = $op_is_immw && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_srliw = $op_is_immw && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sraiw = $op_is_immw && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);

         $is_addw = $op_is_regw && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_subw = $op_is_regw && ($funct3 == 3'b000) && ($funct7 == 7'b0100000);
         $is_sllw = $op_is_regw && ($funct3 == 3'b001) && ($funct7 == 7'b0000000);
         $is_srlw = $op_is_regw && ($funct3 == 3'b101) && ($funct7 == 7'b0000000);
         $is_sraw = $op_is_regw && ($funct3 == 3'b101) && ($funct7 == 7'b0100000);

         $is_fence = $op_is_fence;
         // Decoded but intentionally unused this phase (FENCE is a
         // functional NOP -- no memory-ordering hazards exist in a
         // single-cycle, single-hart core); silences the SandPiper
         // unused-signal warning per the tool's own suggested idiom.
         `BOGUS_USE($is_fence)

         $is_shift_imm  = $is_slli || $is_srli || $is_srai;
         $is_shift_immw = $is_slliw || $is_srliw || $is_sraiw;
         $is_alu_imm    = $is_addi || $is_slti || $is_sltiu || $is_xori || $is_ori || $is_andi || $is_shift_imm;
         $is_alu_reg    = $is_add || $is_sub || $is_sll || $is_slt || $is_sltu || $is_xor || $is_srl || $is_sra || $is_or || $is_and;
         $is_alu_immw   = $is_addiw || $is_shift_immw;
         $is_alu_regw   = $is_addw || $is_subw || $is_sllw || $is_srlw || $is_sraw;
         $is_w_op       = $is_alu_immw || $is_alu_regw;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE DECODE — Custom-0 (0001011): Object-Bind (I-type,
         //  funct3=101) vs OCL/OCS (R-type). funct3=101 alone identifies
         //  Bind unambiguously (VEDA_CORE_SPEC.md Section 1: OCL/OCS's
         //  own width table never uses funct3=101, reserved exactly for
         //  this). This milestone only implements OCL.D/OCS.D (funct3=
         //  011, matching Sail V-A's own scope) -- funct7 selects OCL
         //  (0000000) vs OCS (0000001), the R-type case.
         //
         //  Capability-register operand fields are packed into their
         //  5-bit R-type/I-type slots as [0, vcapidx(4)] -- the same
         //  convention already fixed in the Sail model (VEDA_CORE_SPEC.md
         //  Section 3: "future-proofs against growing past 16 capability
         //  registers"), so only the low 4 bits of the relevant field are
         //  real; the top bit is expected to be 0 for a validly-encoded
         //  Veda-Core instruction.
         // ─────────────────────────────────────────────────────────
         $op_is_custom0 = ($opcode == 7'b0001011);
         // R30: imm[11:2] MUST be zero. Sail's encdec pins
         // `0b0000000000 @ mode` (veda_bind_insts.sail:173-175), so 1023 of the
         // 1024 upper-immediate patterns are decode-undefined there. This layer
         // tested opcode+funct3 only and read the mode out of $instr[21:20],
         // which made every one of those patterns execute as a real Bind --
         // measured, and Bind is the CAPABILITY-MINTING path
         // (difftest/probes/p6_overbroad.S w0: cgettag reads 1 here, 0 on Sail).
         // Narrowing the decode itself rather than adding a parallel gate is
         // deliberate: every consumer downstream inherits it, so there is no
         // second place to forget.
         $is_veda_bind  = $op_is_custom0 && ($funct3 == 3'b101) && ($instr[31:22] == 10'b0);
         $is_veda_ocl   = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000000);
         $is_veda_ocs   = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000001);
         // OCL.C/OCS.C -- RTL Milestone 7 (VEDA_CORE_SPEC.md's own
         // "OCL.C/OCS.C semantics" writeup). Same funct7 as OCL/OCS
         // above, differentiated by funct3=100 (the width table's own
         // reserved "C" slot). `rd` here is NOT a GPR -- it reuses
         // $veda_rd_cap (instr[10:7], already extracted below for Bind/
         // OCA/CSetBounds/CSeal/CUnseal) as a Capability Register index,
         // matching real CHERI's own [C]LC/[C]SC precedent (already
         // decided and cited in the spec): a 128-bit capability plus Tag
         // has no meaningful GPR representation.
         $is_veda_ocl_c = $op_is_custom0 && ($funct3 == 3'b100) && ($funct7 == 7'b0000000);
         $is_veda_ocs_c = $op_is_custom0 && ($funct3 == 3'b100) && ($funct7 == 7'b0000001);

         // Bind: mode = instr[21:20] (imm[1:0]), rs1 = instr[19:15]
         // (already extracted as $rs1, an ordinary GPR holding Object_ID
         // -- VEDA_CORE_SPEC.md Section 4's own "not a capability-register
         // reference" choice), rd_cap = instr[10:7] (4-bit capability
         // register index).
         // RTL Milestone 8: the mode field is now actually branched on.
         // A real, previously-undetected gap closed by this milestone:
         // since $veda_bind_mode was decoded but never checked, EVERY
         // mode value (00/01/10/11) silently executed as plain Bind --
         // `veda.rebind` would have wrongly reset Offset to 0 exactly
         // like a fresh Bind, defeating Rebind's entire purpose (Section
         // 4: "Offset preserved across relocation"). Fixed by decoding
         // each mode explicitly below.
         $veda_bind_mode[1:0] = $instr[21:20];
         $is_veda_bind_plain  = $is_veda_bind && ($veda_bind_mode == 2'b00);
         // Bind-NoTrap (mode=01): Sail's own distinction from plain Bind
         // is trap-vs-soft-fail on an ODT miss (veda_bind_insts.sail:
         // VEDA_BIND traps via veda_trap(), VEDA_BIND_NOTRAP instead
         // writes zero_capability+Tag=0). This RTL has no trap
         // infrastructure at all (the same honest floor stated
         // throughout this file) -- plain Bind's own existing soft-fail
         // convention (Tag = $veda_odt_valid, already 0 on a miss) is
         // therefore ALREADY behaviorally identical to Bind-NoTrap.
         // Decoded as its own signal for documentation/test clarity and
         // to keep the door open for real trap infra later (at which
         // point only $is_veda_bind_plain would start trapping), but
         // shares $bind_wr_en's write path unchanged below.
         $is_veda_bind_notrap = $is_veda_bind && ($veda_bind_mode == 2'b01);
         // Rebind (mode=10): the real, new-this-milestone behavior --
         // refreshes Base/Length/Perms/otype/generation from the ODT
         // while leaving the capability register's own Offset field
         // untouched, and reads/writes rd (not rs1) as its own "current
         // capability" input -- distinct enough from Bind/Bind-NoTrap to
         // need its own write path below, not a shared one.
         $is_veda_rebind      = $is_veda_bind && ($veda_bind_mode == 2'b10);

         // ─────────────────────────────────────────────────────────
         //  MILESTONE 24: real DRAM-latency stall FSM (TCM_FAST_PATH_
         //  DESIGN.md Part A). Scope, deliberately narrow (design doc's
         //  own reasoning): only Object-Bind/Bind-NoTrap/Rebind's ODT
         //  access and OCL.C/OCS.C's capability-width memory access --
         //  NOT plain OCL.D/OCS.D, NOT ordinary ld/sd, which would
         //  silently regress ACT4's own cycle-count assumptions for no
         //  benefit this milestone's own scope needs.
         //
         //  Real correctness property, verified by hand-tracing before
         //  writing this (not copied from the design doc's own first-
         //  draft formula, which had a same-cycle combinational-loop
         //  risk: gating $instr on THIS cycle's own $veda_dram_busy,
         //  itself derived from decoding THIS cycle's $instr, is a real
         //  cycle in the dependency graph). The fix: $instr's own NOP-
         //  forcing (below) and $pc's own freeze (below) both gate on
         //  >>1$veda_dram_busy (the PREVIOUS cycle's busy state, a real
         //  register read, never this cycle's own combinational value) --
         //  so the triggering Bind/OCL.C/OCS.C instruction decodes and
         //  executes NORMALLY, unforced, on its own first (only) fetch
         //  cycle -- $bind_wr_en/$oclc_wr_en/OCS.C's own always_ff write
         //  logic below are completely untouched, same 1-cycle write
         //  latency as every prior milestone. The new mechanism purely
         //  holds $pc at the SAME value for DRAM_EXTRA_CYCLES additional
         //  cycles afterward (forcing NOP during those extra cycles only)
         //  before the NEXT instruction is allowed to fetch -- verified
         //  by hand-tracing to add exactly DRAM_EXTRA_CYCLES extra cycles
         //  (not DRAM_EXTRA_CYCLES+1, a real off-by-one the same-cycle-
         //  load-into-stall_cnt formula below specifically avoids).
         //
         //  $veda_dram_stall_req fires exactly once per DRAM-tier access
         //  attempt: real decode this cycle (safe -- $instr is unforced
         //  whenever >>1busy was 0, which is the only time this guard
         //  passes) AND not already mid-stall (>>1busy==0) AND not also a
         //  PCC violation (a faulting fetch must not spuriously start a
         //  stall that would then eat into the trap-handling flow).
         // ─────────────────────────────────────────────────────────
         // MILESTONE 24 Stage 2: the Bind/Bind-NoTrap/Rebind term gains
         // the `&& !$veda_odt_tcm_hit` guard (judged on Object_ID).
         // MILESTONE 24 Stage 3: OCL.C/OCS.C's own term gains the
         // `&& !$veda_capmem_tcm_hit` guard (judged on the resolved
         // memory address, $veda_capmem_tcm_hit defined below alongside
         // $veda_capmem_granule -- SandPiper's own order-independent
         // elaboration within this @0 stage, already relied on
         // throughout this file, makes the forward reference safe).
         // ─────────────────────────────────────────────────────────
         //  R21 FIX 1 (DESIGN_07): an access that will NOT happen must not
         //  buy latency for it. Before this, the only trap term here was
         //  !$veda_pcc_violation -- a FETCH-side check. The comment above
         //  already states exactly why that guard exists ("a faulting fetch
         //  must not spuriously start a stall that would then eat into the
         //  trap-handling flow"); it was simply never extended to the
         //  DATA-side violations, and that omission is a fail-open
         //  compartment escape at DRAM_EXTRA_CYCLES != 0:
         //
         //    an OCL.C/OCS.C (or bind) that BOTH violates AND misses the TCM
         //    started a stall; $pc line ~1039 ranks >>1$veda_dram_busy ABOVE
         //    >>1$pc_src, and $instr is forced to NOP for every stall cycle
         //    (so $pc_src reads 0 out of all of them), so the trap's own
         //    mtvec redirect was DISCARDED and execution resumed at pc+4 --
         //    while every trap STATE effect still fired, including
         //    $veda_pcc_length := 40'hFFFFFFFFFF (UNBOUNDED),
         //    $veda_pcc_base := 0, $veda_current_region := 0 and
         //    $veda_pcc_object := VEDA_OBJECT_NONE. The attacker keeps
         //    running its own instruction stream with the compartment
         //    bound removed.
         //
         //  The bind arm needs ALL FOUR of its refusal terms, not just
         //  $veda_bind_trap: $bind_wr_en (~line 2424) gates on bind_trap,
         //  domain_violation, region_fault AND residency_fault, and
         //  $veda_bind_trap alone is only owner||notfound (line 1974).
         //  Gating on bind_trap alone would leave three of the four escape
         //  paths open -- checked against $bind_wr_en's own term list
         //  rather than assumed.
         //
         //  This edit is strictly monotone: it only ever REMOVES stalls,
         //  and only on paths that trap anyway. It cannot create a stall
         //  that did not exist, so it cannot open a new escape.
         //
         //  All referenced signals are @0, same stage as this expression
         //  (verified by stage-marker scan, not assumed): domain_violation
         //  :1971, bind_trap :1974, region_fault :2004, residency_fault
         //  :2027, oclc_violation :3083, ocsc_violation :3084. Forward
         //  reference within @0 is order-independent under SandPiper, as
         //  this file already relies on for $veda_capmem_tcm_hit above.
         //
         //  NOT YET SIMULATED -- see R21 FIX 2 and the test named in
         //  DESIGN_07. iverilog is absent from this machine, so this fix is
         //  hand-verified against the RTL only. Do not credit it as proven.
         // ─────────────────────────────────────────────────────────
         $veda_dram_stall_req =
            !$veda_pcc_violation && !(>>1$veda_dram_busy) &&
            ((($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind)
                 && !$veda_odt_tcm_hit
                 && !$veda_bind_trap && !$veda_domain_violation
                 && !$veda_region_fault && !$veda_residency_fault) ||
             (($is_veda_ocl_c || $is_veda_ocs_c)
                 && !$veda_capmem_tcm_hit
                 && !$veda_oclc_violation && !$veda_ocsc_violation));
         // Same-cycle load (NOT >>1$veda_dram_stall_req) -- loading on the
         // >>1-delayed request would add one extra spurious cycle before
         // the counter reflects the real remaining wait, the exact
         // off-by-one caught by hand-tracing above.
         $veda_dram_stall_cnt[7:0] =
            $reset                       ? 8'd0 :
            $veda_dram_stall_req         ? DRAM_EXTRA_CYCLES[7:0] :
            (>>1$veda_dram_stall_cnt != 8'd0) ? (>>1$veda_dram_stall_cnt - 8'd1) :
                                                 8'd0;
         // Real bug caught only by actually running the regression (not
         // just hand-tracing the nonzero-E case): $veda_dram_stall_req can
         // fire on any DRAM-tier access attempt REGARDLESS of
         // DRAM_EXTRA_CYCLES's own value (it's a pure decode/idle check,
         // never compared against E). Without the explicit
         // `DRAM_EXTRA_CYCLES != 0` guard here, busy would go true for
         // exactly one spurious cycle even at the E=0 regression floor
         // (stall_cnt loads to 0 that same cycle, but stall_req alone
         // still made busy true), forcing one spurious NOP after every
         // single Bind/OCL.C/OCS.C even with the feature nominally "off"
         // -- confirmed as a real functional regression (Milestone 4 and
         // Milestone 10's own POSITIVE tests genuinely failed) before
         // this fix, not a hypothetical concern.
         $veda_dram_busy = ($veda_dram_stall_cnt != 8'd0) ||
                            ($veda_dram_stall_req && (DRAM_EXTRA_CYCLES != 0));

         // mode=11 (VEDA_BIND_RESERVED, Sail: Illegal_Instruction()) --
         // deliberately produces no write-enable anywhere below, this
         // file's own established floor for "no trap to raise" (matches
         // e.g. an out-of-range funct7 producing no decode match at all).
         $veda_rd_cap[3:0]    = $instr[10:7];

         // OCL/OCS: rs1 is a capability register at instr[18:15] (4
         // bits), rs2 = instr[24:20] (already extracted as $rs2, the
         // fresh per-access GPR offset), rd = instr[11:7] (already
         // extracted as $rd -- OCL's GPR load destination, or OCS's
         // GPR store-value source). Reused as-is below by OCA/NMC_ADD/
         // Veda-Atomic too -- all of Custom-0/2's R-type instructions and
         // Custom-1 share the identical rs1-capability field position, so
         // this one signal (and $rs2/$rd) serves all of them without a
         // per-instruction rename.
         $veda_ocl_ocs_rs1_cap[3:0] = $instr[18:15];

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 2 DECODE — OCA (Custom-2), NMC_ADD.W/D
         //  (Custom-0), Veda-Atomic (Custom-1, its own separate opcode).
         //  Build order matters here and is real, not arbitrary: OCA must
         //  exist before NMC_ADD/Veda-Atomic are usefully testable, since
         //  Milestone 1's Object-Bind always resets a capability's Offset
         //  to 0, and NMC_ADD/Veda-Atomic both operate on the capability's
         //  own *persistent* Offset (VEDA_CORE_SPEC.md Section 1: "OCA is
         //  the missing instruction that lets software position a
         //  capability register at an exact target offset before issuing
         //  an atomic or NMC operation") -- the identical dependency
         //  order already used when this same subset was built in Sail.
         // ─────────────────────────────────────────────────────────
         $op_is_custom2 = ($opcode == 7'b1011011);
         $is_veda_oca   = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001010);
         // RTL mirror of DESIGN_01/Sail CAndPerm: rights attenuation. funct7
         // 0010111, the next free Custom-2/funct3=001 slot (OCA 0001010 ..
         // OCRETURN 0010110). cd = cs1 with Perms &= rs2, otherwise the OCA
         // manipulate idiom exactly: all fields carry from cs1, Tag cleared
         // on an untagged or sealed source. Monotonic by construction (AND
         // only clears), so no bounds term.
         $is_veda_candperm = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010111);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 3 DECODE — the Veda-Cap query family
         //  (funct3 = 000, dest-kind = GPR) and CSetBounds/CSetBoundsExact
         //  (funct3 = 001, dest-kind = Capability, same as OCA). No
         //  permission or bounds checks on the query family at all --
         //  deliberately, matching CHERI's own real principle (already
         //  applied once in Sail): capability *metadata* is always
         //  inspectable, even on a sealed or untagged capability.
         // ─────────────────────────────────────────────────────────
         $is_veda_cgetbase   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000000);
         $is_veda_cgetlen    = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000001);
         $is_veda_cgetperm   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000010);
         $is_veda_cgettag    = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000011);
         $is_veda_cgettype   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000100);
         $is_veda_cgetaddr   = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000101);
         $is_veda_cgetoffset = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000110);
         // RTL-19: THE FAULT-IDENTIFICATION CHANNEL. A trap reports
         // {cap_idx, cause} and no Object_ID, and this family could read every
         // field of a capability EXCEPT its name -- so a handler was told which
         // REGISTER faulted and could never learn which OBJECT that was. The
         // copy-on-write handler cannot mint a copy without it, and the closest
         // thing to a pager in the corpus hardcodes the Object_ID it repairs
         // because there was no other way.
         //
         // Disclosing the name is safe, established rather than assumed:
         // DESIGN_08 draws the confidentiality line around the physical base,
         // explicitly not around the name, and CGetBase already returns a raw
         // physical Base -- strictly more sensitive than this.
         //
         // NOT tag-gated and NO generation check, exactly like the other seven.
         // A STALE capability therefore returns a real, currently-allocated
         // name belonging to a DIFFERENT incarnation of that slot. Fault
         // handlers are safe by construction (a capability that reached a fault
         // already passed the tag and generation checks); a handler that stores
         // the name and uses it later is not.
         $is_veda_cgetobjectid = $op_is_custom2 && ($funct3 == 3'b000) && ($funct7 == 7'b0000111);
         $is_veda_capquery = $is_veda_cgetbase || $is_veda_cgetlen || $is_veda_cgetperm ||
                              $is_veda_cgettag || $is_veda_cgettype || $is_veda_cgetaddr || $is_veda_cgetoffset ||
                              // omitting this OR-term would decode the instruction and
                              // never fire the query path -- it would read back zero,
                              // silently, which is the worst of the three outcomes
                              $is_veda_cgetobjectid;

         // Real, honest observation already recorded once in Sail, not
         // re-litigated here: CSetBoundsExact's real distinction from
         // CSetBounds ("traps instead of rounding if not exactly
         // representable") only matters for a *compressed* bounds
         // encoding CHERI has and this design deliberately doesn't
         // (VEDA_CORE_SPEC.md Section 2's `Length` is a plain, uncompressed
         // 16-bit value -- every value is exactly representable). Both
         // decode separately (their real, distinct funct7 slots are kept,
         // matching the spec) but share one identical execute path below.
         $is_veda_csetbounds      = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001000);
         $is_veda_csetboundsexact = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0001001);
         $is_veda_csetbounds_either = $is_veda_csetbounds || $is_veda_csetboundsexact;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 6: CSeal/CUnseal (VEDA_CORE_SPEC.md
         //  Section 1's already-decided encoding, a direct, unmodified
         //  field-for-field match to CHERI-RISC-V's own real CSeal/
         //  CUnseal shape). funct7=0010000/0010001, same Custom-2
         //  opcode/funct3=001 dest-is-capability-register convention as
         //  OCA/CSetBounds. The first RTL instructions where `rs2` is
         //  ALSO a capability register (the "type-authority" operand),
         //  not a GPR -- a genuinely new operand pattern, decoded below.
         // ─────────────────────────────────────────────────────────
         $is_veda_cseal   = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010000);
         $is_veda_cunseal = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010001);
         // rs2 as a capability register: instr[23:20] (4 bits) -- the
         // same relative position/width as $veda_ocl_ocs_rs1_cap's own
         // instr[18:15] rs1-capability field, just shifted to the rs2
         // slot (instr[24:20]'s low 4 bits), mirroring
         // VEDA_CORE_SPEC.md Section 1's own stated field-position
         // consistency principle.
         $veda_cseal_cunseal_rs2_cap[3:0] = $instr[23:20];

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 4 DECODE — a minimal, real privilege
         //  gate (MILESTONE_PLAN.md's own Milestone 4 addendum has the
         //  full reasoning for why this couldn't be deferred further
         //  once ODT-Populate exists), and ODT-Populate/ODT-Destroy
         //  themselves (VEDA_CORE_SPEC.md Section 5.1's already-decided
         //  encoding). `veda.droppriv` lives in Custom-3 -- explicitly
         //  "Reserved, unallocated" in this file's own ISA summary since
         //  the very first draft, exactly the room this project has
         //  repeatedly reserved for real, later growth rather than
         //  overloading an already-populated opcode.
         // ─────────────────────────────────────────────────────────
         $op_is_custom3 = ($opcode == 7'b1111011);
         // funct7 = 0000000 claims one Custom-3 slot, leaving room for
         // more (the same "reserve, don't exhaust" principle already
         // used for Custom-3 as a whole).
         // R30: funct3 was never tested at all, so all eight values reached
         // `$priv = 0` at :1020. Seven of them are encodings Sail refuses.
         $is_veda_droppriv = $op_is_custom3 && ($funct7 == 7'b0000000) && ($funct3 == 3'b000);

         // rs1/rs2/rd here are ordinary GPRs, not capability registers --
         // ODT-Populate/Destroy operate on raw Object_ID/descriptor
         // *values*, not on an already-bound capability (Section 5.1:
         // "rs1 = a GPR holding Object_ID, mirrors Object-Bind's own rs1
         // convention field-for-field"). $rs1/$rs2/$rd are already the
         // right, full 5-bit GPR fields -- no new decode signal needed.
         $is_veda_odt_populate = $op_is_custom0 && ($funct3 == 3'b000) && ($funct7 == 7'b0000011);
         $is_veda_odt_destroy  = $op_is_custom0 && ($funct3 == 3'b001) && ($funct7 == 7'b0000011);
         // RTL Milestone 18 (mirrors Sail's VEDA_ODT_POPULATE_FAST,
         // veda_ocl_insts.sail): same funct3 as plain Populate (grouping
         // with the Populate family), funct7 = 0000100 -- the next free
         // Custom-0 slot, verified free by grepping every existing
         // $is_veda_* decode condition in this file before choosing it.
         // rs2 = Base directly (no packed descriptor); Length/Perms come
         // from $veda_attr (defined further below), not from rs2.
         $is_veda_odt_populate_fast = $op_is_custom0 && ($funct3 == 3'b000) && ($funct7 == 7'b0000100);
         // ─────────────────────────────────────────────────────────
         //  RTL-6c (DESIGN_02 Phase 2, increment 2): the PAGE-OUT /
         //  PAGE-IN pair. funct7 0b0000101, split on funct3 by operand
         //  shape exactly as Populate (000) and Destroy (001) already
         //  split 0b0000011.
         //
         //  The slot was verified free INDEPENDENTLY of Sail by
         //  enumerating every $op_is_custom0 decode in this file: funct7
         //  0000000 (OCL, OCL.C), 0000001 (OCS, OCS.C), 0000010 (NMC.W/.D),
         //  0000011 (Populate, Destroy), 0000100 (Populate-Fast). Nothing
         //  uses 0000101. The one 7'b0000101 literal elsewhere in the file
         //  is CGetAddr under Custom-2, a different opcode.
         //
         //  KNOWN DIVERGENCE, recorded rather than hidden: Sail's page-out
         //  encoding hardwires the rs2 field to 0b00000, so an encoding
         //  with rs2 != 0 does not match and Sail raises Illegal. The RTL
         //  decode idiom tests only opcode/funct3/funct7, so it accepts a
         //  wider encoding here. That is inherited from ODT-Destroy, which
         //  has the identical asymmetry, not introduced by this increment.
         $is_veda_odt_page_out = $op_is_custom0 && ($funct3 == 3'b001) && ($funct7 == 7'b0000101);
         // RTL-17: the POLICY write path. Two-register form (rs2 = new domain,
         // rs1 = Object_ID) in the same funct3=001 family as Destroy and
         // page-out, on the first free funct7.
         $is_veda_odt_set_domain = $op_is_custom0 && ($funct3 == 3'b001) && ($funct7 == 7'b0000110);
         // RTL-18: the second policy field. A SEPARATE instruction rather than a
         // field selector -- a selector would put the set of writable fields in
         // a software register; separate opcodes keep it fixed in the decoder.
         $is_veda_odt_set_cow = $op_is_custom0 && ($funct3 == 3'b001) && ($funct7 == 7'b0000111);
         $is_veda_odt_page_in  = $op_is_custom0 && ($funct3 == 3'b000) && ($funct7 == 7'b0000101);

         $op_is_custom1   = ($opcode == 7'b0101011);
         // Op-select (funct7[31:27]) reuses real RISC-V Zaamo's own
         // encoding verbatim -- VEDA_CORE_SPEC.md Section 1's own text
         // already names the identical operation set, and this project's
         // established practice throughout is to reuse a real, verified
         // encoding wherever the concept transfers directly, not invent
         // new bit values (the same reasoning already applied when this
         // same op-select table was built once already in Sail
         // Milestone V-B). aq/rl (funct7[26:25]) are real, named signals
         // below, matching Sail's own identical decoded-but-unused
         // treatment (veda_atomic_insts.sail's own `_aq`/`_rl`
         // underscore-prefixed parameters) -- fixed this security-audit
         // pass: an earlier version of this comment claimed they were
         // "decoded" when no RTL signal here actually captured them at
         // all, a real documentation/code mismatch caught by direct
         // inspection, not assumed correct from the comment alone. Left
         // unused deliberately -- this core is genuinely single-hart,
         // in-order, with no reordering of memory operations relative
         // to program order ever possible, so aq/rl are trivially
         // satisfied regardless of their value (RVWMO reduces to
         // program order on one hart), not a silently-ignored real
         // ordering requirement. See ATOMIC_AQRL_SAFETY_ANALYSIS.md for
         // the full reasoning and the explicit, load-bearing warning for
         // whoever eventually builds real multi-hart RTL.
         $veda_atomic_aq = $instr[26];
         $veda_atomic_rl = $instr[25];
         `BOGUS_USE($veda_atomic_aq)
         `BOGUS_USE($veda_atomic_rl)
         $veda_atomic_op[4:0] = $instr[31:27];
         // Width scoped to D (64-bit) only this milestone, matching the
         // established D-only precedent already used for OCL.D/OCS.D and
         // Sail's own Veda-Atomic scope.
         // R30: the op-select field was never tested. Sail's encdec_veda_atomicop
         // (veda_atomic_insts.sail:47-57) allocates exactly these nine of the
         // thirty-two, and the two aq/rl bits are don't-care. Verified value by
         // value against $veda_atomic_result's own arms below, which is where
         // the RTL's real allocation lives.
         $veda_atomic_op_known = ($veda_atomic_op == 5'b00001) || ($veda_atomic_op == 5'b00000) ||
                                 ($veda_atomic_op == 5'b00100) || ($veda_atomic_op == 5'b01100) ||
                                 ($veda_atomic_op == 5'b01000) || ($veda_atomic_op == 5'b10000) ||
                                 ($veda_atomic_op == 5'b10100) || ($veda_atomic_op == 5'b11000) ||
                                 ($veda_atomic_op == 5'b11100);
         $is_veda_atomic  = $op_is_custom1 && ($funct3 == 3'b011) && $veda_atomic_op_known;

         $is_veda_nmc_add_w = $op_is_custom0 && ($funct3 == 3'b010) && ($funct7 == 7'b0000010);
         $is_veda_nmc_add_d = $op_is_custom0 && ($funct3 == 3'b011) && ($funct7 == 7'b0000010);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: ODT lookup for Object-Bind, by Object_ID read
         //  from the GPR named by $rs1. Milestone 1's 256-entry ODT
         //  (MILESTONE_PLAN.md item 1) indexes on only the low 8 bits of
         //  the real 23-bit Object_ID field -- a real, stated scope
         //  boundary, not silent truncation.
         // ─────────────────────────────────────────────────────────
         $veda_object_id[43:0] = $rs1_data[43:0];
         // MILESTONE 24 Stage 2: judged on the FULL 23-bit Object_ID
         // above, NOT the truncated low-8-bit $veda_odt_idx below -- a
         // TCM-tier placement decision must never be judged on the
         // already-aliased index, or a DRAM-tier object sharing the same
         // low byte as a TCM-tier one could be misclassified, the exact
         // class of bug Milestone 15 (below) already found and fixed for
         // ODT lookups generally. This must not reintroduce a variant of
         // it for latency classification specifically.
         // ─────────────────────────────────────────────────────────
         //  RTL-4 (DESIGN_08): domain-segmented Object_ID. Mirrors Sail's
         //  veda_odt_index / veda_odt_base_of (veda_regs.sail:487-522).
         //  The 44-bit Object_ID is TWO fields: an outer protection domain
         //  and an inner object name within it.
         // ─────────────────────────────────────────────────────────
         $veda_region[19:0] = $veda_object_id[43:24];
         $veda_local[23:0]  = $veda_object_id[23:0];
         // The CRBR fast path. If the object lives in the domain we are
         // already executing in, its ODT base is ALREADY in the CRBR, so no
         // Region-Table read is needed and an intra-domain bind stays at
         // exactly ONE memory read -- no regression from the pre-DESIGN_08
         // single flat table (DESIGN_08 Section 4).
         $veda_intra_region = ($veda_region == $veda_current_region);
         // MILESTONE 24 Stage 2, re-stated for RTL-4: the TCM-tier decision
         // is judged on `local` AND intra-domain residency -- never on the
         // truncated low-8-bit index, and no longer on the raw 44-bit
         // Object_ID either. Judged on the raw ID, a region-1 object with a
         // small local would fail the < 32 test purely because its region
         // bits make the number large; judged on `local` alone, a region-1
         // object with local < 32 would be wrongly called TCM-tier even
         // though the TCM holds only the CURRENT domain's low entries.
         // Provably a no-op on the whole existing corpus: every one of its
         // 88 Object_IDs is region 0, region 0 is the current region, so
         // $veda_intra_region is 1 and $veda_local equals the full
         // Object_ID -- the expression is identical to its pre-RTL-4 form
         // for every test that asserts a cycle count.
         $veda_odt_tcm_hit = $veda_intra_region && ($veda_local < {18'b0, TCM_ODT_ENTRIES[5:0]});
         // RT_ENTRIES is 8, so this comparison needs FIVE bits, not three:
         // RT_ENTRIES[2:0] would be 3'b000 and every region would read as
         // out-of-window. Widened deliberately to [7:0] so a future
         // RT_ENTRIES up to 255 cannot silently re-create that bug -- the
         // exact missed-width class that cost RTL-3 four silent bugs.
         $veda_region_in_window = ($veda_region < {12'b0, RT_ENTRIES[7:0]});
         // The observable that proves the fixed-shape one-read property.
         // Nothing consumes it yet (the cross-region read's LATENCY is not
         // charged this increment, see the DRAM stall comment above), but a
         // testbench probes it to assert that an intra-domain bind reads the
         // RT exactly 0 times and a cross-domain bind exactly 1 -- the
         // difference between a single architectural register and a cache.
         $veda_rt_read_en = ($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind ||
                             $is_veda_odt_populate || $is_veda_odt_populate_fast || $is_veda_odt_destroy ||
                             // RTL-6c: the paging pair resolves through the
                             // same Region Table, so it must be enumerated
                             // here too. Purely observational (behind
                             // BOGUS_USE), which is exactly why omitting it
                             // would be invisible -- no functional failure,
                             // just a probe that under-reports.
                             $is_veda_odt_page_out || $is_veda_odt_page_in)
                            && !$veda_intra_region;
         // Resolve the region's ODT base -- CRBR if intra-domain, else the
         // RT. rt_*[$veda_region[2:0]] truncates to 3 bits, which is safe
         // ONLY because $veda_region_in_window already guarantees the region
         // is below RT_ENTRIES=8; out-of-window regions take the 32'b0 arm
         // and are rejected by the residency gate below, never indexed.
         $veda_region_base[31:0] = $veda_intra_region ? $veda_current_odt_base :
                                    ($veda_region_in_window ? rt_odt_base[$veda_region[2:0]] : 32'b0);
         // ENTRY units. The base is added to local in ENTRIES, and the
         // ODT_ENTRY_BYTES stride is applied exactly ONCE, below -- Sail's
         // `idx = unsigned(veda_odt_base_of(region)) + lu` (veda_regs.sail
         // :519). Multiplying the base by the stride here as well would
         // shift every non-zero-base region by 32x, silently.
         $veda_odt_entry_idx[31:0] = $veda_region_base + {24'b0, $veda_local[7:0]};
         // Bound the RESOLVED index, mirroring Sail's `if idx <
         // VEDA_ODT_MODELED_ENTRIES then Some(idx) else None()`
         // (veda_regs.sail:520). Region 0 provably cannot trip this
         // (base 0 + [0,256) < 768), so this is not a corpus concern -- it
         // is the guard against a MIS-PROGRAMMED region base pointing
         // outside the array, whose blast radius is region-wide.
         $veda_odt_idx_ok = ($veda_odt_entry_idx < {16'b0, ODT_ENTRIES[15:0]});
         $veda_odt_idx[7:0]    = $veda_local[7:0];
         // Clamp to entry 0 when out of bounds so the physical array read
         // stays in range and never returns X. $veda_odt_idx_ok, folded into
         // $veda_odt_valid below, is what makes the result ARCHITECTURALLY
         // not-found -- the clamp is only about not reading garbage.
         //
         // The stride now references ODT_ENTRY_BYTES instead of a bare
         // 32'd32. That literal was Mutation W's whole hazard in RTL-3:
         // bumping the localparam while the stride stayed at 16 took the
         // suite from 58 passing to 14 with no compile diagnostic anywhere.
         // Referencing the parameter removes the hazard rather than relying
         // on a checklist to remember it.
         $veda_odt_addr[31:0]  = ODT_BASE + (($veda_odt_idx_ok ? $veda_odt_entry_idx : 32'b0)
                                             * {24'b0, ODT_ENTRY_BYTES[7:0]});
         // $veda_odt_idx_ok is also consumed by the trailing raw \SV
         // always_ff (Populate/Destroy), and $veda_rt_read_en is consumed
         // only by a hierarchical testbench probe -- both invisible to
         // SandPiper's TLV-level dependency tracking, same reason
         // $veda_owner_claim_en already needs this below.
         `BOGUS_USE($veda_odt_idx_ok)
         `BOGUS_USE($veda_rt_read_en)
         $veda_odt_base[55:0]   = {odt_mem[$veda_odt_addr+6], odt_mem[$veda_odt_addr+5], odt_mem[$veda_odt_addr+4], odt_mem[$veda_odt_addr+3], odt_mem[$veda_odt_addr+2], odt_mem[$veda_odt_addr+1], odt_mem[$veda_odt_addr+0]};
         $veda_odt_length[39:0] = {odt_mem[$veda_odt_addr+11], odt_mem[$veda_odt_addr+10], odt_mem[$veda_odt_addr+9], odt_mem[$veda_odt_addr+8], odt_mem[$veda_odt_addr+7]};
         $veda_odt_perms[15:0]  = {odt_mem[$veda_odt_addr+13], odt_mem[$veda_odt_addr+12]};
         $veda_odt_gen[23:0]    = {odt_mem[$veda_odt_addr+16], odt_mem[$veda_odt_addr+15], odt_mem[$veda_odt_addr+14]};
         // RTL MILESTONE 15: the low-8-bit ODT index above aliases any
         // two Object_IDs sharing a low byte onto the same physical
         // slot -- found via a real empirical reproduction
         // (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 1), not a
         // theoretical concern: Object_ID=100 and Object_ID=356
         // silently overwrote each other's ODT metadata with no trap,
         // no error, no signal to either party. Bytes +11/+12 of the
         // 16-byte entry were real, allocated-but-unused space ("88
         // bits used of 128 available", per this file's own header
         // comment above) -- store the real upper 15 bits of Object_ID
         // there on every Populate (below), and require it to match on
         // every lookup here. A low-byte collision with a DIFFERENT
         // real Object_ID now reads as "not found" (folded into
         // $veda_odt_valid itself, so every existing downstream
         // consumer -- owner_ok, bind_trap, rebind_ok -- inherits the
         // fix with no other change needed) instead of silently
         // returning a different object's metadata.
         // RTL-3: id_hi is 36 bits now -- Object_ID[43:8] -- so the anti-alias tag
         // covers the FULL 44-bit namespace. Sail bounds the index instead
         // (a flat vector(2^44) will not compile there); RTL is a 256-entry
         // direct-mapped table with a hi-tag, so it mirrors the PROPERTY (no two
         // Object_IDs may alias one slot) rather than Sail's MECHANISM, at the
         // true width, for 3 extra bytes in an entry with 7 spare.
         //
         // RTL-4: the tag stays at 36 bits, Object_ID[43:8], and that is a
         // PROOF, not an omission. Two Object_IDs alias iff entry(A) ==
         // entry(B), where entry(X) = region_base(region(X)) + local(X)[7:0].
         // Every region_base is a multiple of ODT_REGION_ENTRIES = 256 and
         // local[7:0] is in [0,256), so region_base is exactly the window
         // number x 256 and local[7:0] is exactly the offset inside it.
         // Therefore entry(A) == entry(B) iff they land in the same window
         // AND agree on bits [7:0] -- which means two DIFFERENT Object_IDs
         // that collide must differ somewhere in [43:8], which is precisely
         // what the tag covers. Index bits and tag bits stay exactly
         // complementary and jointly total over all 44 bits, as before.
         //
         // This also holds in the pathological case DESIGN_08 warns about:
         // if two distinct regions were MIS-PROGRAMMED to the same
         // region_odt_base, they would land in the same window -- but the
         // region occupies [43:24], which is inside [43:8], so the tag still
         // differs and the lookup reads not-found. The 36-bit tag is the
         // ONLY backstop in the design against RT mis-programming, which is
         // the reason to keep it at full width rather than narrowing it to
         // the local-only [23:8]. The converse is a trap worth naming: it
         // must NOT be narrowed to just the region field [43:24] either,
         // because 32 and 288 share region 0 and that alone would silently
         // break veda_smoke_m15_neg.S's deliberate alias detection.
         $veda_odt_id_hi[35:0] = {odt_mem[$veda_odt_addr+24], odt_mem[$veda_odt_addr+23], odt_mem[$veda_odt_addr+22], odt_mem[$veda_odt_addr+21], odt_mem[$veda_odt_addr+20]};
         $veda_odt_id_match    = ($veda_odt_id_hi == $veda_object_id[43:8]);
         // $veda_odt_idx_ok mirrors Sail's None() arm (veda_regs.sail:520 ->
         // odt_lookup:532 -> empty_odt_entry): an unresolvable index is
         // architecturally not-found, and every existing downstream consumer
         // (owner_ok, bind_trap, rebind_ok) inherits it with no other change.
         $veda_odt_valid        = $veda_odt_idx_ok && odt_mem[$veda_odt_addr+17][0] && $veda_odt_id_match;
         // Milestone 12: the owner-hart byte, read alongside every other
         // ODT field above -- an object with no live owner yet
         // (VEDA_OWNER_UNOWNED), or one this same hart already owns, is
         // fair game for Bind/Rebind to claim (or re-claim, idempotently)
         // -- mirrors veda_bind_insts.sail's own `owner_ok` boolean
         // field-for-field.
         $veda_odt_owner[7:0]  = odt_mem[$veda_odt_addr+18];
         $veda_owner_ok        = ($veda_odt_owner == VEDA_OWNER_UNOWNED) || ($veda_odt_owner == MHARTID);
         // RTL MILESTONE 16: the 8-bit generation counter, empirically
         // confirmed to wrap after 256 destroy/re-populate cycles on the
         // same slot, creates a real ABA-problem use-after-free false
         // negative (a capability cached before the wrap can pass the
         // staleness check again once the count wraps back to its old
         // value) -- ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2,
         // reproduced empirically before any fix was designed. Simply
         // saturating the counter at 0xFF instead of wrapping is NOT
         // sufficient by itself -- every future re-populate of the slot
         // would then also land on 0xFF, making every incarnation from
         // that point on indistinguishable from every other, a
         // *permanent* ambiguity instead of a periodic one. The real fix
         // needs a second bit: once generation would wrap, PERMANENTLY
         // retire the slot (refuse any future ODT-Populate against it)
         // instead of reusing 0xFF forever. (RTL-6 correction: the rest of
         // this comment used to say retired "uses 1 bit of byte +13" after
         // Milestone 15's use of "+11/+12". Every one of those offsets is
         // wrong against the code directly below it and has been since
         // RTL-3 -- retired is at +19, +13 is Perms[15:8], and id_hi is at
         // +20..+24. The counter is 24 bits, not 8, and saturates at
         // 0xFFFFFF. Corrected rather than deleted because a future reader
         // hunting spare bytes by comment would have written into Length
         // and Perms.)
         $veda_odt_retired     = odt_mem[$veda_odt_addr+19][0];
         // ─────────────────────────────────────────────────────────
         //  RTL-6 (DESIGN_02 Phase 2, increment 1): per-OBJECT residency.
         //  Mirrors Sail's odt_entry.resident (veda_types.sail:301).
         //
         //  NAME COLLISION WARNING, and it is a genuine one. This is NOT
         //  $veda_region_resident (below) and NOT rt_resident[]. Those ask
         //  "is this DOMAIN's table paged in" and produce cause 0x09. This
         //  asks "is this OBJECT's storage paged in" and produces 0x0A.
         //  Sail keeps the two deliberately distinct and says so at the
         //  field declaration; the names here are as far apart as the
         //  established $veda_odt_* / $veda_region_* prefixes allow.
         $veda_odt_resident    = odt_mem[$veda_odt_addr+ODT_OFF_RESIDENT][0];
         $veda_odt_cow = odt_mem[$veda_odt_addr+ODT_OFF_COW][0];
         $veda_odt_owner_domain[19:0] = {odt_mem[$veda_odt_addr+ODT_OFF_OWNER_DOMAIN+2][3:0],
                                          odt_mem[$veda_odt_addr+ODT_OFF_OWNER_DOMAIN+1],
                                          odt_mem[$veda_odt_addr+ODT_OFF_OWNER_DOMAIN]};
         // Milestone 12: plain Bind's own real, genuine hard-trap --
         // a LIVE object owned by a genuinely different hart, distinct
         // in kind from "object not found" (Milestone 13, below). Joins
         // the combined trap-taken family below. Bind-NoTrap never
         // participates here at all (matches its own established
         // soft-fail-always convention; only plain Bind is gated by
         // $is_veda_bind_plain), mirroring veda_bind_insts.sail's own
         // exact mode split.
         $veda_bind_owner_violation = $is_veda_bind_plain && $veda_odt_valid && !$veda_owner_ok;
         // Milestone 13: plain Bind's own second real hard-trap reason --
         // object-not-found ($veda_odt_valid=0) -- closing the gap
         // Milestone 9 itself named and deliberately deferred
         // (MILESTONE_9_RESULTS.md: "doing so would, for the first time,
         // make RTL's plain Bind and Bind-NoTrap behaviorally different"
         // -- a concern Milestone 12 already made moot, since plain
         // Bind's own owner-violation trap above already created that
         // exact divergence). Mutually exclusive with
         // $veda_bind_owner_violation by construction (one requires
         // $veda_odt_valid, the other requires !$veda_odt_valid) --
         // combined into one umbrella $veda_bind_trap below, mirroring
         // veda_bind_insts.sail's own catch-all else-chain exactly
         // (owner check, THEN object-not-found, mutually exclusive
         // outcomes of the same `e.valid` test).
         // RTL-14: a Bind that fails must hand back NOTHING, not a tagless copy
         // of someone else's descriptor. Bind-NoTrap exists to be a SILENT
         // probe, which is exactly what makes leaking through it worse than
         // through a trapping instruction -- there is no fault to notice.
         $veda_bind_ok = $veda_odt_valid && $veda_owner_ok;
         // ═══ RTL-17: PER-OBJECT BIND AUTHORITY ═══
         //
         // The object itself says who may bind it. Three ways to pass: it is
         // OPEN (how every object is created, so this changes nothing until
         // software narrows one); the caller is in no compartment at all (boot
         // and trap handlers -- the bootstrap and the pager); or the domains
         // match.
         //
         // PER-OBJECT, NOT PER-REGION, and that is the lesson of the retracted
         // R17. A region-granular rule broke the RETURN PATH: a compartment's
         // caller lives in another domain by definition, so forbidding
         // cross-domain Bind made compartments one-way and livelocked a test.
         // Here the return object is left open while its neighbours are
         // narrowed -- which is what legitimate sharing looks like.
         //
         // Subject is $veda_pcc_object, never $veda_current_region: that
         // register is zero at reset and reset again on every trap, and region
         // zero is ALSO a real domain, so "no domain" and "domain 0" would be
         // one value.
         //
         // GATED ON $veda_odt_valid, and that term is a Sail-parity
         // requirement rather than an optimisation. The model reads a
         // not-found lookup as the empty entry, whose owner_domain is ANY, so
         // it passes the gate and falls through to the not-found trap. This
         // core would instead read whatever bytes occupy the slot, and could
         // refuse with the wrong cause. Same property, different mechanism,
         // so the term has to be explicit here.
         // RTL-18: a store reached a copy-on-write object. Read from the ENTRY,
         // never from the capability's permissions: set.cow does not bump the
         // generation, so capabilities minted BEFORE the object became
         // copy-on-write are still live and still carry store permission --
         // and at fork() the parent holds exactly such a capability, which is
         // the first one that will be written.
         $veda_cow_write = $veda_check_odt_cow;
         $veda_bind_domain_ok = ($veda_odt_owner_domain == VEDA_DOMAIN_ANY) ||
                                 ($veda_pcc_object == VEDA_OBJECT_NONE) ||
                                 ($veda_odt_owner_domain == $veda_pcc_object[43:24]);
         $veda_domain_violation = ($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind)
                                   && $veda_odt_valid && !$veda_bind_domain_ok;
         $veda_bind_notfound_violation = $is_veda_bind_plain && !$veda_odt_valid;
         $veda_bind_trap = $veda_bind_owner_violation || $veda_bind_notfound_violation;
         $veda_bind_cause[4:0] = $veda_bind_owner_violation ? 5'h06 : 5'h05;
         // ─────────────────────────────────────────────────────────
         //  RTL-4 (DESIGN_08): the REGION RESIDENCY GATE and
         //  VEDA_CAUSE_REGION_FAULT (0x09). Mirrors veda_bind_insts.sail
         //  :86 and :139-150 -- placed textually BEFORE the ODT-lookup
         //  consumers, matching Sail's gate preceding odt_lookup.
         // ─────────────────────────────────────────────────────────
         //  The current region is resident BY CONSTRUCTION -- you cannot be
         //  executing in a domain whose table is not present
         //  (veda_regs.sail:500). An out-of-window region is not modeled and
         //  is therefore not resident (veda_regs.sail:503). Everything else
         //  is resident iff its RT entry says so.
         $veda_region_resident = $veda_intra_region ? 1'b1 :
                                  ($veda_region_in_window && rt_valid[$veda_region[2:0]]
                                                          && rt_resident[$veda_region[2:0]]);
         //  THE THREE-MODE OR IS LOAD-BEARING, and it deliberately does NOT
         //  copy the $is_veda_bind_plain gating used by the two violations
         //  above. veda_bind_insts.sail:145-147 states in as many words that
         //  this is a hard trap for ALL bind modes. The reason is a security
         //  one, not a symmetry one: a paged-out region is a RECOVERABLE,
         //  serviceable event -- the handler pages the domain's ODT in and
         //  retries. If Bind-NoTrap merely soft-failed with a cleared Tag,
         //  and Rebind merely cleared Tag, the pageable region would be
         //  misreported as "object not found", the pager would never be
         //  invoked, and a perfectly live object would look permanently
         //  destroyed. This knowingly narrows this file's own longstanding
         //  "Rebind never hard-traps for ANY reason" invariant -- the first
         //  condition ever to do so -- which is recorded here rather than
         //  left to be discovered.
         $veda_region_fault = ($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind)
                              && !$veda_region_resident;
         // ─────────────────────────────────────────────────────────
         //  RTL-6: the OBJECT residency gate, VEDA_CAUSE_RESIDENCY_FAULT
         //  (0x0A). Mirrors veda_bind_insts.sail's `if e.valid &
         //  not(e.resident) then veda_trap(rd, RESIDENCY_FAULT)`, placed
         //  BEFORE the mode match so it hard-traps all three bind modes.
         //
         //  THE THREE-MODE OR copies $veda_region_fault above and
         //  deliberately NOT the $is_veda_bind_plain gating used by
         //  $veda_bind_owner_violation and $veda_bind_notfound_violation.
         //  Same security argument, one level down: a paged-out OBJECT is
         //  a recoverable, serviceable event. If Bind-NoTrap soft-failed
         //  with a cleared Tag and Rebind merely cleared Tag, a live
         //  object would be misreported as destroyed and the pager would
         //  never run. Copying the wrong neighbour here is silent.
         //
         //  THE $veda_odt_valid CONJUNCT IS LOAD-BEARING and is what keeps
         //  0x05 outranking 0x0A. A never-populated slot reads valid=0 AND
         //  resident=0 (both from the pre-zero). Without this conjunct it
         //  would report "paged out" for an object that never existed --
         //  telling a pager to fetch something with no backing anywhere.
         //  Sail spells the same conjunct explicitly for the same reason.
         $veda_residency_fault = ($is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind)
                                 && $veda_odt_valid && !$veda_odt_resident;

         // ─────────────────────────────────────────────────────────
         //  RTL Milestone 8: Rebind reads its OWN destination register
         //  (rd, not rs1) as its "current capability" input -- needed
         //  to check whether rd is already sealed (veda_types.sail:
         //  isSealedCap(c) = c.otype != 0xFFFF), matching Sail's exact
         //  rule (VEDA_CORE_SPEC.md Section 4/Section 1's manipulate-
         //  vs-use split): a Rebind targeting an already-sealed
         //  capability register soft-fails (Tag cleared, ODT refresh
         //  skipped) rather than trapping, joining OCA/CSetBounds's own
         //  soft-fail family. $veda_object_id/$veda_odt_* above already
         //  serve as Rebind's ODT lookup too (Sail computes `object_id`
         //  and `odt_lookup` identically for every bind mode, branching
         //  only afterward) -- no separate ODT read needed here.
         // ─────────────────────────────────────────────────────────
         $veda_rdcap_otype[15:0] = /vreg[$veda_rd_cap]$otype;
         $veda_rebind_sealed     = ($veda_rdcap_otype != 16'hFFFF);
         // Milestone 12: a wrong-owner ODT entry joins "sealed rd" and
         // "ODT miss" as a THIRD soft-fail reason for Rebind -- Rebind
         // never hard-traps for ANY failure reason (Section 1's
         // manipulate-vs-use split), matching veda_bind_insts.sail's own
         // VEDA_REBIND match arm, which folds all three into the same
         // uniform soft-fail branch.
         $veda_rebind_ok         = !$veda_rebind_sealed && $veda_odt_valid && $veda_owner_ok;
         // Milestone 12: real claim/re-claim write-back, shared by both
         // Bind's and Rebind's own success paths below -- mirrors
         // veda_bind_insts.sail's own `claimed_entry`, written on every
         // successful Bind/Bind-NoTrap/Rebind regardless of whether
         // owner_hart was already MHARTID or VEDA_OWNER_UNOWNED (an
         // idempotent re-claim is still a real write, matching Sail
         // exactly). Deliberately excludes plain Bind's own hard-trap
         // path ($veda_bind_owner_violation, defined further below) --
         // mutually exclusive by construction, since that path requires
         // !$veda_owner_ok while this one requires $veda_owner_ok.
         $veda_bind_claim_en     = ($is_veda_bind_plain || $is_veda_bind_notrap) &&
                                    $veda_odt_valid && $veda_owner_ok;
         $veda_rebind_claim_en   = $is_veda_rebind && $veda_rebind_ok;
         // RTL-4: gate the claim on the region fault too. This one is NOT
         // defensive -- it is reachable. The gate fires on residency, before
         // the lookup, so the resolved slot can legitimately hold a valid,
         // id_hi-matching, unowned entry (region 2's seed is exactly that),
         // which makes $veda_bind_claim_en true. Without this term a
         // region-faulting Bind would still write MHARTID into the ODT's
         // owner byte -- a trapping instruction silently taking ownership of
         // an object in a domain it was just refused access to. The write
         // lives in the trailing raw \SV always_ff behind BOGUS_USE, so it
         // is invisible to TLV-level dependency review; found by tracing the
         // consumer, not by reading this line.
         // RTL-6 adds !$veda_residency_fault for the identical reason one
         // level down. A paged-out object is still valid and still
         // id_hi-matching and still unowned, so $veda_bind_claim_en is
         // true for it. Without this term a residency-faulting Bind takes
         // ownership of an object it was just refused. Worse than the
         // region case: ownership is the thing page-in is specified to
         // PRESERVE, so a stolen owner byte would survive the whole paging
         // cycle and outlive the fault that created it.
         $veda_owner_claim_en    = ($veda_bind_claim_en || $veda_rebind_claim_en)
                                    && !$veda_region_fault
                                    && !$veda_residency_fault;
         // Only consumed by the trailing raw \SV always_ff block below,
         // the same real reason $veda_odtpd_new_gen/etc. already needed
         // this (invisible to SandPiper's own TLV-level dependency
         // tracking otherwise).
         `BOGUS_USE($veda_owner_claim_en)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 4: ODT-Populate/ODT-Destroy
         //  (VEDA_CORE_SPEC.md Section 5.1's real, decided encoding and
         //  data model, mirrored field-for-field from the already-working
         //  Sail implementation, veda_ocl_insts.sail's own
         //  VEDA_ODT_POPULATE/VEDA_ODT_DESTROY). rs1 = Object_ID -- the
         //  exact same GPR-to-index computation Object-Bind's own lookup
         //  above already performs, so $veda_odt_addr/$veda_odt_valid/
         //  $veda_odt_gen/$veda_odt_base/$veda_odt_length/$veda_odt_perms
         //  above ARE this instruction's own "old_entry" read -- reused
         //  directly, not recomputed.
         //
         //  Gated on $priv, not a capability check -- Section 5.1's own
         //  stated, honest deviation (no spare R-type operand for a
         //  capability-authority operand), realized here as
         //  MILESTONE_PLAN.md's Milestone 4 addendum's real $priv gate:
         //  a violation suppresses the odt_mem write below exactly like
         //  every other soft-fail in this file (no trap infrastructure to
         //  raise a real Illegal_Instruction() into, the identical real
         //  constraint Sail itself has none of here either -- Sail's own
         //  version genuinely traps because Sail has real privilege/trap
         //  machinery; this RTL's honest floor is "the write doesn't
         //  happen").
         // ─────────────────────────────────────────────────────────
         // RTL Milestone 11: an OR, not a replacement -- ordinary M-mode
         // privilege still always suffices on its own (unchanged from
         // Milestone 4), and a live, unsealed, PERMIT_ACCESS_SYSTEM_
         // REGISTERS-carrying capability delegated into the ODA (via
         // OSpecialRW, below) is now a second, independent, real
         // authorization path -- closing NEXT_STEPS_ROADMAP.md §2.5's
         // own named gap ("a real capability-permission-gated version
         // would need Veda-Core's own privileged-capability model
         // designed first"). $veda_oda_authorized is defined further
         // below (after $veda_rs1cap_* it depends on) but referenced
         // here -- a real forward reference, the same combinational-
         // elaboration-is-order-independent pattern already used
         // throughout this file (e.g. $veda_trap_taken referencing
         // per-family violation signals defined later in the file).
         // RTL MILESTONE 16 (continued): a retired slot can never be
         // re-populated -- folded into the SAME $veda_odt_populate
         // _violation signal that already gates privilege, so it reuses
         // the established soft-no-op-on-violation write path with no
         // new plumbing.
         // RTL Milestone 18: shares this same violation signal with
         // VEDA_ODT_POPULATE_FAST (identical privilege/retired gate on
         // both, mirroring Sail's own two execute clauses, which each
         // repeat the identical check rather than sharing a helper).
         // ─────────────────────────────────────────────────────────
         //  RTL-9 (R11(b), DESIGN_07 Tier H): YOU MAY NOT EVICT THE CODE
         //  YOU ARE RUNNING.
         //
         //  Instruction fetch compares the PC against PCC's CACHED Base and
         //  Length and never re-reads the ODT, so the crossing checks of
         //  RTL-7 cannot help once execution is already inside an object.
         //  PCC now carries the object's NAME, and the entry-changing
         //  instructions refuse on it -- one 44-bit compare, on a cold path,
         //  instead of a table read on every fetch.
         //
         //  THE SAVED NAME COUNTS TOO, while a return is owed. That is only
         //  safe because RTL-8's OCRETURN-abandon releases it: a switcher
         //  that walks away from a compartment drops the frame, so the pin
         //  is released by the very act of abandoning. Without that, a
         //  scheduler could pin a code object forever -- denial of
         //  revocation.
         //
         //  THE COMPLETE CONSUMER SET, enumerated from the decoder rather
         //  than by example: every instruction that can change an entry's
         //  identity or backing. That is Populate, Populate-Fast, Destroy
         //  and page-out. Page-in is NOT in the set -- it already refuses
         //  unless the object is non-resident, and an executing object is
         //  necessarily resident, so it is closed for an independent reason
         //  that predates this increment.
         //
         //  POPULATE IS IN THE SET AND IS THE ONE THAT NEARLY GOT MISSED.
         //  Repopulating a still-valid slot bumps generation AND repoints
         //  Base/Length/Perms ($veda_odtpd_new_gen below), so it does
         //  everything Destroy does and more. Refusing Destroy while
         //  leaving Populate open would not be a partial fix, it would be a
         //  BYPASSABLE one.
         //  THE COMPARISON IS BY SLOT, NOT BY NAME, AND THAT IS A REAL
         //  SAIL/RTL DIVERGENCE -- a deliberate one, because the two layers
         //  do not identify a descriptor the same way.
         //
         //  Sail resolves an entry as base(region) + the FULL 24-bit local,
         //  so name and slot are in bijection there and a name compare IS a
         //  slot compare. This file models 256 locals per region and
         //  resolves with local[7:0] only ($veda_odt_entry_idx, above), so
         //  MANY names share one slot -- Object_ID 436 and Object_ID 180
         //  land on the same 32 bytes. The id_hi tag exists to detect
         //  exactly that, but it is consulted only on the two READ paths
         //  ($veda_odt_valid, $veda_check_odt_valid); neither ODT write arm
         //  looks at it.
         //
         //  So a name compare here would have been bypassable in one
         //  instruction: destroy or repopulate Object_ID 436 while the core
         //  executes object 180, pass the pin (436 != 180), and clobber the
         //  descriptor of the code being fetched. Execute-after-free, by
         //  the exact route this increment exists to close.
         //
         //  Same region and same local[7:0] means the same entry, because
         //  entry_idx = region_base(region) + local[7:0] and equal regions
         //  give equal bases. Full-name equality implies this, so the slot
         //  compare strictly subsumes the name compare rather than
         //  replacing one guarantee with another.
         $veda_object_slot_is_pcc   = ($veda_object_id[43:24] == $veda_pcc_object[43:24]) &&
                                       ($veda_object_id[7:0]   == $veda_pcc_object[7:0]);
         $veda_object_slot_is_mepcc = ($veda_object_id[43:24] == $veda_mepcc_object[43:24]) &&
                                       ($veda_object_id[7:0]   == $veda_mepcc_object[7:0]);
         $veda_object_is_executing = $veda_object_slot_is_pcc ||
                                      (($veda_trap_depth != 8'b0) && $veda_object_slot_is_mepcc);
         //  THE PIN REFUSAL IS A SEPARATE SIGNAL FROM THE GATES IT JOINS,
         //  and that split is deliberate rather than tidiness.
         //
         //  Populate's and Destroy's PRE-EXISTING gates (privilege, ODA
         //  authority, retired) refuse SILENTLY here: they suppress the ODT
         //  write and the rd write and raise nothing. veda_smoke_m4_neg.S
         //  and veda_smoke_m11_neg.S both depend on exactly that -- they
         //  droppriv, populate, and keep executing. Sail raises
         //  Illegal_Instruction for those same gates, so the two layers
         //  already disagree about SIGNALLING here; that divergence predates
         //  this increment and is recorded separately rather than silently
         //  widened or silently inherited.
         //
         //  The pin must NOT inherit the silence. Sail's own pin refusal is
         //  Illegal_Instruction, this file's page-out and page-in refusals
         //  already trap, and the security argument is the decisive one: the
         //  whole point is that software LEARNS it may not evict the running
         //  object, so it can abandon the frame first and retry. A silent
         //  refusal tells a pager the eviction happened when it did not --
         //  which is worse than either trapping or succeeding, because the
         //  pager then reuses memory it does not own.
         // RTL-11 (R14): $veda_executing_pin_refusal used to live here as its
         // own signal, because Populate's and Destroy's violations refused
         // SILENTLY and the pin must not be silent. Now that both violations
         // trap (below), the pin term inside them is carried automatically and
         // a separate signal would be pure duplication -- two routes computing
         // the same condition, free to drift apart later.
         $veda_odt_populate_violation = ($is_veda_odt_populate || $is_veda_odt_populate_fast) &&
                                          (!($priv || $veda_oda_authorized) || $veda_odt_retired ||
                                           $veda_object_is_executing);
         // RTL-17: authority exactly as Populate/Destroy, plus a refusal on a
         // slot that holds nothing -- a policy on a non-existent object is
         // meaningless, and allowing it would let software pre-stage rules on
         // slots someone else has yet to populate.
         $veda_odt_set_domain_violation = $is_veda_odt_set_domain &&
                                           (!($priv || $veda_oda_authorized) || !$veda_odt_valid);
         $veda_odt_set_cow_violation = $is_veda_odt_set_cow &&
                                        (!($priv || $veda_oda_authorized) || !$veda_odt_valid);
         $veda_odt_destroy_violation  = $is_veda_odt_destroy  &&
                                          (!($priv || $veda_oda_authorized) ||
                                           $veda_object_is_executing);
         // ─────────────────────────────────────────────────────────
         //  RTL-6c: the paging pair's refusal conditions. Follows
         //  Destroy's authority shape, NOT Populate's -- Sail's gate is
         //  `cur_privilege == Machine | veda_oda_authorized()` with no
         //  `retired` term, and a retired slot is not special to paging.
         //
         //  PAGE-OUT refuses unless the object is live AND resident AND
         //  its generation is below the ceiling. The generation term is
         //  THE SECURITY CORE of this increment, not a bounds check.
         //  `generation` saturates at 0xFFFFFF rather than wrapping, so at
         //  the ceiling the bump becomes a silent no-op: page-out would
         //  clear residency while invalidating NOTHING, and the later
         //  page-in -- which preserves generation by design -- would
         //  restore residency at a NEW frame while every outstanding
         //  capability still matched. Each would then read and write the
         //  freed frame now owned by another object. A full
         //  use-after-free, at the exact boundary the pair exists to
         //  defend. Fail closed: if the invalidation mechanism cannot run,
         //  the operation depending on it must not proceed.
         //
         //  THE RAW COMPARISON IS DELIBERATE. $veda_odtpd_new_gen below
         //  already saturates-and-freezes, and reusing it here would be
         //  precisely wrong -- it computes the no-op instead of refusing
         //  it, and $veda_odtpd_new_retired would additionally retire the
         //  slot, which Sail's page-out preserves.
         $veda_odt_page_out_refusal = $is_veda_odt_page_out &&
                                       (!($priv || $veda_oda_authorized) ||
                                        // RTL-9 (R11(b)): first, so no future
                                        // relaxation of the gates below can open it
                                        $veda_object_is_executing ||
                                        !$veda_odt_valid ||
                                        !$veda_odt_resident ||
                                        ($veda_odt_gen == 24'hFFFFFF));
         //  PAGE-IN refuses unless the object is live AND currently paged
         //  out. The `resident` half is the security-critical one: page-in
         //  PRESERVES generation, which is what lets a returning object
         //  keep its capabilities alive. Turned against a LIVE object that
         //  same property becomes the attack -- an authorized pager could
         //  repoint a live object's Base at memory of its choosing while
         //  every outstanding capability kept validating and nothing
         //  signalled the move. Doing the same through Populate bumps
         //  generation and makes the relocation loud.
         $veda_odt_page_in_refusal  = $is_veda_odt_page_in &&
                                       (!($priv || $veda_oda_authorized) ||
                                        !$veda_odt_valid ||
                                        $veda_odt_resident);
         //  Page-out's generation bump. SATURATING, not a raw +1, and the
         //  refusal above already makes the saturation unreachable -- so
         //  this is deliberate defence in depth and the reasoning belongs
         //  on the record.
         //
         //  Mutation testing is what produced this. A mutant replacing
         //  this expression with the pre-existing saturating
         //  $veda_odtpd_new_gen SURVIVED, which is expected -- page-out
         //  requires $veda_odt_valid, so the two agree on every input
         //  page-out accepts. But examining WHY it survived showed the
         //  mutant was the better design: a raw +1 WRAPS at the ceiling,
         //  and a wrapped generation is the ABA use-after-free that
         //  Milestone 16 introduced saturation to eliminate in the first
         //  place. Saturation freezes instead, which is detectable and
         //  inert.
         //
         //  So the two mechanisms now fail in the same direction. If the
         //  refusal above is ever weakened -- and DESIGN_02 still has
         //  `cow` and `backing` to add -- the worst outcome becomes a
         //  frozen counter rather than a silently reused one. A safety
         //  argument that rests on a single gate elsewhere in the file is
         //  worth one gate's cost here.
         $veda_pageout_new_gen[23:0] = ($veda_odt_gen == 24'hFFFFFF) ? 24'hFFFFFF
                                                                     : ($veda_odt_gen + 24'd1);
         `BOGUS_USE($veda_odt_page_out_refusal)
         `BOGUS_USE($veda_odt_page_in_refusal)
         `BOGUS_USE($veda_pageout_new_gen)

         // Sail's own real rule: repopulating a still-valid slot bumps
         // generation too, not just Destroy -- a stale capability's
         // cached generation must stop matching regardless of whether
         // software destroyed the old entry first or overwrote it
         // directly. Destroy always bumps (old entry may or may not have
         // been valid; either way the slot's identity changes).
         // RTL MILESTONE 16: once already at 0xFF, freeze instead of
         // wrapping back to 0 -- the retirement write-back below (near
         // odt_mem[...+13]) is what actually stops the slot from ever
         // being reused once this point is reached.
         // RTL-3: generation is 24 bits in the widened entry, so the
         // saturate-then-retire threshold moves with the field -- 0xFFFFFF, not
         // 0xFF. The mechanism is unchanged: freeze at max, retire on the next
         // bump. Retirement ceiling goes from 255 reuses per slot to ~16.7M.
         $veda_odtpd_new_gen[23:0] = ($is_veda_odt_destroy || $veda_odt_valid) ?
                                    (($veda_odt_gen == 24'hFFFFFF) ? 24'hFFFFFF : ($veda_odt_gen + 24'd1)) : $veda_odt_gen;
         $veda_odtpd_new_retired = $veda_odt_retired ||
                                    (($is_veda_odt_destroy || $veda_odt_valid) && ($veda_odt_gen == 24'hFFFFFF));
         // Populate: Base/Length/Perms come from rs2's packed descriptor
         // (Section 5.1: Base[31:0] in bits[63:32], Length[15:0] in
         // bits[31:16], Perms[15:0] in bits[15:0]). Populate-Fast (RTL
         // Milestone 18): Base = rs2 directly (no packing -- the whole
         // real point, a clean 2-instruction `la`/`li` suffices instead
         // of a full 6-instruction `li`), Length/Perms = $veda_attr
         // (defined further below). Destroy: preserved unchanged from
         // old_entry, matching Sail's own VEDA_ODT_DESTROY exactly (only
         // valid/generation actually change).
         // RTL-3: the two populate paths now differ in REACH, matching Sail.
         // Plain populate keeps its packed single-GPR descriptor and is
         // explicitly the COMPACT form -- Base32/Length16 zero-extended into
         // the wide entry -- because Base56+Length40+Perms16 = 112 bits simply
         // cannot fit one 64-bit register. Every existing program that builds
         // a packed descriptor keeps working unchanged. Populate-Fast is the
         // WIDE form: Base at full 56 bits straight from rs2, Length40/Perms16
         // from the widened veda_attr. The limit lives visibly in the compact
         // ENCODING, not as a silent truncation of a wide value.
         $veda_odtpd_new_base[55:0]   = $is_veda_odt_populate      ? {24'b0, $rs2_data[63:32]} :
                                          $is_veda_odt_populate_fast ? $rs2_data[55:0]  : $veda_odt_base;
         $veda_odtpd_new_length[39:0] = $is_veda_odt_populate      ? {24'b0, $rs2_data[31:16]} :
                                          $is_veda_odt_populate_fast ? $veda_attr[55:16] : $veda_odt_length;
         $veda_odtpd_new_perms[15:0]  = $is_veda_odt_populate      ? $rs2_data[15:0]  :
                                          $is_veda_odt_populate_fast ? $veda_attr[15:0]  : $veda_odt_perms;
         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value/$veda_nmc_add_result_d/
         // $veda_atomic_result all needed this).
         `BOGUS_USE($veda_odtpd_new_gen)
         `BOGUS_USE($veda_odtpd_new_base)
         `BOGUS_USE($veda_odtpd_new_length)
         `BOGUS_USE($veda_odtpd_new_perms)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: Capability Register File (16 x 128-bit-equivalent
         //  fields + 1 Tag bit each), array-of-registers exactly mirroring
         //  /xreg's own real, already-proven convention below -- not a
         //  new idiom. Written only by Object-Bind this milestone (OCA/
         //  CSetBounds/CSeal/Rebind, which partially update individual
         //  fields, don't exist in RTL yet).
         // ─────────────────────────────────────────────────────────
         /vreg[15:0]
            // Two independent write sources this milestone: Bind (full
            // register write, from the ODT) and OCA. A real bug was found
            // and fixed here, caught by the Milestone 2 smoke test, not
            // assumed correct from the source alone: OCA does NOT do a
            // partial Tag+Offset-only update -- CHERI's real semantics
            // (and this project's own already-verified Sail
            // implementation, veda_cap_insts.sail's VEDA_OCA) are "rd =
            // a full copy of rs1's fields, with Offset replaced" -- an
            // *initial* RTL draft only wrote Tag+Offset, wrongly assuming
            // rd's other fields were already correct from some earlier
            // Bind. They aren't, in general (OCA's rd and rs1 are often
            // *different* registers). Fixed: OCA now copies every field
            // from $veda_rs1cap_* (the same rs1 capability already read
            // for the checks above), exactly mirroring Bind's own
            // structure but sourced from rs1 instead of the ODT.
            // RTL Milestone 8: restricted from "any $is_veda_bind" to
            // just the two modes that share this write path (plain
            // Bind + Bind-NoTrap, behaviorally identical on this RTL's
            // no-trap floor -- see the mode-decode comment above). A
            // real gap closed here: previously mode=10/11 fell through
            // to this same path too, silently mis-executing Rebind as
            // plain Bind. Rebind now has its own write path below.
            // Milestone 12/13: plain Bind's own two hard-trap reasons
            // (wrong-owner, object-not-found -- $veda_bind_trap, the
            // combined umbrella) must leave rd COMPLETELY untouched, not
            // even Tag cleared -- matches Sail exactly (veda_trap()
            // diverts control flow before wC()/wCTag() are ever called
            // on either path). Mirrors OCInvoke's own identical
            // `!violation` exclusion already established for this same
            // reason (RTL Milestone 10). Bind-NoTrap can never set
            // $veda_bind_trap (only plain Bind can), so its own two
            // soft-fail reasons below are unaffected by this exclusion.
            // RTL-4: the region fault needs its OWN exclusion here, not a
            // free ride on $veda_bind_trap. $veda_bind_trap is false by
            // construction for Bind-NoTrap (both its terms are gated on
            // $is_veda_bind_plain), so without this term a Bind-NoTrap into
            // a non-resident region would trap AND still write the full
            // /vreg entry -- architectural state mutated by an instruction
            // that did not complete.
            // RTL-6: identical argument for the OBJECT residency fault.
            // Note it cannot ride on $veda_bind_trap either, and here the
            // consequence is sharper than the region case: the fields
            // written would be read from a PAGED-OUT entry, so a
            // Bind-NoTrap would mint a live capability caching a Base
            // whose frame the pager is free to have given away.
            $bind_wr_en = (|cpu>>1$is_veda_bind_plain || |cpu>>1$is_veda_bind_notrap) &&
                          !|cpu>>1$veda_bind_trap &&
                          !|cpu>>1$veda_domain_violation &&
                          !|cpu>>1$veda_region_fault &&
                          !|cpu>>1$veda_residency_fault &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            // Rebind: a genuinely different write shape from every
            // other source in this mux -- on failure (sealed rd, or an
            // ODT miss) only Tag changes (to 0); every other field,
            // INCLUDING Offset even on success, is preserved untouched
            // (VEDA_CORE_SPEC.md Section 4: "Offset preserved across
            // relocation" -- Rebind never resets it, unlike plain
            // Bind). Gated separately per-field below via
            // $veda_rebind_ok, not folded into a single unconditional
            // $rebind_wr_en write like every other source here.
            // RTL-4: the sharpest Bind-vs-Rebind difference in this
            // increment. Rebind is architecturally trap-free everywhere else
            // -- every failure only clears Tag via $veda_rebind_ok below --
            // and a region fault is the FIRST condition under which it must
            // hard-trap and leave rd completely untouched, Tag not even
            // cleared, because Sail's residency gate precedes the
            // VEDA_REBIND match arm entirely (veda_bind_insts.sail:148-149
            // opens the else at :150 and does not close until :261). A
            // Tag-clear here would look entirely plausible and would be
            // wrong: it is the difference between "your object is gone" and
            // "your object's domain is paged out, retry after servicing".
            // RTL-6: the object residency fault is the SECOND condition
            // ever to make Rebind hard-trap, and it needs its own
            // exclusion for the same reason -- the whole point of trapping
            // rather than Tag-clearing is the difference between "your
            // object is gone" and "your object is paged out, retry after
            // servicing". A Tag-clear would tell the holder the first
            // thing when the second is true, and the pager would never
            // be invoked.
            $rebind_wr_en = |cpu>>1$is_veda_rebind &&
                            !|cpu>>1$veda_domain_violation &&
                          !|cpu>>1$veda_region_fault &&
                            !|cpu>>1$veda_residency_fault &&
                            (|cpu>>1$veda_rd_cap == #vreg);
            $oca_wr_en  = |cpu>>1$is_veda_oca &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            $candperm_wr_en = |cpu>>1$is_veda_candperm &&
                              (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 3 addition: CSetBounds/CSetBoundsExact, a third
            // independent write source, same shared $veda_rd_cap
            // position. Applies the fix already learned from OCA's own
            // real bug: copies every non-overridden field from rs1
            // ($veda_rs1cap_*), not a partial update.
            $csetbounds_wr_en = |cpu>>1$is_veda_csetbounds_either &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 6 addition: CSeal/CUnseal, a 4th/5th independent
            // write source, same shared $veda_rd_cap position. Same
            // copy-cs1-fields-then-override-one-field skeleton already
            // proven for OCA/CSetBounds -- here the one overridden field
            // is otype (cs2.Offset for CSeal, UNSEALED_OTYPE for
            // CUnseal), everything else copies from cs1 ($veda_rs1cap_*)
            // unchanged, mirroring veda_cap_insts.sail's own struct
            // literal field-for-field.
            $cseal_wr_en   = |cpu>>1$is_veda_cseal &&
                              (|cpu>>1$veda_rd_cap == #vreg);
            $cunseal_wr_en = |cpu>>1$is_veda_cunseal &&
                              (|cpu>>1$veda_rd_cap == #vreg);
            // Milestone 7 addition: OCL.C, a 6th independent write
            // source, same shared $veda_rd_cap position -- but a
            // genuinely different KIND of source from every one above:
            // OCA/CSetBounds/CSeal/CUnseal all copy fields from an
            // already-bound rs1 capability register; OCL.C's fields come
            // fresh from memory ($veda_oclc_unpacked_*), unpacked from
            // real bytes a real OCS.C (or nothing at all, if never
            // written) put there -- not from any other capability
            // register.
            $oclc_wr_en = |cpu>>1$is_veda_ocl_c && !|cpu>>1$veda_oclc_violation &&
                          (|cpu>>1$veda_rd_cap == #vreg);
            // RTL Milestone 10: OCInvoke's own write source -- a
            // genuinely different KIND of write-enable from every one
            // above: its target is NOT $veda_rd_cap (OCInvoke's own
            // encoding has no destination-capability field at all,
            // matching real CHERI's identical choice -- its outputs are
            // architecturally fixed, not instruction-selectable). Fixed
            // to index 15 (VEDA_IDC_INDEX, the same fixed target already
            // decided and verified in Sail, veda_cap_insts.sail).
            $ocinvoke_wr_en = |cpu>>1$is_veda_ocinvoke && !|cpu>>1$veda_ocinvoke_violation &&
                              (#vreg == 4'd15);
            // RTL Milestone 11: OSpecialRW's own `cd` write -- an
            // ordinary $veda_rd_cap-indexed target (real operand, unlike
            // OCInvoke's fixed index above), receiving the ODA's OWN
            // value from BEFORE this same instruction's write to it
            // (real CHERI's own CSpecialRW semantics: read-then-write,
            // not write-then-read) -- $veda_oda_tag/base/etc. below are
            // already the correct "old" values at this point, since the
            // ODA's own persistent-register update (above) only takes
            // effect on the NEXT cycle.
            $ospecialrw_wr_en = |cpu>>1$is_veda_ospecialrw && !|cpu>>1$veda_ospecialrw_violation &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            // Minimal OS kernel Milestone B: VEDA_CSEALENTRY's own write
            // source -- same shared $veda_rd_cap position, same
            // copy-cs1-fields-then-override-one-field skeleton CSeal
            // already established, but the one overridden field (otype)
            // becomes the fixed 0xFFFE constant rather than a
            // capability-derived value.
            $csealentry_wr_en = |cpu>>1$is_veda_csealentry &&
                                (|cpu>>1$veda_rd_cap == #vreg);
            // ─────────────────────────────────────────────────────
            //  RTL-5 (R10) test scaffold, explicitly temporary -- the
            //  direct mirror of Sail's own CRF seeds (veda_regs.sail's
            //  wC(Vcapno(10)/(11)/(13)) in veda_test_seed_odt).
            //
            //  A region-2 capability CANNOT be built at runtime, and that
            //  is the mechanism working rather than a test inconvenience:
            //  Bind is residency-gated, so a paged-out domain's objects
            //  cannot be bound, and every derivation instruction (OCA,
            //  CSeal, CSetBounds, CAndPerm, CSealEntry) carries the source
            //  Object_ID through unchanged. But capabilities MINTED WHILE
            //  THE REGION WAS RESIDENT can legitimately still be sitting
            //  in registers when it pages out -- residency is dynamic in
            //  the real design. These seeds model exactly that legal
            //  state, the same direct state-injection technique the
            //  wrong-owner (Object_ID 60) and near-retirement ODT seeds
            //  above already use for the same reason.
            //
            //  c12 = sealed region-2 CODE (Execute|Invoke, otype 0x0042),
            //  c13 = sealed region-2 DATA (Invoke only, matching otype),
            //  c14 = region-2 SENTRY (otype 0xFFFE, Execute). c12/c13/c14
            //  chosen because every read of them in the corpus is preceded
            //  by a write (grep-verified before choosing), so seeding them
            //  cannot disturb an existing test.
            $tag = (|cpu$reset || |cpu>>1$reset) ? ((#vreg == 11 || #vreg == 12 || #vreg == 13 || #vreg == 14) ? 1'b1 : 1'b0) :
                   // Milestone 12: Bind/Bind-NoTrap's own success now
                   // additionally requires owner_ok -- a wrong-owner
                   // live object soft-fails here exactly like an ODT
                   // miss already did (Tag cleared, same as before;
                   // Bind-NoTrap's OTHER fields still carry over from
                   // the wrong object's real ODT entry below, dead
                   // either way once Tag=0 -- the same established,
                   // accepted convention already governing every other
                   // "$bind_wr_en fires unconditionally, only Tag is
                   // gated" soft-fail path in this mux, not a new
                   // concession). Plain Bind's OWN wrong-owner case
                   // never reaches this line at all -- $bind_wr_en
                   // itself is already false then (the exclusion above).
                   // RTL-14: this same condition now gates the DATA fields too --
                   // see $veda_bind_ok below. A failed Bind-NoTrap used to write
                   // the resolved slot's Base/Length/Perms/Object_ID and clear
                   // only the Tag, and the comment there called those fields
                   // "dead either way once Tag=0". They are not dead: the
                   // capability query family is deliberately NOT tag-gated, so
                   // cgetbase after a failed probe returned the RAW PHYSICAL BASE
                   // of whatever live object occupies the slot. Sail writes
                   // zero_capability on the same failure.
                   $bind_wr_en       ? |cpu>>1$veda_bind_ok :
                   // Rebind: 1 only on the real success path (rd wasn't
                   // already sealed, AND the ODT entry is valid) --
                   // covers both soft-fail cases (sealed rd; ODT miss)
                   // with the single already-computed $veda_rebind_ok,
                   // matching Sail's own three-way match exactly.
                   $rebind_wr_en     ? |cpu>>1$veda_rebind_ok :
                   $oca_wr_en        ? |cpu>>1$veda_oca_ok :
                   $candperm_wr_en   ? |cpu>>1$veda_candperm_ok :
                   $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_ok :
                   $cseal_wr_en      ? |cpu>>1$veda_cseal_ok :
                   $cunseal_wr_en    ? |cpu>>1$veda_cunseal_ok :
                   // The memory-resident tag, not "load succeeded = 1" --
                   // this is the one real security property Milestone 7
                   // exists to prove (see the load-side comment above).
                   $oclc_wr_en       ? |cpu>>1$veda_oclc_loaded_tag :
                   // OCInvoke: 1 only on the real, already-authorized
                   // success path ($ocinvoke_wr_en itself already
                   // excludes the violation case) -- mirrors Sail's own
                   // unconditional wCTag(VEDA_IDC_INDEX, true) after
                   // every check has passed.
                   $ocinvoke_wr_en   ? 1'b1 :
                   // OSpecialRW's own `cd` = the ODA's Tag from BEFORE
                   // this instruction's own write to it.
                   $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_tag : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_tag : |cpu>>1$veda_oda_tag) :
                   $csealentry_wr_en ? |cpu>>1$veda_csealentry_ok :
                                       $RETAIN;
            // RTL-6b seed -- c11 names Object_ID 104, the reset-seeded
            // {valid, NOT resident} object, with every OTHER field built to
            // PASS: generation 0 matches the entry, unsealed, Permit_Load |
            // Permit_Store matching the entry's own Perms, Offset 0 and
            // Length 0x40 so an 8-byte access is comfortably in bounds.
            //
            // That construction is the whole point. Sail raises
            // RESIDENCY_FAULT only for an access that would OTHERWISE HAVE
            // SUCCEEDED, so a fixture that fails any earlier check would
            // report that earlier cause and prove nothing about residency's
            // position at the end of the chain. Every field here is chosen
            // to make residency the only remaining objection.
            //
            // WHY A SEED, and this is a real architectural limitation
            // rather than a testing shortcut: the dereference-side term is
            // UNREACHABLE THROUGH THE ISA. Page-out is the only producer of
            // {valid, non-resident} and it bumps generation by design, so
            // any capability held across it fails the generation check
            // (0x02) before residency is ever consulted -- and re-Binding
            // afterwards is refused by the bind-side gate. The two designs
            // agree on every reachable input; they differ only here.
            //
            // c11 was chosen because both tests that use it (m23_scheduler,
            // ssc_cross_thread) BIND it before any read, so no test depends
            // on its reset value. Verified by reading them, not assumed.
            //
            // RTL-5 (R10) seed. c12/c13 name region 2 (rt_valid=1,
            // resident=0 -- a paged-out domain); c14 names region 3
            // (rt_valid=0, resident=1 -- an unconfigured slot whose
            // resident bit is garbage-true). The two fixtures test the two
            // conjuncts of the residency check SEPARATELY: OCInvoke through
            // c12 must fail on the resident bit, OCReturn through c14 must
            // fail on rt_valid despite resident being set.
            // 33554452 = (2<<24)|20, 33554453 = (2<<24)|21,
            // 50331670 = (3<<24)|22. The region field [43:24] is all the
            // crossing gate reads -- the local half is never looked up,
            // because the gate fires before any ODT access.
            $object_id[43:0] = (|cpu$reset || |cpu>>1$reset) ?
                                 ((#vreg == 11) ? 44'd104 :
                                  (#vreg == 12) ? 44'd33554452 :
                                  (#vreg == 13) ? 44'd33554453 :
                                  (#vreg == 14) ? 44'd50331670 : 44'b0) :
                               $bind_wr_en       ? (|cpu>>1$veda_bind_ok ? |cpu>>1$veda_object_id : 44'b0) :
                               // Rebind success only -- on failure (sealed
                               // rd / ODT miss), Sail's own execute clause
                               // never calls wC() at all, so every field
                               // below except Tag must fall through to
                               // $RETAIN unchanged, not get overwritten.
                               ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_object_id :
                               // RTL-12: $candperm_wr_en was missing here too.
                               // The comment above this very mux already says
                               // "every derivation instruction (OCA, CSeal,
                               // CSetBounds, CAndPerm, CSealEntry) carries the
                               // source Object_ID through unchanged" -- the
                               // code did not, so the file contradicted its own
                               // written intent. An attenuated capability came
                               // out naming Object_ID 0, and the dereference
                               // re-check then looked up the wrong slot and
                               // reported a stale generation (0x02) for what is
                               // really a lost name.
                               ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en || $candperm_wr_en) ? |cpu>>1$veda_rs1cap_object_id :
                               $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_object_id :
                               // OCInvoke copies cs2's OWN full field set
                               // into c15 (IDC) -- a genuinely different
                               // source capability register from every
                               // other write source above, which all
                               // either come from the ODT or from cs1.
                               $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_object_id :
                               $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_object_id : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_object_id : |cpu>>1$veda_oda_object_id) :
                               $csealentry_wr_en ? |cpu>>1$veda_rs1cap_object_id :
                                                                    $RETAIN;
            $base[55:0] = (|cpu$reset || |cpu>>1$reset) ? ((#vreg == 11) ? 56'h8001_0300 : 56'b0) :
                          $bind_wr_en       ? (|cpu>>1$veda_bind_ok ? |cpu>>1$veda_odt_base : 56'b0) :
                          ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_base :
                          $oca_wr_en        ? |cpu>>1$veda_rs1cap_base :
                          $candperm_wr_en   ? |cpu>>1$veda_rs1cap_base :
                          $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_new_base :
                          ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_base :
                          $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_base :
                          $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_base :
                          $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_base : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_base : |cpu>>1$veda_oda_base) :
                          $csealentry_wr_en ? |cpu>>1$veda_rs1cap_base :
                                              $RETAIN;
            $length[39:0] = (|cpu$reset || |cpu>>1$reset) ? ((#vreg == 11) ? 40'h40 : 40'b0) :
                            $bind_wr_en       ? (|cpu>>1$veda_bind_ok ? |cpu>>1$veda_odt_length : 40'b0) :
                            ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_length :
                            $oca_wr_en        ? |cpu>>1$veda_rs1cap_length :
                            $candperm_wr_en   ? |cpu>>1$veda_rs1cap_length :
                            $csetbounds_wr_en ? |cpu>>1$veda_csetbounds_new_length :
                            ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_length :
                            $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_length :
                            $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_length :
                            $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_length : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_length : |cpu>>1$veda_oda_length) :
                            $csealentry_wr_en ? |cpu>>1$veda_rs1cap_length :
                                                $RETAIN;
            // A fresh Bind always starts at the object's own beginning
            // (VEDA_CORE_SPEC.md Section 4) -- Offset isn't sourced from
            // the ODT at all. OCA is the one instruction that moves it
            // (Section 1) -- the entire reason OCA exists. CSetBounds
            // resets it to 0 too (Section 1: "the narrowed capability's
            // cursor resets to its own new start"). CSeal/CUnseal leave
            // it unchanged (Section 1: "cd.Offset = cs1.Offset" -- sealing
            // is purely a metadata operation, the cursor doesn't move).
            // OCL.C restores whatever Offset a real OCS.C actually
            // stored (the capability's own full state at store time, not
            // reset to 0 -- a capability round-tripped through memory
            // must come back exactly as it was saved).
            // Rebind deliberately has NO branch here at all, success or
            // failure -- this is the one field Rebind never touches
            // (VEDA_CORE_SPEC.md Section 4: "Offset preserved across
            // relocation" -- the entire reason Rebind exists, distinct
            // from plain Bind's own Offset=0 reset above). Falls through
            // to $RETAIN exactly like every cycle $rebind_wr_en is false.
            // OCInvoke copies cs2's OWN Offset unchanged too -- CHERI's
            // own real unsealCap() only ever clears otype, every other
            // field (including the cursor) carries over exactly as it
            // was in the sealed capability.
            $offset[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                            $bind_wr_en       ? 40'b0 :
                            $oca_wr_en        ? |cpu>>1$veda_oca_sum[39:0] :
                            $csetbounds_wr_en ? 40'b0 :
                            $candperm_wr_en   ? |cpu>>1$veda_rs1cap_offset :
                            ($cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_offset :
                            $oclc_wr_en       ? |cpu>>1$veda_oclc_unpacked_offset :
                            $ocinvoke_wr_en   ? |cpu>>1$veda_cs2_offset :
                            $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_offset : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_offset : |cpu>>1$veda_oda_offset) :
                            $csealentry_wr_en ? |cpu>>1$veda_rs1cap_offset :
                                                $RETAIN;
            // RTL-5 (R10) seed: c12 CODE Execute|Invoke (0x0402), c13 DATA
            // Invoke-only (0x0400, deliberately NON-executable so it passes
            // OCInvoke's "data capability must not be executable" check),
            // c14 sentry Execute (0x0002). Together c12/c13 pass all NINE
            // of OCInvoke's capability checks, so the region gate is
            // provably the FIRST failure -- which is the whole point.
            $perms[15:0] = (|cpu$reset || |cpu>>1$reset) ?
                             ((#vreg == 11) ? 16'h100C :
                              (#vreg == 12) ? 16'h0402 :
                              (#vreg == 13) ? 16'h0400 :
                              (#vreg == 14) ? 16'h0002 : 16'b0) :
                           // RTL-18: a copy-on-write object never hands out store
                           // permission, however often it is bound. Handing out a
                           // store-stripped capability in software would be only
                           // advisory -- the holder could re-Bind the name and get a
                           // fresh, fully-permissioned one. 16'hFFF7 clears bit 3.
                           $bind_wr_en ? (|cpu>>1$veda_bind_ok
                                            ? (|cpu>>1$veda_odt_cow ? (|cpu>>1$veda_odt_perms & 16'hFFF7)
                                                                    : |cpu>>1$veda_odt_perms)
                                            : 16'b0) :
                           // R23 FIX: Rebind must attenuate exactly as Bind does.
                           // The comment above says "a copy-on-write object never
                           // hands out store permission, however often it is
                           // bound" -- and three lines below it, the Rebind arm
                           // handed out $veda_odt_perms verbatim with no cow test,
                           // so the file contradicted its own stated intent. Sail
                           // masks BOTH paths (veda_bind_insts.sail:308 and :341
                           // via veda_bind_perms, veda_regs.sail:822-823), so this
                           // was an RTL-only divergence. Same shape as the CAndPerm
                           // defect: a derivation arm that silently kept a right
                           // the neighbouring arm strips.
                           ($rebind_wr_en && |cpu>>1$veda_rebind_ok)
                              ? (|cpu>>1$veda_odt_cow ? (|cpu>>1$veda_odt_perms & 16'hFFF7)
                                                      : |cpu>>1$veda_odt_perms) :
                           $candperm_wr_en ? (|cpu>>1$veda_rs1cap_perms & |cpu>>1$rs2_data[15:0]) :
                           ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en) ? |cpu>>1$veda_rs1cap_perms :
                           $oclc_wr_en ? |cpu>>1$veda_oclc_unpacked_perms :
                           $ocinvoke_wr_en ? |cpu>>1$veda_cs2_perms :
                           $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_perms : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_perms : |cpu>>1$veda_oda_perms) :
                           $csealentry_wr_en ? |cpu>>1$veda_rs1cap_perms :
                                                                $RETAIN;
            // A fresh Bind always carries the UNSEALED sentinel (Section
            // 1: "otype always set to 0xFFFF... sealing only ever happens
            // explicitly via CSeal"). OCA/CSetBounds both copy otype from
            // rs1 as-is (Section 1: neither ever seals/unseals; if rs1
            // happened to be sealed, $veda_oca_ok/$veda_csetbounds_ok
            // already clear Tag separately -- the otype *field value*
            // itself still carries over unconditionally, matching
            // CHERI's own real "fields always set, tag conditionally
            // cleared" pattern already used in Sail). CSeal/CUnseal are
            // the one real exception, and the entire reason these two
            // instructions exist: CSeal sets otype = cs2.Offset (the
            // type-authority's own cursor value, the new seal); CUnseal
            // resets it back to 0xFFFF.
            // Rebind's own struct literal (veda_bind_insts.sail) sets
            // otype = UNSEALED_OTYPE unconditionally on success -- same
            // as plain Bind, matching Section 1: "Object-Bind... always
            // populates a freshly-derived capability's otype with
            // 0xFFFF... sealing only ever happens explicitly via CSeal".
            // OCInvoke is the second real "unseal" consumer (after
            // CUnseal) -- unconditionally 0xFFFF on its own success
            // path, matching Sail's own unsealCap() semantics exactly
            // (the entire reason c15/IDC becomes usable again after
            // OCInvoke, not still sealed).
            // RTL-5 (R10) seed: c12/c13 share otype 0x0042 (sealed, and
            // MATCHING, so OCInvoke's otype-equality check passes); c14 is
            // 0xFFFE, the CSealEntry-minted sentry type OCReturn requires.
            // 0xFFFF (the default) means UNSEALED.
            $otype[15:0] = (|cpu$reset || |cpu>>1$reset) ?
                             ((#vreg == 12 || #vreg == 13) ? 16'h0042 :
                              (#vreg == 14) ? 16'hFFFE : 16'hFFFF) :
                           $bind_wr_en ? 16'hFFFF :
                           ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? 16'hFFFF :
                           $candperm_wr_en ? |cpu>>1$veda_rs1cap_otype :
                           ($oca_wr_en || $csetbounds_wr_en) ? |cpu>>1$veda_rs1cap_otype :
                           $cseal_wr_en   ? |cpu>>1$veda_cs2_offset :
                           $cunseal_wr_en ? 16'hFFFF :
                           $oclc_wr_en    ? |cpu>>1$veda_oclc_unpacked_otype :
                           $ocinvoke_wr_en ? 16'hFFFF :
                           // OSpecialRW's own `cd` receives the ODA's
                           // real otype as-is (unlike OCInvoke/CUnseal,
                           // this is a plain read-back, not an unseal --
                           // the ODA's own contents might genuinely be
                           // sealed, and `cd` must show that faithfully).
                           $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_otype : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_otype : |cpu>>1$veda_oda_otype) :
                           // Minimal OS kernel Milestone B: VEDA_CSEALENTRY's
                           // one overridden field -- the fixed 0xFFFE
                           // (VEDA_OTYPE_SENTRY) constant, unconditionally,
                           // mirroring CSeal's own "otype = the new seal"
                           // pattern above but with a fixed value instead of
                           // a capability-derived one.
                           $csealentry_wr_en ? 16'hFFFE :
                                                                $RETAIN;
            // Cached generation, for the staleness re-check below. OCL.C
            // restores the generation a real OCS.C actually stored --
            // matching the Sail model's own veda_cap_unpack exactly
            // (Reserved is packed/unpacked like every other field, not
            // special-cased).
            $reserved[23:0] = (|cpu$reset || |cpu>>1$reset) ? 24'b0 :
                             $bind_wr_en ? (|cpu>>1$veda_bind_ok ? |cpu>>1$veda_odt_gen : 24'b0) :
                             // Reserved = e.generation on Rebind success --
                             // the entire point of a Rebind refresh: the
                             // capability's cached generation must move
                             // forward to the ODT slot's CURRENT
                             // generation, or the very next dereference's
                             // own staleness re-check ($veda_gen_stale
                             // below) would immediately reject the
                             // freshly-rebound capability as stale.
                             ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ? |cpu>>1$veda_odt_gen :
                             // RTL-12: $candperm_wr_en BELONGS HERE and was
                             // missing -- a real bug, not a tidy-up. CAndPerm
                             // carried every other field of cs1 (Base, Length,
                             // Offset, Perms, otype, tag, Object_ID) and not
                             // the generation, so the result fell through to
                             // $RETAIN and kept whatever the destination
                             // register happened to hold -- 0 for a fresh one.
                             // Every dereference through an attenuated
                             // capability then trapped 0x02 (stale generation)
                             // instead of working.
                             //
                             // Invisible until now for a precise reason: the
                             // two existing CAndPerm tests inspect the result
                             // with CGetPerm/CGetTag and never ACCESS through
                             // it, so they exercised attenuation as
                             // bookkeeping and never as enforcement. A missing
                             // arm here compiles clean -- $RETAIN is a legal
                             // default and there is no type checker to object.
                             ($oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en || $candperm_wr_en) ? |cpu>>1$veda_rs1cap_reserved :
                             $oclc_wr_en ? |cpu>>1$veda_oclc_unpacked_reserved :
                             $ocinvoke_wr_en ? |cpu>>1$veda_cs2_reserved :
                             $ospecialrw_wr_en ? (|cpu>>1$veda_ospecialrw_scr_is_tsc ? |cpu>>1$veda_tsc_reserved : |cpu>>1$veda_ospecialrw_scr_is_ssc ? |cpu>>1$veda_ssc_reserved : |cpu>>1$veda_oda_reserved) :
                             $csealentry_wr_en ? |cpu>>1$veda_rs1cap_reserved :
                                                                  $RETAIN;

            // RTL-2b: flags[19:0] -- the new opaque/reserved field of the
            // 256-bit format. Every producer mints zeros (nothing can set it
            // nonzero yet); OCL.C restores whatever was stored so the
            // memory round-trip matches Sail's struct pack/unpack exactly
            // rather than silently diverging the day flags gains meaning.
            $flags[19:0] = (|cpu$reset || |cpu>>1$reset) ? 20'b0 :
                           $oclc_wr_en ? |cpu>>1$veda_oclc_unpacked_flags :
                           ($bind_wr_en || ($rebind_wr_en && |cpu>>1$veda_rebind_ok) ||
                            $oca_wr_en || $csetbounds_wr_en || $cseal_wr_en || $cunseal_wr_en ||
                            $candperm_wr_en || $ocinvoke_wr_en || $ospecialrw_wr_en ||
                            $csealentry_wr_en) ? 20'b0 :
                                                                  $RETAIN;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: OCL.D/OCS.D checks. Real hard-trap enforcement
         //  (VEDA_CORE_SPEC.md Section 3's mcause=0x18 convention) has no
         //  RTL infrastructure to land in yet -- this core has no
         //  privileged/trap architecture at all (MILESTONE_PLAN.md item
         //  2). A violation instead suppresses the write: $reg_write is
         //  gated off for OCL, the elfmem write below is gated off for
         //  OCS. $veda_violation is exposed so the real security property
         //  (an illegal access cannot corrupt state) is testable now.
         // ─────────────────────────────────────────────────────────
         $veda_rs1cap_tag           = /vreg[$veda_ocl_ocs_rs1_cap]$tag;
         $veda_rs1cap_base[55:0]    = /vreg[$veda_ocl_ocs_rs1_cap]$base;
         $veda_rs1cap_length[39:0]  = /vreg[$veda_ocl_ocs_rs1_cap]$length;
         $veda_rs1cap_perms[15:0]   = /vreg[$veda_ocl_ocs_rs1_cap]$perms;
         $veda_rs1cap_otype[15:0]   = /vreg[$veda_ocl_ocs_rs1_cap]$otype;
         $veda_rs1cap_object_id[43:0] = /vreg[$veda_ocl_ocs_rs1_cap]$object_id;
         $veda_rs1cap_reserved[23:0] = /vreg[$veda_ocl_ocs_rs1_cap]$reserved;
         // Milestone 2 addition: Offset wasn't read anywhere in Milestone
         // 1 (OCL/OCS use a fresh per-access GPR offset, not the
         // capability's own persistent one), so it never got promoted to
         // a top-level signal at all -- OCA/NMC_ADD/Veda-Atomic all need
         // it, so it's added here.
         $veda_rs1cap_offset[39:0] = /vreg[$veda_ocl_ocs_rs1_cap]$offset;

         // Generation re-check: a fresh, independent ODT lookup by the
         // *capability's own cached* Object_ID (distinct from Bind's own
         // lookup above, which is keyed by whatever the GPR $rs1 holds
         // *now* -- these are two different address computations that
         // happen to share the same odt_mem array). Included from the
         // start this milestone rather than reproducing the real gap
         // found and fixed in Sail Milestone V-B (MILESTONE_PLAN.md item
         // 3) -- not independently testable until a real ODT-Destroy
         // exists in RTL (a later milestone), same real caveat V-A/V-B
         // had in Sail.
         // ─────────────────────────────────────────────────────────
         //  RTL-4: the dereference re-check must resolve through the SAME
         //  region base as Bind did. Kept textually parallel to the Bind
         //  path line-for-line so the two stay diffable -- this is now the
         //  FOURTH hand-written copy of an ODT address computation in this
         //  file, ~700 lines from the first, and the file already carries
         //  three unshared copies of the entry layout.
         //
         //  Miss this and the failure is MISLEADING, not obvious: every
         //  cross-region capability would resolve to a region-0 slot on its
         //  first OCL/OCS/OCL.C/OCS.C/NMC/Atomic, read a mismatched tag, and
         //  report $veda_gen_stale -- cause 0x02, from an entirely different
         //  fault family. It is also invisible to the whole existing corpus,
         //  which is region 0 throughout, which is exactly why the new
         //  uniqueness test DEREFERENCES its region-1 capability instead of
         //  merely binding it.
         //
         //  NO REGION_FAULT here, deliberately, and that remains true.
         //  Region residency is a BIND-time authority question: you resolve
         //  which domain's table to consult once, when the capability is
         //  minted, not on every use of it.
         //
         //  RTL-6b CORRECTION -- this comment used to extend that claim to
         //  OBJECT residency as well ("residency is a BIND-time authority
         //  question, not a per-dereference one"). That is false, and it is
         //  stated here rather than quietly deleted because the reasoning
         //  is the interesting part and the next reader will otherwise
         //  delete the new term below as redundant.
         //
         //  The region precedent does not transfer, for one reason: a
         //  capability caches Base. Region residency cannot change what a
         //  held capability points AT; object residency can, because paging
         //  exists precisely to free a frame and give it to someone else.
         //  A bind-time-only object check would therefore authorise the
         //  first access and silently permit every later one against a
         //  frame that is no longer the object's.
         //
         //  It is fair to ask whether the term is redundant TODAY, and the
         //  honest answer is that it is close to it: RTL-6c's page-out is
         //  the only producer of {valid, non-resident}, and it bumps
         //  generation, so a stale capability fails on 0x02 first. The term
         //  is kept anyway. That soundness argument is a property of the
         //  current producer set, not of the checker, and DESIGN_02 still
         //  has `cow` and `backing` to add. A checker that is correct only
         //  because of what no other instruction happens to do yet is one
         //  edit away from being wrong, with nothing to catch it.
         $veda_check_region[19:0] = $veda_rs1cap_object_id[43:24];
         $veda_check_local[23:0]  = $veda_rs1cap_object_id[23:0];
         $veda_check_intra_region = ($veda_check_region == $veda_current_region);
         $veda_check_region_in_window = ($veda_check_region < {12'b0, RT_ENTRIES[7:0]});
         $veda_check_region_base[31:0] = $veda_check_intra_region ? $veda_current_odt_base :
                                          ($veda_check_region_in_window ? rt_odt_base[$veda_check_region[2:0]] : 32'b0);
         $veda_check_entry_idx[31:0] = $veda_check_region_base + {24'b0, $veda_check_local[7:0]};
         $veda_check_idx_ok = ($veda_check_entry_idx < {16'b0, ODT_ENTRIES[15:0]});
         // ─────────────────────────────────────────────────────────
         //  RTL-5 (R10, DESIGN_07 Tier G): the RT-DIRECT residency check
         //  used ONLY for CRBR loads at domain crossings. Mirrors Sail's
         //  veda_region_rt_resident (veda_regs.sail:565-569).
         //
         //  Deliberately a SEPARATE signal from $veda_region_resident
         //  above, and deliberately WITHOUT its `$veda_intra_region ?
         //  1'b1 :` first arm. Two independent reasons, both load-bearing:
         //
         //  1. The exemption's soundness is exactly what a validated load
         //     ESTABLISHES, so a load that consulted it would be circular
         //     -- a stale current region would validate its own successor,
         //     which is the R10 escape itself.
         //  2. $veda_region_resident is keyed off $veda_region, which
         //     comes from $rs1_data (the GPR Bind operand). A domain
         //     crossing must take its region from the CAPABILITY, never
         //     from a GPR -- that is R10's unforgeability clause.
         //
         //  rt_valid gains its first-ever consumer here: an unconfigured
         //  slot must fail CLOSED even if its resident bit reads true.
         //  The in-window compare uses the 8-bit-extended form;
         //  RT_ENTRIES[2:0] would be 3'b000 for RT_ENTRIES=8 and make
         //  every region read out-of-window.
         $veda_crossing_rt_resident = $veda_check_region_in_window
                                       && rt_valid[$veda_check_region[2:0]]
                                       && rt_resident[$veda_check_region[2:0]];
         $veda_check_odt_idx[7:0]   = $veda_check_local[7:0];
         $veda_check_odt_addr[31:0] = ODT_BASE + (($veda_check_idx_ok ? $veda_check_entry_idx : 32'b0)
                                                  * {24'b0, ODT_ENTRY_BYTES[7:0]});
         $veda_check_odt_gen[23:0]  = {odt_mem[$veda_check_odt_addr+16], odt_mem[$veda_check_odt_addr+15], odt_mem[$veda_check_odt_addr+14]};
         // RTL MILESTONE 15 (same fix as the Bind-side lookup above):
         // the dereference-time re-check must also confirm the slot
         // still holds the SAME real Object_ID the capability was bound
         // to -- otherwise a capability for Object_ID=100 could keep
         // successfully dereferencing after Object_ID=356 (a low-byte
         // alias) took over slot 100, since generation/valid alone
         // can't tell the two apart.
         // RTL-18: the DEREFERENCE-side cow read. Deliberately a different read
         // from $veda_odt_cow above: that one is addressed from the GPR
         // Object_ID a Bind names, this one from the capability being
         // dereferenced. Using the bind-side signal here would consult
         // whichever object some unrelated Bind happened to name.
         $veda_check_odt_cow = odt_mem[$veda_check_odt_addr+ODT_OFF_COW][0];
         $veda_check_odt_id_hi[35:0] = {odt_mem[$veda_check_odt_addr+24], odt_mem[$veda_check_odt_addr+23], odt_mem[$veda_check_odt_addr+22], odt_mem[$veda_check_odt_addr+21], odt_mem[$veda_check_odt_addr+20]};
         $veda_check_odt_id_match    = ($veda_check_odt_id_hi == $veda_rs1cap_object_id[43:8]);
         $veda_check_odt_valid      = $veda_check_idx_ok && odt_mem[$veda_check_odt_addr+17][0] && $veda_check_odt_id_match;
         $veda_gen_stale = (!$veda_check_odt_valid) || ($veda_check_odt_gen != $veda_rs1cap_reserved);
         // RTL-6b: the dereference-side object residency term.
         //
         // READ FROM $veda_check_odt_addr, NEVER $veda_odt_addr. Both are
         // [31:0], both index odt_mem, both are in scope right here, and
         // both are named $veda_*odt_addr. Substituting one for the other
         // compiles, elaborates and simulates -- and keys the residency
         // decision off whatever Object_ID the current GPR rs1 happens to
         // hold rather than the one the capability was bound to.
         //
         // NOT folded into $veda_gen_stale, though that would be one edit
         // instead of fourteen. $veda_gen_stale carries cause 0x02, so
         // folding would report "stale generation" for a paged-out object:
         // a permanent verdict for a serviceable condition, which is the
         // same error the bind-side ordering exists to avoid.
         $veda_check_odt_resident = odt_mem[$veda_check_odt_addr+ODT_OFF_RESIDENT][0];
         $veda_deref_nonresident  = !$veda_check_odt_resident;

         $veda_sealed        = ($veda_rs1cap_otype != 16'hFFFF);
         $veda_perm_load_ok  = $veda_rs1cap_perms[2];
         $veda_perm_store_ok = $veda_rs1cap_perms[3];
         // ═══ RTL-16 (R18): THE BOUNDS CHECK MUST NOT WRAP ═══
         //
         // This addition was 64 bits wide on both sides, and $rs2_data is a
         // full, attacker-chosen 64-bit GPR. offset = 0xFFFFFFFFFFFFFFF8 makes
         // offset+8 wrap to 0, "0 <= Length" passes, and $veda_real_addr --
         // also a modular 64-bit add -- lands at Base-8. Every other term of
         // the violation is satisfied by a perfectly ordinary capability:
         // tagged, in-generation, unsealed, permitted, resident. So the access
         // RETIRES, with no trap, reading and WRITING the bytes immediately
         // below the object. In a packed allocator those bytes are the tail of
         // the neighbouring object.
         //
         // Sail cannot express this bug: its `unsigned()` yields an
         // arbitrary-precision integer, so `unsigned(offset) + width` cannot
         // wrap. The model was right and the hardware was wrong -- the third
         // divergence of this shape found in this file, and the first that is
         // straightforwardly exploitable.
         //
         // The fix is to do the arithmetic one bit wider than the widest
         // operand, so the carry has somewhere to go. 2^64-1 + 16 needs 65
         // bits; at 65 bits the sum is far larger than any 40-bit Length and
         // the compare correctly refuses. Widening the COMPARE is what matters
         // -- clamping the offset instead would silently alias a huge offset
         // onto a legal one, which is the same class of bug wearing a hat.
         $veda_bounds_ok     = (({1'b0, $rs2_data} + 65'd8) <= {25'b0, $veda_rs1cap_length});

         $veda_ocl_violation = $is_veda_ocl && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok || !$veda_bounds_ok || $veda_deref_nonresident);
         $veda_ocs_violation = $is_veda_ocs && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || $veda_cow_write || !$veda_perm_store_ok || !$veda_bounds_ok || $veda_deref_nonresident);
         // $veda_violation itself is combined further below, once
         // NMC_ADD/Veda-Atomic's own violation signals are also computed
         // (kept textually after the checks they depend on, matching this
         // file's own established define-before-use style, even though
         // TL-Verilog's combinational elaboration doesn't strictly
         // require it).

         $veda_real_addr[63:0] = {8'b0, $veda_rs1cap_base} + $rs2_data;
         // The GPR holding OCS's store value ($rd is the shared 5-bit
         // GPR-index field at instr[11:7], reused here as the "value
         // source" the same way the base ISA's own store instructions
         // reuse $rs2 for theirs -- OCL/OCS's own R-type shape puts the
         // value/destination in the $rd slot instead, per
         // VEDA_CORE_SPEC.md Section 1).
         $veda_ocs_value[63:0] = /xreg[$rd]$val;
         // Only consumed by the trailing raw \SV always_ff block below via
         // its mangled name (invisible to SandPiper's own TLV-level
         // dependency tracking, same real reason $mem_addr/$rs2_data's
         // trailing-\SV consumption never needed this -- those are *also*
         // used elsewhere in TLV logic, this signal genuinely isn't).
         `BOGUS_USE($veda_ocs_value)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 7: OCL.C/OCS.C checks. Real, own
         //  16-byte (128-bit) bounds check -- deliberately NOT sharing
         //  $veda_bounds_ok above, which is hardcoded to the 8-byte
         //  D-width. Same real_addr computation as OCL.D/OCS.D
         //  ($veda_real_addr, already computed above: rs1cap.Base +
         //  fresh GPR offset) -- the capability width doesn't change
         //  where the access lands, only how many bytes/whether the tag
         //  store is touched.
         // ─────────────────────────────────────────────────────────
         // RTL-16 (R18): same widening, same reason -- see $veda_bounds_ok above.
         //
         // R23 FIX: the width was 65'd16 and the access is 32 BYTES. An OCL.C /
         // OCS.C moves a whole 256-bit capability -- $veda_ocsc_packed[255:0]
         // (:3215), $veda_oclc_load_data[255:0] (:4994, whose own comment reads
         // "a capability is 32 bytes now -- both arms read 32, not 16"), and the
         // elfmem store extent +0..+31 -- while this check only ever asked
         // whether SIXTEEN bytes fit. Sail has always passed 32
         // (veda_ocl_insts.sail:188 and :224), so this was RTL-only.
         //
         // The hole: for an object of Length L, offset L-16 satisfies
         // (L-16)+16 <= L, so the check PASSES -- and the access then reads or
         // writes through Base+L+15, sixteen bytes PAST the object, with a
         // valid capability and no trap. A real out-of-object write primitive,
         // not merely a mis-reported cause.
         //
         // Found while grounding the R19 check-reorder: that reorder promises
         // "an out-of-bounds store to a copy-on-write object reports 0x01 and
         // never arms a copy", and this width made that promise false by 16
         // bytes on the capability chains. Fixed FIRST, on its own, because it
         // is a spatial-safety defect in its own right and would otherwise ship
         // inside an ordering change whose tests are not looking for it.
         $veda_oclc_bounds_ok = (({1'b0, $rs2_data} + 65'd32) <= {25'b0, $veda_rs1cap_length});
         // RTL-2a: 32-byte natural alignment is architectural for capability
         // memory access -- it is the only rule under which
         // one-capability-one-granule is well defined.
         $veda_capmem_misaligned = $veda_real_addr[4:0] != 5'b0;
         $veda_oclc_violation = $is_veda_ocl_c && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok  || !$veda_oclc_bounds_ok || $veda_capmem_misaligned || $veda_deref_nonresident);
         $veda_ocsc_violation = $is_veda_ocs_c && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || $veda_cow_write || !$veda_perm_store_ok || !$veda_oclc_bounds_ok || $veda_capmem_misaligned || $veda_deref_nonresident);

         // Tag-store granule index: $veda_real_addr is absolute
         // (ELFMEM_BASE-relative), tag_mem[] is declared 0-based
         // (mirroring elfmem[]'s own absolute-vs-tag_mem's own relative
         // indexing choice, both real, deliberate, independent design
         // calls) -- subtract ELFMEM_BASE, then >>4 (real hardware's own
         // natural way to divide by 16, the granule size, since 16 is a
         // power of two -- the same technique already used in the Sail
         // model's own tag-store index computation, byte_off >> 5).
         // RTL mirror increment RTL-2a: the granule is 32 bytes, matching the
         // 256-bit capability that is about to land. One capability MUST
         // occupy exactly one granule: with a 16-byte granule a plain store
         // into the second half of a stored capability -- the half holding
         // Perms/otype/generation -- would clear only that half's tag while
         // the tag the load actually checks (the start granule) survived,
         // i.e. a permission/generation forgery with a valid Tag. Landing
         // the granule BEFORE the format change is deliberate: the reverse
         // order leaves a window where the hole is open and the suite is
         // still green.
         $veda_capmem_granule[31:0] = ($veda_real_addr[31:0] - ELFMEM_BASE) >> 5;

         // MILESTONE 24 Stage 3: OCL.C/OCS.C's own TCM routing decision --
         // a real, separate address-range check on $veda_real_addr
         // (already computed above), completely independent of Stage 2's
         // Object_ID-based $veda_odt_tcm_hit (OCL.C/OCS.C's rs1 selects a
         // CRF register, never an Object_ID -- these two "_tcm_hit"
         // signals are judged on fundamentally different data and must
         // stay separate). A parallel, TCM-relative granule index is
         // real, load-bearing, not cosmetic: feeding a TCM_SCRATCH_BASE
         // -relative address into tag_mem[]'s own ELFMEM_SIZE-scoped
         // index space would alias or overflow -- the exact "easy-to-
         // miss bug class" flagged before any code was written here, now
         // closed by construction with its own, separate index.
         $veda_capmem_tcm_hit = ($veda_real_addr[31:0] >= TCM_SCRATCH_BASE) &&
                                 ($veda_real_addr[31:0] <  (TCM_SCRATCH_BASE + TCM_SCRATCH_SIZE));
         $veda_capmem_tcm_granule[31:0] = ($veda_real_addr[31:0] - TCM_SCRATCH_BASE) >> 5;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 7: byte-granular tag invalidation --
         //  real CHERI hardware's own core property, found missing by
         //  this milestone's own negative test (not assumed correct
         //  from the design alone): ANY plain, non-OCS.C write that
         //  touches a 16-byte granule must clear that granule's tag,
         //  because the bytes there may no longer form a valid, intact
         //  capability. Without this, a plain OCS.D could silently
         //  corrupt the low 8 bytes of a previously-stored capability
         //  while tag_mem[] kept reporting it as still genuinely tagged
         //  -- exactly the forgery OCL.C/OCS.C's whole design exists to
         //  prevent. Reused for NMC_ADD/Veda-Atomic's own write address
         //  below (both use $veda_cap_real_addr, distinct from OCL/OCS's
         //  $veda_real_addr above).
         // ─────────────────────────────────────────────────────────
         $veda_capmem_nmc_granule[31:0] = ($veda_cap_real_addr[31:0] - ELFMEM_BASE) >> 5;

         // OCS.C's own store source: rd is a Capability Register here
         // (Section 1's own field-position-reuse idiom, same as every
         // other Custom-0/2 instruction), not a GPR -- pack its 128 data
         // bits in the identical field order the Sail model uses
         // (veda_cap_pack: Object_ID @ Base @ Length @ Offset @ Perms @
         // otype @ Reserved @ 1'b0 padding), so both real, independent
         // implementations of this ISA agree on one real memory layout,
         // not two silently different ones.
         $veda_ocsc_store_cap_object_id[43:0] = /vreg[$veda_rd_cap]$object_id;
         $veda_ocsc_store_cap_base[55:0]      = /vreg[$veda_rd_cap]$base;
         $veda_ocsc_store_cap_length[39:0]    = /vreg[$veda_rd_cap]$length;
         $veda_ocsc_store_cap_offset[39:0]    = /vreg[$veda_rd_cap]$offset;
         $veda_ocsc_store_cap_perms[15:0]     = /vreg[$veda_rd_cap]$perms;
         $veda_ocsc_store_cap_otype[15:0]     = /vreg[$veda_rd_cap]$otype;
         $veda_ocsc_store_cap_reserved[23:0]  = /vreg[$veda_rd_cap]$reserved;
         // RTL-2b: flags is opaque/reserved -- minted zero by every producer,
         // carried through memory so the pack/unpack round-trip matches Sail
         // exactly rather than diverging the instant flags gains meaning.
         $veda_ocsc_store_cap_flags[19:0]     = /vreg[$veda_rd_cap]$flags;
         $veda_ocsc_store_tag                 = /vreg[$veda_rd_cap]$tag;
         // RTL-2b: the 256-bit memory image. Object_ID(44) Base(56) Length(40)
         // Offset(40) Perms(16) otype(16) generation(24) flags(20) = 256
         // EXACTLY -- the old layout was 127 data bits + a 1'b0 pad, and
         // that pad no longer exists. Widths must sum to exactly 256: if any
         // one source were left narrow the concat under-fills and every
         // field below it slides, with no diagnostic.
         $veda_ocsc_packed[255:0] = {$veda_ocsc_store_cap_object_id, $veda_ocsc_store_cap_base,
                                      $veda_ocsc_store_cap_length, $veda_ocsc_store_cap_offset,
                                      $veda_ocsc_store_cap_perms, $veda_ocsc_store_cap_otype,
                                      $veda_ocsc_store_cap_reserved, $veda_ocsc_store_cap_flags};
         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value needed this).
         `BOGUS_USE($veda_ocsc_packed)
         `BOGUS_USE($veda_ocsc_store_tag)

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: OCA (Object Capability Adjust). Soft-fail (Tag
         //  cleared, no trap) on out-of-bounds or sealed rs1 -- matches
         //  CHERI's own real CIncOffset unconditional-field/conditional-
         //  tag pattern (already used for the /vreg write logic below),
         //  the identical semantics already built and verified in Sail.
         //  No permission gate: OCA is a "manipulate" instruction
         //  (Section 1), not a "use" instruction -- it never dereferences
         //  the object itself.
         // ─────────────────────────────────────────────────────────
         // Ordinary 64-bit two's-complement addition already produces the
         // mathematically-correct signed sum regardless of operand signs
         // (same principle already relied on throughout this file for
         // $alu_result64/$branch_target/etc.) -- checking sum[63] for
         // "negative" needs no $signed() cast, avoiding the real
         // misparse issue already documented and fixed once in this
         // project (the `$` sigil collides with TL-Verilog's own syntax).
         $veda_oca_sum[63:0] = {24'b0, $veda_rs1cap_offset} + $rs2_data;
         $veda_oca_out_of_range = $veda_oca_sum[63] || ($veda_oca_sum >= {24'b0, $veda_rs1cap_length});
         $veda_oca_ok = $veda_rs1cap_tag && !$veda_oca_out_of_range && ($veda_rs1cap_otype == 16'hFFFF);
         // CAndPerm: no bounds term (masking Perms cannot leave the window);
         // Tag survives only a tagged, unsealed source.
         $veda_candperm_ok = $veda_rs1cap_tag && ($veda_rs1cap_otype == 16'hFFFF);

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: Veda-Cap query family. Pure combinational reads of
         //  the already-fetched $veda_rs1cap_* fields -- no checks, per
         //  the decode comment above.
         // ─────────────────────────────────────────────────────────
         $veda_capquery_result[63:0] =
            $is_veda_cgetbase   ? {8'b0, $veda_rs1cap_base} :
            $is_veda_cgetlen    ? {24'b0, $veda_rs1cap_length} :
            $is_veda_cgetperm   ? {48'b0, $veda_rs1cap_perms} :
            $is_veda_cgettag    ? {63'b0, $veda_rs1cap_tag} :
            $is_veda_cgettype   ? {48'b0, $veda_rs1cap_otype} :
            $is_veda_cgetaddr   ? ({8'b0, $veda_rs1cap_base} + {24'b0, $veda_rs1cap_offset}) :
            $is_veda_cgetoffset ? {24'b0, $veda_rs1cap_offset} :
            $is_veda_cgetobjectid ? {20'b0, $veda_rs1cap_object_id} :
                                  64'b0;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: CSetBounds/CSetBoundsExact. "cd.Base = cs1.Base +
         //  cs1.Offset (narrows the object window to start at the
         //  capability's current position)... cd.Length = rs2... cd.Offset
         //  = 0" (VEDA_CORE_SPEC.md Section 1) -- soft-fail (Tag cleared,
         //  no trap) if cs1 was sealed or the requested bounds would
         //  exceed cs1's own current window, the same "manipulate" family
         //  convention as OCA above.
         // ─────────────────────────────────────────────────────────
         $veda_csetbounds_new_base[31:0]   = $veda_rs1cap_base + {16'b0, $veda_rs1cap_offset};
         $veda_csetbounds_new_length[15:0] = $rs2_data[15:0];
         // Monotonic narrowing: the new window, starting at the current
         // position, must not extend past cs1's own remaining Length --
         // the same principle already applied for CSetBounds in Sail.
         // RTL-2b: compared in a uniform 64-bit domain. Offset/Length are 40 bits
         // now while rs2_data is 64, so mixing a {24'b0,40} term with a
         // {48'b0,16} term would silently size the expression to the widest
         // operand and compare misaligned magnitudes.
         $veda_csetbounds_window_ok = (({24'b0, $veda_rs1cap_offset}) + {48'b0, $rs2_data[15:0]}) <= {24'b0, $veda_rs1cap_length};
         $veda_csetbounds_ok = $veda_rs1cap_tag && !$veda_sealed && $veda_csetbounds_window_ok;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE RTL MILESTONE 6: CSeal/CUnseal. Mirrors
         //  veda_cap_insts.sail's own VEDA_CSEAL/VEDA_CUNSEAL field-for-
         //  field (already real, working, verified Sail) -- ground truth
         //  re-read directly from that file before writing this, not
         //  re-derived from the CHERI spec summary. cs1 = the already-
         //  extracted $veda_rs1cap_* (this Custom-2 format's own rs1-
         //  capability field, instr[18:15], the exact same field OCA/
         //  CSetBounds/the query family already read). cs2 = the NEW
         //  rs2-capability operand ($veda_cseal_cunseal_rs2_cap,
         //  instr[23:20]) -- a fresh, independent /vreg read, not reused
         //  from anything above.
         // ─────────────────────────────────────────────────────────
         $veda_cs2_tag          = /vreg[$veda_cseal_cunseal_rs2_cap]$tag;
         $veda_cs2_length[39:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$length;
         $veda_cs2_offset[39:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$offset;
         $veda_cs2_perms[15:0]  = /vreg[$veda_cseal_cunseal_rs2_cap]$perms;
         $veda_cs2_otype[15:0]  = /vreg[$veda_cseal_cunseal_rs2_cap]$otype;
         $veda_cs2_sealed       = ($veda_cs2_otype != 16'hFFFF);
         // Object_ID/Base/Reserved: not needed by CSeal/CUnseal above
         // (cs2 there is only ever a type-authority, never copied into
         // cd), but needed by OCInvoke below, which really does copy
         // cs2's own full field set into c15 (IDC) on success.
         $veda_cs2_object_id[43:0] = /vreg[$veda_cseal_cunseal_rs2_cap]$object_id;
         $veda_cs2_base[55:0]      = /vreg[$veda_cseal_cunseal_rs2_cap]$base;
         $veda_cs2_reserved[23:0]  = /vreg[$veda_cseal_cunseal_rs2_cap]$reserved;

         // CSeal: cs2 must be a live, unsealed, Permit_Seal-carrying
         // (Perms bit 8, matching veda_types.sail's PERM_SEAL=8, the
         // same bit-index convention already used for Perms[2]=Load/
         // Perms[3]=Store/Perms[12]=NMC_Compute above) capability whose
         // own Offset (the value about to become cs1's new otype) lies
         // within cs2's own [0,Length) window and isn't the UNSEALED
         // sentinel (0xFFFF) -- using 0xFFFF as a "sealed" otype would
         // silently alias UNSEALED, a real, meaningful check, not a
         // mechanical bound. cs1 itself must be tagged and not already
         // sealed ("if cs1 was already sealed" -- Sail's own comment,
         // reused verbatim).
         // Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         // `!= 16'hFFFE` added alongside the pre-existing `!= 16'hFFFF`
         // exclusion -- the load-bearing security property for the
         // entire sentry mechanism (VEDA_CSEALENTRY/VEDA_OCRETURN
         // below), mirroring real CHERI's own CSeal `cursor <=
         // cap_max_otype` bound: ordinary, software-directed sealing
         // must never be able to forge the hardware-reserved sentry
         // otype. Without this line, a capability sealed here with
         // otype=0xFFFE would be indistinguishable from a genuine
         // VEDA_CSEALENTRY-minted sentry to VEDA_OCRETURN.
         $veda_cseal_authorized = $veda_cs2_tag && !$veda_cs2_sealed && $veda_cs2_perms[8] &&
                                   ($veda_cs2_offset < $veda_cs2_length) &&
                                   ($veda_cs2_offset != 16'hFFFF) && ($veda_cs2_offset != 16'hFFFE);
         $veda_cseal_ok = $veda_cseal_authorized && $veda_rs1cap_tag && !$veda_sealed;

         // CUnseal: mirror of CSeal's authorization -- cs2 must be live,
         // unsealed, Permit_Unseal-carrying (Perms bit 9, PERM_UNSEAL),
         // and its Offset must exactly match cs1's current otype (the
         // type-authority proving it's allowed to unseal *this specific*
         // sealed type), within cs2's own bounds. cs1 must actually be
         // sealed and tagged.
         $veda_cunseal_authorized = $veda_cs2_tag && !$veda_cs2_sealed && $veda_cs2_perms[9] &&
                                     $veda_sealed && ($veda_cs2_offset == $veda_rs1cap_otype) &&
                                     ($veda_cs2_offset < $veda_cs2_length);
         $veda_cunseal_ok = $veda_cunseal_authorized && $veda_rs1cap_tag;

         // ─────────────────────────────────────────────────────────
         //  Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         //  VEDA_CSEALENTRY -- term-for-term adaptation of real CHERI's
         //  own CSealEntry (CHERI ISA spec p.215, read in full before
         //  writing this): cd = cs1 sealed with the fixed 0xFFFE
         //  (VEDA_OTYPE_SENTRY) constant -- no authorizing capability
         //  operand at all, unlike CSeal/CUnseal above (real CHERI's own
         //  text, p.101: "an ambient monotonic action, requiring no
         //  additional permission than to have a capability bearing
         //  Permit_Execute"). Perms (including Permit_Execute) are
         //  carried through unchanged, neither stripped nor added --
         //  VEDA_OCRETURN below is what actually enforces Permit_Execute,
         //  at the point of use, matching real CHERI's own division of
         //  labor between CSealEntry and CJALR exactly (verified against
         //  the Sail model, veda_cap_insts.sail's own VEDA_CSEALENTRY).
         //  funct7 = 0010101, the next genuinely free Custom-2/funct3=001
         //  slot after OCJALR (0010100), verified directly against every
         //  existing funct7==7'b0010... decode line in this file before
         //  picking it. Single source operand, reusing the same shared
         //  rs1-cap field ($veda_ocl_ocs_rs1_cap / $veda_rs1cap_*) every
         //  other Custom-2 instruction already shares -- no new field
         //  extraction needed.
         // ─────────────────────────────────────────────────────────
         $is_veda_csealentry = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010101);
         // Soft-fail only, no hard trap -- mirrors CSeal's own $veda_cseal_ok
         // pattern, minus any cs2/authorization term (CSealEntry takes
         // none): an already-untagged or already-sealed cs1 can't
         // produce a valid sentry, the same "untagged/already-sealed
         // source can't produce a valid result" reasoning CSeal already
         // applies.
         $veda_csealentry_ok = $veda_rs1cap_tag && !$veda_sealed;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 10: OCInvoke -- Veda-Core's own term-for-term
         //  adaptation of real CHERI's CInvoke (CHERI ISA spec p.209,
         //  read in full before writing this, not assumed from a
         //  summary), the protection-domain-transition primitive
         //  VEDA_CORE_SPEC.md Section 6 item 7 named and deferred until
         //  now. cs1 (code) = $veda_rs1cap_* (this format's already-
         //  established rs1-capability field); cs2 (data) =
         //  $veda_cs2_* above (already read for CSeal/CUnseal, reused
         //  unchanged). Real CHERI check order, mirrored exactly (not
         //  re-derived): Tag(cs1) -> Tag(cs2) -> Seal(cs1) -> Seal(cs2)
         //  -> matching otype -> Permit_Invoke(cs1) -> Permit_Invoke
         //  (cs2) -> Permit_Execute(cs1) must hold -> Permit_Execute
         //  (cs2) must NOT hold. cap_idx for mtval is NOT the single
         //  shared rs1-cap signal every other "use" family instruction
         //  could rely on (Milestone 9) -- OCInvoke genuinely involves
         //  two distinct capability registers, so the specific one that
         //  actually failed must be reported, muxed per failing check
         //  below, exactly matching Sail's own per-check
         //  veda_trap(rs1 or rs2, ...) choice.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocinvoke = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010010);
         // RTL-5 (R10): the region gate joins this OR as the LAST term, so
         // a capability that fails any earlier check still reports its own
         // real reason -- mirroring Sail's placement after all nine checks
         // (veda_cap_insts.sail:489). Because $veda_ocinvoke_violation is
         // what every commit below is gated on, adding the term here means
         // a non-resident target domain commits NOTHING: no c15/IDC write,
         // no PCC narrowing, no SSC clear, no PC redirect.
         $veda_ocinvoke_region_fault = $is_veda_ocinvoke && !$veda_crossing_rt_resident;
         // ─────────────────────────────────────────────────────────
         //  RTL-7 (R11, DESIGN_07 Tier H): REVALIDATE THE CODE OBJECT.
         //
         //  The three crossings were the ONLY consumers of an object's Base
         //  that never re-read the ODT -- so a sealed CODE capability
         //  survived an eviction that a DATA capability to the same object
         //  did not. Execute-after-free, reproduced on the Sail model with
         //  a control isolating it: after the same page-out, veda.bind
         //  refused with 0x0A while ocinvoke took the jump.
         //
         //  THE MIRROR IS NEARLY FREE HERE, and why is worth recording.
         //  All three crossing encodings place the CODE capability at
         //  instr[18:15] -- exactly $veda_ocl_ocs_rs1_cap, the index
         //  already feeding the shared dereference lookup. So the entry is
         //  ALREADY read for these instructions, and both halves of the
         //  check already exist: $veda_gen_stale is generation/valid,
         //  $veda_deref_nonresident is residency. Sail needed a new helper;
         //  the RTL needs only new terms. The shared-checker asymmetry that
         //  cost fourteen edit sites in RTL-6b buys the mirror back here.
         $veda_ocinvoke_violation = $is_veda_ocinvoke && (
            !$veda_rs1cap_tag || !$veda_cs2_tag ||
            !$veda_sealed || !$veda_cs2_sealed ||
            ($veda_rs1cap_otype != $veda_cs2_otype) ||
            !$veda_rs1cap_perms[10] || !$veda_cs2_perms[10] ||
            !$veda_rs1cap_perms[1] || $veda_cs2_perms[1] ||
            !$veda_crossing_rt_resident ||
            $veda_gen_stale || $veda_deref_nonresident);
         $veda_ocinvoke_cause[4:0] =
            !$veda_rs1cap_tag           ? 5'h02 :
            !$veda_cs2_tag              ? 5'h02 :
            !$veda_sealed               ? 5'h03 :
            !$veda_cs2_sealed           ? 5'h03 :
            ($veda_rs1cap_otype != $veda_cs2_otype) ? 5'h04 :
            !$veda_rs1cap_perms[10]     ? 5'h19 :
            !$veda_cs2_perms[10]        ? 5'h19 :
            !$veda_rs1cap_perms[1]      ? 5'h11 :
            // RTL-5 (R10): EXPLICIT arm, not the fall-through. This chain's
            // default is 5'h11, so without naming 0x09 here a region fault
            // would report PERMIT_EXECUTE_VIOLATION -- a wrong, misleading
            // cause that no existing test could catch (the corpus never
            // crosses into a non-resident domain).
            !$veda_crossing_rt_resident ? 5'h09 :
            // RTL-7 (R11): AFTER the region arm -- a non-resident REGION
            // means the object's entry was never legitimately readable.
            // Generation before residency, matching Sail and both
            // dereference checkers: 0x02 is the PERMANENT verdict
            // (re-Bind), 0x0A the SERVICEABLE one (page it in). Page-out
            // bumps generation, so a capability held across one reports
            // 0x02 -- the Option-A contract, not a defect.
            $veda_gen_stale             ? 5'h02 :
            $veda_deref_nonresident     ? 5'h0A :
            // The old fall-through, now EXPLICIT. It has to be: the arms
            // above are new reachable causes, so leaving cs2's wrong
            // executability silent would report 0x11 for a paged-out
            // object. Same restructure RTL-6b needed, same reason.
            $veda_cs2_perms[1]          ? 5'h11 :
                                           5'h11;
         $veda_ocinvoke_cap_idx[3:0] =
            !$veda_rs1cap_tag           ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_tag              ? $veda_cseal_cunseal_rs2_cap :
            !$veda_sealed               ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_sealed           ? $veda_cseal_cunseal_rs2_cap :
            ($veda_rs1cap_otype != $veda_cs2_otype) ? $veda_ocl_ocs_rs1_cap :
            !$veda_rs1cap_perms[10]     ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_perms[10]        ? $veda_cseal_cunseal_rs2_cap :
            !$veda_rs1cap_perms[1]      ? $veda_ocl_ocs_rs1_cap :
            // RTL-5 (R10): likewise explicit. This chain's default is cs2,
            // but Sail reports rs1 for the region fault (veda_trap(rs1,
            // VEDA_CAUSE_REGION_FAULT)) -- the faulting thing is the CODE
            // capability whose domain is paged out, not the data operand.
            !$veda_crossing_rt_resident ? $veda_ocl_ocs_rs1_cap :
            // RTL-7 (R11): the new causes need their OWN arms here, and
            // this was caught by the test rather than by review. Both
            // revalidate cs1 (the CODE capability, whose Base becomes
            // PCC), and Sail traps veda_trap(rs1, cause) accordingly -- but
            // this chain's DEFAULT is cs2's index, so without these two
            // arms a paged-out code object reported cap_idx 4 instead of 3.
            // The mechanism was right and the report was wrong, which is
            // the harder kind of bug: mtval would have sent a handler to
            // inspect the wrong capability entirely.
            $veda_gen_stale             ? $veda_ocl_ocs_rs1_cap :
            $veda_deref_nonresident     ? $veda_ocl_ocs_rs1_cap :
                                           $veda_cseal_cunseal_rs2_cap;
         // Real jump target: cs1.Base + cs1.Offset (the same real
         // CGetAddr semantics already established) -- CHERI's own real
         // "clear bit 0 as for RISCV JALR" is a no-op here, since
         // Base/Offset are already byte-address-aligned integers with
         // no such low bit convention to clear.
         $veda_ocinvoke_target[63:0] = {8'b0, $veda_rs1cap_base} + {24'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  OCJALR (Milestone 17, veda-core/STACK_FRAME_CALL_RETURN_
         //  ANALYSIS.md): closes the real, honest software-discipline
         //  gap that analysis found by testing rather than assuming --
         //  a return-address convention built entirely from already-
         //  existing instructions (OCA+CSeal at the call site, already
         //  proven working) left the return side as a hand-rolled
         //  CUnseal+CGetAddr+JALR sequence with no hardware gate: a
         //  never-sealed or corrupted-to-unsealed capability's own
         //  Base/Offset fields were still readable and jumpable, the
         //  check that made it safe was purely a software habit.
         //  OCJALR merges unseal-verification and jump into one atomic
         //  instruction, so the check cannot be forgotten by
         //  construction -- the same real property real CHERI's own
         //  CJALR provides for its sentry-capability jumps (CHERI ISA
         //  spec p.213, `CapEx_SealViolation` on a sealed-but-wrong
         //  capability, full semantics read before writing this).
         //  funct7 = 0010100, the next genuinely free Custom-2/
         //  funct3=001 slot -- 0010011 was this instruction's own
         //  first-draft value, found (on the Sail side, before any RTL
         //  was written) to collide with OSpecialRW's already-existing
         //  encoding, since OSpecialRW hardwires its own rs2-position
         //  field to all-zero rather than treating it as a real
         //  operand -- a real, narrow encoding bug caught and fixed
         //  before it could reach RTL at all.
         //  rs1 = cs1 (the sealed return-capability being verified and
         //  jumped through, reusing $veda_rs1cap_*, the same rs1-cap
         //  field position every Custom-2 instruction already shares);
         //  rs2 = cs2 (the seal-authority, reusing $veda_cs2_*, the
         //  same field CSeal/CUnseal/OCInvoke already established).
         //  Check order mirrors veda_cap_insts.sail's own VEDA_OCJALR
         //  exactly: Tag(cs1) -> Tag(cs2) -> Seal(cs1) must hold ->
         //  Seal(cs2) must NOT hold -> Permit_Unseal(cs2) ->
         //  cs2.Offset == cs1.otype (the same real type-authority match
         //  CUnseal itself already checks) -> Permit_Execute(cs1).
         //  Deliberately narrower than real CHERI's own general-purpose
         //  CJALR (which also mints a new sentry-sealed return
         //  capability as a side effect of every jump, via a dedicated
         //  reserved otype): this instruction is scoped to exactly the
         //  verify-and-consume half the vulnerability was in, reusing
         //  Milestone 6's existing CSeal/CUnseal type-authority model
         //  rather than inventing a second, parallel sealing mechanism.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocjalr = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010100);
         // RTL-7 (R11): OCJALR jumps to cs1.Base exactly as the two real
         // crossings do, so it needs the identical revalidation even though
         // it is intra-domain by design and carries no region check.
         // Intra-domain says WHICH table resolves the Object_ID, not
         // whether the object still exists.
         $veda_ocjalr_violation = $is_veda_ocjalr && (
            !$veda_rs1cap_tag || !$veda_cs2_tag ||
            !$veda_sealed || $veda_cs2_sealed ||
            !$veda_cs2_perms[9] ||
            ($veda_cs2_offset != $veda_rs1cap_otype) ||
            !$veda_rs1cap_perms[1] ||
            $veda_gen_stale || $veda_deref_nonresident);
         $veda_ocjalr_cause[4:0] =
            !$veda_rs1cap_tag                       ? 5'h02 :
            !$veda_cs2_tag                          ? 5'h02 :
            !$veda_sealed                           ? 5'h03 :
            $veda_cs2_sealed                        ? 5'h03 :
            !$veda_cs2_perms[9]                     ? 5'h03 :
            ($veda_cs2_offset != $veda_rs1cap_otype) ? 5'h04 :
            // RTL-7 (R11). Execute-permission was this chain's IMPLICIT
            // default, so it is promoted to an explicit arm -- otherwise
            // the two new arms are unreachable dead code, and placing them
            // first would report 0x02 for a capability that simply is not
            // executable.
            !$veda_rs1cap_perms[1]                  ? 5'h11 :
            $veda_gen_stale                         ? 5'h02 :
            $veda_deref_nonresident                 ? 5'h0A :
                                                        5'h11;
         $veda_ocjalr_cap_idx[3:0] =
            !$veda_rs1cap_tag                       ? $veda_ocl_ocs_rs1_cap :
            !$veda_cs2_tag                          ? $veda_cseal_cunseal_rs2_cap :
            !$veda_sealed                           ? $veda_ocl_ocs_rs1_cap :
            $veda_cs2_sealed                        ? $veda_cseal_cunseal_rs2_cap :
            !$veda_cs2_perms[9]                     ? $veda_cseal_cunseal_rs2_cap :
            ($veda_cs2_offset != $veda_rs1cap_otype) ? $veda_ocl_ocs_rs1_cap :
                                                        $veda_ocl_ocs_rs1_cap;
         $veda_ocjalr_target[63:0] = {8'b0, $veda_rs1cap_base} + {24'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  Minimal OS kernel Milestone B (MILESTONE_B_RESULTS.md):
         //  VEDA_OCRETURN -- the actual cheap, cross-compartment-
         //  boundary-crossing counterpart to OCJALR's own always-two-
         //  operand design above. Deliberately a NEW opcode rather than
         //  a sentry branch folded into OCJALR: OCJALR's own rs2 is a
         //  fixed encoding field (folding a branch in would either still
         //  require rs2 to be supplied unused, defeating the single-
         //  operand premise, or make one static encoding mean two
         //  different things depending on runtime capability contents --
         //  this file's own convention already gives each distinct
         //  security-relevant behavior its own funct7, e.g. OCA/
         //  CSetBounds/CSetBoundsExact). OCJALR itself is completely
         //  unmodified by this addition -- direct, load-bearing
         //  preservation of RTL Milestone 22's own already-shipped,
         //  already-tested "OCJALR cannot cross a compartment boundary"
         //  finding (veda_smoke_m22.S).
         //
         //  cs1 must be a genuine VEDA_CSEALENTRY-minted sentry (otype
         //  == 0xFFFE, a value ordinary CSeal is now hardware-blocked
         //  from ever producing, per the hardened $veda_cseal_authorized
         //  above) -- verified with exactly the same three checks
         //  OCJALR's own cs1-side already performs (tag, seal-validity,
         //  Permit_Execute), reusing the identical cause codes, but with
         //  NO second, type-authority capability operand at all: a
         //  sentry's own otype is self-authenticating, unlike an
         //  arbitrary CSeal otype which always needs an explicit
         //  CUnseal-style authority to vouch for it. Permit_Invoke is
         //  deliberately NOT checked -- matches real CHERI's own sentry/
         //  CJALR mechanism exactly.
         //
         //  On success, narrows $veda_pcc_base/$veda_pcc_length to cs1's
         //  own Base/Length (defined further below, alongside
         //  OCInvoke's own identical assignment) -- the actual
         //  compartment-boundary-crossing side effect. c15 (IDC) is
         //  deliberately left untouched (not cleared): real CJALR never
         //  touches IDC either (only CInvoke does), and OCInvoke's own
         //  write-back mux above already treats "install data-capability
         //  context" and "narrow PCC" as two independently-triggered
         //  effects, so OCRETURN adopting only the PCC half reuses a
         //  split this file already makes internally rather than
         //  inventing a new one.
         //
         //  funct7 = 0010110, the next free Custom-2/funct3=001 slot
         //  after CSealEntry's own 0010101 above (verified by grep
         //  against every existing user of this space before picking
         //  it). Single source operand, reusing the same shared rs1-cap
         //  field every other Custom-2 instruction already shares -- no
         //  new field extraction needed. cap_idx for a trap needs no new
         //  per-family branch in $veda_trap_cap_idx below -- its own
         //  existing default fallback is already $veda_ocl_ocs_rs1_cap,
         //  exactly the single operand OCRETURN has.
         // ─────────────────────────────────────────────────────────
         $is_veda_ocreturn = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010110);
         // RTL-5 (R10): the return half, and the sharper half of the escape
         // closure -- the original hole was precisely that OCReturn restored
         // no region, so a caller resumed holding the callee's domain as
         // "current" (fault-exempt by construction). The domain being
         // RETURNED TO is the region field of the SENTRY's own Object_ID:
         // csealentry carries the source object's Object_ID into the sentry
         // (the $csealentry_wr_en arm of /vreg's $object_id), so the
         // caller's domain is named unforgeably at mint time.
         $veda_ocreturn_region_fault = $is_veda_ocreturn && !$veda_crossing_rt_resident;
         // RTL-7 (R11): a return is a crossing, and the one where an
         // evicted object is MOST likely -- a callee runs for an unbounded
         // time and the caller's code object is exactly the cold page a
         // pager picks. Sail mutation testing proved this arm needs its own
         // test: deleting OCRETURN's revalidation left the whole suite
         // passing while the other two crossings were covered.
         $veda_ocreturn_violation = $is_veda_ocreturn && (
            !$veda_rs1cap_tag || !$veda_sealed ||
            ($veda_rs1cap_otype != 16'hFFFE) ||
            !$veda_rs1cap_perms[1] ||
            !$veda_crossing_rt_resident ||
            $veda_gen_stale || $veda_deref_nonresident);
         $veda_ocreturn_cause[4:0] =
            !$veda_rs1cap_tag                    ? 5'h02 :
            !$veda_sealed                        ? 5'h03 :
            ($veda_rs1cap_otype != 16'hFFFE)     ? 5'h03 :
            // RTL-5 (R10): explicit arm ahead of the 5'h11 default, same
            // reason as OCInvoke's. cap_idx needs no new arm here --
            // OCRETURN's single operand IS $veda_ocl_ocs_rs1_cap, which is
            // already $veda_trap_cap_idx's default fallback.
            !$veda_crossing_rt_resident          ? 5'h09 :
            // RTL-7 (R11), same promotion of the implicit default.
            !$veda_rs1cap_perms[1]               ? 5'h11 :
            $veda_gen_stale                      ? 5'h02 :
            $veda_deref_nonresident              ? 5'h0A :
                                                    5'h11;
         $veda_ocreturn_target[63:0] = {8'b0, $veda_rs1cap_base} + {24'b0, $veda_rs1cap_offset};

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 11: OSpecialRW + capability-authority-gated
         //  ODT-Populate/ODT-Destroy (NEXT_STEPS_ROADMAP.md §2.5).
         //  Mirrors veda_cap_insts.sail's own VEDA_OSPECIALRW field-for-
         //  field. funct7 = 0010011, the next unused Custom-2 slot after
         //  OCInvoke (0010010). Reads/writes the ODA (Object Descriptor
         //  Authority) -- Veda-Core's own single Special Capability
         //  Register, real CHERI's own CSpecialRW/SCR model (CHERI ISA
         //  spec §4.3.6) adapted to Veda-Core's one-SCR case (no scr-
         //  index operand needed). Real CHERI's own access rule (Table
         //  4.3's "ASR" column) needs PCC.perms to grant
         //  PERMIT_ACCESS_SYSTEM_REGISTERS -- Veda-Core has no PCC
         //  (Milestone 10's own stated scope boundary), so this RTL
         //  gates OSpecialRW itself on ordinary privilege alone
         //  ($priv), the identical, already-established convention
         //  ODT-Populate/ODT-Destroy themselves already use below.
         // ─────────────────────────────────────────────────────────
         // R30: the SCR selector sits in the rs2 field and was never validated.
         // Sail's encdec_veda_scr (veda_cap_insts.sail:883-887) maps exactly
         // three values, so 29 of 32 are decode-undefined there -- a hole in the
         // MIDDLE of an allocated funct7, not at the edge of the space. Here the
         // ODA write was gated on `!is_tsc && !is_ssc`, so every one of those 29
         // reached the Object Descriptor Authority. Narrowing the decode makes
         // the whole instruction undefined for a bad selector, which is exactly
         // what Sail does, and it fixes the ODA gate as a side effect rather
         // than needing the gate rewritten separately.
         $veda_ospecialrw_sel_known = ($instr[24:20] == 5'b00000) || ($instr[24:20] == 5'b00001) ||
                                      ($instr[24:20] == 5'b00010);
         $is_veda_ospecialrw = $op_is_custom2 && ($funct3 == 3'b001) && ($funct7 == 7'b0010011) && $veda_ospecialrw_sel_known;
         $veda_ospecialrw_violation = $is_veda_ospecialrw && !$priv;

         // RTL mirror of minimal OS kernel Milestone A
         // (MINIMAL_OS_KERNEL_DESIGN.md): the SCR-selector operand
         // veda_cap_insts.sail's own VEDA_OSPECIALRW extension added,
         // read from the FULL 5-bit rs2 register-field position
         // ($instr[24:20]) -- unlike every vcapidx-shaped rs2-capability
         // operand elsewhere in this file (e.g.
         // $veda_cseal_cunseal_rs2_cap[3:0] = $instr[23:20], a 0-spacer
         // + 4-bit split), Sail's own encdec_veda_scr mapping consumes
         // the entire 5-bit field directly, confirmed by re-reading that
         // mapping before writing this, not assumed from the vcap
         // pattern. 5'b00000 = VEDA_SCR_ODA (the pre-existing, only
         // encoding every already-shipped test still uses -- x0 in this
         // position, backward-compatible by construction); 5'b00001 =
         // VEDA_SCR_TSC; 5'b00010 = VEDA_SCR_SSC (SSC milestone --
         // SSC_STACK_SPILL_CAPABILITY_DESIGN.md, mirrors the Sail side's
         // own encdec_veda_scr mapping exactly).
         $veda_ospecialrw_scr_sel[4:0] = $instr[24:20];
         $veda_ospecialrw_scr_is_tsc = ($veda_ospecialrw_scr_sel == 5'b00001);
         $veda_ospecialrw_scr_is_ssc = ($veda_ospecialrw_scr_sel == 5'b00010);

         // The ODA itself: a persistent capability register, structurally
         // identical to a /vreg entry but deliberately kept OUTSIDE the
         // CRF (VEDA_CORE_SPEC.md's own reasoning: it plays a genuinely
         // different architectural role -- a capability-authority
         // context for privileged instructions, not a general-purpose
         // capability register any Object-Bind/OCL/OCS/etc. can target).
         // Same real persistent-signal idiom already proven for
         // $mtvec/$mepc/$mcause/$mtval (Milestone 9), not a new one.
         // Minimal OS kernel Milestone A addition: write now also
         // requires the selector to specifically pick ODA (previously
         // unconditional whenever OSpecialRW fired at all, back when
         // ODA was the only SCR) -- TSC below mirrors this exactly with
         // the opposite selector value, so the two registers are
         // genuinely independent, never aliased.
         $veda_oda_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_oda_tag;
         $veda_oda_object_id[43:0] = (|cpu$reset || |cpu>>1$reset) ? 44'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_oda_object_id;
         $veda_oda_base[55:0] = (|cpu$reset || |cpu>>1$reset) ? 56'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_oda_base;
         $veda_oda_length[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_oda_length;
         $veda_oda_offset[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_oda_offset;
         $veda_oda_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_oda_perms;
         $veda_oda_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_oda_otype;
         $veda_oda_reserved[23:0] = (|cpu$reset || |cpu>>1$reset) ? 24'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && !>>1$veda_ospecialrw_scr_is_tsc && !>>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_oda_reserved;

         // The real, load-bearing check every OSpecialRW consumer
         // ultimately depends on -- mirrors Sail's own
         // veda_oda_authorized() exactly: a live, unsealed ODA carrying
         // PERMIT_ACCESS_SYSTEM_REGISTERS (bit 7 -- already reserved in
         // the Perms table since CHERI adoption, never before consumed
         // by any real instruction).
         $veda_oda_sealed = ($veda_oda_otype != 16'hFFFF);
         $veda_oda_authorized = $veda_oda_tag && !$veda_oda_sealed && $veda_oda_perms[7];

         // The TSC (Trusted Stack Capability): minimal OS kernel
         // Milestone A's own second Special Capability Register, term-
         // for-term adapted from real CHERIoT's own `mtdc`
         // (MINIMAL_OS_KERNEL_DESIGN.md). Structurally identical to the
         // ODA's own 8-field persistent-register pattern immediately
         // above, mirrored field-for-field, gated by the opposite
         // selector value so the two registers are never aliased.
         $veda_tsc_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_tsc_tag;
         $veda_tsc_object_id[43:0] = (|cpu$reset || |cpu>>1$reset) ? 44'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_tsc_object_id;
         $veda_tsc_base[55:0] = (|cpu$reset || |cpu>>1$reset) ? 56'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_tsc_base;
         $veda_tsc_length[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_tsc_length;
         $veda_tsc_offset[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_tsc_offset;
         $veda_tsc_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_tsc_perms;
         $veda_tsc_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_tsc_otype;
         $veda_tsc_reserved[23:0] = (|cpu$reset || |cpu>>1$reset) ? 24'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_tsc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_tsc_reserved;

         // The SSC (Stack-Spill Capability): SSC_STACK_SPILL_CAPABILITY_
         // DESIGN.md's own third Special Capability Register, added to
         // give ordinary compiled C's ABI-mandated callee-saved-register
         // spills a real, dedicated, capability-checked register to
         // route through instead of raw sd/ld (which Milestone 19's
         // purecap rule unconditionally traps inside a live compartment).
         // Structurally identical to the ODA/TSC 8-field persistent-
         // register pattern above, mirrored field-for-field, gated by
         // its own selector value so all three SCRs stay genuinely
         // independent. Unlike ODA/TSC, this register is ALSO cleared
         // by $is_veda_ocinvoke and $is_veda_ocreturn below (their own
         // violation-gated blocks) -- deliberately NOT persistent-and-
         // -boundary-crossing-transparent like ODA/TSC, per an
         // independent design review's real finding (see the design
         // doc): an SSC following ODA/TSC's own "untouched by OCInvoke"
         // convention would let a callee compartment silently inherit
         // full OCL.D/OCS.D access to the caller's entire stack region.
         $veda_ssc_tag = (|cpu$reset || |cpu>>1$reset) ? 1'b0 :
                          (>>1$is_veda_ocinvoke && !>>1$veda_ocinvoke_violation) ? 1'b0 :
                          (>>1$is_veda_ocreturn && !>>1$veda_ocreturn_violation) ? 1'b0 :
                          (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_tag :
                                                                                        >>1$veda_ssc_tag;
         $veda_ssc_object_id[43:0] = (|cpu$reset || |cpu>>1$reset) ? 44'b0 :
                                      (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_object_id :
                                                                                                     >>1$veda_ssc_object_id;
         $veda_ssc_base[55:0] = (|cpu$reset || |cpu>>1$reset) ? 56'b0 :
                                 (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_base :
                                                                                                >>1$veda_ssc_base;
         $veda_ssc_length[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_length :
                                                                                                  >>1$veda_ssc_length;
         $veda_ssc_offset[39:0] = (|cpu$reset || |cpu>>1$reset) ? 40'b0 :
                                   (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_offset :
                                                                                                  >>1$veda_ssc_offset;
         $veda_ssc_perms[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'b0 :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_perms :
                                                                                                 >>1$veda_ssc_perms;
         $veda_ssc_otype[15:0] = (|cpu$reset || |cpu>>1$reset) ? 16'hFFFF :
                                  (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_otype :
                                                                                                 >>1$veda_ssc_otype;
         $veda_ssc_reserved[23:0] = (|cpu$reset || |cpu>>1$reset) ? 24'b0 :
                                    (>>1$is_veda_ospecialrw && !>>1$veda_ospecialrw_violation && >>1$veda_ospecialrw_scr_is_ssc) ? >>1$veda_rs1cap_reserved :
                                                                                                   >>1$veda_ssc_reserved;

         // ─────────────────────────────────────────────────────────
         //  VEDA-CORE: NMC_ADD.{W,D} and Veda-Atomic share the same
         //  capability-positioned real-address computation and, at
         //  D-width, the same read of the current value -- both operate
         //  on the capability's own *persistent* Offset (Section 1),
         //  unlike OCL/OCS's fresh per-access GPR offset ($veda_real_addr
         //  above). Gated on Permit_NMC_Compute (NMC_ADD, its own
         //  dedicated bit, Section 2) vs. Permit_Load+Permit_Store
         //  (Veda-Atomic, a general RMW, not the dedicated compute-at-
         //  memory dispatch NMC_ADD is) -- the identical permission split
         //  already reasoned through and built in Sail.
         // ─────────────────────────────────────────────────────────
         $veda_cap_real_addr[63:0] = {8'b0, $veda_rs1cap_base} + {24'b0, $veda_rs1cap_offset};
         $veda_cap_old_d[63:0] =
            {elfmem[$veda_cap_real_addr[31:0]+7], elfmem[$veda_cap_real_addr[31:0]+6],
             elfmem[$veda_cap_real_addr[31:0]+5], elfmem[$veda_cap_real_addr[31:0]+4],
             elfmem[$veda_cap_real_addr[31:0]+3], elfmem[$veda_cap_real_addr[31:0]+2],
             elfmem[$veda_cap_real_addr[31:0]+1], elfmem[$veda_cap_real_addr[31:0]+0]};
         $veda_cap_old_w[31:0] =
            {elfmem[$veda_cap_real_addr[31:0]+3], elfmem[$veda_cap_real_addr[31:0]+2],
             elfmem[$veda_cap_real_addr[31:0]+1], elfmem[$veda_cap_real_addr[31:0]+0]};

         $veda_perm_nmc_ok = $veda_rs1cap_perms[12];
         $veda_nmc_bounds_ok_d = (({24'b0, $veda_rs1cap_offset}) + 64'd8) <= {24'b0, $veda_rs1cap_length};
         $veda_nmc_bounds_ok_w = (({24'b0, $veda_rs1cap_offset}) + 64'd4) <= {24'b0, $veda_rs1cap_length};

         // Only consumed by the trailing raw \SV always_ff block below
         // (invisible to SandPiper's own TLV-level dependency tracking,
         // same real reason $veda_ocs_value needed this).
         $veda_nmc_add_result_d[63:0] = $rs2_data + $veda_cap_old_d;
         `BOGUS_USE($veda_nmc_add_result_d)
         $veda_nmc_add_result_w[31:0] = $rs2_data[31:0] + $veda_cap_old_w;
         `BOGUS_USE($veda_nmc_add_result_w)
         // rd receives the *old* value, matching real AMOADD's return
         // convention exactly (Section 1) -- W sign-extends, D doesn't
         // need to (already xlen-wide).
         $veda_nmc_rd_value[63:0] = $is_veda_nmc_add_w ? {{32{$veda_cap_old_w[31]}}, $veda_cap_old_w} : $veda_cap_old_d;

         // RTL-13: NMC_ADD IS A LOAD AND A STORE, and asked for neither.
         // Permit_NMC_Compute was its only permission gate, so a capability
         // with Permit_Store stripped still wrote through it -- and the seeded
         // Perms 0x100C carry Load|Store|NMC together, so attenuating bit 3
         // leaves bit 12 set and the write lands. That made every store-side
         // attenuation advisory, including the one copy-on-write is to be
         // built on. Veda-Atomic, the identical read-modify-write shape, has
         // required both since it was written; NMC is the one nobody asked
         // about. Permit_NMC_Compute stays as an ADDITIONAL gate, not a
         // substitute.
         $veda_nmc_add_w_violation = $is_veda_nmc_add_w && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_nmc_ok || !$veda_perm_load_ok || $veda_cow_write || !$veda_perm_store_ok || !$veda_nmc_bounds_ok_w || $veda_deref_nonresident);
         // RTL-13: NMC_ADD IS A LOAD AND A STORE, and asked for neither.
         // Permit_NMC_Compute was its only permission gate, so a capability
         // with Permit_Store stripped still wrote through it -- and the seeded
         // Perms 0x100C carry Load|Store|NMC together, so attenuating bit 3
         // leaves bit 12 set and the write lands. That made every store-side
         // attenuation advisory, including the one copy-on-write is to be
         // built on. Veda-Atomic, the identical read-modify-write shape, has
         // required both since it was written; NMC is the one nobody asked
         // about. Permit_NMC_Compute stays as an ADDITIONAL gate, not a
         // substitute.
         $veda_nmc_add_d_violation = $is_veda_nmc_add_d && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_nmc_ok || !$veda_perm_load_ok || $veda_cow_write || !$veda_perm_store_ok || !$veda_nmc_bounds_ok_d || $veda_deref_nonresident);

         // Veda-Atomic ALU: op-select values reuse real RISC-V Zaamo's
         // own encoding (see decode comment above). Signed MIN/MAX use
         // the same sign-bit-based technique as $lt_signed elsewhere in
         // this file, not $signed().
         $veda_atomic_lt_signed = ($rs2_data[63] != $veda_cap_old_d[63]) ? $rs2_data[63] : ($rs2_data < $veda_cap_old_d);
         $veda_atomic_result[63:0] =
            ($veda_atomic_op == 5'b00001) ? $rs2_data :                                                     // SWAP
            ($veda_atomic_op == 5'b00000) ? ($rs2_data + $veda_cap_old_d) :                                 // ADD
            ($veda_atomic_op == 5'b00100) ? ($rs2_data ^ $veda_cap_old_d) :                                 // XOR
            ($veda_atomic_op == 5'b01100) ? ($rs2_data & $veda_cap_old_d) :                                 // AND
            ($veda_atomic_op == 5'b01000) ? ($rs2_data | $veda_cap_old_d) :                                 // OR
            ($veda_atomic_op == 5'b10000) ? ($veda_atomic_lt_signed ? $rs2_data : $veda_cap_old_d) :        // MIN
            ($veda_atomic_op == 5'b10100) ? ($veda_atomic_lt_signed ? $veda_cap_old_d : $rs2_data) :        // MAX
            ($veda_atomic_op == 5'b11000) ? (($rs2_data < $veda_cap_old_d) ? $rs2_data : $veda_cap_old_d) : // MINU
            ($veda_atomic_op == 5'b11100) ? (($rs2_data > $veda_cap_old_d) ? $rs2_data : $veda_cap_old_d) : // MAXU
                                             64'b0;
         // Only consumed by the trailing raw \SV always_ff block below.
         `BOGUS_USE($veda_atomic_result)
         $veda_atomic_violation = $is_veda_atomic && (!$veda_rs1cap_tag || $veda_gen_stale || $veda_sealed || !$veda_perm_load_ok || $veda_cow_write || !$veda_perm_store_ok || !$veda_nmc_bounds_ok_d || $veda_deref_nonresident);

         $veda_violation = $veda_ocl_violation || $veda_ocs_violation ||
                           $veda_nmc_add_w_violation || $veda_nmc_add_d_violation ||
                           $veda_atomic_violation;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: per-family cause codes, mirroring
         //  veda_bind_insts.sail's own VEDA_CAUSE_* constants and
         //  veda_check_access/veda_check_nmc_access's exact if-else
         //  priority order (Tag/generation -> Seal -> Permission ->
         //  Bounds) field-for-field -- not re-derived or approximated.
         //  Only the seven "use" families that actually call
         //  veda_check_access/veda_check_nmc_access in Sail (and
         //  therefore genuinely veda_trap()) get a cause signal here;
         //  OCA/CSetBounds/CSetBoundsExact/CSeal/CUnseal are correctly
         //  absent -- Sail's own execute clauses for those never call
         //  either check function at all, they soft-fail by
         //  unconditional design (see the /vreg comment block below),
         //  not because RTL trap infrastructure was missing until now.
         // ─────────────────────────────────────────────────────────
         // ─────────────────────────────────────────────────────────
         //  RTL-6b: RESIDENCY_FAULT (0x0A) enters all seven chains, and
         //  doing so required RESTRUCTURING them rather than appending an
         //  arm. This is the single most error-prone edit in RTL-6 and the
         //  reason is worth stating once, here, for all seven.
         //
         //  Sail places the residency term LAST, after bounds, and says
         //  why: RESIDENCY_FAULT is raised only for an access that would
         //  otherwise have SUCCEEDED. That is an information-flow property,
         //  not a stylistic one. Reporting 0x0A for an access that was
         //  going to fail anyway invites a pager to fetch an object to
         //  service a request that will be refused on arrival -- and lets
         //  an attacker drive unbounded paging with deliberately
         //  out-of-bounds offsets.
         //
         //  But in these chains BOUNDS WAS NEVER AN EXPLICIT TEST. The
         //  trailing 5'h01 was a fall-through default: reached when the
         //  violation fired and no earlier arm matched, which could only
         //  mean bounds. Adding residency to the violation OR breaks that
         //  reasoning -- the default is now reachable two ways.
         //
         //  So each chain gains an explicit `!<bounds> ? 5'h01 :` and
         //  residency becomes the new default. Appending `? 5'h0A` after
         //  the old default instead would have been unreachable dead code;
         //  inserting it before would have reported 0x0A for every
         //  out-of-bounds access. Both compile clean.
         //
         //  Each chain must name ITS OWN bounds signal -- there are four
         //  ($veda_bounds_ok, $veda_oclc_bounds_ok, $veda_nmc_bounds_ok_w,
         //  $veda_nmc_bounds_ok_d) and they are not interchangeable; each
         //  is paired here with the one its own violation expression uses.
         //
         //  The 0x08 capability-misalignment arm in the OCL.C/OCS.C chains
         //  has no Sail counterpart, so its position relative to 0x0A was a
         //  decision rather than a transcription: it stays AHEAD, on the
         //  same principle -- a misaligned access would not have succeeded
         //  either, so residency is not the useful thing to report.
         // ─────────────────────────────────────────────────────────
         // R19 increment 1 -- THE ORDER OF THIS CHAIN IS THE SECURITY PROPERTY.
         // Two classes of arm. REFUSALS (0x02 0x03 0x12 0x13 0x1f 0x08 0x01) say
         // "never allowed"; order among them is cosmetic. REPAIRS (0x0A residency,
         // 0x0C copy-on-write) say "fix something and retry", and each ARMS REAL
         // WORK in a handler -- a page-in, or an allocate-copy-mint. Raising a
         // repair for an access a refusal was going to reject anyway arms that
         // work for nothing. So every refusal precedes every repair. That rule was
         // already written down here for residency ("raised only for an access
         // that would otherwise have SUCCEEDED"); the cow arm violated it from the
         // day it landed, sitting third.
         //
         // 0x0A BEFORE 0x0C: you cannot copy an object that is not in memory --
         // the handler would dereference a Base whose frame the pager may already
         // have reassigned.
         //
         // The 0x13 arm is GATED on !$veda_cow_write. Without the gate, moving cow
         // to the bottom breaks fork() outright: veda_bind_perms masks a cow
         // object's Perms with 16'hFFF7, so a freshly bound capability lacks store
         // BY CONSTRUCTION and every fork write would report "you may not write"
         // instead of "copy me". The old order's property is preserved exactly --
         // by the gate rather than by precedence.
         //
         // The DEFAULT IS DELIBERATELY HOSTILE (5'h02), never 0x0C. 0x0C is the
         // only cause that tells software to hand back a fresh writable object: a
         // spurious 0x0A makes the pager refuse loudly, a spurious 0x0C succeeds
         // SILENTLY. All arms explicit, all seven chains one shape, diffable
         // against Sail arm for arm.
         //
         // The trap SET is provably unchanged, so the violation OR-expressions are
         // untouched -- they also feed R21's stall gate, and restructuring one is
         // the single way this edit could reopen R21:
         //   old (cow) | (!STORE)  ==  new (!STORE & !cow) | (cow)
         $veda_ocl_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
            !$veda_bounds_ok                       ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
                                                      5'h02;
         $veda_ocs_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            (!$veda_perm_store_ok && !$veda_cow_write) ? 5'h13 :
            !$veda_bounds_ok                       ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
            $veda_cow_write                        ? 5'h0C :
                                                      5'h02;
         $veda_oclc_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
            $veda_capmem_misaligned                ? 5'h08 :
            !$veda_oclc_bounds_ok                  ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
                                                      5'h02;
         $veda_ocsc_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            (!$veda_perm_store_ok && !$veda_cow_write) ? 5'h13 :
            $veda_capmem_misaligned                ? 5'h08 :
            !$veda_oclc_bounds_ok                  ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
            $veda_cow_write                        ? 5'h0C :
                                                      5'h02;
         $veda_nmc_add_w_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_nmc_ok                     ? 5'h1f :
            !$veda_perm_load_ok                    ? 5'h12 :
            (!$veda_perm_store_ok && !$veda_cow_write) ? 5'h13 :
            !$veda_nmc_bounds_ok_w                 ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
            $veda_cow_write                        ? 5'h0C :
                                                      5'h02;
         $veda_nmc_add_d_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_nmc_ok                     ? 5'h1f :
            !$veda_perm_load_ok                    ? 5'h12 :
            (!$veda_perm_store_ok && !$veda_cow_write) ? 5'h13 :
            !$veda_nmc_bounds_ok_d                 ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
            $veda_cow_write                        ? 5'h0C :
                                                      5'h02;
         // Atomic reuses veda_check_access with need_load=need_store=
         // true -- Sail checks Permit_Load before Permit_Store in that
         // case (veda_ocl_insts.sail's own if-else chain), so a missing
         // Permit_Load must win the cause code over a missing
         // Permit_Store when both happen to be absent, matching exactly.
         $veda_atomic_cause[4:0] =
            (!$veda_rs1cap_tag || $veda_gen_stale) ? 5'h02 :
            $veda_sealed                           ? 5'h03 :
            !$veda_perm_load_ok                    ? 5'h12 :
            (!$veda_perm_store_ok && !$veda_cow_write) ? 5'h13 :
            !$veda_nmc_bounds_ok_d                 ? 5'h01 :
            $veda_deref_nonresident                ? 5'h0A :
            $veda_cow_write                        ? 5'h0C :
                                                      5'h02;

         // One combined trap-taken signal + cause mux across every real
         // hard-trapping family. cap_idx is NOT muxed per-family -- all
         // seven share the identical rs1-capability field position
         // ($veda_ocl_ocs_rs1_cap, already established and reused
         // throughout this file), so the same signal is correct
         // regardless of which family actually trapped.
         // RTL Milestone 10 addition: OCInvoke joins the same combined
         // trap-taken family. Its own cap_idx is NOT the shared
         // $veda_ocl_ocs_rs1_cap every other family here can rely on
         // (OCInvoke genuinely spans two distinct capability registers)
         // -- $veda_trap_cap_idx below resolves that per-family, falling
         // back to the shared field for every family that only ever
         // involves one capability register.
         // RTL Milestone 12/13 addition: plain Bind's own two hard-trap
         // reasons (owner-violation, object-not-found -- combined into
         // $veda_bind_trap) join the same combined trap-taken family
         // too. Their shared cap_idx is rd (the destination capability
         // register, $veda_rd_cap), NOT rs1 -- mirrors
         // veda_bind_insts.sail's own `veda_trap(rd, ...)` call exactly
         // for both cause codes (every other family here traps on the
         // capability being DEREFERENCED, rs1; Bind's own cap_idx is the
         // capability being WRITTEN, rd).
         // RTL Milestone 14 addition: $veda_pcc_violation joins the same
         // combined trap-taken family -- its own cap_idx (16, the PCC
         // sentinel) and cause (0x01, reused) are both fixed constants,
         // built directly into $mtval's own construction below rather
         // than routed through $veda_trap_cap_idx[3:0] (only 4 bits wide,
         // can't carry the 5-bit sentinel value 16 without a wider,
         // more invasive change to every existing call site) -- the
         // identical "built inline, not through the typed interface"
         // choice already made on the Sail side (veda_bind_insts.sail's
         // veda_trap() vs. the PCC hook's own direct handle_exception()
         // call).
         // RTL Milestone 19 addition: $veda_purecap_violation joins the
         // same combined trap-taken family -- its own cap_idx (17, the
         // "this was purecap enforcement, not a real capability register"
         // sentinel -- the next free value after PCC's own 16) and cause
         // (0x07, VEDA_CORE_SPEC.md's previously-reserved slot, matching
         // the Sail side) are both fixed constants, built directly into
         // $mtval's own construction below, the identical "built inline,
         // not through the typed interface" choice PCC's own cap_idx=16
         // already established (see that comment above) -- 17 doesn't fit
         // $veda_trap_cap_idx[3:0] (4 bits, max 15) either.
         // RTL Milestone 20 addition: $veda_csr_escape_violation joins
         // the same combined trap-taken family -- it needs no special
         // cap_idx/cause handling of its own beyond $mcause's own
         // mcause=0x02 special-case below (see that comment), because
         // the existing, uniform "any trap resets veda_pcc_base/_length
         // to unbounded, saving the pre-trap bounds into
         // veda_mepcc_base/_length" priority (already the highest
         // -priority branch in each of those four CSRs' own definitions)
         // already correctly prevents the attacker-controlled csr_wdata
         // from ever landing, for free, with no extra per-CSR guard
         // needed -- confirmed by direct inspection before relying on
         // it. veda_mode (0x7C5) has no such pre-existing trap-reset
         // branch of its own (unlike the PCC-family CSRs, nothing else
         // ever writes it), so its own write-gating expression below
         // gets an explicit, separate guard instead.
         // Minimal OS kernel Milestone B: $veda_ocreturn_violation joins
         // the same combined trap-taken family -- its own cap_idx needs
         // NO new branch in $veda_trap_cap_idx below (single operand,
         // already the shared $veda_ocl_ocs_rs1_cap position, exactly
         // the existing default fallback).
         // RTL Milestone 23: $is_ecall joins the same combined
         // trap-taken family -- unlike every other term here (all
         // conditional security violations), ecall is unconditional by
         // design: executing it always traps, no separate violation
         // gate needed. No same-cycle collision risk with any other
         // term -- every other term gates on Custom-0/1/2 opcodes or
         // is_load/is_store/CSRRW/CSRRS, all disjoint from SYSTEM
         // opcode; $veda_pcc_violation forces $instr to a NOP before
         // decode, so it's provably mutually exclusive with $is_ecall
         // needing an exact literal match.
         $veda_trap_taken = $veda_ocl_violation || $veda_ocs_violation ||
                             $veda_oclc_violation || $veda_ocsc_violation ||
                             $veda_nmc_add_w_violation || $veda_nmc_add_d_violation ||
                             // R30/R32: $veda_trap_taken and $veda_illegal_instr are
                             // SEPARATE lists in this file. A new illegal source must
                             // join both -- one alone gives a trap with the wrong cause,
                             // or a cause with no trap.
                             $veda_undef_encoding || $veda_csr_undef ||
                             $veda_atomic_violation || $veda_ocinvoke_violation ||
                             $veda_ocjalr_violation || $veda_ocreturn_violation ||
                             $veda_bind_trap || $veda_pcc_violation ||
                             $veda_purecap_violation || $veda_csr_escape_violation ||
                             $veda_domain_violation ||
                             $veda_region_fault ||
                             $veda_residency_fault ||
                             // RTL-6c: the paging pair's refusals really
                             // TRAP. See $veda_illegal_instr below for why
                             // this was a design decision rather than a
                             // transcription.
                             $veda_odt_page_out_refusal ||
                             $veda_odt_page_in_refusal ||
                             // RTL-11 (R14, DESIGN_07 Tier H): POPULATE AND DESTROY
                             // NOW TRAP ON EVERY GATE, as the model always did.
                             //
                             // These two refused silently: they suppressed the
                             // ODT write and the rd write and raised nothing, so
                             // an unprivileged program could execute a privileged
                             // instruction and be told nothing. Sail raises
                             // Illegal_Instruction for all three gates
                             // (privilege/authority, the executing-object pin,
                             // and retired), page-out and page-in in this very
                             // file already trap on the SAME authority gate, and
                             // RISC-V's own convention for an instruction the
                             // current privilege may not execute is exactly this
                             // trap. The silence was never argued for anywhere --
                             // it was simply what the file did.
                             $veda_odt_populate_violation ||
                             $veda_odt_destroy_violation ||
                             $veda_odt_set_domain_violation ||
                             $veda_odt_set_cow_violation ||
                             $is_ecall;
         // ─────────────────────────────────────────────────────────
         //  RTL-6c: a general ILLEGAL-INSTRUCTION umbrella.
         //
         //  Until now this core produced mcause 0x02 from exactly ONE
         //  signal, named by hand in two separate ternaries
         //  ($veda_csr_escape_violation, at $mcause and $mtval below).
         //  There was no general mechanism. Sail's page-out and page-in
         //  refuse via Illegal_Instruction(), so mirroring them was a real
         //  DESIGN QUESTION, not transcription, and it is recorded here
         //  because the alternative was available and defensible.
         //
         //  THE ALTERNATIVE, and why it was rejected. Populate and Destroy
         //  already have a refusal convention in this file: the write is
         //  suppressed and nothing else happens. PC advances, rd keeps its
         //  old value, mcause is untouched. Inheriting that floor would
         //  have been consistent and cost nothing, and the saturation
         //  refusal's MEMORY-level safety would still hold -- no write
         //  means no corruption.
         //
         //  But it would make the refusal UNOBSERVABLE. A refused page-out
         //  would be architecturally indistinguishable from a successful
         //  one, so a pager could not tell that eviction failed and would
         //  believe it had freed a frame it had not. And the value of this
         //  pair concentrates in what it REFUSES -- the Sail-side mutation
         //  testing made that concrete: of six mutants, the four that
         //  survived the first pass were all refusals or preservations.
         //  A refusal software cannot see is half a feature.
         //
         //  So the existing single-purpose mechanism is generalized rather
         //  than duplicated. Adding a third hand-named signal to two
         //  ternaries would have worked and would have been the fourth
         //  place to forget next time.
         // ═══════════════════════════════════════════════════════════════════
         //  R30 -- FAIL-CLOSED DECODE. Every encoding in Veda's opcode space
         //  that this core does not implement now traps, as the architecture
         //  requires and as the model has always done.
         //
         //  THE MODEL IS FAIL-CLOSED BY CONSTRUCTION and says so:
         //  model/sys/insts_begin.sail declares `ILLEGAL : word` with the
         //  comment "the encdec mapping must come last to ensure that all
         //  unmatched encodings decode to an illegal instruction", and the
         //  wildcard clause lives in postlude/insts_end.sail. This layer had no
         //  equivalent -- $veda_illegal_instr below was a list of named refusals
         //  and was the ONLY illegal-instruction source in the file. An
         //  unrecognised encoding fell through to $pc + 4 and retired.
         //
         //  MEASURED BEFORE FIXING, on both layers, in three classes:
         //    veda.bind mode 0b11 -- not merely undefined; veda_bind_insts.sail
         //      :276 maps VEDA_BIND_RESERVED to Illegal_Instruction() BY NAME.
         //    custom-0 f3=000 f7=0001010 -- 125 of 128 funct7 unallocated there.
         //    custom-2 f3=111 -- the whole funct3 unallocated.
         //  See difftest/probes/p5_reserved.S and p6_overbroad.S.
         //
         //  NOT AN ESCALATION, and the record should say so plainly: no
         //  fail-open encoding granted authority the executing code did not
         //  already hold. The reason to close it is that FAIL-OPEN IS WHAT HIDES
         //  BUGS, and this project has the receipt -- difftest/probes/p2_derive.S
         //  records a draft that used the wrong funct3 for CAndPerm, "which
         //  decodes as nothing -- and the probe still reported AGREE, because
         //  BOTH layers did the same no-op." After this, that same slip TRAPS on
         //  the instruction's own first test run.
         //
         //  TERMINALS ONLY, NEVER UMBRELLAS. $is_veda_bind, $is_veda_capquery
         //  and $is_veda_csetbounds_either are OR-groups; listing one of them
         //  here would re-open exactly the holes this closes, because an
         //  umbrella is true for encodings none of its members claim. That is
         //  how the four over-broad decoders above came to exist. The rule is
         //  checkable rather than remembered: every name below must be defined
         //  by a comparison against $opcode/$funct3/$funct7, not by an OR.
         //
         //  THE FAILURE DIRECTION INVERTS, which is the whole point. Add a new
         //  Veda instruction and forget to list it here, and it TRAPS -- its own
         //  directed test fails on the first simulation with mcause 0x02 and
         //  mtval holding the exact offending word. Before this change the same
         //  omission was invisible.
         // ═══════════════════════════════════════════════════════════════════
         $veda_op_claimed = $op_is_custom0 || $op_is_custom1 || $op_is_custom2 || $op_is_custom3;
         $veda_decoded =
            // custom-0
            $is_veda_odt_populate || $is_veda_odt_populate_fast || $is_veda_odt_page_in ||
            $is_veda_odt_destroy || $is_veda_odt_page_out || $is_veda_odt_set_domain ||
            $is_veda_odt_set_cow || $is_veda_nmc_add_w || $is_veda_ocl || $is_veda_ocs ||
            $is_veda_nmc_add_d || $is_veda_ocl_c || $is_veda_ocs_c ||
            // custom-0 Bind: the three real modes. Mode 0b11 is deliberately
            // absent -- it is VEDA_BIND_RESERVED and must trap.
            $is_veda_bind_plain || $is_veda_bind_notrap || $is_veda_rebind ||
            // custom-1
            $is_veda_atomic ||
            // custom-2
            $is_veda_cgetbase || $is_veda_cgetlen || $is_veda_cgetperm || $is_veda_cgettag ||
            $is_veda_cgettype || $is_veda_cgetaddr || $is_veda_cgetoffset || $is_veda_cgetobjectid ||
            $is_veda_csetbounds || $is_veda_csetboundsexact || $is_veda_oca || $is_veda_cseal ||
            $is_veda_cunseal || $is_veda_ocinvoke || $is_veda_ospecialrw || $is_veda_ocjalr ||
            $is_veda_csealentry || $is_veda_ocreturn || $is_veda_candperm ||
            // custom-3
            $is_veda_droppriv;
         $veda_undef_encoding = $veda_op_claimed && !$veda_decoded;

         // ═══════════════════════════════════════════════════════════════════
         //  R32 -- FAIL-CLOSED CSR ADDRESSES. A second, independent surface the
         //  encoding catch-all above cannot reach: a CSR access is opcode
         //  1110011, so $veda_op_claimed is false for it.
         //
         //  Sail is fail-closed here by the same construction -- a last wildcard
         //  `function clause is_CSR_accessible(_) = false` in
         //  postlude/csr_end.sail -- and veda_regs.sail declares 0x7C0..0x7C8
         //  only. This layer had NO address-validity term anywhere:
         //  $csr_rdata's default arm is 64'b0, so an undefined CSR READ ZERO,
         //  silently. Zero is worse than a no-op, because zero is a value
         //  software can act on: a handler probing for a feature by reading its
         //  CSR concludes the feature is present and disabled rather than
         //  absent. Measured in difftest/probes/p7_csr_space.S.
         //
         //  0x7C6/0x7C7/0x7C8 are READ-ONLY in the model -- their
         //  is_CSR_accessible clauses carry `access_type == CSRRead`, so a write
         //  is inaccessible and traps before any dispatch, which is why no
         //  write_CSR clause exists for them. This layer simply had no write
         //  path for them and ignored the attempt; now it refuses it.
         // ═══════════════════════════════════════════════════════════════════
         $csr_addr_known = $csr_is_mtvec || $csr_is_mscratch || $csr_is_mepc || $csr_is_mcause ||
                           $csr_is_mtval || $csr_is_veda_pcc_base || $csr_is_veda_pcc_length ||
                           $csr_is_veda_mepcc_base || $csr_is_veda_mepcc_length ||
                           $csr_is_veda_attr || $csr_is_veda_mode || $csr_is_veda_current_region ||
                           $csr_is_veda_saved_region || $csr_is_veda_trap_status;
         $csr_is_readonly = $csr_is_veda_current_region || $csr_is_veda_saved_region ||
                            $csr_is_veda_trap_status;
         $veda_csr_undef = $is_csr_access && (!$csr_addr_known || ($csr_write_en && $csr_is_readonly));

         $veda_illegal_instr = $veda_undef_encoding ||
                                $veda_csr_undef ||
                                $veda_csr_escape_violation ||
                                $veda_odt_page_out_refusal ||
                                $veda_odt_page_in_refusal ||
                                $veda_odt_populate_violation ||
                                $veda_odt_destroy_violation ||
                                $veda_odt_set_domain_violation ||
                                $veda_odt_set_cow_violation;
         $veda_trap_cause[4:0] =
            // RTL-4: 0x09 MUST precede the $veda_bind_trap arm, and that
            // ordering is mandatory rather than stylistic. A non-resident
            // region also produces !$veda_odt_valid, so for a plain Bind
            // $veda_bind_notfound_violation fires in the SAME cycle; putting
            // 0x09 second would report 0x05 "the object never existed" for a
            // domain that is merely paged out -- destroying exactly the
            // distinction veda_bind_insts.sail:78-85 introduced 0x09 to
            // make, and telling the handler to give up where it should page
            // the domain in and retry. Verified free before use: 0x09
            // appears nowhere among this file's existing cause literals.
            // RTL-17: before residency, matching Sail. Residency says "page
            // this in"; this says "you were never entitled". Telling a caller
            // with no right to the object to go run the pager is a hint about
            // an object that is none of its business.
            $veda_domain_violation    ? 5'h0B :
            $veda_region_fault        ? 5'h09 :
            // RTL-6: 0x0A sits immediately after 0x09 and immediately
            // before $veda_bind_trap, and both halves of that placement
            // are load-bearing.
            //
            // AFTER 0x09: region residency and object residency are
            // different questions and the region one wins. If a domain's
            // table is paged out you cannot have read the object's entry
            // at all, so any residency answer for the object is
            // meaningless -- the RTL would happily compute one anyway from
            // a byte it had no right to trust.
            //
            // BEFORE $veda_bind_trap: this arm is what makes 0x0A outrank
            // 0x06 (wrong owner), matching Sail, where the residency gate
            // precedes the mode match that produces 0x05/0x06. It does NOT
            // need to outrank 0x05, and must not -- $veda_residency_fault
            // carries $veda_odt_valid, so the two are mutually exclusive
            // by construction rather than by this ordering.
            //
            // Verified free before use, same discipline the 0x09 arm
            // records: every cause literal in this file was enumerated
            // (0x01,02,03,04,05,06,07,08,09,11,12,13,19,1f) and 0x0A
            // appears in none of them.
            $veda_residency_fault     ? 5'h0A :
            $veda_ocl_violation       ? $veda_ocl_cause :
            $veda_ocs_violation       ? $veda_ocs_cause :
            $veda_oclc_violation      ? $veda_oclc_cause :
            $veda_ocsc_violation      ? $veda_ocsc_cause :
            $veda_nmc_add_w_violation ? $veda_nmc_add_w_cause :
            $veda_nmc_add_d_violation ? $veda_nmc_add_d_cause :
            $veda_atomic_violation    ? $veda_atomic_cause :
            $veda_ocinvoke_violation  ? $veda_ocinvoke_cause :
            $veda_ocjalr_violation    ? $veda_ocjalr_cause :
            $veda_ocreturn_violation  ? $veda_ocreturn_cause :
            $veda_bind_trap           ? $veda_bind_cause :
                                        5'b0;
         // RTL-4: the region fault needs its own arm. The existing bind arm
         // is gated on $veda_bind_trap, which is plain-Bind-only, so a fault
         // from Bind-NoTrap or Rebind would fall through to the default
         // $veda_ocl_ocs_rs1_cap = $instr[18:15] -- on a Bind encoding that
         // is a slice of the GPR rs1 field, meaningless in mtval[8:5]. Sail
         // reports rd for all three bind traps (veda_bind_insts.sail:149).
         $veda_trap_cap_idx[3:0] = $veda_ocinvoke_violation ? $veda_ocinvoke_cap_idx :
                                    $veda_ocjalr_violation   ? $veda_ocjalr_cap_idx :
                                    $veda_domain_violation   ? $veda_rd_cap :
                                    $veda_region_fault       ? $veda_rd_cap :
                                    $veda_residency_fault    ? $veda_rd_cap :
                                    $veda_bind_trap          ? $veda_rd_cap :
                                                                $veda_ocl_ocs_rs1_cap;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 9: real Zicsr-lite CSR state. mtvec and mepc
         //  are both genuinely software-writable (mtvec: software
         //  installs its own trap handler address; mepc: a real trap
         //  handler must be able to advance PAST the faulting
         //  instruction before MRET, or MRET would jump straight back
         //  into the same instruction and re-trap forever -- confirmed
         //  a real, load-bearing need while designing this milestone's
         //  own trap-and-resume test, not a speculative feature added
         //  "to be complete"). mcause/mtval stay hardware-write-only
         //  (CSRRS can read them; CSRRW to them is decoded but its
         //  write silently has no effect, real RISC-V's own WARL
         //  convention for a field software isn't allowed to move) --
         //  no real trap-handler pattern in this project ever needs to
         //  fabricate a cause/value software didn't actually observe.
         // ─────────────────────────────────────────────────────────
         $csr_rdata[63:0] = $csr_is_mtvec  ? $mtvec :
                             $csr_is_mscratch ? $mscratch :
                             $csr_is_mepc   ? $mepc :
                             $csr_is_mcause ? $mcause :
                             $csr_is_mtval  ? $mtval :
                             $csr_is_veda_pcc_base     ? {8'b0, $veda_pcc_base} :
                             $csr_is_veda_pcc_length   ? {24'b0, $veda_pcc_length} :
                             $csr_is_veda_mepcc_base   ? {8'b0, $veda_mepcc_base} :
                             $csr_is_veda_mepcc_length ? {24'b0, $veda_mepcc_length} :
                             $csr_is_veda_attr         ? $veda_attr :
                             $csr_is_veda_mode         ? {32'b0, $veda_mode} :
                             // RTL-5 (R10): read-only. No write arm exists
                             // anywhere for these two -- a write is silently
                             // dropped rather than re-pointing a live
                             // compartment's namespace.
                             $csr_is_veda_current_region ? {44'b0, $veda_current_region} :
                             $csr_is_veda_saved_region   ? {44'b0, $veda_saved_region} :
                             $csr_is_veda_trap_status    ? {55'b0, $veda_trap_poison, $veda_trap_depth} :
                                              64'b0;
         // CSRRS with rs1=x0 must not write the CSR at all (real
         // RISC-V's own rule, VEDA_CORE... no -- the base Zicsr spec
         // itself: "If rs1=x0, then the instruction... shall not write
         // to the CSR"), matching this project's own real trap-handler
         // pattern (`csrr t3, mcause` expands to exactly this form and
         // must never attempt to write mcause).
         $csr_wdata[63:0] = $is_csrrw ? $rs1_data :
                             $is_csrrs ? ($csr_rdata | $rs1_data) :
                                         64'b0;
         $csr_write_en = $is_csr_access && !($is_csrrs && ($rs1 == 5'b0));
         // RTL MILESTONE 20 (Sail mirror, MILESTONE_20_RESULTS.md): the
         // real, empirically-confirmed compartment-state CSR
         // self-escape -- code entered via a real OCInvoke could simply
         // CSRRW its own compartment-state CSRs (veda_pcc_base/_length,
         // veda_mepcc_base/_length, veda_mode) to undo its own bounding,
         // zero trap. A write to any of these five while a compartment
         // is live (veda_pcc_length != UNBOUNDED) is now illegal --
         // matches the Sail side's own real-CHERI-grounded rule
         // ("Reading or writing any CSR requires the
         // Access_System_Registers permission on the PCC"). Read access
         // is deliberately NOT gated (capability metadata is always
         // inspectable, the same principle CGetTag/CGetType already
         // rely on -- code inside a compartment already knows its own
         // bounds, it got there via the capability that defined them).
         // RTL M27-mtvec-gate: $csr_is_mtvec added to this OR-list -- see
         // the real comment at $mtvec's own update logic below for the full
         // reasoning. Reuses 100% of the already-wired mcause=0x02/
         // mtval=raw-instr/veda_trap_taken machinery for free.
         $veda_csr_escape_violation = $csr_write_en &&
            ($csr_is_veda_pcc_base || $csr_is_veda_pcc_length ||
             $csr_is_veda_mepcc_base || $csr_is_veda_mepcc_length ||
             $csr_is_veda_mode || $csr_is_mtvec) &&
            (($veda_pcc_length != 40'hFFFFFFFFFF) ||
                                          // R26: authority is a NAME, not a bound. This one
                                          // comparator covers all six Sail authority sites
                                          // (0x7C0-0x7C3, 0x7C5 and mtvec), which this layer
                                          // fuses into a single OR-list. ADDED, never
                                          // substituted -- see the Sail header. A capability
                                          // naming NONE cannot cross either domain crossing,
                                          // because both check RT residency first and NONE's
                                          // region field is out of the modeled window, so the
                                          // name is unforgeable where the Length was not.
                                          ($veda_pcc_object != VEDA_OBJECT_NONE));
         `BOGUS_USE($csr_rdata)
         `BOGUS_USE($csr_wdata)

         // RTL M27-mtvec-gate (Sail-parity mirror, MILESTONE_27_MTVEC_CSR_
         // GATE_RESULTS.md): mtvec joins $veda_csr_escape_violation's own
         // CSR list below (the same "same class of gap" that doc's own
         // "Not yet built" section already named) -- a live compartment
         // silently CSRRW-ing its own trap handler out from under itself
         // (installing an attacker-controlled trap target) is now blocked
         // for the identical real reason the pcc_base/_length/mepcc_*/mode
         // family already is. Unlike those, mtvec has no trap-reset branch
         // of its own to piggyback on, so it needs its own explicit guard
         // here -- matching $veda_mode's own already-established pattern.
         $mtvec[63:0] = $reset ? 64'b0 :
                        (>>1$csr_write_en && >>1$csr_is_mtvec && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata :
                                                                  >>1$mtvec;
         // RTL Milestone 25 mirror: mscratch, byte-for-byte structural
         // copy of $mtvec's own pattern above -- no hardware-capture
         // logic needed, nothing but software CSRRW ever writes it,
         // exactly mtvec's own situation.
         $mscratch[63:0] = $reset ? 64'b0 :
                            (>>1$csr_write_en && >>1$csr_is_mscratch) ? >>1$csr_wdata :
                                                                         >>1$mscratch;
         $mepc[63:0] = $reset ? 64'b0 :
                       // A real trap-taken event always wins over a
                       // same-cycle software CSRRW to mepc -- the two
                       // can't actually co-occur in practice (a CSRRW
                       // to mepc is never itself a Veda-Core violation),
                       // but ordering it this way keeps the hardware
                       // capture the authoritative source on the one
                       // cycle that matters, matching mcause/mtval's
                       // own precedence below.
                       (>>1$veda_trap_taken) ? >>1$pc :
                       (>>1$csr_write_en && >>1$csr_is_mepc) ? >>1$csr_wdata :
                                                                >>1$mepc;
         $mcause[63:0] = $reset ? 64'b0 :
                         // E_Extension's own fixed top-level code
                         // (VEDA_CORE_SPEC.md Section 3, verified
                         // against core/types_ext.sail's real
                         // ext_exc_type_bits mapping, not assumed) --
                         // every Veda-Core hard trap shares this one
                         // mcause value regardless of which family or
                         // cause sub-code fired; the real detail lives
                         // in mtval below, matching Sail's own
                         // make_sync_exception(E_Extension(()), xtval)
                         // shape exactly.
                         // RTL Milestone 20: a compartment-state CSR
                         // self-escape attempt is a real, standard
                         // RISC-V Illegal_Instruction (mcause=0x02), NOT
                         // Veda-Core's own E_Extension (0x18) every
                         // other family here shares -- matches the Sail
                         // side's own real, idiomatic write_CSR
                         // Err(())=>Illegal_Instruction() mechanism
                         // exactly (a stronger, more consistent response
                         // than a silent no-op, per that milestone's own
                         // reasoning).
                         // RTL Milestone 23: ecall gets the real,
                         // standard RISC-V privileged-spec mcause for
                         // "Environment call from M-mode" (0x0B=11) --
                         // not an invented Veda-specific code, and the
                         // only possible value since this core only
                         // ever runs M-mode.
                         (>>1$veda_trap_taken) ? (>>1$veda_illegal_instr ? 64'h02 :
                                                   >>1$is_ecall ? 64'h0B : 64'h18) :
                                                  >>1$mcause;
         $mtval[63:0] = $reset ? 64'b0 :
                        // veda_xtval(cap_idx, cause) = zero_extend(cap_idx5
                        // @ cause) -- cap_idx5 is cap_idx zero-extended
                        // from 4 to 5 bits, verified directly from
                        // veda_bind_insts.sail's own source, the same
                        // encoding already cross-checked once this
                        // session for the Sail-side atomic8 test.
                        // RTL Milestone 14: the PCC-violation case is
                        // special-cased here directly (cap_idx=5'b10000,
                        // cause=5'b00001) rather than going through
                        // $veda_trap_cap_idx[3:0]/$veda_trap_cause[4:0]
                        // (see $veda_trap_taken's own comment above).
                        // RTL Milestone 19: the purecap-violation case is
                        // special-cased identically (cap_idx=5'b10001=17,
                        // cause=5'b00111=0x07) -- checked ahead of the PCC
                        // case in this ternary chain, but the two can
                        // never actually co-occur on the same cycle
                        // ($veda_pcc_violation only ever fires from the
                        // fetch-time check, which forces $instr to a NOP
                        // before decode, so $is_load/$is_store -- and
                        // therefore $veda_purecap_violation -- can never
                        // also be true that same cycle), so the ordering
                        // here is a don't-care, not a real priority
                        // decision.
                        // RTL Milestone 20: mtval for the mcause=0x02
                        // case above holds the real, standard RISC-V
                        // convention for an illegal-instruction trap --
                        // the raw faulting instruction bits (the
                        // offending CSRRW/CSRRS itself) -- rather than a
                        // cap_idx/cause pair, since this is not a
                        // Veda-specific violation family at all.
                        // RTL Milestone 23: mtval=0 for ecall, the real
                        // RISC-V spec convention (no fault-address info
                        // applies) -- the pre-existing default fallback
                        // below is built from $veda_trap_cap_idx/_cause,
                        // which ecall never populates, so it needs its
                        // own explicit branch rather than falling through.
                        (>>1$veda_trap_taken) ? (>>1$veda_illegal_instr ? {32'b0, >>1$instr}
                                                  : >>1$veda_purecap_violation ? {54'b0, 5'b10001, 5'b00111}
                                                  : >>1$veda_pcc_violation ? {54'b0, 5'b10000, 5'b00001}
                                                  : >>1$is_ecall ? 64'b0
                                                                         : {55'b0, >>1$veda_trap_cap_idx, >>1$veda_trap_cause}) :
                                                 >>1$mtval;

         // ─────────────────────────────────────────────────────────
         //  RTL MILESTONE 14: veda_pcc_base/veda_pcc_length (the live
         //  compartment) and veda_mepcc_base/veda_pcc_length (the saved
         //  copy across a trap) -- the same real persistent-signal idiom
         //  $mtvec/$mepc already established (Milestone 9), applied to a
         //  new, genuinely different kind of state (a fetch-time bound,
         //  not an ordinary CSR value alone). Reset to
         //  VEDA_PCC_UNBOUNDED (40'hFFFFFFFFFF as of RTL-3) -- a real correctness
         //  requirement, not styling: left at 0 by default, every fetch
         //  would bounds-check against an empty window at address 0 and
         //  hard-trap on the very first cycle (the identical real reason
         //  already named on the Sail side, postlude/step_ext.sail).
         //  Priority order, matching veda_trap()'s own real behavior on
         //  the Sail side field-for-field: (1) a real trap always wins --
         //  save the live bounds into mepcc, reset pcc to unbounded so
         //  the trap handler itself runs in a trusted, unconstrained
         //  context (real CHERI's own "Exception Code Capability"
         //  requirement); (2) a successful OCInvoke narrows pcc to the
         //  invoked code capability's own Base/Length; (3) an explicit
         //  CSRRW/CSRRS to one of the four new addresses -- this
         //  project's own established "software, not hardware, restores
         //  across mret" convention (mepc's own explicit
         //  advance-before-mret since Milestone 9, carried forward here
         //  rather than inventing an automatic mechanism); (4) retain.
         // ─────────────────────────────────────────────────────────
         // Minimal OS kernel Milestone B: a successful VEDA_OCRETURN
         // joins OCInvoke at the same priority tier -- both narrow PCC
         // to cs1's own Base/Length on their own real success path, the
         // actual compartment-boundary-crossing side effect. Structurally
         // identical branches (both read $veda_rs1cap_base/_length, the
         // shared rs1-capability signal every Custom-2 instruction here
         // already reads), just gated by a different instruction/
         // violation pair.
         // RTL M21-restore (Sail-parity mirror, MILESTONE_21_PCC_AUTO_RESTORE_
         // RESULTS.md): automatic PCC restore-on-mret, ported from the Sail
         // side's own veda_pcc_restore_on_xret(). Priority ordering matches
         // that design field-for-field: (1) a real trap always wins (already
         // the top-priority branch, unchanged); (2) a real mret consuming a
         // genuinely-saved mepcc (length != UNBOUNDED, i.e. a real
         // compartment WAS captured there, not just "some trap happened
         // while already unbounded") restores; (3) OCInvoke/OCReturn
         // (unchanged); (4) explicit CSRRW/CSRRS (unchanged, still honored
         // -- software retains full override, this is a default not a
         // forced behavior, matching the Sail side's own explicit-override
         // test property); (5) retain.
         // ─────────────────────────────────────────────────────────
         //  R27 -- the PRIVILEGE half, on the four CSRs that were missing it.
         //  Milestone 20 gated five compartment-state CSRs together so a
         //  compartment could not rewrite its own execution bounds or forge its
         //  own trap return -- but only 0x7C5 ever got the privilege term. The
         //  four that rewrite PCC and MEPCC directly had the PCC-bounds half
         //  alone, which puts the WEAKER gate on the STRONGER authority.
         //
         //  This is also what turns R26 from a partial escape into a complete
         //  one: once the "am I in a compartment" predicate is forged by
         //  entering on a sentinel-Length object, THESE are the CSRs that let
         //  the compartment widen its own PCC and fetch anywhere. This arm does
         //  not close R26 -- only explicit compartment state does -- but it
         //  means forging the predicate is no longer sufficient by itself.
         //
         //  Gating the write-enable rather than trapping, matching Sail: a
         //  non-Machine write is a silent no-op, register holds, read-back
         //  returns the unchanged value.
         // ─────────────────────────────────────────────────────────
         // ─────────────────────────────────────────────────────────
         //  R28 -- THE ESCAPE VIOLATION TRAPPED BUT DID NOT SUPPRESS THE WRITE.
         //  $veda_csr_escape_violation already listed all six CSRs, and it
         //  correctly raised a trap. But only ONE of the five write-enables --
         //  $veda_mode -- ever consulted it. For 0x7C0-0x7C3 the trap fired AND
         //  the register changed: a compartment could rewrite its own PCC bounds
         //  or forge its trap return, take the trap, and keep the write.
         //  Sail is fail-closed here by construction: write_CSR returns Err(())
         //  before any assignment, so nothing is written. RTL-only divergence,
         //  and the same fail-open shape as R21 -- the refusal was raised and
         //  the effect happened anyway.
         //  Found by the R26 authority test: from inside a sentinel-Length
         //  compartment the mtvec write was refused while the 0x7C3 write landed,
         //  which is only possible if the two are gated differently.
         //  "Applied to four of five arms" for the fourth time in this project,
         //  and the first time in code nobody had just edited.
         // ─────────────────────────────────────────────────────────
         $veda_pcc_base[55:0] = $reset ? 56'b0 :
                                 (>>1$veda_trap_taken) ? 56'b0 :
                                 // RTL-8 (R12): occupancy is out of band now. depth==1 means this is
                                 // the OUTERMOST unwind, the one that owns the saved frame.
                                 (>>1$is_mret && (>>1$veda_trap_depth == 8'd1) && !(>>1$veda_trap_poison)) ? >>1$veda_mepcc_base :
                                 // Poisoned outermost unwind: DENY. A zero-length PCC faults on the
                                 // very next fetch -- loud, and incapable of granting anything.
                                 (>>1$is_mret && (>>1$veda_trap_depth == 8'd1) && (>>1$veda_trap_poison)) ? 56'b0 :
                                 // An INNER level's context was the reset context by construction, so
                                 // it is reconstructed rather than stored -- which is what makes one
                                 // slot plus a counter lossless here instead of an approximation.
                                 (>>1$is_mret && (>>1$veda_trap_depth > 8'd1)) ? (>>1$veda_trap_poison ? 56'b0 : 56'b0) :
                                 (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_rs1cap_base :
                                 (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_rs1cap_base :
                                 (>>1$csr_write_en && >>1$csr_is_veda_pcc_base && >>1$priv && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[55:0] :
                                                                                   >>1$veda_pcc_base;
         // ─────────────────────────────────────────────────────────
         //  RTL-4: the Current-Region Base Register (CRBR), DESIGN_08
         //  Section 4. Mirrors Sail's veda_current_region /
         //  veda_current_odt_base (veda_regs.sail:481-482). It is NOT a
         //  cache and NOT a TLB: one base, no tags, no fill-on-miss, no
         //  eviction, no access history.
         //
         //  RTL-5 (R10, DESIGN_07 Tier G): the CRBR is now genuinely LOADED
         //  at the two domain crossings. RTL-4 shipped it reset-only as a
         //  deliberate refusal -- loading it at entry without a matching
         //  restore is itself a compartment escape, because OCReturn carries
         //  no saved caller region and the current region is fault-EXEMPT by
         //  construction, so a caller would resume holding the CALLEE's
         //  domain and inherit unchecked, RT-free reach into its whole object
         //  namespace. The Sail fix landed first (fork commit 2fd7070c,
         //  76/76, 6/6 mutants killed); this mirrors it.
         //
         //  One rule, two clauses:
         //    The CRBR is loaded ONLY from Object_ID[43:24] of the code
         //    capability being entered or returned to, and EVERY load is
         //    validated through the Region Table -- never through the
         //    current-region fast-path exemption.
         //  The first clause makes the source unforgeable (only a
         //  residency-gated Bind mints an Object_ID; a GPR cannot name a
         //  domain). The second makes the exemption sound BY CONSTRUCTION:
         //  the CRBR can only ever come to name a region the RT said was
         //  resident. Validation lives in $veda_crossing_rt_resident, which
         //  is folded into each crossing's violation term, so a faulting
         //  crossing commits NOTHING -- these arms cannot fire.
         //
         //  Arm order mirrors $veda_pcc_base exactly: reset, trap, mret
         //  -restore, OCInvoke, OCReturn, retain.
         //
         //  Units: ENTRY index, matching rt_odt_base and Sail's
         //  veda_odt_base_of, NOT bytes. Note the deliberate width
         //  divergence from Sail: Sail's veda_current_odt_base is bits(56)
         //  because it is a modelled table offset; the RTL holds the same
         //  quantity in 32 bits to match rt_odt_base[31:0]. Widening it to
         //  56 "to match Sail", or storing a byte address here, would shift
         //  every non-zero-region base by 32x -- invisible on region 0,
         //  whose base is 0, which is precisely the silent-truncation class
         //  that cost RTL-3 four bugs.
         $veda_current_region[19:0] = $reset ? 20'b0 :
                                       (>>1$veda_trap_taken) ? 20'b0 :
                                       (>>1$is_mret && (>>1$veda_saved_region != 20'hFFFFF)) ? >>1$veda_saved_region :
                                       (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_check_region :
                                       (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_check_region :
                                                                                                   >>1$veda_current_region;
         //  The base half comes from the REGION TABLE, never from the
         //  capability: the capability supplies only the NAME of the domain,
         //  the always-resident RT supplies its table location. Mirrors
         //  Sail's veda_crbr_load reading veda_region_table[ru].
         $veda_current_odt_base[31:0] = $reset ? 32'b0 :
                                         (>>1$veda_trap_taken) ? rt_odt_base[0] :
                                         (>>1$is_mret && (>>1$veda_saved_region != 20'hFFFFF)) ? >>1$veda_saved_region_base :
                                         (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? rt_odt_base[>>1$veda_check_region[2:0]] :
                                         (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? rt_odt_base[>>1$veda_check_region[2:0]] :
                                                                                                     >>1$veda_current_odt_base;
         //  RTL-5 (R10): the saved-CRBR shadow, the structural twin of
         //  veda_mepcc_base/_length. Capture is CONDITIONAL on a non-root
         //  domain being live (region 0 needs no save -- the reset target IS
         //  region 0, so restoring it would be the identity), which is also
         //  what protects the saved value from a nested trap: the handler
         //  runs in region 0, so a second trap captures nothing and cannot
         //  clobber the first trap's save. Restore is SELF-CONSUMING: the
         //  mret arm writes the empty sentinel back, so a saved domain is
         //  never applied to more than one mret.
         //
         //  THE SENTINEL IS 20'hFFFFF, NOT 20'b0, and that is load-bearing:
         //  region 0 is a LEGITIMATE domain (the root every existing test
         //  runs in), so zero cannot double as "nothing saved" the way
         //  VEDA_PCC_UNBOUNDED does for mepcc. 0xFFFFF is out-of-window
         //  (>= RT_ENTRIES), so it can never be a real current region --
         //  every load is RT-validated and out-of-window regions are never
         //  resident. Resetting this to 20'b0 instead would make "nothing
         //  saved" indistinguishable from "region 0 saved", the restore
         //  would fire on every mret, and on this all-region-0 corpus it
         //  would look perfectly correct forever.
         $veda_saved_region[19:0] = $reset ? 20'hFFFFF :
                                     (>>1$veda_trap_taken && (>>1$veda_current_region != 20'b0)) ? >>1$veda_current_region :
                                     (>>1$is_mret && (>>1$veda_saved_region != 20'hFFFFF)) ? 20'hFFFFF :
                                                                                              >>1$veda_saved_region;
         $veda_saved_region_base[31:0] = $reset ? 32'b0 :
                                          (>>1$veda_trap_taken && (>>1$veda_current_region != 20'b0)) ? >>1$veda_current_odt_base :
                                          (>>1$is_mret && (>>1$veda_saved_region != 20'hFFFFF)) ? 32'b0 :
                                                                                                   >>1$veda_saved_region_base;
         $veda_pcc_length[39:0] = $reset ? 40'hFFFFFFFFFF :
                                   (>>1$veda_trap_taken) ? 40'hFFFFFFFFFF :
                                   // RTL-8 (R12): occupancy is out of band now. depth==1 means this is
                                   // the OUTERMOST unwind, the one that owns the saved frame.
                                   (>>1$is_mret && (>>1$veda_trap_depth == 8'd1) && !(>>1$veda_trap_poison)) ? >>1$veda_mepcc_length :
                                   // Poisoned outermost unwind: DENY. A zero-length PCC faults on the
                                   // very next fetch -- loud, and incapable of granting anything.
                                   (>>1$is_mret && (>>1$veda_trap_depth == 8'd1) && (>>1$veda_trap_poison)) ? 40'b0 :
                                   // An INNER level's context was the reset context by construction, so
                                   // it is reconstructed rather than stored -- which is what makes one
                                   // slot plus a counter lossless here instead of an approximation.
                                   (>>1$is_mret && (>>1$veda_trap_depth > 8'd1)) ? (>>1$veda_trap_poison ? 40'b0 : 40'hFFFFFFFFFF) :
                                   (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_rs1cap_length :
                                   (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_rs1cap_length :
                                   (>>1$csr_write_en && >>1$csr_is_veda_pcc_length && >>1$priv && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[39:0] :
                                                                                       >>1$veda_pcc_length;
         // Real bug found (not copied blindly from Sail) while designing
         // this mirror: the pre-existing trap-time capture below was
         // UNCONDITIONAL (captured on every trap, even one that fired while
         // PCC was already unbounded). Harmless while nothing auto-consumed
         // mepcc -- but once mret starts consuming it automatically (above),
         // a second, nested trap between a first trap's save and its own
         // later mret would silently overwrite the first trap's real saved
         // bounds with {don't-care, UNBOUNDED}. Fixed by gating the capture
         // itself on `>>1$veda_pcc_length != 40'hFFFFFFFFFF` (a compartment was
         // genuinely live at the moment of the trap) -- exactly the Sail
         // side's own already-adversarially-reviewed conditional-capture
         // design (veda_pcc_save_and_reset()'s own guard). Self-consuming:
         // a successful mret-restore immediately resets mepcc back to
         // {0, UNBOUNDED} so a stale value can never be restored twice --
         // the identical self-consuming property the Sail side's own design
         // already proved necessary for the same nested-trap hazard class.
         // ═════════════════════════════════════════════════════════
         //  RTL-8 (R12, DESIGN_07 Tier H): OUT-OF-BAND TRAP NESTING.
         //
         //  This file held the OPPOSITE half of R12 from the Sail model, and the
         //  divergence was caused by a COMMENT. veda_regs.sail stated that
         //  veda_pcc_save_and_reset's capture "is itself conditional". It was not
         //  -- that function had no guard at all. This file then guarded ITS
         //  capture, citing that comment as justification. So the RTL implemented
         //  what the comment SAID while Sail did what its code DID: Sail clobbered
         //  the outer save and resumed UNBOUNDED, while this file kept the save
         //  but let the INNER mret consume it, narrowing the handler mid-flight.
         //
         //  Recorded because every cross-layer mirror here is written by reading
         //  the other layer's comments. Code says WHAT, comments say WHY -- so a
         //  comment that misdescribes its own function becomes a specification bug
         //  that propagates. Verify against the other layer's CODE.
         //
         //  Root cause on both sides was the in-band sentinel: 40'hFFFFFFFFFF was
         //  made to mean both "this compartment has no bounds" and "nothing was
         //  saved". An object may legitimately have that Length, so the collision
         //  is reachable, not theoretical.
         //
         //  Depth decrements on mret AND on a successful OCRETURN. That second
         //  exit has no RISC-V counterpart: the trusted switcher leaves a handler
         //  by OCRETURN and cannot do otherwise, since narrowing PCC with csrw and
         //  then falling through to a separate mret requires fetching that mret,
         //  by then outside the narrowed bounds. OCRETURN installs PCC from its
         //  own operand, so a saved frame is superseded -- abandoned, not restored.
         $veda_trap_depth[7:0] = $reset ? 8'b0 :
                                  (>>1$veda_trap_taken && (>>1$veda_trap_depth != 8'hFF)) ? (>>1$veda_trap_depth + 8'b1) :
                                  ((>>1$is_mret || (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation))) && (>>1$veda_trap_depth != 8'b0)) ? (>>1$veda_trap_depth - 8'b1) :
                                                                                            >>1$veda_trap_depth;
         //  Poison marks a chain that cannot be reconstructed: a handler that
         //  narrowed ITSELF -- via OCInvoke, or the PCC CSRs, writable precisely
         //  while unbounded -- and then faulted. Reconstructing the reset context
         //  there would hand unbounded authority to a level that was narrowed,
         //  which is R12 again one level up. Saturation poisons too: at the ceiling
         //  the chain stops being countable, so it stops being reconstructible.
         $veda_trap_poison = $reset ? 1'b0 :
                              (>>1$veda_trap_taken && (>>1$veda_trap_depth != 8'b0) &&
                               ((>>1$veda_pcc_length != 40'hFFFFFFFFFF) || (>>1$veda_current_region != 20'b0) || (>>1$veda_pcc_object != VEDA_OBJECT_NONE))) ? 1'b1 :
                              (>>1$veda_trap_taken && (>>1$veda_trap_depth == 8'hFF)) ? 1'b1 :
                              ((>>1$is_mret || (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation))) && (>>1$veda_trap_depth == 8'd1)) ? 1'b0 :
                                                                                        >>1$veda_trap_poison;
         $veda_mepcc_base[55:0] = $reset ? 56'b0 :
                                   (>>1$veda_trap_taken && (>>1$veda_trap_depth == 8'b0)) ? >>1$veda_pcc_base :
                                   ((>>1$is_mret || (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation))) && (>>1$veda_trap_depth == 8'd1)) ? 56'b0 :
                                   (>>1$csr_write_en && >>1$csr_is_veda_mepcc_base && >>1$priv && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[55:0] :
                                                                                       >>1$veda_mepcc_base;
         $veda_mepcc_length[39:0] = $reset ? 40'hFFFFFFFFFF :
                                     (>>1$veda_trap_taken && (>>1$veda_trap_depth == 8'b0)) ? >>1$veda_pcc_length :
                                     ((>>1$is_mret || (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation))) && (>>1$veda_trap_depth == 8'd1)) ? 40'hFFFFFFFFFF :
                                     (>>1$csr_write_en && >>1$csr_is_veda_mepcc_length && >>1$priv && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[39:0] :
                                                                                           >>1$veda_mepcc_length;
         // RTL-9 (R11(b)): the name PCC is running under. Mirrors Sail's
         // veda_pcc_object exactly, arm for arm, including which arms are
         // ABSENT -- a poisoned unwind and an inner-level unwind both leave
         // it alone, because trap entry already cleared it to NONE and an
         // inner handler genuinely belongs to no object. Adding arms that
         // force NONE there would compute the same value by a second route
         // and invite the two routes to drift apart later.
         $veda_pcc_object[43:0] = $reset ? VEDA_OBJECT_NONE :
                                   // the handler runs unbounded at mtvec and is not
                                   // executing any object, so it must not carry the
                                   // callee's name. Nothing is lost: while the return
                                   // is owed the SAVED name pins the same object.
                                   (>>1$veda_trap_taken) ? VEDA_OBJECT_NONE :
                                   (>>1$is_mret && (>>1$veda_trap_depth == 8'd1) && !(>>1$veda_trap_poison)) ? >>1$veda_mepcc_object :
                                   (>>1$is_veda_ocinvoke && !(>>1$veda_ocinvoke_violation)) ? >>1$veda_rs1cap_object_id :
                                   (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation)) ? >>1$veda_rs1cap_object_id :
                                                                                              >>1$veda_pcc_object;
         // The saved name travels with the saved bounds, captured and
         // released on exactly the same conditions as $veda_mepcc_base --
         // deliberately keyed on the SAME depth terms, because a save slot
         // whose three fields answered to different conditions is precisely
         // the defect R12 existed to remove.
         $veda_mepcc_object[43:0] = $reset ? VEDA_OBJECT_NONE :
                                     (>>1$veda_trap_taken && (>>1$veda_trap_depth == 8'b0)) ? >>1$veda_pcc_object :
                                     ((>>1$is_mret || (>>1$is_veda_ocreturn && !(>>1$veda_ocreturn_violation))) && (>>1$veda_trap_depth == 8'd1)) ? VEDA_OBJECT_NONE :
                                                                                               >>1$veda_mepcc_object;
         // RTL Milestone 18: plain read/write CSR, no other write source
         // (unlike veda_pcc_base/length, which also get written by a
         // successful OCInvoke/trap) -- mirrors $mtvec's own simple
         // reset/CSRRW-only pattern exactly. Reset to 0 is harmless: an
         // all-zero Length/Perms just makes the first Populate-Fast
         // object real but permission-less until software actually sets
         // this CSR, matching the Sail side's own identical reasoning.
         $veda_attr[63:0] = $reset ? 64'b0 :
                              (>>1$csr_write_en && >>1$csr_is_veda_attr) ? >>1$csr_wdata[63:0] :
                                                                            >>1$veda_attr;
         // RTL Milestone 19: veda_mode, bit 0 = veda_purecap. Identical
         // simple reset/CSRRW-only pattern as veda_attr directly above --
         // reset to 0 is the real correctness requirement here (not just
         // styling): purecap defaults OFF, so the entire pre-existing
         // 27-test RTL corpus and the 51/51 ACT4 conformance suite, none
         // of which anticipate this feature, see zero behavior change
         // until software explicitly opts in.
         // RTL Milestone 20: !(>>1$veda_csr_escape_violation) added --
         // unlike veda_pcc_base/_length/_mepcc_*, nothing else ever
         // writes veda_mode, so there is no pre-existing higher-priority
         // trap-reset branch to fall back on here; this guard is the
         // only thing preventing an attacker's csr_wdata from landing
         // while a compartment is live.
         $veda_mode[31:0] = $reset ? 32'b0 :
                              // R26 Lever B: the PRIVILEGE half of this gate was missing.
                              // Sail's write_CSR(0x7C5) is `if pcc_length != UNBOUNDED then Err
                              // else if cur_privilege == Machine then veda_mode = ...`, so a
                              // non-Machine write is a silent no-op that leaves the register
                              // unchanged. This layer checked only the PCC-bounds half, so a
                              // post-droppriv, unbounded-PCC principal could clear purecap here
                              // while being refused at Populate (:2281, which does carry $priv).
                              // Gating the write-enable rather than raising a violation is the
                              // exact parity choice -- Sail neither traps nor writes.
                              (>>1$csr_write_en && >>1$csr_is_veda_mode && >>1$priv && !(>>1$veda_csr_escape_violation)) ? >>1$csr_wdata[31:0] :
                                                                            >>1$veda_mode;

         // OCA is deliberately absent here -- its destination (rd) is a
         // Capability Register, not a GPR (VEDA_CORE_SPEC.md Section 1:
         // funct3's dest-kind bit selects Capability Register for OCA),
         // handled entirely by /vreg's own write logic below.
         // CSetBounds/CSetBoundsExact are deliberately absent here too,
         // for the identical reason as OCA -- their destination is a
         // Capability Register (funct3 = 001, Section 1), not a GPR.
         // CSeal/CUnseal (Milestone 6) are absent for the same reason
         // again -- funct3 = 001, destination is a Capability Register.
         // OCL.C (Milestone 7) is absent for the same reason once more --
         // funct3 = 100, destination is a Capability Register (rd reused
         // as $veda_rd_cap, Section 1's own "OCL.C/OCS.C semantics"). OCS.C
         // needs no entry here at all -- its own destination is memory
         // (elfmem[]/tag_mem[], via the trailing \SV block below), not
         // any register, GPR or Capability, matching OCS.D's own absence
         // from this list. OCInvoke (Milestone 10) needs no entry either
         // -- its own destination (c15/IDC) is fixed, not GPR-written,
         // and its real destination effect is the PC redirect, not any
         // register write at all. OSpecialRW (Milestone 11) is absent
         // for the identical reason as OCA/CSetBounds/CSeal/CUnseal --
         // its `cd` is a Capability Register, not a GPR.
         // RTL Milestone 19: $is_load's own term gains
         // !$veda_purecap_violation -- an ordinary load blocked by
         // purecap enforcement must not write $rd with load data (the
         // memory access itself is also suppressed below, at /dmem's
         // read is unaffected since RAM reads have no side effect to
         // block, but the *write-back* of that data into a GPR is the
         // real thing that must never happen on a violation, matching
         // every other family's own $reg_write gating in this list).
         $reg_write = ($is_load && !$veda_purecap_violation) || $is_alu_imm || $is_alu_reg || $is_lui || $is_auipc ||
                      $is_jal || $is_jalr || $is_alu_immw || $is_alu_regw ||
                      ($is_veda_ocl && !$veda_violation) ||
                      ($is_veda_nmc_add_w && !$veda_nmc_add_w_violation) ||
                      ($is_veda_nmc_add_d && !$veda_nmc_add_d_violation) ||
                      ($is_veda_atomic && !$veda_atomic_violation) ||
                      $is_veda_capquery ||
                      ($is_veda_odt_populate && !$veda_odt_populate_violation) ||
                      ($is_veda_odt_populate_fast && !$veda_odt_populate_violation) ||
                      ($is_veda_odt_destroy  && !$veda_odt_destroy_violation) ||
                      // RTL-6c: rd is written only on the SUCCESS path, so
                      // a refused page operation leaves rd untouched as
                      // well as leaving the ODT untouched -- the refusal is
                      // reported through the trap, not through rd.
                      ($is_veda_odt_page_out && !$veda_odt_page_out_refusal) ||
                      ($is_veda_odt_page_in  && !$veda_odt_page_in_refusal) ||
                      // RTL Milestone 9: CSRRW/CSRRS always write rd
                      // with the CSR's OLD value, independent of
                      // $veda_trap_taken -- a CSR read/write is never
                      // itself a Veda-Core violation, and real Zicsr
                      // semantics give rd the pre-write value
                      // unconditionally (matching every prior /xreg
                      // write-gating convention in this file: gate on
                      // "is this instruction real", not on an
                      // unrelated signal).
                      $is_csr_access;

         // ─────────────────────────────────────────────────────────
         //  REGISTER FILE (32 x 64-bit), x0 hardwired to 0
         // ─────────────────────────────────────────────────────────
         /xreg[31:0]
            $wr_en = |cpu>>1$reg_write &&
                     (|cpu>>1$rd == #xreg) &&
                     (#xreg != 5'b0);
            $val[63:0] = (|cpu$reset || |cpu>>1$reset) ? 64'b0 :
                         $wr_en ? |cpu>>1$wr_data :
                                  $RETAIN;
         $rs1_data[63:0] = ($rs1 == 5'd0) ? 64'b0 : /xreg[$rs1]$val;
         $rs2_data[63:0] = ($rs2 == 5'd0) ? 64'b0 : /xreg[$rs2]$val;

         // ─────────────────────────────────────────────────────────
         //  IMMEDIATE GENERATION — bit layouts verified against the
         //  RISC-V ISA manual's own immediate-encoding figures.
         // ─────────────────────────────────────────────────────────
         $imm_i[63:0] = {{52{$instr[31]}}, $instr[31:20]};
         $imm_s[63:0] = {{52{$instr[31]}}, $instr[31:25], $instr[11:7]};
         $imm_b[63:0] = {{51{$instr[31]}}, $instr[31], $instr[7], $instr[30:25], $instr[11:8], 1'b0};
         $imm_u[63:0] = {{32{$instr[31]}}, $instr[31:12], 12'b0};
         $imm_j[63:0] = {{43{$instr[31]}}, $instr[31], $instr[19:12], $instr[20], $instr[30:21], 1'b0};

         // ─────────────────────────────────────────────────────────
         //  ALU — full 64-bit op table plus the 32-bit *W path
         //  (compute on the low 32 bits, then sign-extend to 64).
         // ─────────────────────────────────────────────────────────
         $alu_op2[63:0]     = ($is_alu_reg || $is_alu_regw) ? $rs2_data : $imm_i;
         $shift_amt64[5:0]  = ($is_sll || $is_srl || $is_sra) ? $rs2_data[5:0] : $shamt6;
         $shift_amt32[4:0]  = ($is_sllw || $is_srlw || $is_sraw) ? $rs2_data[4:0] : $shamt5;
         // Signed less-than without a `signed` cast (the `$` sigil in
         // "$signed(...)" collides with TL-Verilog's own signal-name
         // syntax and is misparsed as a signal reference): if the sign
         // bits differ, the operand whose sign bit is set is the smaller
         // one; otherwise a plain unsigned compare already gives the
         // correct signed result.
         $lt_signed         = ($rs1_data[63] != $alu_op2[63]) ? $rs1_data[63] : ($rs1_data < $alu_op2);
         $lt_unsigned       = ($rs1_data < $alu_op2);
         // Arithmetic right shift built from sign-bit replication +
         // logical shift, for the same reason (no `$signed()` cast):
         // concatenate the sign bit ahead of the value, logical-shift
         // the widened value, then take the low bits.
         $sra_ext128[127:0]  = {{64{$rs1_data[63]}}, $rs1_data};
         $alu_sra64[63:0]    = ($sra_ext128 >> $shift_amt64);
         $sraw_ext64[63:0]   = {{32{$rs1_data[31]}}, $rs1_data[31:0]};
         $alu_sraw32_wide[63:0] = ($sraw_ext64 >> $shift_amt32);

         $alu_result64[63:0] =
            ($is_add || $is_addi)   ? ($rs1_data + $alu_op2) :
            $is_sub                  ? ($rs1_data - $rs2_data) :
            ($is_sll || $is_slli)    ? ($rs1_data << $shift_amt64) :
            ($is_slt || $is_slti)    ? {63'b0, $lt_signed} :
            ($is_sltu || $is_sltiu)  ? {63'b0, $lt_unsigned} :
            ($is_xor || $is_xori)    ? ($rs1_data ^ $alu_op2) :
            ($is_srl || $is_srli)    ? ($rs1_data >> $shift_amt64) :
            ($is_sra || $is_srai)    ? $alu_sra64 :
            ($is_or || $is_ori)      ? ($rs1_data | $alu_op2) :
            ($is_and || $is_andi)    ? ($rs1_data & $alu_op2) :
                                        64'b0;

         $alu_result32_raw[31:0] =
            ($is_addw || $is_addiw)              ? ($rs1_data[31:0] + $alu_op2[31:0]) :
            $is_subw                               ? ($rs1_data[31:0] - $rs2_data[31:0]) :
            ($is_sllw || $is_slliw)                ? ($rs1_data[31:0] << $shift_amt32) :
            ($is_srlw || $is_srliw)                ? ($rs1_data[31:0] >> $shift_amt32) :
            ($is_sraw || $is_sraiw)                ? $alu_sraw32_wide[31:0] :
                                                       32'b0;
         $alu_result32[63:0] = {{32{$alu_result32_raw[31]}}, $alu_result32_raw};

         $alu_result[63:0] = $is_w_op ? $alu_result32 : $alu_result64;

         // ─────────────────────────────────────────────────────────
         //  BRANCH / JUMP TARGET
         // ─────────────────────────────────────────────────────────
         // Same sign-bit-based technique as $lt_signed above (no
         // $signed() cast, for the same TL-Verilog $-sigil reason).
         $blt_signed = ($rs1_data[63] != $rs2_data[63]) ? $rs1_data[63] : ($rs1_data < $rs2_data);
         $branch_taken =
            ($is_beq  && ($rs1_data == $rs2_data)) ||
            ($is_bne  && ($rs1_data != $rs2_data)) ||
            ($is_blt  && $blt_signed) ||
            ($is_bge  && !$blt_signed) ||
            ($is_bltu && ($rs1_data < $rs2_data)) ||
            ($is_bgeu && ($rs1_data >= $rs2_data));
         $branch_target[63:0] = $pc + $imm_b;
         $jal_target[63:0]    = $pc + $imm_j;
         $jalr_target[63:0]   = ($rs1_data + $imm_i) & ~64'b1;
         // RTL Milestone 9: a real hard trap now genuinely redirects
         // control flow (PC = mtvec), the same real property Sail has
         // enforced since Milestone V-A/B and RTL has, until now,
         // never actually delivered -- every prior RTL milestone's own
         // "violation suppresses write" floor left PC unaffected,
         // meaning execution silently continued past a blocked access.
         // Checked before MRET (both can't be true from the same
         // instruction -- MRET is its own, unrelated opcode -- but
         // trap takes priority in the mux ordering as the more
         // security-critical of the two, matching this file's own
         // established "most critical condition first" mux style).
         // RTL Milestone 10: OCInvoke's own real jump -- checked after
         // $veda_trap_taken (an OCInvoke that fails its own checks is
         // already routed to $veda_trap_taken above, never reaches
         // here) but the success path is a real, unconditional hardware
         // redirect, the literal "atomic unseal-and-jump" CHERI's own
         // real CInvoke performs (CHERI ISA spec p.209's own
         // `nextPC = newPC` on the success path) -- not a two-
         // instruction unseal-then-JALR software sequence.
         // RTL Milestone 17: OCJALR's own real jump, the same real
         // unconditional-hardware-redirect shape OCInvoke's own jump
         // above already established (a failing OCJALR is already
         // routed to $veda_trap_taken, never reaches here).
         // Minimal OS kernel Milestone B: VEDA_OCRETURN's own real jump
         // joins the same unconditional-hardware-redirect family as
         // OCInvoke/OCJALR above (a failing OCRETURN is already routed
         // to $veda_trap_taken, never reaches here).
         $pc_src = $veda_trap_taken || $is_mret ||
                   ($is_veda_ocinvoke && !$veda_ocinvoke_violation) ||
                   ($is_veda_ocjalr && !$veda_ocjalr_violation) ||
                   ($is_veda_ocreturn && !$veda_ocreturn_violation) ||
                   $is_jal || $is_jalr || $branch_taken;
         $alt_pc[63:0] = $veda_trap_taken ? $mtvec :
                          $is_mret         ? $mepc :
                          ($is_veda_ocinvoke && !$veda_ocinvoke_violation) ? $veda_ocinvoke_target :
                          ($is_veda_ocjalr && !$veda_ocjalr_violation) ? $veda_ocjalr_target :
                          ($is_veda_ocreturn && !$veda_ocreturn_violation) ? $veda_ocreturn_target :
                          $is_jal ? $jal_target : $is_jalr ? $jalr_target : $branch_target;

         // ─────────────────────────────────────────────────────────
         //  DATA MEMORY — byte-addressable via a doubleword-granular
         //  /dmem array (64 entries, byte addresses 0-511) with
         //  explicit byte-lane shift/mask/merge logic on top, the
         //  standard technique for byte-addressable memory backed by
         //  word-granular storage.
         // ─────────────────────────────────────────────────────────
         $mem_addr[63:0]     = $rs1_data + ($is_store ? $imm_s : $imm_i);
         $mem_word_idx[5:0]  = $mem_addr[8:3];
         $mem_byte_off[2:0]  = $mem_addr[2:0];
         // RTL MILESTONE 19 (Sail mirror): Veda-Purecap Enforcement --
         // closes the real CGetBase-then-ordinary-load/store bypass
         // (`cgetbase x1,c2` then a plain `ld`/`sd` through x1 completely
         // skips every Veda-Core check). An ordinary base-ISA load/store
         // traps if EITHER veda_mode's own purecap bit is set (a global
         // "no ordinary load/store anywhere" switch) OR the live
         // compartment is narrowed away from VEDA_PCC_UNBOUNDED (code
         // entered via a successful OCInvoke can otherwise still read/
         // write memory directly, undermining the isolation OCInvoke/PCC
         // -bounding is meant to provide) -- both trigger conditions
         // verified directly against MILESTONE_19_RESULTS.md's own Sail
         // design before writing this. Deliberately does NOT touch any
         // Veda-Core instruction's own memory path ($veda_ocl_load_data,
         // OCS.D's write, etc.) -- those already go through their own,
         // separate capability checks entirely (veda_check_access), zero
         // shared code path by construction, matching the Sail side's own
         // "never interferes with a legitimate Veda access" guarantee.
         $veda_purecap_violation = ($is_load || $is_store) &&
                                    ($veda_mode[0] || ($veda_pcc_length != 40'hFFFFFFFFFF));
         // VEDA-CORE RTL MILESTONE 7: base ISA stores can land inside the
         // same real elfmem[] region Veda-Core objects live in (in
         // act4_mode) -- must clear that granule's tag too (see the byte-
         // granular tag invalidation comment near $veda_capmem_granule
         // above). Real bounds check needed here, unlike the Veda-only
         // granule signals above: an ordinary base-ISA store's address
         // isn't capability-checked, so it can legitimately land outside
         // ELFMEM_BASE/ELFMEM_SIZE (act4_mode is off) or even, in
         // principle, out of range within act4_mode -- guarded rather
         // than assumed in-range.
         $veda_baseisa_store_in_range = ($mem_addr[31:0] >= ELFMEM_BASE) && ($mem_addr[31:0] < (ELFMEM_BASE + ELFMEM_SIZE));
         $veda_baseisa_store_granule[31:0] = ($mem_addr[31:0] - ELFMEM_BASE) >> 5;
         $mem_shift_bits[5:0] = {$mem_byte_off, 3'b0};

         $mem_cur_word[63:0] = /dmem[$mem_word_idx]$val;
         // Milestone C: an 8-byte little-endian read starting at the
         // exact target address, straight from elfmem -- equivalent in
         // shape to $mem_cur_word already shifted so the target byte
         // sits at bit 0, so it slots into the *existing* width-based
         // extraction/sign-extension logic below completely unchanged.
         $mem_bytes_elf[63:0] =
            {elfmem[$mem_addr[31:0]+7], elfmem[$mem_addr[31:0]+6],
             elfmem[$mem_addr[31:0]+5], elfmem[$mem_addr[31:0]+4],
             elfmem[$mem_addr[31:0]+3], elfmem[$mem_addr[31:0]+2],
             elfmem[$mem_addr[31:0]+1], elfmem[$mem_addr[31:0]+0]};
         $mem_shifted[63:0]  = act4_mode ? $mem_bytes_elf : ($mem_cur_word >> $mem_shift_bits);

         // VEDA-CORE: OCL.D's own 8-byte little-endian read, same shape
         // as $mem_bytes_elf above but at $veda_real_addr (the capability-
         // resolved location, Base+offset), not $mem_addr -- a real,
         // separate physical target from the base ISA's own loads, not
         // a reinterpretation of the same address computation.
         $veda_ocl_load_data[63:0] =
            {elfmem[$veda_real_addr[31:0]+7], elfmem[$veda_real_addr[31:0]+6],
             elfmem[$veda_real_addr[31:0]+5], elfmem[$veda_real_addr[31:0]+4],
             elfmem[$veda_real_addr[31:0]+3], elfmem[$veda_real_addr[31:0]+2],
             elfmem[$veda_real_addr[31:0]+1], elfmem[$veda_real_addr[31:0]+0]};

         // OCL.C's own 16-byte little-endian read (Milestone 7) -- same
         // real shape as OCL.D's 8-byte read directly above, doubled in
         // width, at the identical $veda_real_addr. Feeds /vreg's own new
         // OCL.C write source below, not $load_data/$wr_data (this
         // instruction's destination is a Capability Register, not a
         // GPR -- same reason OCA/CSetBounds/CSeal/CUnseal are absent
         // from $reg_write below).
         // MILESTONE 24 Stage 3: real address-range mux -- a TCM-tier
         // OCL.C reads from tcm_scratch[] (real, separate array, never
         // elfmem[] itself, matching the design's own genuinely-separate
         // -array precedent), a DRAM-tier one reads from elfmem[]
         // exactly as every prior milestone already did.
         // RTL-2b: a capability is 32 bytes now -- both arms read 32, not 16.
         $veda_oclc_load_data[255:0] =
            $veda_capmem_tcm_hit ?
            {tcm_scratch[$veda_real_addr[31:0]+31], tcm_scratch[$veda_real_addr[31:0]+30],
             tcm_scratch[$veda_real_addr[31:0]+29], tcm_scratch[$veda_real_addr[31:0]+28],
             tcm_scratch[$veda_real_addr[31:0]+27], tcm_scratch[$veda_real_addr[31:0]+26],
             tcm_scratch[$veda_real_addr[31:0]+25], tcm_scratch[$veda_real_addr[31:0]+24],
             tcm_scratch[$veda_real_addr[31:0]+23], tcm_scratch[$veda_real_addr[31:0]+22],
             tcm_scratch[$veda_real_addr[31:0]+21], tcm_scratch[$veda_real_addr[31:0]+20],
             tcm_scratch[$veda_real_addr[31:0]+19], tcm_scratch[$veda_real_addr[31:0]+18],
             tcm_scratch[$veda_real_addr[31:0]+17], tcm_scratch[$veda_real_addr[31:0]+16],
             tcm_scratch[$veda_real_addr[31:0]+15], tcm_scratch[$veda_real_addr[31:0]+14],
             tcm_scratch[$veda_real_addr[31:0]+13], tcm_scratch[$veda_real_addr[31:0]+12],
             tcm_scratch[$veda_real_addr[31:0]+11], tcm_scratch[$veda_real_addr[31:0]+10],
             tcm_scratch[$veda_real_addr[31:0]+9], tcm_scratch[$veda_real_addr[31:0]+8],
             tcm_scratch[$veda_real_addr[31:0]+7], tcm_scratch[$veda_real_addr[31:0]+6],
             tcm_scratch[$veda_real_addr[31:0]+5], tcm_scratch[$veda_real_addr[31:0]+4],
             tcm_scratch[$veda_real_addr[31:0]+3], tcm_scratch[$veda_real_addr[31:0]+2],
             tcm_scratch[$veda_real_addr[31:0]+1], tcm_scratch[$veda_real_addr[31:0]+0]} :
            {elfmem[$veda_real_addr[31:0]+31], elfmem[$veda_real_addr[31:0]+30],
             elfmem[$veda_real_addr[31:0]+29], elfmem[$veda_real_addr[31:0]+28],
             elfmem[$veda_real_addr[31:0]+27], elfmem[$veda_real_addr[31:0]+26],
             elfmem[$veda_real_addr[31:0]+25], elfmem[$veda_real_addr[31:0]+24],
             elfmem[$veda_real_addr[31:0]+23], elfmem[$veda_real_addr[31:0]+22],
             elfmem[$veda_real_addr[31:0]+21], elfmem[$veda_real_addr[31:0]+20],
             elfmem[$veda_real_addr[31:0]+19], elfmem[$veda_real_addr[31:0]+18],
             elfmem[$veda_real_addr[31:0]+17], elfmem[$veda_real_addr[31:0]+16],
             elfmem[$veda_real_addr[31:0]+15], elfmem[$veda_real_addr[31:0]+14],
             elfmem[$veda_real_addr[31:0]+13], elfmem[$veda_real_addr[31:0]+12],
             elfmem[$veda_real_addr[31:0]+11], elfmem[$veda_real_addr[31:0]+10],
             elfmem[$veda_real_addr[31:0]+9], elfmem[$veda_real_addr[31:0]+8],
             elfmem[$veda_real_addr[31:0]+7], elfmem[$veda_real_addr[31:0]+6],
             elfmem[$veda_real_addr[31:0]+5], elfmem[$veda_real_addr[31:0]+4],
             elfmem[$veda_real_addr[31:0]+3], elfmem[$veda_real_addr[31:0]+2],
             elfmem[$veda_real_addr[31:0]+1], elfmem[$veda_real_addr[31:0]+0]};
         // Field-for-field the inverse of $veda_ocsc_packed's own pack
         // order above (Object_ID @ Base @ Length @ Offset @ Perms @
         // otype @ Reserved @ 1'b0 padding) -- matching the Sail model's
         // veda_cap_unpack exactly.
         // RTL-2b: transcribed from DESIGN_01's layout table character by
         // character, NOT re-derived from widths -- Perms [75:60] and otype
         // [59:44] are the two a width-driven review skips because their
         // widths did not change, yet their POSITIONS moved.
         $veda_oclc_unpacked_object_id[43:0] = $veda_oclc_load_data[255:212];
         $veda_oclc_unpacked_base[55:0]      = $veda_oclc_load_data[211:156];
         $veda_oclc_unpacked_length[39:0]    = $veda_oclc_load_data[155:116];
         $veda_oclc_unpacked_offset[39:0]    = $veda_oclc_load_data[115:76];
         $veda_oclc_unpacked_perms[15:0]     = $veda_oclc_load_data[75:60];
         $veda_oclc_unpacked_otype[15:0]     = $veda_oclc_load_data[59:44];
         $veda_oclc_unpacked_reserved[23:0]  = $veda_oclc_load_data[43:20];
         $veda_oclc_unpacked_flags[19:0]     = $veda_oclc_load_data[19:0];
         // The memory-resident Tag -- a capability loaded from memory is
         // only as trustworthy as what a real OCS.C genuinely stored
         // there (tag_mem[]), never assumed true just because the load
         // itself succeeded (real CHERI's own core tagged-memory
         // property, already the load-bearing reason this milestone
         // exists, restated here at the point it's actually enforced).
         // MILESTONE 24 Stage 3: the SAME tier decision selects the tag
         // source AND its own tier-relative granule index -- reading
         // tag_mem[] with a tcm_scratch-relative granule (or vice versa)
         // is exactly the aliasing/overflow risk flagged before writing
         // this; both index AND array must switch together.
         $veda_oclc_loaded_tag = $veda_capmem_tcm_hit ?
            tcm_scratch_tag[$veda_capmem_tcm_granule] : tag_mem[$veda_capmem_granule];

         $load_data[63:0] =
            $is_lb  ? {{56{$mem_shifted[7]}},  $mem_shifted[7:0]}  :
            $is_lh  ? {{48{$mem_shifted[15]}}, $mem_shifted[15:0]} :
            $is_lw  ? {{32{$mem_shifted[31]}}, $mem_shifted[31:0]} :
            $is_lbu ? {56'b0, $mem_shifted[7:0]}  :
            $is_lhu ? {48'b0, $mem_shifted[15:0]} :
            $is_lwu ? {32'b0, $mem_shifted[31:0]} :
            $is_ld  ? $mem_shifted :
                      64'b0;

         $store_mask_base[63:0] =
            $is_sb ? 64'h00000000000000FF :
            $is_sh ? 64'h000000000000FFFF :
            $is_sw ? 64'h00000000FFFFFFFF :
            $is_sd ? 64'hFFFFFFFFFFFFFFFF :
                     64'b0;
         $store_mask[63:0]     = $store_mask_base << $mem_shift_bits;
         $store_data_sh[63:0]  = ($rs2_data << $mem_shift_bits) & $store_mask;
         $dmem_new_word[63:0]  = ($mem_cur_word & ~$store_mask) | $store_data_sh;

         /dmem[63:0]
            // RTL Milestone 19: !(|cpu>>1$veda_purecap_violation) added,
            // matching the real elfmem write block's own identical gate
            // below -- kept consistent even though every real milestone
            // test exercises the elfmem (act4_mode) path, not this
            // Milestone A/B-era ROM-testing one.
            $wr_en = |cpu>>1$is_store &&
                     !(|cpu>>1$veda_purecap_violation) &&
                     (|cpu>>1$mem_word_idx == #dmem);
            $val[63:0] = (|cpu$reset || |cpu>>1$reset) ? 64'b0 :
                         $wr_en ? |cpu>>1$dmem_new_word :
                                  $RETAIN;

         // ─────────────────────────────────────────────────────────
         //  WRITEBACK
         // ─────────────────────────────────────────────────────────
         $wr_data[63:0] =
            ($is_jal || $is_jalr) ? ($pc + 64'd4) :
            $is_lui                 ? $imm_u :
            $is_auipc                ? ($pc + $imm_u) :
            $is_load                  ? $load_data :
            $is_veda_ocl               ? $veda_ocl_load_data :
            ($is_veda_nmc_add_w || $is_veda_nmc_add_d) ? $veda_nmc_rd_value :
            $is_veda_atomic                              ? $veda_cap_old_d :
            $is_veda_capquery                              ? $veda_capquery_result :
            // rd = 0 on success, matching Sail's own "X(rd) = zeros()"
            // exactly (VEDA_CORE_SPEC.md Section 5.1: "rd unused (written
            // 0 on success)"). Irrelevant when a violation suppresses the
            // write ($reg_write already gates that off above).
            // RTL-6c: both new instructions do X(rd) = zeros() on success.
            //
            // HONEST NOTE, because the first version of this comment was
            // wrong and asserting it without checking is the failure this
            // project keeps guarding against. It claimed that omitting the
            // arm would let rd fall through to a "plausible-looking nonzero
            // value". It would not: the fall-through is $alu_result, whose
            // $alu_result64 chain defaults to 64'b0, and a Custom-0 opcode
            // matches no ALU arm. So rd reads 0 either way, and a mutant
            // deleting these two decodes from this list is PROVABLY
            // EQUIVALENT -- confirmed by running it, not by argument.
            //
            // The arm stays regardless. The correct value here must be a
            // stated decision, not an accident of an unrelated default two
            // thousand lines away that any future ALU change could move.
            ($is_veda_odt_populate || $is_veda_odt_populate_fast || $is_veda_odt_destroy ||
             $is_veda_odt_page_out || $is_veda_odt_page_in) ? 64'b0 :
            // RTL Milestone 9: rd = the CSR's value from BEFORE this
            // write (real CSRRW/CSRRS semantics) -- $csr_rdata is read
            // combinationally in the same cycle the write is computed,
            // matching real hardware's own atomic "read-then-write"
            // CSR access.
            $is_csr_access ? $csr_rdata :
                                         $alu_result;

         // ═════════════════════════════════════════════════════════
         //  VIZ — RV64I Single-Cycle Datapath status view. Follows
         //  arm_single_cycle.tlv's proven 'sig'.asBigInt/asInt/asBool
         //  signal-reading convention. Added at the end of Milestone B
         //  (per plan Section 4) now that the full 50-encoding datapath
         //  is stable, rather than re-visualizing a moving target
         //  through Milestones A and B.
         \viz_js
            box: {width: 1080, height: 620, fill: "#0d1117", stroke: "#30363d", strokeWidth: 1},
            where: {left: 0, top: 0},
            init() {
               const mkTxt = (x,y,s,size,colorv,boldv) => new fabric.Text(s, {left: x, top: y, fontSize: size || 10, fill: colorv || "#c9d1d9", fontFamily: "monospace", fontWeight: boldv ? 700 : 400, selectable: false, evented: false})
               const mkBox = (x,y,w,h,fillv,strokev) => new fabric.Rect({left: x, top: y, width: w, height: h, fill: fillv || "#161b22", stroke: strokev || "#30363d", strokeWidth: 1, rx: 3, ry: 3, selectable: false, evented: false})

               let hdr_box = mkBox(0, 0, 1080, 36, "#ffffff", "#ffffff")
               let hdr_ttl = new fabric.Text("RVA23 Base Core -- RV64I Single-Cycle CPU (Phase 1)", {left: 300, top: 8, fontSize: 18, fill: "#128BAB", fontWeight: 700, fontFamily: "Gill Sans, Calibri, sans-serif", selectable: false, evented: false})

               // Status strip: PC, raw instruction word, disassembly.
               let status_box = mkBox(10, 46, 1060, 56)
               let status_pc    = mkTxt(20, 54, "PC=0x0", 13, "#0969da", true)
               let status_instr = mkTxt(160, 54, "instr=0x00000000", 12, "#8b949e", false)
               let status_asm   = mkTxt(420, 54, "--", 15, "#3fb950", true)
               let status_line2 = mkTxt(20, 76, "", 11, "#e3b341", false)

               // Datapath activity indicators.
               let dp_box = mkBox(10, 110, 1060, 40)
               const DP_LABELS = ["RegWrite","ALU","Branch","Jump","Load","Store","W-op","Fence"]
               let dpCells = {}
               DP_LABELS.forEach((nm, i) => {
                  let cx = 20 + i * 132
                  dpCells["dp_lbl_" + i] = mkTxt(cx, 118, nm, 10, "#555555", false)
                  dpCells["dp_led_" + i] = new fabric.Circle({left: cx, top: 132, radius: 6, fill: "#30363d", selectable: false, evented: false})
               })

               // Register grid: x0-x31, 8 columns x 4 rows.
               let rg_box = mkBox(10, 160, 1060, 200)
               let rgCells = {}
               for (let i = 0; i < 32; i++) {
                  let col = i % 8, row = Math.floor(i / 8)
                  let cx = 20 + col * 131, cy = 168 + row * 48
                  rgCells["rg_cell_" + i] = mkBox(cx, cy, 125, 42, "#0d1117", "#128BAB")
                  rgCells["rg_lbl_" + i]  = mkTxt(cx + 6, cy + 3, "x" + i, 9, "#128BAB", true)
                  rgCells["rg_val_" + i]  = mkTxt(cx + 6, cy + 18, "0", 10, "#e6edf3", false)
               }

               // Data-memory activity line (address + operation, when active).
               let mem_box = mkBox(10, 370, 1060, 34)
               let mem_txt = mkTxt(20, 380, "mem: --", 11, "#c9d1d9", false)

               // Cycle counter / PASS banner.
               let bottom_box = mkBox(10, 414, 1060, 40)
               let cyc_txt = mkTxt(20, 424, "cyc=0", 11, "#8b949e", false)
               let pass_txt = mkTxt(160, 424, "", 13, "#e3b341", true)

               return Object.assign({
                  hdr_box, hdr_ttl, status_box, status_pc, status_instr, status_asm, status_line2,
                  dp_box, rg_box, mem_box, mem_txt, bottom_box, cyc_txt, pass_txt
               }, dpCells, rgCells)
            },
            render() {
               const h = (v, w) => "0x" + BigInt.asUintN(64, BigInt(v)).toString(16).toUpperCase().padStart(w || 16, "0")

               let pc      = '$pc'.asBigInt(0n)
               let instr   = '$instr'.asInt(0)
               let cyc     = '$cyc_cnt'.asInt(0)
               let reg_write = '$reg_write'.asBool(false)
               let is_load = '$is_load'.asBool(false)
               let is_store= '$is_store'.asBool(false)
               let is_jal  = '$is_jal'.asBool(false)
               let is_jalr = '$is_jalr'.asBool(false)
               let branch_taken = '$branch_taken'.asBool(false)
               let is_w_op = '$is_w_op'.asBool(false)
               let is_fence = '$is_fence'.asBool(false)
               let alu_res = '$alu_result'.asBigInt(0n)
               let mem_addr = '$mem_addr'.asBigInt(0n)

               // Minimal disassembler covering all 50 RV64I encodings,
               // decoded straight from the instruction bits (never a
               // separately hand-maintained mnemonic list).
               const disasm = (w) => {
                  w = w >>> 0
                  let op = w & 0x7F, f3 = (w >>> 12) & 0x7, f7 = (w >>> 25) & 0x7F
                  let rd = (w >>> 7) & 0x1F, rs1 = (w >>> 15) & 0x1F, rs2 = (w >>> 20) & 0x1F
                  const R = (nm) => nm + " x" + rd + ",x" + rs1 + ",x" + rs2
                  const I = (nm) => nm + " x" + rd + ",x" + rs1
                  if (op === 0x33) { // OP
                     if (f3===0 && f7===0) return R("add"); if (f3===0 && f7===0x20) return R("sub")
                     if (f3===1) return R("sll"); if (f3===2) return R("slt"); if (f3===3) return R("sltu")
                     if (f3===4) return R("xor"); if (f3===5 && f7===0) return R("srl"); if (f3===5 && f7===0x20) return R("sra")
                     if (f3===6) return R("or"); if (f3===7) return R("and")
                  }
                  if (op === 0x13) { // OP-IMM
                     if (f3===0) return I("addi"); if (f3===2) return I("slti"); if (f3===3) return I("sltiu")
                     if (f3===4) return I("xori"); if (f3===6) return I("ori"); if (f3===7) return I("andi")
                     if (f3===1) return I("slli"); if (f3===5 && f7===0) return I("srli"); if (f3===5 && f7===0x20) return I("srai")
                  }
                  if (op === 0x63) { // BRANCH
                     const B = (nm) => nm + " x" + rs1 + ",x" + rs2
                     if (f3===0) return B("beq"); if (f3===1) return B("bne"); if (f3===4) return B("blt")
                     if (f3===5) return B("bge"); if (f3===6) return B("bltu"); if (f3===7) return B("bgeu")
                  }
                  if (op === 0x6F) return "jal x" + rd
                  if (op === 0x67) return "jalr x" + rd + ",x" + rs1
                  if (op === 0x37) return "lui x" + rd
                  if (op === 0x17) return "auipc x" + rd
                  if (op === 0x03) { // LOAD
                     if (f3===0) return "lb x"+rd+",(x"+rs1+")"; if (f3===1) return "lh x"+rd+",(x"+rs1+")"
                     if (f3===2) return "lw x"+rd+",(x"+rs1+")"; if (f3===3) return "ld x"+rd+",(x"+rs1+")"
                     if (f3===4) return "lbu x"+rd+",(x"+rs1+")"; if (f3===5) return "lhu x"+rd+",(x"+rs1+")"
                     if (f3===6) return "lwu x"+rd+",(x"+rs1+")"
                  }
                  if (op === 0x23) { // STORE
                     if (f3===0) return "sb x"+rs2+",(x"+rs1+")"; if (f3===1) return "sh x"+rs2+",(x"+rs1+")"
                     if (f3===2) return "sw x"+rs2+",(x"+rs1+")"; if (f3===3) return "sd x"+rs2+",(x"+rs1+")"
                  }
                  if (op === 0x1B) { // OP-IMM-32
                     if (f3===0) return I("addiw"); if (f3===1) return I("slliw")
                     if (f3===5 && f7===0) return I("srliw"); if (f3===5 && f7===0x20) return I("sraiw")
                  }
                  if (op === 0x3B) { // OP-32
                     if (f3===0 && f7===0) return R("addw"); if (f3===0 && f7===0x20) return R("subw")
                     if (f3===1) return R("sllw"); if (f3===5 && f7===0) return R("srlw"); if (f3===5 && f7===0x20) return R("sraw")
                  }
                  if (op === 0x0F) return "fence"
                  return "-- (0x" + w.toString(16) + ")"
               }

               let objs = this.getObjects()

               objs.status_pc.set({text: "PC=" + h(pc, 4)})
               objs.status_instr.set({text: "instr=" + h(instr, 8)})
               objs.status_asm.set({text: disasm(instr)})
               objs.status_line2.set({text: (is_load||is_store) ? ("mem_addr=" + h(mem_addr,4)) :
                                             (is_jal||is_jalr||branch_taken) ? "control transfer" : ""})

               const dpVals = [reg_write, true, branch_taken, (is_jal||is_jalr), is_load, is_store, is_w_op, is_fence]
               for (let i = 0; i < 8; i++) {
                  objs["dp_led_" + i].set({fill: dpVals[i] ? "#3fb950" : "#30363d"})
               }

               // SandPiper's preprocessor scans for /scope[N]$sig syntax
               // even inside JS string literals, so each register must be
               // read via its own literal-index string (matching
               // arm_single_cycle.tlv's proven pattern) -- a dynamically
               // interpolated '/xreg[' + i + ']$val' string is not
               // recognized and breaks the headless transpile.
               let xregs = [0n,
                  '/xreg[1]$val'.asBigInt(0n),  '/xreg[2]$val'.asBigInt(0n),  '/xreg[3]$val'.asBigInt(0n),
                  '/xreg[4]$val'.asBigInt(0n),  '/xreg[5]$val'.asBigInt(0n),  '/xreg[6]$val'.asBigInt(0n),
                  '/xreg[7]$val'.asBigInt(0n),  '/xreg[8]$val'.asBigInt(0n),  '/xreg[9]$val'.asBigInt(0n),
                  '/xreg[10]$val'.asBigInt(0n), '/xreg[11]$val'.asBigInt(0n), '/xreg[12]$val'.asBigInt(0n),
                  '/xreg[13]$val'.asBigInt(0n), '/xreg[14]$val'.asBigInt(0n), '/xreg[15]$val'.asBigInt(0n),
                  '/xreg[16]$val'.asBigInt(0n), '/xreg[17]$val'.asBigInt(0n), '/xreg[18]$val'.asBigInt(0n),
                  '/xreg[19]$val'.asBigInt(0n), '/xreg[20]$val'.asBigInt(0n), '/xreg[21]$val'.asBigInt(0n),
                  '/xreg[22]$val'.asBigInt(0n), '/xreg[23]$val'.asBigInt(0n), '/xreg[24]$val'.asBigInt(0n),
                  '/xreg[25]$val'.asBigInt(0n), '/xreg[26]$val'.asBigInt(0n), '/xreg[27]$val'.asBigInt(0n),
                  '/xreg[28]$val'.asBigInt(0n), '/xreg[29]$val'.asBigInt(0n), '/xreg[30]$val'.asBigInt(0n),
                  '/xreg[31]$val'.asBigInt(0n)]
               for (let i = 0; i < 32; i++) {
                  objs["rg_val_" + i].set({text: xregs[i].toString()})
               }

               // Mirrors *passed's condition (Section "PASS/FAIL" below) using
               // the same register values already read above -- the viz_js
               // signal-string convention only resolves $name/scope[n]$name
               // pipeline signals, not top-level *name assertions, so '*passed'
               // cannot be read directly here (confirmed: attempting to do so
               // throws "Unexpected token '*'" in Makerchip's real VIZ runtime).
               let passed = (xregs[15] === 1n) && (xregs[16] === 1n) &&
                            (xregs[30] === 1n) && (xregs[10] === 20n) &&
                            (cyc > 100)

               objs.mem_txt.set({text: (is_load||is_store) ? ("mem: " + (is_load?"READ":"WRITE") + " @" + h(mem_addr,4) + " alu=" + alu_res) : "mem: --"})
               objs.cyc_txt.set({text: "cyc=" + cyc})
               objs.pass_txt.set({text: passed ? "PASS" : ""})
               objs.pass_txt.set({fill: "#3fb950"})
            }

   // ─────────────────────────────────────────────────────────────
   //  PASS / FAIL — a small, robust set of final-state checks (the
   //  last write to each of these registers happens near the very end
   //  of the program, nothing overwrites them afterward). Full 50-
   //  encoding coverage is verified via manual trace review against
   //  the expected values documented inline in the program above, per
   //  Milestone B's own done criteria.
   // ─────────────────────────────────────────────────────────────
   *passed = (|cpu/xreg[15]>>1$val == 64'd1)  &&   // ROM[77] JALR landing
             (|cpu/xreg[16]>>1$val == 64'd1)  &&   // ROM[79] post-FENCE
             (|cpu/xreg[30]>>1$val == 64'd1)  &&   // ROM[39] JAL landing
             (|cpu/xreg[10]>>1$val == 64'd20) &&   // ROM[72] SLLW result
             (|cpu>>1$cyc_cnt > 32'd100);
   *failed = 1'b0;

   // Milestone C's elfmem store (see trailing \SV block at end of file)
   // references |cpu@0's real mangled SV signal names directly
   // (CPU_is_store_a0, CPU_mem_addr_a0, etc. -- confirmed by inspecting
   // this file's own SandPiper-generated output) rather than bridging
   // through a new *name[N:0] top-level signal: SandPiper generates a
   // bare `assign` for a wide, non-predeclared *name[N:0] without a
   // matching net declaration, which Icarus correctly rejects
   // ("Net ... is not defined in this context") -- confirmed by
   // actually attempting it and reading the real error, not assumed.

\SV
   // Milestone C: performs the actual byte-wise store into elfmem.
   // References |cpu@0's real mangled SV signal names directly (see
   // note above this block's *-driven predecessor, removed after
   // confirming SandPiper doesn't correctly declare a new wide
   // *name[N:0] top-level net). Standard synchronous-write timing
   // (non-blocking assignment => value committed and visible starting
   // next clock edge), matching how /dmem's own $wr_en/$val TLV idiom
   // already behaves.
   always_ff @(posedge clk) begin
      // RTL Milestone 19: !CPU_veda_purecap_violation_a0 added -- an
      // ordinary base-ISA store blocked by purecap enforcement must not
      // write elfmem at all (the real, previously-open bypass this
      // milestone closes: a raw address extracted via cgetbase followed
      // by a plain sd used to reach this exact write, completely
      // unchecked).
      if (act4_mode && CPU_is_store_a0 && !CPU_veda_purecap_violation_a0) begin
         if (CPU_is_sb_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
         end else if (CPU_is_sh_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
         end else if (CPU_is_sw_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
            elfmem[CPU_mem_addr_a0[31:0]+2] <= CPU_rs2_data_a0[23:16];
            elfmem[CPU_mem_addr_a0[31:0]+3] <= CPU_rs2_data_a0[31:24];
         end else if (CPU_is_sd_a0) begin
            elfmem[CPU_mem_addr_a0[31:0]+0] <= CPU_rs2_data_a0[7:0];
            elfmem[CPU_mem_addr_a0[31:0]+1] <= CPU_rs2_data_a0[15:8];
            elfmem[CPU_mem_addr_a0[31:0]+2] <= CPU_rs2_data_a0[23:16];
            elfmem[CPU_mem_addr_a0[31:0]+3] <= CPU_rs2_data_a0[31:24];
            elfmem[CPU_mem_addr_a0[31:0]+4] <= CPU_rs2_data_a0[39:32];
            elfmem[CPU_mem_addr_a0[31:0]+5] <= CPU_rs2_data_a0[47:40];
            elfmem[CPU_mem_addr_a0[31:0]+6] <= CPU_rs2_data_a0[55:48];
            elfmem[CPU_mem_addr_a0[31:0]+7] <= CPU_rs2_data_a0[63:56];
         end
         // Milestone 7: byte-granular tag invalidation -- an ordinary
         // base-ISA store landing inside the same real elfmem[] region a
         // Veda-Core object's tagged capability might occupy must clear
         // that granule's tag, the identical real property every Veda
         // write block below also now enforces. Gated on
         // CPU_veda_baseisa_store_in_range_a0 -- tag_mem[] is a real,
         // bounded array (ELFMEM_SIZE/32 entries), an out-of-range index
         // here would be a real simulation error, not assumed safe.
         if (CPU_veda_baseisa_store_in_range_a0) begin
            tag_mem[CPU_veda_baseisa_store_granule_a0] <= 1'b0;
         end
      end
   end

   // VEDA-CORE: OCS.D's own store into elfmem, a real, separate
   // always_ff block rather than folding into the block above --
   // deliberately kept independent of the base ISA's own $is_store/
   // $mem_addr signals (a different physical-address computation and a
   // different value source, $veda_ocs_value via $rd, not $rs2_data) so
   // this new logic carries zero risk of regressing the base core's own
   // already-verified 51/51 ACT4 RV64I conformance. Gated on
   // !CPU_veda_violation_a0 -- the real security property this
   // milestone can actually enforce without trap infrastructure
   // (MILESTONE_PLAN.md item 2): an illegal OCS.D simply never writes.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_ocs_a0 && !CPU_veda_violation_a0) begin
         elfmem[CPU_veda_real_addr_a0[31:0]+0] <= CPU_veda_ocs_value_a0[7:0];
         elfmem[CPU_veda_real_addr_a0[31:0]+1] <= CPU_veda_ocs_value_a0[15:8];
         elfmem[CPU_veda_real_addr_a0[31:0]+2] <= CPU_veda_ocs_value_a0[23:16];
         elfmem[CPU_veda_real_addr_a0[31:0]+3] <= CPU_veda_ocs_value_a0[31:24];
         elfmem[CPU_veda_real_addr_a0[31:0]+4] <= CPU_veda_ocs_value_a0[39:32];
         elfmem[CPU_veda_real_addr_a0[31:0]+5] <= CPU_veda_ocs_value_a0[47:40];
         elfmem[CPU_veda_real_addr_a0[31:0]+6] <= CPU_veda_ocs_value_a0[55:48];
         elfmem[CPU_veda_real_addr_a0[31:0]+7] <= CPU_veda_ocs_value_a0[63:56];
         // Milestone 7: byte-granular tag invalidation -- this is the
         // exact real gap Milestone 7's own negative test caught (not
         // assumed correct from the design alone): an OCS.D that lands
         // in the same granule a real OCS.C previously tagged must clear
         // that tag, or a capability's own raw bytes could be silently
         // corrupted while tag_mem[] kept reporting it as still valid.
         tag_mem[CPU_veda_capmem_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 2: NMC_ADD.{W,D}'s own real-memory
   // read-modify-write. The read half is already combinational
   // ($veda_cap_old_d/_w, consumed both for the ALU result computed in
   // TLV and for rd's writeback), so only the write half needs a real
   // synchronous always_ff -- the identical single-cycle RMW pattern
   // already proven for the base ISA's own stores and for OCS.D above,
   // just with the write DATA now computed from a real ALU operation
   // rather than a passthrough GPR value.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_nmc_add_d_a0 && !CPU_veda_nmc_add_d_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_nmc_add_result_d_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_nmc_add_result_d_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_nmc_add_result_d_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_nmc_add_result_d_a0[31:24];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+4] <= CPU_veda_nmc_add_result_d_a0[39:32];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+5] <= CPU_veda_nmc_add_result_d_a0[47:40];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+6] <= CPU_veda_nmc_add_result_d_a0[55:48];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+7] <= CPU_veda_nmc_add_result_d_a0[63:56];
      end else if (act4_mode && CPU_is_veda_nmc_add_w_a0 && !CPU_veda_nmc_add_w_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_nmc_add_result_w_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_nmc_add_result_w_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_nmc_add_result_w_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_nmc_add_result_w_a0[31:24];
      end
      // Milestone 7: byte-granular tag invalidation, both W and D --
      // real-memory compute-at-memory writes are exactly the kind of
      // plain, non-OCS.C write that must clear a granule's tag if it
      // overlaps one, the same real property every other write block in
      // this file now enforces.
      if (act4_mode && ((CPU_is_veda_nmc_add_d_a0 && !CPU_veda_nmc_add_d_violation_a0) ||
                         (CPU_is_veda_nmc_add_w_a0 && !CPU_veda_nmc_add_w_violation_a0))) begin
         tag_mem[CPU_veda_capmem_nmc_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 2: Veda-Atomic's own real-memory
   // read-modify-write, D-width only this milestone (matching the decode
   // scope above). Same real pattern as NMC_ADD's own write block.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_atomic_a0 && !CPU_veda_atomic_violation_a0) begin
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+0] <= CPU_veda_atomic_result_a0[7:0];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+1] <= CPU_veda_atomic_result_a0[15:8];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+2] <= CPU_veda_atomic_result_a0[23:16];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+3] <= CPU_veda_atomic_result_a0[31:24];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+4] <= CPU_veda_atomic_result_a0[39:32];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+5] <= CPU_veda_atomic_result_a0[47:40];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+6] <= CPU_veda_atomic_result_a0[55:48];
         elfmem[CPU_veda_cap_real_addr_a0[31:0]+7] <= CPU_veda_atomic_result_a0[63:56];
         // Milestone 7: byte-granular tag invalidation -- same real
         // property, Veda-Atomic's own write.
         tag_mem[CPU_veda_capmem_nmc_granule_a0] <= 1'b0;
      end
   end

   // VEDA-CORE RTL MILESTONE 4: ODT-Populate/ODT-Destroy's own real
   // write into odt_mem[] -- the same real byte-addressable array
   // Object-Bind/OCL/OCS/etc. already read from above, written here for
   // the first time. Gated on !CPU_veda_odt_populate_violation_a0 /
   // !CPU_veda_odt_destroy_violation_a0 -- MILESTONE_PLAN.md's Milestone
   // 4 addendum's real $priv gate, the identical violation-suppresses-
   // write convention already used for every other soft-fail in this
   // file, now closing the one real gap (minting new capability-granting
   // authority from raw values) that convention alone couldn't cover
   // without $priv existing first. act4_mode-gated to match every other
   // Veda-Core write block in this file, even though odt_mem[] itself
   // (unlike elfmem) doesn't actually depend on an ELF load -- kept
   // consistent rather than a one-off exception, since every real
   // Veda-Core instruction test in this project already runs under
   // +elf_hex/act4_mode anyway.
   always_ff @(posedge clk) begin
      // RTL-4: CPU_veda_odt_addr_a0 already carries the region base, so this
      // enumeration inherits region addressing with no edit -- which is
      // exactly WHY the change was made in the shared address rather than in
      // a Bind-only copy: a Populate on the old formula and a Bind on the
      // new one would write one slot and read another. Mirrors Sail, whose
      // odt_write also resolves through veda_odt_index. The added
      // idx_ok term mirrors Sail's None() arm being a silent no-op
      // (veda_regs.sail:536-539) -- without it an out-of-range base produces
      // a write the simulator drops with no architectural statement at all.
      if (act4_mode && (CPU_is_veda_odt_populate_a0 || CPU_is_veda_odt_populate_fast_a0) && !CPU_veda_odt_populate_violation_a0 && CPU_veda_odt_idx_ok_a0) begin
         // RTL-17: a NEW object is created open. Destroy, page-out and page-in
         // deliberately do NOT write this field, so policy SURVIVES paging --
         // if eviction cleared it, an object could be un-narrowed simply by
         // paging it out and back. That is the trap owner_hart already learned,
         // and here "preserve" is expressed by the ABSENCE of a write, which no
         // compiler checks. Stated here so the absence is deliberate and
         // documented rather than accidental.
         // RTL-18: and cow is CLEARED. The reset pre-zero is the right default for
         // a fresh table, but Populate may reuse a slot whose previous object
         // was copy-on-write -- without this, the new object would be born
         // copy-on-write and its first write would fault for no reason.
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_COW] <= 8'h00;
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN]   <= VEDA_DOMAIN_ANY[7:0];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN+1] <= VEDA_DOMAIN_ANY[15:8];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN+2] <= {4'b0, VEDA_DOMAIN_ANY[19:16]};
         // Layout, byte-aligned: Base +0..+6, Length +7..+11, Perms
         // +12..+13, generation +14..+16, valid +17, owner_hart +18, retired
         // +19, id_hi +20..+24, resident +25 (RTL-6, ODT_OFF_RESIDENT).
         //
         // RTL-6 CORRECTION: this comment used to say "three hand-written
         // copies". It undercounts, and the undercount is the hazard. There
         // are SIX: (1) the five reset seeds, (2) the Bind-side read, (3)
         // the dereference-side read (partial -- gen/id_hi/valid only), (4)
         // this Populate/Populate-Fast write, (5) the Destroy write below,
         // (6) the owner-claim write in its own always_ff further down.
         // There is no shared macro and no struct. A field added to five of
         // six compiles clean and produces wrong values with no diagnostic.
         // RTL-6's `resident` is the first field to use a named offset
         // constant instead of a literal, for exactly this reason.
         odt_mem[CPU_veda_odt_addr_a0+0] <= CPU_veda_odtpd_new_base_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+1] <= CPU_veda_odtpd_new_base_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+2] <= CPU_veda_odtpd_new_base_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+3] <= CPU_veda_odtpd_new_base_a0[31:24];
         odt_mem[CPU_veda_odt_addr_a0+4] <= CPU_veda_odtpd_new_base_a0[39:32];
         odt_mem[CPU_veda_odt_addr_a0+5] <= CPU_veda_odtpd_new_base_a0[47:40];
         odt_mem[CPU_veda_odt_addr_a0+6] <= CPU_veda_odtpd_new_base_a0[55:48];
         odt_mem[CPU_veda_odt_addr_a0+7] <= CPU_veda_odtpd_new_length_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+8] <= CPU_veda_odtpd_new_length_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+9] <= CPU_veda_odtpd_new_length_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+10] <= CPU_veda_odtpd_new_length_a0[31:24];
         odt_mem[CPU_veda_odt_addr_a0+11] <= CPU_veda_odtpd_new_length_a0[39:32];
         odt_mem[CPU_veda_odt_addr_a0+12] <= CPU_veda_odtpd_new_perms_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+13] <= CPU_veda_odtpd_new_perms_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+14] <= CPU_veda_odtpd_new_gen_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+15] <= CPU_veda_odtpd_new_gen_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+16] <= CPU_veda_odtpd_new_gen_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+17] <= 8'h01;
         // RTL-6: Populate and Populate-Fast BOTH establish residency.
         // Minting an object is what makes its storage present -- there is
         // no path that creates an object whose contents are elsewhere.
         // Missing this line is loud, not silent: every populate-then-bind
         // test in the corpus (43 of them) would trap 0x0A.
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_RESIDENT] <= 8'h01;
         // RTL MILESTONE 15: record the real full Object_ID's upper 15
         // bits in the real Object_ID bytes +20..+24 (this comment said
         // "+11/+12" until RTL-6 -- stale since RTL-3, and +11/+12 are
         // Length[39:24], so anyone trusting it would have corrupted every
         // object's bounds), so a later low-byte-aliasing lookup can be
         // told apart from the object that genuinely owns this slot (the
         // two new checks above).
         odt_mem[CPU_veda_odt_addr_a0+20] <= CPU_veda_object_id_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+21] <= CPU_veda_object_id_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+22] <= CPU_veda_object_id_a0[31:24];
         odt_mem[CPU_veda_odt_addr_a0+23] <= CPU_veda_object_id_a0[39:32];
         odt_mem[CPU_veda_odt_addr_a0+24] <= {4'b0, CPU_veda_object_id_a0[43:40]};
         // RTL MILESTONE 16: commit the retirement bit computed above --
         // once generation would wrap, this slot can never legitimately
         // distinguish a new object from an old one again, so ODT
         // -Populate itself is permanently refused for it from here on
         // ($veda_odt_populate_violation, above).
         odt_mem[CPU_veda_odt_addr_a0+19] <= {7'b0, CPU_veda_odtpd_new_retired_a0};
      // RTL-10 (R13, DESIGN_07 Tier H): DESTROY MAY ONLY TOUCH A SLOT THAT
      // ACTUALLY HOLDS THE NAMED OBJECT.
      //
      // Milestone 15 fixed low-byte aliasing by storing the full Object_ID
      // in the slot and requiring it to match -- but it applied that to the
      // two READ paths only ($veda_odt_valid, $veda_check_odt_valid). Destroy
      // is an access too, and without the same tag it clears a DIFFERENT,
      // LIVE object: `veda.odt.destroy 436` lands on slot 180 (436's low byte
      // is 180) and wipes object 180's descriptor.
      //
      // Sail cannot express that bug -- it indexes with the FULL 24-bit local
      // (VEDA_LOCAL_MODELED = 2^20), so 436 and 180 are genuinely different
      // entries and destroying one leaves the other alone. Gating on the tag
      // is what makes this file agree: if the slot's tag is not ours, the
      // object we named is not in the table, and Destroy has nothing here to
      // do.
      //
      // Gated on id_match and NOT on $veda_odt_valid, deliberately: Sail's
      // Destroy bumps the generation of an already-invalid entry too, and
      // that must keep working. Only the IDENTITY is in question here, not
      // the liveness.
      //
      // Populate keeps its slot TAKEOVER -- that is Milestone 15's own
      // deliberate semantics for a 256-slot model, and the displaced object
      // then reads not-found rather than reading someone else's data. Taking
      // a free-able slot is reuse; clearing a slot you do not own is not.
      // RTL-17: veda.odt.set.domain writes owner_domain AND NOTHING ELSE.
      // The generation is deliberately NOT bumped -- that is the whole reason
      // this instruction exists. Every other ODT writer bumps it and kills
      // every outstanding capability, which would mean declaring a sharing
      // rule destroys the sharing it describes.
      //
      // Gated on id_match for the same reason Destroy is (RTL-10): this core
      // indexes by slot, so without the tag a policy meant for one object
      // would land on whichever object actually occupies that slot.
      // RTL-18: set.cow writes ONE BIT and nothing else -- above all it does not
      // bump the generation. id_match gated for the same reason set.domain and
      // Destroy are: this core indexes by slot, so without the tag a policy
      // meant for one object lands on whichever object occupies that slot.
      end else if (act4_mode && CPU_is_veda_odt_set_cow_a0 && !CPU_veda_odt_set_cow_violation_a0 && CPU_veda_odt_idx_ok_a0 && CPU_veda_odt_id_match_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_COW] <= {7'b0, CPU_rs2_data_a0[0]};
      end else if (act4_mode && CPU_is_veda_odt_set_domain_a0 && !CPU_veda_odt_set_domain_violation_a0 && CPU_veda_odt_idx_ok_a0 && CPU_veda_odt_id_match_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN]   <= CPU_rs2_data_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN+1] <= CPU_rs2_data_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_OWNER_DOMAIN+2] <= {4'b0, CPU_rs2_data_a0[19:16]};
      end else if (act4_mode && CPU_is_veda_odt_destroy_a0 && !CPU_veda_odt_destroy_violation_a0 && CPU_veda_odt_idx_ok_a0 && CPU_veda_odt_id_match_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+14] <= CPU_veda_odtpd_new_gen_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+15] <= CPU_veda_odtpd_new_gen_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+16] <= CPU_veda_odtpd_new_gen_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+17] <= 8'h00;
         odt_mem[CPU_veda_odt_addr_a0+19] <= {7'b0, CPU_veda_odtpd_new_retired_a0};
         // RTL-6: Destroy clears residency too. This write is invisible to
         // the entire existing 64-test corpus -- Destroy also clears valid,
         // and the Bind gate is `valid && !resident`, so a dead slot can
         // never reach the residency check no matter what this byte holds.
         // It is here anyway, and Sail carries it for the same reason: no
         // path may ever read a stale resident=true off a destroyed slot.
         // "Currently unreachable" is a statement about today's checkers,
         // not about the field's meaning, and RTL-6c adds a second reader.
         // Named as a deliberate belt-and-braces write rather than left to
         // look like a line whose absence nobody noticed.
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_RESIDENT] <= 8'h00;
      // ────────────────────────────────────────────────────────────────
      //  RTL-6c: the paging pair's writes, added as further arms of THIS
      //  chain rather than a new always_ff. That placement is required,
      //  not stylistic: page-out writes +14..+16 and +25, the same bytes
      //  the Destroy arm writes, and page-in writes +0..+6 and +25,
      //  overlapping the Populate arm. Two always_ff blocks driving the
      //  same odt_mem byte in one cycle is a race SystemVerilog will not
      //  diagnose. The if/else-if chain gives mutual exclusion for free.
      //  (The owner-claim write lives in its own block ONLY because +18 is
      //  touched by nothing else.)
      end else if (act4_mode && CPU_is_veda_odt_page_out_a0 && !CPU_veda_odt_page_out_refusal_a0 && CPU_veda_odt_idx_ok_a0) begin
         // PAGE-OUT writes exactly TWO fields. valid stays 1 -- the object
         // still EXISTS, which is the whole distinction RESIDENCY_FAULT
         // exists to express versus OBJECT_NOT_FOUND. Base is left stale
         // and is unreachable: RTL-6a's bind gate traps before any mode can
         // mint from it, and RTL-6b's dereference term catches any
         // capability that already had.
         odt_mem[CPU_veda_odt_addr_a0+14] <= CPU_veda_pageout_new_gen_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+15] <= CPU_veda_pageout_new_gen_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+16] <= CPU_veda_pageout_new_gen_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_RESIDENT] <= 8'h00;
      end else if (act4_mode && CPU_is_veda_odt_page_in_a0 && !CPU_veda_odt_page_in_refusal_a0 && CPU_veda_odt_idx_ok_a0) begin
         // PAGE-IN writes exactly TWO fields: the new Base and resident.
         //
         // WHAT IS ABSENT HERE IS THE SPECIFICATION. generation (+14..+16),
         // owner_hart (+18), Length (+7..+11), Perms (+12..+13) and retired
         // (+19) must all carry over, and they do so by NOT being written.
         // That is a negative specification with no compiler check, and it
         // is the single strongest reason `resident` was kept byte-aligned
         // rather than packed into a shared flags byte: as eight
         // enumerated lines this arm can be audited by eye, whereas a
         // read-modify-write of a shared byte would hide a preservation bug
         // completely.
         //
         // Preserving generation is the entire reason page-in exists as a
         // separate instruction: Populate bumps whenever the old entry was
         // valid, and a paged-out object IS valid, so using Populate here
         // would invalidate every capability on every page-in and make
         // demand paging useless. Preserving owner_hart is a multi-hart
         // property provable only in the negative today -- page-out is
         // gated on authority, not ownership, so a pager may evict an
         // object it does not own; if page-in reset owner_hart, any hart
         // could then claim it. Object theft by triggering a page fault.
         //
         // Base takes the WIDE form. Populate-Fast's $rs2_data[55:0], not
         // plain Populate's packed {24'b0, $rs2_data[63:32]} -- Sail reads
         // base_gpr64[55..0]. Copying the compact form compiles clean and
         // stores the wrong half of the register, with +4..+6 zeroed.
         odt_mem[CPU_veda_odt_addr_a0+0] <= CPU_rs2_data_a0[7:0];
         odt_mem[CPU_veda_odt_addr_a0+1] <= CPU_rs2_data_a0[15:8];
         odt_mem[CPU_veda_odt_addr_a0+2] <= CPU_rs2_data_a0[23:16];
         odt_mem[CPU_veda_odt_addr_a0+3] <= CPU_rs2_data_a0[31:24];
         odt_mem[CPU_veda_odt_addr_a0+4] <= CPU_rs2_data_a0[39:32];
         odt_mem[CPU_veda_odt_addr_a0+5] <= CPU_rs2_data_a0[47:40];
         odt_mem[CPU_veda_odt_addr_a0+6] <= CPU_rs2_data_a0[55:48];
         odt_mem[CPU_veda_odt_addr_a0+ODT_OFF_RESIDENT] <= 8'h01;
      end
   end

   // VEDA-CORE RTL MILESTONE 12: owner-hart claim/re-claim write-back --
   // the real, first-time consumer of odt_mem[]'s own byte offset +18
   // (this said "+10" until RTL-6; stale since RTL-3's relayout).
   //
   // RTL-6 NOTE, because the absence of a line is not self-documenting.
   // Sail's Bind rebuilds the whole entry and therefore needs an explicit
   // `resident = e.resident` to carry residency across a claim. This block
   // writes exactly ONE byte, so residency carries over by construction
   // and NO corresponding line belongs here. Adding one would be the bug:
   // writing 8'h01 would make any Bind mark any object resident, which is
   // the precise defeat of the gate that Bind is supposed to be subject
   // to. The failure mode for this field is a write that should not exist,
   // not a missing one -- the inverse of every other site in this mirror.
   // Fires on every successful Bind/Bind-NoTrap/Rebind (gated by
   // CPU_veda_owner_claim_en_a0, already mutually exclusive from plain
   // Bind's own hard-trap path by construction -- see the TLV-side
   // comment above), claiming the ODT slot for MHARTID regardless of
   // whether it was already unowned or already owned by this same hart
   // -- mirrors veda_bind_insts.sail's own unconditional `claimed_entry`
   // write on every success path, not just first-time claims.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_veda_owner_claim_en_a0) begin
         odt_mem[CPU_veda_odt_addr_a0+18] <= MHARTID;
      end
   end

   // VEDA-CORE RTL MILESTONE 7: OCS.C's own real store -- 16 bytes of
   // packed capability data into elfmem[] (the identical little-endian
   // byte-write shape OCS.D already uses, doubled in width) PLUS the
   // real, out-of-band Tag into tag_mem[] at the same granule OCL.C's
   // own read side indexes (CPU_veda_capmem_granule_a0). Gated on
   // !CPU_veda_ocsc_violation_a0 -- the identical violation-suppresses-
   // write convention as every other Veda-Core store in this file. An
   // untagged source capability (CPU_veda_ocsc_store_tag_a0 = 0) still
   // stores its real field bits -- matching real CHERI's own behavior
   // (storing an invalid capability is legal; it just cannot be loaded
   // back as valid) -- the tag_mem[] write below correctly records
   // "not a real capability" for those bytes either way, not skipped.
   // MILESTONE 24 Stage 3: the same real address-range decision
   // (CPU_veda_capmem_tcm_hit_a0) selects tcm_scratch[]/tcm_scratch_tag[]
   // (real, separate arrays) instead of elfmem[]/tag_mem[] -- array AND
   // granule index switch together, the same paired discipline the read
   // side above already applies, closing the same aliasing/overflow risk
   // on the write side too.
   always_ff @(posedge clk) begin
      if (act4_mode && CPU_is_veda_ocs_c_a0 && !CPU_veda_ocsc_violation_a0 && CPU_veda_capmem_tcm_hit_a0) begin
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+0] <= CPU_veda_ocsc_packed_a0[7:0];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+1] <= CPU_veda_ocsc_packed_a0[15:8];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+2] <= CPU_veda_ocsc_packed_a0[23:16];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+3] <= CPU_veda_ocsc_packed_a0[31:24];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+4] <= CPU_veda_ocsc_packed_a0[39:32];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+5] <= CPU_veda_ocsc_packed_a0[47:40];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+6] <= CPU_veda_ocsc_packed_a0[55:48];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+7] <= CPU_veda_ocsc_packed_a0[63:56];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+8] <= CPU_veda_ocsc_packed_a0[71:64];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+9] <= CPU_veda_ocsc_packed_a0[79:72];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+10] <= CPU_veda_ocsc_packed_a0[87:80];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+11] <= CPU_veda_ocsc_packed_a0[95:88];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+12] <= CPU_veda_ocsc_packed_a0[103:96];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+13] <= CPU_veda_ocsc_packed_a0[111:104];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+14] <= CPU_veda_ocsc_packed_a0[119:112];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+15] <= CPU_veda_ocsc_packed_a0[127:120];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+16] <= CPU_veda_ocsc_packed_a0[135:128];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+17] <= CPU_veda_ocsc_packed_a0[143:136];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+18] <= CPU_veda_ocsc_packed_a0[151:144];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+19] <= CPU_veda_ocsc_packed_a0[159:152];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+20] <= CPU_veda_ocsc_packed_a0[167:160];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+21] <= CPU_veda_ocsc_packed_a0[175:168];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+22] <= CPU_veda_ocsc_packed_a0[183:176];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+23] <= CPU_veda_ocsc_packed_a0[191:184];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+24] <= CPU_veda_ocsc_packed_a0[199:192];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+25] <= CPU_veda_ocsc_packed_a0[207:200];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+26] <= CPU_veda_ocsc_packed_a0[215:208];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+27] <= CPU_veda_ocsc_packed_a0[223:216];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+28] <= CPU_veda_ocsc_packed_a0[231:224];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+29] <= CPU_veda_ocsc_packed_a0[239:232];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+30] <= CPU_veda_ocsc_packed_a0[247:240];
         tcm_scratch[CPU_veda_real_addr_a0[31:0]+31] <= CPU_veda_ocsc_packed_a0[255:248];
         tcm_scratch_tag[CPU_veda_capmem_tcm_granule_a0] <= CPU_veda_ocsc_store_tag_a0;
      end else if (act4_mode && CPU_is_veda_ocs_c_a0 && !CPU_veda_ocsc_violation_a0) begin
         elfmem[CPU_veda_real_addr_a0[31:0]+0] <= CPU_veda_ocsc_packed_a0[7:0];
         elfmem[CPU_veda_real_addr_a0[31:0]+1] <= CPU_veda_ocsc_packed_a0[15:8];
         elfmem[CPU_veda_real_addr_a0[31:0]+2] <= CPU_veda_ocsc_packed_a0[23:16];
         elfmem[CPU_veda_real_addr_a0[31:0]+3] <= CPU_veda_ocsc_packed_a0[31:24];
         elfmem[CPU_veda_real_addr_a0[31:0]+4] <= CPU_veda_ocsc_packed_a0[39:32];
         elfmem[CPU_veda_real_addr_a0[31:0]+5] <= CPU_veda_ocsc_packed_a0[47:40];
         elfmem[CPU_veda_real_addr_a0[31:0]+6] <= CPU_veda_ocsc_packed_a0[55:48];
         elfmem[CPU_veda_real_addr_a0[31:0]+7] <= CPU_veda_ocsc_packed_a0[63:56];
         elfmem[CPU_veda_real_addr_a0[31:0]+8] <= CPU_veda_ocsc_packed_a0[71:64];
         elfmem[CPU_veda_real_addr_a0[31:0]+9] <= CPU_veda_ocsc_packed_a0[79:72];
         elfmem[CPU_veda_real_addr_a0[31:0]+10] <= CPU_veda_ocsc_packed_a0[87:80];
         elfmem[CPU_veda_real_addr_a0[31:0]+11] <= CPU_veda_ocsc_packed_a0[95:88];
         elfmem[CPU_veda_real_addr_a0[31:0]+12] <= CPU_veda_ocsc_packed_a0[103:96];
         elfmem[CPU_veda_real_addr_a0[31:0]+13] <= CPU_veda_ocsc_packed_a0[111:104];
         elfmem[CPU_veda_real_addr_a0[31:0]+14] <= CPU_veda_ocsc_packed_a0[119:112];
         elfmem[CPU_veda_real_addr_a0[31:0]+15] <= CPU_veda_ocsc_packed_a0[127:120];
         elfmem[CPU_veda_real_addr_a0[31:0]+16] <= CPU_veda_ocsc_packed_a0[135:128];
         elfmem[CPU_veda_real_addr_a0[31:0]+17] <= CPU_veda_ocsc_packed_a0[143:136];
         elfmem[CPU_veda_real_addr_a0[31:0]+18] <= CPU_veda_ocsc_packed_a0[151:144];
         elfmem[CPU_veda_real_addr_a0[31:0]+19] <= CPU_veda_ocsc_packed_a0[159:152];
         elfmem[CPU_veda_real_addr_a0[31:0]+20] <= CPU_veda_ocsc_packed_a0[167:160];
         elfmem[CPU_veda_real_addr_a0[31:0]+21] <= CPU_veda_ocsc_packed_a0[175:168];
         elfmem[CPU_veda_real_addr_a0[31:0]+22] <= CPU_veda_ocsc_packed_a0[183:176];
         elfmem[CPU_veda_real_addr_a0[31:0]+23] <= CPU_veda_ocsc_packed_a0[191:184];
         elfmem[CPU_veda_real_addr_a0[31:0]+24] <= CPU_veda_ocsc_packed_a0[199:192];
         elfmem[CPU_veda_real_addr_a0[31:0]+25] <= CPU_veda_ocsc_packed_a0[207:200];
         elfmem[CPU_veda_real_addr_a0[31:0]+26] <= CPU_veda_ocsc_packed_a0[215:208];
         elfmem[CPU_veda_real_addr_a0[31:0]+27] <= CPU_veda_ocsc_packed_a0[223:216];
         elfmem[CPU_veda_real_addr_a0[31:0]+28] <= CPU_veda_ocsc_packed_a0[231:224];
         elfmem[CPU_veda_real_addr_a0[31:0]+29] <= CPU_veda_ocsc_packed_a0[239:232];
         elfmem[CPU_veda_real_addr_a0[31:0]+30] <= CPU_veda_ocsc_packed_a0[247:240];
         elfmem[CPU_veda_real_addr_a0[31:0]+31] <= CPU_veda_ocsc_packed_a0[255:248];
         tag_mem[CPU_veda_capmem_granule_a0] <= CPU_veda_ocsc_store_tag_a0;
      end
   end
   endmodule

# Wildbits Level-2 vtio / grfdrv256 rewrite

Branch `wb/multiterm`. Rewrite of `level2/wildbits/modules/vtio.asm` +
`level2/wildbits/cmds/grfdrv256.asm` (built into `grfdrv256`).

## STATUS  (2026-09-08)  — **RESOLVED.**  Boots the full `sysgo` → `Shell
## "startup -p"` → nested-fork chain to an interactive prompt.  The cause was
## **not** in vtio or grfdrv256.

Commit `f98f5575`.  Verified in MAME `wbjr2`, deterministic, with the
temporary `sysgo.as` fork-skip hack removed:

```
08: NitrOS-9/6809 Level 2-DEV
09: Wildbits Jr2 - 2026-09-08 (a5cd3388 - wb/multiterm)
10: Wildbits/Jr2 - PCBID B0 - TinyVicky 000200080000 - RAM - Turbo   <- wbinfo, from startup
12: Shell+ v2.2a 26/09/08 10:02:08
14: {term|02}/dd:
Active LUT 0 Blocks: [00, 3E, 03, 02, 04, 05, 06, 07]
```

Line 10 is `wbinfo` output from the `startup` script, so `load utilpak1` and
`link shell` both ran — the whole nested fork chain works.

### The actual bug: a module linked into MMU slot 7 above block offset `$1D00`

The F256 core keeps **three pages fixed at the top of every map**:

| range | contents |
|---|---|
| `$FD00-$FDFF` | constant page (`MMU_IO_CTRL` bit 0) — holds the kernel's copied-down switch code |
| `$FE00-$FEFF` | SYS0/SYS1, INTC, RTC |
| `$FF00-$FFFF` | I/O + CPU vectors |

Those overlays shadow **block offsets `$1D00-$1FFF` of whatever sits in MMU
slot 7** — a 768-byte dead zone.  (The CoCo3 has the same hazard but only
`$100` of it, at `$FF00`.)  MAME's map states it explicitly: the `$FD00`
handler only falls through to
`get_physical_block_ptr(m_mlut[act][7])[0x1d00 + offset]` when the constant
page is *disabled*, and L2 needs it enabled.

`CMDS/shell` is a **merged file** — `Shell, Date, DeIniz, Echo, Iniz, Link,
Load, Save, Unlink` — all sharing one allocation and one module-directory
`MD$MPDAT`/`MD$MBSiz`.  `recipes/wildbits/wildbits.mak:71` had gained `date`
and `deiniz` relative to the prior tree, growing the file by exactly
`$F1 + $53 = $144` bytes and pushing four modules over the line:

```
   prior tree                 current tree
 Shell  $0000 ok            Shell  $0000 ok     Date   $1B57 ok
 Echo   $1B57 ok            DeIniz $1C48 ok     Echo   $1C9B ok
 Iniz   $1B79 ok            Iniz   $1CBD ok
 Link   $1BC0 ok            Link   $1D04  *** DEAD
 Load   $1BEC ok            Load   $1D30  *** DEAD
 Save   $1C10 ok            Save   $1D54  *** DEAD
 Unlink $1C77 ok            Unlink $1DBB  *** DEAD
```

`F$Link`/`F$SLink` place a module's blocks top-down, so that block went into
slot 7 and `flink.asm:FLinkTarget3` → `CmpLBlk` (`fdatlog.asm`) computed
`MD$MPtr + slot*8192` = `$1D30 + 7*8192` = **`$FD30`**, entry
`$FD30 + M$Exec($12)` = **`$FD42`**.  That is not the module at all — it is
the constant page's copy of `KrnActualMMUBlock`.  The forked child's first
`rti` executed it and detonated.

**This is the long-sought explanation for "resumes mid-`KrnBank` at
`$FD42`"** which appears throughout the older sections below.  It was never a
stale or corrupt stack frame; it was the module entry point resolving onto
the constant page.  It also explains every "load-bearing non-determinism"
report in this document: any size change moves modules across the `$1D00`
line, and a warm-RAM reboot can land the block in a different slot.

### The fix (two parts — the second is easy to miss)

**1. `level1/modules/kernel/flink.asm`** — upstream commit
[`0cb427a2`](https://github.com/nitros9project/nitros9/commit/0cb427a24e8f9157bf42370439222490a6256a52)
("Wildbits 3-page slot 7 protection for FLink", Roger Taylor).  An
`IFNE wildbits` leg replaces the CoCo3 shift chain with
`ldb #8 / mul / cmpb #$E8 / tfr a,b / bcs / inca`, allowing `$300` (three
pages) instead of the CoCo3's `$200` when computing the start-slot count `A`.
A module whose allocation is used past block offset `$1D00` then starts the
top-down search one slot lower and never lands in slot 7.  `B`, the run
length the search must find, is unchanged.

**2. `level2/modules/kernel/krn.asm`** — the MUL form is **3 bytes shorter**
than the chain it replaces (10 vs 13; the upstream comment says "10 against
14" and miscounts the old one), and the upstream commit does **not**
compensate the wildbits filler.

`Krn` must be **exactly `$1000` bytes**.  The bootfile is padded to end at
`$FE00`, `Krn` is its last module, and `bootos9.as` looks for it at exactly
`$EE00` (*"Level 2: Krn is last module and located at $EE00"*).  Three bytes
short put `Krn` at `$EE03` and the boot died in an infinite retry loop with
**"Can't locate the kernel in the bootfile."** — a failure with no visible
connection to FLink.  Fix: `fcc /www/` added to the `IFNE wildbits` leg of
the `* FILL - all unused bytes are now here` block (~line 82).

> **Invariant: any change to wildbits-conditional code in `Krn` must be
> compensated in that FILL block.**  Check `stat -c%s
> recipes/wildbits/l2/.mods/krn` == 4096 after every build.

### Two build traps

- **The makefile does not list `flink.asm` as a dependency of `krn`.**
  Editing it does not trigger a rebuild, and the first "fixed" run silently
  used the stale kernel.  Before testing a kernel-source change:
  `rm -f recipes/wildbits/l2/{.mods/krn,krn.list,bootfile}`.
- **Confirm the wildbits leg actually assembled.**
  `grep 'hi \* 8' recipes/wildbits/l2/krn.list` should show `C608 3D C1E8`.
  If you see `inca ; instead of adda #2` at that spot, you built the CoCo3
  leg.

### Verification that the guard bumps only when needed

```
Shell   MBSiz=$1DE2  -> P$PModul=$C000  R$PC=$C074   DATImg=... 000B 333E  (slot 6)
Load    MPtr=$1D30   -> P$PModul=$DD30  R$PC=$DD42
Link    MPtr=$1D04   -> P$PModul=$DD04  R$PC=$DD16
wbinfo  MBSiz=$0188  -> P$PModul=$E000  R$PC=$E013   DATImg=... 333E 000E  (slot 7)
```

`wbinfo` proves it is not blanket-avoiding slot 7 — small modules still use
it, unchanged.

### Method: non-perturbing tracing via MAME instrumentation

The `-debug` unreliability documented further down is real, and it blocked
this investigation for two sessions.  The way through was to **instrument the
MAME driver instead of attaching the debugger** — no per-instruction
breakpoint checks, so emulated timing is untouched and the failure stays
deterministic.  The code is still in
`mame/src/mame/wildbits/wildbits_jr2.cpp`, disabled behind
`// #define WB_TRACE_MMU 1` (~line 524).  Uncomment and
`make SOURCES=src/mame/wildbits/wildbits_jr2.cpp` (~1 min) to get:

- **`mmu_slot_w` hook** — every write to the kernel's slot-5/6 temp map
  window (`DAT.Regs+5`, used by `F$Move` and `KrnBlockNumberWhere`),
  excluding `KrnBank`'s sequential 0..7 sweep; flags any write where
  `EDIT_LUT != ACT_LUT`.
- **`F$Move` decoder** — at `$FA38` (the instruction after
  `sty >DAT.Regs+5`) the whole `F$Move` frame is on the 6809 stack, so
  source/dest block+offset, the DAT image pointers and the byte count can be
  read out.  Filtered to `R$Size` (12-byte) moves, which is `F$Fork`'s child
  register-stack write.  It also dumps the child descriptor and the module
  directory (`D.ModDir` = DP `$44`, `D.ModEnd` = DP `$58`, 8-byte entries:
  `MD$MPDAT MD$MBSiz MD$MPtr MD$Link`), resolving each module's name straight
  out of physical RAM via `get_physical_block_ptr`.
- **`mmu_mem_ctrl_w` hook** — a ring of the last 64 `ACT_LUT` switches with
  PC, `D.Proc`, the new LUT contents, `Y` (= `P$SP`), and the 12 bytes the
  imminent `rti` will pop.  This is what showed proc 5 entering with
  `frame@Y=80 00 09 00 1E F7 1F 00 00 00 FD 42 -> PC=$FD42`.

Reading physical memory directly through `get_physical_block_ptr()` avoids
the MMU entirely and cannot perturb anything.  Do **not** read `$FFA8-$FFAF`
from a hook — that goes through `mmu_slot_r`/`io_wait()` and eats CPU cycles.
Also note hook ordering: read memory *after* `m_mlut[...] = data`, or the
mapping you are trying to observe is not live yet (this cost one cycle).

### What this retracts from the sections below

Everything below this line is preserved as the investigation record, but the
following conclusions are **wrong** and should not be acted on:

1. **"`gr.DATImg` format mismatch"** (2026-09-07 ROOT CAUSE section) — already
   retracted at the time.  6809 `,u++` on a word op double-increments, so
   `KrnActualMMUBlock`'s byte-pair reads do match `SetBlkC2C3`'s word writes.
2. **"`F$Fork` builds a bad child stack frame"** — false.  Traced directly:
   `F$Move` copies proc 5's frame from `$6E00 + P$Stack - R$Size` to physical
   block `$0C` offset `$1EEB`, which is exactly its `P$DATImg` slot 0 and its
   `P$SP`.  The write is correct; the *contents* were already wrong.
3. **"EDIT_LUT stuck at 1 / the dead `clr MMU_MEM_CTRL` in
   `KrnActualMMUBlock`"** — measured over a full boot:
   `misdirected(edit!=act)=0`.  `EDIT_LUT` is always 0 when the slot-5/6
   window is used.  (The dead `clr` on the 6809 leg is real but inert; the
   following `sta >DAT.Task` rewrites the register from `D.TINIT`, which only
   ever holds 0 or 1.)
4. **"the crash is a regression from the vtio reorg (`6e29509e`)"** — false.
   It is a `SHELLMODS` merge-list change exposing a latent address-space bug.
   The prior tree boots because its merged `shell` file lacks `date` and
   `deiniz`, so nothing lands past `$1D00`.
5. **`KrnRsvSlot2` / the `01013877` bundle** — not related.  It appeared to
   "move" the crash only because it changed allocation and therefore module
   placement.
6. **"path number management with `/term`"** (2026-09-07 open lead) — a dead
   end, unrelated.

### Two real vtio bugs found while chasing this (fixed; neither was the cause)

- **`CallGrfDrv2` did not preserve `U` across the grfdrv flip.**  The return
  path `SysRet` → `D.Flip0` → `R.Flip0` restores only `S` (from `gr.Stack`)
  and `CC` (from `A`) — `D/X/Y/U/DP` come back holding whatever grfdrv left.
  The prior tree funnelled every call through `CallWrite`, which did
  `pshs u` / `puls u` and carried the comment *"Flip0 leaves U as the LUT-1
  VSta alias ($6000 -> $A000)"*; the reorg deleted that funnel and did not
  carry the save to the new call sites.  Meanwhile the new `SetBlkC2C3` ends
  with `ldu >gr.U5` (prior's never touched `U`), `GFClrScrn` leaves `U` past
  the end of its fill, and `ScrollLive`/`ScrollShadow` leave it from
  `leau`/`CpyBlk`.  Callers with no `pshs u`: `PutCell` (prior `BufCell` had
  `pshs d,x,u`), `ClrScrn`→`CurHome`, `EraseLine`/`ErEOLine`/`ErEOScrn`,
  `ChgPal`, `BlankTermText`, and `PutGlyph`'s scroll.  Their next `V.xxx,u`
  access landed in the **system** map.  Fixed at the funnel so no new call
  site can forget it:

  ```
  CallGrfDrv2         pshs      u
                      bsr       CallGrfDrvGo
                      puls      u,pc
  CallGrfDrvGo        orcc      #Entire
                      ...unchanged body...
  ```

  The `bsr` is load-bearing: `R.Flip0` returns via `rts` off `gr.Stack`, so a
  bare `pshs u` at the top would make it `rts` into `U`.  Routing through
  `CallGrfDrvGo` provides a real code point after the flip.
- **`CurHome` did `clr V.CurPos,u`** on a 2-byte field — same class as the
  earlier `inc V.CurPos` bug; only the high byte was cleared, so "home" left
  the low byte behind.  Now clears both.

## Console usability  (2026-09-08, same day)  — **cursor + scrolling FIXED**

With the boot chain working, the console itself still was not: the screen
never scrolled at the bottom, and the hardware cursor lagged the text.  Two
separate regressions from the vtio reorg, both verified fixed in MAME.

### 1. `V.ScreenSize` was never written — the screen could not scroll

`V.ScreenSize` (`defs/wildbits_vtio.d:36`) was declared and **read exactly
once** — `ldy V.ScreenSize,u` in `vtio.asm`'s scroll block, just before
`CallScrollLive`/`CallScrollShadow`.  Nothing in the tree ever stored to it,
so it was always `0`.

In `grfdrv256.asm` `ScrollLive`/`ScrollShadow` the byte count is computed as
`V.ScreenSize - V.WWidth`, i.e. `0 - 80` = `$FFB0`.  `CpyBlk` opens with
`leax d,u` to form the source-end address; with a count that large it wraps
to *below* the source start, the very first `cmpu ,s / blo CpyLp` fails, and
**zero bytes are copied**.  `Y` is therefore still `#$2000` (`#$6000` for
shadow) when the "blank the exposed last row" loop runs, so that loop wiped
**row 0**.  Net symptom, exactly as reported: no scroll, top line blanks,
bottom line churns.

The prior tree does not have this bug because it never used
`V.ScreenSize` — it computed `gr.WCount = WWidth*(WHeight-1)` inline and
passed that.  The rewrite moved the arithmetic into grfdrv and read a field
nobody initialises.

Fix: new `SetScreenSize` helper next to `CalcCurPos` (`V.ScreenSize =
V.WWidth * V.WHeight`, preserves D), called at all three writes to
`V.WWidth`/`V.WHeight` — `InitDisplay`, `InitTermStatic` (both the 80x60
default *and* the "match the live console" copy), and `SetWin` (the shared
`DWSet` tail).

> **Invariant: any new write to `V.WWidth`/`V.WHeight` must be followed by
> `lbsr SetScreenSize`.**  A stale value here does not fail loudly; it just
> silently stops scrolling.

The `WWidth * WHeight` stride assumption is right: MAME's renderer indexes
`cell_idx = row * cols + col` with `cols = dbl_x ? 40 : 80`
(`wildbits_jr2.cpp:2293`), matching `CalcCurPos` and `EraseLineCore`.

### 2. `ChkESC` dispatched with `jmp d,x` — the hardware cursor never moved

`ChkESC`'s `DCodeTbl` dispatch was `jmp d,x`, so every single-byte control
code handler `rts`'d **straight back to SCF**, never reaching
`UpdateLiveCursor`.  `CurHome $01`, `EraseLine $03`, `ErEOLine $04`,
`CurRght $06`, `CurLeft $08`, `CurUp $09`, `ErEOScrn $0B`, `ClrScrn $0C` and
`Retrn $0D` all moved `V.CurRow`/`V.CurCol` without ever writing
`VKY_TXT_CURSOR_X/Y_REG_L`.  Only `CurDown $0A`, the `PutGlyph` path and
`EscCodeComplete` updated it — which is why the cursor looked right at a
fresh prompt (the last thing written is a glyph) but drifted the moment you
pressed Backspace.

The prior tree's `Write` was `ldx V.EscVect,u / jsr ,x` and then fell into
the cursor update, so every code got it for free.  Fix: `jsr d,x / clrb /
lbra UpdateLiveCursor`.  Because `UpdateLiveCursor` ends `andcc #^Carry /
rts`, this also scrubs the dirty carry `CurRght`'s `bye@` path used to hand
back to SCF (`cmpa` leaves `C` set), which SCF would have read as an error.
`CurDown`'s now-redundant `lbra UpdateLiveCursor` became `lbra CalcCurPos`.

### Smaller fixes made alongside

- **`CurRght` off-by-one.**  `cmpb V.WWidth,u / bgt nextrow@` let column
  `WWidth` be stored: at column 79 of an 80-wide window `incb` gives 80,
  `bgt` is not taken, and `V.CurCol` became 80 — one cell off the end.  Now
  `bhs`; the row test `bge bye@` is likewise `bhs`.  (The prior tree has the
  same `bgt`; it is not a reorg regression.)
- **`$0A` at the bottom row now keeps its column.**  `CurDown` shares the
  scroll block via `incrow`, which did `clrb` before `pshs d` and so forced
  column 0 — inconsistent with its own mid-screen `CDmv@`.  That `clrb` is
  deleted: `B` is already correct at both entries (`PutGlyph`'s line wrap
  clears it itself; `CurDown` enters with `B = V.CurCol`).
- **`CalcCurPos` re-clamps `V.CurRow` to `V.WHeight-1`** (and handles
  `WHeight = 0`).  The prior tree's `RawWrite` clamped on every character to
  guard "DWSet 80x60 then 80x30 leaves CurRow at 50"; the rewrite dropped
  it.  Doing it in `CalcCurPos` covers every handler, since they all route
  through it.  `EraseChar` now uses `CalcCurPos`'s result instead of
  carrying its own copy of the `row*width+col` arithmetic.
- **`V.CurPos` resync gaps closed.**  `V.CurPos` is a cache of
  `CurRow*WWidth + CurCol` that `PutGlyph` paints at directly.  `Init` and
  `InitTermStatic` cleared row/col but left it stale, and `SwitchTerm`
  clamped `V.CurRow` without recomputing it.  All three fixed — the
  `SwitchTerm` one matters for multiterm.

### Verification

`dir -e /dd/CMDS` appended to `startup` (~100 lines) scrolls correctly: the
60-row VRAM snapshot shows the tail of the listing followed by the Shell+
prompt, with no blanked row 0.  Cursor: `display 0C 41 42 43 08 08` +
`sleep 3000` leaves `A` alone on row 0 and `HW CURSOR: x=1 y=0` — the two
backspaces moved the hardware cursor.  Before the fix it stayed at `x=3`.
Regression: the full `sysgo` → `Shell "startup -p"` → nested-fork chain
still reaches an interactive prompt with the `wbinfo` line present, and
`Krn` is still exactly 4096.

`mame/src/mame/wildbits/wildbits_jr2.cpp`'s `device_stop()` exit dump was
extended from 25 to all 60 text rows and now also prints
`HW CURSOR: x=.. y=.. ctrl=$..`.  Both are what make these two bugs
diagnosable without attaching `-debug`.

### grfdrv parameter registers renamed to `gr.b1-b5` / `gr.d1-d2`

vtio reaches grfdrv through a register-bank flip (`CallGrfDrv2` →
`jmp [D.Flip1]`) and so cannot pass arguments in CPU registers — it snapshots
them into a block of globals in GrfMem first. Those globals were named after
the *first* use of each slot and had drifted into being actively wrong:
`gr.WColor` carried a PSG **volume** and a bitmap **control byte**; `gr.WOff`
("cell offset 0..4799") carried a PSG **frequency**, a bitmap **physical
address**, and text-LUT bytes 0-1; `gr.WWidth` was a **0=FG / 1=BG selector**;
`gr.WOp` was dead.

They are now a numbered register file — `bN` = 1 byte, `dN` = 2 bytes
("double") — so no name can claim the wrong thing:

| old | new | | old | new |
|---|---|---|---|---|
| `gr.WOp`    | `gr.b1` (unassigned) | | `gr.WOff`   | `gr.d1` |
| `gr.WGlyph` | `gr.b2` | | `gr.WCount` | `gr.d2` |
| `gr.WColor` | `gr.b3` | | | |
| `gr.WDest`  | `gr.b4` | | | |
| `gr.WWidth` | `gr.b5` | | | |

The meaning moved to an ABI table in `defs/wildbits_vtio.d` above the
declarations (which op uses which register for what), a parameter block in
every grfdrv handler header, and a trailing comment at all 81 store/load
sites. **Read the `.d` table before adding a `GF.*` op.** Two things it
records that are easy to trip over:

- **`GF.ClrScrn` and the erase family clobber `b3`.** They take no parameters
  there, but both spill `V.FBCol` into it because `U` gets reused as the
  colour-plane pointer. Nothing may hold a live `b3` across those calls.
- **The direct-call entries bypass the block entirely.**
  `WriteCharLive`/`Shadow` and `ScrollLive`/`Shadow` take everything in
  `A`/`B`/`Y`.

Declarations kept their physical order (`b1 b2 d1 d2 b3 b4 b5`) so GrfMem
offsets did not move — the interleave is historical, not meaningful.

The one code change alongside the rename: the dead `sta >gr.WWidth` in vtio's
scroll block is deleted. `ScrollLive`/`ScrollShadow` take the width in `A` and
never read it; it was left over from the removed `GF.Write WO.Scroll` op, and
under generic names it would have read as a meaningful write to the register
`GF.Pal` actually uses. The `ldd V.WWidth,u` before it stays — `B` (the
height) feeds the two `beq noscroll` guards.

Verified behaviour-neutral: `.mods/grfdrv256` builds **byte-identical** to
commit `00abe155` (1923 bytes), and `.mods/vtio` is exactly 3 bytes smaller
(4312 → 4309, one extended `sta`). Boot, scrolling and the cursor are
unchanged in MAME.

This pass also surfaced that **`GFInitDisp` is a bare `rts`** — `GF.InitDisp`
(19) is a live entry in `FuncTbl` that does nothing, while the `.d` comment
described a gamma ramp / font copy / screen fill. The comment now says STUB;
the stub itself is untouched and still open.

### `GF.InitDisp` deleted; text LUTs were on the wrong block

`GF.InitDisp` (19) had decayed to a bare `rts` behind a live `FuncTbl` entry
annotated *"Verify obsolute then delete"*, and its vtio caller
`InitDisplayMem` was already gone. It used to do four things:

| job | status |
|---|---|
| 256-entry identity gamma ramp into `$C0` | dead — vtio never sets `Mstr_Ctrl_GAMMA_En`, so the gamma LUT is never consulted |
| install the `palette` data module into the text LUTs | the FPGA preloads it (so does MAME's `device_reset`) |
| copy the `font` data module into `$C1` | ditto |
| fill `$C2`/`$C3` with spaces + `$10` | that is `GF.ClrScrn`'s job now |

So it is genuinely obsolete and is **deleted**, along with `gr.PalBuf` (its
64-byte snapshot area, the last field in the `gr.` block) and the dangling
`fontmod`/`palettemod` name strings in L2 `vtio.asm`. Ops above it renumber
down one: **`GF.Pal` 20→19, `GF.BmEnable` 21→20, `GF.BmFree` 22→21,
`GF.BmPalet` 23→22.** Safe because `FuncTbl` is a dense `jmp [b,y]` with no
bounds check and every call site goes through the `GF.*` equs.

> Both consumers now rely on the FPGA having preloaded the font and the text
> palettes at reset. That is true of the current FPGA load and of MAME's
> `device_reset`. If a bare board ever comes up without them, this is the
> code that used to install them — see `grfdrv256.asm~`'s `GWInitDisp` and
> `vtio.asm~`'s `InitDisplayMem`, and note L1 `vtio.asm` still does the whole
> job (gamma, palette, font) around lines 315-350.

**The real find: the text LUTs were being written to the wrong block.** All
four sites used `$4000+TEXT_LUT_FG/BG`, but `SetBlkC0C1` maps **`$C0` at
`$2000`** and `$C1` at `$4000`, while `defs/wildbits.d:446` says
`TEXT_LUT_BLK equ $C0`. So they landed on `$C1+$1700` — inside graphics LUT1
(`GRPH_LUT0_OFF+$700`) — instead of `$C0+$1700`. Corroborated three ways: the
`TEXT_LUT_BLK` equ, L1 `vtio.asm` (which maps `TEXT_LUT_BLK` into `MAPSLOT`
and writes at `TEXT_LUT_FG` within it), and MAME reading the text palette from
`m_vram_c0[0x1700]`. Now `$2000+TEXT_LUT_FG/BG`. Affected:

- **`GFPal`** — `1B 60` / `1B 61` (`ChgForePal`/`ChgBackPal`) had never worked;
  they were quietly corrupting a graphics CLUT instead.
- **`PushBuf` / `PullBuf`** — a terminal switch was saving and restoring 128
  bytes of graphics LUT rather than the text palette. **This one is on the
  multiterm critical path** and would have shown up as per-terminal colours
  not surviving a switch.

That also settles the old open question *"`ChgForePal` byte order assumed
BGRA — verify against the Vicky text LUT format when palette actually
works"*: **the order is correct.** `display 1B 60 01 00 00 FF FF` (PRN 1,
R=00 G=00 B=FF A=FF) leaves `$C0+$1700` entry 1 reading `FF,00,00,FF`, and
MAME's renderer reads that slot as B,G,R,A.

Verification: `.mods/grfdrv256` 1923 → 1920 (the 1-byte `rts` plus its 2-byte
`fdb`), `.mods/vtio` 4309 → 4298 (`fcs /font/` 4 + `fcs /palette/` 7), `Krn`
still 4096, boot and cursor unchanged.

### Known-latent, deliberately left alone

- `ScrollLive`/`ScrollShadow` blank the exposed last row of the **character**
  plane only; the colour plane keeps the old bottom row's attributes.
  Masked on every current path because the caller reaches `clrline` →
  `EraseLine` immediately after and `EraseLineCore` fills both planes.

### Still open / worth doing

- `FLinkProcess` (the "is it already linked in this process map?" scan) still
  starts at slot 7, using `B` rather than the bumped `A`.  Harmless today —
  with the fix no process ever has an oversized module's block at slot 7, so
  the scan can never match there — but it is an asymmetry to keep in mind if
  `F$Link` is called from a process that already has such a block mapped.
- `SS.DfPal` (`SSDfPal`) still maps `$C1` with the raw
  `F$MapBlk`-into-`D.SysPrc` helper rather than `CallGrfDrv`.  (It now does the
  same for the terminal's `T.CLUT0-3` buffer copy — see the 2026-09-09 bitmap
  section.)  Note it does **no** file I/O — the caller loads the data module and the driver just
  `F$Move`s 1K from the caller's task, which is the right shape.  The mapping
  is dead-zone-safe by construction: `F$Move` resolves the destination through
  the DAT *image* and maps the block into the kernel's slot-5/6 window, so it
  never dereferences the returned address itself.  That matters because
  `F$MapBlk` uses `F$FreeHB` (highest free block), which on the system map
  tends to return slot 7 — and CLUT 3 at offset `$1C00` would then straddle
  the `$1D00-$1FFF` dead zone if anything ever did dereference it directly.
- `SS.FntLoadF` (`SSFntLoadF`) keeps its in-driver `I$Open`/`I$Read`.  See the
  asset-loading section above for why it was left that way and what is wrong
  with it.
- `InsLine` / `DelLine` are still `rts` stubs.
- `SS.DevNm` is unimplemented in vtio; Shell+ calls it and handles the error
  gracefully.
- The known-latent scroll item above (the colour-plane last row).

## Asset loading: `assetload`, and why it is not a driver job  (2026-09-08)

Commits `518b182a` (new module) and `0c097832` (grfdrv cleanup).

The question was where `SS.FntLoadF`'s file I/O belongs.  It runs entirely
inside the driver today — `F$MapBlk` `$C1` into the **calling** process, then
`I$Open`/`I$Seek`/`I$Read`/`I$Close`.  The answer turned out to depend on a
requirement fonts do not expose: the same mechanism has to load 80K bitmaps,
plus sprites and tilemaps, as fast as the disk allows.

### The constraint that decides it: address space, not I/O semantics

Something has to map the destination blocks, and there are only three places
to do it:

- **The system map** is not available.  Device static storage can overflow
  into slot 2, and kernel blocks cannot be unmapped for the duration of an 80K
  load while the rest of the system runs.
- **The caller's map** may be full, and a driver scribbling blocks into a
  caller's address space is a poor contract.
- **A private address space** costs neither.  A forked child gets its own
  8-slot DAT image (`DAT.BlCt = 8`, `coco.d:198`); with its code and a small
  data area it has ~6 slots free, so it can map six blocks and issue one
  `I$Read` across the lot.

That is what `level2/wildbits/cmds/assetload.asm` is:

```
assetload <path> <startblock> [<blockcount> [<offset>]]
```

An application `F$Fork`s it and `F$Wait`s, so only that application blocks.
It handles OS-9 data modules (seeking to `M$Exec`, which is how
`sys/fonts/*` are built) and raw files alike, so a 2K font and a 76800-byte
pixmap go through the same path.

`<blockcount>` is a hard limit rather than "read to EOF", and that matters:
block `$C1` with a count of 6 would walk straight through the text screen at
`$C2`/`$C3`.  `<offset>` reaches sub-block assets — font set 1 at `$C1+$0800`,
the CLUTs at `$C1+$1000/$1400/$1800/$1C00`.

### Ported from vtio's `FileGetAllData`, with one trap

The module is derived from that routine.  Three things changed on the way out
of the driver, and the first is a trap worth remembering:

- **`Rd2B2Mem` had to go.**  Its `D.Proc`→`D.SysPrc` swap only made sense in
  the driver, where the stack is in the system map, so redirecting `I$Read`
  there landed the bytes on the driver's own stack.  In a user-state process
  the stack is in *that process's* map, so keeping the swap would have aimed
  the header read into the **system** map at the same logical address.  It
  also held `IntMasks` across a blocking disk read.
- Parameters arrive in the fork parameter area, not a caller register stack;
  status goes back through `F$Exit` for the parent's `F$Wait`.
- It maps up to six blocks per pass instead of one, so 76800 bytes is two
  passes rather than ten map/read/clear cycles.

Two bugs inherited from the original are fixed.  A file whose length is an
exact multiple of the window reported `E$EOF` as failure; `E$EOF` is now
success only if something actually landed — which also stops a seek past EOF
reporting success having transferred nothing.  And `U` is preserved across the
`I$Seek` calls: `I$Seek` takes the low half of the position in `U`, but `U` is
also the data area base that the header read addresses through, so clobbering
it left `hdrbuf` stale and sent the seek to offset `$87CD`.

> **`F$Chain` carves the register stack and the parameter area out of the
> module's own `M$Mem`** (`fchain.asm:95-97` subtracts `R$Size` and the
> parameter size and fails the fork with `E$IForkP` if it underflows).  A
> forked module must reserve both on top of its working stack, the way
> `merge.asm` does.

### Verified in MAME against known file contents

Not "no error reported" — actual bytes, via a `device_stop()` dump of the
`$C1` font blocks and of physical blocks `$20-$29`:

| case | expected | result |
|---|---|---|
| `boldfont` → `$C1+$0000` | sum `$0241FF`, `00×8 C0×8` | match |
| `cbmfont` → `$C1+$0800` via `<offset>` | sum `$022B5B` | match |
| `testpixmapbm0`, 76800 B → blocks `$20-$29` | all ten block sums | all match, incl. the partial 3072-byte tail |
| 76800 B file with a 1-block allowance | text screen intact | intact |
| `chd /dd/sys/fonts` then a bare filename | relative path resolves | resolves |

The last one confirms a forked child inherits the parent's CWD — `F$Fork`
copies `P$DIO` at `ffork.asm:186-190`.

### `GF.SSFntLoadF` deleted from grfdrv

`GF.SSFntLoadF` (5) was a live `FuncTbl` entry vtio never dispatched to, and
its body was already dead-ended by a `bra errorclose@` sitting before the
`I$Open`.  Deleted the same way `GF.InitDisp` was, with the ops above
renumbering down one: **`GF.SSFntChar` 6→5, `GF.SSDScrn` 7→6, `GF.PushBuf`
8→7, `GF.PullBuf` 9→8, `GF.EraseLine` 10→9, `GF.ErEOLine` 11→10,
`GF.ErEOScrn` 12→11, `GF.PSGInit` 13→12, `GF.PSGBell` 14→13, `GF.PSGOff`
15→14, `GF.Cell` 16→15, `GF.ClrScrn` 17→16, `GF.Blank` 18→17, `GF.Pal` 19→18,
`GF.BmEnable` 20→19, `GF.BmFree` 21→20, `GF.BmPalet` 22→21.**  grfdrv's own
`Rd2B2Mem` went with it — both callers were inside the deleted block.
`.mods/grfdrv256` 1920 → 1718; `.mods/vtio` unchanged at 4298.

### Retracted from earlier in this document and from this session

Three claims that were made and are **wrong**:

1. **"grfdrv runs with interrupts masked."**  It does not.  `CallGrfDrvGo`
   captures `CC` into `gr.Temp` *before* its `orcc #IntMasks` and plants that
   pre-mask value as `R$CC` in the RTI frame (`vtio.asm:537-549`), so grfdrv
   resumes with the caller's original mask state.  The `orcc` only covers the
   stack swap.  The AltISR's `gr.Busy` tests only make sense because
   interrupts are live in there.
2. **"grfdrv cannot make `os9` calls."**  It can, and stock grfdrv does
   (`F$AlHRAM`, `F$AllRAM`, `F$DelRAM`).  The kernel has explicit machinery
   for it: `D.SSTskN` is "0 = system, 1 = GrfDrv" (`krn.asm:1022`), `SysCall`
   saves it and forces 0 for the duration, and `KrnSysProcDesc` restores it
   and ORs task 1 back into `DAT.Task` (`krn.asm:1200-1210`).  The real limit
   is *blocking* calls, for the re-entrancy reason below.
3. **"`F$Wait` from a driver breaks because `F$Exit` delivers status through
   the parent's `P$SP`."**  It does not break.  `FSleepTarget4` lays down
   exactly the `R$Size` frame shape (`pshs dp,x,y,u,pc` … `pshs cc,d` …
   `sts P$SP,x`, `fsleep.asm:203-215`), and the `R$U` in it is the register
   stack pointer `SysCall` set up with `leau ,s`, which stays valid because
   the caller's system-state stack survives the sleep.  So `F$Exit` would
   write into the driver's own SWI2 frame and `os9 F$Wait` would return with
   the PID and status in `A`/`B` — correct behaviour.

### Why grfdrv is still the wrong home for a blocking read

Not the reasons above.  The real one: **there is no lock.**  grfdrv's whole
context is single-instance — `gr.Stack` holds one caller's `S`, `D.CCStk` is
one stack that `lds <D.CCStk` resets to the top of on every entry, and
`SysCall` pushes the `D.SSTskN` byte onto that same stack.  Nothing gates the
foreground path: `gbusy` is defined at `vtio.asm:555` and **never branched
to**, as the comment at `vtio.asm:988` admits.  If a read slept there, a
second process writing to any terminal would walk straight in and overwrite
the sleeper's frames.  Gate it and you get a stall instead — and because
`gr.Busy` is what the AltISR checks before `SwitchTerm` (`vtio.asm:105`) and
`PSGOff` (`vtio.asm:126`), that stall would freeze Alt-arrow terminal
switching for the duration.

### Options priced and rejected

- **Stock's write-stream approach.**  CoCo3 has no font SetStat at all:
  `merge /dd/sys/stdfonts` (a plain user program, `level1/cmds/merge.asm:112-132`)
  reads the file and `I$Write`s it, and CoWin absorbs the payload in 72-byte
  chunks through a continuation state machine (`V.ParmCnt`/`V.ParmVct`,
  `cowin.asm:747`).  wildbits vtio already has the same machinery under
  different names (`V.EscNeed`/`V.EscHandler`/`V.EscParms`, and `vtio.asm:1400`
  already re-arms it).  Rejected on cost: 2048 driver entries and ~4096 Vicky
  I/O register writes to move a 2K font, against four sector reads.
- **`F$Load`'s fake-process pattern** (`ioman.asm:1694-1760`) — `F$AllPrc` a
  throw-away descriptor, `I$Open` while `D.Proc` is still the caller so
  relative paths resolve, `F$AllTsk`, `stx <D.Proc`, then read into blocks
  mapped in its private DAT image, growing to all eight slots.  This is the
  same idea as the forked module, done inside the kernel, and is the template
  if this ever becomes a kernel service.  Not used: a module is easier to
  build and test, and it costs no permanent kernel space (and no `Krn` `$1000`
  compensation).
- **DMA** would beat all of it, but DriveWire boots cannot use it, so it
  cannot be the only path.

### Deliberately deferred

`SS.FntLoadF` keeps its current in-driver implementation.  Forking `assetload`
from it is the better shape eventually, but it needs the caller-map parameter
marshalling (`F$Fork` reads the parameter area through `P$Task` of `D.Proc`,
`ffork.asm:228-236`, so the string must be assembled in the caller's space —
the `F$PErr` pattern of scratch below the caller's `P$SP`, `krnp3_perr.asm:124-126`)
and it inherits `F$Wait`'s reap-any-child behaviour.  Not worth it for a 2K
font while multiterminal is unfinished.

Its known defects, for whenever it is revisited: the module check is
`cmpx #$87CD / bcc`, so anything ≥ `$87CD` passes; the failure paths return
`ldb #3` and `ldb #4`, which are not OS-9 error codes; short reads are not
detected; and `Rd2B2Mem` holds `IntMasks` across a blocking disk read.

An unrelated one found alongside: vtio's armed escape-collector path calls
`UpdateLiveCursor` on **every** gathered parameter byte (`vtio.asm:1181`),
writing two Vicky cursor registers each time to no effect.  Stock returns
immediately (`Do1E: clrb / rts`).

## Multiterminal works  (2026-09-08)  — **two live terminals, verified**

Multiterminal had never been tested; only `/term` had ever been opened.
`InitTerm`'s `NotFirst` branch, `BlankTermText`, `SwitchTerm`,
`PushBuf`/`PullBuf` and `gr.TermTbl` had never executed, and two of them had
only just been made correct (`PushBuf`/`PullBuf` addressed the wrong block
until `b0f35885`, `SwitchTerm`'s `V.CurPos` resync until `00abe155`).

All four stages now pass in MAME `wbjr2`, deterministically:

| stage | result |
|---|---|
| `iniz /vt1` + `echo HelloVT >/vt1`, no shell | `HelloVT` lands in `/vt1`'s `T.Block` buffer, nothing on screen, `/term` untouched |
| Alt-Left / Alt-Right switching, no second shell | `/vt1` appears, `/term` restored **intact**; both buffer checksums identical across the round trip |
| `dir -e /dd/CMDS >/vt1` while `/vt1` is shadow | ~100 lines scroll `/vt1`'s buffer correctly through `ScrollShadow`, no blanked row 0 |
| `shell i=/vt1&`, then both shells interactive | `free` and `pwd` typed on each terminal, switching between them, each shell reads its own keyboard input and paints its own screen |

`gr.TermCnt=2`, `T.Live` on exactly one entry, `D.KbdSta` following the live
terminal, `HW CURSOR` tracking the live terminal's `V.CurRow`/`V.CurCol`, and
the grfdrv re-entry counter at 0 throughout.

### The one blocker: `PutGlyph`'s shadow path never set `gr.TermBlk`

`WriteCharShadow` / `ScrollShadow` are *direct* calls — they bypass the
`gr.b*`/`gr.d*` parameter block and take A/B/Y in registers — so `gr.TermBlk`
is their only parameter out of GrfMem, and they use it to map the 16K buffer
into MMU slots 3/4.  Every other grfdrv entry that consumes `gr.TermBlk` has a
caller that refreshes it first:

| grfdrv entry | vtio caller refreshes via |
|---|---|
| `PushBuf` / `PullBuf` | `SetTermGrfPtrs` (InitTerm, SwitchTerm, TermTerm) |
| `EraseLine` / `ErEOLine` / `ErEOScrn` / `ClrScrn` | `SetThisTermGrfPtrs` |
| `GFCell` (PutCell), `GFPal` (ChgPal) | `SetWDest` |
| `GFBlank` | `BlankTermText` stores it itself |
| **`WriteCharShadow` / `ScrollShadow`** | **nothing** |

So a glyph written to a non-live terminal landed in whichever terminal's buffer
`gr.TermBlk` happened to name — in practice `/term`'s, because the live shell's
own scrolling reaches `EraseLine` → `SetThisTermGrfPtrs(/term)` first.  With one
terminal it could never be wrong; with two it was wrong most of the time, and it
would have looked exactly like a `PushBuf`/`PullBuf` failure.

Fixed with a `SetShadowBlk` helper next to `SetWDest`, called at both shadow
sites in `PutGlyph`.  It preserves A/B/X/Y/U (the glyph path needs all of them)
and returns **Z set** when `V.TermBufBlk` is 0 so the caller skips the write
entirely — the same refusal `BlankTermText` makes, because block 0 at LUT 1
`$6000` is the kernel.  `LDA`/`STA` both set Z and `PULS` does not touch CC, so
the flag survives the `puls a,pc`.

### `gr.Busy`: a detector, deliberately not a gate

`gbusy` (`vtio.asm:555`) is still never branched to.  That was re-examined
before adding a second writer, and the conclusion is to leave the foreground
path ungated:

- **A driver cannot be preempted mid-call.**  Slice expiry only sets
  `P$State |= TimOut` (`falltsk.asm:190-200`); the switch is taken in the
  system-call *return* path (`krn.asm` `KrnShutDownInts`), i.e. when returning
  to user state.  Two shells writing concurrently cannot overlap inside
  `CallGrfDrv2` — which the two-live-terminal test confirms.
- The window between `sts gr.Stack` and `jmp [D.Flip1]` is covered by
  `orcc #IntMasks`, and `gr.Busy` is set inside it, so the AltISR (which *does*
  check `gr.Busy`, `vtio.asm:105` and `:126`) cannot enter there either.
- The hole opens only if something inside the grfdrv window *blocks*.  Nothing
  does; `SS.FntLoadF`'s `I$Read` is in vtio, not grfdrv.
- A gate would turn silent corruption into a stall, and because `gr.Busy` is
  what the AltISR tests before `SwitchTerm`, that stall would freeze Alt-arrow
  switching for its duration.  The commented-out `WaitPush` in `InitTerm`
  already says so.

So it is **counted** instead: `CallGrfDrvGo` bumps `$12E2` and records the
second entrant's `GF.*` code in `$12E3`, and the MAME exit dump prints both.
It stayed 0 through every test above.  If it ever goes non-zero, the fix is
known and the culprit is named.

### `PushBuf`/`PullBuf` were copying the wrong 4K

`T.CLUT0`-`T.CLUT3` were copied to/from `$2800`, but CLUTs 0-3 are
`GRPH_LUT0_OFF` (`$1000`) within `FONT_BLK` (`$C1`), which `SetBlkC0C1` maps at
`$4000` — so `$5000`.  `$2800` is `$C0+$0800`, and 4096 bytes from there runs to
`$C0+$17FF`, straight across the sprite records (`$1300`) and the text LUTs
(`$1700`) the same routine has just saved separately.

A push/pull round trip was self-consistent, which is why nothing ever showed: it
saved and restored the gamma area instead of the graphics CLUTs, so
per-terminal CLUTs simply did not exist.  Same family as the text-LUT bug
recorded above.  Fixed in both routines; `grfdrv256` stays 1718 bytes (two
changed immediates), and the two-terminal round trip is unchanged.

### Verification harness in the MAME driver

A terminal switch cannot be checked from the screen alone — the terminal you
switched *away* from exists only in its buffer.  `wildbits_jr2.cpp` grew two
pieces, both reading through `get_physical_block_ptr()` so they perturb nothing:

- **`dump_multiterm()`**, called from `device_stop()`.  Prints the GrfMem
  globals, the block map use counts and the system DAT image, then per terminal:
  the decoded `gr.TermTbl` entry, the driver static (`V.TermID`/`V.TermLive`/
  `V.TermBufBlk`/cursor/dimensions/`V.V_MCR`/`V.WAKE`/`V.IBuf*`), a checksum of
  both blocks of the 16K pair, and its `T.TXT` rendered as text rows.  The
  checksums are what prove a round trip did not corrupt anything.  GrfMem
  addresses come from `vtio.list`, the `V.*` offsets from `vtio.map`;
  re-derive both if `defs/wildbits_vtio.d` changes.
- **`WB_KEYS`** — frame-scheduled PS/2 scancode injection through the existing
  `queue_kbd_scancode()` FIFO, e.g.
  `WB_KEYS="1200:alt-left;1450:pwd;1520:enter;1800:alt-right"` (60 frames per
  second).  This drives the genuine path — `keydrv_ps2`'s `E0Handler` →
  `DoLeftArrowDown` → `changewindowl` → `gr.SwitchReq` → vtio's AltISR — rather
  than poking `gr.SwitchReq` behind the driver's back, and it is the only way to
  exercise two live terminals in a headless run.  `WB_SYSDAT=1` additionally
  prints every change to the system DAT image.

### One thing that looks like a bug and is not

The exit dump shows `/term`'s 16K buffer block (`$3E`) sitting in the active
LUT at slot 1, which reads like a block handed out twice: the buffer comes from
`F$AlHRAM`, i.e. the top of RAM, and `PushBuf` writes 16K into it.  It is not.
The block-map use count for `$3E` is 1, and the same slot-1/2 churn — `$3E`
included — happens before `/term`'s `InitTerm` runs at all: those two slots are
a kernel scratch mapping window.  Corroborated by the buffer checksums, which
are byte-identical across a switch out and back.

### Gaps found and deliberately left

- **Cursor control registers are not per terminal.**  `PushBuf` saves
  `$FFC0-$FFCF` (= `V.V_MCR` + `V.V_LayerCTL` + `V.BordBack`, exactly 16 bytes);
  the cursor registers start at `$FFD0`, so enable / character / flash rate are
  global.  `SwitchTerm` sets X/Y explicitly, which is what matters.
- The cursor flash-rate setter `CurRate` (`05 23`) still pokes
  `VKY_TXT_CURSOR_CTRL_REG` without the `V.TermLive` guard its neighbours
  `CurOff`/`CurOn`/`CurChar` have, so `05 23` from a shadow terminal changes the
  live cursor's flash rate.  Same two-line fix as `CurChar`.
  **Closed 2026-09-09** — see the bitmap section.
- `InitTermStatic` does not inherit `V.CapsLck`, so caps-lock state is per
  terminal while the keyboard LED is global.
- `InitTerm`'s `cmpx #DAT.BlMx+1 / bhs AlHramD / tfr x,d` around `F$AlHRAM` is
  dead code.  `F$AlHRAM` returns the starting block in **`D`**
  (`fallram.asm:54-61`, sharing `FAllramStartReqBlk` with `F$AllRAM`), never in
  `X`; the branch is always taken because `X` is still the `gr.TermTbl` entry
  pointer (`$114D`+), which is why it works.
- The known-latent colour-plane last row in `ScrollLive`/`ScrollShadow` is still
  masked on the shadow path too: `PutGlyph`'s scroll block reaches `clrline` →
  `EraseLine`, and `EraseLineCore`'s `EraseLineShadow` leg fills both planes.


### Font set and cursor character made per-terminal  (2026-09-08, same day)

The gap above, closed for the three codes that had it.  Both fixes are in
`vtio.asm`; verified in MAME against the live `$FFC0`/`$FFD0` registers, which
`device_stop()` now prints as `HW MCR` and `HW CURSOR ... char=`.

**`ChgFont0`/`ChgFont1` (`1B 62` / `1B 63`) now defer rather than drop.**  The
font set is `FT_FSET` (`$20`) in `MASTER_CTRL_REG_H`, and `V.V_MCR` mirrors
`$FFC0-$FFC1`, so `PushBuf`/`PullBuf` already carry it per terminal — it just
was not being used.  Both entries now share a `ChgFont` tail with exactly
`SetWin`'s split: live writes the register *and* the mirror, shadow writes only
the mirror.  `tst V.TermLive,u` rather than `lda` so `A` survives for the escape
dispatcher.  Measured, with `/term` at `80x30` (`MCR_H = $04`):

| | live `MCR_H` | `/term` `V.V_MCR` | `/vt1` `V.V_MCR` |
|---|---|---|---|
| `display 1B 63` on live `/term` | `$24` | `$0024` | — |
| `display 1B 63 >/vt1` (shadow) | `$04` unchanged | `$0004` unchanged | `$0124` |
| …then Alt-Left to `/vt1` | `$24` | `$0104` | `$0124` |
| …then Alt-Right back | `$04` | `$0104` | `$0124` |

Before the fix the second row wrote `$24` to the live register and left `/vt1`'s
mirror alone — the font changed under whatever was on screen, and the next
`PushBuf` made it stick on the wrong terminal.

**`CurChar` (`05 22`) can only be guarded, not deferred.**  `PushBuf`/`PullBuf`
carry `$FFC0-$FFCF` (`V.V_MCR` + `V.V_LayerCTL` + `V.BordBack`) and the cursor
registers start at `$FFD0`, so there is no per-terminal mirror to stage it in.
It now returns early for a shadow terminal, the same shape as `CurOff`/`CurOn`:
`display 05 22 2A` on the live terminal still sets the hardware cursor character
to `$2A`, and `display 05 22 2A >/vt1` leaves it at the default `$5F` instead of
hijacking the live cursor.  Giving the cursor registers a per-terminal mirror
would mean 8 more bytes between `V.BordBack` and `V.BM0Cl_En` and widening both
copies to 24 bytes, which moves every `V.*` offset after it (including the ones
the MAME dump reads).  Not done.

`Krn` still 4096, `vtio` 4331 → 4356, and the two-live-terminal sequence is
unchanged with the re-entry counter still 0.

### Real hardware: Alt-arrow flashed the new window then went black

Reported from a real Jr2 after the above: the system boots, Alt+Right shows the
next window *for a split second*, then everything goes black and the machine
looks unresponsive.  MAME never reproduced it.

That is the signature `InitTerm`'s own comment predicts — *"PullBuf restores
uninitialized MCR and the display goes black after a one-frame flash"* — and the
ordering inside `PullBuf` matches it exactly: text, colour, LUTs, sprites, font
and CLUTs are restored first (so the new window appears), and the 16 bytes of
`$FFC0-$FFCF` are programmed **last**, so a bad `MASTER_CTRL_REG_L` turns the
display off a frame or two later.  A blank display also explains
"unresponsive": the machine is blind, not wedged.

**Root cause: `V.V_MCR` was only ever populated by reading the registers back.**
`PushBuf` captured `$FFC0-$FFCF` with a `CpyBlk`, and nothing else ever wrote
the mirror except `SetWin`, `ChgFont` and `SSDScrn` (high byte / both bytes of
the MCR only).  `InitDisplay` seeded none of it, and did not even program 6 of
those 16 registers — `$FFC2`/`$FFC3` (layer control), `$FFC8`/`$FFC9` (border
size) and `$FFCD-$FFCF` (background colour) were left at whatever the FPGA came
up with.  So the mirror's contents were whatever read-back produced, and
`PullBuf` then programmed that.  MAME's `vky_r` returns the last value written
for offsets `$00-$09` and `$0D-$0F`, so the round trip worked there; a Vicky
register is under no obligation to read back, and on the real FPGA it evidently
does not.

**Fix: the mirror is the source of truth, not the hardware.**

- `InitDisplay` now seeds `V.V_MCR`/`V.V_LayerCTL`/`V.BordBack` from a 16-byte
  `DispRegs` table and programs `$FFC0-$FFCF` *from the mirror*, so the two
  agree by construction and all 16 registers have a known value.
- `InitTermStatic` inherits those 16 bytes from the live console, alongside the
  width/height/colour it already copied.
- `PushBuf` no longer reads `$FFC0-$FFCF` at all.  `PullBuf` still programs them
  from the mirror; only the capture is gone.
- Every remaining reader now reads the mirror instead of the register:
  `SetWin` and `ChgFont0`/`ChgFont1` (both legs read `V.V_MCR+1`, and only the
  hardware store is conditional on `V.TermLive`), and `GSDScrn` reports from the
  mirror — which also fixes `SS.DScrn` reporting the *live* terminal's mode to a
  caller on a shadow terminal.
- `SSPScrn` mirrors its `VKY_LAYER_CTRL_0/1` writes into `V.V_LayerCTL`;
  without that, layer setup would be lost on the next switch now that `PushBuf`
  does not recapture it.

The invariant this establishes: **`$FFC0-$FFCF` is write-only as far as this
driver is concerned.**  Every writer updates the mirror; every reader uses the
mirror; the hardware is touched only for the live terminal.

Verified in MAME, where the change must be behaviour-neutral and is.  The
visible confirmation is `/term`'s mirror in a plain single-terminal boot: it
used to read `$0004` (the MCR low byte had never been written to it, because no
`PushBuf` had run) and now reads `$0104`, matching the live `HW MCR` exactly.
The two-live-terminal sequence still passes with **Alt+Right as the first
switch** this time, as does the font-set deferral table above.  `vtio` 4356 →
4389, `grfdrv256` 1718 → 1703, `Krn` still 4096, re-entry counter still 0.

### …and it was Vicky memory too: `TermVRAMSave`

Two more real-hardware rounds settled the rest.

First, a regression of my own: `InitDisplay` programs `$FFC0-$FFCF` with
`sta ,x+`, which leaves `X` at `$FFD0`, and the four cursor-register writes that
follow are all `TXT.Base`-relative — so they went to `$FFE0`-`$FFE6`.  Nothing in
`defs/wildbits.d` even names that range; on a real board it is undocumented I/O
page and the boot stalled before the shell.  MAME maps only `$FFC0-$FFDF` to
Vicky and lets the rest fall through to slot-7 RAM past the end of `Krn`, where
the writes are inert — so MAME booted clean and hardware did not.  Fixed by
reloading `X` (`52332714`).  A cheap reminder to check what an index register
holds after a copy loop, and that MAME's memory map is more forgiving than the
board's.

With that fixed the switch still blacked out, which exonerated the registers and
left the other thing `PushBuf` reads back: **Vicky memory**.  `PushBuf` captured
the text palette (`$C0+$1700`), the sprite records (`$C0+$1300`), font 0
(`$C1+$0000`) and the four graphics CLUTs (`$C1+$1000`), and `PullBuf` programmed
them.  On an FPGA, palette and font RAM is commonly written by the CPU and read
only by video scanout, with no CPU read port — so the capture is garbage and
`PullBuf` installs it.  A zeroed text palette is black on black; a zeroed font is
blank glyphs.  MAME models all of it as plain RAM.

The reported behaviour matches exactly, including the part that looks like a
hang: switching *back* restores the other terminal's equally-garbage capture, so
Alt-arrow never recovers and the machine stays blind — alive but with nothing on
screen.  `proc` on the real board confirmed it, showing the second terminal's
shell sleeping normally in `Read`.

The four copies are each gated by their own `TermSave*` switch in
`defs/wildbits_vtio.d`, so they can be brought back **one at a time on the
board** — MAME models all of it as plain RAM and cannot tell us which region is
at fault.  Addresses verified against the F256 Revision E map (2026-03-13);
every constant in `defs/wildbits.d` checks out against it:

| switch | region | Vicky | bytes |
|---|---|---|---|
| `TermSaveFont0` | font memory bank 0 | `$C1+$0000` | 2048 |
| `TermSaveTextLUT` | text LUT foreground + background | `$C0+$1700` | 128 |
| `TermSaveSprite0` | sprite bank 0 | `$C0+$1300` | 256 |
| `TermSaveCLUT` | graphics LUT0-3 | `$C1+$1000` | 4096 |

Sprite bank 1 (`$C0+$1400`) is deliberately not carried, so the sprite copy is
256 bytes even though `T.SPRITE0` reserves 512; banks 2 and 3 are FUTURE on
Revision E.  Whatever is switched off stays global, shared by every terminal.

**Bisect results so far, on the board:**

- **`TermSaveFont0` — works.** Font memory bank 0 reads back correctly, and
  three terminals with independent fonts *and* colours switch between each other
  cleanly.  So the black screen is not the font, and per-terminal font sets are
  a real feature now.
- **`TermSaveTextLUT` — this was the culprit.**  The text LUT does not read
  back.  `PushBuf` captured a dead palette and `PullBuf` programmed it — black
  on black, in both directions, which is exactly why Alt-arrow never recovered.
  128 bytes at `$C0+$1700`, and it cost the whole investigation.  **Left off.**
- **`TermSaveSprite0` and `TermSaveCLUT` — work.**  Tested together; the
  console switches cleanly with both on.

**Final state: everything but the text LUT is carried per terminal.**
Multiterminal is working on real hardware — three terminals, independent fonts
and colours, Alt-arrow switching in both directions.

> **Reading the last two carefully.**  Sprite records only matter with sprites
> enabled and the graphics CLUTs only in bitmap/tile mode, so a clean text-mode
> switch shows they do not *break* anything — not that they read back
> correctly.  Confirming those needs a graphics test, not a console one.

> **The FPGA is being fixed.**  A future release will support reading the text
> LUT, at which point `TermSaveTextLUT` 1 works — but only on that bitstream and
> later.  The mirror approach below works on every version, so prefer it unless
> you control which bitstream the board runs.

### Getting per-terminal palettes back without the read-back

`TermSaveTextLUT` is not the way, but the feature is still reachable, because
**only the capture is broken — writing the LUT works fine.**  So the same
asymmetry the display registers now use applies: `PushBuf` skips the region,
`PullBuf` still programs it, and the buffer copy becomes a write-only mirror
that vtio maintains.

For the text LUT most of that already exists: `GFPal` writes `T.FLUT`/`T.BLUT`
directly for a shadow terminal (that is what `SetWDest`'s `WD.Buf` leg is).
Two pieces are missing:

1. `GFPal` writes the hardware *or* the buffer, never both, so a live
   terminal's `1B 60`/`1B 61` never reaches its own buffer copy and is lost at
   the next switch-out.  It needs to write both.
2. `T.FLUT`/`T.BLUT` need seeding for a new terminal — from the live console's
   buffer copy, the way `InitTermStatic` seeds the `$FFC0-$FFCF` mirror.

Then `PullBuf` can restore the palette from the buffer with `PushBuf` never
reading Vicky, and `1B 60`/`1B 61` become per-terminal for real.

Three live terminals also supersedes the prior tree's *"One extra VT is enough.
Do not restore two shell i=/vtN& + proc."*  Two and three both work, on hardware
and in MAME.

> **Build trap: no rule lists a defs file as a prerequisite.**  Editing
> `defs/wildbits_vtio.d` alone did not rebuild `grfdrv256`, so a `TermSave*`
> change assembled to nothing and the `.mods` file was untouched — the same
> class of trap as `krn` not depending on `flink.asm`, and it nearly sent an
> untested build to the board.  `recipes/wildbits/l2/makefile` now adds
> `$(MODDIR)/vtio $(MODDIR)/grfdrv256: $(DEFSDIR)/wildbits_vtio.d
> $(DEFSDIR)/wildbits.d` after the include.  The tell, if it ever regresses, is
> `.mods/grfdrv256` not changing size when a switch is flipped.

What each routine stops copying: `T.FLUT`+`T.BLUT` 128 bytes (text FG/BG
palettes, `$C0+$1700`), `T.SPRITE0` 512 (`$C0+$1300`), `T.FONT0` 2048
(`$C1+$0000`) and `T.CLUT0`-`T.CLUT3` 4096 (`$C1+$1000`) — **6784 bytes**.  A
switch runs `PushBuf` on the terminal it leaves and `PullBuf` on the one it
enters, so **13568 bytes** leave every switch, against 19200 still copied for
the two 4800-byte planes.  At `CpyBlk`'s ~8.5 cycles/byte that is ~18ms less
time with interrupts masked inside `SwitchTerm` — about a frame.  `grfdrv256`
1703 → 1599, the 104 bytes being eight copy setups at 13 bytes each.

The Revision E map also shows how bad the old `$2800` CLUT copy was: 4096 bytes
from `$C0+$0800` runs to `$C0+$17FF`, across gamma R, the mouse graphics, the
**BITMAP and TILE control registers**, the memtext registers, all four sprite
banks and the text LUTs — so `PullBuf` was programming the bitmap and tile
registers with whatever had been captured.  `$C1+$1000` (LUT0 `$1000`, LUT1
`$1400`, LUT2 `$1800`, LUT3 `$1C00`) is exactly the 4096 bytes intended.

The cost is real: `1B 60`/`1B 61` per-terminal palettes need `TermSaveTextLUT`,
and a per-terminal font set needs `TermSaveFont0`.  If a region turns out not to
read back, the right way to get the feature back is the same
write-only mirror discipline the display registers now have — vtio owns the
value, writes it to both the buffer and the hardware, and never reads Vicky
back.  `GFPal` already writes the buffer copy for a shadow terminal, so that
half exists.

### Bitmaps: the background image, and five ways the driver lost it  (2026-09-09)

Reported from the board with `shellbg` running: the top ~40% of the background
image was noise, switching terminals corrupted the text screen, and switching
back left the graphics screen completely corrupt.  All three are one bug, and
it is not in the driver.

**`shellbg` hardcoded the bitmap's block number.**  It calls `SS.AScrn`, stores
the block the driver returns — and then, thirty lines later, overwrites it:

```
                    lda       #$36                First BMBlock
                    sta       <bmblock
```

`$36` is where `F$AlHRAM` used to land 10 blocks, *before* multiterminal.  Every
open terminal now takes a 16K switch buffer off the top of RAM first, so the
bitmap starts lower.  Measured in MAME with `/term` and `/vt1` open:

| | blocks |
|---|---|
| `/term` switch buffer | `$3E-$3F` |
| `/vt1` switch buffer | `$3C-$3D` |
| bitmap (`SS.AScrn`, 10 blocks) | `$32-$3B` |
| where `shellbg` wrote the pixmap | `$36-$3F` |

So the bitmap registers pointed at `$32` while the image went to `$36` — four
blocks of ten, 40% of the screen, showing whatever was in `$32-$35`.  That is
the noise band.  And the last four blocks of the write, `$3C-$3F`, went
straight through **both terminals' switch buffers**.  The `device_stop()` dump
showed it plainly: `T0.TXT` rendered as pixmap bytes instead of text.  From
there the other two symptoms follow mechanically — `PullBuf` restored `/vt1`'s
text and colour planes from image data (the unreadable text screen), and
restored `/term`'s `T.CLUT0-3` from image data (the corrupt graphics screen).

Fixed by deleting the two lines; `<bmblock` already held the right value.
`pixview.asm` had the identical hardcode and is fixed the same way.
`drawtest.asm` was already correct.

**Four driver bugs behind it, all in the same family as the display-register
work above.**  None of them could show while the block collision was
destroying the buffers, and every one of them would have bitten the moment it
was fixed:

- **`V.BMxCl_En` was never written.**  `SS.AScrn` and `SS.Palet` sent the
  control byte to `GF.BmEnable`/`GF.BmPalet` — which is to say to the
  hardware — and stored only the *block* in the mirror.  `PullBuf` programs
  `$C0+$1000+8x` from the pair, so the first Alt-arrow back into the terminal
  wrote a zero control byte and turned the bitmap off.  The dump made it
  visible: `HW BM2 ctrl=$05` against `V: BM2 ctl=$00`.  Both setters now write
  the same byte to the mirror that the register gets, and `SS.FScrn` clears
  both bytes of the pair rather than just the block.
- **`SS.FScrn` read `MASTER_CTRL_REG_H` back** to decide whether to free 8
  blocks or 10.  Reads `V.V_MCR+1` now.  (`SS.AScrn` sizes the *allocation*
  from its screentype parameter instead, so a caller that passes a screentype
  disagreeing with `CLK_70` allocates and frees different counts.  Nothing
  does today.)
- **`SS.PScrn` read `VKY_LAYER_CTRL_0` back** — twice in the layer-1 leg, once
  to merge the other layer's nibble and once again after storing it.  It now
  merges out of `V.V_LayerCTL` with a `mul`, and writes the register only for
  the live terminal.
- **`SS.DScrn`, `SS.PScrn`, `SS.AScrn`, `SS.FScrn`, `SS.Palet` and `CurRate`
  were unguarded.**  A shadow terminal could repoint the live bitmap
  registers, layer control and MCR.  All six now take the `SetWin` shape:
  the mirror is always updated, the hardware only when `V.TermLive`.

**`SS.DfPal` now writes the buffer copy as well as the live CLUT.**  It was the
one graphics setter with nowhere to defer to — guarding it would have made
`SS.DfPal` from a background terminal silently do nothing.  `T.CLUT0-3` sit at
buffer offset `$3000-$3FFF`, which is offset `$1000-$1FFF` of the *second*
block of the 16K pair — exactly the offsets they have inside `$C1`, so the same
`clutlookup` table addresses both, and the new `DfPalMv` helper does one
`F$MapBlk`/`F$Move`/`F$ClrBlk` per destination.  Dead-zone safe by construction
for the same reason the original `$C1` copy was: `F$Move` resolves the
destination through the DAT image and `F$ClrBlk` only edits the map, so neither
dereferences a slot-7 address where CLUT3 would straddle `$1D00-$1FFF`.

Verified in MAME, `/term` and `/vt1` both running `shellbg`, with an
Alt-Right/Alt-Left round trip in between:

| | `/term` | `/vt1` (shadow) |
|---|---|---|
| bitmap blocks | `$32-$3B` | `$28-$31` |
| `V.BM2Cl_En` / `V.BM2Blk` | `$05` / `$32` | `$05` / `$28` |
| `V.V_MCR` | `$0F04` | `$0F04` |
| `T.CLUT2` sum | `$003651` | `$003651` |
| live `BM2` register | `ctrl $05 → block $32` | untouched by the shadow |
| live `HW MCR` | `$0F04` | untouched by the shadow |

Switch buffers `$3C-$3F` stay intact, checksums identical across the round
trip, grfdrv re-entry counter 0.  Before the fix `shellbg >/vt1` repointed the
live bitmap register at the shadow terminal's block.

### …and the bitmap registers do not read back either  (2026-09-09, same day)

Reported from the board with the above in: `/vt1` came up, `shellbg` ran on it
and the background image displayed correctly.  Alt to `/term` — fine.  Alt back
to `/vt1` — **pure static**, full-spectrum noise with horizontal black bands,
text overlay still perfectly readable.  `/term` unaffected, switching still
worked.

Static rather than wrong colours is the tell.  A bad CLUT turns a picture into
flat blocks of the wrong colour, because the flat areas of the image share one
index; only wrong *pixel data* gives fine-grained noise.  So the display was
pointed at the wrong address, and the only thing that touches the bitmap
address across a switch is `PushBuf`:

```
                    lda       $3010
                    sta       V.BM2Cl_En,u
                    ldd       $3011
                    lbsr      Addr2Blk
                    sta       V.BM2Blk,u
```

`$C0+$1000` is the bitmap register block, and `PushBuf` was reading it back and
overwriting the mirror with the result — the same mistake as `$FFC0-$FFCF` and
the text LUT, in the one place the earlier round had not looked, because the
`TermSave*` bisect only ever covered the four Vicky *memory* regions.  The
sequence:

1. `shellbg` on live `/vt1` → `SS.AScrn` writes `V.BM2Blk`, hardware programmed,
   image correct.
2. Alt away → `PushBuf` on `/vt1` reads `$3010-$3013` back and clobbers
   `V.BM2Cl_En`/`V.BM2Blk` with garbage.
3. Alt back → `PullBuf` programs the garbage.  Static.

`/term` looked fine throughout only because it had no bitmap of its own.  It was
in fact being corrupted the other way: `PushBuf` scraped **`/vt1`'s** live
bitmap registers into **`/term`'s** mirror, so `/term` was one `PullBuf` away
from displaying another terminal's image.

The bitmap and tile-map/tile-set capture is deleted; `Addr2Blk` went with it.
vtio owns these values now — `SS.AScrn`/`SS.Palet` write the mirror,
`SS.FScrn` clears it, and `InitTermStatic` zeroes `V.BM0Cl_En` through
`V.TS7Blk` for a new terminal (that range used to be seeded by `InitTerm`'s
`PushBuf`, which no longer reads anything).  `PullBuf` also clears each
bitmap's address low byte, because `GFBmEnable` — previously the only writer of
it — no longer runs for a terminal that sets its bitmap up while it is a
shadow.  `grfdrv256` 1677 → 1598.

Verified in MAME by replaying the exact report — `WB_KEYS` Alt-Right onto
`/vt1`, type `shellbg`, Alt-Left, Alt-Right — and in the mirror image of it
with the bitmap on `/term`.  Both round trip with the live `BM2` register
matching the terminal's own mirror and `/term`'s mirror staying all zeros.  As
always MAME passed before the fix too; it models the whole `$C0` page as plain
RAM.

> **Running total of what is write-only on this FPGA.**  `$FFC0-$FFCF`
> (display registers), `$C0+$1700` (text LUT), `$C0+$1000` (bitmap registers),
> and by association `$C0+$1100`/`$1180` (tile registers).  What *does* read
> back: `$C1+$0000` (font bank 0), `$C2`/`$C3` (the text planes).  The pattern
> that fits: Vicky **registers** never read back, Vicky **memory** does — which
> would make the text LUT at `$C0+$1700` the odd one out, and is why the two
> remaining questions below are still worth answering rather than guessing.

### Still open: does the graphics CLUT read back?

The caveat above — *"the graphics CLUTs only matter in bitmap/tile mode, so a
clean console switch shows they do not break anything, not that they read back
correctly"* — is now testable, because `shellbg` works.  MAME cannot answer it;
it models `$C1` as plain RAM.

**The board test.**  Boot with one extra terminal, run `shellbg`, Alt-arrow
away and back, and look at the image:

```
iniz /vt1
shell i=/vt1&
shellbg
```

This test was confounded until the bitmap-register fix above: the address was
being corrupted on every switch, so the image came back as noise no matter what
the CLUT did.  It is clean now — the image structure returning correctly is
what makes the colours meaningful.

- Colours survive the round trip → `$C1+$1000` reads back, `TermSaveCLUT 1` is
  correct, nothing to do.
- Image comes back with the right structure but wrong colours, or black → the
  graphics CLUTs are write-only, the same story as the text LUT.  The remedy is
  already staged: set

  ```
  TermSaveCLUT        equ       0     PushBuf stops reading Vicky back
  TermRestCLUT        equ       1     PullBuf still programs from the buffer
  ```

  `PullBuf`'s restore was split out from `PushBuf`'s capture for exactly this,
  and `SS.DfPal` already maintains `T.CLUT0-3`, so the mirror is complete.

The cost of that setting, and the reason it is not the default already:
**`fadein` and `fadeout` map `$C1` into their own process and write the CLUT
directly**, bypassing the driver entirely (`fadein.asm:97`).  With the capture
off their fades would become global instead of per terminal until they are
moved onto `SS.DfPal`.

Sprite bank 0 (`$C0+$1300`, `TermSaveSprite0`) is still unconfirmed the same
way; `sprtest2` is the equivalent test for it.

### Alt+arrow on the K2 keyboard, and the direction swap  (2026-09-09)

**The direction changed.**  `SwitchTerm`'s `SW.Next` (`$01`) reaches
`SwFindNext`, which does `inca` and walks *up* the terminal ids; `SW.Prev`
(`$FF`) is caught by `bmi` and walks down.  `keydrv_ps2` had Alt+**Left** on
`SW.Next`, so the left arrow moved toward `/vt1`, `/vt2`.  Now Alt+Right is
`SW.Next` and Alt+Left is `SW.Prev`.

> **Test tables in this document dated before 2026-09-09 read the opposite
> way.**  They are left as written — they record what those runs actually did.

Two terminals cannot show this: `+1` and `-1` land on the same place, which is
why every MAME run up to here was blind to it.  With three:

| from | key | to | evidence |
|---|---|---|---|
| `/term` (0) | Alt+Right | `/vt1` (1) | `aaa` in `T1.TXT` |
| `/vt1` (1) | Alt+Right | `/vt2` (2) | `bbb` on the live screen, `LiveTerm=$02` |
| `/term` (0) | Alt+Left | `/vt2` (2) | wraps down; `zzz` in `T2.TXT` |
| `/vt2` (2) | Alt+Left | `/vt1` (1) | `yyy` on the live screen, `LiveTerm=$01` |

**`keydrv_k2` gained the feature.**  The K2 is a matrix scanner, not a scancode
stream, so it is not a copy of the PS/2 code — but the hook is cleaner.  All
four arrows plus Space funnel through one routine, `processarrows`, with the
key code in `A` (`kLEFT $E2`, `kRIGHT $E3`), so the test goes there, after the
`bcc puparrows` key-down branch and before the `ModChrTbl` bits are set.  The
ALTBIT it reads needs no new work: `RALT` is `$F2` and `ModTbl` maps
`suba #$F0` to `CTRLBIT,SHIFTBIT,ALTBIT`, so `processmodifier`/`pupmodifier`
already maintain it exactly the way the PS/2 driver does.

Three details that make that placement the right one.  Being after
`KeyDownTest` leaves the key-up path alone, so `puparrows` still clears
LEFTBIT/RIGHTBIT and still reaches `rstkeyrpt@`.  Exiting through
`skipbuffer@` rather than `bufferit@` is the K2 equivalent of the PS/2
driver's `comb` — "do not treat as input" — and it balances, because the
routine's own `puls d,x` matches its `pshs d,x` and `skipbuffer@`'s `puls a`
then recovers the shifted eora bits for the rest of the bit loop.  And never
reaching `BufferChar` means no key repeat is armed, so holding Alt+Left does
not repeat the switch — which is what the PS/2 driver does too.

Everything inside is an `@` local, deliberately: `ProcessRow`'s `bufferit@`
(`$00A6`) and `BufferChar`'s (`$01BB`) are two different symbols with the same
name, and the existing `lbra bufferit@` in `processarrows` resolves backwards
to the first.  Adding non-local labels in between would be asking for trouble.
Verified in `keydrv_k2.list` instead of assumed: `lbra skipbuffer@` assembles
as `16 FF7E` at `$013A`, i.e. `$013D - $82 = $00BB`, which is `skipbuffer@`;
`sta >gr.SwitchReq` is `B7 114B`, matching `gr.SwitchReq` in the defs listing.

**A K2-only ordering hazard, left in.**  PS/2 scancodes are inherently
sequential so Alt always precedes the arrow.  The K2 FIFO delivers a whole
matrix snapshot per event and `ReadFIFOData` walks rows 0..8 in order.  From
`WBKKeys`: **kLEFT is row 0 col 5, RALT is row 6 col 2, kRIGHT is row 8 col
1.**  So if Alt and Left go down inside the same 16ms scan, row 0 is processed
before row 6, ALTBIT is not set yet, and Left is buffered as its character
(`$08`) instead of switching.  Alt+Right cannot hit this — row 8 comes after
row 6.  Pressing Alt first, which is what anyone actually does, avoids it
entirely, because Alt-down is then its own earlier FIFO event.  The fix, if it
ever matters, is to hoist the modifier rows ahead of the main loop in
`ReadFIFOData`; not worth the restructure speculatively.

**This cannot be tested in MAME.**  `mame.lst` has one Wildbits machine,
`wbjr2`, and `wildbits_jr2.cpp` models the Jr2's PS/2 controller with nothing
at `OKB.Base` (`$FE10`).  So `keydrv_k2` is assemble-and-inspect here and the
board is the only functional test — which is the argument for keeping the diff
a mechanical mirror of the PS/2 logic rather than an improvement on it.  What
was checked: `PLATFORM=k2` builds the whole L2 disk, `Krn` still 4096,
`.mods/keydrv_k2` 755 → 785, and both drivers assemble clean at Level 1 as
well (783 / 909).

**Left alone deliberately: `>gr.SwitchReq` is unguarded at Level 1.**
`gr.SwitchReq`, `SW.Next` and `SW.Prev` sit at `wildbits_vtio.d:309-312`,
outside every `IFGT Level-1` block, so they resolve at Level 1 — but there is
no grfdrv and no terminal table there, and `$114B` is ordinary system RAM.
`keydrv_ps2` has always poked it unconditionally and the L1 recipe builds the
same driver, so `keydrv_k2` now reproduces that rather than diverging.  If it
should be `IFGT Level-1`, it belongs in both drivers in one change.

> Unrelated, found while checking: the L1 recipe did not build at all.
> **Fixed the same day.**  `level1/wildbits/modules/vtio.asm` had drifted two
> symbols out of sync with `defs/wildbits_vtio.d`: `V.MapSav`, which the L2
> statics do not need and which is now declared in an `ELSE` leg of the
> `IFGT Level-1` block so it exists only at Level 1; and `V.EscVect`, the
> pre-rewrite name for what is now `V.EscHandler` — same 2-byte field, same
> `stx`/`ldx` use, renamed at its six sites in the L1 driver rather than
> aliased in the shared defs, so one field keeps one name.
>
> All four targets build again — `l1`/`l2` × `jr2`/`k2` — and the L1 `jr2`
> disk boots in MAME to an `OS9:` prompt.  L2 is provably untouched by the
> defs change: `vtio` stays 4474 and `Krn` 4096, which is what the `ELSE`
> placement buys.  **Anything added to that block in future must go in the
> `ELSE` leg for the same reason** — a byte on the L2 side shifts every `V.*`
> offset after it, including the ones `wildbits_jr2.cpp`'s dump reads.

---

## SUPERSEDED — see 2026-09-08 above.
## STATUS  (2026-09-07, continued session)  — four real bugs fixed and
## verified in MAME; boot still doesn't reach a shell; root cause of the
## remaining failure not yet found, and it looks environment/timing-
## sensitive rather than deterministic

Picks up from the "ROOT CAUSE FOUND" session below. That session's Task 2
(force kernel block into `KrnActualMMUBlock` slot 7) had *already* been
done by the user before this session started. This session found and
fixed three more real bugs, found and fixed a MAME driver bug that was
making our own diagnostics unreliable, and then spent most of its length
on MAME-based diagnosis that turned out to be undermined by MAME itself
not being deterministic/faithful for this specific class of bug. Ends
with a live, unresolved lead ("path number management with `/term`") and
a clean tree (only real fixes committed to the working copy; all sysgo.as
test scaffolding reverted).

### Fixes made and verified this session (all in the working tree, uncommitted)

1. **`SetTermGrfPtrs` skipped for `/term`** (`vtio.asm`, `InitTerm`,
   ~line 1077). The first-terminal branch (`gr.TermCnt==0`) took a
   `bra TermInited` shortcut that (correctly) skips `PushBuf`/
   `BlankTermText` for the live terminal, but also (incorrectly) skipped
   `SetTermGrfPtrs` — the only thing that loads `gr.TermBlk`/`gr.VBlk`/
   `gr.U5`/`gr.VStaStorU` from `T.Block` etc. Left `gr.TermBlk` at
   `InitGrfDrv`'s cleared `$00` until `SetWDest`'s next per-call snapshot
   caught up, so any grfdrv op that ran first (the sign-on banner's
   `PutCell`) mapped block `0` into MMU slots 3/4 via `SetBlkC2C3`. Fix:
   call `SetTermGrfPtrs` in that branch too, same as `NotFirst`.
2. **`V.CurPos` 8-bit `inc` on a 16-bit field** (`vtio.asm`, `PutGlyph`,
   ~line 1298). `V.CurPos RMB 2`, but `PutGlyph` advanced it with a plain
   `inc`, which (6809 words are big-endian) only touched the *high* byte
   — added 256 per character instead of 1. With `V.WWidth=80`,
   `256 = 3×80+16`, producing the exact "+3 rows +16 cols per character"
   diagonal scatter the user spotted in the banner. `V.CurRow`/`V.CurCol`
   (separate bookkeeping, advanced correctly nearby) silently diverged
   from where glyphs actually landed. Fix: `ldd/addd #1/std` instead of
   `inc`.
3. **`R.Flip0`'s `#$FE` mask only clears `ACT_LUT` bit 0, not
   `EDIT_LUT`** (`krn.asm`, ~line 114). `R.Flip0` is the *shared*,
   unguarded "return to system task 0" routine used by every 6809 port
   (CoCo3/MC09 included) — `EDIT_LUT`/`ACT_LUT` are F256-MMU-only
   concepts `defs/wildbits.d`-only, so the fix had to go inside a NEW
   `IFNE wildbits` guard (verified via direct `lwasm` invocation with
   `H6309=0` and `=1`, no `-Dwildbits`, against `defs/coco.d` — CoCo3's
   assembled bytes are still exactly `84 FE`/`02 FE 91`, byte-identical
   to before this fix). Effect of the original bug: any code that
   selected `EDIT_LUT_1` (`WriteCharLive`/`ScrollLive`'s direct writes,
   or `KrnWeGngBack` before `KrnActualMMUBlock`) left `MMU_MEM_CTRL`
   stuck on `EDIT_LUT_1` forever after — `ACT_LUT` correctly went back to
   LUT 0 (safe to *execute*), but every later MMU slot *write* from
   ordinary system-task code silently landed in LUT 1 instead, and raw
   reads like `wbinfo`'s `lda $FFAF` read LUT 1's slot 7, not LUT 0's.
   Fix (simplified per user's correction — no need for a
   preserve-other-bits mask; `DoFontGetSet`'s `%10010001` proves other
   bits of this register *are* used elsewhere, but confirmed unused at
   this specific point): `clr <D.TINIT` / `clr >DAT.Task` in both the
   6809 and H6309 legs, inside `IFNE wildbits`. No `pshs/puls a` needed —
   `CLR` never touches a register, so `A` survives untouched through to
   the routine's shared `tfr a,cc` tail.
4. **`SS.ScSiz` has no `rts`** (`vtio.asm`, `SSScSiz`, ~line 2168). Falls
   straight through into `SSJoy`'s body, which unconditionally
   overwrites `R$A` and conditionally overwrites `R$X`/`R$Y` with
   joystick VIA-port data. `SSScSiz` itself computed the right
   width/height into `R$X`/`R$Y` first — the *values* were fine, but the
   syscall returned joystick garbage instead on some/all of them
   depending on what the (likely unconnected) joystick VIA port happens
   to read. Found via a systematic audit of every `GetStat`/`SetStat`
   handler for exactly this bug class (see below). Fix: added `rts`.
   Note: turned out **not to be on Shell+'s startup path** —
   `shellplus.asm` never calls `SS.ScSiz`/`SS.ScTyp` at all — so real
   but not the cause of the current hang. Still correct to fix.

### Also fixed: the MAME driver's own diagnostic dump was reading the wrong offsets

`mame/src/mame/wildbits/wildbits_jr2.cpp`'s `device_stop()` read `D.Proc`/
`D.AProcQ`/`D.WProcQ`/`D.SProcQ` from `$4B`/`$4D`/`$4F`/`$51` — a stale
Level-1-era layout. `defs/os9.d` has two conflicting definitions of these
symbols (one commented "$4B", one without an address comment); the
*actual* assembled code (`std <D.Proc` → `DD 50` in `krn.list`) uses
direct-page offset `$50`, five bytes later. Fixed the driver to read
`$50`/`$52`/`$54`/`$56` instead and rebuilt MAME (`make
SOURCES=src/mame/wildbits/wildbits_jr2.cpp` — fast, incremental, ~30s).
Every `D.Proc` value quoted anywhere in this doc or in memory *before*
this fix is bogus; everything after it is real. This single mistake
explains a lot of confusing readings earlier in the investigation (the
driver was silently reading whatever else happened to sit at `$4B`).

### Confirmed NOT a regression, deprioritized

`GSPalet` (`SS.Palet` "get palettes") is completely empty and falls
through into `SSFBRGs`'s code — same bug *class* as the `SS.ScSiz` fix,
but confirmed byte-identical in `nitros9-priorversion/level2/wildbits/
modules/vtio.asm` (the known-working prior tree). Pre-existing, harmless
enough that it never mattered before. Left alone.

### Confirmed real, NOT yet fixed — same root-cause family as the very first
### session's diagnosis, still live

- **`SS.DfPal`** (`vtio.asm` `SSDfPal`, ~line 2868) still uses the
  original `mapblock`/`clearblock`/`F$MapBlk`-into-`D.SysPrc` mechanism —
  never migrated to `CallGrfDrv` the way `GS.FntChar`/`SS.FntChar` were
  (in a prior session, before this one).
- **`SS.FntLoadF`** (`vtio.asm` `SSFntLoadF`, ~line 2544) — same,
  confirmed still using raw `F$MapBlk`.
- Neither is confirmed to be *reachable* on the current fresh-disk boot
  path (`scfg -dl` only reaches `SS.FntLoadF` if `/dd/sys/defaultsettings`
  already has a saved font — confirmed absent on the test disk and,
  per the user, absent on the real hardware SD card too). Real bugs,
  but not proven to be *this* bug.

### MAME's `-debug` mode is not trustworthy for this investigation

Repeatedly confirmed: merely attaching `-debug` (even combined with
`-nothrottle`) changes the boot's *outcome*, not just its wall-clock
speed — e.g. a plain `-nothrottle` run reaching a clean full banner, vs.
the identical build under `-debug` corrupting earlier and differently.
This is presumably because the debugger's per-instruction-fetch
breakpoint-check overhead shifts exactly the kind of interrupt-vs-
instruction-stream timing this bug is sensitive to. Consequence:
anything learned via a MAME breakpoint/watchpoint trace in this session
should be treated as suspect, not as ground truth about normal
execution. Techniques that *did* prove reliable, for reference:

- `save FILE,ADDR,LEN` inside a `bpset`/`wpset` action reliably reaches
  the host filesystem; `printf` mostly does not (matches the existing
  MAME memory note, reconfirmed many times over).
- MAME debug expressions support inline memory dereference:
  `w@ADDR`/`b@ADDR`, and these can nest — e.g.
  `bpset (w@((w@C2)+6)),1,{...}` computes a syscall's dispatch-table
  entry from the fixed `D.SysDis` global (`$C2`) and sets a breakpoint on
  the *result*, without needing to know any dynamically-loaded module's
  load address in advance. (`D.SysDis`+`syscall#*2` → absolute handler
  address, Level-2 dispatch format — see `fssvc.asm`.)
- The single most useful *fixed*-address breakpoint for tracing syscalls
  system-wide, regardless of caller: `ExecSvcCall` in `krn.asm`
  (`$EE00+$03EB = $F1EB` in this build) — every `os9 Fxxx`/`Ixxx` call,
  user-state or system-state, converges here with `B` = the syscall
  function code. `bpset F1EB,B==N,{...}` catches every call to syscall
  `N` from anywhere, with no dynamic-address hunting needed.
- Dynamically-loaded modules (`sysgo`, `krnp2`, anything not `krn.asm`
  itself) do **not** sit at a fixed, computable address — tried and
  disproved the "contiguous bootfile blob" hypothesis empirically (a
  `save` at the computed address read all zeros). Don't waste time
  computing predicted addresses for these; either find them at runtime
  (a full-visible-RAM `save`+search for a unique string worked poorly —
  the target is often in a physical block not currently windowed into
  the active LUT) or use the `ExecSvcCall` trick instead to sidestep the
  problem entirely.

### Diagnostic bisection this session, and what it showed

User's idea: replace what `sysgo` forks in place of `Shell "startup -p"`
to bisect where the failure actually is (`level1/wildbits/modules/
sysgo.as`, `DoStartup`, temporarily wired to fork a `TestCmd`/
`TestCmdArg` pair instead of `Shell`/`Startup` — reverted clean now,
`sysgo.as.bak` is the backup used to revert).

- **`hold@`/`hold2@`: infinite loop placed right before, then right
  after, `DoStartup`'s `F$Fork`.** On *real hardware*: the loop holds
  (confirmed by the user), and the mouse cursor is fully responsive the
  whole time — interrupts and grfdrv/LUT-1 flips are demonstrably
  healthy at this point. In MAME: never actually caught sitting in the
  placed loop — always found elsewhere (frozen at one address for the
  first `hold@` test, wandering for `hold2@`) — consistent with the
  general MAME-unreliability finding above, not trusted.
- **Forking `dir` instead of `Shell`.** First attempt: complete,
  correct, stable output (`Directory of .` + correct file listing) for
  every sample across a 30s run. This looked like strong evidence that
  vtio's entire write path is fine and the bug is specific to whatever
  `Shell` does differently. **But it was not reproducible** — later,
  unchanged-disk, no-code-change re-runs of the identical `.dsk` file
  mostly *failed* (logo truncated at row 4-5, LUT/MMU garbage by 15-30s)
  — 1 success out of ~6 repeat attempts on the exact same binary. This
  is real, load-bearing evidence of *genuine non-determinism*, most
  likely timing-dependent (an interrupt landing at a slightly different
  point in the instruction stream between otherwise-identical runs) —
  not proof that `dir`'s path is safe.
- **Forking `proc` instead of `Shell`.** Failed harder and *every* time
  it was tried: logo truncated before even finishing (worse/earlier
  than any `dir` failure), and the most extreme garbage signature seen
  all session (`D.Proc`/`D.AProcQ`/`D.WProcQ`/`D.SProcQ` all `$FFFF`,
  `Code at PC` solid `$FF` — reading from what looks like fully
  unmapped/open bus). `proc` has to read *other processes'* descriptors
  (cross-task memory access) where `dir` only reads its own directory —
  fits the F$MapBlk/cross-DAT-image theme of every other confirmed bug
  this session, and is the sharper, more consistent signal of the two.
  Not yet traced to a specific mechanism (`F$GPrDsc`? direct `D.PrcDBT`
  walk? — not yet checked).
- A `TestCmd2 equ *-TestCmd2` the user tried mid-session is a
  self-referential `equ` (evaluates to 0, since `*` at that point *is*
  `TestCmd2`'s own address) — flagged but never actually tested with a
  rebuild (build was aborted as "taking too long"); `sysgo.as` was then
  reverted clean instead of pursuing it. Worth another look: passing
  `F$Fork` a genuinely zero-length parameter area (vs. the intended
  1-byte bare-CR) could itself cause a forked command to scan into
  unterminated memory for a parameter that isn't there — a plausible
  *additional*, separate source of non-determinism, never confirmed
  either way.

### Traced: what Shell+ actually does at startup (source-level, not runtime)

`level1/cmds/shellplus.asm`, forked as `Shell "startup -p"`. First ~6
`os9` calls in order: `F$Icpt` → `F$ID` (user # for logging) →
`I$GetStt SS.DevNm` (building the default prompt `'{@|#}$:...'`'s `@`
device-name placeholder — **vtio doesn't implement `SS.DevNm` in its
`GetStat` dispatch at all**, hits the "unknown service" fallback, but
Shell+ handles that error gracefully and just omits the device name —
confirmed not fatal) → `F$SUser` (restores current user#, part of a
paired temp-superuser-switch/restore where the "switch away" half got
skipped this first time — looks like intentional/harmless asymmetry, not
investigated further) → **`F$Fork`/`F$Wait` inside `CmdSTARTUP`**.

The standout finding: `"startup"` isn't an ordinary external command —
it's a **hardcoded keyword** in Shell+'s own command parser
(`CmdSTARTUP`, `shellplus.asm:1428`). When Shell+'s command line matches
the literal word `"startup"`, it **forks a second copy of itself**
(`L000D` → `fcs /Shell/`, i.e. the module's own name), passing the *bare*
parameter `"startup"` (no `-p`), and blocks on `F$Wait`. So
`sysgo → Shell "startup -p"` actually becomes `sysgo → Shell → (forks) →
Shell "startup"`, and everything from opening the `startup` script
onward (`load utilpak1`/`link shell`/`wbinfo`) happens inside that
*inner*, nested Shell process. **Open question, not resolved**: what
stops the inner child (bare `"startup"`, no `-p`) from matching the same
keyword again and recursively forking forever — either the `-p` flag
changes which parse path the *outer* Shell+ takes before ever reaching
keyword matching, or the inner child's bare-word argument is handled as
"read commands from this file" rather than re-triggering `CmdSTARTUP`.
Worth resolving before spending more time on Shell-specific hypotheses.

### Open, unresolved at end of session

**"Path number management with `/term`"** — the user's live hypothesis
when the session ended. Checked so far: `/term`'s own `SS.Open` handling
(`SSOpenNamed`, `vtio.asm:2418`) is trivial and looks correct (just
returns `V.TermID`/`gr.TermCnt` for a breadcrumb). `PD.PD` (the actual
path-number field in the OS-9 path descriptor) exists but vtio never
reads it anywhere — not necessarily wrong on its own, most drivers
address via the descriptor pointer, not a raw number. Not yet checked:
whether `F$Fork`'s standard path-inheritance (child inherits parent's
open paths 0/1/2) behaves correctly across the `scfg` → (F$Exit) →
next-forked-child sequence specifically on this port, or whether
anything in vtio's per-device (not per-path) static storage — e.g.
`V.SSigID`, which can only hold one signal registration at a time — gets
confused when multiple paths/processes share the same `/term` device
static storage via inheritance.

### Current tree state at end of session

Working tree has exactly four fixes, all uncommitted: the three
`vtio.asm` fixes above, the `krn.asm` `R.Flip0` fix above.
`level1/wildbits/modules/sysgo.as` is back to byte-identical with
`sysgo.as.bak` (all `TestCmd` diagnostic scaffolding removed). MAME
itself (not part of this repo's own source, but locally rebuilt) has the
`D.Proc` offset fix baked in.

---

## SUPERSEDED / PARTLY RETRACTED — see 2026-09-08 above.
## STATUS  (2026-09-07)  — ROOT CAUSE FOUND, fix planned

Both modules assemble; bootfile fits.  Boots (FEU L1 → `bootos9` → L2
kernel; L2 clears the screen with its own colour), then **crashes into
`D.Crash` / `CrashCode` (`$EEDE: bra $EEDE`)** shortly after `sysgo` forks
`scfg -dl`.

### The crash chain (verified by MAME trace + slot-7 write log)

1. `scfg -dl` (new in the branch `sysgo.as`, edition 3 — the prior version
   forks `fcfg`, no `-dl`) issues `SS.FntLoadF` / `SS.DfPal` / `SS.Palet`
   SetStats on the console.
2. vtio's `DoFontGetSet` / `SSFntLoadF` / `SSDfPal` (and the `mapblock` /
   `clearblock` helpers) **abuse `F$MapBlk`**: they set `D.Proc = D.SysPrc`
   and call `F$MapBlk` to map `$C1` into the *system* process.  `F$MapBlk`
   ends in `F$SetImg`, which sets `D.SysPrc.P$State |= ImgChg`.
3. Next syscall return → `KrnSysProcDesc` → `TstImg` sees `ImgChg` on
   `D.SysPrc` → `FSetTsk` (`$FB39` in the trace) does **`clr <D.Task1N`**
   and reloads the MMU via `KrnActualMMUBlock`.  This fires ~31×/boot
   (≈11 from `F$MapBlk`, the rest from `F$Fork`/`F$Exit`).
4. `clr <D.Task1N` forces the **next grfdrv flip** (`S.Flip1` shares
   `KrnActualMMUBlock`) to *re-load* LUT 1 from `gr.DATImg`.
5. **Format mismatch:** grfdrv maintains `gr.DATImg` as **8 × 2-byte
   words** (`SetBlkC2C3`: `ldx #gr.DATImg+2 / std ,x++`), but
   `KrnActualMMUBlock` consumes it as **`leau 1,u` + 8 single bytes**
   (`lda ,u++ / ldb ,u++ / std ,x++` ×4), so `MMU slot 7 = gr.DATImg[8]`
   — a `$00` word-high-byte or `gr.TermBlk+1` (`$0B` in the trace), **never
   the kernel block**.  LUT 1 slot 7 ends up garbage.
6. A timer IRQ during a grfdrv op → `S.SysIRQ`'s tail switches back into
   the task-1 map (`$FCEC sta DAT.Task`) and executes `$FCEF+` = LUT 1
   slot 7 = garbage → NOP-slide → `CrashCode`.

The prior version works only because its `sysgo` (`fcfg`, no `-dl`) never
runs those SetStats, so `D.Task1N` stays `2`, `KrnActualMMUBlock` never
re-loads LUT 1, and the latent `gr.DATImg` format bug never bites.

### Agreed fix (do in this order, next session)

1. **Remove `F$MapBlk`/`F$ClrBlk` from vtio.**  `SS.FntChar`/`GS.FntChar`
   and `SS.DfPal` → move wholesale into grfdrv ops (they only use
   `F$Move`, which is non-blocking and safe from grfdrv; grfdrv maps `$C1`
   via `SetBlkC0C1` — `EDIT_LUT_1`, never touches the system DAT).
   `SS.FntLoadF` — **keep `I$Open`/`I$Read`/`I$Close` in vtio** (the SD
   read path `F$Sleep`s in `rbsuper`; blocking inside the grfdrv flip →
   scheduler runs another process → re-entrant `CallGrfDrv2` clobbers
   `gr.Stack`/`gr.PDRGS` since **`gr.Busy` is never enforced** — `gbusy` is
   dead code).  vtio reads into a scratch buffer, one grfdrv op blits it
   to `$C1`.  grfdrv already has stubbed `SSFntLoadF`/`SSFntChar` handlers
   (FuncTbl b=4/5/6) started and abandoned — finish/replace them.
2. **Kernel: force slot 7 = `KrnBlk` in `KrnActualMMUBlock`** (wildbits
   branch), exactly like the `picothing` branch already does
   ("kernel page must always be in slot 7").  After the 6809 `KrnBank`
   loop, X = `$FFB0`, so `lda #KrnBlk / sta -1,x` (or `sta >DAT.Regs+7`).
   This makes every task-1 flip keep the kernel reachable regardless of
   `gr.DATImg`.
3. **Enforce `gr.Busy`** on `CallGrfDrv2`/`CallGrfDrvNoPD` (also fixes the
   AltISR terminal-switch race).  Prerequisite if #1's `SS.FntLoadF` is
   ever fully moved into grfdrv.

### Changes already in the working tree (branch `wb/multiterm`)

- `grfdrv256.asm`: `WriteCharLive/WriteCharShadow/ScrollLive/ScrollShadow`
  (the direct-call entries, reached via `jmp [D.Flip1]` which skips
  `entry`) now do `lda #EDIT_LUT_1+ACT_LUT_1 / sta MMU_MEM_CTRL` first —
  they were doing `stb MMU_SLOT_n` against LUT 0 (system map) and
  corrupting it (`00 C2 C3 …`).  **Real bug, verified fixed.**
- `grfdrv256.asm`: deleted breadcrumbs `stx $1190 / sty $1192` and
  `sta $1194 / sty $1196 / sta $1198` — they landed inside `gr.TermTbl` /
  on `gr.WGlyph`/`gr.WOff` (GrfMem actually spans `$1100-$11DD`, not just
  256 bytes).
- `vtio.asm`: `edition set 3` (so `F$Link("vtio")` under L2 beats the
  FEU's edition-2 L1 vtio — the L1 vtio maps VRAM into slot 7, which is
  fine under L1 but not L2).
- An earlier `InitGrfDrv` slot-7 edit was **reverted** — it wrote
  `gr.DATImg` word 7, which `KrnActualMMUBlock` never reads.

### MAME notes

`./mame wbjr2 -window -skip_gameinfo -hard <dsk>` — **pad the disk first:
`truncate -s 4M l2_wildbitsjr2.dsk`** or the SPI-SDCARD model rejects it.
Flash is un-dumped ($FF); the driver bootstraps at `$FC02`.  On exit the
driver prints a VRAM text snapshot + PC + MMU state.  Trace with
`-debug -debugscript FILE` containing `trace out.log,0,noloop`.  Kernel
loads at `$EE00` (`Bt.Start`), so module offset N = `$EE00+N`;
`recipes/wildbits/l2/krn.list` has offsets.  KrnBlk = RAM block `$07` in
this build.

`make -C recipes/wildbits/l2` builds `.mods/vtio` + `.mods/grfdrv256` +
`bootfile` clean (set `NITROS9DIR`; `wildbits-sys-assets` fails locally on
a missing `port.mak` — unrelated).

---

## STATUS  (2026-09-06)  — historical

**Both modules assemble. Bootfile fits ($7E00).  Boots partway then hangs:
gets to / through the initial screen clear, then stops.**  No migrated
grfdrv op has ever run before this build (the module never assembled until
now), so every one is suspect.

## What the rewrite did (all DONE / assembling)

### 1. Escape parser — table-driven byte-counter state machine
Replaced the old `V.EscVect` chained-vector parser with
`V.WriteState / V.EscCount / V.EscNeed / V.EscHandler / V.EscParms`.
- `DCodeTbl` (`vtio.asm` ~1385) `jmp d,x` for single-byte codes $00-$0D.
- `Arm02/Arm05/Arm1B/Arm1C/Arm1F` + `EscArm` arm the collector;
  `EscCodeComplete` runs `[V.EscHandler]` then `UpdateLiveCursor`.
- `Esc1BTbl / Esc05Tbl / Esc1FTbl` — linear `{fcb byte, fcb nparm,
  fdb handler-base}` tables, `$00` terminator; `EscScan` + `Disp1B/05/1F`.
- Leaf handlers rewritten to read `V.EscParms+0…` and `rts`:
  `CurXY`, `FColor/BColor/Border` (`FGCUpdate` shared tail), `ChgForePal/
  ChgBackPal` (merged: `clrb`/`ldb #1` + shared `ChgPal`), `DWSelect/DWEnd/
  DefColr/BoldSw` (`rts` stubs), `$1F` attr stubs `ULOn/ULOff/BlkOn/BlkOff`,
  `InsLine/DelLine` (`rts` stubs — real behaviour still TODO, see §5).

### 2. Cursor position tracking — `CalcCurPos`
`V.CurPos` (linear text-map cell) is what `PutGlyph` writes at. New helper
`CalcCurPos` (`vtio.asm` ~1586) = `V.CurRow*V.WWidth + V.CurCol`, carry
clear.  Called from `CurXY / CurRght / CurLeft(EraseChar) / CurUp / CurDown
/ Retrn` and `clrline` (post-scroll fix — was off by `V.WWidth`).
`CurDown` given its own non-scroll body (`CDmv@`), still routes to `incrow`
for scroll-at-bottom.

### 3. DSS access from grfdrv — slot 5 + the term table
grfdrv reads the calling terminal's device static storage (DSS) through
**MMU slot 5 ($A000)**, mapped by `SetBlkC2C3`.  Safe as one 8K block:
`V.Last = 250`, `F$SRqMem` is 256-byte-page aligned, 256 | 8192.  Build
assert in `wildbits_vtio.d` guards `V.Last > 256`.
- `gr.TermSz` 4 → **8** (index math = `lslb lslb lslb`).  Row:
  `T.Flags T.Block T.StatPtr(2) T.VBlk T.grU5(2) T.Unused`.
- `InitTerm` caches `T.VBlk` (block #, one-time `<D.SysDAT` P$DATImg walk)
  and `T.grU5` (= `$A000 | (T.StatPtr & $1FFF)`).
- `SetTermGrfPtrs` copies `T.Block→gr.TermBlk`, `T.VBlk→gr.VBlk`,
  `T.grU5→gr.U5`, `T.StatPtr→gr.VStaStorU` — no DAT walk.
  `SetThisTermGrfPtrs` = derive the row from `V.TermID,u`, fall through.
- `SetBlkC2C3` ends `ldu >gr.U5` → handlers index `V.xxx,u`.
- Fixed three `lslb lslb` (→ ×8) in `SwitchTerm`; `WriteCharShadow`
  `gr.DATImg+2`→`+6`; `ScrollShadow` still `+4` — SHOULD be `+6` (latent).

### 4. GF.Write dispatch removed — flat FuncTbl ops
`GrfWrite` (the `gr.WOp` sub-dispatch) is gone.  FuncTbl now:
`0-9` stock, `10 EraseLine  11 ErEOLine  12 ErEOScrn  13 PSGInit
14 PSGBell  15 PSGOff  16 GFCell  17 GFClrScrn  18 GFBlank  19 GFInitDisp
20 GFPal  21 GFBmEnable  22 GFBmFree  23 GFBmPalet`.
- grfdrv handlers `GFCell/GFClrScrn/GFBlank/GFInitDisp/GFPal/GFBm*` +
  `GFBmX` + shared `GWRet`, after `PSGOff` in `grfdrv256.asm`.  Ported
  near-verbatim from `grfdrv256.asm~` (`GWCell/GWBlank/GWInitDisp/GWPal/
  GWBmReg`); `GFClrScrn` is new (reads dims from DSS, mirrors `ErEOScrn`).
- vtio: deleted `BufCell` (dead) / `FillCells` / `CallWrite`; added
  `PutCell` (single-cell → `GF.Cell`).  Rewrote `InitDisplayMem`,
  `BlankTermText`, `ClrScrn`, `EraseChar`, `ChgPal`, the 3 bitmap SS
  sites, `dbgwrite` to `ldb #GF.xxx / lbsr CallGrfDrvNoPD`.
- `defs`: removed `WO.* WP.* WB.*`; `gr.WOp` kept as a dead reserved byte.
- Promoted out-of-range `bne AlreadyOpen` / `bcs InitError` in `InitTerm`
  to `lbne`/`lbcs` (pre-existing, surfaced once codegen ran).

### PSG / bell
`InitPSG` → `GF.PSGInit`; `BellTone` → `GF.PSGBell` (fire-and-forget, no
`F$Sleep`, `D.SndPrcID` unused); `HandleSound`/`sndoff` → `GF.PSGOff`.
`$07` in the output stream now runs `Bell` (was a `rts` stub).

## 5. Still TODO (functional, not blocking assembly)

- **The boot hang** (see below).
- `InsLine` / `DelLine` ($1F 30/31) are `rts` stubs — real row-memmove
  grfdrv ops still to write (model on `ScrollLive`/`GWScroll`).
- `ScrollShadow` `gr.DATImg+4` → `+6`.
- Stale comments mentioning "GF.Write" / "WO.*" (cosmetic).
- `ChgForePal` byte order assumed BGRA (`gr.WOff`=B/G, `gr.WCount`=R/A) —
  verify against the Vicky text LUT format when palette actually works.

## 6. Debugging the boot hang — starting points

**Breadcrumb convention:** poke a byte to `$1200`-`$12FF` (the `F256Gfx`
page, always mapped), read it back from an emulator memory dump.  In use:
`$1203-04` InitGrfDrv, `$12DC-DF` SS.Open, `$12E0-E1` TermTerm,
`$12E4-E7` SwitchTerm, `$12EB-EF` BlankTermText, `$12F0-F8` InitTerm.
Free: `$1205-$12DB`.

**Suspects, roughly in execution order:**
1. `GF.InitDisp` (`GFInitDisp`, `grfdrv256.asm`) — runs from
   `InitDisplayMem` during `Init`.  Gamma ramp, `gr.PalBuf`→text LUTs,
   font-block CpyBlk, then `SetBlkC2C3` + blank $C2/$C3.  The font-block
   MMU poke (`gr.DATImg+6`, `MMU_SLOT_3/4`) and `CpyBlk` of `gr.WCount`
   bytes are the risky parts.  `gr.WCount` is 0 if the font `F$Link`
   failed (defensively cleared at `InitDisplayMem` top) → font copy
   skipped.
2. `GF.ClrScrn` (`GFClrScrn`) — the "initial screen clear".  Reads
   `V.WHeight/V.WWidth/V.FBCol/V.TermLive` from the DSS (U = `gr.U5`).
   **Check `gr.U5`/`gr.VBlk`/`gr.TermBlk` are valid when this runs** —
   `ClrScrn` calls `SetThisTermGrfPtrs` (needs `V.TermID,u` correct).
   If the DSS map is wrong, dims are garbage → fill loop still terminates
   (capped 4800) but writes to the wrong place.
3. The erase family (`GF.EraseLine / ErEOLine / ErEOScrn` +
   `EraseLineCore`) — first exercised when the shell prints its prompt /
   wraps a line.  `ErEOScrn`'s `l@` loop uses `bge` on `V.WHeight,u`.
4. `SetBlkC2C3` + `gr.U5`: it now ends `ldu >gr.U5` and returns via
   `puls cc,d,x,pc`.  If `gr.U5` is 0/stale, slot 5 maps block 0 (globals
   aliased at $A000) — harmless unless a handler reads/writes $A000.
5. The Flip1/Flip0 round trip: `CallGrfDrvNoPD` → `CallGrfDrv2` builds a
   frame on `D.CCStk`, `jmp [D.Flip1]`; handler ends `jmp >GrfMod+SysRet`
   → `jmp [D.Flip0]`.  A corrupt `gr.DATImg` at flip time, or a handler
   that never reaches `SysRet`, hangs here.

**Bisection:** stub a handler to `jmp >GrfMod+SysRet` (no-op) and see how
much further it boots.  Start with `GFClrScrn`, then `GFInitDisp`.

**Files:** `level2/wildbits/modules/vtio.asm`,
`level2/wildbits/cmds/grfdrv256.asm`, `defs/wildbits_vtio.d`.
Reference (older, more complete GF.Write monolith):
`level2/wildbits/cmds/grfdrv256.asm~` (a copy of the
`origin/wild-grfdrv-screens` version).
Session plan with full edit list:
`~/.claude/plans/hi-claude-picking-back-jiggly-waffle.md`.

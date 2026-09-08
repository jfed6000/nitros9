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
- `SS.DfPal` (`SSDfPal`) and `SS.FntLoadF` (`SSFntLoadF`) still use the
  original raw `F$MapBlk`-into-`D.SysPrc` mechanism instead of `CallGrfDrv`.
  Real, unfixed, not currently reachable on the boot path.
- `InsLine` / `DelLine` are still `rts` stubs.
- `SS.DevNm` is unimplemented in vtio; Shell+ calls it and handles the error
  gracefully.
- The known-latent scroll item above (the colour-plane last row).
- `GFInitDisp` is a bare `rts`, but `GF.InitDisp` (19) is still a live
  `FuncTbl` entry.

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

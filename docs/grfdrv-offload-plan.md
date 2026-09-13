# Moving vtio work into grfdrv256 — implementation plan

Written 2026-09-13 for a fresh session.  Branch `wb/multiterm`, baseline commit
`735713c7` (switching and `TermTerm`'s fall-back already moved: `GF.Switch`,
`GF.TermGone`; K2 build tested on the board by the user, "looks good").

**Line numbers below are as of `735713c7`.  Find code by label, not by line.**

The history of everything referenced here is in `docs/wildbits-vtio-rewrite.md`
(newest sections at the end of its first half: `1B 21` Select, `GF.Switch`,
`GF.TermGone`).

---

## Why

The Level 2 bootfile has a hard ceiling.  `recipes/wildbits/wildbits.mak`
fails the build when `bootfile` passes **32,256 bytes** (`$7E00`, the
`$8000-$FDFF` window).  vtio is in the bootfile; grfdrv256 is not — vtio loads
it from CMDS with `F$NMLoad` and reaches it through its own blocks, so grfdrv
code costs no bootfile or system-map space.  grfdrv's own limit is 8K: past
that, `InitGrfDrv` maps the module's second block into slot 7 instead of the
kernel and interrupts during grfdrv break (see `docs/roadmap.md`).

| as of `735713c7` | bytes |
|---|---|
| `vtio` | 4,229 |
| `grfdrv256` | 2,058 |
| bootfile modules (unpadded, jr2) | 31,613 |
| margin to 32,256 | **643** |

This plan removes roughly 300 more bytes from vtio: margin to about 940.

---

## Ground rules for the session

**Build (jr2):**

```
cd recipes/wildbits/l2
export NITROS9DIR=/home/magnus/projects/wild/multiterm/nitros9
make PLATFORM=jr2 COCO_SHELF=/home/magnus/projects/coco-shelf/ ; echo exit=$?
```

- `NITROS9DIR` must be **exported**, and check the exit status — otherwise the
  disk silently is not rebuilt and MAME boots the old image.
- **`.mods` is shared between `PLATFORM=jr2` and `k2`** and make does not
  rebuild on a platform change.  `krnp2.asm` assembles differently per platform
  (its uncommitted more-memory map is `IFNE k2`).  Before building for the other
  platform: `rm .mods/krnp2 bootfile`.  Tell: `.mods/krnp2` is 3,248 bytes for
  jr2, 3,290 for k2; in MAME a K2 kernel shows `T.Block` values above `$3F`.
- `level2/modules/kernel/krnp2.asm` carries a **deliberately uncommitted**
  change.  Commit by explicit path only; never `git add -A` / `commit -a`.
- The `lwasm` on this machine (`coco-shelf/bin/lwasm`) is a wrapper that
  appends `--map=<basename(out)>.map --list=<basename(out)>.list` **relative to
  the current directory**.  Assembling by hand from the repo root drops
  `.list`/`.map` files there.  After `make`, use `recipes/wildbits/l2/vtio.list`
  and `grfdrv256.list`.

**Measure after every step** (from `recipes/wildbits/l2`):

```
stat -c '%s %n' .mods/vtio .mods/grfdrv256 .mods/krnp2 .mods/krn bootfile
t=0; for m in krnp2 ioman init scf vtio keydrv_ps2 term bannerfont palette SOLdrv fSOL wizfi wz wz0 wz1 wz2 wz3 vt vt1 vt2 vt3 vt4 vt5 vt6 vt7 vt8 mousedrv_ps2 rbf rbsuper llwbsd rbmem dds0 s0 s1 f0 f1 c0 c1 clock clock2_wildbits krn; do t=$((t+$(stat -c%s .mods/$m))); done; echo "modules=$t margin=$((32256-t))"
```

(The module list is jr2's `BOOTMODS`; k2 has `keydrv_k2` instead of
`keydrv_ps2`.)  `.mods/krn` must stay 4,096.

Routine sizes from a listing (labels in the fixed column):

```
python3 - vtio.list <<'EOF'
import re,sys
L=open(sys.argv[1],errors='replace').read().split('\n'); labs=[]; end=None
for ln in L:
    m=re.match(r'^([0-9A-F]{4})\s[^(]*\([^)]*vtio\.asm\):(\d{5}) {9}([A-Za-z_][A-Za-z0-9_.$]*)\b',ln)
    if m and m.group(3)!='eom': labs.append((int(m.group(1),16),m.group(3)))
    m2=re.match(r'^\s*([0-9A-F]{4})\s[^(]*\([^)]*vtio\.asm\):\d{5} {9}eom\b',ln)
    if m2: end=int(m2.group(1),16)
labs.append((end,'<eom>'))
for (a,n),(b,_) in zip(labs,labs[1:]): print(f'{a:04X} {b-a:4d} {n}')
EOF
```

**MAME (`wbjr2`, 512K RAM, PS/2 keyboard):**

```
S=<scratch dir>; cp l2_wildbitsjr2.dsk $S/t.dsk && truncate -s 134217728 $S/t.dsk
cd nitros9/mame && WB_KEYS="..." ./mame wbjr2 -skip_gameinfo -hard $S/t.dsk \
    -nothrottle -seconds_to_run 40 -video none -sound none > $S/t.log 2>&1
awk '/=== MULTITERM/{f=1} f' $S/t.log | grep "gr: TermCnt\|D.KbdSta\|TERM [0-9] flags\|TXT.*dd:"
awk '/=== MULTITERM/{exit} {print}' $S/t.log | grep "dd:\|ERROR"    # live screen
```

- Pad **up** to 128 MiB, never down.  Several runs in parallel on separate disk
  copies work.
- `WB_KEYS` items split on `;`; only ~7 characters survive per item, so type
  literals in 4-6 character chunks 10 frames apart (`1200:shel;1210:l i=/;...`).
  Shifted `> < & | !` work.
- The dump at exit prints GrfMem (`LiveTerm`, `TermCnt`, `SwitchReq`, re-entry
  counter), each terminal's table entry and statics, its buffer text, bitmap
  control registers, graphics CLUT sums, and per-terminal `T.CLUT0-3` sums.
- Three-terminal setup used for regressions:
  `1200:ini;1210:z /v;1220:t1;1230:enter;1350:shel;1360:l i=/;1370:vt1&;1380:enter;1500:ini;1510:z /v;1520:t2;1530:enter;1650:shel;1660:l i=/;1670:vt2&;1680:enter`
  then `1900:alt-right` etc.
- Regression set that passed at `735713c7` (expected end state):

| keys after setup | expect |
|---|---|
| Alt+Right ×1 / ×2 / ×3 | `LiveTerm` `$01` / `$02` / `$00` |
| Alt+Left ×1 | `$02` (wrap) |
| no setup: `shell i=/vt1&`, `shell i=/vt2&`, Alt+Right, `ex` | `$00`, `TermCnt=2`, `/vt2` intact |
| `iniz /vt1`, `shell i=/vt1&`, `display 1b 21 >/vt1` | `$01` |
| …then on `/vt1`: `display 1b 21 >/term` | `$00` |
| no setup: `display 1b 21`, then `display 1b 21 >/vt2` | `$00`, `TermCnt=1`, no error |

---

## Facts already established — do not re-derive

**Calling grfdrv and getting results back**

- GrfMem is `$1100` in block 0, slot 0 in both vtio's and grfdrv's maps.  vtio
  loads `gr.b1-b5` / `gr.d1-d2` right before a call and can read any of GrfMem
  right after it returns.  Nothing can change those bytes in between: the
  AltISR issues only `GF.Switch` and `GF.PSGOff` (neither touches `gr.b*`,
  `gr.d*` or `gr.PDRGS`), and a driver call in system state is not preempted.
  **Keep it that way** — an IRQ-issued op must never use the parameter block.
- `gr.b1` = `GF.TermGone`'s id.  `gr.b2-b5`, `gr.d1-d2` are shared by the ops
  documented in `defs/wildbits_vtio.d` above them.  Last GrfMem variable is
  `gr.b5` at `$119D`.
- `CallGrfDrv` (vtio, needs `Y` = path descriptor) stores the caller's
  register-stack address in `gr.RGSADR`, copies `R$Size` bytes into `gr.PDRGS`
  and 16 bytes of the caller's DAT image into `gr.PDAT`
  (`defs/wildbits_vtio.d:300-302`).  `CallGrfDrvNoPD` fills none of them.
- This build does **not** define `H6309` (`ldb #R$Size/2` assembles `C6 06`):
  `R$CC 0, R$A 1, R$B 2, R$DP 3, R$X 4, R$Y 6, R$U 8, R$PC 10, R$Size 12`.
- **Nothing copies `gr.PDRGS` back today.**  grfdrv's `GSMouse`/`GSDScrn` write
  into it and it goes nowhere; `GetABXYU`/`PutABXYU` in grfdrv256 are empty
  labels.  Item 3 adds the copy-back.
- Return path: `SysRet` does `tfr cc,a` and loads `X` from `gr.Stack`; the
  kernel's `R.Flip0` does `tfr x,s / tfr a,cc / rts` (`krn.asm:145-147`).  So
  **`B` and carry come back as grfdrv left them**; `A` and `X` do not; `Y` does
  but do not rely on it; `U` is restored by `CallGrfDrv2`.  An op reports errors
  with `B` + carry and needs nothing else.
- grfdrv is **not** interrupt-masked while it runs, **can** make `os9` calls
  (kernel `MapGrf` path), and **cannot sleep**.  An op that masks must
  `pshs cc` / `puls cc` before `SysRet`, because `SysRet` hands grfdrv's CC back
  to the caller.

**Inside grfdrv**

- `SetBlkC2C3` maps `$C2`/`$C3` at slots 1/2, `gr.TermBlk`/`+1` at slots 3/4
  (`$6000`/`$8000`), `gr.VBlk` at slot 5, and loads `U` from `gr.U5` — the
  terminal's statics seen through slot 5.  **That `U` is an alias**: never store
  it anywhere a system-map address is expected (`D.KbdSta` takes `T.StatPtr`).
  vtio's `SetThisTermGrfPtrs` / `SetTermGrfPtrs` aim those `gr.*` pointers
  before a call.
- Every `MMU_SLOT_n` write in grfdrv is mirrored into `gr.DATImg` (see
  `SetBlkC2C3`, `GMapAddr2Blk`); `InitGrfDrv` points the kernel's task-1 image
  at `gr.DATImg` (`vtio.asm` `setupgrfdrv`/`store7`).  Keep new slot writes in
  step the same way.
- `PushCore`/`PullCore` are the callable bodies of `GF.PushBuf`/`GF.PullBuf`
  (exit `U` = `gr.U5`); `GSEnter`, `GSTermPtrs`, `GSCalcPos` are shared helpers.
  Split other op bodies the same way when an op needs to call one.
- New grfdrv code goes **after `ErEOScrn`**: `ErEOLine`/`ErEOScrn` reach
  `EraseLineCore` with a short `bsr`.
- Adding a `FuncTbl` entry does not move GrfMem.  Next free op number: **25**.
  Put the `GF.*` equate next to its siblings in `defs/wildbits_vtio.d`
  (an equate reserves nothing; Level 1 is unaffected — multiterminal and grfdrv
  are Level 2 only).
- grfdrv's `DoFontGetSet` (`GF.GSFntChar`/`GF.SSFntChar`) stores debug values at
  `$11A0-$11B3`, `$12B0`, `$12C0` (`grfdrv256.asm:357-392`).  Harmless today
  because GrfMem ends at `$119D` — **remove them before adding any GrfMem
  variable.**

**Breadcrumbs**

- The MAME dump reads only `$12E2-$12E7`, `$12EC`, `$12F5-$12F8`
  (`mame/src/mame/wildbits/wildbits_jr2.cpp:2799-2801`).

---

## Work items, in order

Each item is its own build → measure → MAME → doc section → commit.

### 1. Delete dead code and unread probes (vtio only) — ~110 bytes, no risk

| what | where (`735713c7`) | bytes | note |
|---|---|---|---|
| `dbgwrite` / `dbgdn` | end of vtio | 36 | no callers |
| `Log2Blk` | after `DispRegs` | 36 | no callers |
| `std $1208` | `InitGrfDrv`, after `store7` | 3 | nothing reads `$1208` |
| `sta $12E1` / `sta $12E0` and the `lda #'Q` | `Term` | ~8 | **keep `lda >gr.TermCnt`** — it sets the flags `bne TermEx` tests |
| `SSOpen` probes: `$12DC`, `$12DD`, `$12D5`, `$12D6`, `$12D7` (three places), `$12DE`/`$12DF` (two places) and the loads that exist only for them | `SSOpen` … `SSOpenNamed` | ~40 | **keep `$12D8-$12DA`**: that is the `/vtN` name `F$SLink` links (`ldx #$12D8`) |

Keep: `HandleKeySwtchTrm`'s `$12E4-$12E7`, `CallGrfDrvGo`'s `$12E2`/`$12E3`
re-entry counter, `BlankTermText`'s `$12EC`, `InitTerm`'s `$12F5-$12F8` — the
dump reads them.  Also update the stale comment blocks that list the removed
probes (`SSOpen`'s header, `Init`'s marker list).

Nothing else reads the removed addresses (checked: vtio, grfdrv256, Level 1/2
wildbits cmds, the MAME driver; only vtio's editor backup `vtio.asm~`).

**Verify:** full regression set.  `SSOpen` is the `/vt` factory path, so add a
run that opens `/vt`: `shell i=/vt&` (binds the first free id, `/vt1`), then
Alt+Right → `LiveTerm=$01`, `TermCnt=2`.

### 2. Sound chip setup into `GF.PSGInit` — ~85 bytes, low risk

**Today** (vtio): `Init` calls `InitSound` before `InitGrfDrv`.  `InitSound`
clears `D.SndPrcID`, sets `SYS_PSG_ST|SYS_SID_ST` in `SYS1` (`$FE01`), then
`bra InitCODEC`; `InitCODEC` sends ten register values with `SendToCODEC`
(codec at `$FE70`) and **falls through into `InitBELL`**, which stores `Bell`'s
address in `D.Bell`.  `InitPSG` (after `InitGrfDrv`) issues `GF.PSGInit`, which
silences the PSG at `$C4`.

**Move:** the `SYS1` update, the ten codec writes and `SendToCODEC` into
grfdrv's `PSGInit`, before or after the PSG silencing.  `$FE01` and `$FE70` are
in the fixed `$FExx` page, present in every map.  `SendToCODEC` is only called
from `InitCODEC`.

**Stays in vtio:** `clr D.SndPrcID` and `InitBELL` (`Bell` is vtio code).
`InitSound` becomes `clr D.SndPrcID` + `bra InitBELL` (or inline it).

**Behaviour change:** the codec is programmed after the keyboard and mouse
drivers are linked and grfdrv is loaded, instead of before.  Nothing known
depends on the order.  `SendToCODEC` busy-waits on the codec status bit; inside
grfdrv that runs unmasked, same as today.

**Verify:** MAME boots and the regression set passes; `display 07` rings
without hanging.  Audio (headphones, bell tone) can only be checked on the board.

### 3. Register copy-back routine (vtio) — prerequisite for item 5

Add to vtio, next to `CallGrfDrv`:

```
* CallGrfDrvRet - CallGrfDrv, then copy the caller's R$A..R$U back from
* gr.PDRGS so a grfdrv op can return values in the caller's registers.
* Entry as CallGrfDrv (B = GF.* op, Y = path descriptor).  B and carry
* (grfdrv's error) are preserved across the copy.  R$CC/R$PC are not
* copied: IOMan reports the error in R$CC.
```

Copy bytes `R$A` through `R$U+1` (offsets 1-9) from `gr.PDRGS` to
`[gr.RGSADR]`, preserving `B` and CC around the copy.  About 20 bytes.  Only
valid after `CallGrfDrv` (needs `Y` = path descriptor); an op that returns
values must be called this way, not through `CallGrfDrvNoPD`.  The grfdrv op
writes results into `gr.PDRGS` exactly as vtio writes a real register stack
(`ldx #gr.PDRGS / std R$X,x`), including on error paths that return a value.

For values vtio itself needs (not the caller), return them in `gr.b*`/`gr.d*`
instead.

No behaviour change on its own; it lands with item 5 (or item 4's commit if
convenient — item 4 does not need it).

### 4. `SS.DfPal` into grfdrv — ~130-145 bytes, medium

**Today** (vtio `SSDfPal`, `DfPalMv`, `clutlookup`, `mapblock`, `clearblock`):
entry `R$X` = CLUT# 0-3, `R$Y` = address of 1K of palette data in the caller.
Copies it into this terminal's `T.CLUTn` in its 16K switch buffer — the second
block of the pair (`V.TermBufBlk+1`), offset `$1000+$400*n`, the same offsets
the CLUTs have in `$C1` — and, only if the terminal is live, into `$C1`.  No
buffer yet (`V.TermBufBlk=0`) → live CLUT only.  It uses `F$MapBlk` with
`D.Proc` swapped to the system process under mask, `F$Move` from the caller's
task, and `F$ClrBlk`.  **`R$X` is not range-checked** (indexes `clutlookup`).
`mapblock`/`clearblock` have no other callers.

**New:** vtio stub —

```
SSDfPal             lbsr      SetThisTermGrfPtrs
                    ldb       #GF.DfPal
                    lbsr      CallGrfDrv          B + carry come back
                    rts
```

(`CallGrfDrv`'s caller is `SetStat` with `X` = `PD.RGS,y`, `Y` = path
descriptor — check the dispatch still has `Y` intact at the stub.)

grfdrv `GFDfPal` (op 25 or next free):

1. Read `R$X` from `gr.PDRGS`; CLUT# above 3 → `E$IllArg`, carry, `SysRet`.
2. `SetBlkC2C3` → `U` = statics.  Save `V.TermLive,u` and whether
   `V.TermBufBlk,u` is non-zero **before** remapping slot 5 or slots 1/2.
3. Map the caller's source.  Caller slot = `R$Y >> 13`; its block is in
   `gr.PDAT` (2 bytes per slot, block number in the low byte — see
   `GMapAddr2Blk`).  Map it at slot 1 (`$2000`).  **If
   `(R$Y & $1FFF) + $400 > $2000` the 1K straddles into the caller's next slot:
   map that block at slot 2 (`$4000`).**  Straddling out of caller slot 7 →
   error.  Source = `$2000 + (R$Y & $1FFF)`.  Mirror each slot write into
   `gr.DATImg`.
4. If there is a buffer: destination `$8000 + $1000 + $400*n` (slot 4 is
   `gr.TermBlk+1` after `SetBlkC2C3`).  `CpyBlk` (`U` = source, `Y` = dest,
   `D` = count) `$400`.
5. If live: map `$C1` at slot 3 (`$6000`), destination `$6000 + $1000 + $400*n`
   (CLUT3 ends at `$7FFF` — no dead zone), copy again.
6. `clrb`, `SysRet`.

Delete vtio's `DfPalMv`, `clutlookup`, `mapblock`, `clearblock`.

**Note:** `GF.GSFntChar`/`GF.SSFntChar` have the same single-block limitation
for their 8 bytes (`GMapAddr2Blk` maps one block).  Out of scope; note it.

**Verify:**
- `shellbg` (no arguments) issues `SS.AScrn` and `SS.DfPal` and was the
  bitmap test in the rewrite doc (2026-09-09 sections).  Run it on live `/term`,
  and on `/vt1` after Alt+Right, **before and after** the change on the same
  disk contents; the dump's graphics CLUT0-3 sums (live) and each terminal's
  `T.CLUT0-3` sums must match between the two builds.
- Background terminal: `shellbg` on `/vt1`, Alt+Left back to `/term` before it
  finishes is racy; instead run it on `/vt1`, switch back, and check `/term`'s
  live CLUT sums did not change while `/vt1`'s `T.CLUT` sums did.
- Straddle: no existing command controls where its buffer lands.  Use a
  throwaway test command (not committed) whose palette data sits at data offset
  `$1E00` so it crosses an 8K boundary, and compare the CLUT sum against the
  same data placed mid-block.
- Board: a background image with its palette on two terminals, switching back
  and forth.

### 5. `SS.AScrn` into grfdrv (uses item 3) — ~80 bytes, medium

**Today** (vtio `SSAScrn`): entry `R$Y` = bitmap# 0-2, `R$X` = screen type
(0 = 320x240 → 10 blocks, 1 = 320x200 → 8 blocks).  If `V.BMxBlk` is already
non-zero → `E$WADef` **and return that block in `R$X`**.  Else `F$AlHRAM`
(`E$MFull` on failure), store `V.BMxBlk` = block and `V.BMxCl_En` = 1 (the
mirror pair `PullBuf` programs on every switch), return the block in `R$X`,
and — only if live — issue `GF.BmEnable` with `gr.b2` = bitmap#, `gr.b3` = 1,
`gr.d1` = physical address from vtio's `Blk2Addr`.  **`R$Y` is not
range-checked** (indexes the `V.BM0Cl_En` pairs).  `Blk2Addr` has no other
vtio caller.

**New:** vtio stub —

```
SSAScrn             lbsr      SetThisTermGrfPtrs
                    ldb       #GF.AScrn
                    lbsr      CallGrfDrvRet       R$X comes back, B + carry too
                    rts
```

grfdrv `GFAScrn`:

1. Bitmap# from `gr.PDRGS` `R$Y+1`; above 2 → `E$IllArg`.
2. `SetBlkC2C3` → `U`.  Existing `V.BMxBlk` → write it to `gr.PDRGS` `R$X`,
   `E$WADef`, carry, `SysRet` (the copy-back still runs).
3. `os9 F$AlHRAM` from grfdrv (allowed; stock CoCo grfdrv does it).  The
   kernel returns to grfdrv's map rebuilt from `gr.DATImg` — **re-run
   `SetBlkC2C3` or re-load `U` from `gr.U5` after the call** rather than
   assuming slot 5 survived.  Failure → `E$MFull`.
4. Store `V.BMxBlk`, `V.BMxCl_En` = 1; write the block to `gr.PDRGS` `R$X`.
5. If live: program the bitmap.  Split `GFBmEnable`'s body into a callable
   core (like `PushCore`) and call it with `gr.b2`/`gr.b3`/`gr.d1` loaded;
   grfdrv already has a `Blk2Addr` (near `PullBuf`, `A` = block, `B` = 0 →
   `D`).
6. `clrb`, `SysRet`.

Delete vtio's `Blk2Addr` if nothing else uses it by then.

**Verify:** `shellbg` on `/term` and on `/vt1`: the dump's `V: BM0/1/2
ctl/blk` per terminal, the decoded `BM0/1/2` control registers and the
physical block sums `$30-$3F` must match a pre-change run.  Run it twice on the
same terminal for the `E$WADef` path (`drawtest` tolerates `E$WADef`:
`drawtest.asm` after its `SS.AScrn`).  Board: background images on two
terminals, switching.

---

## Considered and not planned

| candidate | why not (now) |
|---|---|
| `InitDisplay`'s register programming (~35 bytes) | the mirror must still be seeded in vtio before `InitTerm`; a `GF.InitDisp` was deleted once for writing the text LUTs to the wrong block |
| `SetWin`, `ChgFont`, `SSDScrn`, `SSPScrn` "mirror + live register" handlers (~160 total) | each is small; stubs that load `gr.*` eat most of it — maybe 60 net |
| `InitTermStatic` (154) | copies the live console's statics into the new one: needs two terminals' statics mapped at once, and `SetBlkC2C3` maps one via slot 5 |
| GetStats (`GSDScrn` etc.) | 10-25 bytes each; not worth a stub even with copy-back |
| `PutGlyph` / line wrap / scroll / `UpdateLiveCursor` | per-character hot path; the direct grfdrv entries do not map statics, so it would become a full `GF.*` op per character |

**Must stay in vtio:** `Read` (sleeps), `SSOpen` (process swap around
`F$SLink`, replaces `V$DESC`), `SS.FntLoadF` (blocking file I/O — deliberately
kept in the driver), `InitKeyboard`/`InitMouse`/`Term` (link/unlink modules),
`InitGrfDrv` and the `CallGrfDrv*` plumbing, the escape parser and
`GetStat`/`SetStat` dispatch.

## grfdrv-side cleanup (no bootfile effect; keeps grfdrv away from 8K)

- grfdrv's `GSDScrn` and `SSDScrn` (ops 3 and 6) are unused — vtio has its
  own — and read Vicky registers back, which the driver no longer does.  Keep
  the `FuncTbl` slots (numbering) pointing at a stub that returns
  `E$UnkSvc`.
- Check whether grfdrv's `GSMouse` (op 2) is issued anywhere; vtio has its own.
- Empty `GetABXYU`/`PutABXYU`, unused `MMUKrnVars`, placeholder `Term` op.
- `DoFontGetSet`'s debug stores (see facts above).

## Expected result

| after item | vtio | margin (approx.) |
|---|---|---|
| baseline | 4,229 | 643 |
| 1 | ~4,120 | ~750 |
| 2 | ~4,035 | ~835 |
| 3 | ~4,055 | ~815 |
| 4 | ~3,915 | ~955 |
| 5 | ~3,835 | ~1,035 |

Estimates from listing sizes minus stub sizes; measure each step.

## Per-item checklist

1. Edit; build jr2 (exported `NITROS9DIR`, check exit, `.mods/krnp2` is 3,248).
2. Measure `vtio`, `grfdrv256`, module total, margin; `.mods/krn` 4,096.
3. Listing: new `FuncTbl` entry resolves to the new op; stub emits the right
   `ldb #op`.
4. MAME: the item's own tests plus the regression set; grfdrv re-entry counter
   0 in every run.
5. Add a dated section to `docs/wildbits-vtio-rewrite.md` and update its status
   block.
6. Commit only the files changed (by path); leave `krnp2.asm` alone.
7. K2: `rm .mods/krnp2 bootfile`, build `PLATFORM=k2`, board test.

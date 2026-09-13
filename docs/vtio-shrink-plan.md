# Shrinking vtio further — implementation plan

Written 2026-09-13 for a fresh session.  Branch `wb/multiterm`, baseline commit
`972356b7`; the code is as of `07a6f4a4`.  The previous plan,
`docs/grfdrv-offload-plan.md`, is finished: all five items are done in MAME, and
the user tested the K2 build on the board ("K2 looks good").

**Find code by label, not by line number.**  Line numbers go stale after the first edit.

History for everything referenced here is in `docs/wildbits-vtio-rewrite.md`.
Its newest sections, at the end of the first half, are the four written
2026-09-13 for the previous plan.

---

## Why, and how far it can go

The Level 2 bootfile must stay at or below **32,256 bytes**
(`recipes/wildbits/wildbits.mak`).  vtio is in the bootfile; grfdrv256 is loaded
from CMDS and costs no bootfile space.

| as of `07a6f4a4` | bytes |
|---|---|
| `vtio` | 3,795 |
| `grfdrv256` | 2,408 |
| bootfile modules, jr2 / k2 | 31,179 / 31,095 |
| margin to 32,256, jr2 / k2 | **1,077** / 1,161 |

Where vtio's bytes go (routine sizes from `recipes/wildbits/l2/vtio.list`):

| bytes | what | movable? |
|---|---|---|
| 1,274 | Write path: glyph painting and line wrap 244, escape parser and tables 331, escape handlers 699 | parser and handlers yes (item 3); glyph painting parked |
| 527 | graphics GetStat/SetStat handlers and their dispatch | yes (item 2) |
| 492 | terminal setup and teardown: `InitTerm` 178, `InitTermStatic` 154, `TermTerm` and helpers 129, `BlankTermText` 31 | mostly (item 4) |
| 189 + 88 + 80 | `InitGrfDrv`, `InitKeyboard`/`InitMouse`, `Term` | no |
| 187 | `CallGrfDrv*` plumbing and `SetTermGrfPtrs` | no |
| 188 | `SS.FntLoadF` | not into grfdrv: it blocks (see "Must stay") |
| 145 | `SSOpen` (the `/vt` path) | no |
| 133 + 80 | AltISR, `Read` | no |
| 80 | `InitDisplay` | yes (item 5) |
| 39 | `SSDMAFill` | delete (item 1) |

**The floor.**  What cannot leave vtio adds up to roughly 1,550 bytes:
- module header and name strings, AltISR, `Init`, linking the keyboard and mouse drivers;
- `InitGrfDrv`, the `CallGrfDrv` plumbing, `Term`, `Read`;
- a small GetStat/SetStat front end with `SS.SSig`/`SS.Relea`;
- `SSOpen`, `SS.FntLoadF`, the `D.Bell` target;
- a few hundred bytes of terminal setup;
- a stub `Write`.

Reaching it also means moving the printable-glyph path, which is parked (see
below).  This plan targets about **1,900**.

**grfdrv's own ceiling.**  grfdrv256 must stay inside one 8K block.  Past that,
`InitGrfDrv` maps the module's second block into slot 7 instead of the kernel,
and interrupts that arrive while grfdrv runs break (see `docs/roadmap.md`).  This
plan adds roughly 1,900 bytes, to about 4.3K.  Check the size after every item.

---

## Ground rules for the session

**Build (jr2):**

```
cd recipes/wildbits/l2
export NITROS9DIR=/home/magnus/projects/wild/multiterm/nitros9
make PLATFORM=jr2 COCO_SHELF=/home/magnus/projects/coco-shelf/ ; echo exit=$?
```

- `NITROS9DIR` must be **exported**, and check the exit status.  Otherwise the
  disk silently isn't rebuilt and MAME boots the old image.
- **`.mods` is shared between `PLATFORM=jr2` and `k2`.**  Before building for
  the other platform, run `rm .mods/krnp2 bootfile`.  How to tell which one is
  there: `.mods/krnp2` is 3,248 bytes for jr2 and 3,290 for k2.
- `level2/modules/kernel/krnp2.asm` carries a **deliberately uncommitted**
  change.  Commit by explicit path only; never `git add -A` / `commit -a`.
- The `lwasm` wrapper drops `.list`/`.map` files into the current directory.
  After `make`, use `recipes/wildbits/l2/vtio.list` and `grfdrv256.list`.
- **Save the previous build's disk before each item**, e.g.
  `cp l2_wildbitsjr2.dsk $S/base/`.  Every test below compares the old disk with
  the new one.
- A long branch to a label that moves out of range fails the assemble with
  `Byte overflow`.  Lengthen that branch and rebuild.

**Measure after every step** (from `recipes/wildbits/l2`):

```
stat -c '%s %n' .mods/vtio .mods/grfdrv256 .mods/krnp2 .mods/krn bootfile
t=0; for m in krnp2 ioman init scf vtio keydrv_ps2 term bannerfont palette SOLdrv fSOL wizfi wz wz0 wz1 wz2 wz3 vt vt1 vt2 vt3 vt4 vt5 vt6 vt7 vt8 mousedrv_ps2 rbf rbsuper llwbsd rbmem dds0 s0 s1 f0 f1 c0 c1 clock clock2_wildbits krn; do t=$((t+$(stat -c%s .mods/$m))); done; echo "modules=$t margin=$((32256-t))"
```

(For k2, use `keydrv_k2` instead of `keydrv_ps2`.)  `.mods/krn` must stay 4,096 bytes.

Routine sizes from a listing:

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

**MAME harness.**  The machine is `wbjr2` (512K, PS/2 keyboard); there is no K2
machine.  The scratch scripts from the last session are gone, so recreate them
from Appendix A.
- `run1.sh <dir> <name> "<keys>"` copies `<dir>/l2_wildbitsjr2.dsk`, pads it
  **up** to 128 MiB (never truncate down), runs it with `WB_KEYS`, and writes
  `<dir>/<name>.log`.
- Ten runs in parallel through `xargs -P 10` take under 20 seconds.
- `WB_KEYS` items are separated by `;`, and only about 7 characters survive per
  item.  Type literals in chunks of 4-6 characters, 10 frames apart.  Shifted
  `> < & | !` work, so `cmd >/vt1` exercises a background terminal without
  switching.
- The dump printed at exit includes:
  - `gr:` (`TermCnt`, `LiveTerm`), the grfdrv re-entry count, and each
    terminal's `V:` statics line;
  - `V: BM0-2` mirror pairs, `T.CLUT0-3` sums, buffer block sums, `T.TXT` rows;
  - the live screen text, `HW CURSOR`, `HW MCR`, decoded `BM0-2` registers,
    live `CLUT0-3` sums, `BLK $30-$3F` sums, the text LUT FG entries.
- **It does not print** `V.FBCol`, `V.Reverse`, `V.ScTyp` or the live colour
  plane.  Add those to `dump_multiterm()` in
  `mame/src/mame/wildbits/wildbits_jr2.cpp` before item 3.  Rebuild with
  `make SOURCES=src/mame/wildbits/wildbits_jr2.cpp -j12` from `mame/`; the
  `mame/` tree is untracked.

**Comparing builds.**  Expect differences you can ignore:
- statics addresses (`VStaStorU`, `D.KbdSta`, `T.StatPtr`, `gr.VBlk`), which
  move when vtio's size changes;
- buffer-block sums that include Shell+ banner timestamps;
- stale RAM in buffer blocks and in `T.CLUTn` a run never loaded (it begins
  `bootos9 `).

Everything else should be identical unless the item intends a change.

**Regression set** (Appendix A `tests.txt`); every item must pass it:

| test | expect |
|---|---|
| three terminals, Alt+Right ×1 / ×2 / ×3, Alt+Left ×1 | `LiveTerm` `$01` / `$02` / `$00` / `$02`, `TermCnt=3` |
| shells on `/vt1`, `/vt2`, Alt+Right, `ex` | `$00`, `TermCnt=2`, `/vt2` intact |
| `iniz /vt1`, `shell i=/vt1&`, `display 1b 21 >/vt1` | `$01` |
| …then on `/vt1`: `display 1b 21 >/term` | `$00` |
| `display 1b 21`, `display 1b 21 >/vt2` | `$00`, `TermCnt=1`, no error |
| `shell i=/vt&`, Alt+Right | `$01`, `TermCnt=2` |
| `display 07`, `echo ok` | `ok` printed |
| every run | grfdrv re-entry count 0 |

Graphics set (runs with `SECS=60`; Appendix B has the test commands): `shellbg` on
`/term`, on `/vt1` after Alt+Right, and `shellbg >/vt1`; `dftest`,
`dftest >/vt1`; `asctest`, `asctest >/vt1`.  Results as of `07a6f4a4`:
- `shellbg` on `/term`: `BM2 ctrl=$05` pointing at block `$34`.
- `asctest` on `/term`: `ERROR #054`.
- `asctest >/vt1`: `ERROR #052`.
- `dftest`: CLUT1 = CLUT3 = `$01FE00`.

---

## Facts already established — do not re-derive

**Calling grfdrv**

- GrfMem is `$1100` in block 0, slot 0 in both vtio's and grfdrv's maps.
  Parameters go in `gr.b1-b5`/`gr.d1-d2`, loaded right before the call.  The
  AltISR issues only `GF.Switch` and `GF.PSGOff`, and neither touches `gr.b*`,
  `gr.d*` or `gr.PDRGS`.  **Keep it that way.**
- `CallGrfDrv` (needs `Y` = path descriptor) stores `PD.RGS` in `gr.RGSADR`,
  copies the caller's 12 register bytes into `gr.PDRGS` and their 16-byte DAT
  image into `gr.PDAT`.
- `CallGrfDrvRet` does the same, then copies `R$A..R$U` back from `gr.PDRGS`,
  keeping `B` and carry.
- `CallGrfDrvNoPD` copies nothing.
- `R$CC 0, R$A 1, R$B 2, R$DP 3, R$X 4, R$Y 6, R$U 8, R$PC 10, R$Size 12` (no
  `H6309`).
- On return, `B` and carry are what grfdrv left, and `U` is restored by
  `CallGrfDrv2`.  `A`, `X` and `Y` are whatever grfdrv left.
  **vtio must save `Y` itself** around a call if it uses the path descriptor
  afterwards.
- SCF saves and restores `Y`/`U` around the driver's GetStat/SetStat
  (`ExecuteStatusRequest`, `pshs u,y` / `jsr b,x` / `puls y,u,pc`), and `Y`/`X`
  around `D$WRIT` (`CallWriteDriver`, `CallDeviceWrite`).  So vtio returning
  grfdrv's `Y` to SCF is safe.
- **grfdrv can make `os9` calls:** `GFAScrn`'s `F$AlHRAM` is the working
  example.  After the call, remap slot 5 and reload `U` with `lbsr SetBlkC2C3`,
  which keeps `D`, `X` and CC.  **grfdrv cannot sleep.**
- grfdrv is not interrupt-masked while it runs.  Mask around each run of MMU
  slot writes and their `gr.DATImg` mirror (the `pshs cc` / `orcc` /
  `puls cc` pattern in `GFDfPal`).

**Inside grfdrv**

- `SetBlkC2C3` maps `$C2`/`$C3` at slots 1/2, `gr.TermBlk`/`+1` at slots 3/4,
  `gr.VBlk` at slot 5, and loads `U` from `gr.U5`.  That `U` is an **alias**
  through slot 5; never store it where a system-map address is expected.
  vtio's `SetThisTermGrfPtrs` aims those `gr.*` pointers first.
- An op may remap slots 1-4 freely, as `GFDfPal` does.  `WriteCharLive`/
  `ScrollLive` recheck slots 1/2 against `$C2C3` and remap them if they differ;
  `WriteCharShadow`/`ScrollShadow` map slots 3/4 themselves.
- Every `MMU_SLOT_n` write is mirrored into `gr.DATImg` (2 bytes per slot, high
  byte 0).
- Reading caller memory: the caller's block for logical address `A` is
  `gr.PDAT+1+2*(A>>13)`.  `GFDfPal` shows both the one-block and the 8K-straddle
  case.
- The fixed I/O pages are visible in grfdrv's map, as shown by `PSGInit` writing
  `SYS1` `$FE01` and the codec `$FE70`.  Addresses: `TXT.Base` `$FFC0` (MCR,
  layers, cursor registers), mouse `MS_*` `$FEA0+`, `VIA0.Base` `$FEB0`,
  `DMA.Base` `$FEC0`.
- Direct-page system globals (`D.Proc`, `D.SndPrcID`, `D.TnCnt`, `D.KbdSta`) are
  in block 0, visible to grfdrv.  **Process descriptors and path descriptors
  are not**: anything touching `P$*` or `PD.*` stays in vtio.
- An op body that another op needs must be split into a callable core, because
  ops end in `jmp >GrfMod+SysRet`.  Examples: `PushCore`/`PullCore`, `BmEnCore`,
  `EraseLineCore`, `GSEnter`, `GSCalcPos`.
- Put new grfdrv code **after `ErEOScrn`**, because `ErEOLine`/`ErEOScrn` reach
  `EraseLineCore` with a short `bsr`.  The last two ops (`GFDfPal`, `GFAScrn`)
  sit just before `PSGInit`.
- Next free op number: **27**.  Put `GF.*` equates next to their siblings in
  `defs/wildbits_vtio.d`.  Adding a `FuncTbl` entry does not move GrfMem.
- grfdrv's `DoFontGetSet` stores debug values at `$11A0-$11B3`, `$12B0`, `$12C0`.
  Harmless while GrfMem ends at `gr.b5` (`$119D`); removed in item 2.

**The MAME dump reads** only `$12E2-$12E7`, `$12EC` and `$12F5-$12F8` of the
probe area.

---

## Work items, in order

Each item is its own build → measure → MAME → doc section → commit.

### 1. Delete `SSDMAFill` — about 44 bytes, no risk

`SSDMAFill` has no callers.  A search of the tree for `SS.DMAFill`/`DMAFill`,
outside `nitros9-priorversion` and `mame/`, finds only the two vtio sources.  It
is also broken:
- It reads the caller's control block at `R$X` through the **system** map.
- `lda DMF$DstAddrLow,x` is followed by `stb DMA_DEST_ADDR_L,y`, so the low
  address byte gets `B`.
- `stb DMA_DATA_2_WRITE` has no `,y`.  The equate is an offset
  (`DMA_STATUS_REG`), so it writes system address `$0001`.
- It starts the transfer before loading the parameters.

**Delete** `SS.DMAFill equ $B0`, the `DMF$*` equates, the SetStat compare/branch
and the routine.  If a DMA fill is ever wanted, rewrite it as a grfdrv
SetStat handler reading the control block through `gr.PDAT` (after item 2).
`level1/wildbits/modules/vtio.asm` has the same code; it is Level 1 and out of
scope, so leave it and mention it in the doc.

**Verify:** regression set.

### 2. Forward GetStat/SetStat to grfdrv — about 450 bytes, medium

The previous plan rejected moving "update the mirror, and the register if live"
handlers because each op needs a vtio stub that eats most of the saving.  One
op per *direction*, dispatching on the status code inside grfdrv, removes the
per-handler stubs and most of the 146 bytes of compare-and-branch dispatch.

**vtio after the change:**

```
GetStat             cmpa      #SS.EOF
                    beq       SSEOF
                    ldx       PD.RGS,y
                    cmpa      #SS.Ready
                    beq       SSReady
                    sta       >gr.b1              status code for grfdrv
                    lbsr      SetThisTermGrfPtrs
                    ldb       #GF.GetStt
                    lbra      CallGrfDrvRet
```

SetStat keeps `SS.Open`, `SS.SSig`, `SS.Relea`, `SS.Tone` (it shares
`BellTone` with `Bell`, which stays for `D.Bell`) and `SS.FntLoadF`.  Everything
else goes the same way to `GF.SetStt`.  Pass the code in `gr.b1`, not
`gr.PDRGS+R$B`: SCF's internal calls (`CallComStatus` issuing `SS.ComSt`) do not
put the code in the caller's `R$B` the way `I$GetStt`/`I$SetStt` do.  Store
`gr.b1` **before** `SetThisTermGrfPtrs`, which clobbers `A`.

Check whether `level2/wildbits/modules/vtio.asm` is ever assembled at Level 1
(`recipes/wildbits/wildbits.mak`, the `AFLAGS` include lines).  If it isn't,
the `IFGT Level-1` blocks in GetStat/SetStat are dead; otherwise keep the new
code inside them.

**grfdrv `GFGetStt` (27) and `GFSetStt` (28):** `lbsr SetBlkC2C3` (U = statics),
`ldx #gr.PDRGS`, scan a table of `fcb code / fdb handler-table` entries, then
`jmp` to the handler.  Handlers end with `jmp >GrfMod+SysRet`, as the existing
`GFDfPal`, `GFAScrn` and `DoFontGetSet` already do.  With `X = #gr.PDRGS` the
register offsets are the same ones vtio's handlers use with `X = PD.RGS`, so
most bodies port line for line.  An unknown code must give
`comb / ldb #E$UnkSvc`: SCF's `CallComStatus` tolerates exactly that error, and
`tmode`/`xmode` changing the pause/baud options depends on it.

| direction | code | handler after the move | notes |
|---|---|---|---|
| Get | `SS.ScSiz` | from `SSScSiz` | |
| Get | `SS.ScTyp` | from `SSScTyp` | returns `R$A` |
| Get | `SS.KySns` | from `GSKySns` | `V.KySns,u` |
| Get | `SS.Joy` | from `SSJoy` | **bug:** writes `R$X/R$Y/R$A` through `,u` (the statics), not the register stack.  Write `gr.PDRGS` |
| Get | `SS.Mouse` | from vtio's `GSMouse` | `MS_*` registers and `V.MSButtons` |
| Get | `SS.DScrn` | from vtio's `GSDScrn` | from the mirror |
| Get | `SS.FntChar` | grfdrv `GSFntChar` | already an op body |
| Get | `SS.Palet`, `SS.FBRgs` | from `SSFBRGs` | `GSPalet` is an empty label that falls into `SSFBRGs` today; keep that |
| Get | `SS.DfPal` | `clrb` | as today |
| Set | `SS.AScrn` | `GFAScrn` | already grfdrv |
| Set | `SS.DfPal` | `GFDfPal` | already grfdrv |
| Set | `SS.FntChar` | grfdrv `SSFntChar` | already an op body |
| Set | `SS.DScrn` | from vtio's `SSDScrn` | mirror + `MASTER_CTRL_REG_L/H` if live |
| Set | `SS.PScrn` | from `SSPScrn` | mirror + `VKY_LAYER_CTRL_0/1` if live |
| Set | `SS.Palet` | from `SSPalet` | mirror + `BmEnCore`-style core of `GFBmPalet` if live |
| Set | `SS.FScrn` | from `SSFScrn` | `os9 F$DelRAM` (8 blocks if `CLK_70` in `V.V_MCR+1`, else 10), then `SetBlkC2C3` again; clear the pair; `GFBmFree`'s body as a core if live |

Also, in grfdrv:
- Delete the unused op bodies `GSMouse` (2), `GSDScrn` (3) and `SSDScrn` (6).
  They read Vicky registers back, which the driver no longer does.  Point their
  `FuncTbl` slots at a shared `E$UnkSvc` stub so the numbering holds.
- Ops 4, 5, 25 and 26 become internal to the dispatcher; keep their table entries.
- Remove `DoFontGetSet`'s debug stores.
- vtio's `SSFntChar`/`GSFntChar`/`SSAScrn`/`SSDfPal` stubs go away.  Keep
  `SetThisTermGrfPtrs`, which other code uses.

**Verify:**
- The graphics set (Appendix B) on both disks: identical `BM0-2`, `V: BM`,
  CLUT and `BLK` lines.  Also `shellbgoff` if it issues `SS.FScrn`/`SS.DScrn`
  (read `level2/wildbits/cmds/shellbgoff.asm`).
- GetStat values.  Look for existing callers first (`level1/wildbits/cmds`,
  `level1/wildbits/tests/winfo.b09`).  Otherwise write a throwaway command
  that issues `SS.ScSiz`, `SS.ScTyp`, `SS.FBRgs`, `SS.DScrn` and `SS.KySns` and
  prints the returned registers in hex.  Compare its output on both disks, live
  and `>/vt1`, and after `display 1b 20 02 00 00 50 1e 01 00 00` (DWSet 80x30).
- Shell+ calls `SS.ScSiz` at startup, so a wrong value shows in every run.
- `tmode pause` then `tmode -pause`: no error.  That runs `SS.ComSt` through the
  forwarder.
- Regression set.

### 3. Control bytes and the escape parser into grfdrv (`GF.Ctrl`) — about 950 bytes, medium-high

**Design.**  vtio keeps painting printable characters exactly as today, through
the direct `WriteCharLive`/`WriteCharShadow` entries.  It also keeps the
escape-parameter collector, the few instructions at `Write` that store a
parameter byte and count `V.EscNeed` down.  vtio calls grfdrv's `GF.Ctrl` (op 29)
in three cases:
- a byte below `$20` arrives with no escape pending;
- the collector has just gathered its last parameter byte;
- a printable character wraps off the bottom row.

grfdrv owns the rest: `ChkESC`, `DCodeTbl`, `Esc1BTbl`/`Esc05Tbl`/`Esc1FTbl`,
the `Arm*`/`EscArm`/`EscScan`/`Disp*` plumbing and every handler.

Cost per byte:
- Printable text: unchanged.
- Parameter bytes: no call (today none either).
- Each control byte: one grfdrv call plus `SetBlkC2C3`.
- Scrolling output: a line ending CR LF at the bottom row cost 2 calls before
  (scroll, then erase the new line) and costs 2 after (CR, LF).  A line not at
  the bottom goes from 0 calls to 2.

**vtio front end** (sketch):

```
Write               tst       V.WriteState,u
                    beq       DefaultState
                    (store the byte at V.EscParms+V.EscCount, inc V.EscCount - unchanged)
                    dec       V.EscNeed,u
                    bne       WrNoCur             more to come: no call
                    bra       CtrlFwd             complete: grfdrv dispatches it
DefaultState        cmpa      #C$SPAC
                    bhs       PutGlyph
CtrlFwd             sta       >gr.b2              the byte (ignored when completing)
                    pshs      y                   path descriptor, for CF.SelP
                    lbsr      SetThisTermGrfPtrs
                    ldb       #GF.Ctrl
                    lbsr      CallGrfDrvNoPD
                    puls      y
                    lda       >gr.b1              CF.* result flags
                    (CF.Glyph: lda V.EscParms,u / lbra PutGlyph   - 1C literal)
                    (CF.Bell:  lbsr Bell                          - $07)
                    (CF.SelP:  ldx PD.RGS,y / lda R$A,x / ldx >D.Proc / sta P$SelP,x - 1B 21)
                    lbra      WrNoCur             carry clear
```

`PutGlyph`'s wrap at the bottom row becomes: store `V.CurRow` unchanged with
`V.CurCol = 0`, then `lda #C$LF` and `bra CtrlFwd`.  grfdrv's `CurDown` sees the
bottom row and takes the scroll path with column 0, exactly as `incrow` does
today.  A wrap that isn't on the bottom row stays in vtio with no call.
`UpdateLiveCursor` stays in vtio for the glyph path.

**grfdrv `GFCtrl`:**
1. `lbsr SetBlkC2C3`, then `clr >gr.b1`.
2. If `V.WriteState,u` is non-zero, the collector completed: do today's
   `EscCodeComplete` (clear `V.WriteState`, `jsr [V.EscHandler,u]`).
   `V.EscHandler` now holds grfdrv addresses; grfdrv's code is at a fixed
   `$C000`, so an address stored by one call is valid in the next.
3. Otherwise treat `gr.b2` as a control byte and do today's `ChkESC`.
4. Update the hardware cursor if live: a copy of `UpdateLiveCursor`, since
   `TXT.Base` is visible.
5. `clrb`, `jmp >GrfMod+SysRet`.

What each handler needs on the grfdrv side:
- **Already grfdrv ops, which need callable cores:**
  - `EraseLine` (`EraseLineCore`), `ErEOLine` (`ErEOLine2`), `ErEOScrn`;
  - `ClrScrn` (`GFClrScrn`), `EraseChar`'s `PutCell` (`GFCell`), `ChgPal` (`GFPal`);
  - `InsLine` (`GFInsLine`), `DelLine` and the scroll (`ScrollLive`/
    `ScrollShadow`, whose `jmp SysRet` endings need splitting).
- **`gr.b4` destination:** `SetWDest`'s choice for `GFCell`/`GFPal` becomes a
  small grfdrv helper, the same `V.TermLive`/`V.TermBufBlk` test.  Keep the
  "no buffer → refuse" guard that `SetShadowBlk` and `DoScroll` make.
- **Helpers to copy or reuse:** `CalcCurPos` (grfdrv's `GSCalcPos` does the same
  clamp and calculation), `CurHome`, `SetScreenSize` (vtio keeps its own for
  `InitTermStatic`), and `incrow`/`noscroll`/`clrline`.
- **Handled by vtio after the call:** `DWSelect` sets `gr.SwitchTerm`/
  `gr.SwitchReq` itself, but `P$SelP` is in a process descriptor grfdrv can't
  reach, so it sets `CF.SelP`.  `Do1C` sets `CF.Glyph`.  `$07` sets `CF.Bell`
  (vtio keeps `Bell`/`BellTone` for `D.Bell` and `SS.Tone`).

Define `GF.Ctrl` and the `CF.*` bits in `defs/wildbits_vtio.d`, and note next to
`gr.b1` that `GF.Ctrl` returns flags in it.  No new GrfMem variables.

**Delete from vtio:**
- `ChkESC` through `DelLine`, except `Bell`/`BellTone`;
- `EscCodeComplete`, `PutCell`, `SetWDest`, `DoScroll`;
- `CallScrollLive`/`CallScrollShadow`, `incrow`/`noscroll`/`clrline`;
- `CalcCurPos`, `CurHome`, `EraseLine`, if no vtio callers remain (check the listing).

`SetShadowBlk`, `SetScreenSize` and `UpdateLiveCursor` stay.

**Verify.**  Extend the MAME dump first (see ground rules).  Then run the same
`display` script on the old and new disks, once on live `/term` and once as
`>/vt1`, and diff: `T.TXT` rows, live screen text, `HW CURSOR`, `HW MCR`, text
LUT FG, buffer sums, `V:` lines incl. the new `V.FBCol`/`V.Reverse`/`V.ScTyp`/
colour-plane sum.  Codes to cover:
- Cursor: `0c`, `01`, `02 25 23`, `06`, `08`, `09`, `0a` (at the bottom row
  too), `0d`.
- Erase: `03`, `04`, `0b`.
- `05`: `05 20`, `05 21`, `05 22 41`, `05 23 01`.
- `1b`: `1b 20 02 00 00 50 1e 01 00 00` then `1b 20 04 00 00 50 3c 01 00 00`,
  `1b 32 03`, `1b 33 04`, `1b 60 01 ff 00 00 ff`, `1b 62`/`1b 63`, `1b 21 >/vt1`.
- `1f`: `1f 20`, `1f 21`, `1f 30`, `1f 31`.
- Literal: `1c 01`.
- Bell: `07`.

Also:
- `list` a file longer than a screen (for example `list /dd/sys/helpmsg`) on
  both disks, with identical text afterwards.
- Regression set.
- An unknown sub-code (`1b 7f`, `05 7f`, `1f 7f`) is ignored, and the next
  command works.

### 4. Terminal setup and teardown — a few hundred bytes, design first

Less certain than items 2-3: read the code again before committing to a split.

- **Stays in vtio:**
  - claiming the id and table entry, and `stu T.StatPtr`;
  - the `D.SysDAT` lookup that computes `T.VBlk`/`T.grU5` (the system DAT image
    isn't known to be in block 0);
  - `F$AlHRAM` for the buffer, which is small; `V.TermID`; `D.KbdSta`.
- **Candidate `GF.TermNew`:**
  - `InitTermStatic`'s defaults and the "inherit from the live console" copy;
  - the first-terminal / not-first branch (`gr.LiveTerm`, `T.Live`,
    `V.TermLive`), `PushCore`, `BlankTermText`, `inc gr.TermCnt`.
- **Why the copy is now possible:** it needs two terminals' statics at once.
  The previous plan rejected that because `SetBlkC2C3` maps only one statics
  block, but `GFDfPal` showed an op may map other blocks at slots 1-4.
  - Map the live terminal's statics (its table entry's `T.VBlk`) at a free
    slot, and rebase its `T.grU5` from `$A0xx` to that slot.
  - If both statics are in the same block, use slot 5 for both.
  - The live console is `D.KbdSta` today; `gr.LiveTerm`'s entry is the same
    terminal.
- **Candidate teardown:** fold `FreeBuf` (`F$DelRAM`), `ClearEntry` and
  `dec gr.TermCnt` into `GF.TermGone`; os9 calls from grfdrv are proven.  Keep
  vtio's ownership check (`cmpu T.StatPtr,x`).
- **Verify:** regression set, the graphics set, `iniz`/`deiniz` of `/vt1`
  repeatedly, and `shell i=/vt&` twice.  Also the three-terminal setup with
  different `1b 20` window sizes on `/term` first, since new terminals inherit
  width, height and colours.

### 5. `InitDisplay` into grfdrv — about 65 bytes, low risk

`Init` calls `InitDisplay` before `InitGrfDrv`, but nothing needs the display
registers before the first terminal's `InitTerm`.
- `InitTermStatic` already sets 80x60 and `SetScreenSize` for every terminal, so
  `InitDisplay`'s first three lines duplicate it.
- The first terminal skips `InitTermStatic`'s inherit copy (`D.KbdSta` equals
  `U`).  So its mirror comes only from `InitDisplay`'s `DispRegs` seed.

Move the seeding, the `$FFC0-$FFCF` programming and the cursor register setup
into `GF.InitDisp`.  Call it from `InitTerm`'s first-terminal branch after
`SetTermGrfPtrs`.  `DispRegs` moves with it.  The earlier `GF.InitDisp` was
deleted for writing the text LUTs to the wrong block; this one touches no LUTs.

**Verify:** boot on both disks: identical `HW MCR`, `HW CURSOR`, text LUT FG,
`V:` lines and screen.  Regression set.

### 6. Final squeeze — about 80 bytes, no risk

- **Long branches.**  At `07a6f4a4`, 23 long branches would fit short ones
  (about 30 bytes).  Rerun the scan after items 2-5 (Appendix C), shorten them,
  and rebuild.
- **Breadcrumbs** (about 55 bytes):
  - Put `HandleKeySwtchTrm`'s `$12E4-$12E7`, `BlankTermText`'s `$12EC`, and the
    `$12F5-$12F8` stores in `TermInited`/`AlreadyOpen`/`InitError` under
    `IFNE VTIODBG`, with `VTIODBG set 0` near the top of vtio.
  - **Keep `CallGrfDrvGo`'s re-entry counter (`$12E2`/`$12E3`)
    unconditional.**  It is the only detector for a real hazard, and the
    regression set checks it.
  - With the flag off, the dump's `breadcrumbs:` fields read zero; say so in the
    doc.

---

## Parked — not in this plan

| candidate | why parked |
|---|---|
| printable-glyph path into grfdrv (about 250 more bytes) | every printable byte would become a full op with `SetBlkC2C3` (two dozen instructions, masked slot writes) instead of today's direct entry, which skips remapping when `$C2`/`$C3` are already mapped.  Needs a throughput measurement first |
| `SS.FntLoadF` out of the driver (188 bytes) | reverses the decision recorded under "Asset loading" in `docs/wildbits-vtio-rewrite.md`: it blocks on file I/O, so it can't go to grfdrv, and an `assetload`-style command changes the API |
| `SSOpen`, `Read`, AltISR, `InitKeyboard`/`InitMouse`/`Term`, `InitGrfDrv`, `CallGrfDrv*` | must stay: `Read` sleeps; `SSOpen` swaps the process around `F$SLink`; the rest link, load or are the plumbing |

## Noticed while planning — not in scope

- `SSFntLoadF`'s module check is `cmpx #$87CD / bcc`, which accepts any file
  whose first word is at least `$87CD` (it should be an equality test).
- `shellbg` does `os9 F$Link` then `beq` (tests Z, not carry) before falling back
  to `F$Load`.  It may explain why `shellbg` on `/vt1` lands CLUT2 `$4BCA`
  against `$44E9` on `/term`, on both old and new builds.
- `level1/wildbits/modules/vtio.asm` carries the same broken `SSDMAFill`.

## Expected result

| after item | vtio (approx.) | jr2 margin (approx.) | grfdrv256 (approx.) |
|---|---|---|---|
| baseline | 3,795 | 1,077 | 2,408 |
| 1 | 3,750 | 1,120 | 2,408 |
| 2 | 3,300 | 1,570 | 2,850 |
| 3 | 2,350 | 2,520 | 3,800 |
| 4 | 2,100 | 2,770 | 4,050 |
| 5 | 2,035 | 2,835 | 4,120 |
| 6 | 1,955 | 2,915 | 4,120 |

Estimates are listing sizes minus stub costs; measure each step.

## Per-item checklist

1. Save the previous disk; edit; build jr2 (exported `NITROS9DIR`, check the
   exit status, `.mods/krnp2` is 3,248).
2. Measure `vtio`, `grfdrv256`, module total, margin; `.mods/krn` is 4,096;
   grfdrv256 well under 8,192.
3. Listing: new `FuncTbl` entries resolve to the new labels; stubs load the right op.
4. MAME: the item's tests on the old and new disks side by side, plus the
   regression set; re-entry count 0 everywhere.
5. Add a dated section to `docs/wildbits-vtio-rewrite.md` and update its status
   block and the progress line in this file.
6. Commit only the changed files, by path; leave `krnp2.asm` alone.
7. K2: `rm .mods/krnp2 bootfile`, build `PLATFORM=k2`, then rebuild jr2 the same
   way.  The user tests on the board.

---

## Appendix A — MAME runner and regression keys

Put these in the session's scratchpad (`$S`).

`run1.sh`:

```
#!/bin/bash
# run1.sh <build-dir> <test-name> <keys>
S=<scratchpad>
d=$1; n=$2; k=$3
cp $S/$d/l2_wildbitsjr2.dsk $S/$d/$n.dsk && truncate -s 134217728 $S/$d/$n.dsk
cd /home/magnus/projects/wild/multiterm/nitros9/mame && WB_KEYS="$k" ./mame wbjr2 -skip_gameinfo -hard $S/$d/$n.dsk \
  -nothrottle -seconds_to_run ${SECS:-40} -video none -sound none > $S/$d/$n.log 2>&1
rm -f $S/$d/$n.dsk
```

`tests.txt` (`name|keys`), with `SETUP` and `T6` expanded:

```
SETUP = 1200:ini;1210:z /v;1220:t1;1230:enter;1350:shel;1360:l i=/;1370:vt1&;1380:enter;1500:ini;1510:z /v;1520:t2;1530:enter;1650:shel;1660:l i=/;1670:vt2&;1680:enter
T6    = 1200:ini;1210:z /v;1220:t1;1230:enter;1350:shel;1360:l i=/;1370:vt1&;1380:enter;1500:disp;1510:lay 1;1520:b 21 ;1530:>/v;1540:t1;1550:enter

r1|SETUP;1900:alt-right
r2|SETUP;1900:alt-right;2000:alt-right
r3|SETUP;1900:alt-right;2000:alt-right;2100:alt-right
l1|SETUP;1900:alt-left
ex|1200:shel;1210:l i=/;1220:vt1&;1230:enter;1350:shel;1360:l i=/;1370:vt2&;1380:enter;1500:alt-right;1650:ex;1660:enter
s1|T6
s2|T6;1700:disp;1710:lay 1;1720:b 21 ;1730:>/t;1740:erm;1750:enter
s3|1200:disp;1210:lay 1;1220:b 21;1230:enter;1350:disp;1360:lay 1;1370:b 21 ;1380:>/v;1390:t2;1400:enter
vt|1200:shel;1210:l i=/;1220:vt&;1230:enter;1450:alt-right
bl|1200:disp;1210:lay 0;1220:7;1230:enter;1400:echo;1410: ok;1420:enter
```

Graphics keys (`V1 = 1200:ini;1210:z /v;1220:t1;1230:enter`):

```
sb0|1200:shel;1210:lbg;1220:enter
sb1|V1;1350:shel;1360:l i=/;1370:vt1&;1380:enter;1500:alt-right;1600:shel;1610:lbg;1620:enter
sbr|V1;1350:shel;1360:lbg >;1370:/vt1;1380:enter
dft|1200:dfte;1210:st;1220:enter
dfr|V1;1350:dfte;1360:st >;1370:/vt1;1380:enter
ast|1200:asct;1210:est;1220:enter
asr|V1;1350:asct;1360:est >;1370:/vt1;1380:enter
```

Run a list (`dir|name|keys` per line) and summarise:

```
cd $S && cat list.txt | SECS=60 xargs -d '\n' -P 10 -I{} bash -c 'IFS="|" read d n k <<< "{}"; ./run1.sh "$d" "$n" "$k"'
for n in r1 r2 r3 l1 ex s1 s2 s3 vt bl; do printf "%-3s " $n; awk '/=== MULTITERM/{f=1} f' new/$n.log | grep -o 'TermCnt=\S*\|LiveTerm=\S*\|re-entry count=\S*' | tr '\n' ' '; echo; done
ext(){ grep -a 'BM[012] ctrl\|^BLK \$\|V: BM\|CLUT[0-3] \|CLUT[0-3] sum\|TermCnt=\|re-entry' "$1" | sed 's/VStaStorU=\S*\|U5=\S*\|D.KbdSta=\S*//g; s/^ *//'; awk '/=== MULTITERM/{exit} {print}' "$1" | grep -a 'dd:\|ERROR\|GFX\|Theme' | sed 's/ *|$/|/'; }
diff <(ext old/sb0.log) <(ext new/sb0.log)
```

The live screen is the part of the log before `=== MULTITERM`, and the dump is
from there on.

## Appendix B — throwaway test commands (never commit)

Assemble from the scratchpad and copy onto a disk copy:

```
N=/home/magnus/projects/wild/multiterm/nitros9
lwasm --6309 --format=os9 --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir=$N/defs -Dwildbits=1 -I$N/recipes/wildbits/l2 dftest.asm -odftest
os9 copy -r dftest dir/l2_wildbitsjr2.dsk,CMDS/dftest
os9 attr -q dir/l2_wildbitsjr2.dsk,CMDS/dftest -e -pe
```

All four share this header, with `nam`, `size` and `name` changed:

```
                    nam       dftest
                    ifp1
                    use       defsfile
                    endc
tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1
                    mod       eom,name,tylg,atrv,start,size
                    org       0
buf                 rmb       $2400               dftest; asctest: blk rmb 2
                    rmb       250
size                equ       .
name                fcs       /dftest/
                    fcb       edition
...
                    emod
eom                 equ       *
                    end
```

`dftest`: the same 1K pattern goes into CLUT1 from data offset `$1E00`, which
crosses `$2000`, and into CLUT3 from `$0800`.  The two sums must match
(`$01FE00`).

```
start               cmpu      #0
                    bne       notzero
                    leax      $1E00,u
                    bsr       fill
                    leax      $0800,u
                    bsr       fill
                    ldx       #1
                    ldy       #$1E00
                    lda       #1
                    ldb       #SS.DfPal
                    os9       I$SetStt
                    bcs       exit
                    ldx       #3
                    ldy       #$0800
                    lda       #1
                    ldb       #SS.DfPal
                    os9       I$SetStt
                    bcs       exit
                    clrb
exit                os9       F$Exit
notzero             ldb       #1
                    bra       exit
fill                clra
                    clrb
fl@                 pshs      d
                    pshs      b
                    ldb       #$35
                    mul
                    addb      ,s+
                    stb       ,x+
                    puls      d
                    addd      #1
                    cmpd      #$400
                    bne       fl@
                    rts
```

`asctest`: allocates bitmap 1 (8 blocks), then asks again.  The second call must
fail with `E$WADef` and return the same `X`.  It exits with the block number, so
the shell prints `ERROR #<block>`.

```
start               ldy       #1
                    ldx       #1
                    lda       #1
                    ldb       #SS.AScrn
                    os9       I$SetStt
                    bcs       exit
                    stx       <blk
                    ldy       #1
                    ldx       #0
                    lda       #1
                    ldb       #SS.AScrn
                    os9       I$SetStt
                    bcc       bad
                    cmpb      #E$WADef
                    bne       exit
                    cmpx      <blk
                    bne       bad
                    ldb       <blk+1
                    bra       exit
bad                 ldb       #1
exit                os9       F$Exit
```

`dfarg` / `ascarg`: `SS.DfPal` with `X=4` (`Y` = `U`) and `SS.AScrn` with `Y=3`,
exiting with the error.  Expect `ERROR #187`.  Run these on the new build only:
the pre-`e1f2627c` code does not range-check.

## Appendix C — long branches that would fit short

```
python3 - vtio.list <<'EOF'
import re,sys
save=0; cnt={}
for ln in open(sys.argv[1],errors='replace'):
    m=re.match(r'^([0-9A-F]{4}) ([0-9A-F]+)\s+\([^)]*vtio\.asm\):(\d{5})\s+(?:\S+\s+)?(lbsr|lbra|lb[a-z]{2})\s',ln)
    if not m: continue
    a=int(m.group(1),16); code=m.group(2); op=m.group(4)
    disp=int(code[2:6] if op in ('lbsr','lbra') else code[4:8],16)
    ln_=3 if op in ('lbsr','lbra') else 4
    if disp>=0x8000: disp-=0x10000
    sd=a+ln_+disp-(a+2)
    if -128<=sd<=127:
        save+=1 if op in ('lbsr','lbra') else 2; cnt[op]=cnt.get(op,0)+1
        print(m.group(3), op)
print(cnt, "bytes ~", save)
EOF
```

Shorten the reported lines; one change can push a neighbour out of range, so
rebuild and repeat until the build is clean.

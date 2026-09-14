# selector

# Cursor selector, order selector and group issue: verified port spec (TotalA.exe)

I checked this spec against the disassembly and made no repository changes. Line by line, I re-read these routines:

- 0x43f0e0 and 0x43e490, with both jump tables and every name string decoded
- the predicates 0x4899b0, 0x489960 and 0x489a90
- the group issue path: 0x48cf30, 0x43e470, 0x438830, 0x43afc0, 0x43adc0 and 0x438880
- the mouse path: 0x498da0, 0x498f70, 0x499100, the dispatcher around 0x499278–0x4995b8, and 0x48d220
- the buttons: 0x419be0, 0x41a490 and 0x41ab89
- the FBI flag loader
- every call site of 0x43f0e0

I also re-ran the Unicorn oracle with a new seed: 5,000 cases, 0 order mismatches, 0 cursor mismatches.

**Markings used below**
- **V:** confirmed by the oracle.
- **V-asm:** read directly from the disassembly.
- **I:** inferred meaning.
- **FIXED:** the earlier spec was wrong or incomplete here.

Offsets are from `G = [0x511de8]`.

---

## 0. Field glossary

### Unit definition flags

**`ud+0x245`** (V-asm, from the loader at 0x42c8xx–0x42cbxx; the shift and mask of each key were checked):

| Bit | Meaning |
|---|---|
| 0x1 | mobilestandorders (I) |
| 0x2 | firestandorders (I) |
| 0x4 | onoffable |
| 0x8 | canstop |
| 0x10 | canattack |
| 0x20 | canguard |
| 0x40 | canpatrol |
| 0x80 | canmove |
| 0x100 | canload |
| 0x200 | Copy of canreclamate, set at 0x42ca3b as `(v>>1)&0x200`. Used as the repair ability (I) |
| 0x400 | canreclamate |
| 0x800 | canresurrect |
| 0x1000 | cancapture |
| 0x4000 | candgun |
| 0x80000 | cantbetransported |

**`ud+0x241`** (V-asm):

| Bit | Meaning |
|---|---|
| 0x40 | builder |
| 0x200 | isairbase |
| 0x800 | canfly. Every "VT(a,b)" below tests this bit |
| 0x1000 | canhover |
| 0x2000 | teleporter |
| 0x80000 | floater |
| 0x100000 | upright |
| 0x200000 | amphibious |
| 0x8000000 | hoverattack |
| 0x10000000 | kamikaze |

**Other definition fields** (meanings I unless noted):

| Offset | Meaning |
|---|---|
| +0x14a | footprintx (word) |
| +0x156 | Build-options pointer |
| +0x16e | Model max-Y, 16.16 dword; +0x170 is its integer word |
| +0x1be | Depth limit (word) |
| +0x1c0 | minwaterdepth (word) |
| +0x1ee | weapon1 definition pointer |
| +0x1fa | maxdamage (dword) |
| +0x22a | Transport size limit (byte) |
| +0x22b | transportcapacity (byte) |

### Weapon record

- `+0x111` flags:

  | Bit | Meaning |
  |---|---|
  | 0x2 | ballistic |
  | 0x100 | dropped (bomb) |
  | 0x10000 | waterweapon |
  | 0x20000 | toairweapon |
  | 0x4000000 | commandfire |

- `+0xc0` energy per shot and `+0xc4` metal per shot, as floats (I).

### Unit fields

| Offset | Meaning |
|---|---|
| +0 | Locomotion object; non-zero means "mobile" (I) |
| +0x10 / +0x2c / +0x48 | Weapon slot 0/1/2 definition pointers. Slot 1 flag byte is +0x3b |
| +0x5c | Order queue head. +0x60 is the background queue (V-asm) |
| +0x6a / +0x6e / +0x72 | Position x/y/z, 16.16. +0x70 is the y integer word |
| +0x86 | Transporter |
| +0x8a / +0x8e | Cargo list head / next |
| +0x92 | Definition |
| +0x96 | Player |
| +0xec | Resource record: +0x8c energy, +0x98 metal (I) |
| +0xfb | dword, 0 means selectable |
| +0xff | Owner index byte |
| +0x104 | Build fraction, float (0.0 = finished) |
| +0x108 | Health (word) |

`+0x110` flags:

| Bit | Meaning |
|---|---|
| low 2 bits | State; value 2 means airborne (I) |
| 0x10 | Selected |
| 0x20 | Selectable |
| 0x10000000 | Alive (I) |
| 0x20000000 | Stationary attacker (I) |
| 0x40000000 | Transporter lets its cargo be selected |
| 0x80000000 | Armed (I) |

### Order record (V-asm)

| Offset | Meaning |
|---|---|
| +4 | Type byte |
| +0xe | Unit |
| +0x16 | Target |
| +0x22 / +0x2a | Position x / z |
| +0x42 | Flags |
| +0x4a | Next |

The TYPES table is `[0x512344] + id*0x19`, with flags at +0x11 (0x438830).

### Player and game fields

**Player:** `+0x80` and `+0x84` are the seen-bitmap width and height; `+0x108[idx]` are alliance bytes; `+0x146` is the player index.

**Alliance** (V): `allied = byte[u.player+0x108+byte[h.player+0x146]] != 0`.
- `enemy = h && !allied`; `ally = h && allied`.
- An own unit counts as an ally whenever that byte is set.

**Game fields:**

| Offset | Meaning |
|---|---|
| +0x2a42 | Local player |
| +0x2a43 | Viewing player |
| +0x2c76 | Keyboard/GUI input block. The STOP button passes this as `input` |
| +0x2caa | Cursor world position (16.16 triple) |
| +0x2cba | Hovered unit id (word): `[G+0x14357] + id*0x118`; 0 means none |
| +0x2cbe | Cursor id (signed byte) |
| +0x2cc3 | Order mode (byte) |
| +0x2cc4 | Build type (word) |
| **+0x1427f** | **Sea level. It is a BYTE, zero-extended, in every comparison (FIXED)** |
| +0x37efa | Interface (dword). 0x43f0e0, 0x43e490, 0x498f70 and the dispatcher's LBUTTONDOWN branch at 0x499567 test `== 1`. 0x499100 and 0x499352 test `!= 0`. Treat 1 as Right-Click and 0 as Left-Click; the tests only agree for the values 0 and 1 |

**G+0x2cc6 bits (FIXED: now traced, set in 0x498da0 on every mouse move, V-asm):**

| Bit | Meaning |
|---|---|
| 0x01 | Cursor inside the minimap rectangle, `0x4b6720(G+0x142bb, x, y)`. Not tested while 0x08 is set. The cursor position is then mapped from the minimap |
| 0x02 | Cursor inside the main view rectangle, G+0x37e27 |
| 0x04 | `(bit 0x01 or bit 0x02)`: the cursor has a valid world position |
| 0x08 | Drag box active. Cleared on every mode set |
| 0x10 | Minimap drag (I). Released on the interface's button-up |
| 0x20 | Keep mode after issuing (shift) |
| 0x40 | Build placement legal |

### featureVisible(u, pos) (V)

```
lx = s16(pos+2) sar 5;  lz = (s16(pos+0xa) - (s16(pos+6) sar 1)) sar 5     // unsigned compares
require lx < [u.player+0x80] && lz < [u.player+0x84]
require word[[G+0x14273] + ([u.player+0x80]*lz + lx)*2] & (1 << (byte G+0x2a43 & 31))
cell = 0x4815a0(pos); if !cell: none
occ = word cell+8
if occ < 0xfffb: require occ < [G+0x14253] (signed); f = [G+0x1426f] + occ*0x100
elif occ == 0xfffe: back = word (cell - (byte cell+10 * [G+0x14233] + byte cell+11)*13)+8; require back < 0xfffb; f = [G+0x1426f] + back*0x100   // no count check
else none
require byte f+0xfe & 0x80
```

The call order differs by site:
- In 0x43f0e0 mode 12, 0x4815a0 runs before the bitmap test and before the `pos` null check.
- Everywhere else, the bitmap test runs first.

### Predicates (V-asm; the oracle stubbed them)

**canRepair(u, t) = 0x4899b0.** thiscall with `ecx = u`, `ret 4`.
1. Return 0 if `!t`.
2. Return 0 if `!(ud.245 & 0x200)`.
3. Return 0 if `s16(t.health) == td.1fa`. This is an equality test.
4. Return 0 if `(t.f110&3) == 2`.
5. If `ud.241&0x800 && !(ud.241&0x200000)`: require `s16(t+0x70) + s16(td+0x170) >= sea`.
6. If u is canfly, return 1.
7. Otherwise require `s16(t+0x70) + s16(td+0x170) >= sea − s16(ud+0x1be)` and return 1.

**canReclaimUnit(u, t) = 0x489960:** `ud.245&0x400 && (t.f110&3) != 2 && !(td.245&0x1000)`. There is no null check on t.

**canLoad(u = transport, t) = 0x489a90.** Return 0 unless all of these hold:
- `!(td.245&0x80000)`
- `ud.245&0x100`
- The count of u's cargo list entries with `+0x86 == u` is less than `byte ud+0x22b`
- `t[0] != 0`
- `word td+0x14a <= byte ud+0x22a` (signed word compare)
- `(t.f110&3) != 2`
- If u is not canfly: `word td+0x1c0 < 0`
- `dword t+0x6e + dword td+0x16e > sea<<16` (signed)
- `t.build == 0.0`

There is no alliance check.

**Range tests (I):** `0x49abb0(u, t, slot)` and `0x49aa80(u, &u.pos, pos, slot)`. Both are stdcall; only the cursor uses them.

---

## 1. Order modes and input routing

### Order button handler 0x419be0

This is V-asm; its only caller is 0x41abcc, after 0x41a490. The gadget name has its side prefix stripped by 0x49fed0 and is compared with `stricmp` (0x4e49b0).

- **Button down** (`word [gadget+0x138] != 0`): set the mode, clear `2cc6 & 0x08`, play the sound.
- **Button toggled off (FIXED):** set mode = 1, and also clear `2cc6 & 0x08` and play the same sound.

| Gadget | Mode | Sound |
|---|---|---|
| MOVE | 2 | immediateorders |
| ATTACK | 3 | immediateorders |
| BLAST | 4 | immediateorders |
| UNLOAD | 5 | specialorders |
| LOAD | 6 | immediateorders |
| DEFEND | 7 | immediateorders |
| REPAIR | 8 | specialorders |
| PATROL | 9 | immediateorders |
| RECLAIM | 12 | specialorders |
| CAPTURE | 13 | specialorders |

- **STOP:** mode = 1, clear 0x08, then `0x48cf30(&G+0x2c76, 0, Stop, null, 0, 0)`, then play immediateorders (FIXED: input block and sound).
- **Mode 14** is set at 0x41ab89 for a build gadget with unit id `bx != 0`, only when `byte [[G+0x1439b] + id*0x249 + 0x22f] == 0`. It sets `G+0x2cc4 = id` and plays "addbuild".
- **Modes 10 and 11:** no literal writer exists. The only generic setter, 0x419bc0, has no code or data references, so these modes are unreachable from the UI (V-asm).
- **Quickkeys** (m, a, d, u, l, g, r, p, e, c, s, b and their variants) come from GUI data, not exe code. They were not re-verified.
- **Toggles in 0x41a490** all issue `0x48cf30(input, 0, type, null, p5, 0)` (V-asm):
  - Standing_MoveOrder and Standing_FireOrder with p5 = 0, 1 or 2.
  - Cloak_On or Cloak_Off, depending on G+0x37ec0.
  - Activate or Deactivate, depending on G+0x37ec0.

### Mouse dispatcher (around 0x499278–0x4995b8, V-asm)

**Each event:**
1. `G+0x2cba = 0x48cd80()` (hover).
2. `G+0x2cbe = 0x48d220(mode)`.

**When `2cc6 & 0x10`** (minimap drag):
- The Left-Click interface ends the drag on message 0x205.
- The Right-Click interface ends it on 0x202.
- Other messages go to 0x41d0f0.

**Otherwise, if `[G+0x2cdf] != 0`:** call 0x41cd50.

**Otherwise:**
- **0x204** (right button down) calls 0x499100.
- **Mode ≠ 1:** 0x201 (left button down) calls 0x498f70 immediately.
- **Mode 1 with `2cc6&8`** (drag box):
  - On 0x202, clear 0x08.
  - If the box is smaller than 32 px on both axes and `now < start + 25` ticks (from 0x4b6340), call **0x498f70** (a click).
  - Otherwise call 0x48c390 (box select). If that returns 0, deselect all: `0x48bd00(); 0x491d70(1)`.
  - Other messages update the box corner.
- **Mode 1, on 0x201:**
  - `2cc6&2` (over the view): set 0x08, record the start, and set cursor 0x13.
  - Otherwise, if `37efa == 1`: `2cc6&1` sets 0x10 and cursor 0x13.
  - Otherwise, `2cc6&1` calls **0x498f70**: in the Left-Click interface, a left click on the minimap issues orders.

### 0x498f70(input): left-click action (V-asm)

- **Mode 14:**
  - If `2cc6&0x40`: `0x419670(input)` and play "oktobuild".
  - Otherwise play "notoktobuild" and return, with no mode change.
  - After a legal build: shift (`input+8 & 4`) sets `2cc6 |= 0x20`. Otherwise set mode = 1, clear 0x20 and re-select the STOP gadget (0x49fe60 / 0x4a6a40).
- **Else if `byte 2cbe == 0xf`:** `0x48c7f0(input)` (click select).
- **Else if `(s8)2cbe >= 0x11`:** if `37efa == 1 && mode == 1`, deselect all. Otherwise do nothing. Either way, the mode is not reset.
- **Else:** `0x48cf30(input, mode, 0, &G+0x2caa, 0, 0)`, followed by the same shift / mode-1 rule.

This gating applies in both interfaces and every mode except 14 (FIXED: the earlier spec limited it to the Left-Click interface in mode 1). In the Right-Click interface, mode-1 cursors are only 0xf, 0x11, 0x12 and 0x13, so a mode-1 left click there only selects or deselects.

### 0x499100(input): right button down (V-asm, FIXED)

- **Mode ≠ 1:** mode = 1, clear `2cc6&0x20`, re-select STOP. Nothing is issued.
- **Mode 1 with `37efa != 0`** (Right-Click interface): if `2cc6 & 4`, run `0x48cf30(input, 1, 0, &G+0x2caa, 0, 0)`. There is no cursor check.
- **Mode 1 with `37efa == 0`** (Left-Click interface):
  - `2cc6 & 2` (over the view): Ctrl (`input+8 & 8`) calls 0x41cc60 (I: view-control). Otherwise deselect all.
  - Otherwise, `2cc6 & 1` (over the minimap): set `2cc6 |= 0x10` and cursor 0x13, with 0x4ab400.

### Cursor aggregation 0x48d220(mode) (V-asm, FIXED)

1. Build the list of selected units (f110&0x10), then remove H (the hover) from it with 0x480100.
2. **If the list is empty:** return 0xf if `mode == 1` and H is selectable (same test as §2). Otherwise return 0x13.
3. **Otherwise:** return `min(0x13, 0x43e490(mode, s, H, &G+0x2caa))` over the list, using a signed compare. H is always passed, whatever the mode.

### Call sites of 0x43f0e0 (mode pushed; V-asm)

| Call site | Mode |
|---|---|
| 0x401f2f | 3 |
| 0x402e3d | 9 |
| 0x4031a7 | 3 |
| 0x405265 | 8 |
| 0x405abc | 8 |
| 0x4064f5 | 8 |
| 0x40804c | 3 |
| 0x408299 | 14 |
| 0x408403 | 2 |
| 0x408435 | 9 |
| 0x408589 | 9 |
| 0x40fe86 | 8 |
| 0x410ad9 | 7 |
| 0x43b242 | 3 |
| 0x43b285 | 2 |
| 0x43b416 | 8 |
| 0x43b451 | 2 |
| **0x43b583** | **2 (FIXED: missing before; in the function after 0x43b560)** |
| 0x4804a3 | variable |
| 0x487d5b | 2 (AI) |
| 0x487dd3 | 5 (AI) |
| 0x487e2e | 7 (AI) |
| 0x487efd | 9 (AI) |
| 0x487f8c | 3 (AI) |
| 0x43fe5a / 0x43fe83 / 0x43fecc | Internal recursion to 3 / 12 / 8 |
| 0x48d0a0 | Group issue |

---

## 2. Order selector `0x43f0e0(out*, mode, u, h, pos*)` (V oracle and V-asm)

**Calling convention:** stdcall, `ret 0x14`. It writes the order-type byte to `*out` through the name lookup `0x438760(ecx = out, name)` and returns `out` (FIXED: it returns a pointer, not a byte). A result of 0 is written as `byte [out] = 0`.

**Jump table** at 0x4401ec, indexed by `(mode & 0xff) − 1`:

| Mode | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Target | 0x43f9e9 | 0x43f845 | 0x43f154 | 0x43f7e8 | 0x43f735 | 0x43f701 | 0x43f4c7 | 0x43f46c | 0x43f3b9 | 0x43f82c | 0x43f813 | 0x43f4f7 | 0x43f6d1 | 0x43f7a0 |

Modes outside 1..14 give 0.

```
if h && !(h.f110 & 0x10000000): return 0      // before dispatch: applies to EVERY mode
VT(a,b) = (ud.241 & 0x800) ? a : b;  mobile = u[0] != 0;  sea = byte G+0x1427f
```

A "→ mode N" below is a tail recursion `0x43f0e0(out, N, u, h, pos)`. Its result is returned as is, even when it is 0; nothing falls through after it.

### mode 1 (default)

1. **Right-Click interface (37efa == 1):**
   1. `ud.245&0x10 && enemy` → mode 3.
   2. `ud.245&0x400 && enemy` → VT(VTOL_ReclaimUnit 0x3a, ReclaimUnit 0x20).
   3. If ally and canRepair(u, h):
      - `h.build != 0.0` → VT(VTOL_HelpBuild 0x32, HelpBuild 0x16).
      - Otherwise → VT(VTOL_RepairUnit 0x3c, RepairUnit 0x22). There is no health test here; canRepair already rejects full health.
   4. `ud.241&0x800 && ally && hd.241&0x200` → VTOL_Landing 0x34.
   5. `h && canLoad(u, h)` → VT(VTOL_Pickup 0x38, Ground_Pickup 0x13).
   6. `ud.245&0x20 && ally` → VT(VTOL_Follow 0x30, Follow_Ground 0x11).
2. **Left-Click interface:**
   1. `ud.245&0x10 && enemy` → mode 3.
   2. `ud.245&0x400 && enemy` → mode 12. If pos is null, 0x4815a0 is called with null (native crash risk).
   3. `h && canRepair && h.build != 0.0` → mode 8.
   4. If h is selectable (owner byte == G+0x2a42, f110&0x20, build == 0.0, +0xfb == 0):
      - If it has no transporter, or its transporter has f110&0x40000000 → **return 0**.
      - If it has a transporter without that bit, fall through.
3. **Both interfaces:**
   1. `ud.245&0x800 && pos && featureVisible` → Resurrect 0x24.
   2. `ud.245&0x400 && pos && featureVisible` → VT(VTOL_Reclaim 0x39, Reclaim 0x1f).
   3. `ud.245&0x80 && mobile` → VT(VTOL_Move 0x36, Move_Ground 0x19).
   4. Otherwise 0.

### mode 2 (MOVE)

1. `!(ud.245&0x80)` → 0.
2. `!mobile` → QMove 0x1d.
3. If h:
   1. `ud.245&0x1000 && enemy` → Capture 0x0d.
   2. `ud.245&0x400 && enemy` → VT(0x3a, 0x20).
   3. `ally && canRepair && build != 0.0` → VT(0x32, 0x16).
   4. `ally && canRepair && (u32)s16(h.health) < hd.1fa` → VT(0x3c, 0x22).
   5. `ud.241&0x800 && ally && hd.241&0x200` → VTOL_Landing.
   6. `canLoad` → VT(0x38, 0x13).
   7. `ud.245&0x20 && ally` → VT(0x30, 0x11).
4. Otherwise VT(VTOL_Move, Move_Ground).

### mode 3 (ATTACK)

1. `!(ud.245&0x10)` → 0.
2. If `u.f110 & 0x80000000` (armed), with `w0 = [u+0x10]`:
   1. **Not enemy** (no hover, or own/allied hover):
      - `w0.111&0x20000` → 0.
      - Not canfly → Suppress 0x2d.
      - Canfly → `[ud+0x1ee].111 & 0x100` ? AirStrike 0x01 : AirToGround 0x03.
   2. **Enemy:**
      1. `(h.f110&3) != 2 && w0.111&0x20000` → 0.
      2. `depth = s16(hd+0x170) + s16(h+0x70)`.
      3. If `depth < sea`: continue only if `w0.111&0x10000` or (`byte u+0x3b & 2` and `[u+0x2c].111 & 0x10000`); otherwise return 0. This path skips the canhover test.
      4. Else if `ud.241&0x1000`: `w0.111&0x10000` → 0; (`u+0x3b&2 && w1.111&0x10000`) → 0.
      5. If canfly, with `bomb = [ud+0x1ee].111&0x100` and `tair = hd.241&0x800`:
         - `bomb && !tair` → AirStrike
         - `!bomb && tair` → AirToAir 0x02
         - `!tair && !(ud.241&0x8000000)` → AirToGround
         - `!tair && ud.241&0x8000000` → AirToGroundHover 0x04
         - `bomb && tair` → 0
      6. Not canfly: mobile → Attack_Chase 0x05. Else `u.f110&0x20000000` → Attack_NoMove 0x07. Else fall through to step 3.
3. Not armed, or the immobile fallthrough: `ud.241&0x10000000` → Attack_Kamikaze 0x06, else 0.

### Other modes

- **mode 4:** `ud.245&0x4000` → AttackSpecial 0x08, else 0.
- **mode 5:**
  - `ud.245&0x100 && canfly && h && hd.241&0x200` → VTOL_Landing.
  - Else `ud.245&0x100` → VT(VTOL_Unload 0x40, Ground_Unload 0x14).
  - Else 0.
- **mode 6:** `h && canLoad` → VT(0x38, 0x13), else 0.
- **mode 7:** `ud.245&0x20 && ally` → VT(0x30, 0x11), else 0.
- **mode 8:** `canRepair(u, h)` → `h.build == 0.0` ? VT(0x3c, 0x22) : VT(0x32, 0x16). Otherwise 0.
- **mode 9:**
  - `!(ud.245&0x40)` → 0.
  - `!mobile` → QPatrol 0x1e.
  - `ud.245&0x200` → VT(VTOL_RepairPatrol 0x3b, RepairPatrol 0x21).
  - Else VT(VTOL_Patrol 0x37, Patrol 0x1c).
- **mode 10:** Stop 0x2c. **mode 11:** Teleport 0x2e. Both are unconditional apart from the hover gate.
- **mode 12:**
  1. `!(ud.245&0x400)` → 0.
  2. `0x4815a0(pos)` runs first (crash risk if pos is null).
  3. If pos: `ud.245&0x800 && featureVisible` → Resurrect; else `featureVisible` → VT(0x39, 0x1f).
  4. **If neither returned (pos null, or no visible feature; FIXED wording):** `h` → VT(0x3a, 0x20). There is no ally test, so own units can be reclaimed.
  5. Otherwise 0.
- **mode 13:** `ud.245&0x1000 && h && u.player != h.player` → Capture. It compares player pointers, not alliance.
- **mode 14:** `[ud+0x156] && mobile` → VT(VTOL_MobileBuild 0x35, MobileBuild 0x18), else 0.

---

## 3. Cursor selector `0x43e490(mode, u, h, pos*) → cursor id` (V oracle and V-asm)

**Calling convention:** stdcall, `ret 0x10`. The jump table is at 0x43f0a8:

| Mode | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Target | 0x43e505 | 0x43e8bb | 0x43e545 | 0x43e850 | 0x43e80c | 0x43e7d3 | 0x43e615 | 0x43e5fa | 0x43e5de | 0x43f098 (=0x13) | 0x43e8ae | 0x43e65c | 0x43e797 | 0x43e828 |

- There is **no** alive gate on h.
- Recursion re-enters at 0x43e49f with a new mode and recomputes ally/enemy.
- featureVisible is called **without a pos null check** in modes 1 (both interfaces), 2 and 12.
- The default result is 0x13.

**mode 1, Right-Click interface:**
1. h selectable, and it has no transporter or its transporter has 0x40000000 → 0xf.
2. enemy → 0x11.
3. ally → 0x12.
4. `245&0x800 && featureVisible` → 0x12.
5. `245&0x400 && featureVisible` → 0x12.
6. Otherwise 0x13.

**mode 1, Left-Click interface:**
1. `245&0x10 && enemy` → mode 3.
2. `245&0x400 && enemy` → mode 12.
3. If h: `canRepair && build != 0.0` → 6. Then selectable (same transporter rule) → 0xf.
4. `245&0x800 && featureVisible` → 0xa.
5. `245&0x400 && featureVisible` → 0xb.
6. Otherwise `245&0x80` ? 0xe : 0x13.

**mode 2:**
1. `!(245&0x80)` → 0x13.
2. `245&0x800 && featureVisible` → 0xa. This checks resurrect before the hover, but the order selector never gives Resurrect in mode 2 (a cursor/order mismatch quirk).
3. If `h && mobile`:
   1. If `245&0x1000`: enemy → 4. Otherwise, `enemy && canReclaimUnit` → 0xb. Either way, fall through if not returned.
   2. `ally && canRepair` → 6.
   3. `ud.241&0x800 && hd.241&0x200` → 0xd. There is no ally test.
   4. `canLoad` → canfly ? 8 : 0xc.
   5. `245&0x20 && ally` → 5.
4. Otherwise 0xe. This includes immobile units, whose order is QMove.

**mode 3:**
1. `245&0x10 && [ud+0x1ee].111&0x100` → 2.
2. `!(245&0x10)` → 0x13.
3. mobile → 1.
4. h → `0x49abb0(u, h, 0)` ? 1 : 3.
5. `!0x49aa80(u, &u+0x6a, pos, 0)` → 3.
6. Otherwise `[u+0x10].111&0x20000` ? 3 : 1.

**mode 4:**
1. `!(245&0x4000)` → 0x13.
2. `float [[u+0xec]+0x8c] < float [[u+0x48]+0xc0]` → 3. The weapon is slot 2.
3. `float [[u+0xec]+0x98] < float [[u+0x48]+0xc4]` → 3.
4. Otherwise 1. An unordered (NaN) comparison also gives 3.

**Remaining modes:**
- **mode 5:** `245&0x100` ? 0xd : 0x13.
- **mode 6:** `h && canLoad` → canfly ? 8 : 0xc. Otherwise 0x13.
- **mode 7:**
  1. `!(245&0x20) || !ally` → 0x13.
  2. canfly → 5.
  3. `hd.241&0x800` → 0x13.
  4. Otherwise 5.
- **mode 8:** canRepair(u, h) ? 6 : 0x13.
- **mode 9:** `245&0x40` ? 7 : 0x13.
- **mode 10:** 0x13. **mode 11:** 9.
- **mode 12:** `245&0x400 && featureVisible` → 0xb. Otherwise (including without 0x400) `h && canReclaimUnit` → 0xb. Otherwise 0x13.
- **mode 13:** `245&0x1000 && h && u.player != h.player` → 4.
- **mode 14:** `[ud+0x156] && mobile` → 0x10.

---

## 4. Group issue `0x48cf30(input*, mode, type, pos*, p5, p6)` (V-asm, stdcall `ret 0x18`)

```
shift = ([input+8] >> 2) & 1
exclH = (mode&0xff) ? 0x43e470(mode) /* 0 for 5,10,14 else 1 */ : (TYPES[type].flags & 0x200)
H = (exclH && word G+0x2cba) ? [G+0x14357] + id*0x118 : null      // FIXED: for modes 5/10/14 H is null,
                                                                  // so the hovered unit is NOT excluded and the selector sees no hover
p = byte G+0x2a42; base = G + p + p*0x14a; first = [base+0x1bca]; last = [base+0x1bce]
n = sx = sz = 0
for s = first; s <= last (unsigned, cached); s += 0x118:
    if s.f110&0x10 && s != H: n++; sx += s16(s.x sar 16); sz += s16(s.z sar 16)
if n == 0: return
cx = ftol(double(sx idiv n) * 65536.0); cz likewise                  // idiv truncates toward 0
lim = n*3000
for s = first; s <= [base+0x1bce] (re-read each step); s += 0x118:
    if !(s.f110&0x10) || s == H: continue
    t = mode ? *0x43f0e0(&tmp, mode, s, H, &G+0x2caa) : type          // selector always gets the cursor pos, not the pos argument
    if t == 0: continue
    if t == Standing_FireOrder && !(sd.245&2): continue
    if t == Standing_MoveOrder && !(sd.245&1): continue
    P = pos
    if pos && TYPES[t].flags & 0x2:
        dx = s.x - cx; dz = s.z - cz                                   // 32-bit 16.16
        d = hi32((i64)dx*dx) + hi32((i64)dz*dz)                        // _allmul, then _allshr 32 (arithmetic)
        if d <= lim (signed): P = (pos.x + s.x - cx, pos.y, pos.z + s.z - cz)
    0x43afc0(t, shift, s, H, P, p5, p6)
```

**Formation types (flag 0x2):** Move_Ground, Patrol, RepairPatrol, VTOL_Move, VTOL_Patrol and VTOL_RepairPatrol. QMove and QPatrol have 0x400 only.

**Consequences for modes 5 and 14:** because H is null in mode 5, a UI UNLOAD click never gives VTOL_Landing, although the cursor still shows 0xd. Mode 14 through this path never sees a hover either.

**issue_one 0x43afc0(t, shift, s, H, P, p5, p6)** (`ret 0x1c`, V-asm):
1. If shift and `s+0x5c` is non-empty, walk the queue (next = +0x4a) for an order where all of these hold:
   - `byte +4 == t`
   - `H == 0 || H == [o+0x16]`
   - `P == 0 || (unsigned)(P.x − o+0x22 + 0x100000) <= 0x200000 && (unsigned)(P.z − o+0x2a + 0x100000) <= 0x200000`

   That is a ±16.0 box, inclusive (FIXED: this tolerance was missing).
2. If found, unlink it from +0x60 when `o+0x42 & 0x40000`, otherwise from +0x5c.
   - If it was not in the list, return without adding.
   - If it was not the original head, set `o+0x42 |= 0x10000`.
   - Destroy it: 0x43a1f0, then free.
   - Return. A shift click on a matching order removes it.
3. Otherwise call `0x43adc0(t, shift, s, H, P, p5, p6)`.

**add_order 0x43adc0** (V-asm):
1. Construct the order with 0x43a0c0.
2. If not shift and the new order lacks flag 0x40: delete every queued order in +0x5c that lacks flag 0x4, setting 0x10000 on each one that is not the head.
3. If the new order lacks 0x40000: remove the leading +0x5c orders that have 0x4000.
4. Set `flags |= 1`.
5. If not shift, also set `flags |= 0x2000` (acknowledge).
6. Link the order in.

**Quirk (I):** if the constructor drops the target for types without 0x200, a shift-click while hovering a unit (H ≠ 0) never matches a queued Move, so the Move is added instead of toggled.

**Acknowledgement:** 0x438880 (thiscall on the order; 30 call sites): if `flags & 0x2000`, clear it and call `0x47f780([order+0xe], 5, arg)` (I: unit reply 5). Shift issues never acknowledge.

**Quirks worth porting:**
- A hovered unit without `f110&0x10000000` makes 0x43f0e0 return 0 in every mode where H is passed, so nothing is issued. With exclH, H is also excluded from the recipients.
- In the Left-Click interface, a left click on your own finished, selectable unit selects it (cursor 0xf). Repair of a damaged finished unit only comes from mode 8 or the Right-Click interface.
- In a non-default mode, a click whose aggregate cursor is ≥ 0x11 does nothing and keeps the mode.

---

## 5. Still unverified or inferred

- **Field meanings:**
  - f110 bits 31, 29 and 28, and `u[0]` as "mobile"
  - `+0xec`, `ud+0x156` and `ud+0x1be` (meanings)
  - `ud.245 0x200` as the repair ability
  - `+0x22a` / `+0x22b` transport limits
  - `2cc6` bit 0x10 as minimap drag
- **Routines not decoded:** 0x41cc60 (Ctrl), 0x41d0f0, the range tests 0x49abb0 and 0x49aa80, 0x480460 (variable-mode caller at 0x4804a3), 0x47f780 reply semantics, and whether 0x43a0c0 zeroes +0x16 for non-0x200 types.
- **Predicates:** 0x4899b0, 0x489960 and 0x489a90 were read from asm only; the oracle stubbed them.
- **Quickkey letters** are from GUI data and were not re-checked.
- **37efa values other than 0 or 1** would make 0x499100 and 0x499352 (`!= 0`) disagree with the `== 1` tests elsewhere.

---

## 6. Class × hover tables

These are derived from the verified model (`matrix.py`) and are unchanged in substance; they only follow from §2 and §3. Each cell is order type (cursor id); `-` means 0, no order.

**Assumptions:**
- Sea level 0; features visible.
- No toairweapon or waterweapon flags.
- Repair needs 0x200 and a damaged target; load succeeds for any finished target.
- Every modifier from §2/§3 still applies:
  - Enemy hovers in the Left-Click interface route through mode 3 or mode 12.
  - UI issue in modes 5 and 14 has H = null.
  - Dead hover means no order at all.

**Mode 1, Left-Click interface (left click)**

| Class | none | feature | own idle | own damaged | own nanoframe | ally | allied airbase | enemy ground | enemy air |
|---|---|---|---|---|---|---|---|---|---|
| Ground combat | Move_Ground (e) | Move_Ground (e) | - (f) | - (f) | Move_Ground (e) | Move_Ground (e) | Move_Ground (e) | Attack_Chase (1) | Attack_Chase (1) |
| Static defense | - (13) | - (13) | - (f) | - (f) | - (13) | - (13) | - (13) | Attack_NoMove (1/3 by range) | Attack_NoMove |
| Factory | - (e) | - (e) | - (f) | - (f) | - (e) | - (e) | - (e) | - (e) | - (e) |
| Fighter | VTOL_Move (e) | VTOL_Move (e) | - (f) | - (f) | VTOL_Move (e) | VTOL_Move (e) | VTOL_Move (e) | AirToGround (1) | AirToAir (1) |
| Bomber | VTOL_Move (e) | VTOL_Move (e) | - (f) | - (f) | VTOL_Move (e) | VTOL_Move (e) | VTOL_Move (e) | AirStrike (2) | - (2) |
| Mobile builder | Move_Ground (e) | Reclaim (b) | - (f) | - (f) | HelpBuild (6) | Move_Ground (e) | Move_Ground (e) | ReclaimUnit (b) | ReclaimUnit (b) |
| Air builder | VTOL_Move (e) | VTOL_Reclaim (b) | - (f) | - (f) | VTOL_HelpBuild (6) | VTOL_Move (e) | VTOL_Move (e) | VTOL_ReclaimUnit (b) | VTOL_ReclaimUnit (b) |
| Commander | Move_Ground (e) | Reclaim (b) | - (f) | - (f) | HelpBuild (6) | Move_Ground (e) | Move_Ground (e) | Attack_Chase (1) | Attack_Chase (1) |
| Ground transport | Move_Ground (e) | Move_Ground (e) | - (f) | - (f) | Move_Ground (e) | Move_Ground (e) | Move_Ground (e) | Move_Ground (e) | Move_Ground (e) |
| Air transport | VTOL_Move (e) | VTOL_Move (e) | - (f) | - (f) | VTOL_Move (e) | VTOL_Move (e) | VTOL_Move (e) | VTOL_Move (e) | VTOL_Move (e) |

**Mode 1, Right-Click interface (right click over the map, `2cc6&4`; no cursor gate)**

| Class | none | feature | own idle | own damaged | own nanoframe | ally | allied airbase | enemy ground | enemy air |
|---|---|---|---|---|---|---|---|---|---|
| Ground combat | Move_Ground | Move_Ground | Follow_Ground | Follow_Ground | Follow_Ground | Follow_Ground | Follow_Ground | Attack_Chase | Attack_Chase |
| Static defense | - | - | - | - | - | - | - | Attack_NoMove | Attack_NoMove |
| Factory | - | - | Follow_Ground | Follow_Ground | Follow_Ground | Follow_Ground | Follow_Ground | - | - |
| Fighter | VTOL_Move | VTOL_Move | VTOL_Follow | VTOL_Follow | VTOL_Follow | VTOL_Follow | VTOL_Landing | AirToGround | AirToAir |
| Bomber | VTOL_Move | VTOL_Move | VTOL_Follow | VTOL_Follow | VTOL_Follow | VTOL_Follow | VTOL_Landing | AirStrike | - |
| Mobile builder | Move_Ground | Reclaim | Follow_Ground | RepairUnit | HelpBuild | Follow_Ground | Follow_Ground | ReclaimUnit | ReclaimUnit |
| Air builder | VTOL_Move | VTOL_Reclaim | VTOL_Follow | VTOL_RepairUnit | VTOL_HelpBuild | VTOL_Follow | VTOL_Landing | VTOL_ReclaimUnit | VTOL_ReclaimUnit |
| Commander | Move_Ground | Reclaim | Follow_Ground | RepairUnit | HelpBuild | Follow_Ground | Follow_Ground | Attack_Chase | Attack_Chase |
| Ground transport | Move_Ground | Move_Ground | Ground_Pickup | Ground_Pickup | Follow_Ground | Ground_Pickup | Ground_Pickup | Ground_Pickup | Ground_Pickup |
| Air transport | VTOL_Move | VTOL_Move | VTOL_Pickup | VTOL_Pickup | VTOL_Follow | VTOL_Pickup | VTOL_Landing | VTOL_Pickup | VTOL_Pickup |

**Mode 2 (MOVE)**

| Class | Result |
|---|---|
| Ground combat, fighter, bomber | Move_Ground / VTOL_Move. Follow on own or ally hover. Air units get VTOL_Landing on an allied airbase |
| Static defense | - |
| Factory | QMove |
| Builders | Follow on own or ally; RepairUnit on a damaged own/ally; HelpBuild on a nanoframe; ReclaimUnit on enemies. The cursor shows 0xa over a visible feature for canresurrect units, but the order is still Move |
| Commander | As builders, but Capture on enemies |
| Transports | Pickup on any finished unit, any owner; Follow on an own/ally nanoframe |

**Mode 3 (ATTACK)**

| Class | No hover or own/ally hover | Enemy ground | Enemy air |
|---|---|---|---|
| Armed ground or commander | Suppress | Attack_Chase | Attack_Chase |
| Static defense | Suppress | Attack_NoMove | Attack_NoMove |
| Fighter | AirToGround | AirToGround | AirToAir |
| Bomber | AirStrike | AirStrike | - |
| Unarmed | Kamikaze if kamikaze, else - | Same | Same |

**Other modes:**
- **Mode 4:** AttackSpecial for candgun units. The cursor is 3 when energy or metal is below the slot-2 cost.
- **Mode 5:** Ground_Unload or VTOL_Unload (no Landing from UI).
- **Mode 6:** Pickup on finished units.
- **Mode 7:** Follow on own or ally units.
- **Mode 8:** RepairUnit (damaged) or HelpBuild (nanoframe) for 0x200 units.
- **Mode 9:** Patrol, or RepairPatrol for 0x200 units; QPatrol for immobile units.
- **Mode 12:** Resurrect or Reclaim on a visible feature, otherwise ReclaimUnit on any hovered unit, own included.
- **Mode 13:** Capture on any unit of another player (pointer compare).
- **Mode 14:** MobileBuild or VTOL_MobileBuild.

# move

# Movement, idle, patrol and guard order handlers: verified port spec

I checked every claim below against the disassembly of `local/original/TotalA.exe`. That covers the handler dumps in `C:\Users\garet\AppData\Local\Temp\claude\re-scratch\handlers\` and fresh disassembly of every helper (dispatcher, constructor, list operations, goal and follower vtables, weapon helpers, air goal, RNG). The main dispatcher `0x43b7c0` is the only piece already checked against a native oracle. No repository files were changed.

**Legend:**
- **V**: read directly from the instructions. Offsets, constants, branch order and RNG call order are exact.
- **I**: inferred. This covers meanings, names, and consequences reasoned from V pieces but not run.

## Corrections to the earlier draft

1. **Code 5/8/9 removal flag.** The 0x10000 flag is set when the order is not the head of `main` as re-read **after** the handler returns (`0x43b8ab mov edx,[ebx]`). The earlier draft said the head captured before the handler, which is wrong. So a handler that pushes a new order to the front and then returns 5 gets its own order flagged.
2. **The order destructor `0x43a1f0` has two missing side effects:**
   - If flag 0x400000 is set, it runs the `StopBuilding` script and clears the flag.
   - If flag 0x10000 is **not** set, it calls `0x489800(u,3)` (clear weapon targets) and then unlinks the target.
   - Removing the head order therefore clears weapon targets. Removing a non-head order does not.
3. **Constructor `0x43a0c0`.** A null target clears static flag 0x200, and a null `pos` clears static flag 0x400. Both happen before the target-link test. It also stores the creation tick at `+0x46` and zeroes `+0x2e..+0x35`.
4. **RepairPatrol reclaim gate was inverted.** Real rule: return 2 (no reclaim) when energy **and** metal are both at or above 20%. Reclaim is attempted when either one is below 20%.
5. **"Goal slot 11 returns 0 for every goal type" is wrong.** Point and rectangle goals use `0x44cef0`, which returns 0. The air goal uses `0x44e3a0`, which returns 1 when `flags & 1` and a unit is linked at `+0x1a`. Every air goal built by the handlers here lacks flag 1, so for them it returns 0 and the follower still drops the goal on arrival.
6. **`0x4898b0` does more than clear 0x10.** It also resets the slot target to (0, 0x8000) and runs the `TargetCleared` script, the same way `0x489800` does.
7. **`rand(n)` (`0x4b6c30`) returns 0 without drawing when `n < 2`.** Every `rand(count)` on a list of 1 therefore consumes no RNG.
8. **Follower waypoint pop.** It compares against waypoint **[1]** and only when `count >= 2`, then drops [0]. When `count < 2` it clears has-path. After that, it sets needs-path (flag 2) when a goal exists and either `(mover+0x2e & 4)` or `count < 2`.
9. **SetGoal `0x44f2a0` has more logic than "request a path":**
   - It first cancels the pending path request (`0x40e9c0`).
   - It can reuse the existing path: when `count >= 3` and the last waypoint's cell already satisfies the new goal (slot 5), or when twice the distance to the last waypoint is less than the distance to the goal.
   - The 0x800000 test that skips the 2-point shortcut reads the **unit's `main` head**, not the goal's order.
10. **Badtarget and noChase fields are pointers.** `def+0x231/235/239/23d` are dwords pointing to bit arrays: `bit = (*(def+X))[cat>>5] & (1<<(cat&31))`.
11. **Guard event source (I lead).** `0x406f50` sets unit event word bit 0x4000 when `a > 2b`, otherwise 0x2000. That is likely where Guard_NoMove's 0x4000/0x2000 come from. `0x406f80` is the caller of `0x4897b0(unit, 0x10)`.
12. **Rectangle goal reached.** `0x44dcb0` is vtable slot **5** (cell test). Slot 4 (`0x44cf00`) calls slot 5 with the unit's cell `+0x76/+0x78`.

Everything else in the earlier draft checked out.

---

## 0. Conventions

### Handler signature and order record

- **Signature (V).** `stdcall handler(unit, order, ev) -> int` (`ret 0xc`).
- **Where `ev` comes from (V).** `ev = (pending | word unit+0xBA) & mask`, so it is 0 when the mask is 0. Bits at or above 0x10000 can only come from `pending`.
- **Destroy notification (V).** The destructor calls `handler(u, o, 2)` only when `mask & 2`. The dispatcher zeroed `mask` before the call, so the handler must have set bit 2 during that same call. No handler below does.

**Order record layout (0x56 bytes, V):**

| Offset | Field |
|---|---|
| +0 | vtable `0x4fd2c8` (slot 0 `0x438870`: `pending \|= arg`) |
| +4 | type (byte) |
| +5 | state (byte) |
| +6 | mask |
| +0xA | wake |
| +0xE | unit |
| +0x12 | target-link node: `+0x16` target, `+0x1a` next, `+0x1e` owner = order |
| +0x22 | pos (x, y, z; 16.16) |
| +0x2e / +0x30 | origin words |
| +0x36 / +0x3a / +0x3e | p36 / p3a / p3e |
| +0x42 | flags |
| +0x46 | creation tick |
| +0x4a | next |
| +0x4e | pending |
| +0x52 | goal |

Static order table: entry = `[0x512344] + type*25`; handler at `+4`, static flags at `+0x11` (V).

### Main dispatcher `0x43b7c0`

**Dispatch step (V), repeated while `main` is non-empty:**
1. If `tick >= wake` (unsigned): `wake = 0xFFFFFFFF`, `pending |= 1`.
2. `ev = (pending | word unit+0xBA) & mask`.
3. If `mask != 0 && ev == 0`: **return immediately** (no default idle order is created on this path).
4. `unit+0xBA &= ~ev` (16-bit), `pending &= ~ev`, `mask = 0`.
5. If `ev & 0x10000`: `0x48a0f0(u, s)` for s = 0, 1, 2 (reset aim).
6. Call the handler and apply the return code (jump table `0x43baa4`).

**Return codes (V):**

| Code | Effect |
|---|---|
| 0 | state = 0 |
| 1 | state + 1 |
| 2, 4 | no change |
| 3 | `mask \|= 1`, `wake = tick + 30 + rand(15)` |
| 5, 8 | Unlink from its own list (`bg` if 0x40000, else `main`). If not found, nothing happens. If order ≠ current `[unit+0x5c]` (read after the handler), `flags \|= 0x10000`. Then destructor and free. |
| 6 | Unlink from **`main`** and append at the tail of `main` |
| 7 | Destroy all of `main` (every order except the head taken at that moment gets 0x10000), then all of `bg` via `0x439f80`; **return** |
| 9 | `flags \|= 0x800000`. If `next != 0`: remove as in code 5. Otherwise `state = 0`, `mask \|= 1`, `wake = tick + 30 + rand(30)`. |
| > 9 | `0x439eb0(unit, 1)`; return |

After codes 0–6, 8 and 9, the dispatcher re-reads the `main` head and loops.

**Default idle order (V, `0x43b9ad`).** Runs only when `main` is empty (initially, or after the loop emptied it):
- Conditions: `player = [unit+0x96]`, `[player] != 0`, `player+0x73 in {1,2}`, and `def+0x230 != 0`. `def+0x230` is the order id; the FBI loader converts the string at `0x42c018`.
- It builds `ctor(type, 0, null, 0, 0, 0)` (so 0x200 and 0x400 are cleared), sets `flags |= 0x4000`, and inserts it before the head of `bg` or `main` (by 0x40000) with `0x43ac60`, which ORs in the next order's 0x4000.
- It runs on the next dispatch.

### Background dispatcher `0x43bad0` (V)

For each `bg` order, it skips the order if `mask != 0 && tick < wake`. Otherwise:
- It sets `mask = 0` and calls the handler with **`ev = 0` always**. Pending bits and the unit event word are neither read nor consumed, and `wake` is not reset.
- Return codes:
  - 0, 1, 2, 3, 4: as in the main dispatcher.
  - 5, 8, 9 and > 9: remove, with the 0x10000 test against the `main` head.
  - 6, 7: remove, then stop the loop.
- After each call it restarts from the `bg` head.

None of the handlers in this document have static flag 0x40000 (I).

### Shared helpers

- **`rand(n)` `0x4b6c30` (V).** Returns 0 without advancing the seed when `n < 2`; otherwise `seed' mod n`.
- **`wake(n)` `0x439e80` (V).** `mask |= 1; wake = tick + n`, with `tick = [[0x511de8]+0x38a47]`.
- **`ack(text)` `0x438880` (V).** If `flags & 0x2000`: clear it and call `0x47f780(o.unit, 5, text)`. Treating `0x47f780` as a reply/status call only is I, as is reading code 6 as "arrived".
- **Constructor `0x43a0c0(type, target, pos*, p36, p3a, p3e)` (V):**
  - Sets `state = 0`, `mask = 0`, `pending = 0`, `wake = 0xFFFFFFFF`, `unit = 0`, `next = 0`, `goal = 0`, `+0x46 = tick`.
  - `pos` is copied, or (0,0,0) when null. `flags = static`.
  - `target == 0` clears 0x200; `pos == null` clears 0x400. If 0x200 is then clear, the link is cleared (`0x489690(0)`).
- **Retype `0x438b90(o, type)` (V).** `type` byte set; `flags = (static(type) & ~0x600) | (old & 0x600)`. All other runtime flags are lost.
- **Destructor `0x43a1f0` (V):**
  1. If `mask & 2`: call `handler(u, o, 2)`.
  2. If flag 0x400000: `StopBuilding` script, clear the flag.
  3. If `[unit+0]` exists and the follower's goal is non-null and equals `o.goal`: `SetGoal(0)`, then delete the goal. Otherwise delete `o.goal` if non-null. Then `o.goal = 0`.
  4. **If `!(flags & 0x10000)`: `0x489800(u, 3)`.**
  5. Unlink the target node (`0x489650`).

### Unit, definition and player fields

| Field | Meaning | Status |
|---|---|---|
| `unit+0` | Mover. `[[unit+0]]` is the path follower; `mover+0x2e` bits 0-1: 1 = landed (I) | V offsets |
| `+0x4 + 0x1c*s` | Weapon slot s: `+0` word target unit index, `+2` word (0x8000 = unit target; (0, 0x8000) = cleared), `+0xc` weapon def pointer, `+0x1b` flag byte | V |
| `+0x5c` / `+0x60` | `main` / `bg` list heads | V |
| `+0x66` | Word compared by the air-goal flag-4 test | V (meaning I) |
| `+0x6a/+0x6e/+0x72` | 16.16 position; `+0x6c/+0x74` are the integer x and z words | V |
| `+0x76/+0x78` | Cell | V |
| `+0x7e/+0x80` | footX / footZ | V |
| `+0x86` | Transporter | V |
| `+0x8a` | Tested by VTOL_Standby | Meaning unknown |
| `+0x92` def, `+0x96` player, `+0x9a` script | | V |
| `+0xa2` | Head of reference nodes (node `+4` target, `+8` next, `+0xc` owner object) | V |
| `+0xa6` | Category index for bitsets | V use, I name |
| `+0xa8` | Unit index | V |
| `+0xBA` | 16-bit event word | V |
| `+0xF0` | Last attacker | V offset, I meaning |
| `+0xF4/+0xF5` | Last hit player / reason | V offset, I meaning |
| `+0xFF` | Owner index | V |
| `+0x104` | Build remaining (float) | V offset, I meaning |
| `+0x108` | Health (word, sign-extended) | V |
| `+0x110` | Bits 0-1: layer (1 ground, 2 air); 0xC0000: move state (0 hold, 0x40000 maneuver, 0x80000 roam); 0x300000: fire state (0 hold fire, 0x200000 fire at will); 0x10000000: alive; 0x20000000: tested by Standby_Mine | V offsets and branch values; meanings I |
| `def+0x1c0` | minwaterdepth (word; movement class `+0xA`) | V (`0x44038d`) |
| `def+0x1fa` | maxdamage (dword) | V (`0x42c39e`) |
| `def+0x202` | sightdistance (word) | V (`0x42c3b3`) |
| `def+0x214` | maneuverleashlength (word) | V (`0x42cadd`) |
| `def+0x21c` | cruisealt (word) | V (`0x42c5af`) |
| `def+0x230` | defaultmissiontype (order id byte) | V |
| `def+0x231/235/239` | **Pointers** to primary/secondary/special badTargetCategory bit arrays | V |
| `def+0x23d` | **Pointer** to noChaseCategory bit array | V |
| `def+0x241` | Bit 0x40 builder, bit 0x800 canfly | V |
| `player+0x73` | Controller byte | V |
| `player+0x8c/+0x98` | Energy / metal stored (float) | V |
| `player+0xa4/+0xa8` | Energy / metal storage (float) | V |
| `player+0x108[i]` | Alliance table, indexed by the other player's `+0x146` | V |
| `player+0x146` | Player index | V |

---

## 1. Movement plumbing

### 1.1 Point goal `0x438930(o, pos*, radius)` (V)

1. **canfly** (`def+0x241 & 0x800`): if `[unit+0]` exists and `o.goal` is set, call `follower.SetGoal(0)`, delete the goal, set `o.goal = 0`. Return. No goal is set and `pending` is not touched.
2. Otherwise allocate a 0x14-byte goal `0x44cf60(goal, o, pos.x, pos.z, radius)` (vtable `0x4fd328`):
   - `+4 = o`
   - `+8 = cx = (x - (footX<<19) + 0x80000) >> 20` (arithmetic shift, stored as short)
   - `+0xA = cz` (same with footZ)
   - `+0xC = radius`
   - `+0x10 = (radius/16)²` (rounds toward zero)
3. If `[unit+0] == 0`: stop here. The goal leaks and nothing else changes.
4. If `o.goal` is set: `SetGoal(0)`, delete it, `o.goal = 0`. This `SetGoal(0)` posts 0x80 to **whichever order owns the follower's current goal**; see 1.4.
5. `o.pending &= 0xFFFFFC1F` (clears 0x20..0x200), `SetGoal(goal)`, `o.goal = goal`.

**Point goal vtable `0x4fd328` (V):**

| Slot | Address | Behaviour |
|---|---|---|
| 4 | `0x44d310(unit)` | Reached: `(unit.cx - cx)² + (unit.cz - cz)² <= r_cells²` |
| 5 | `0x44d290(cx, cz)` | Same test on given cell coordinates |
| 7 | `0x44d350` | Heuristic `18*max + 7*min - radius`, floored at 0 |
| 8 | `0x44d2c0` | Goal point `x = (footX + 2*cx) << 19`, same for z; y untouched; returns 1 |
| 11 | `0x44cef0` | Returns 0 |

**Release and set `0x4388d0(o, g)` (V).** Requires `[unit+0]`. Release as in step 4; if `g` is non-null, apply step 5 with `g`.

### 1.2 Rectangle goal `0x438ad0(o, (sx,sz), (w,h))` (V)

- canfly and release handling as in 1.1.
- Constructor `0x44d8a0`, vtable `0x4fd388`:
  - `x0 = sx - footX`, `x1 = sx + w`
  - `z0 = sz - footZ`, `z1 = sz + h`
- Slot 4 `0x44cf00` calls slot 5 `0x44dcb0(unit.cx, unit.cz)`. That is true on the perimeter only: (`cx ∈ {x0, x1}` and `z0 <= cz <= z1`) or (`cz ∈ {z0, z1}` and `x0 <= cx <= x1`).
- Slot 11 = `0x44cef0` (returns 0).

### 1.3 Air goal (0x36 bytes, vtable `0x4fd3b8`) (V)

**Constructor `0x44e2d0(o, pos*)`:**

| Offset | Value |
|---|---|
| +4 | o |
| +8 | flags word = 0x20 |
| +0xA | radius = 0 |
| +0xC | altitude = 0 |
| +0x10 | 0xFFFF |
| +0x12 | o.unit |
| +0x16 | link node (no target) |
| +0x26 | pos |

**Setters:**
- `0x44e6c0(alt)`: `flags |= 8`; `+0xC = alt`. If flags has 0x20: `y = (max(0x485070(&pos), byte [G]+0x1427f) + alt) << 16`, capped at `0x1ff0000`.
- `0x44e730(r)`: `flags |= 0x10`; `+0xA = r`.

**Reached, slot 4 `0x44e5b0(unit)`:**
- `d = hypot(unit.x - gx, unit.z - gz) * (1/65536)`.
- Flag 0x10: reached iff `d < r` (strict), with no other checks.
- Otherwise it requires `d <= 0.5` (`0x4fd3ec`), then:
  - flag 1 needs a linked unit;
  - flag 4 needs `word unit+0x66 == word linked+0x66`;
  - flag 8 needs `|unit.y - goal.y| <= 0x10000`.

**Other slots:** 5 = `0x44cf20` (returns 0, so an existing path is never reused); 11 = `0x44e3a0` (returns 1 only when `flags & 1` and a unit is linked).

### 1.4 Path follower (vtable `0x4fd458`) and event sources

Fields: `+4` goal, `+8` unit, `+0xC` waypoints (short x,z; max 20), `+0x5c` count, `+0x60` timer, `+0x64` flags (1 has path, 2 needs path, 8 dirty) (V).

**SetGoal (slot 1, `0x44f2a0`) (V):**
1. `0x40e9c0(pathfinder, this)` (I: cancel the queued request).
2. If an old goal exists: post **0x80** to the old goal's order (`0x44ced0`: `goal.order.pending |= ev`).
3. `flags &= ~1`; `goal = g`. If `g == 0`: `flags &= ~2`.
4. Otherwise `flags |= 2`, then:
   - If `count >= 3` and `g.slot5(lastWP.x>>4, lastWP.z>>4)`: `flags = (flags & ~2) | 1` (reuse the path).
   - If still no path and `g.slot8(&p)`: when `count >= 3` and `2*|unit - lastWP| < |unit - p|` (`0x4fb440` distances, `0x4e43a0` ftol), set `flags |= 1`.
   - If still no path and the **unit's `main` head** exists without 0x800000: 2-point path `[unit (x,z words), p (x,z words)]`, `count = 2`, `flags |= 1`. Flag 2 stays set.
5. If `timer <= tick - 10`: `timer = 0`. Always `flags |= 8`.

**Update (slot 2, `0x44f1a0`), called first by `0x43dd20`, which then calls steering `0x43d290` (canfly) or `0x43cd20` (V):**
1. If `goal && goal.slot4(unit)`: post **0x20**. If `goal.slot11() == 0`, call `SetGoal(0)`, which posts **0x80** to the same order. For every goal built in this document, arrival therefore delivers `0x20|0x80` and the follower drops the goal while the order still holds `+0x52`.
2. If `count >= 2` and `(word unit+0x6c - wp[1].x)² + (word unit+0x74 - wp[1].z)² <= 25`: drop wp[0], `count--`. If `count < 2`, clear flag 1. Set flag 8.
3. If a goal exists and (`mover+0x2e & 4` or `count < 2`): `flags |= 2`.

**Other entry points (V):**
- **Path result `0x44f080(list, n)`.** `n == 0`: if the goal exists and is not reached, post **0x40**; clear flags 1 and 2; set 8. Otherwise copy up to 20 points, set 1, clear 2, set 8.
- **Pathfinder progress `0x40e750..0x40e974`.** Posts 0x100/0x200. No handler here arms them, and `0x438930` clears them.
- **Order destroy.** Releases the follower goal only if it is this order's goal. **The previous order's goal is never reinstated.** `0x4388b0` (re-assert own goal) has one caller, `0x4875cb` (I: transport).

**Reference events (V):**
- `0x4897b0(unit, ev)` calls `owner.vtable[0](ev)` for every node referencing the unit; for orders that is `pending |= ev`. Its only caller `0x406f80` posts **0x10** (I: unit damaged).
- `0x489740(unit)` posts **0x08**, then unlinks each node, so `order+0x16` becomes 0. Caller `0x486d75` (I: unit removal).

**Pitfalls (V pieces, I consequence):**
- Step 4 of 1.1 posts 0x80 to the owner of the follower's current goal, which can be a **different** order when this order still holds a stale `+0x52`.
- A new order setting a goal while the follower holds another order's goal posts 0x80 to that other order, and it stays pending there.

**Tick order (I).** Dispatch, then background dispatch, then movement. Arrival and no-path events are consumed on the next tick's dispatch.

### 1.5 Engage helpers (V)

**`idle_scan(u)` `0x43b700`:** `0x40b7b0(u, 0, 0)` if `(f110 & 0x300000) == 0x200000`, else 0.

**`create_attack(u, t, force)` `0x43b1f0`:**
```
if u == t: return 0
if !force and (f110&0xC0000)==0: return 0
if !force and (f110&0x300000)==0: return 0
atype = selector(3, u, t, null); if !atype: return 0
if (f110&0xC0000)==0x40000 and !force:
    mtype = selector(2, u, null, &u.pos)
    push_front_inherit(u, ctor(mtype, 0, &u.pos, 0,0,0))
    a = ctor(atype, t, null, 0, 0, p3e = uint16 def+0x214)
    a.origin = (word u+0x6c, word u+0x74)
    push_front_inherit(u, a)
else:
    push_front_inherit(u, ctor(atype, t, null, 0,0,0))
return 1
```
Resulting queues: maneuver `[Attack(leash), Move(back), old…]`; roam, move state 3 or force `[Attack, old…]`.

**`create_repair(u, t, force)` `0x43b400`:**
- `rtype = selector(8, u, t, 0)`; return 0 if none.
- Hold (0) and `!force`: `Move(back)`, then `Repair(p3e = sign-extended word def+0x202)` with origin; return 1.
- Maneuver (0x40000) and `!force`: same with `p3e = uint16 def+0x214`; return 1.
- Roam (0x80000) and `!force`: `Repair(p3e = 0)`, no origin; return 1.
- `force != 0` or move state 0xC0000: return 0.

**Attack_Chase prologue `0x4034a0`:** return 5 when `ev & 0x800`, or `!o.target`, or `ev & 0x10008`, or (`p3e != 0` and `ftol(hypot(word u+0x6c - o+0x2e, word u+0x74 - o+0x30)) >= p3e`, signed).

**`patrol_origin(u, o)` `0x43a020`:**
- If no order in **`main`** has 0x8000: `n = ctor(o.type, 0, &u.pos, 0,0,0)`, appended at the tail of `bg` or `main` (by `n`'s 0x40000), `n.unit = u`, `n.next = 0`. It gets no 0x4000 inheritance and no 0x8000.
- Always `o.flags |= 0x8000`.

**List helpers:**
- `push_front_inherit(u, o)` `0x43acb0`: insert at the head of `bg` or `main` (by `o`'s 0x40000), `o.unit = u`, OR in the next order's 0x4000. A null `o` would crash; ignore that path.
- `0x43ac60(u, o, before)`: insert before a given node.

**Weapon helpers (V):**
- `0x489800(u, s)` (s = 3 means 0, 1, 2): for a slot with flag 0x2 and without 0x10, set 0x10. If its target is not already (0, 0x8000), set it and run the `TargetCleared(s)` script.
- `0x4898b0(u, s)`: for flag 0x2 **with** 0x10, clear 0x10 and do the same target reset and script call.
- `0x48a0f0(u, s)`: target reset and script only.
- `0x48a060(u, t, s)`: `slot = (t.idx, 0x8000)`; `unit+0xBA &= 0x83FF`.
- `0x48a190(u, s)`: the target unit when `+2 == 0x8000` and the index is non-zero, else 0.
- `0x49abb0(u, t, s)`: I (target can be reached or fired on).

Calling `0x489800` "clear weapon targets / enable auto targeting" is I.

---

## 2. Handlers

### 2.1 Move_Ground `0x4031d0` (0x19, static flags 0x402)
```
state 0: if u+0x86: return 7
         ack(0)
         set_point_goal(&o.pos, o.p36 + 4)
         o.mask = 0xE0          # assign
         return 1
state 1: if ev & 0x20: 0x47f780(u, 6, 0); return 5
         return 9
state >=2: return 7
```
- All V. There is no locomotion check.
- For canfly units no goal is set, so the order would wait forever (I: the selector issues VTOL_Move for them).
- **Code 9 (V).** A lone Move gets 0x800000, returns to state 0 after 30–59 ticks and re-goals. Re-goaling posts 0x80 to itself through the release, and the pending clear removes it. After that the 2-point shortcut is skipped. With a successor, the Move is removed.
- When it is removed as head (arrived, or code 9 with a successor), the destructor calls `0x489800(u,3)` (V).

### 2.2 QMove / QPatrol `0x403160` (0x1D/0x1E, flags 0x400)
```
wake(60); return 6
```
V. Treating these as factory rally markers that GetBuilt copies is I.

### 2.3 VTOL_Move `0x40fa20` (0x36, flags 0x402)
```
state 0: if !unit+0 or !(def+0x241&0x800): return 7
         0x4898b0(u,3)
         if u+0x86: 0x48aac0(u, 0, -1, 2)
         0x48b090(u, 1, 1)                          # thiscall
         if ([unit+0]+0x2e & 3) == 1:
             0x43d210(u, 2)
             g = air_goal(o, &u.pos); g.set_alt(int16 cruisealt / 2 rounded toward 0)
             release_and_set(o, g); o.mask |= 0xE0
         return 1
state 1: ack(0); 0x489800(u,3)
         cx = (o.x - (footX<<19) + 0x80000) >> 20 (short); o.x = (footX + 2*cx) << 19; same for z; y kept
         release_and_set(o, air_goal(o, &o.pos))     # flags 0x20 only: reached at d <= 0.5
         o.mask = 0xE0; return 1
state 2: if o.next == 0: 0x47f780(u, 6, 0)
         return 5
state >=3: return 7
```
- All V; the meanings of `0x48aac0`, `0x48b090` and `0x43d210` are I.
- If the unit was not landed, the mask stays 0 and state 1 runs in the same tick.

### 2.4 Park `0x4061a0` (0x1B, flags 0)
```
state 0: if !unit+0: return 7
         if canfly: o.pos = u.pos; retype(o, "VTOL_MOVE"); return 0     # loop runs VTOL_Move state 0 the same tick
         e = int16 u+0x7e; if int16 def+0x1c0 >= 0: e += 3
         cx = u.x >> 20 (logical), cz = u.z >> 20
         set_rect_goal(o, (cx - 4e, cz - 3e), (8e, 6e))              # all 16-bit
         o.mask = 0xE0; return 1
state 1: if ev & 0x20: return 5
         if o.next: return 5
         wake(30); return 0
state >=2: return 7
```
- V. Treating `minwaterdepth >= 0` as "naval" is I. The rectangle goal subtracts footZ for z0 even though `e` uses footX (V).

### 2.5 Stop `0x401c20` (0x2C, flags 0)
```
ack(0)
0x48a0f0(u,0); 0x48a0f0(u,1); 0x48a0f0(u,2)
if (f110&3)==2 and def+0x241&0x800:
    push_front_inherit(u, ctor("VTOL_LANDIFCAN", 0, &u.pos, 0,0,0))
return 5
```
- V. It ignores `ev`.
- **With LandIfCan:** Stop is no longer head, so it is flagged 0x10000 and there is no weapon clear. LandIfCan runs the same tick.
- **Without it:** Stop is head, so the destructor calls `0x489800(u,3)`. If `main` is then empty, the idle order is created and runs on the next dispatch.

### 2.6 Standby `0x405fe0` (0x28, flags 0x20000)
```
state 0: if !unit+0: return 7
         0x489800(u,3); o.mask |= 0x10000; wake(1); return 1
state 1: t = idle_scan(u)
         if t and create_attack(u, t, 0): return 5     # Standby is no longer head: flagged 0x10000, no weapon clear
         o.mask |= 0x10000; wake(30 + rand(30)); return 2   # stays in state 1
state >=2: return 7 (unreachable)
```
- V. It has no movement or leash of its own.
- Units without locomotion get code 7; the idle order is recreated in that unit's next dispatch and runs the one after, so it cycles.
- RNG: `rand(30)` per failed scan.

### 2.7 Standby_Mine `0x406090` (0x29)
```
state 0: if !(f110 & 0x20000000): return 7
         0x489800(u,3); o.mask |= 0x10000; wake(1); return 1
state 1: t = idle_scan(u)
         if t and (t.f110&3)==1 and (u.f110&0x300000)!=0:
             push_front_inherit(u, ctor("SELFDESTRUCT", 0, null, p36=1, 0, 0)); return 5
         o.mask |= 0x10000; wake(30 + rand(30)); return 2   # stays in state 1
```
V. The SELFDESTRUCT order has 0x200 and 0x400 cleared.

### 2.8 VTOL_Standby `0x40f7d0` (0x3F)
```
state 0: if !unit+0 or !canfly: return 7
         0x4898b0(u,3); o.mask |= 0x10000; wake(1)
         o.origin = (word o.unit+0x6c, word o.unit+0x74)
         return 1
state 1: t = idle_scan(u)
         if t and create_attack(u,t,0): o.mask = 0; o.state = 0; return 3
         return 1                                     # mask 0: state 2 runs the same tick
state 2: if canfly and (f110&3)==2:
             if u+0x8a != 0:
                 a = rand(0x10000); r = (rand(32) + 8) << 16
                 p = ((int16 origin.x)<<16 - F1(a,r), 0, (int16 origin.z)<<16 - F2(a,r))   # F1 = 0x4b70ef, F2 = 0x4b7123
                 g = air_goal(o, &p); g.set_alt(int16 cruisealt)
                 release_and_set(o, g); wake(30 + rand(15)); o.state = 1; return 2
             push_front_inherit(u, ctor("VTOL_LANDIFCAN", 0, &o.pos, 0,0,0)); return 5
         o.mask |= 0x10000; wake(30 + rand(30)); o.state = 1; return 2
state >=3: return 7
```
- V. RNG order in the loiter branch: `rand(0x10000)`, `rand(32)`, `rand(15)`.
- Reading F1/F2 as sin/cos and the loiter radius as 8..39 world units is I.
- After code 3 the order restarts at state 0 and re-captures the origin.
- An idle-created order has pos (0,0,0), so LandIfCan is built with pos (0,0,0) and a non-null pointer, keeping 0x400 (V).

### 2.9 Patrol `0x4033a0` (0x1C, flags 0x412)
```
state 0: if !unit+0: return 7
         ack(0); patrol_origin(u, o); wake(1); return 1
state 1: 0x489800(u,3)
         set_point_goal(&o.pos, 0)
         wake(15); o.mask |= 0xE0; return 1
state 2: if ev & 0xE0: o.state = 1; return 6
         t = idle_scan(u)
         if t and create_attack(u,t,0): o.mask = 0; o.state = 1; return 3
         wake(30 + rand(30)); o.state = 1; return 4
state >=3: return 7
```
- **V.**
  - State 1 arms a 15-tick timer plus 0xE0.
  - State 2 on a timer with no engagement waits 30–59 ticks with only the timer armed, then re-goals in state 1. The pending clear drops any stale 0x20/0x80.
  - Any of 0x20/0x40/0x80 in state 2 rotates the order to the tail at state 1.
- **I.**
  - Scan cadence is about 45–74 ticks.
  - Arrival during the wait is noticed after the re-goal (reached again on the next movement tick), up to about 74 ticks late.
- **Engagement.** After code 3 the Patrol keeps `mask = 1` and `wake = engage tick + 30..44`. When it resurfaces with that time already past, it re-goals immediately (V).
- **Loop.** The origin order has the same type and no 0x8000. When it reaches the head, `patrol_origin` finds the others marked and only marks it, giving an A → B → … → origin loop (V).

### 2.10 RepairPatrol `0x405980` (0x21, flags 0x412)
```
state 0: if o.target: o.pos = o.target.pos      # a player issue has 0x200 cleared, so no target
         patrol_origin(u, o); return 1           # no ack, no locomotion check; state 1 the same tick
state 1: if ev & 0xE0: return 6
         set_point_goal(&o.pos, 16)
         wake(60); o.mask |= 0xE0
         P = u.player
         if !(0.2*P.E_max > P.E):                                        # energy >= 20%
             list = 0x47e890(&u.pos, (int16 sightdistance)<<16, filter{vt 0x4fc960, P, &vec, u})
               # callback 0x405d90(cand): cand != u; P.alliance[cand.player.idx] != 0;
               #   (cand.f110&3)==1; ((int16 health) < maxdamage unsigned or build_remaining != 0.0);
               #   not (cand+0xF4 == P.idx and cand+0xF5 == 5)
             if list non-empty:
                 c = list[rand(count)]                                    # no draw when count == 1
                 if P.alliance[c.player.idx] and selector(8,u,c,0):
                     free; return create_repair(u, c, 0) ? 6 : 3           # 3 consumes rand(15), overrides wake(60)
             free
         if !(0.2*P.E_max > P.E) and !(0.2*P.M_max > P.M): return 2        # CORRECTED: both >= 20%, no reclaim
         if !0x47ea40(&u.pos, (int16 sightdistance)<<16, &ePos, &eAmt, &mPos, &mAmt): return 2
         if mPos and 0.2*P.M_max > P.M:        reclaim(mPos); return 3
         elif ePos and 0.2*P.E_max > P.E:      reclaim(ePos); return 3
         elif mPos and P.M + mAmt <= P.M_max:  reclaim(mPos); return 3
         elif ePos and P.E + eAmt <= P.E_max:  reclaim(ePos); return 3
         return 2
  reclaim(p): release_and_set(o, 0); push_front_inherit(u, ctor("RECLAIM", 0, p, 0,0,0)); o.mask = 0
              (the metal-low branch calls release_and_set(o,0) a second time after the push; it is a no-op)
state >=2: return 7
```
- **Argument layout of `0x47ea40` (V):** `(pos, radius, &A, &B, &C, &D)`. A and C are feature pointers passed straight to the RECLAIM constructor. C is tested against metal with amount D; A is tested against energy with amount B.
- The metal/energy naming, and C/D really being the metal feature and amount, is I. The comparison order and directions are V.
- Code 3 or 6 leaves the scan path; 2 keeps the 60-tick timer. There is no RNG unless candidates exist (V).
- **Quirks.**
  - V: after a successful repair engage the code is 6, so RepairPatrol goes to the `main` tail with `mask = 0xE1`, `wake = +60`.
  - I: the Repair order's first goal (`SetGoal`) posts 0x80 to RepairPatrol, because the follower still held RepairPatrol's goal. On resurfacing, state 1 returns 6 at once and the waypoint is skipped.
  - I: RepairUnit's own leash enforcement was not decoded.

### 2.11 VTOL_Patrol `0x410e70` (0x37)
```
state 0: if !unit+0 or !canfly: return 7
         patrol_origin(u,o); ack("Patrolling"); 0x4898b0(u,3)
         if u+0x86: 0x48aac0(u,0,-1,2)
         0x48b090(u,1,1)
         if ([unit+0]+0x2e & 3)==1: 0x43d210(u,2); g=air_goal(o,&u.pos); g.set_alt(cruisealt/2); release_and_set(o,g); o.mask |= 0xE0
         0x489800(u,3); return 1
state 1: o.pending &= 0xFFFFFF1F; return 1
state 2: if ev & 0xE0: return 6
         h = 0x48a980(&u.pos, &o.pos)
         p = (o.x - F1(h, 320<<16), o.y, o.z - F2(h, 320<<16))
         g = air_goal(o, &p); g.set_radius(336); release_and_set(o, g); o.mask |= 0xE0
         if (int16 health) < (maxdamage>>2)*3 (unsigned):
             v = 0x40b530(P.idx, &u.pos, 3840, &vec)
             if v non-empty:
                 release_and_set(o, 0); x = v[rand(n)]
                 push_front_inherit(u, ctor("VTOL_LANDING", x, null, 0,0,0))
                 o.mask = 0; free; return 0             # restarts at state 0 later
             free
         t = idle_scan(u); if t and create_attack(u,t,0): o.mask = 0; return 3
         wake(30); return 2
state >=3: return 7
```
- V. Each 30-tick re-goal releases the order's own goal; the resulting 0x80 is cleared by the pending clear, so there is no self-skip (V).
- I: the geometry of `0x48a980` (heading) and the point 320 units along the approach, and `0x40b530` returning repair pads.

### 2.12 Follow_Ground `0x406300` (0x11, flags 0x200)
```
pre:  if !o.target: return 5
      if u+0x86: return 7
      if target.def+0x241 & 0x800: return 8
state 0: ack("Guarding"); 0x489800(u,3)
         o.p36 = (int16 u.footX + int16 t.footX + 2) << 4
         a = rand(0x10000); r = o.p36 << 16
         o.pos = (-F1(a,r), 0, -F2(a,r))
         return 1
state 1:
 (a) A = target+0xF0
     if A and A.player.alliance[u.player.idx]==0 and (ev & 0x10)
        and !bit(*(def_u+0x23d), A+0xA6):
         if create_attack(u, A, 1): o.mask = 0; return 3
         if u.f110 & 0x300000:
             for s in 0..2 with slot flag &2, &0x10 and !(dword [slot weapon def]+0x111 bit 26):
                 cur = 0x48a190(u,s)
                 if !cur or !0x49abb0(u,cur,s) or bit(*(def_u+0x231+4s), cur+0xA6):
                     0x48a060(u, A, s)
 (b) if (int16 target.health) < target.def+0x1fa (unsigned) and def_u+0x241 & 0x40:
         ty = selector(8, u, target, 0)
         if ty: release_and_set(o,0); push_front_inherit(u, ctor(ty, target, null, 0,0,0)); o.mask = 0; return 3
 (c) h = target.main_head
     if h and h.type and def_u&0x40 and def_t&0x40 and h.flags&0x100000 and h.target != u:
         isBuild = h.type in {"MobileBuild", "BuildingBuild"}
         hasTgt  = (h.flags&0x200 and h.target) or (h.flags&0x400)
         if !isBuild and hasTgt: ty = h.type
         elif isBuild and h.target: ty = "HelpBuild"
         else: goto (d)
         release_and_set(o,0); push_front_inherit(u, ctor(ty, h.target, &h.pos, 0,0,0)); o.mask = 0; return 3
 (d) set_point_goal(target.pos + o.pos, o.p36 / 2 rounded toward 0)
     wake(30); o.mask |= 0x18; return 2                   # stays in state 1
state >=2: return 7
```
- V. Exactly one RNG draw, in state 0.
- Attacks use `force = 1`, so there is no leash and no return Move. The goal is re-set every 30 ticks, and arrival is not armed.
- Wake-ups: 0x10 when the guarded unit is damaged (`0x4897b0` from `0x406f80`), and 0x08 on unlink, which leads to the pre-check `return 5`.

### 2.13 Guard_NoMove `0x4021f0` (0x15, flags 0x20)
```
pre:  if ev & 0x10008: o.state = 3; return 2         # loops: state 3 runs the same tick with ev = 0
      switch state (table 0x402414 = 402233/402256/4022df/402347; >3 returns 7)
state 0: 0x489800(u,3); wake(30); return 1
state 1: link(o, 0x48a190(u,0))
         if o.target and o.target.f110 & 0x10000000:
             o.pos = target.pos; 0x4898b0(u,0); 0x48a060(u, o.target, 0)
             o.p36 = 0; o.p3a = rand(3) + 3; return 1         # state 2 the same tick with ev = 0
         wake(30); return 2
state 2: o.p36 = (ev & 0x4000) ? 0 : o.p36 + 1
         if o.p36 <= o.p3a (signed) and 0x49abb0(u, o.target, 0): o.mask |= 0x7008; return 2
         if rand(100) < 80: o.p36 = 0; return 1              # to state 3
         return 0
state 3: v = 0x40ad80(byte u+0xFF, &o.pos, 640, 0, &vec)
         if v empty: free; return 0
         link(o, v[rand(n)]); 0x48a060(u, o.target, 0); o.state = 1; free; return 2
             # state 1 then re-runs the same tick: reads slot 0, sets p3a = rand(3)+3, enters state 2
```
- V control flow and RNG order.
- I: the meanings of events 0x1000/0x2000/0x4000. Lead: `0x406f50` sets 0x4000 when `a > 2b`, otherwise 0x2000.

---

## 3. Leash and return behaviour

| Issuer | Queue produced | Leash | Return |
|---|---|---|---|
| Standby / Patrol / VTOL_Standby / VTOL_Patrol idle scan, fire at will, maneuver | `[Attack(p3e = maneuverleashlength, origin), Move(pos at engage), …]` | Attack_Chase returns 5 when `ftol(hypot) >= p3e`; 0 means none (V) | Move_Ground back, then the previous order (V) |
| Same with roam or move state 3 | `[Attack, …]` | none | none; the previous order re-goals from where the unit is (V) |
| Hold position or hold fire | no attack (V) | – | – |
| Follow_Ground retaliation | `[Attack(force, p3e = 0), Follow…]` | none | Follow state 1 re-goals when it is next dispatched (V) |
| RepairPatrol | `create_repair` (hold: sightdistance + Move(back); maneuver: leash + Move(back); roam: none) | Enforcement in the Repair handler not decoded (I) | V as listed |
| Follow_Ground repair / build assist | raw `ctor(ty, target, …)`, no leash fields | – | Follow resumes after (V) |

No goal carries over between orders. Destroying the front order nulls the follower goal, and the resumed order moves again only when its goal-setting state runs (V).

## 4. Not decoded / open

- **VTOL_Follow `0x40fbe0`** and **VTOL_RepairPatrol `0x4152f0`:** dumps exist, not decoded.
- **Selector `0x43f0e0`** modes 2, 3 and 8.
- **Scans `0x40b7b0`, `0x40b530`, `0x40ad80`, `0x47e890`, `0x47ea40`:** what they return, beyond the RepairPatrol filter callback `0x405d90`.
- **Unknown sources and fields:** the poster of pending 0x10000; `unit+0x8a`; `mover+0x2e` bits; and `0x48aac0`, `0x48b090`, `0x43d210`, `0x48a980`, `0x49abb0`.
- **Recommended oracle.** Run each handler natively with the goal/follower virtual calls, scans and selector stubbed, seeding `[0x51fc88]`. Record per call: `(state, mask, wake, pending, flags, pos, p36/p3a/p3e, return, inserted orders, goal args, RNG draws)`.
- **Timeline cases that need coverage:**
  - the code-5 0x10000 flag and its weapon-clear consequence;
  - the RepairPatrol code-6 plus 0x80 skip;
  - Patrol late arrival;
  - SetGoal path reuse (`count >= 3`) and the 0x800000 shortcut skip;
  - `rand(n < 2)` not drawing.

# combat

# TA combat order handlers: Attack_Chase, Attack_NoMove, Suppress, stance gating and weapon-target assignment (port spec, adversarially verified)

All addresses are in `TotalA.exe`. **V** means I re-read it in the disassembly during this verification pass. **I** means inferred: a field name, a meaning, or behaviour I did not trace. Nothing is oracle-verified yet, and no repository files were changed.

Helper scripts are in `C:\Users\garet\AppData\Local\Temp\claude\re-scratch\handlers\`: `dis2.py <start> <end>` disassembles, and `dd.py <addr> <n> I|h|s` dumps dwords, words or a string.

## Corrections to the previous draft

1. **Events are masked before the handler sees them (V, 0x43B7FE..0x43B846).** The handler receives `ev = (pending | unit.ev16) & mask`. Only those bits are consumed. Unmasked `unit+0xBA` bits stay pending. The dispatcher's aim reset on 0x10000 fires only when 0x10000 was in the mask.
2. **The handler's unit argument is the order owner `order+0xE` (V).**
3. **Code 7 clears both order lists (V, 0x43BA3D).** The draft called it "can't execute". A Chase issued to an immobile, flying or unarmed unit, or a bad state, therefore wipes the unit's whole queue.
4. **A shot sets 0x400 or 0x800, never both (V, 0x49E4F2..0x49E50B).** It is `ax = commandfire ? 0x800 : 0x400`. A commandfire shot raises only 0x800.
5. **The second 0x1000 source is inside 0x49D580 (V).** That routine has no direct callers in the listing, so it is called indirectly (I: aim callback). It requires slot flag 0x01 and `slot+8 ≠ 0`. On failure it clears slot flag 0x01 and sets 0x1000. For ballistic weapons the failure is `0x49A890 == 0x8000`; otherwise it is `0x49D910` returning 0.
6. **`in_range_unit` pseudo-code.** The garbled "tgt.y + unit.def.170" line is removed; the exact code is below. The water branch halves with `sar 1` (floor), not truncation. The ballistic call takes the shooter−target vector and the dword values at w+0x68 and w+0xC8.
7. **Return fire's event 0x10 goes to every observer of the victim (V).** That means every order whose target link is the victim, not only Guard orders.
8. **Scheduler details added.** It walks units with a round-robin cursor. The alliance test uses the scheduler's own player object. The `isAI` argument is now V. Fire == 2 is re-tested before 0x40B7B0, but not on the interceptor path.
9. **Attack_Chase approach sub-states 2..5 are unreachable (V).** Sub-state 1 never increments p3a.
10. **`goal_point` details (V).** It passes only x and z to the goal. If `move_obj == 0`, the new goal is allocated but never installed (leaked).
11. **Selector.** The 0x1000 underwater test reads the attacker's unit-def. Its surface test is `h < sea`, while `in_range_unit` rejects at `h <= sea`: a boundary mismatch.
12. **Standing_FireOrder** tests only slot flag 0x10, not 0x2.
13. **Guard_NoMove timing (V).** State 2 first runs in the same tick with `ev = 0`, so p36 becomes 1 at once. State 3 re-runs state 1 in the same tick.
14. **Hit-report damages** are masked to 16 bits at the direct-hit site 0x499CBC and then compared as signed ints.

---

## 0. Shared conventions

### Dispatcher 0x43B7C0 (V)
It loops on the live head of the main list. Per iteration:
```
if tick >= o.wake: o.pending |= 1; o.wake = 0xFFFFFFFF
ev = (o.pending | unit.ev16) & o.mask
if o.mask != 0 and ev == 0: return                  # wait
unit.ev16 &= ~ev; o.pending &= ~ev; o.mask = 0
if ev & 0x10000: clear_target(unit, 0..2)           # 0x48A0F0 ×3
code = handler[o.type](o.owner /*+0xE*/, o, ev)     # stdcall, ret 0xC
```

| Code | Effect |
|---|---|
| 0 | state = 0 |
| 1 | state + 1 |
| 2, 4 | keep |
| 3 | wake in 30 + rand(15) ticks |
| 5, 8 | remove |
| 6 | rotate to tail |
| 7 | clear both lists |
| 9 | set flag 0x800000; remove if there is a successor, otherwise state = 0, mask \|= 1, wake = tick + 30 + rand(30) |
| > 9 | 0x439EB0(unit, 1) |

- The loop then continues with the new head.
- When a handler returns without setting a mask, the head runs again in the same tick with `ev = 0`.

### Order record (V)
| Offset | Attack_Chase | Attack_NoMove | Suppress |
|---|---|---|---|
| +4 type, +5 state, +6 mask, +0xA wake, +0x4E pending, +0x42 flags, +0x52 goal | | | |
| +0x12 link object (+0x16 target ptr, +0x1A next, +0x1E observer = the order) | target | target | none (ctor unlinks when static flags lack 0x200) |
| +0x22/+0x26/+0x2A pos 16.16 | state 0 copies the attacker position (use I) | unused | ground point |
| +0x2E/+0x30 short | leash origin x/z | – | – |
| +0x36 p36 | weapon slot (0 = auto-pick) | unused | weapon slot (the dword == 2 test selects the D-gun path) |
| +0x3A p3a | approach sub-state 0..8 | – | approach distance R |
| +0x3E p3e | leash length (0 = none) | – | – |

**Order constructor `0x43A0C0(type, target, pos*, p36, p3a, p3e)` (V):**
- Zeroes the dwords at +0x2E and +0x32; state, mask and pending = 0; wake = 0xFFFFFFFF.
- Stamps the creation tick at +0x46 and sets flags from the static table.
- No target: clears 0x200. No pos: pos = 0 and clears 0x400.
- Links the target, then unlinks it if flags lack 0x200.

**Observer callback (V).** The order vtable 0x4FD2C8[0] = 0x438870 does `pending |= ev`.
- The target-change link `0x489690(t)` unlinks the old target. It links the new one only if `t && t.+0xA6 != 0`.

### Unit fields (offsets V, names I where marked)
| Offset | Meaning |
|---|---|
| +0x00 | Movement object (null = immobile) |
| +0x04 + i·0x1C | Weapon slot i, i = 0..2 |
| +0x5C / +0x60 | Main / background order list |
| +0x6A/+0x6E/+0x72 | Position, 16.16 dwords; +0x6C/+0x70/+0x74 are the integer words |
| +0x7E/+0x80 | Footprint words, used by goal cell coordinates |
| +0x92 | Unit def |
| +0x96 | Player |
| +0x9A | Script |
| +0xA2 | Observer list |
| +0xA6 | Type word (0 = dead/empty) |
| +0xA8 | Index word |
| +0xB8 | Kills word |
| +0xBA | Event word |
| +0x104 | Build fraction float |
| +0x10E | State byte (bit 1 activate, bit 8 building, bit 4 I: cloak) |
| +0x110 | f110 flags |

**f110 bits:**
- Move state: `(f110 >> 18) & 3`. Fire state: `(f110 >> 20) & 3`. V from the Standing_* writers.
- Bit 31: armed (I). The selector and scheduler test it (V).
- 0x20000000: selects Attack_NoMove (V).
- 0x10000000: valid/alive (I; the selector tests it, V).
- `f110 & 3 == 2`: in the air (I).

**Weapon slot, base `unit+4+i*0x1C` (V):**
| Offset | Meaning |
|---|---|
| +0 word A | Target unit index, or ground X |
| +2 word B | 0x8000 = unit target; otherwise ground Z (0x8000 stored as 0x8001) |
| (A, B) = (0, 0x8000) | No target |
| +0xC | Weapon def |
| +0x12 word | Reload countdown (decremented when > 0) |
| +0x1B flags | 0x01 aim started; 0x02 weapon present; 0x0C aim-script index >> 2; **0x10 AUTO** (scheduler-owned; clear = order-controlled) |

**Unit def:**
- +0x170 word: height (I).
- +0x1EE: weapon def pointer (I: primary weapon, used for aircraft).
- +0x214 word: maneuverleashlength (I name; V use).
- +0x231 + 4i: per-slot category bitset pointer (I: badTargetCategory).
- +0x23D: category bitset pointer (I: noChaseCategory).
  - Bitsets are indexed by the target type word: `bits[t>>5] & (1<<(t&31))` (V).
- +0x241: 0x800 canfly (V use); 0x10000000 kamikaze (I); 0x80000 and 0x1000 underwater-related (I); 0x8000000 hover (I).
- +0x245: 0x10 canattack; 0x4000 can D-gun; 0x1000 used by return fire (I).
- +0x230 byte: default idle order type.

**Weapon def:**
- +0xDC dword: range (V).
- +0x111 bits:
  - 0x2 ballistic (V use).
  - 0x10000 water weapon (I).
  - 0x20000 anti-air only (I).
  - 0x4000000 commandfire (V: it drives the 0x800 event).
  - 0x40000000 interceptor (I).
  - 0x100 skipped by the scheduler.
  - 0x80 is paired with target +0x10E bit 0x10.
  - 0x2000000 skips veteran lead (V at 0x48A309).
  - 0x10000000 stockpile-like counter at slot+0x1A (I).
- +0x68 and +0xC8: dwords passed to the ballistic solver.

### Weapon-target primitives (all V)
- **`first_weapon_slot` 0x4897E0 (thiscall):** `f0&2 ? 0 : f1&2 ? 1 : (f2 & 2)`. The last case gives 2, or 0 if no slot has a weapon.
- **`release_to_auto(s)` 0x489800 (thiscall, ret 4):**
  - s == 3 recurses over slots 0 and 1, then does slot 2.
  - A slot with `flags&2 && !(flags&0x10)` gets 0x10 set.
  - If it had a target, the target is set to (0, 0x8000) and the script gets `TargetCleared(slot)`.
- **`take_for_order(s)` 0x4898B0:** the mirror of `release_to_auto`. It acts on slots with `&2 && &0x10`, clears 0x10, and clears the target with TargetCleared.
- **`set_unit_target(u, t, slot)` 0x48A060 (stdcall):** `A = t.+0xA8; B = 0x8000; u.ev16 &= 0x83FF`.
  - The AND drops pending 0x400/0x800/0x1000/0x2000/0x4000.
  - The slot index is not byte-masked.
- **`set_ground_target(u, pos*, slot)` 0x48A0A0:** `A = x sar 16; B = z sar 16` (16-bit), with 0x8000 stored as 0x8001; `ev16 &= 0x83FF`.
- **`clear_target(u, slot)` 0x48A0F0:** if a target exists, sets (0, 0x8000) and queues `TargetCleared(slot)` through 0x4B0A70.
  - Its call to 0x4B07C0("StartBuilding") is a lookup whose result is discarded. Drop it in the port.
- **`clear_target_nocall` 0x48A160:** sets (0, 0x8000) only.
- **`resolve_unit(u, slot)` 0x48A190:** if `B == 0x8000 && A != 0`, returns `units[sext(A)]` (game+0x14357, ×0x118); otherwise null.
  - There is no alive check.
  - Unit index 0 can never be resolved.
- **Firing resolver 0x48A1E0(u, &pos, slot):**
  - Ground target: `(A<<16, (terrainH > sea ? terrainH : sea)<<16, B<<16)`, returns 1.
  - `A == 0` with `B == 0x8000`: returns 0 without clearing.
  - Dead target (`+0xA6 == 0`): clears the target, sends TargetCleared, returns 0.
  - Otherwise returns the target position plus veteran lead when `kills(+0xB8) > 5`, the weapon lacks 0x2000000, and `w+0x68 ≠ 0`.
- **`weapon_range(u, slot)` 0x49ADF0:** `u.slot[slot&0xFF].def+0xDC` (dword).

**`in_range_unit(u, t, slot)` 0x49ABB0 (stdcall, slot byte-masked):**
```
w = u.slot[slot].def
dx = t.x − u.x ; dz = t.z − u.z                      # 16.16 dwords
d2 = lo32((i64)dx*dx >> 32) + lo32((i64)dz*dz >> 32)  # signed
if w.111 & 0x10000:                                   # water weapon
    if !(t.def.241 & 0x80000) and t.y_word > sea: return 0
    if (t.def.241 & 0x1000) and t.y_word + (t.def.170 sar 1) > sea: return 0
    return d2 <= range*range
if u.y_word + u.def.170 <= sea: return 0              # shooter submerged
if t.y_word + t.def.170 <= sea: return 0              # target submerged
if (w.111 & 0x20000) and (t.f110 & 3) != 2: return 0
if (w.111 & 2) and (short)0x49A890(u.x−t.x, u.y−t.y, u.z−t.z, w.[+0x68], w.[+0xC8]) == 0x8000: return 0
return d2 <= range*range                              # range = dword w+0xDC, 32-bit imul, signed <=
```
- `sea` is the byte at game+0x1427F.
- Height words are sign-extended.
- Range is 2-D (x/z) and inclusive.

### Weapon events on unit+0xBA (V)
| Bit | Source |
|---|---|
| 0x400 | Weapon tick 0x49E50B: a shot from a non-commandfire weapon |
| 0x800 | Same site: a shot from a commandfire weapon (instead of 0x400) |
| 0x1000 | 0x49E53A: reload == 0 but `0x49AA80(u, u.pos, &aim, slot)` fails |
| 0x1000 | 0x49D664 inside 0x49D580: solve failure, which also clears slot flag 0x01 |
| 0x2000 | Hit report 0x406F50(proj, enemyDmg, friendlyDmg) on shooter `proj+0x52`: `enemyDmg <= 2*friendlyDmg` |
| 0x4000 | Same: `enemyDmg > 2*friendlyDmg` (signed compare) |

- The hit report is called at 0x499CBC and 0x49A09B (direct hits, 16-bit args) and at 0x49A837 (end of splash). That the splash accumulators start at 0 is I.
- The events are unit-wide: AUTO slots raise them too.
- In 0x49E1A0..0x49E560 the weapon tick reads no f110 bits (V). Callees were not checked.

### Order pending events (V)
- **0x8:** target death. 0x486D75 calls 0x489740(unit), which sends 8 to each observer and unlinks it.
- **0x10:** broadcast to the victim's observers when it is damaged (0x406F80).
- **0x10000:** `+0x10E` bit 4 newly set, in 0x48B090. It also plays reply 0xE and is broadcast to observers.
- **0x20 / 0x40 / 0x80:** goal events (arrived, no path, replaced: meanings from ORDER_QUEUE). `goal_*` clears `pending &= 0xFFFFFC1F` on install.
- **0x1:** timer. `wake(o, n)` 0x439E80 does `mask |= 1; wake = tick + n`.

### Goal helpers (V)
**`goal_point(o, pos*, r)` 0x438930 (thiscall, ret 8):**
- If the unit has canfly: cancel the existing goal (when move_obj and goal exist) and return.
- Otherwise build `0x44CF60(o, pos.x, pos.z, r)` (vtable 0x4FD328):
  - `cell = (coord − sext(fp)<<19 + 0x80000) sar 20`, using footprint words +0x7E/+0x80.
  - `r2 = trunc(r/16)²`.
- If `move_obj == 0`: stop (the goal is leaked).
- Else: cancel the old goal (`move.vtbl[1](0)`, `goal.vtbl[0](1)`, goal = 0), then `pending &= 0xFFFFFC1F`, `move.vtbl[1](new)`, goal = new.
- "Reached" (0x44D290/0x44D310): `dcell² <= r2`.

**`goal_annulus(o, pos*, outer, inner)` 0x438A00:**
- Built by `0x44D3B0(o, x, z, outer, inner)`: `+0x18 = trunc(outer/16)²`, `+0x14 = trunc(inner/16)²`.
- "Reached" (0x44D7C0/0x44D800): `inner2 <= dcell² <= outer2`.
- Install and cancel are identical to `goal_point`.

**`set_goal(o, g)` 0x4388D0:**
- If move_obj exists: cancel the current goal.
- If `g ≠ 0`: clear pending 0x3E0 and install g.
- With `g = 0` it only cancels ("cancel_goal").

**`ack(o, x)` 0x438880:** if flags & 0x2000: clear it and call `0x47F780(owner, 5, x)`.

### Trig and RNG (V)
- **`atan2i(x, z)` 0x4B715A (cdecl):** `fistp(fpatan(x, z) * 10430.378350470453)`, i.e. 32768/π. The rounding mode is the FPU default (I: round-to-nearest).
- **0x48A980(a*, b*) (stdcall):** `atan2i(a.x − b.x, a.z − b.z)`.
- **`msin(ang, v)` 0x4B70EF (cdecl):** `idx = ((ang16 + 0x20) >> 7) & 0x1FF`; `lo32(((i64)tab[idx]*v + 0x1000) >> 13)`.
  - The table 0x509F00 has 512 signed words: 0, 101, 201, 302, …; entry 128 = 8192.
- **`mcos` 0x4B7123:** the same with `ang16 + 0x4000`.
- **`rand(n)` 0x4B6C30 (stdcall):** returns 0 for n < 2. Otherwise the shared RNG gives 0..n−1 (natively run in the ORDER_QUEUE oracle).

---

## 1. Order-type selection 0x43F0E0(out, mode, unit, target, pos) (V)

The switch is on `mode−1`, table 0x4401EC.

**Common prelude:**
- If a target exists and lacks f110 bit 28, the result is 0 for every mode.
- `enemy = target && player(unit).allied[player(target).+0x146] == 0`.

**Mode 3, attack (0x43F154):**
```
if !(udef.245 & 0x10): 0
if !(u.f110 bit31): return udef.241 & 0x10000000 ? ATTACK_KAMIKAZE : 0
w0 = u.slot0.def
if !enemy:                                   # no target, or allied target
    if w0.111 & 0x20000: 0
    if !(udef.241 & 0x800): SUPPRESS
    return (udef.1EE.111 & 0x100) ? AIRSTRIKE : AIRTOGROUND
if (t.f110&3) != 2 and w0.111 & 0x20000: 0
h = t.y_word + t.def.170
if h < sea:
    if !(w0.111 & 0x10000) and !(slot1&2 and w1.111 & 0x10000): 0
elif udef.241 & 0x1000:                      # attacker's def
    if w0.111 & 0x10000: 0
    if slot1&2 and w1.111 & 0x10000: 0
if udef.241 & 0x800:
    wp = udef.1EE.111 & 0x100 ; tf = t.def.241 & 0x800
    wp and !tf → AIRSTRIKE
    !wp and tf → AIRTOAIR
    !tf and !(udef.241 & 0x8000000) → AIRTOGROUND
    !tf and hover → AIRTOGROUNDHOVER
    else 0
u.move_obj ? ATTACK_CHASE : (u.f110 & 0x20000000) ? ATTACK_NOMOVE : (udef.241 & 0x10000000) ? ATTACK_KAMIKAZE : 0
```
- Boundary quirk: the selector treats `h == sea` as surfaced, while `in_range_unit` rejects `h <= sea`.

**Mode 4 (0x43F7E8):** `udef.245 & 0x4000` gives ATTACKSPECIAL. There is no other check.

**AttackSpecial 0x403190 (V):**
```
t = sel(3, u, o.target, null); retype(o, t); o.p36 = 2; return 2
```
- **Retype 0x438B90:** `type = t; flags = (old & 0x600) | (static[t] & ~0x600)`.
  - Every other runtime flag is lost: 0x1, 0x1000, 0x2000 ack, 0x4000 and 0x10000. So a D-gun order never acknowledges.
  - `t == 0` turns the order into type 0 (Activate).
- **Resulting behaviour:**
  - Enemy unit target: Attack_Chase using slot 2.
  - Ground (or an ally with a non-AA w0): Suppress with the `p36 == 2` D-gun path.
  - An allied unit target giving Suppress would fire at whatever the stored pos is (I).

## 2. Attack_Chase 0x4034A0 (type 0x05, flags 0x280) (V)

```
handler(u, o, ev):
  slot = o.p36                                    # dword, read once at entry
  if ev & 0x800 or o.target == 0 or ev & 0x10008: return 5
  if o.p3e != 0:
     d = ftol(_hypot(sext(u.+0x6C) − sext(o.+0x2E), sext(u.+0x74) − sext(o.+0x30)))   # 0x4FB440, 0x4E43A0 truncation
     if d >= o.p3e: return 5
  switch o.state:                                 # > 3 → 7
  0: if u.move_obj == 0 or udef.241 & 0x800 or !(u.f110 & 0x80000000): return 7   # clears both lists
     ack(o, 0)
     o.pos = u.pos (3 dwords); o.p3a = 0
     if slot == 0: o.p36 = first_weapon_slot(u)
     return 1
  1: set_goal(o, 0)                               # cancel movement goal
     if ev & 0x3000: return 1                     # → state 2
     if !in_range_unit(u, o.target, slot): return 1
     take_for_order(u, 0); take_for_order(u, 2)   # slot 1 NOT taken (quirk)
     set_unit_target(u, o.target, slot)
     o.mask = 0x13808; return 2                   # wait: 0x10000|0x2000|0x1000|0x800|0x8
  2: R = weapon_range(u, slot)
     switch o.p3a:                                # > 8 → 7
       0: goal_point(o, &t.pos, R); o.p3a = 1; return 1
       1,2,3,4:
          if |u.y − t.y| (16.16 dwords) > 0x80000:
              goal_point(o, &t.pos, trunc(R/2)); o.p3a = 6; return 1
          a  = atan2i(t.x − u.x, t.z − u.z) + rand(0x8000) − 0x4000
          ox = −msin(a, R<<16); oz = −mcos(a, R<<16)
          goal_point(o, &(t.x+ox, t.y, t.z+oz), trunc(R/4)); return 1   # p3a unchanged
       5: goal_point(o, &t.pos, trunc(R/2)); o.p3a = 6; return 1
       6: goal_point(o, &t.pos, 0);          o.p3a = 7; return 1
       7: goal_annulus(o, &t.pos, R, trunc(R/2));  o.p3a = 8; return 1
       8: goal_annulus(o, &t.pos, 2R, R);          o.p3a = 0; return 1
  3: if ev & 0x40E0: o.state = 1; return 4        # effective hit / goal events → state 1 same tick
     if in_range_unit(u, o.target, slot):
        take_for_order(u,0); take_for_order(u,2); set_unit_target(u, o.target, slot)
        o.mask = 0x148E8; wake(o, 30)             # mask 0x148E9
     else:
        release_to_auto(u, 3)
        o.mask = 0x100E8; wake(o, 30)             # mask 0x100E9
     return 2
```

**Walk-through (V):**
- Every state-2 branch returns 1 with mask 0, so state 3 runs in the same tick with `ev = 0`, and its range test runs at once.
- The flank point is R from the target, toward the attacker ±90° (because the offset is negated).
- p3a sequence: 0 → 1; then 1 either stays at 1 (flank) or goes to 6 → 7 → 8 → 0 → 1. **Sub-states 2..5 are unreachable.**
- In range while moving: slots 0 and 2 plus `slot` are order-controlled, and the unit keeps moving.
- Out of range while moving: all slots go AUTO. The unit-wide 0x4000 from AUTO slots (not cleared by `release_to_auto`) can then end the movement.
- `set_unit_target` clears stale weapon events every time it runs.

**Stance:** the handler reads no move or fire state. A hold-fire unit still fires on a player Attack order (V for the handler and weapon tick body).

**Codes:**
- 5 = done: commandfire shot, target dead or removed, 0x10000, or leash exceeded.
- 7 = clear both lists.

**Port note:** removing the order clears weapon targets through the destroy path (`0x489800(3)` unless flag 0x10000), per ORDER_QUEUE.

## 3. Attack_NoMove 0x402160 (type 0x07, flags 0x280) (V)

```
if o.target == 0 or ev & 0x10808: return 5
switch state (other → 7):
0: ack(o,0); return 1
1: take_for_order(u,0); set_unit_target(u, o.target, 0)   # always slot 0
   o.mask = 0x11808; return 1                             # state 2 then waits
2: release_to_auto(u,3); return 9                         # only 0x1000 reaches here
```
- A normal shot (0x400) is not masked, so it does not end the order.
- Code 9 with a successor removes the order.
- Alone, the order goes to state 0 and waits 30..59 ticks, then re-acks (a no-op, since 0x2000 is already clear) and retargets.

## 4. Suppress (attack ground) 0x4038A0 (type 0x2D, flags 0x410) (V)

```
if ev & 0x800: return 5
switch state (other → 7):
0: if udef.241 & 0x800: return 8
   ack(o,0); o.p3a = weapon_range(u, (byte)o.p36); return 1
1: if o.p36 == 2 (dword):
       take_for_order(u,3); set_ground_target(u, &o.pos, 2)
   else:
       take_for_order(u,0); take_for_order(u,1)
       set_ground_target(u,&o.pos,0); set_ground_target(u,&o.pos,1)   # slot 2 untouched
   o.mask = 0x1C00; return 1
2: release_to_auto(u,3)
   if ev & 0x400: o.state = 1; return 6            # rotate to tail; alone → re-runs state 1 this tick
   if u.move_obj == 0: return 9
   if o.p3a <= 0: return 9                          # signed
   goal_point(o, &o.pos, o.p3a)
   o.mask = 0xE0
   o.p3a −= rand(trunc(weapon_range(u,(byte)o.p36) / 3))   # drawn after the goal install
   o.state = 1; return 4
```
- If `ev` holds both 0x400 and 0x1000, 0x400 wins.
- While approaching, all slots are AUTO.
- Several queued Suppress orders take turns, because each normal shot rotates the current one to the tail.
- Code 9 when alone restarts at state 0, which resets R to the full range.

## 5. create_attack 0x43B1F0(u, t, force) (V)

```
if u == t: return 0
if !force and (u.f110 & 0xC0000) == 0: return 0
if !force and (u.f110 & 0x300000) == 0: return 0
typeA = sel(3, u, t, null); if typeA == 0: return 0
if (u.f110 & 0xC0000) == 0x40000 and !force:
    typeM = sel(2, u, null, &u.pos)                       # result not checked (may be 0)
    M = Order(typeM, 0, &u.pos, 0, 0, 0); push_front(M)
    A = Order(typeA, t, null, 0, 0, zext(word udef.214))
    A.+0x2E = u.+0x6C; A.+0x30 = u.+0x74; push_front(A)   # queue = [A, M, old…]
else:
    push_front(Order(typeA, t, null, 0, 0, 0))
return 1
```
- `push_front` chooses the list by that order's flags & 0x40000 (background vs main).
- It inserts before the current head, sets owner = u, and ORs in `head.flags & 0x4000`.
- There are no 0x1, 0x2000 or 0x1000 flags, no acknowledgement, and no goal cancel of the old head.
- Callers include Standby 0x406002/0x40600F, Patrol 0x4033EB, return fire 0x4070DD and the VTOL handlers.

## 6. Stance effects

| | Fire 0 hold | Fire 1 return fire | Fire 2 fire at will |
|---|---|---|---|
| Scheduler 0x4089A0 fills AUTO slots | no | no | yes |
| Idle scan 0x43B700 | 0 | 0 | 0x40B7B0(u, 0, 0) |
| create_attack (not forced) | rejected | allowed if move ≠ 0 | allowed if move ≠ 0 |
| Return fire (b), retarget AUTO slots | no | yes | yes |
| Order-controlled slots fire | yes | yes | yes |

- **Move 0:** create_attack rejects the unit (it never chases on its own).
- **Move 1:** leash plus a return move.
- **Move 2:** no leash.

**Scheduler 0x4089A0 (thiscall on a per-player object; arg = 1 when player obj ≠ 0 and player+0x73 == 2, V at 0x408C40..0x408CA7):**
```
repeat trunc(word game+0x37EE6 / 30) + 1 times:
  cursor = (cursor && cursor != player.+0x6B) ? cursor + 0x118 : player.+0x67
  u = cursor
  skip unless u.+0xA6 ≠ 0, buildfrac == 0.0, f110 bit31, fire == 2
  for i in 0..2:
    skip unless flags&2 and flags&0x10
    skip if w.111 & 0x100
    skip if !arg and w.111 & 0x4000000
    cur = resolve_unit(u,i)
    if cur and !scheduler.player.allied[cur.player.+0x146] and !(udef.231[i] has cur.type)
           and !((w.111 & 0x80) and cur.+0x10E & 0x10): keep      # no range recheck
    elif w.111 & 0x40000000:
        p = 0x49D120(u,i); p ? set_ground_target(u, p+4, i) : clear_target(u,i)
    elif fire == 2:
        tt = 0x40B7B0(u,i,1); tt ? set_unit_target(u,tt,i) : clear_target(u,i)
```
- A ground target on an AUTO slot is always replaced, because `resolve_unit` returns null for it.

**Standing orders (V):**
- **Standing_FireOrder 0x403100:** `f110 = (f110 & ~0x300000) | ((p36&3) << 20)`. If `p36 ∈ {0, 1}`, it calls `clear_target` on every slot with flags & 0x10 (flag 0x2 not tested). Returns 5.
- **Standing_MoveOrder 0x4030D0:** the same with bits 18/19. Returns 5.

## 7. Return fire 0x406F80(attacker, victim, unused) (V)

Its only caller is the damage path at 0x489DA2.
```
0x4897B0(victim, 0x10)                            # every observer order: pending |= 0x10
if attacker and attacker.+0xA6 == 0: attacker = null
if vdef.245 & 0x1000 and victim.player.obj and victim.player.+0x73 == 2:
    victim.player.+0x74 → +0xD = rand(300) + tick + 30        # rand first
    0x439EB0(victim, 0)
if attacker and victim.player.obj and victim.player.+0x73 ∈ {1,2}
   and vdef.241 & 0x10010000 and victim.buildfrac == 0.0
   and victim.player.allied[attacker.player.+0x146] == 0:
    r = 0
    if main.empty or main.head.flags & 0x20000:
        if !(vdef.23D has att.type) and !(vdef.231[0] has att.type) and in_range_unit(victim, attacker, 0):
            r = create_attack(victim, attacker, 0)
    if r == 0 and victim.f110 & 0x300000:
        for i in 0..2 with flags&2 and flags&0x10:
            if !in_range_unit(victim, attacker, i): continue
            if w_i.111 & 0x4000000: continue
            cur = resolve_unit(victim, i)
            if cur == null or !in_range_unit(victim, cur, i) or (vdef.231[i] has cur.type):
                set_unit_target(victim, attacker, i)
if !(0x438BE0(victim) & 0x80) and (victim.+0xF4 != victim.+0xFF or victim.+0xF5 == 1):
    0x47F850(victim, 2, 0)
```
- `0x438BE0(victim)` returns the main head's flags, or 0 when the list is empty.
- Hold position with return fire: (a) fails inside create_attack because move == 0, so (b) turns the AUTO slots onto the attacker if it is in range.
- Order-controlled slots are never retargeted.

## 8. Guard_NoMove 0x4021F0 (type 0x15, flags 0x20) (V except the candidate search)

```
if ev & 0x10008: o.state = 3; return 2
switch state (table 0x402414; >3 → 7):
0: release_to_auto(u,3); wake(o,30); return 1
1: link(o, resolve_unit(u,0))
   if o.target and o.target.f110 & 0x10000000:
       o.pos = target.pos; take_for_order(u,0); set_unit_target(u,o.target,0)
       o.p36 = 0; o.p3a = rand(3)+3; return 1      # state 2 runs same tick → p36 becomes 1
   wake(o,30); return 2
2: o.p36 = (ev & 0x4000) ? 0 : o.p36 + 1
   if o.p36 <= o.p3a and in_range_unit(u,o.target,0): o.mask |= 0x7008; return 2
   if rand(100) < 80: o.p36 = 0; return 1          # → state 3
   return 0
3: vec = 0x40AD80(u.+0xFF, &o.pos, 0x280, 0, &out)   # I: candidate enemies within 640
   if empty: free; return 0
   link(o, vec[rand(n)]); set_unit_target(u, o.target, 0); o.state = 1; free; return 2   # state 1 re-runs this tick
```

## 9. Open items

1. **Field names.** def+0x231/+0x23D, the unit+0x10E bit meanings, weapon bits 0x100/0x80/0x20000/0x10000, the def+0x241 underwater/hover bits and def+0x245 bit 0x1000 are all I.
2. **Splash accumulators.** Their initial value (0x49A6A3..0x49A837) is I.
3. **Aim routine.** How 0x49D580 is invoked (indirectly, I: aim callback) is not traced.
4. **Not decoded.** Attack_Kamikaze 0x403260, the air handlers, target finders 0x40B7B0 and 0x49D120, candidate search 0x40AD80, 0x439EB0 (I: clear all orders), and the ballistic solver 0x49A890.
5. **Weapon tick callees** were not checked for stance reads.
6. **Oracle candidates:**
   - Attack_Chase states 0–3 with stubbed goal, range and rand; include the flank math with the Q13 table and sub-state reachability.
   - Suppress states 0–2.
   - Attack_NoMove.
   - The 0x438B90 retype rule.
   - Return fire (a)/(b).
   - The scheduler slot loop and cursor.
   - `in_range_unit` boundaries (h == sea, inclusive range).

# build

# TA build-family order handlers: verified port spec

I checked every claim in the draft against the capstone disassembly of `local/original/TotalA.exe`. I used the existing dumps in `%TEMP%\claude\re-scratch\handlers\` plus new dumps of the helpers (`0x41b8d0`, `0x41ba60`, `0x41bcd0`, `0x41bd10`, `0x401180`, `0x4011c0`, `0x4385f0`…`0x439e80`, `0x44d3b0`, `0x44d7c0`, `0x44d8a0`, `0x44dcb0`, `0x489690`…`0x4899b0`, `0x489bb0`, `0x48b090`, `0x480b20`, `0x4b6c30`, `0x419670`, `0x419b00`, `0x43b0b0`, `0x439d80`, `0x43f0e0`). No repository files were modified.

**Marks:**
- **V**: read directly from the disassembly in this pass.
- **P**: established earlier by project oracles or docs.
- **I**: inferred name or meaning.
- Nothing here has been run natively.

## Changes from the draft

| # | Draft claim | Verdict |
|---|---|---|
| C1 | `0x41ba60` sets the "worked on" flag when `work > 0` | **Wrong.** The flag is set when `work >= 0`. A builder with `trunc(wt/30) == 0` still posts 0x8000 and then returns 0. |
| C2 | "RepairUnit reads ev as a byte" (list of byte readers) | **Incomplete.** Reclaim `0x404ad0` and Resurrect `0x404db0` also test `ev` as a byte. |
| C3 | Resurrect with `trunc(wt/30)==0` gives `ftol(inf) = 0x80000000` | **Wrong.** `_ftol` (`0x4e43a0`) does `fistp qword` and returns the low dword. The integer-indefinite value 0x8000000000000000 therefore gives **eax = 0**, so the countdown is 0, not negative. |
| C4 | `rand(feature height)` is always a draw | **Wrong for small n.** `0x4b6c30(n)` returns 0 **without advancing the seed** when `n < 2`. |
| C5 | `0x41b8d0` completes unconditionally | **Incomplete.** It does nothing unless builder `b != 0`, `b` is alive (0x10000000), `bdef+0x156 != 0`, `t != 0` and `t` is alive. The `+0x86` detach and the network echo run only when `t`'s player controller byte (`+0x73`) is 1 or 2. |
| C6 | BuildingBuild S3 is "same as MobileBuild S3" | **Incomplete.** The factory S3 does **not** write `u+0xB0`. |
| C7 | "sound 8/11/0x10", "sound 3/4" | These are all `0x47f780(u, category, NULL)`: reply/feedback calls with a null string. They are not separate sound calls. They are presumably audio-only (I). |
| C8 | `0x4899b0` water rule | **Corrected** in §2. A canfly builder skips the depth test entirely; the `+0x200000` bit decides whether it needs `>= sealevel`. |
| C9 | `0x41ba60` negative work: only the kill | **Incomplete.** It also refunds `metal·|Δ|` to `t+0xD4` (×0.5 / ×0.7 in controller-2 modes), sets `f110 |= 0x2000`, and lowers HP by the truncation difference. Energy is not refunded. |
| C10 | Repair `h` is "at most 1" | **Stronger than that.** `h = 1` exactly whenever `MD·w >= 1`, and `h = 0` when `w = 0`. `0x489bb0` type 10 skips armour and veterancy, so the heal is 1 HP per successful call. The only unread step is the packet apply in `0x489ce0`. |
| C11 | Decay: "loses 11/energycost of progress" | **Confirmed.** Remaining rises by `n/E` with `n = 11`: `work = −BT·n/E`, and `Δremaining = work/BT`. |
| C12 | ReclaimUnit S1 `mask = 0x100E8` | It is `mask |= 0x100E8` followed by `wake(15)`. The result is the same because the dispatcher zeroed the mask. |
| C13 | Goal setters | They also do nothing when the order owner has no locomotion (`u+0 == 0`). A canfly owner has its current goal cancelled and gets no new one. |
| C14 | `0x43b0b0` "count ≥ 1 / < 1" | **Confirmed.** Detail: `count == 0` takes the subtract path, which is a no-op. The 0x10000 flag is set when the order is not the head of the **main** list (`u+0x5C`), even when it is removed from the bg list. |
| C15 | Refund sign in `0x402640` and `0x41ba60` | **Confirmed as an addition.** Opcode `DE E9` is `fsubp st(1)`, so `d4 − metal·(−0.5 or −0.7)`. |
| C16 | VTOL reclaim is "0x4147b0" | The handler entry is `0x414770`. `0x4147b0` is its post-precheck body (jump table `0x414a6c`). Base 30.0 (`0x4fcc50`) and factor −0.5 are confirmed, and there is no `rand` call in it. RECLAIM.md and `construction_world.gd` describe this VTOL handler, not ground Reclaim `0x404ad0`. |
| C17 | 0x43f0e0 alliance | **Confirmed.** `eax = 1` when `attackerPlayer[+0x108 + targetPlayer.idx(+0x146)] == 0`, and `ebx = 1` when that byte is non-zero. CAPTURE and RECLAIMUNIT key on eax; HELPBUILD and REPAIRUNIT key on ebx. A dead target (no 0x10000000) produces no order. |

Everything else in the draft checked out; it is restated below with the corrections folded in.

---

## 0. Key behaviours to act on

1. **Ground Reclaim is `0x404ad0`** (V). The port's current reclaim is VTOL_Reclaim `0x414770` (base 30.0). The ground handler differs:
   - Countdown base is **15.0** (`0x4fc944`).
   - S1 draws `rand(F.heightbyte)`, which is no draw when height < 2.
   - Reply category 11 plays on every 2-tick S3 run.
   - It has an extra S4 state.
2. **Repair heals exactly 1 HP per successful call** when `trunc(wt/30) >= 1` (V, `0x41bd10` + `0x489bb0`). It spends at most 1 energy per call and no metal. Confirm natively, since `0x489ce0` is unread.
3. **Unattended nanoframes decay** (V, `0x402da0`):
   - 300-tick grace, then 30 ticks.
   - Every 0x8000 ("worked on") event re-arms the 30-tick timer.
   - When the timer expires, remaining rises by `11/E` every 11 ticks (a metal refund to the frame's `+0xD4`).
   - The frame is killed (30000, type 9) when remaining reaches ≥ 1.0.
4. **Build-site "arrival" is a perimeter test on the builder's top-left cell** (V, `0x44dcb0`). It is not a distance test.
5. **Resurrect writes `remaining = 0.0` and `hp = 1` directly** (V). `0x41b8d0` is never called, so there is no Activate or unit-complete network echo.
6. **Factory cancel (ev 2) removes the order** (V). If a frame exists:
   - It refunds `ftol((1−remaining)·metal)` (scaled by 0.5/0.7 in controller-2 modes) to factory `+0xD4`.
   - It runs `0x41b8d0(fac, t)` and then kills the frame (30000, type 9).
   - It always runs `0x48b090(fac, 9, 0)` and returns 5.

## 1. Handler convention and records

- **Calling convention (V):** `stdcall handler(unit, order, ev)`, `ret 0xC`.
- **Dispatcher (P):**
  - It zeroes `order.mask` before each call.
  - Return 1 without a re-armed mask runs the next state in the same tick with ev = 0.
  - Return 0 restarts at state 0.
  - The meaning of return codes 5, 7, 8 and 9 is as in ORDER_QUEUE.
- **How each handler reads `ev` (V):**
  - Byte: MobileBuild, HelpBuild, BuildingBuild, RepairUnit, Reclaim, Resurrect.
  - Full dword in the pre-check: ReclaimUnit and Capture (`ev & 0x10008`), and GetBuilt (`ev & 0x8000`).

**Order record (0x56 bytes, P). Build usage:**

| Off | Use |
|---|---|
| +4 type, +5 state, +6 mask, +0xA wake | P |
| +0xE | Owner unit (P) |
| +0x12 | Target link node: +0x16 target, +0x1A next, +0x1E callback (V) |
| +0x22/+0x26/+0x2A | 16.16 position: site centre, feature point, spawn point |
| +0x2E/+0x30 | s16 leash origin (RepairUnit). `0x43b1f0` writes unit `+0x6C/+0x74` there (V) |
| +0x36 p36 | MobileBuild/BuildingBuild/Resurrect: unit type. ReclaimUnit: damage per hit. Reclaim: countdown. Capture: progress |
| +0x3A p3a | BuildingBuild: remaining count. ReclaimUnit: tick accumulator. Capture: required progress. Resurrect: countdown |
| +0x3E p3e | MobileBuild: blocked-retry counter. RepairUnit: leash length (I: from def+0x214 via `0x43a0c0`) |
| +0x42 flags | 0x400000 = StartBuilding was called (V). 0x2000 = ack pending (V). 0x40000 = bg list. 0x100 = counted |
| +0x4E pending, +0x52 goal | V: goal setters do `pending &= 0xFFFFFC1F` |

**Unit fields** (names are I unless marked):

| Off | Meaning |
|---|---|
| +0x00 | Locomotion object; 0 = structure (V use) |
| +0x5C / +0x60 | Main / bg order list heads; next link at order +0x4A (V) |
| +0x66 | Heading word |
| +0x6A/+0x6E/+0x72 | 16.16 x/y/z; +0x6C/+0x70/+0x74 are the integer words |
| +0x76/+0x78 | Top-left cell x/z (V) |
| +0x7E/+0x80 | Footprint x/z (V) |
| +0x86 | Carrier/pad link |
| +0x92 | Definition |
| +0x96 | Player pointer. `[p]` non-zero = in use; `p+0x73` = controller (1, 2 local; 3 remote, I) |
| +0x9A | Script context |
| +0xA2 | Head of links pointing at this unit (V) |
| +0xA6 | Word, non-zero = live slot (V) |
| +0xA8 | Unit id |
| +0xAC | Copied from builder for controller-1 players (V) |
| +0xB0 | Nano-busy timer, `tick + 150/300/900` |
| +0xB8 | Kills (V) |
| +0xBA/+0xBB | Event word. `+0xBA |= 4` from COB set_value; `+0xBB |= 0x80` = 0x8000 (V) |
| +0xBC | Resource request block (V: `+4` E demand, `+8` E granted, `+0xC` E debt, `+0x1C/+0x20/+0x24` metal equivalents) |
| +0xD4 | Float metal accumulator; refunds land here (V) |
| +0xEC | Pointer used for the controller-2 refund scaling (`[p]`, `p+0x73==2`) (V use, I meaning) |
| +0xFF | Owner byte |
| +0x104 | Float remaining (1.0 = new, 0.0 = done) |
| +0x108 | s16 health |
| +0x10E | Byte: 1 active, 2 armored, 4 (reply 0xE/0xF + event 0x10000 to referrers), 8 building (V via `0x48b090`) |
| +0x10F | Byte: bit 0 INBUILDSTANCE, bit 1 value 6, bit 3 value 19 (V) |
| +0x110 | Bits 0–1 air state (2 = flying); 0xC = moving or transported; 0x10 selected; 0x2000 changed; 0x4000 dying; 0xC0000 move state; 0x300000 fire state; 0x10000000 alive; 0x20000000 structure |

**Unit definition** (0x249 bytes at `G+0x1439b`, V offsets):
- `+0x14A/+0x14C` footprint
- `+0x156` must be non-zero for `0x41b8d0` to act
- `+0x15E..+0x172` bbox (particles only); `+0x170` s16 y-offset for the water test
- `+0x184` s16 extra reclaim range
- `+0x186` energy cost (float), `+0x18A` metal cost (float)
- `+0x1AA` armour multiplier
- `+0x1BE` s16 max water depth
- `+0x1EA` buildtime, `+0x1FA` maxdamage (both int)
- `+0x1FE` u16 workertime, `+0x212` u16 builddistance
- `+0x241`: 0x40 builder, 0x800 canfly, 0x200000 (used in the water test), bit 18 activate-when-built, bit 24 (sets `f5 = 7`, `0x4000`)
- `+0x245`: 0x200 can assist/repair, 0x400 canreclamate, 0x800 canresurrect, 0x1000 cancapture. A target with 0x1000 cannot be captured or unit-reclaimed.

**Feature definition** (`[G+0x1426f] + id·0x100`, V):
- `+0x00` name
- `+0x94/+0x96` footprint
- `+0xEC` energy, `+0xF0` metal
- `+0xFA` height byte
- `+0xFE & 0x80` reclaimable

## 2. Shared helpers

| Addr | Behaviour | Mark |
|---|---|---|
| `0x438590(u,o,hdg)` | Script `StartBuilding` with argc 1 (`hdg & 0xFFFF`), echo `0x456290`, `o.flags |= 0x400000` | V |
| `0x4385f0(u,o)` | If `o.flags & 0x400000`: script `StopBuilding()`, `0x456190`, clear the flag | V |
| `0x438700(u,o,m)` | `if (u+0x10F & 1) return 1; o.mask = m|4; return 2` | V |
| `0x480b20` set_value | Values 1..20 use table `0x480c18`: 1→`0x48b090(1,v)`, 5→`10F` bit 0, 6→bit 1, 18→`0x47dac0`, 19→bit 3, 20→`0x48b090(2,v)`. **Every** call (any value) does `+0xBA |= 4` | V |
| `0x48b090(u,bits,set)` | Rising bit 1: `Activate` + reply 3. Falling bit 1: `Deactivate` + reply 4. Bit 8 rising/falling: `StartBuilding()` / `StopBuilding()`. Bit 4 rising: reply 0xE + post 0x10000 to linked orders. Bit 4 falling: reply 0xF. Then `0x41c110`, plus packet 0x11 for controller 1/2 | V |
| `0x439e80(o,n)` | `mask |= 1; wake = tick + n` | V |
| `0x438880(o,str)` | If `flags & 0x2000`: clear it and call `0x47f780(owner, 5, str)` | V |
| `0x4898b0(u,slot)` | Slot 3 recurses to slots 0, 1 and 2. For each slot with flags 2 and 0x10 set: clear 0x10, reset the target to `(0, 0x8000)` if needed, and call script `TargetCleared(slot)` | V |
| `0x489690(link,unit)` | Unlink first. Link only if `unit != 0 && unit+0xA6 != 0` | V |
| `0x489740(unit)` | For each link to the unit, call its callback with **event 8**, then unlink | V |
| `0x4897b0(unit,ev)` | Posts `ev` to every linked order | V |
| `0x47f780(u,cat,str)` | Reply/feedback. Null `str` = category cue only | V call, I effect |
| `0x4b6c30(n)` | `n < 2`: return 0, no draw. Otherwise LCG step on `[0x51fc88]`, return `seed % n` | V |
| `0x4e43a0` `_ftol` | Truncate via `fistp qword`; returns eax, so an invalid value gives 0 | V |

**Build work `0x41ba60(b, t, work)` (V):**
```
if t.rem == 0: return 0
if work >= 0: t+0xBB |= 0x80
if work == 0: return 0
new = t.rem - work/BT;  nr = clamp(new, 0, 1)
dRem = t.rem - nr
dE = E*dRem;  dM = M*dRem
dHP = ftol(t.rem*MD) - ftol(nr*MD)
if work < 0:
    t+0xD4 += -dM * (ctrl2 ? (G+0x37eee==0 ? 0.5 : ==1 ? 0.7 : 1) : 1)    // ctrl2 = [t+0xEC] && byte+0x73==2
    t.rem = nr;  t.hp = max(0, hp+dHP);  t.f110 |= 0x2000
    if nr >= 1.0: 0x489bb0(t, t, 30000, 9, 0)
    ret = 0
else:
    if 0x4011c0(b+0xBC, dE, dM):              // adds demand; grants only if E debt<=0 and M debt<=0
        t.hp = min(hp+dHP, MD) (unsigned);  t.rem = nr;  t.f110 |= 0x2000;  ret = 1
if t.rem == 0: 0x41b8d0(b, t)
return ret
```

**Decay `0x41bcd0(u, n)` (V):** `0x41ba60(u, u, −(float)(BT·n)/E)`.

**Repair `0x41bd10(b, t, w)` (V):**
```
if (s16)t.hp >= MD: return 0
h = ftol((MD*w - 1)/BT + 1);  if h >= 1: h = 1          // all target-def values
e = ftol((E*w - 1)/BT + 1);   if e >= 1: e = 1
if 0x401180(b+0xBC, (float)e):                         // demand += e; grant only if debt[+0xC] <= 0
    0x489bb0(b, t, h, 10, 0); return 1
return 0
```

**Damage `0x489bb0(att, tgt, amt, type, x)` (V):**
- **Type 10:** `amt` is used as-is.
- **Other types:**
  1. If `tgt+0x10E & 2` and `amt < 30000`, armour-scale by `def+0x1AA`.
  2. Then `amt = amt·(25 − min(tgt.kills/10, 5))·4/100`.
- Apply via `0x489ce0`, plus a network send for controller 3 when the type is not 11.

**Complete `0x41b8d0(b, t)` (V):**
1. Guard: `b` alive, `bdef+0x156 != 0`, `t` alive.
2. `[t+0x9E]+0x10 = 0`; `t.f110 |= 0x2000`; `t.rem = 0`.
3. If `t.player` controller is 1 or 2: a structure refreshes BUILDER.GUI (UI). Otherwise, if `t+0x86` is set, detach with `0x48aac0(t, 0, −1, 1)`.
4. If `tdef+0x241` bit 18: `0x48b090(t, 1, 1)`.
5. If bit 24: `t+0xF5 = 7`, `f110 |= 0x4000`.
6. Network echo `0x4560c0(b, t)` for controller 1 or 2.
7. UI flag if either unit is selected.

**Reclaim damage per hit `0x438650(b, t, 15)` (V):**
`max(1, ftol((u32)(wt·(b.kills/5+1)·t.MD·15) / (max(t.metal, 10.0)·300.0)))`. The integer product is 32-bit, then taken as unsigned into 64 bits.

**Can assist `0x4899b0(this=b, t)` (V).** All of these must hold:
- `t != 0`
- `bdef+0x245 & 0x200`
- `(s16)t.hp != MD`
- `(t.f110 & 3) != 2`

Water test:
- `bdef` canfly (0x800): if `bdef & 0x200000` there is no test; otherwise require `t.y(+0x70) + tdef+0x170 >= sealevel` (`G+0x1427f`).
- Not canfly: require `t.y + tdef+0x170 >= sealevel − bdef+0x1BE`.

**Can reclaim unit `0x489960(this=b, t)` (V):** `bdef+0x245 & 0x400 && (t.f110 & 3) != 2 && !(tdef+0x245 & 0x1000)`.

### Goals

Both setters are `thiscall` on the order (V):
- If the owner has no locomotion, nothing happens.
- If the owner is canfly, the current goal is cancelled and none is set.
- Otherwise the new goal replaces the old one and pending is cleared with `&= 0xFFFFFC1F`.

**Site goal `0x438ad0(o, cell, foot)` → `0x44d8a0` (vtable `0x4fd388`):**
```
x0=cx-u.footX; x1=cx+fx; z0=cz-u.footZ; z1=cz+fz
reached(x,z) = ((x==x0||x==x1) && z0<=z<=z1) || ((z==z0||z==z1) && x0<=x<=x1)     // 0x44dcb0
```

**Range goal `0x438a00(o, &pos, outer, inner)` → `0x44d3b0(o, pos.x, pos.z, outer, inner)` (vtable `0x4fd358`):**
```
gcx=(pos.x-(u.footX<<19)+0x80000)>>20 (z likewise)
reached = (inner/16)^2 <= (ucx-gcx)^2+(ucz-gcz)^2 <= (outer/16)^2   // /16 signed trunc; 0x44d800 uses u+0x76/+0x78
```

The movement events 0x20 (arrived), 0x40 (no path) and 0x80 (replaced) are P; their posting sites have not been read.

**Edge-distance test** (MobileBuild S1 no-path branch, Capture S1, RepairUnit S1) (V):
```
d  = (s16)(ftol(hypot(u.x16-T.x16, u.z16-T.z16)) >> 16)
d -= ftol(hypot(u.footX,u.footZ)*8.0)
d += ftol(hypot(Tfx,Tfz)*-8.0)
inRange = d <= (u16)udef.builddistance       // signed compare
```
T is the order position with the definition footprint (MobileBuild), or the target unit with its `+0x7E/+0x80` footprint.

**Heading (V):** `hdg = 0x48a980(&u.pos, &p) − u.heading` (word).

**Selector `0x43f0e0(&out, mode, u, target, &pos)`.** Build-family decisions (V):
- **Enemy branch (eax):** CAPTURE if `def+0x245 & 0x1000`; otherwise RECLAIMUNIT if `& 0x400`. The VTOL_ variants are used when canfly.
- **Allied branch (ebx):** HELPBUILD if `0x4899b0` holds and `t.rem != 0`; otherwise REPAIRUNIT if `0x4899b0` holds (one path also checks `hp < MD` unsigned, which is redundant with `0x4899b0`).

## 3. MobileBuild `0x403a20`

Jump table `0x403f5c` = [`a8d`, `b45`, `df5`, `e0c`, `f2d`]. Flags 0x100508 (P).

**Issue `0x419670(evt)` (V).** For each unit of player `G+0x2a42` that is selected (0x10) and a builder (0x40):
```
0x43afc0(canfly ? VTOL_MOBILEBUILD : MOBILEBUILD, shift=([evt+8]>>2)&1, u, 0, &pos, p36=G+0x2cc4, 0)
pos: cell from cursor G+0x2caa;  x=(fx+2cx)<<19;  z=(fz+2cz)<<19;  y=G+0x2c96<<16
```
The same position is used for every builder.

```
pre: ev&8: reply7 "Construction terminated"; 0x41c110; return 8
     ev&2: 0x41c110; return 5
     state>4: return 7
S0: cx,cz from pos and def footprint; pos.x=(fx+2cx)<<19; pos.z=(fz+2cz)<<19 (y kept); p3e=0
    siteGoal(o,(cx,cz),(fx,fz)); mask=0xE0; return 1
S1: if ev&0x40 && !edgeInRange(u, pos, def footprint): reply7 "I can't reach the construction site"; return 8
    if !0x47db70(def,0,(cx,cz),1):
        if p3e==0: reply7 "Waiting for target area to clear"
        elif p3e>10: reply7 "Target area was blocked"; return 8
        p3e++; wake(30); return 2                           // 11 waits max
    0x4898b0(u,3); 0x47ddc0(def,&pos)
    link(o, 0x485f50(u+0xFF, p36, pos.x,pos.y,pos.z, 0,1,0))
    if !target: reply7 "Unable to create any more units"; wake(300); return 2
    reply9 "Starting construction"; 0x41c110
    0x43adc0(GETBUILT, 1, t, u, 0,0,0)
    StartBuilding(u,o,hdg(u→t.pos)); return 1
S2: return 0x438700(u,o,0xA)
S3: if 0x41ba60(u,t,(float)trunc(wt/30)): particles (0x43e400, 0x4720d0)
    u+0xB0=tick+300
    if t.rem != 0: wake(1); mask|=0xA; return 2
    return 1
S4: reply8 "Building complete"; return 5
```
Any S1 wake other than 0x40 (that is 0x20, 0x80 or the timer) skips the range check. StopBuilding on removal via flag 0x400000 is P/I.

## 4. HelpBuild `0x403f70`

Jump table `0x40425c`. Flags 0x100208 (P).

```
pre: ev&2: 0x41c110; return 5
     target==0: reply7 "Construction terminated"; return 8
     state>4: return 7
S0: need u+0 && def+0x241&0x40 else 7
    r=ftol(sqrt(tfx*tfx + tfz + tfz)*16.0)      // exe bug confirmed (fld st1; fmul st2; fadd st1; fadd st1)
    half=(r - (r>>31))>>1                        // trunc toward 0
    rangeGoal(o,&t.pos, builddist+half, half); mask=0xE8; return 1
S1: ev&0x40: reply7 "I can't get there"; return 8
    t.rem==0: return 5
    0x4898b0(u,3); StartBuilding(hdg(u→t)); 0x41c110; return 1      // no range check
S2: return 0x438700(u,o,0xA)
S3: identical to MobileBuild S3 (including u+0xB0 = tick+300)
S4: reply8 "Building complete"; mask|=2; return 5
```
`tfx`/`tfz` are the target definition footprint.

## 5. BuildingBuild (factory) `0x402640`

Jump table `0x402b5c`. Flags 0x10010C (P). The factory never calls `0x438590`; the yard scripts run through `0x48b090`.

**Issue `0x419b00(name, u, count)` (V):**
1. If `u+0xFF == G+0x2a43`, play cue "addbuild" (count > 0) or "subbuild" (count ≤ 0).
2. If the name contains MAKENUKE or MAKEANTI: `0x43b0b0(BUILDWEAPON, u, 0, count)`.
3. Otherwise `type = 0x488b10(name)`. If `type == 0`, do nothing. Else `0x43b0b0(u+0 ? MOBILEBUILD : BUILDINGBUILD, u, type, count)`.

**`0x43b0b0(type, u, p36, count)` (V).** The list is bg if the order-type flags have 0x40000, else main.
- **count ≥ 1:** if the tail has the same type and p36, `p3a += count`. Otherwise `0x43adc0(type, 1, u, 0, 0, p36, count)`.
- **count ≤ 0:** loop:
  1. Take the **last** matching order; stop if there is none.
  2. If `p3a > −count`: `p3a += count` and stop.
  3. Otherwise `count += p3a`; unlink; set 0x10000 if the order is not the main-list head; destroy with `0x43a1f0`; free.

**Menu count `0x439d80(u, p36)` (V):** sum of p3a over main and bg orders with flag 0x100 and a matching p36.

```
pre ev&2: if t:
            m=(float)(u32)ftol((1.0 - t.rem)*tdef.metal)
            fac+0xD4 += m * (ctrl2([fac+0xEC]) ? (G+0x37eee==0 ? 0.5 : ==1 ? 0.7 : 1) : 1)
            0x41b8d0(fac,t); 0x489bb0(fac,t,30000,9,0)
          0x48b090(fac,9,0); 0x41c150; return 5
pre ev&8: reply7 "Construction stopped"; p3a--; 0x41c150; return 0
state>4: 7
S0: link(o,0); if !(fac.f110&0x20000000): return 7
    if p3a<=0: 0x48b090(fac,1,0); return 5
    0x48b090(fac,1,1); return 1
S1: return 0x438700(fac,o,2)                              // mask 6
S2: piece=-1; script QueryBuildInfo(&piece) (0x4b0bc0)
    o.pos = *0x43e060(&tmp,fac,piece)                     // all three coords
    cells from o.pos and def footprint
    if !0x47db70(def,0,cells,fac.f110&3): wake(15); mask|=2; return 2
    link(o,0x485f50(fac+0xFF,p36,o.pos,0,1,0))
    if !t: reply7 "Unable to create any more units"; wake(300); mask|=2; return 2
    reply9 "Starting construction"; 0x48aac0(t,fac,piece,1)
    t.f110: copy bits 0xC0000 then 0x300000 from fac
    0x43adc0(GETBUILT,1,t,fac,0,0,0); 0x48b090(fac,8,1); 0x41c150; return 1
S3: if !t: return 7
    if 0x41ba60(fac,t,(float)trunc(wt/30)): particles
    // no u+0xB0 write
    if t.rem != 0: wake(1); mask|=0xA; return 2
    return 1
S4: 0x47f780(fac,8,NULL); 0x48b090(fac,8,0); 0x41b8d0(fac,t); link(o,0); p3a--; 0x41c150; return 0
```

## 6. GetBuilt `0x402da0`

Flags 0x224 (P). Reads `ev` as a dword.

```
if u.rem == 0.0:
   0x41c110(u)
   if u+0 != 0:
      conv=0; B=o.target
      if B:
         for q in B.mainList (+0x5C, next +0x4A):
             if q.type==QMove:   T=0x43f0e0(&,2,u,0,&q.pos)
             elif q.type==QPatrol: T=0x43f0e0(&,9,u,0,&q.pos) else T=0
             if T: 0x43adc0(T,1,u,0,&q.pos,0,0); conv=1
         if u.f110 & B.f110 both have 0x10000000 and neither has 0x4000:
             u.f110 copies 0xC0000 then 0x300000 from B
             if u.player in use && controller==1: u+0xAC = B+0xAC
      if !conv: 0x43adc0(PARK,1,u,0,0,0,0)
   return 5                                   // structures: no PARK
S0: 0x4898b0(u,3); wake(300); mask|=0x8000; return 1
S1: wake(30); mask|=0x8000; return 1
S2: if ev&0x8000: wake(30); mask|=0x8000; return 2
    if ev&1: wake(11); 0x41bcd0(u,11)
    mask|=0x8000; return 2
state>2: 7
```

## 7. ReclaimUnit `0x404730`

Jump table `0x404ab0`, 6 states. Flags 0x100200 (P).

```
pre: target==0 || ev&0x10008: return 5; state>5: 7
S0: if u+0==0 || !(def+0x245&0x400): reply7 "Reclamation failed"; return 7
    if !0x489960(u,t): reply7 "That unit cannot be reclaimed"; reply7 "Reclamation failed"; return 8
    0x438880(o,"Reclaiming"); 0x4898b0(u,3); return 1
S1: if ev&0x20: return 1
    siteGoal(o, t cell, t foot); mask|=0x100E8; wake(15)
    p36=0x438650(u,t,15); p3a=0; return 2
S2: if ev&0x40: return 9
    StartBuilding(hdg(u→t)); return 1
S3: return 0x438700(u,o,0x10008)
S4: 0x47f780(u,11,NULL); return 1
S5: R = (u16)udef.builddist + (s16)tdef+0x184
    if (s32)(hi32(dx16*dx16) + hi32(dz16*dz16)) > R*R  ||  !0x489960(u,t):
        wake(15); StopBuilding(u,o); return 0
    if p3a >= 15: 0x489bb0(u,t,p36,5,0); p3a=0
    u+0xB0=tick+900; particles (0x472200); wake(2); p3a+=2; return 2
```
S1 re-goals every 15 ticks until 0x20 arrives. `dx16`/`dz16` are unit minus target 16.16 positions, squared as 64-bit.

**Timing:** a hit lands every 8 runs, i.e. every 16 ticks, the first one 16 ticks after S5's first run. The target's death posts event 8, which gives return 5. Resource credit on a reclaim kill is not in this handler (open).

## 8. Reclaim (feature) `0x404ad0`

Jump table `0x404d8c`, 6 states. Flags 0x100800 (P). Reads `ev` as a byte.

```
pre (all states): id=0x421da0(&o.pos,&cell,&foot); id==0xFFFF: reply7 "Reclamation failed"; return 8
     F=featdef[id]; !(F+0xFE&0x80): return 8; state>5: 7
S0: if u+0==0 || !(def+0x245&0x400): return 7
    siteGoal(o,cell,foot); mask=0xE0; return 1
S1: if ev&0x40: return 8
    p36 = ftol(15.0 - (F.energy+F.metal) * -0.5)             // = ftol(15 + (E+M)/2)
    pt.x=(foot.x+2cell.x)<<19; pt.z=(foot.z+2cell.z)<<19
    pt.y=(0x4b6c30(F.height) + 0x485070(&pt)) << 16            // no draw if height<2
    StartBuilding(hdg(u→pt)); return 1                          // pt is local only
S2: return 0x438700(u,o,0)
S3: 0x47f780(u,11,NULL); then S4 body
S4: wake(2); p36-=2; if p36<=0: return 1
    u+0xB0=tick+300; if p36>15: particles; return 2
S5: 0x4237d0(u,&o.pos); return 5                                // credit + FeatureReclamate (P)
```
S3 stays in S3 (return 2) while `p36 > 0`, so the reply cue fires on every 2-tick run. When the countdown reaches ≤ 0, the order goes S3 → S4 (one more 2-tick run) → S5.

## 9. Capture `0x404270`

Jump table `0x404714`, 6 states. Flags 0x200 (P).

```
pre: target==0 || ev&0x10008: reply7 "Capture failed"; return 8; state>5: 7
S0: u+0==0: 7; !(def+0x245&0x1000): 7
    tdef+0x245&0x1000: reply7 "That unit cannot be captured"; 8
    t.rem != 0: reply7 "That unit is a cloud of vapor and cannot be captured"; 8
    0x438880(o,"Capturing")
    b = ftol(E*30*0.0005 - M*30*(-0.0071428573) - (-150.0))     // target def; = 0.015E + 0.2142857M + 150
    if b >= 1800: b = 1800
    b = (u32)(((s16)hp + MD) * b) / (u32)(2*MD)
    p3a = trunc((s32)(b*(t.kills/5 + 10)*10) / 100)
    0x4898b0(u,3); siteGoal(o, t cell, t foot); mask=0x100E8; return 1
S1: ev&0x40: return 8 (no message)
    if !edgeInRange(u,t): return 0                // p36 kept; S0 recomputes p3a and re-goals
    StartBuilding(hdg(u→t)); return 1
S2: return 0x438700(u,o,0x10008)
S3: 0x47f780(u,11,NULL); return 1
S4: if t+0 && (t.f110&0xC): StopBuilding(u,o); wake(30); return 0
    if p36 >= p3a: return 1
    particles; u+0xB0=tick+900; p36+=2; wake(2); return 2         // no range recheck
S5: 0x488570(t, u+0x96, 0); 0x47f780(u,0x10,NULL); return 5
```

**Possible loop:** 0x20 arrives, but the unit is out of edge range. S1 then returns 0, S0 sets a new goal, and the unit is already on it. Check this natively.

## 10. Resurrect `0x404db0`

Jump table `0x4052d8`, 7 states. Flags 0x200 (P). Reads `ev` as a byte.

```
pre (states 0-5 only): feature lookup as Reclaim; 0xFFFF: reply7 "Resurrection failed"; 8; !(0x80): 8
state>6: 7
S0: u+0==0 || !(def+0x245&0x800): 7; siteGoal(o,cell,foot); mask=0xE0; return 1
S1: ev&0x40: 8; pt as Reclaim S1 (same 0x4b6c30(height) call), local only; StartBuilding(hdg(u→pt)); 1
S2: return 0x438700(u,o,0)
S3: strncpy(buf,F.name,64); cut at first '_' within 64 bytes; p36 = 0x488b10(buf) & 0xFFFF
    p36==0: reply7 "Ressurection failed"; 8
    p3a = ftol((double)newdef.buildtime * 0.3 / (double)trunc(wt/30))   // div by 0 → 0 (C3)
    0x47f780(u,11,NULL); return 1
S4: if p3a-- == 0: return 1
    particles (0x4720d0); u+0xB0=tick+300; wake(1); return 2          // runs p3a+1 times
S5: link(o,0x485f50(u+0xFF,p36,o.pos,0,1,0))
    !t: reply7 "Unable to create any more units"; wake(300); return 2
    fr=0x4815f0(&o.pos); if 0x421e60(fr) >= 0xFFFB: return 8       // leaves an unfinished, un-GetBuilt unit
    inst=[G+0x1420b] + fr.word(+0xA)*0x30; if inst: copy 6 bytes inst+0x20 → t+0x64
    0x4246b0(0x4815a0(&o.pos,0)); if 0x435100(G+0x391e9)==3: 0x451df0 packet 0x0F
    t.rem=0.0; t.hp=1; 0x41c110(u); return 1
S6: reply8 "Resurrection complete"; T=0x43f0e0(&,8,u,t,0)
    if T: 0x43acb0(u, new Order via 0x43a0c0(T,t,0,0,0,0)); return 5
```

## 11. RepairUnit `0x405300` and RepairUnitNoMove `0x405740`

**RepairUnit.** Jump table `0x405724`. Reads `ev` as a byte.

```
pre: target==0: reply7 "Repairs unsuccessful."; 5
     if p3e && ftol(hypot(u+0x6C - p2e, u+0x74 - p30)) >= p3e: return 5      // silent leash
     if (t.f110&3) != 1: reply7 "Repairs unsuccessful."; 5
     state>4: 7
S0: u+0 && def+0x241&0x40 && t.rem==0.0 else 7; 0x438880(o,"Repairing"); return 1
S1: ev&0x40: 8
    if !edgeInRange(u,t): siteGoal(o,t cell,t foot); wake(30 + 0x4b6c30(30)); mask|=0xE8; return 2
    0x4898b0(u,3); StartBuilding(hdg(u→t)); return 1
S2: return 0x438700(u,o,8)
S3: if (u32)(s32)t.hp >= MD: return 1
    if t.f110&0xC: StopBuilding(u,o); wake(15); return 0
    u+0xB0=tick+150; if 0x41bd10(u,t,(float)trunc(wt/30)): particles
    wake(1); mask|=8; return 2                                      // no range recheck
S4: reply10 "Unit repaired"; return 5
```
The pre-check reads `t.f110` once; S3 uses that cached low byte.

**RepairUnitNoMove:**
```
pre: target==0: reply7 "Repairs unsuccessful."; 5; state>2: 7
S0: !(def+0x241&0x40): 7; t.rem==0 && u+0x10E&1 else 8; 0x4898b0(u,3); return 1
S1: hp >= MD (unsigned): 1; t.f110&0xC: 1
    u+0xB0=tick+150; repair as RepairUnit S3; wake(1); mask|=8; return 2
S2: reply10 "Unit repaired"; return 5
```
There is no locomotion check, no StartBuilding and no range test.

**RepairPatrol `0x405980` (I, not decoded):**
- Scans for units (`0x47e890`) and features (`0x47ea40`).
- Uses create-repair `0x43b1f0`/`0x43b400`, which sets leash origin = unit position and passes `def+0x214`.
- Push-front-inherits RECLAIM.
- Patrol origin comes from `0x43a020`.

## 12. Porting notes and open items

**Event sources (V):**
- Event 8 comes only from `0x489740` (target removal).
- Event 4 comes from **any** COB set_value, so handlers must re-test `+0x10F` bit 0, as `0x438700` does.
- Event 0x8000 comes from `0x41ba60` with `work >= 0`.
- Event 0x10000 comes from `0x48b090` when bit 4 rises.
- The posting sites and immediacy of 0x20/0x40/0x80 are unverified.

**RNG draws, in order (V unless noted):**
- Reclaim S1 and Resurrect S1: `0x4b6c30(heightbyte)`, only when height ≥ 2.
- RepairUnit S1 out-of-range: `0x4b6c30(30)`.
- Dispatcher codes 3 and 9 (P).
- Particles (`0x4720d0`/`0x472200`) and `0x47f780` were not checked for RNG use.

**Not decoded:**
- BuildWeapon `0x402b70`.
- VTOL variants `0x413d80`, `0x414380`, `0x414a80`, `0x414e70`, `0x4152f0` (`0x414770` is only spot-checked).
- Internals of `0x47db70`, `0x43e060`, `0x48aac0`, `0x4237d0`, `0x488570`, `0x489ce0`, `0x43a1f0`.
- Resource credit on a reclaim kill.
- Meaning of `def+0x156` and `unit+0xEC`.

**Suggested native oracles:**
1. Handler timelines over scripted (ev, tick) inputs, with `0x41ba60`, `0x41bd10`, `0x438650` and `0x4b6c30` real.
2. Reached-test grids for `0x44dcb0` and `0x44d7c0`.
3. `0x41bd10` + `0x489bb0` type-10 HP deltas across workertime values 0, 29, 30 and 300.
4. `0x43b0b0` add/subtract sequences plus the ev-2 cancel refund in each `G+0x37eee` mode.
5. Resurrect with workertime < 30 (expect an immediate spawn).
6. The Capture S1 out-of-range loop.
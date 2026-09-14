# Cursor projection and hover picking

## Screen to world (`godot/cursor_projection.gd`, `0x484b50`)

The original converts the cursor's view position (scrolled map pixels) into a 16.16 world point on the terrain:

1. **Clamp.** `sx` and `sy` are clamped to `[0, mapW-1]` and `[0, mapH-1]` (map pixels, game +0x14223 / +0x14227). `x = sx << 16`.
2. **Step.** Start at row `zi = (sy & ~15) + 128` and step up 16 px at a time, at most 9 samples. At each row the surface height is `h = max(sea, 0x485070 bilinear height)`, where an off-grid `-1` becomes sea. Stop at the first row whose projected surface `s16(zi) - (h >> 1)` is at or above `sy`.
3. **Interpolate.** Sample the next row down (`zi + 16`) the same way, giving `s1`. Then `z = zi + ((sy - s0) << 20) / (s1 - s0)`, a truncating signed division, and `y = surface height at z`, shifted `<< 16`.
4. **Unreachable fallback.** The fallback branch (return the first sample) and the not-found exit cannot happen with byte heights. The port keeps both anyway.

**Evidence.**
- `tools/native_screen_to_world.py` runs the original routine and its height sampler unmodified. It covers 240 scenes (random, cliff-heavy 0/255, and x- or z-ramped grids from 2×2 to 63×63 cells; sea levels 0, 40, 255 and random; map pixel sizes up to 39 px short of the grid) and 14,400 cursor positions, including points outside the map.
- `godot/compare_native_screen_to_world.gd` matches **14,400 / 14,400**. This runs in `-Native`.
- **Mutation testing.** Seven of eight deliberate port mutations were caught:
  - `<` for `<=`
  - starting at +112
  - a missing sea floor
  - `<< 19`
  - rounding the division
  - the step count
  - the height of the first sample
- **The survivor** replaces the interpolation guard with `sy >= s0`. That condition always holds after the loop, so it is equivalent to the original.

## Viewer use

- **Drawing.** Objects are drawn at `z - (y >> 1)` (see PLAYER_CONTROLS.md, Height projection).
- **Unit picks and box select** use that view position.
- **Terrain orders** (move, group move, build placement, reclaim, ground attack, the D-gun ground fallback) now use `ground_point(view)`, which is 0x484b50 over the loaded height grid with `mapW = width × 16`. That map pixel size is an assumption: the writer of +0x14223 was not found.
- **`--verify-projection`** checks that clicking where the ground under a raised unit is drawn resolves to that ground cell (within one 16 px row), and that flat ground maps to itself.

## Recovered but not yet ported

The full research, including an adversarial verification pass, is below. It covers:
- per-frame cursor handling;
- button routing (0x498f70, box drag thresholds);
- the build ghost (0x4197d0) and build click (0x419670);
- hover picking by the rotated root-piece bounding box (0x48cd80 / 0x48c6a0) and the visible-list rebuild;
- the cursor type selector (0x48d220 / 0x43e490, partly decoded);
- camera clamp, edge scroll, follow and minimap centring.

The viewer still picks units by footprint rather than the model bounding box. It does not yet show original cursor ids, and its camera is not the original scroll model.

## Part B: Port-ready spec

This spec is built only from the confirmed readings above. Offsets are from `G=[0x511de8]`. **(I)** marks an inferred meaning.

### 0. Constants and layout
- **Main view rect** (inclusive): `L=128, T=32, R=screenW−1, B=screenH−33`, so `viewW=screenW−128` and `viewH=screenH−64`. The +128/+32 in every projection are L and T.
- **Screen projection of world point (x, y, z):**
  - `sx = x − camX + 128`
  - `sy = z − camY − (y>>1) + 32`
  - Integer parts are used; the unit hit test works in 16.16 first, see §2.2.
- **Scroll extents:** `scrollW = mapW_px − cfg1(default 32)`, `scrollH = mapH_px − cfg2(default 128)`.
- **Height cells** are 16 px. Each cell record is 13 bytes: +4 height (u8), +8 occupant (u16), +10 row back-offset (u8), +11 column back-offset (u8).
- **Rect test** (0x4b6720): inclusive on all four sides.

### 1. Per-frame input (game view, handler 0x499200)
1. `updateCursor(mouse)` (0x498da0), §1.1.
2. Choose the path:
   - If `inView && buildMode(0xe)`: run the build ghost (§1.4). Hover and cursor id are not touched.
   - Else if `!inView && !overMinimap`: cursor = 0x13.
   - Else: `hovered = pickHover()` (§2) and `cursor = chooseCursor(mode)` (§2.3). The cursor image changes only when the id changes.
3. Handle the button message (§1.5).
4. Run the frame step (0x496790). The sim tick includes follow/scroll-to (§3). Then edge scroll (§3), skipped when `G+0x37ebe & 1`. Then rebuild the visible list (§2.1). Then draw.

### 1.1 Cursor world point
```
if inRect(minimapRect, mx, my) && !(flags & BOXDRAG):
    sx = (mx - mmX0) * scrollW / mmW ; sy = (my - mmY0) * scrollH / mmH   // C truncating
    flags: set OVERMINIMAP, clear INVIEW
else:
    sx = camX + clamp(mx, L, R) - L ; sy = camY + clamp(my, T, B) - T
    flags: clear OVERMINIMAP; INVIEW = inRect(view, mx, my)   // unclamped mouse
ANY = OVERMINIMAP || INVIEW
cursorPos = screenToWorld(sx, sy)
cursorCell = (cursorPos.x >>> 20, cursorPos.z >>> 20)
cursorOccupant = resolve(cell)   // id<0xfffb: id; 0xfffe: follow back-link, return that id; else 0xffff
```

### 1.2 screenToWorld(sx, sy) → 16.16 (x, y, z)
```
sx = clamp(sx, 0, mapW_px-1); sy = clamp(sy, 0, mapH_px-1)
x = sx << 16
hs(z) = max(sea, heightAt(x, z))                 // heightAt -1 (off-grid) -> sea
zi = (sy & ~15) + 128
while true:                                      // at most 9 steps; always terminates by zi = sy&~15
    s0 = zi - (hs(zi) >> 1)
    if s0 <= sy: break
    zi -= 16
s1 = (zi+16) - (hs(zi+16) >> 1)                  // provably s1 > sy >= s0
z = (zi << 16) + ((sy - s0) << 20) / (s1 - s0)   // signed int division, truncates
y = hs(z_int) << 16                               // integer height, water surface if below sea
return (x, y, z)
```
`heightAt` (0x485070) works on the signed 16-bit integer parts:
```
cx = x >> 4; fx = x & 15; cz = z >> 4; fz = z & 15
if cx < 0 || cx+1 >= Wc || cz < 0 || cz+1 >= Hc: return -1
d(v) = trunc(v / 16)
top = h00 + d((h10-h00)*fx)
bot = h01 + d((h11-h01)*fx)
return top + d((bot-top)*fz)
```

### 1.4 Build ghost (0x4197d0) and build click (0x419670)
- **Ghost rectangle:** `def = defs[G+0x2cc4]`, `fx, fz` = words at def+0x14a and def+0x14c.
  ```
  cellX = (short)((cursor.x - (fx<<19) + 0x80000) >> 20)   // sar; same for z
  ghost rect = (cellX*16, cellZ*16) to (+fx*16, +fz*16)
  ```
- **Legality:** `legal = 0x47d2e0(def, cellX | cellZ<<16, 0, player[G+0x2a42]) & 1`, stored in flags bit6.
- **Ghost height:** `ghostH = u8(legal ? 0x47c780() : 0x47d820(def, cells))`, stored to both +0x2c96 and +0x2ca2. The meaning is (I) and these routines were not traced.
- **Build click** (legal only): order position is
  - `x = (fx + 2*cellX) << 19`
  - `z = (fz + 2*cellZ) << 19`
  - `y = ghostH << 16`
  - It goes to the selected builders of player G+0x2a42 as MOBILEBUILD, or VTOL_MOBILEBUILD when def+0x241 & 0x800.
  - Shift held (mouse modifier bits & 4): stay in build mode (flag 0x20). Otherwise return to mode 1.
  - Illegal: plays `notoktobuild`.

### 1.5 Left/right button routing
- **0x204 (right down):** 0x499100, which issues an order at cursorPos through 0x48cf30.
- **Mode ≠ 1, 0x201 (left down):** 0x498f70.
- **Mode 1, not dragging:**
  - 0x201 inside the view: start a box drag. Set flag 0x08, record `start = now`, set both corners to the integer (x, y, z) of cursorPos, cursor 0x13.
  - 0x201 outside the view but over the minimap: if `G+0x37efa==1`, start a minimap drag (flag 0x10; each frame centres the camera through 0x41d0f0 until 0x202). Otherwise 0x498f70.
- **Mode 1, dragging:**
  - Any message except 0x202: end corner = integer cursorPos.
  - On 0x202: clear 0x08. If `now < start+25 && |x0−x1| < 32 && |z0−z1| < 32` (world px), treat as a click (0x498f70). Otherwise box select (0x48c390, corners projected with §0).
- **0x498f70 by cursor id:**
  - Build mode: build click (§1.4).
  - Id 0xf: click select (0x48c7f0).
  - Id ≥ 0x11: deselect only if `G+0x37efa==1 && mode==1`.
  - Otherwise: issue an order at cursorPos (0x48cf30).

### 2. Hover pick
#### 2.1 Visible list (rebuilt in the frame step)
For each unit slot in slot order with typeId ≠ 0 (all fields are integer parts):
```
bottomY = def.minY + u.y
if (u.flags110 & 3) != 1 and cell(u.pos) exists and cell.h < bottomY: bottomY = cell.h
left   = def.minX + u.x - camX + 128
right  = def.maxX + u.x - camX + 128
top    = def.minZ + u.z - camY - ((def.maxY + u.y) >> 1) + 32
bottom = def.maxZ + u.z - camY - (bottomY >> 1) + 32
keep if left<=R && right>=L && top<=B && bottom>=T
        && (u.owner == G+0x2a43 || visibleTo(player[G+0x2a43], u))   // 0x465ac0
```

#### 2.2 pickHover() (0x48cd80), using raw mouse (mx, my)
- **Over the main view:** consider each unit in the visible list with typeId ≠ 0.
  1. **Hit shape:** the root piece's own vertex bbox only, and only if the root has more than 2 vertices. The box is grown from (0,0,0) and offset by the root piece's offset.
  2. **Corners** at y = minY: (mn.x, mn.z), (mx.x, mn.z), (mx.x, mx.z), (mn.x, mx.z).
  3. **Rotate** each corner (x,y) by roll +0x64, then (y,z) by pitch +0x68, then (x,z) by heading +0x66, using the existing pair-rotation helper.
  4. **Project:**
     ```
     sx = (short)((r.x + u.x - (camX<<16)) >> 16) + 128
     sy = (short)((u.z - (camY<<16) - r.z) >> 16) - ((short)((r.y + u.y) >> 16) >> 1) + 32
     ```
  5. **Inside test:** for every edge i→(i+1)%4, `(y1−y0)*(px−x0) > (x1−x0)*(py−y0)` must hold. Boundary points fail.
  6. **Score each hit** (16.16 math, int32 wraparound kept, signed): `key = ((int32)((dy*0x8000)>>16) + dz) * dx >> 16`, using the def sizes at +0x17a, +0x17e and +0x176.
  7. **Result:** the unit index (+0xa8) with the smallest key, strict `<`, so ties go to the earlier list entry. Return 0 if none hit.
- **Else over the minimap:** take the blip with `d² = (bx−mx)² + (by−my)² < 4` and the smallest d²; the first wins ties.
- **Else:** 0.

**Blips:** a unit is shown if typeId ≠ 0 and any of these holds: `G+0x37f2f & 0x200`, `(G+0x14281 & 3) == 0`, `u.flags110 & 0x300`, or `owner == G+0x2a43`. Positions:
- `bx = mmX0 + u.x_int*mmW/scrollW`
- `by = mmY0 + (u.z_int − (u.y_int>>1))*mmH/scrollH`

Hover does not filter by owner, alliance or build state.

**(I):** body height does not enlarge the hit area.

#### 2.3 chooseCursor(mode) (0x48d220)
- **Selectable(u):** `owner == G+0x2a42`, `flags110 & 0x20`, `float(+0x104) == 0.0`, `+0xfb == 0`, and (`+0x86 == 0` or `(+0x86)->flags110 & 0x40000000`).
- **Candidate set S:** player G+0x2a42's units with flags110 & 0x10, with the hovered unit removed.
- **S empty:** return `(mode==1 && hovered && selectable(hovered)) ? 0xf : 0x13`.
- **S not empty:** return the minimum of 0x13 and `0x43e490(mode, s, hovered, &cursorPos)` over each s in S.

**"Feature under cursor"** means all of the following hold (s = the selected unit):
1. **Seen-bitmap:** `lx = (short)cur.x_int >> 5` and `lz = ((short)cur.z_int − ((short)cur.y_int >> 1)) >> 5`. Require `lx <u W` and `lz <u H`, where W, H are s's player at +0x80/+0x84. Require `(word[G+0x14273][W*lz+lx] >> G[0x2a43]) & 1`.
2. **Cell:** `cell(cur.x sar 20, cur.z sar 20)` exists.
   - Direct id: `id < 0xfffb && id < G[0x14253]`.
   - Id `0xfffe`: follow the back-link, and that id must be `< 0xfffb`.
   - The feature record is `G[0x1426f] + id*0x100`.
3. **Flag:** `feature+0xfe & 0x80`.

**0x43e490 cases confirmed** (the mode jump table 0x43f0a8 was decoded; other modes were not traced). Let ally = the hovered unit's player is allied to s's player (player+0x108 table); enemy = hovered and not ally.
- **Mode 0xc (reclaim):**
  - def+0x245 & 0x400 and a feature under the cursor → 0xb.
  - Else hovered and 0x489960(s, hovered) → 0xb.
  - Else 0x13.
- **Mode 1, `G+0x37efa ≠ 1`:**
  1. def+0x245 & 0x10 and enemy → treat as mode 3.
  2. Else def+0x245 & 0x400 and enemy → treat as mode 0xc.
  3. Else hovered and 0x4899b0(s, hovered) and hovered +0x104 ≠ 0.0 → 6 (repair).
  4. Else hovered selectable → 0xf.
  5. Else def+0x245 & 0x800 and feature → 0xa.
  6. Else def+0x245 & 0x400 and feature → 0xb.
  7. Else def+0x245 & 0x80 → 0xe, otherwise 0x13.
- **Mode 1, `G+0x37efa == 1`:**
  1. Hovered selectable → 0xf.
  2. Else enemy → 0x11.
  3. Else ally → 0x12.
  4. Else def+0x245 & 0x800 and feature → 0x12.
  5. Else def+0x245 & 0x400 and feature → 0x12.
  6. Else 0x13.
- **Cursor ids:**

  | Id | Name | Id | Name |
  |---|---|---|---|
  | 1 | attack | 0xb | reclamate |
  | 2 | airstrike | 0xc | load |
  | 3 | toofar | 0xd | unload |
  | 4 | capture | 0xe | move |
  | 5 | defend | 0xf | select |
  | 6 | repair | 0x10 | findsite |
  | 7 | patrol | 0x11 | red |
  | 8 | pickup | 0x12 | grn |
  | 9 | teleport | 0x13 | normal |
  | 0xa | revive | 0x14 | hourglass |

  0x15 = pathicon.

### 3. Camera
- **Clamp (0x41c3c0):**
  - `camX`: if < 0, set to 0; else if > scrollW−viewW, set to that.
  - `camY`: same with scrollH−viewH.
  - The low bound is checked first, so a small map pins the camera at 0.
  - Ends by calling 0x466b70(G+0x142cb).
- **Edge scroll (0x41ce90):**
  - `step = min(128, speedByte(G+0x1434d) * G[0x38a3f])`, where G[0x38a3f] is (I) the frame delta. Step 0 means no scroll.
  - Left = (key 0xf4 and not chat) or (`mx==0 && my<screenH`). Else right = (key 0xf6 and not chat) or `mx==screenW−1`.
  - Up = (key 0xf5 and not chat) or (`my==0 && mx<screenW`). Else down = (key 0xf7 and not chat) or `my==screenH−1`.
  - "Chat" = the TALK.GUI gadget is present (I).
  - Windowed mode: if the OS cursor is less than 100 px beyond the window and the window is in the foreground, clamp to W−1 / H−1.
  - Only if the camera moved: set it, clamp, set target = camera, clear G+0x14281 bit 8, and clear follow (G+0x1434b, +0x142f3, +0x142f7).
- **Follow / scroll-to (0x41ca10), during the sim tick:**
  - Source: countdown position +0x1433f; else `[+0x142f7]+4`; else follow unit `[+0x142f3]` if its flags110 & 0x10000000 (otherwise the follow is cleared).
  - Target: `tx = (short)(p.x>>16) − trunc(viewW/2)` and `ty = (short)((p.z − (p.y sar 1))>>16) − trunc(viewH/2)`, clamped to the extents.
  - Step on each axis: `d = cam − target`. If d > 320, cam −= 320. If d < −320, cam += 320. Otherwise `cam −= trunc(d/2)`, which leaves a 1 px difference that never closes.
  - Then call 0x41c6f0 and the clamp.
- **Minimap centre (0x41d0f0):**
  - `camX = (mx−mmX0)*scrollW/mmW − trunc(viewW/2)`, and the same for Y with scrollH, mmH, viewH.
  - Then set flag 0x142f1 |= 2, clamp, set target = camera, clear G+0x14281 bit 8.

### Inferred or not traced
- Field meanings: +0x104 = build fraction (0.0 = done); G+0x14273 = seen bitmap; 0x465ac0 = LOS/radar check; TALK.GUI = chat; the key codes 0xf4..0xf7.
- Not traced: 0x47c780 and 0x47d820 (ghost height), 0x489960, 0x4899b0, 0x489a90, and the other 43e490 modes (2..11, 13, 14).
- Unverified: whether mapW_px = Wc×16.
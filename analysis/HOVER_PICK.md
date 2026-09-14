# Hover picking

`godot/hover_pick.gd` ports the original hover pick (the unit under the cursor) from TotalA.exe. It covers:
- the pick itself, 0x48cd80, with its main-view and minimap branches;
- the hit test 0x48c6a0 and the pieces it calls: bbox 0x4cb650, rotation 0x4b6cc0 / 0x4b7173, and the point-in-quad test 0x4c1320;
- the visible-list rebuild, 0x48bae0;
- the unit loop of the minimap blip builder, 0x466dc0.

It is not wired into the viewer yet.

## Evidence

**Native comparison.** `tools/native_hover_pick.py` runs the original code in Unicorn. `godot/compare_native_hover_pick.gd` prints **HOVER_PICK_NATIVE 307,757 / 307,757 checks match**.

| Checks | Count | What they cover |
|---|---|---|
| 0x4b6cc0 rotations | 20,037 | Random int32 points including extremes. Angles are random, zero, quarter/half turns and all 512 table steps. 586 results overflow to 0x80000000. 37 cases are constructed: 21 exact .5 ties and 16 inputs where the angle constant matters. |
| 0x4cb650 root bboxes | 4,083 | 0 to 8 vertices, count −1, offsets, int32 wrap. |
| Key blocks | 12,183 | Instructions 0x48ce1e..0x48ce5b run in isolation, including int64 helpers and random int32 sizes. |
| 0x48cd80 with a NULL list | 1,000 | |
| 0x48c6a0 hit tests | 121,104 | Each is two checks: the four projected corners captured at the 0x4c1320 call, and inside/outside. 4,583 are inside. |
| 0x48cd80 main-view picks | 15,122 | 1,000 scenes: overlapping and cloned units for ties, duplicate list entries, empty slots, keys at 0x7fff0000 ± 1, camera offsets up to ±40,000, mice on view edges and on projected corners/edges. 1,990 return a nonzero index. |
| 0x48cd80 minimap picks | 9,124 | 1,500 blip lists: ties, count 0/−1, int32-wrapped distances. 2,346 are nonzero. |
| 0x48bae0 visible lists | 1,500 × 2 | 33,945 units. Both the list and the exact 0x465ac0 call sequence are checked. Includes cells at −1/0/w−1/w that decide the lowering. |
| 0x466dc0 blip lists | 1,000 | 9,885 blips. |

**Unit tests.** `godot/test_hover_pick.gd` prints **HOVER_PICK 44 / 44 checks pass** using hand-computed fixtures.

**Mutation testing.** 16 of 17 port mutants are caught. The survivor drops `low32` from the key's half-height step. That is equivalent: `(int64)s32 * 0x8000 >> 16` always fits in int32. The full list is in `analysis/native-hover-pick-validation.json`.

## Recovered rules

### Visible list (0x48bae0)
- **Call sites.** 0x48bae0 is called at 0x49697b in the frame step 0x496790, and also at 0x495c6d, 0x495e5d and 0x48d5a5.
- **Slots.** It walks the unit slots from `[G+0x14357]` to `[G+0x1435b]` inclusive, stepping 0x118. It skips `+0xa6 == 0`.
- **Output.** It writes `+0xa8` words into `[G+0x1435f]` and the count into `G+0x14367`.
- **Integer parts** are the signed high words: unit `+0x6c/+0x70/+0x74`, def `+0x160/+0x164/+0x168/+0x16c/+0x170/+0x174`. A world coordinate of 32,768 px or more wraps.
- **Bottom lowering.** `bottomY = minY + y`. If `(flags110 & 3) != 1` and 0x4815a0 finds the cell, and `bottomY > cell byte +4`, then `bottomY` is lowered to that height.
  - 0x4815a0 uses `x sar 20`, `z sar 20`, signed `0 <= c < w/h`, and a 13-byte cell record.
- **Screen box:**
  - `left = minX + x − camX + 0x80` and `right = maxX + x − camX + 0x80`
  - `top = minZ + z − camY − ((maxY + y) sar 1) + 0x20`
  - `bottom = maxZ + z − camY − (bottomY sar 1) + 0x20`
- **Kept** unless `left > R`, `right < L`, `top > B` or `bottom < T`. R, L, T, B are the view rect at `G+0x37e27`, inclusive.
- **Visibility.** The unit must also have `owner byte +0xff == byte G+0x2a43` or pass `0x465ac0(G+0x1b63 + local*0x14b, unit)`. 0x465ac0 is only called after the box test passes.

### Pick (0x48cd80)
1. **View test.** If the raw mouse (`G+0x2c76/+0x2c7a`) is inside the view rect (0x4b6720, inclusive):
   - A NULL list pointer returns 0.
   - Otherwise, for each list entry `slot`: take `unit = base + slot*0x118`, skip `type == 0`, and hit-test (§Hit test).
   - A hit's key is `low32((int64)low32(size.y*0x8000 >> 16) + size.z) * size.x >> 16)`, using def `+0x17a`, `+0x17e`, `+0x176`. In effect this is `(size.y/2 + size.z) * size.x` in 16.16, the drawn footprint area.
   - The best key starts at **0x7fff0000**, and the test is `key < best`. So the earliest list entry wins ties, and a hit whose key is ≥ 0x7fff0000 is ignored.
   - The result word starts at 0 and becomes `+0xa8` of the best hit.
2. **Minimap.** Else, if the mouse is inside the minimap rect (`G+0x142bb`, inclusive), walk `[G+0x1436b]` 10-byte blips at `[G+0x14363]`:
   - `d2 = (bx−mx)² + (by−my)²` in int32 wraparound (a wrapped negative d2 also qualifies).
   - Accept if `d2 < 4 && d2 < best`, where best starts at 99999, so the first blip wins ties.
   - A count ≤ 0 means no blips.
3. **Else** return 0.

The return value is a word, so a hit on a unit whose index is 0 cannot be told apart from no hit.

### Hit test (0x48c6a0)
- **Model.** `model = [G+0x14377][type +0xa6]`, which is the loaded 3DO root after 0x4cb590.
- **Bbox.** `0x4cb650(model, &min, &max, 0)`:
  - min and max start at (0, 0, 0).
  - Only if the signed vertex count `+4 > 2`: each root vertex (`+0x24`, 12 bytes) plus the root offset `+0x10/+0x14/+0x18` extends them, with int32 wrap and independent `>` / `<` updates.
  - Flag 0 means children (`+0x30`) and siblings (`+0x2c`) are never visited.
- **Corners** at `y = min.y`: `(min.x, min.z)`, `(max.x, min.z)`, `(max.x, max.z)`, `(min.x, max.z)`.
- **Rotation.** `0x4b6cc0(in, out, unit+0x64)` rotates in three steps:
  1. `(x, y)` by word `+0x64`.
  2. `(y, z)` by word `+0x68`.
  3. `(x, z)` by word `+0x66`.
- **Pair rotation** is 0x4b7173 (§Rotation).
- **Projection** (all int32 wraps; `s16` = movsx of the low word):
  - `sx = s16((r.x + (u.x − (camX<<16))) sar 16) + 0x80`
  - `sy = s16(((u.z − (camY<<16)) − r.z) sar 16) − (s16((r.y + u.y) sar 16) sar 1) + 0x20`
  - The +0x80 and +0x20 are constants, not the view rect fields.
- **Inside test.** `0x4c1320(points, 4, mx, my)`:
  - n < 3 returns 0.
  - For every edge `i → (i+1)%n` (idiv), it needs `(yj−yi)*(px−xi) > (xj−xi)*(py−yi)` with two-operand int32 imul, so boundary points are outside.
  - With the negated model z in sy, an unrotated box winds so that its interior passes.

### Rotation (0x4b7173)
- **No sine table.** 0x4b7173 does not use the sine table at 0x509f00. It is x87:
  - `θ = fild word(angle) * qword[0x509ef8]`, where the constant is `0x3F1921FB54442C5A`. That is 9.587379924285e-05, which is 190 ulps below the exact 2π/65536.
  - Then `FSINCOS`, `a' = fistp(a*cos − b*sin)` and `b' = fistp(b*cos + a*sin)`.
- **Zero angle.** A zero word returns the pair untouched.
- **Rounding.** FISTP rounds to nearest even. A result outside int32 becomes 0x80000000.
- **Port.** The port uses doubles, which is exact for x87 precision control 53-bit (0x27f).

### Blips (0x466dc0 unit loop)
- **Callers.** 0x466dc0 is called from 0x465072 and 0x48191f. It resets the count, then walks the same slot range and skips type 0.
- **Filter.** `all = (word G+0x14281 & 3) == 0 || (word G+0x37f2f & 0x200)`. A unit is shown if `all || (flags110 & 0x300) || owner byte == byte G+0x2a43`.
- **Position** (truncating `idiv`):
  - `bx = s16 G+0x142e7 + (x_int * s16 G+0x142eb) / G+0x1422b`
  - `by = s16 G+0x142e9 + ((z_int − (y_int sar 1)) * s16 G+0x142ed) / G+0x1422f`
- **Entry.** Each blip is `[word +0xa8, bx, by]`, appended in slot order.

## Corrections to CURSOR_PROJECTION.md

1. **Rotation helper.** The spec's "existing pair-rotation helper" is an x87 FSINCOS rotation with a slightly-off 2π/65536 constant, round-to-even FISTP and 0x80000000 overflow. It does not use the sine table at 0x509f00. A port that rotates with the COB sine table or exact TAU/65536 differs (the mutation was caught).
2. **Starting key.** The best key starts at 0x7fff0000, not "infinity". Hits with key ≥ 0x7fff0000 never win. A hit whose `+0xa8` is 0 returns the same value as no hit.
3. **Key steps.** The first int64 step (`size.y*0x8000 >> 16`) never wraps; it equals `size.y sar 1`. The wraparound that matters is in `+ size.z` and in the final product.
4. **Minimap distance.** It wraps in int32, and a wrapped negative d2 is accepted.
5. **Projection constants.** In both the hit test and the visible list, the +128/+32 are constants. Only the overlap test and the view gate read the view rect.
6. **Model axes.** The model is the loader's converted 3DO root: 0x4cb590 negates vertex x/z and piece offset x/z, and keeps y. Raw 3DO file values must be converted first (`HoverPick.model_from_3do_piece`).
7. **Vertex count test.** It is on the signed `+4` field. A negative count gives a zero box.
8. **Visible-list call sites.** Besides the frame step (0x49697b), 0x48bae0 is also called at 0x495c6d, 0x495e5d and 0x48d5a5. The spec named only the frame-step caller. Those callers were not traced.

## Stubs and limits

- **0x465ac0** (stdcall, 2 args) → `ret 8` plus a code hook that returns a per-unit answer from the scene RNG. The player pointer argument is checked to equal `G+0x1b63 + local*0x14b`. The real query is already ported and verified in `visibility_queries.gd` (LOS_STAMP_QUERIES.md).
- **Minimap drawing calls** in 0x466dc0 are replaced by their returns: 0x4c6b70 (`ret 0x10`), 0x4b7f30 (`ret 8`) and 0x4b7f90 (`ret 0x10`). The builder runs from 0x466dc0 to 0x4671a0 only; the feature loop after that is not run. Unit flag 0x10 (selected, range rings 0x4c0070/0x4c01a0) is kept clear. Those draws do not touch the blip list.
- **Key block.** It runs from 0x48ce1e to 0x48ce5b. A code hook stops at 0x48ce5b because Unicorn's `until` address was unreliable there.
- **x87 precision.** The oracle uses control word 0x27f (Win32/MSVC CRT default; the CRT's own checks compare against 0x27f). 0 of 20,000 random rotations change under 64-bit precision 0x37f, but 7 of the 37 constructed tie cases do. If the shipped game ran with another control word (for example one set by a DirectDraw wrapper), rare exact-tie rotations could differ.
- **FSINCOS source.** Unicorn/QEMU computes FSINCOS with the host libm on a double, not with physical x87 microcode. Godot's `sin`/`cos` matched it on every case, including the constructed ties. Parity with real hardware FSINCOS (which differs from libm in the last bits for some inputs) is **not** claimed.
- **Not exercised:**
  - model table entries missing for a live type;
  - vertex counts above 8;
  - world coordinates whose high words exceed the view-rect range on real maps;
  - division by a zero scroll size in the blip builder (the native code would fault).

## What the viewer must supply

- **Model** per unit type: the 3DO root piece from `prepare_viewer.model_3do(...)[0]`, i.e. `pieces[0].vertices` and `pieces[0].offset`, converted with `model_from_3do_piece`. Only the root piece matters. A root with ≤ 2 vertices has a zero box that projects to a degenerate quad, so the unit can never be hovered.
- **Def bounds** in 16.16:
  - `min` = def `+0x15e/+0x162/+0x166`, `max` = `+0x16a/+0x16e/+0x172`, `size` = `+0x176/+0x17a/+0x17e`.
  - These come from the 0x42d080 fill: x/z = ∓(footprint<<20)/2, minY = 0, maxY = 0x4cb5f0 model height.
  - `size = max − min`: x/z = footprint<<20, y = height.
  - `tools/native_unit_bounds.py` already records these per unit.
- **Unit state:**
  - 16.16 position `x`, `y`, `z`;
  - angle words `[+0x64, +0x66, +0x68]`, in the unit's heading/pitch/roll convention as stored by the original;
  - `type_id` (non-zero), `index` (the id that is returned);
  - `owner` byte, `flags110`.
- **Camera** `(camX, camY)` in world pixels and the view rect `(128, 32, W−1, H−33)`.
- **Cells:** width, height and height bytes, for the lowering. Plus the local player index and a `visible_fn(slot, unit)`, which is `visibility_queries.gd` for the local player.
- **Minimap:** the rect, origin and size words, scroll extents, and the two game flag words for the blips.
- **Frame order.** The list is built after the frame step and used on the next input frame, so rebuild it after moving units and the camera, then call `hover()` with the raw mouse position.

## Commands

```
python tools/native_hover_pick.py
powershell -File %TEMP%\claude\gd.ps1 --headless --path godot --script res://compare_native_hover_pick.gd
powershell -File %TEMP%\claude\gd.ps1 --headless --path godot --script res://test_hover_pick.gd
```

## Audit status

The planned adversarial audit was interrupted when the session ended. At integration the lead reran the oracle, comparator and tests (307,757 / 307,757 and 44 / 44). Five port mutations were each caught, then reverted:

| Mutation | Checks matching |
|---|---|
| vertex count `> 1` | 296,994 |
| key tie `<=` | 307,265 |
| minimap `d2 <= 4` | 307,730 |
| truncating `/ 2` for the height halving | 287,774 |
| visible-list top `+0x21` | 307,742 |

The module is not yet wired into the viewer, which still picks by footprint around the drawn position.


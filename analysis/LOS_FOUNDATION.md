# Line of sight: assets, ray tables and height grid

This is the first line-of-sight checkpoint. It adds the static inputs that the original visibility system builds at load time. Stamping, queries, radar and fog rendering build on it (`%TEMP%` research plan: C4–C10, recorded in HANDOFF.md).

All work was done by an implementation agent per component, each followed by an independent adversarial audit.

## Assets (`tools/prepare_visibility.py`)

- **`gamedata/LOS.TDF`.** Present only in `totala1.hpi` (7,888 bytes). It declares 9 tables with 2, 4, 4, 6, 8, 10, 12, 12 and 14 lines.
- **`anims/VISMASKS.GAF`.** Four byte-identical copies exist (`rev31.gp3`, `btdata.ccx`, `ccdata.ccx`, `totala1.hpi`), so archive precedence does not matter for this file.
  - The GAF header version is 0, which the old `gaf_entries` rejected; the tool has its own parser.
  - The file holds a single `vismask` sequence of 10 uncompressed frames, 11×11 up to 29×29.
  - Every frame has `xoff = yoff = (w−1)/2`, transparent index 9 and opaque value 255.
  - The frames are filled discs stored as pixels; frame 9 is not symmetric, so the stored pixels must be used.
- **Output.** Everything goes to `local/visibility/` (git-ignored): `los.tdf`, `vismasks.json` with raw palette-index pixels, and `index.json` with sources, hashes and the table and frame summary.

## Ray tables (`godot/los_tables.gd`, loader `0x433130` → `0x433380` → `0x4336f0`, accessor `0x433500`)

- **Counts.** `numtables`, `numlines` and each line's pair count are CRT `atoi` results used as int16.
- **Line format.** Each line reads `n, a1, b1, …` through `strtok(", ")`; extra tokens are ignored.
- **Rotations and ray order.** Every line makes four rotations: `(a,−b)`, `(b,a)`, `(−a,b)` and `(−b,−a)` (jump table `0x4339a4`). Rays are grouped by rotation: `ray index = rot·n + line`. The research plan had interleaved them; the native loader groups them.
- **Missing keys.**
  - A missing `lineN` key clears that ray.
  - A line without tokens leaves the ray untouched.
  - A missing section leaves its table empty.
- **Accessor.** `0x433500` returns `tables[int16(k−1)]`.
- **TDF reader.** It follows the original parser `0x4c3120`/`0x4c3e40`:
  - the last duplicate key wins;
  - comments are blanked by an equal number of spaces;
  - only space, tab, CR and LF are trimmed;
  - a key runs to the next `=`;
  - a stray `}` at the root ends parsing;
  - case folding is A–Z only;
  - the text ends at the first NUL.
- **Faults.** Undefined native outcomes are reported instead of guessed:
  - missing tokens (`atoi(NULL)`);
  - negative sizes;
  - a ray index that wraps int16 (more than 8,192 lines);
  - the fatal TDF parse error handler `0x4b6290`.

**Evidence.**
- `native_los_tables.py` runs the original loader, TDF parser, `strtok`, `atoi` and `sprintf` unmodified. Only the file system, path builder, heap and TLS are stubbed, and every other import traps.
- It covers the real file and 38 synthetic TDF variants.
- `compare_native_los_tables.gd` matches **33,899 / 33,899** checks: every ray step, the table and ray counts, per-line strings, fault kind and location, and accessor indices. This runs in `-Native`.
- The audit fixed five parser divergences and made nine deliberate port mutations, all of which the comparison caught.

## Height grid (`godot/los_height_grid.gd`, `0x482c20`, core `0x482f1b..0x483205`)

- **Size.** The grid is half resolution (`w2 = W/2` with truncation) with padding `(w2·h2 + 7) & ~7`. Each cell holds a max byte and a min byte, initialised to (0, 0xFF). The pointer is null when the padding is 0.
- **Scan.** Columns are the outer loop and rows the inner.
  - Projection: `py = 16r − (h>>1)` and `lr = py >> 5`.
  - When `lr ≥ 0`, the slope value is `s = ((lr<<5)+31)·h / (py+31)` (signed division).
  - Two carried cell pointers A and B are reset per column. Each receives `s` before and after being recomputed, then `h`, with unsigned bounds checks.
- **Smoothing.** A final blend over every padded entry sets `max = max((min + 2·max)/3, sea)` and `min = max((max + 2·min)/3, sea)`.

**Evidence.**
- `native_los_heights.py` runs the original routine with only the allocator and free stubbed.
- It covers 4 real maps (Greenhaven, Hundred Isles, Lava Run, Biggie Biggs) and 240 random grids, including 1–3 cell maps, odd sizes, sea levels 0, 40, 255 and random, and heights near 0 and 255.
- `compare_native_los_heights.gd` matches **244 / 244** grids, 568,416 padded bytes. This runs in `-Native`.
- The audit counted every branch (all hit) and confirmed that results do not depend on leftover heap contents.

## Limits

- Not yet connected to the world or viewer. Stamping, queries, radar and jamming, targeting gates and fog rendering are the next checkpoints.
- The loader's copy of TNT heights into cell `+4`, and the 8×8 overlay grid built earlier in `0x482c20`, are assumed rather than proven by these oracles.

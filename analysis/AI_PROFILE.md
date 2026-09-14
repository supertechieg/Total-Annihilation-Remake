# Skirmish AI: profile interpreter (CP2)

This is checkpoint CP2 of `SKIRMISH_AI_RESEARCH.md`. It ports the interpreter that reads the `ai\<profile>.txt` scripts and the FBI `ai_weight` / `ai_limit` strings into the per-player, per-type AI arrays: weight byte, weight lock, limit and limit lock. The evidence is oracle O1, which runs the original interpreter code.

Every rule below was re-read in the disassembly. Where it differs from the research plan, the change is listed under **Corrections**.

## Data (`tools/prepare_ai.py` → `local/ai/`, git-ignored)

- **Files.** It extracts all 32 `ai/*.txt` files from `rev31.gp3`, `btdata.ccx`, `ccdata.ccx` and `totala1.hpi` into `archives/<archive>/`, byte for byte.
- **Resolved view.** `resolved/` holds one copy of each of the 10 names, chosen by the provisional precedence `rev31.gp3 > btdata.ccx > ccdata.ccx > totala1.hpi`. This is the same order `prepare_units.py` uses and is **inferred**, not verified.
  - `btdata.ccx` is byte-identical to `rev31.gp3`.
  - `krogoth.txt` exists only in `ccdata.ccx`.
- **`index.json`.** It records:
  - the source archive, SHA-256, size and line count of every copy;
  - for all 272 resolved unit FBIs: `unitname` (max 31 characters), `category` (max 99), `ai_weight` / `ai_limit` (max 63, the loader field sizes), `downloadable` and `side`;
  - each unit's **type id**;
  - the console command table, read from the executable (local only).
- **Type ids (verified).** The FBI loader sorts the definition array from index 1 (`0x42d533..0x42d60e`) with comparator `0x42db60 = _stricmp(a+0x20, b+0x20) < 0`, then writes `id = index` into `+0x21e` (`0x42d634`).
  - `_stricmp` (`0x4f8a70`, C locale) folds only A–Z to lower case and compares bytes as unsigned.
  - Id 0 is reserved.
  - The oracle re-checks that every adjacent pair of the real table is strictly ascending under the native `_stricmp`.
  - The resolved set has no names that collide case-insensitively.
- **FBI fields in the real data.** 6 units carry `ai_weight` and 17 carry `ai_limit`. Notable values:
  - `armsnipe` uses `weight ARMAMPH 0.5`, which names a different unit.
  - `corawac` uses `limit CARAwac 5`, which names nothing, so it resolves to an empty set.

## Interpreter (`godot/ai_profile.gd`)

### Script runner and tokenizer

- **Runner `0x4b7a30`.**
  - Lines split on `\n` only; a bare CR does not split, it is only whitespace.
  - A last line without a newline still runs, and a trailing newline adds no empty line.
  - The file length is explicit, so NUL bytes are ordinary characters. Commands see C strings, so everything after a NUL in a token is ignored.
- **Tokenizer `0x4b7440`.**
  - Separators are the C-locale `isspace` characters 0x09–0x0d and 0x20.
  - A `#` ends the line when it starts a token, and also when it appears inside a token (the token ends at the `#`).
  - At most 20 argv entries are kept. Every token, including dropped ones, still uses the 0x7e-byte storage: characters plus a NUL each.
  - If the total of (token length + 1) exceeds 127, a token no longer fits. The loop then writes NULs past the command object forever, and the native code crashes. The port reports `token_storage_overflow`.
- **`%n` substitution `0x4b74f0`.** The profile loader and the FBI passes pass an empty source object, so no substitution happens.

### Dispatch `0x4b7900` (mask −1)

- **Lookup.** Names are matched case-insensitively (`_stricmp` lower bound) in the one global command table.
- **Mask.** The profile loader and both FBI passes call with **mask −1**. `plan`/`weight`/`limit` are registered with flag 8, but every console command (43 + 10 + 30 names from tables `0x501d38`/`0x501f48`/`0x501fd0`) also matches the mask. A profile line such as `Radar` or `Kill 3` therefore runs that console command.
- **Fallback `0x417890` (flag 4)** receives any name not in the table:
  - Every type whose unitname matches `argv[0]` under the wildcard matcher `0x4bc370` is **spawned** (`0x485f50`) for player `atoi(argv[1])`. The matcher uses `?` and `*`, folds a–z to upper case, and keeps a state list capped at 100.
  - If nothing matches, it builds `sprintf(buf, "debugdat\%s.txt", argv[0])` (format at `0x502510`) into the 60-byte stack buffer `[esp+0x28..0x63]` and calls `0x4bb5b0(buf)` = `0x4bb2e0(buf, mode 0x505f10)` to open it. Only on a non-zero handle does it load the file (`0x4bbff0`), run it through the script runner `0x4b7a30` with mask −1, free it (`0x4d85a0`) and close the handle (`0x4bb5d0`).
  - A profile comment such as `// weight ARM 0` is therefore the unknown command `//`: it matches no unitname, so the game tries `debugdat\//.txt`. The GOG install has no `debugdat` directory, so the oracle's open stub returns 0 and nothing runs. The port emits the same `["script_file", "debugdat\\<argv0>.txt"]` event and treats the open as failing.
  - `debugdat\` + token + `.txt` + NUL is 14 + length bytes, and the buffer sits directly below the return address `[esp+0x64]` (the four saved registers are below the buffer). A 46-character token fills the buffer exactly. From 47 characters `sprintf` writes over the return address (see **Native faults**). The open still runs with the overlong path, so the port records the event first and then reports `fallback_path_overflow`.
  - The port records spawns, script-file attempts and console commands as events and executes none of them.

### Commands

- **`plan` `0x406c90`.**
  - It sets flag `0x501774` to 0, then loops `i = 1..argc-1`:
    - if `argv[1]` (always index 1) equals `any`, the flag becomes 1;
    - if `argv[i]` equals the name for the current difficulty (0 easy, 1 medium, 2 hard), the flag becomes 1.
  - A `plan` with no arguments turns lines off.
  - The flag is a global with static initial value 1. It persists across scripts and reloads, and only the FBI passes reset it to 1.
- **`weight` `0x406db0`.** Only when the flag is set:
  - `set, explicit = resolve(argv[1])` and `w = float32(atof(argv[2]))`, where a missing argument gives 0.0;
  - it calls `0x409dc0` for every slot whose AI object pointer (`player+0x74`) is non-zero, whatever its type or presence.
- **`limit` `0x406e40`.** Only when the flag is set:
  - `v = atoi(argv[2])`, where a missing argument gives 0;
  - it calls `0x409e90` for every slot with `player+0 != 0` and type byte `+0x73 == 2`. It does not check the AI object.
- **Resolve `0x488d30`.**
  - It first binary-searches unitnames over ids `1..count-1` with `_stricmp`. A match gives `{id}` and `explicit=1`.
  - Otherwise it uses the category set from `0x488c50`. That set is filled at FBI load by `0x488e70`: `sscanf(" %s %n")` tokens plus `ALL`. An unknown name creates an empty set, so it matches nothing.
  - Unit names take priority over categories with the same name.

### Applying values

- **Weight `0x409dc0`.** For each id in the set with weight lock 0:
  - `byte = clamp(low32(fistp64(byte × w)), 0, 100)`, and an explicit name sets the lock.
  - `_ftol 0x4e43a0` does `fistp qword` with RC=chop and returns the low 32 bits:
    - `100 × 3e7` wraps negative, so the result is 0;
    - `100 × 4.3e7` stays positive, so the result is 100;
    - NaN or values of 2^63 and above give the indefinite integer, so the result is 0.
  - `byte × float32` needs at most 32 significant bits, so the product is exact in both 53- and 64-bit x87 precision. The CRT sets 53-bit (`0x4ea5b0`), the oracle runs with FINIT; the difference cannot change the result.
- **Limit `0x409e90`.** For each id in the set with limit lock 0: `limit = v`, and an explicit name sets the lock.
- **Numbers.**
  - **`atof` `0x4e4560`** reads a prefix `[sign]digits[.digits][e|E|d|D[sign]digits]`. There is no inf, nan or hex. An exponent without digits is ignored (`1e+` is 1). The weight path narrows the double to float32 with `fstp dword`.
    - The port is a **bit-exact port of the statically linked MSVC conversion chain**, not a correctly rounded decimal parser: `_fltin2 0x4eaf00` → `__strgtold12 0x4f3d10` → `__mtold12 0x4f8c40` → `__multtenpow12 0x4f9390` / `__ld12mul 0x4f90d0` → `_ld12tod 0x4f3990` / `_ld12cvt 0x4f37c0` (`_RoundMan 0x4f3610`).
    - Rules that make it differ from correct rounding:
      - at most 25 mantissa digits are kept, and the 25th only bumps digit 24 when digit 24 is ≥ 5;
      - exponent digits are capped at 5201, and |exponent| > 5200 gives infinity or zero;
      - `__multtenpow12` uses 12-byte powers of ten with a truncated 5×5-word product;
      - the final 53-bit rounding increments only when a bit from position 55 on is set, because `0x4f3530` skips bit 54.
    - Consequences: native `1.9703343510627747` is 1 ULP below the correctly rounded double, and `2.4703282292062328e-324` gives 0. The correctly rounded parser that preceded this port (and Godot `String.to_float`, which drops digits past about 1e-18) disagreed with native on such strings.
    - The power-of-ten tables `0x5116f0` / `0x511850` (29 entries each) are derived in the port. The oracle asserts that the executable's bytes, the mathematical derivation and the port's constants are identical.
  - **`atoi` `0x4e4f70`** reads a sign and digits and wraps at 32 bits: `4294967297` → 1, `99999999999` → 1215752191.

### Load, reload and the limit test

- **Defaults `0x409470`.** For every id including 0: weight 100, limit −1, both locks 0.
- **Load `0x4648e0`.**
  1. It runs the slot-7 profile. If the loader fails, it runs `ai\default.txt`; if that fails too, it runs nothing.
  2. For each present type-2 slot `i`, in slot order, it calls `0x409f80(i)` and then `0x40a040(i)`.
     - Both set the flag to 1 and walk types `1..count-1`.
     - For each downloadable type (`+0x241` bit 5) with a non-empty `ai_weight` they run that string as a script.
     - `0x409f80` skips types that are **weight**-locked in slot `i`. `0x40a040` skips types that are **limit**-locked in slot `i`, yet still runs `ai_weight`.
     - `ai_limit` (`+0xfe`) is never executed.
- **ReloadAIProfiles `0x40a100`.** It resets defaults only for present type-2 slots, then runs `0x4648e0`. Weights in the human slot and in AI-object slots of other types accumulate across reloads, and the plan flag carries over.
- **Limit test `0x409f20`.** The id word must be in `1..count-1`, otherwise the test fails. A limit of −1 passes; otherwise the test is `count < limit`.
  - The slot byte indexes the 10 context pointers at `0x5119c0`. The oracle checks only slots 0 and 1. For slot byte ≥ 10 the native code reads past that array (unmodelled), so `limit_allows` returns false and sets `fault = {"kind": "unmodelled_limit_slot"}` instead of throwing. This is a port guard, **not native evidence**.

### Consequences for the shipped data

In the skirmish configuration (slot 0 human, slot 1 AI), for player slot 1:

- **rev31 `default.txt`.** 261 of 272 types end limit-locked by explicit lines at every difficulty; 21, 26 and 30 are weight-locked on easy, medium and hard.
- **`//` lines.** Every `//` line becomes a `debugdat\//….txt` open attempt: 25 in each large rev31 profile, 22 in each large ccdata profile, 18 in `krogoth.txt`, 3 in the rev31 and ccdata `missions.txt`, 5 in each of the totala1 `airbattle.txt` and `seabattle.txt`, and none in totala1 `default.txt` or `missions.txt`.
- **FBI `ai_limit` values.** They are never applied. Units the profile does not name stay unlimited:
  - all 17 under every `missions.txt`;
  - 2 or 14 under totala1 `default.txt`;
  - 1 under ccdata `default.txt`;
  - none under rev31 `default.txt`.
- **FBI `ai_weight` with a category name.** It is multiplied again for every pass and every type-2 slot: 2 × (number of type-2 slots) times. With two AI slots, `weight LEVEL2 0.5` takes an unlocked LEVEL2 type from 100 down to 6.

## Evidence

**Oracle O1.** `tools/native_ai_profile.py` runs the original code unmodified in Unicorn:

- **Registration and table fill:** registration `0x406f00`, the three console tables through `0x4b7760`, the fallback registration `0x4b78e0`, the category fill `0x488e70`, and the defaults `0x409470` for 10 contexts.
- **Load paths:** `0x4648e0` or `0x40a100` with the whole interpreter chain below them.
- **Fallback code:** matcher `0x4bc370`, `sprintf`, and the limit test `0x409f20`.
- **CRT `atof` `0x4e4560`** with its whole conversion chain, followed by `fst qword` and `fstp dword`, over a deterministic corpus of 7,895 strings: grammar edges, 25-digit buffer rounding, double and float32 midpoints truncated to 15–30 digits, subnormal and overflow edges, exponent clamps, and random fuzz.
- **Power-of-ten tables** `0x5116f0` / `0x511850`: the executable bytes must equal the derivation and the port's `_POW10_POS` / `_POW10_NEG`, or the oracle stops.

Stubs:

- **Heap.** Allocations go to a bump allocator.
- **`_getptd`.**
- **Slot-7 name `0x4356c0`** and **file loader `0x4bbe50`.** Every requested name is recorded.
- **Unit spawn `0x485f50`** (`ret 0x20`) is recorded, and its position helper `0x47ddc0` is replaced.
- **debugdat open `0x4bb5b0`** is recorded and returns "not found".
- **The other 83 console handlers** are replaced by a recorder.
- **Imports.** Every other import traps.

Game, player and unit memory is synthetic. The details are in the tool's docstring.

**Native faults versus harness failures.** Only a Unicorn `UcError` inside a load or reload counts as a native crash. An import trap, the execution limit or bump-heap exhaustion raises a harness failure and aborts the whole run, so it can never be recorded as a native fault. The oracle classifies each crash from evidence:

- eip inside the tokenizer `0x4b7440..0x4b74ef` → `token_storage_overflow`;
- otherwise, the last recorded event is the debugdat open with a path longer than 59 characters → `fallback_path_overflow`;
- anything else → `unclassified`. The comparator counts an unclassified native fault as a mismatch.

**Cases.** There are 426, 21 of them native crashes (see the table):

- **75 real.** Covers:
  - all 23 distinct archive copies × 3 difficulties with the real 272-type table;
  - `default.txt` with mixed players at 3 difficulties;
  - a missing profile falling back to `default.txt`;
  - no profile files at all;
  - load → reload → difficulty change → reload.
- **329 synthetic.** Covers:
  - empty files, CRLF, bare CR, tabs/VT/FF;
  - command case, `#` and `//`, NUL bytes;
  - plan quirks, including difficulty 3 and −1;
  - lock order in both directions, unit versus category names, missing arguments, more than 20 tokens;
  - 54 weight strings and 18 limit strings;
  - the token-storage boundary at 126/127/128 and the fallback path length from 40 to 66;
  - 18 full weight-path `atof` strings (long mantissas, exponent-shifted tiny mantissas, 25-digit rounding, exponent clamps);
  - bare CR against categories, spawn owner defaults and wildcard case folding;
  - wildcards, including the 99/100/101 state-cap boundary;
  - console commands and `%` tokens;
  - 160 seeded fuzz scripts;
  - plan-flag persistence and a changed file across reloads.
- **22 FBI.**
  - 16 cases: 4 player layouts × 4 profiles against synthetic units with `ai_weight`/`ai_limit`: explicit, category, a `limit` command inside `ai_weight`, a type that is not downloadable, and a unit named like a category.
  - 6 plan-string cases (3 layouts × difficulties 0 and 2) with the `synthetic_plan` unit set. In id order, ARMAMPH's `ai_weight` is `plan hard`, CORDL's is `weight LEVEL2 0.5`, CORLIM's is `plan any` and CORMULTI's is `weight CORE 0.9`. `0x409f80` / `0x40a040` set the flag once before their loop, so on easy the CORDL line is skipped until `plan any` re-enables later types. This is the witness for "flag set per type" (mutation M19).

The per-case data goes to `local/ai/native-ai-profile.json`. The summary, with input hashes and the real-profile outcomes above, is in `native-ai-profile-validation.json`.

**Comparator.** `godot/compare_native_ai_profile.gd` replays every case. For each load or reload it compares:

- the type id order;
- the plan flag and the event list;
- all four arrays for all 10 slots;
- native fault versus port fault kind;
- the limit tests (112 per case).

It also checks the index and profile hashes. For every `atof` corpus string it requires the port's double bits **and** float32 bits to equal native exactly; there is no tolerance or ULP category. Result: **79,371 / 79,371 checks match** (426 cases, 21 native faults, 7,912 `atof` strings).

The corpus includes three sets of rule witnesses found by searching the native chain, because the random corpus alone did not pin these rules (mutations M33, M36 and M39 below had survived it):

- 24-digit double midpoints plus a 25th digit, for the digit-24 bump;
- exact products `d×10^k` whose `__ld12mul` guard word is exactly 0x8000 with bit 16 clear, found by comparing the original code with an in-memory patch `0x4f92d4 ja → jae`;
- 5,000 leading fraction zeros with exponents 5199 / 5201 / 5300 / 99999, for the exponent cap.

**Mutation audit** (scratch script, each mutation applied to `godot/ai_profile.gd` and reverted byte-exactly). Numbers are comparator checks matching and unit tests passing. The first 30 were run against the 79,337-check trace before the witnesses were added; the rows marked * were rerun against the final trace.

| # | Mutation | Comparator | Unit tests |
|---|---|---|---|
| M1* | `//` treated as a comment | 79,223 / 79,363 | 67 / 68 |
| M2 | `plan any` reads `argv[i]` | 78,916 / 79,337 | 63 / 64 |
| M3 | weight ignores lock | 77,201 | 61 |
| M4 | `_ftol` saturates instead of wrapping | 79,307 | 63 |
| M5 | round instead of truncate | 77,368 | 61 |
| M6 | limit without the type-2 gate | 73,886 | 63 |
| M7 | second FBI pass runs `ai_limit` | 74,987 | 60 |
| M8 | second FBI pass checks the weight lock | 79,031 | 63 |
| M9 | bare CR splits lines | 79,321 | 63 |
| M10 | category weight sets the lock | 75,067 | 61 |
| M11 | weight gate uses "present" | 76,616 | 63 |
| M12 | token storage 0x7e | 79,294 / 79,295 | 63 |
| M13* | no float32 narrowing | 78,019 / 79,363 | 67 / 68 |
| M14 | fallback limit 47 | 79,335 / 79,336 | 63 |
| M15 | wildcard cap 101 | 79,336 | 63 |
| M16 | reload resets the plan flag | 79,323 | 63 |
| M17 | limit test `<=` | 79,084 | 63 |
| M18 | category before unit name | 74,863 | 62 |
| M19* | plan flag set per FBI type | 79,365 / 79,371 | 68 / 69 |
| M20 | no 20-token cap | 79,331 | 63 |
| M21 | id sort folds to upper case | 73,833 | 63 |
| M22 | medium/hard swapped | 77,898 | 63 |
| M23 | no `d`/`D` exponent | 77,997 | 63 |
| M24 | `atoi` saturates | 79,298 | 63 |
| M25* | fallback owner default 1 | 79,358 / 79,363 | 67 / 68 |
| M26 | wildcard case-sensitive | 79,332 | 60 |
| M27 | `#` ends only the token | 79,331 | 63 |
| M28 | empty profile falls back to default | 79,296 | 63 |
| M29 | limit ignores the explicit lock | 78,893 | 63 |
| M30 | clamp at 255 | 77,393 | 62 |
| M32* | `_RoundMan` tail test includes bit 54 | 79,354 / 79,363 | 67 / 68 |
| M33* | 25th-digit rule tests digit[24] | 79,365 / 79,371 | 68 / 69 |
| M34* | table entries not unrounded | 79,231 / 79,363 | 68 / 68 (survives) |
| M35* | `__multtenpow12` keeps the low word | 79,353 / 79,363 | 68 / 68 (survives) |
| M36* | `__ld12mul` rounds half up | 79,365 / 79,371 | 68 / 69 |
| M37 | 26-digit mantissa buffer | 75,925 / 79,337 | 63 (script error) |
| M38 | `limit_allows` slot guard removed | 79,337 (survives; oracle tests slots 0–1 only) | script error, the test run hangs |
| M39* | exponent cap 5301 | 79,369 / 79,371 | 68 / 69 |
| M40* | subnormal path skips the second rounding | 79,341 / 79,363 | 67 / 68 |

Unit tests miss only M34 and M35, which the comparator catches.

**Unit tests.** `godot/test_ai_profile.gd` needs no local assets and gives **69 / 69** checks. They include native `atof` bit patterns (with one witness each for the digit-24 bump, the `__ld12mul` guard and the exponent cap), the M19 plan-string witness, a float32-narrowing witness (`weight ARM 0.7` gives 69, where a double would give 70), `//` as an unknown command, and the `unmodelled_limit_slot` guard.

**Native faults and the port's classification:**

| Case | Native | Port |
|---|---|---|
| `token-storage-128` | endless NUL write, fault at `0x4b74d5` | `token_storage_overflow` |
| `fallback-token-47` | the NUL overwrites the low byte of the return address; `ret` goes to `0x4b7900`, which re-enters dispatch and faults reading `[small value+0xd0]` at `0x4b7910` | `fallback_path_overflow` |
| `fallback-token-48` | return to `0x4b0074`; invalid instruction at `0x4b0078` | `fallback_path_overflow` |
| `fallback-token-49` / `-50` | return address `"xt\0"` + old high byte 0 / `"txt\0"`; fetch fault at `0x7478` / `0x747874` | `fallback_path_overflow` |
| `fallback-token-51..54` | return address is part of `.txt` plus `z`; fault at `0x7478742e`, `0x78742e7a`, `0x742e7a7a`, `0x2e7a7a7a` | `fallback_path_overflow` |
| `fallback-token-55..66` | return address `zzzz`; fault at `0x7a7a7a7a` | `fallback_path_overflow` |

Lengths 40–46 complete natively and in the port. The near-NULL read at 47 and the jumps into non-code for 48 and above would also crash a real process, but where the crash lands depends on process memory. The port stops at the first overflowing line.

## Corrections to the research plan

1. **`//` lines are not ignored.** They reach fallback `0x417890`: a unitname wildcard match spawns units, and otherwise the game tries to open and run `debugdat\<token>.txt`. For the shipped profiles this means file-open attempts only.
2. **Profile and FBI scripts dispatch with mask −1.** Flag 8 does not restrict them, so all 83 console commands are reachable from a profile line.
3. **`#` also ends the line inside a token.** Tokens beyond 20 still consume storage, and more than 127 bytes crashes. Only `\n` splits lines.
4. **`0x40a040` differs from `0x409f80`.** It checks the **limit** lock of slot `i`. "The repeated weight is blocked by its own lock" holds only for explicit unitnames. Category `ai_weight` strings, and non-weight commands inside `ai_weight`, run 2 × (number of type-2 slots) times.
5. **`_ftol` is a 64-bit `fistp` truncated to 32 bits.** Large weights wrap instead of clamping. The product is exact, so x87 precision control is irrelevant.
6. **`atof` also accepts `d`/`D` exponents.** A missing weight or limit argument means 0, so `weight ARM` zeroes the ARM weights.
7. **Weight targets every slot with an AI object pointer, including human and non-present slots. Limit targets present type-2 slots without checking the AI object.**
8. **Reload resets only type-2 contexts.** The global plan flag persists: a profile ending in a non-matching `plan` with no type-2 player makes the next reload skip the lines before the first `plan`.
9. **Type ids are the `_stricmp` sort order of unitnames.**
10. **The limit test uses the id word.** Ids outside `1..count-1` fail.

The following plan statements were confirmed as written:

- the `argv[1]=='any'` quirk;
- initial flag 1;
- unitname before category, unknown name gives an empty set, implicit `ALL`;
- explicit-name locks and first explicit line wins;
- defaults 100 / −1;
- `count < limit` with −1 meaning unlimited;
- `ai_limit` is never applied.

## Open unknowns and limits

- **Archive precedence and the FBI set.** Both the archive order and the set of FBIs the real game loads (loose files, `.ufo` units such as CorNecro) are inferred. Type ids are exact only for the loaded set.
- **More than 512 type ids, id 0 included (unmodelled).** The category and resolve sets are 16 × 32 bits. Beyond that, the set writes go past the local set in `0x406db0`'s frame (the audit reads them as reaching its return address); no oracle case exercises this. The port refuses such a table with `unmodelled_type_set_overflow`. That is a port guard, **not native evidence**, and no shipped data reaches it (272 types).
- **Non-ASCII bytes.** Bytes 0x80 and above in profile lines are not modelled. The tokenizer's `isspace` indexes the C-runtime table with a negative index, which reads runtime-dependent memory. No shipped profile contains such bytes. The C locale is assumed for `_stricmp` and `toupper`.
- **Decimal conversion.** The `atof` port matches the native double and float32 bits on all 7,895 corpus strings, and the executed chain is deterministic integer code. Agreement outside the corpus is not proven, and the port is deliberately *not* correctly rounded where native is not.
- **Fallback buffer overflow.** From 47 characters `sprintf` overwrites the return address of `0x417890` (not saved registers); the emulated crash sites are listed under **Native faults**. What a real process does after the corrupted return is not established. The port treats every length above 46 as a fault and executes nothing after it.
- **Limit test slots ≥ 10.** Unmodelled; the port returns false with `unmodelled_limit_slot` (see the limit test).
- **Side effects not executed.** Console command effects, spawned units (position, owner meaning) and `debugdat` scripts are recorded, not run. No `debugdat` directory exists in the GOG install.
- **Player records.** The layout used in a real skirmish is not traced here: which slots get an AI object (`0x464990` → `0x464700`) and when ReloadAIProfiles can run. The oracle uses synthetic layouts.
- **Integration.** Nothing is connected to the game yet. CP3 (skirmish setup) supplies the difficulty, the `aiprofile` name and the player table; CP5 consumes the weight bytes and limits in `0x40bb00`.

## Rerun

From the repository root (the oracle takes about 2 minutes; the comparator and the tests take seconds):

```
python tools/prepare_ai.py
python tools/native_ai_profile.py
Godot_v4.6.2-stable_win64_console.exe --headless --path godot --script res://compare_native_ai_profile.gd
Godot_v4.6.2-stable_win64_console.exe --headless --path godot --script res://test_ai_profile.gd
```

Expected output: `NATIVE_AI_PROFILE wrote 426 cases (21 native faults)`, `AI_PROFILE_NATIVE 79371 / 79371 checks match`, `AI_PROFILE 69 / 69 checks pass`, all with exit code 0.

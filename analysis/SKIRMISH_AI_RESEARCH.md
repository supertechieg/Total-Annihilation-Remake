# TA skirmish AI port plan (replaces the provisional `godot/opponent.gd`)

**Sources:** the two research results ("build" and "military"), their verdicts and the data inventory. Where a verdict corrected a result, the correction is used. **V** means the address or claim was read from the disassembly, decompile or archives. **I** means it is inferred.

**Port files read:** only `godot/opponent.gd`, to see the API surface: `world.queue_unit`, `begin_build`, `placement_error`, `resume_build`, `move_unit`, `can_build`, `builder_jobs`, `combat.attack`, `catalog.build_options`. No repository files were changed.

---

## 0. What the original AI actually is (what the plan has to reproduce)

1. **Data.** The only AI data is a plain-text profile, `ai\<aiprofile>.txt`, with three commands: `plan`, `weight` and `limit`. Units add FBI `ai_weight` / `ai_limit` strings. There is no `.bai` support, no threat map and no economic planner.
2. **Structure.** Each present player whose type is not 3 gets a "brain" (0x3d bytes, built by 0x408cb0 and stored at player+0x74).
   - The brain has 9 group handlers, one per `unit+0xac` group number. These are the same group numbers humans set with Ctrl+N.
   - Groups are assigned by unit class every 30 ticks.
3. **Difficulty** does not change the thinking. It does two things only:
   - picks which `plan` blocks of the profile apply;
   - scales every resource credit to a type-2 owner: ×0.5 on easy, ×0.7 on medium, ×1.0 on hard (V).
4. **Targeting.** Attack forces go for the nearest enemy unit anywhere on the map with no LOS check (V, 0x4071f0). The AI's weapon scheduler also auto-fires commandfire weapons: the D-gun, nukes, and the CC EMP/Tron launchers (V; the Krogoth is not included).

---

## 1. Data structures (Godot)

### 1.1 `AIProfile` (static per game, loaded once)
- **Source files.** `ai/<name>.txt` from the archive overlay. Search order is rev31.gp3 > btdata/ccdata .ccx > totala*.hpi, plus map .ufo files. That archive precedence is I and needs an oracle.
- **Fallback.** Use `ai/default.txt` when `aiprofile` is empty or the file is missing. The exe paths are 0x435430 slot 7 → 0x4648e0, literal `ai\default.txt` at 0x507308 (V; the missing-file fallback is I).

### 1.2 `AIContext` per player (mirrors `DAT_005119c0[i]`)
In the native code every per-type array is a `std::vector`, not an inline array (V verdict). In the port they are plain arrays indexed by type id; id 0 is invalid.

| field | native | init | notes |
|---|---|---|---|
| completed_count[type] (short) | [ctx+0x81]+2u | 0 | own units with build progress +0x104 == 0.0 only |
| bytes[type][3]: general, metal, energy (signed) | [ctx+0x69]+3u | from 0x409730 | general has no lower clamp |
| value[type] (signed) | [ctx+0x91]+u | 0x409730 | used only by group 9 |
| centre_weight[type] (signed char) | [ctx+0xa1]+u | 40·(bmcode==0) + 20·(buildlist ptr≠0) | 0x409470 |
| weight[type] (u8) | [ctx+0xb1]+u | 100 | |
| weight_lock[type] | [ctx+0xc1] | 0 | |
| limit[type] (int) | [ctx+0xd1]+4u | −1 | |
| limit_lock[type] | [ctx+0xe1] | 0 | |
| builder_capable_count | ctx+0x75 | 0 | own completed units whose def has a build-list pointer |
| has_targeting_facility | ctx+0x79 | 0 | needs unit+0x10e bit 0 |
| known_enemies (LOS) | ctx+5 | | visible via 0x465ac0, not flagged 0x8000 |
| enemy_list_2 (no vis test) | ctx+0x15 | | unit+0x110 bit 0x100 |
| own_airbase_builders | ctx+0x25 | | |
| base_centre (16.16 vec3) | ctx+0x35/39/3d | 0 | returned by 0x40ba80; (0,0,0) means "no base" |
| metal_spots [{cx,cz,metal}] | ctx+0x51/55 | built once (0x40a7b0) | |
| last_refresh_tick | ctx+0xed | | |
| lattice_land {sx,sz,ox,oz,margin=3} | ctx+0xf1..0xf9 | 0x40a150 | |
| lattice_water {…, margin=6} | ctx+0xfd..0x105 | 0x40a150 | |
| place_radius R | ctx+0x109 | 0 | |

### 1.3 `AIBrain` per player (native player+0x74)
- Fields:
  - `countdown` (+5) = 30
  - `commander_build_block_tick` (+0xd) = 0
  - `handlers[10]` at +0x11+4k (slot 0 is null)
  - `weapon_cursor` (+0x39)
- Each handler has `wake_tick` (+0xc, starts at 0, so everything runs on the first tick) and group k.
- Handler table:

| k | think | period | params / notes |
|---|---|---|---|
| 1 | 0x4086d0 | 30 | structures: factories, metal makers |
| 2 | 0x4077e0 | 300 | land attack force; src=3, min=3, start=6, K=20000, attacking=0 |
| 3 | 0x4079f0 | 150 | feeder into group 2 |
| 4 | 0x408100 | 90 | builders and Commander |
| 5 | 0x407380 | none | `ret`; wake is never set, so the no-op runs every tick |
| 6 | 0x4077e0 | 300 | naval attack force; src=7, K=50000 |
| 7 | 0x4079f0 | 150 | feeder into group 6 |
| 8 | 0x407ae0 | 30+rand(900) | aircraft |
| 9 | 0x407e90 | 30+rand(150) | "hunter"; never populated (V/I), port last |

### 1.4 Unit and state fields the port must expose
Only the meanings marked V can be relied on.

- `group` (unit+0xac): 0 = none, −1 = dead.
- `flags110`:
  - bit 29 = structure, i.e. bmcode==0 (V)
  - bit 31 = armed, i.e. any weaponN (V)
  - bit 28 = active (V)
  - bit 0x20 = AI-eligible, set at creation (meaning I)
  - 0x4000 = excluded (I)
  - bits 18–19 = move state, bits 20–21 = fire state (V)
  - low 2 bits = layer; 2 = airborne (I)
- **Order records.**
  - Flag word order+0x42: bit 4 is kept when the queue is cleared (V). Bit 8 means "don't re-plan this builder" (I). Bit 0x4000 means "idle-equivalent" for pass 2 (V as a bit; meaning I). Bit 0x20000 lets return fire override.
  - order+0x36/+0x3a hold p7/p8.
- **Player economy** (player record = game+0x1b63 + i·0x14b):

| field | offset | status |
|---|---|---|
| energy stored | +0x8c | V |
| energy produced | +0x90 | V |
| energy requested | +0x94 | V |
| metal stored | +0x98 | V |
| metal produced | +0x9c | V |
| metal requested | +0xa0 | V |
| energy storage max | +0xa4 | V |
| metal storage max | +0xa8 | V |

  - Settlement 0x401360 was not re-traced; the 0x40bb00 usage was checked.
  - 0x464ad0 = produced − requested (V from the build result; the military verdict only confirms "the return of 0x464ad0").

---

## 2. Routines with pseudo-code

### 2.1 RNG (V, 0x4b6c30, state 0x51fc88)
```
rand(n): if n < 2 (signed): return 0   # state NOT advanced
         state = parkmiller(state); return state % n (unsigned)
```
Every AI draw uses the shared simulation stream. The call order listed below is part of the spec.

### 2.2 Profile interpreter (V: 0x406f00, 0x4b7a30, 0x406c90, 0x406db0, 0x406e40, 0x488d30)
```
active = 1
for line in text.split('\n'):
  tok = whitespace_split(line)[:20]; drop from first token starting '#'
  # '//' is NOT a comment: the line is just an unknown command and is ignored
  cmd = tok[0].lower()
  plan:   active = 0; if any arg matches diff name (easy/medium/hard) or argv[1]=="any": active=1
  weight: if active: (set, explicit) = resolve(tok[1]); for p in slots with brain: apply_weight(p,set,float(tok[2]),explicit)
  limit:  if active: same, but only players with type==2: apply_limit(p,set,int(tok[2]),explicit)
resolve(name): unitname (case-insensitive binary search) -> {id}, explicit=1
               else category set (unknown name -> empty set), explicit=0   # ALL is implicit
apply_weight: for id in set if !weight_lock[id]: weight[id]=clamp(trunc(weight[id]*w),0,100); if explicit: lock
apply_limit:  for id in set if !limit_lock[id]: limit[id]=v; if explicit: lock
```
Load order at game start (0x464990 → 0x464700 per player → 0x4648e0):
1. Run the map profile.
2. For each type-2 player, run 0x409f80(i) then 0x40a040(i). Each applies the FBI `ai_weight` string of every downloadable, unlocked unit.
3. **Native bug (V):** 0x40a040 runs `ai_weight` a second time instead of `ai_limit`. FBI `ai_limit` is never applied, and the second weight pass is blocked by the lock the first pass set.
4. Profile lines are applied first, so they win over the FBI fields.

Reproduce the bug.

### 2.3 Brain tick (V: 0x464f80 → 0x408c40 at 0x465031, then 0x40b2c0 at 0x465037)
```
for i in 0..9: p=player[i]; if p present && type in {1,2,3} && p+0x146 != 10:
   if brain: 
     if type==2 && p[0]!=0:
        if --countdown <= 0: countdown=30; assign_groups(p)
        for k in 1..9: if handlers[k].wake <= tick: handlers[k].think()
        weapon_scheduler(brain, allow_commandfire=1)
     else: weapon_scheduler(brain, 0)
   knowledge_refresh(i)
```

### 2.4 `assign_groups` (0x408830, V)
```
for u in own units (player+0x67..+0x6b, stride 0x118) with flags110 & 0x20:
   move: if def.cancapture: clear 0x80000, set 0x40000 (MANEUVER) else clear 0x40000, set 0x80000 (ROAM)
   fire: clear 0x100000, set 0x200000 (FIRE AT WILL)   # clears only 1 bit of each 2-bit field
   if u.group != 0: continue
   if structure: group = armed?5:1
   elif def.builder(0x241 b6): 4      # air/sea constructors land here
   elif def.canfly(b11): 8
   elif (short)def.minwaterdepth > 0: 7
   elif armed: 3
   else: leave ungrouped
```

### 2.5 `knowledge_refresh` (0x40b2c0 / 0x40aa40, V)
```
if tick < ctx.last+30: return
ctx.last=tick
walk GLOBAL unit array; active = f&0x10000000 && !(f&0x4000)
  own (owner+0x146 == p+0x146) && progress==0.0: completed_count[type]++ ;
      builder_capable_count += (def.buildlist ptr != 0); centre accumulation float32 pos*w/65536
      if def 0x241&0x400 && u10e&1: has_targeting_facility=1 ; if def 0x241 has 0x40&0x200 && u10e&1: list25 add
  non-allied: if visible(0x465ac0) && !(f&0x8000): known_enemies add ; if f&0x100: enemy_list_2 add (no vis)
base_centre = sumW ? ftol(65536.0*(acc/sumW)) : 0
if rand(30)==0: recompute_type_bytes()      # also once at ctx creation (0x40b320)
```

### 2.6 `recompute_type_bytes` (0x409730; formulas V after the verdict corrections)
```
effEU(def) = energyuse!=0 ? energyuse : windgen>0 ? -wind_now*windgen : tidalgen>0 ? -tidal*tidalgen : 0   (0x488f30)
metal  = ftol(clamp((extractsmetal?100:0)+(makesmetal?25:0) - 0.02*buildcostmetal, 0,100))
energy = ftol(clamp(-0.0025*buildcostenergy - 5*effEU, 0,100))
b = (extractsmetal?11:1)+(makesmetal?10:0)+(effEU<0?10:0)
v = ftol(ftol(b+0.01*costM)+0.002*costE)
w = canattack?11:1; for wd in weapon1..3 (no null check; wd+0x10a!=0): w += dmg/40 + 5 + range/100
value = clamp(v + (s8)clamp(w,-100,100), -100,100)
t = canattack?21:1; +30 builder&&count<3; +50 effEU<0; +50 extractsmetal; +25 makesmetal; +40 canfly; +15 sonar; +5 radar
t = ftol(t + clamp(energymake,0,30)); count==0: t*=4; count==1: t*=2; (short)minwaterdepth >= 0: t*=3
if (word)p+0x144 > (word)game+0x1434f/2: t += value/2
if canload || isfeature || (windgen && game+0x1425f < game+0x37ec8/2): t=0
general = min(t,100)   # stored as signed byte, may wrap/negative
```

### 2.7 Build score and chooser (0x40bb00, 0x40bdb0; V)
```
score(p,type):
  if E<50 || M<25 || (campaign && downloadable) || !(limit==-1 || count<limit) || type==0 || type>=ntypes: 0
  ES=min(ftol(Emax),1000); MS=min(ftol(Mmax),500)
  eN=ftol(max(0,(ES-E)*0.125)); mN=ftol(max(0,(MS-M)*0.25))
  if Eprod-Ereq<1: eN+=20; if Mprod-Mreq<1: mN+=20
  if Eprod<50: eN+=100 elif Eprod<200: eN+=10
  if Mprod<3: mN+=100 elif Mprod<5: mN+=20
  m=clamp(mN,0,100); e=clamp(eN-m,0,100); g=max(0,100-m-e)
  return ((g*gen + m*met + e*en) * weight) / 10000   # int32, truncating
choose(p,builder): T=0; c=0; for id in def.buildlist: s=score; if s>0: T+=s; if rand(T)<s: c=id
  return (c && side(c)==side(builder)) ? c : 0
```

### 2.8 Group 1: structures (0x4086d0, V verdict version)
```
wake=tick+30
for u in group1 with bit29 && bit28 && !(f&0x4000):
  if def.makesmetal:
     if 2*M < E: if netEnergy(0x464ad0)>0 && rand(5)!=0: set_active(u,1)   # else unchanged
     else: set_active(u,0)          # 0x48b090(u,1,0)
  elif def.buildcount && u.head_order==null: t=choose(p,u); if t: addbuild(u, t, 1)   # 0x419b00
```

### 2.9 Group 4: builders and Commander (0x408100, V with corrections)
```
wake=tick+90; C=base_centre
pass1: for u in group4 with def.buildcount != 0:
   if def.cancapture: if builder_capable_count>=5 || tick < brain.cmd_block: continue
   if head && head.flags&8: continue
   t=choose(p,u); ok=find_site(p,u.pos,def(t),&out)           # 0x40bfe0
   C.y = out.y (native reads uninitialised stack: out.y never written)  -> port: keep C.y as an explicit "garbage" = previous value; flag unknown
   if cancapture && ftol(sqrt((out.x-C.x)^2+(out.z-C.z)^2)) > (((W-32)+(H-128))/3)<<16: continue   # 2D
   if ok: order(u, mode 0xE MOBILEBUILD, queue=0 REPLACE, pos=out, p7=t, p8=1)
pass2: for u in group4 with head==null || head.flags&0x4000:
   if cancapture: if builder_capable_count<5: continue
       C.y=u.y; d=C-u (3D)
       off = |d| > 640px ? (-sin(a)*640, 0, -cos(a)*640), a=rand(0x10000) : d
       order(u, MOVE, queue0, C+off); order(u, PATROL, queue1, (C.x,u.y,C.z))
   else: d=|C-u| (3D, C.y possibly stale)
       tgt = d>=320px ? C : d<16px ? u+rand320vec : u + (C-u)*(0x140<<32/d)>>16
       order(u, PATROL, queue0, tgt)          # resolves to REPAIRPATROL for builders
```
Trig (V): `0x4b70ef(a,L) = (T[((s16)a+0x20>>6)&0x3fe]*L + 0x1000)>>13`, where T is the int16 table at 0x509f00. 0x4b7123 is the same with a+0x4000.

### 2.10 Placement (0x40bfe0 / 0x40a260 / 0x40a5d0 / 0x40a150; V)
```
find_site(p,bpos,def,&out):
  if R < max(W,H) (game+0x14223/0x14227): R += 160
  D=C-bpos; S = (R<<16 < |D|) ? bpos + D*((R<<32)/|D|)>>16 : C
  if def.extractsmetal && SurfaceMetal < rand(255): ok=extractor_site(def,S,spots,R*4,&cell)
  else ok=grid_site(def,S,R,&cell)
  if ok: out.x=(fpx+2*cell.x)*0x80000; out.z=(fpz+2*cell.z)*0x80000; R=0
lattice init (ctx ctor): land sx=11+rand(10), sz=11+rand(3), ox=rand(sx)-sx/2, oz=rand(sz)-sz/2;
                         water sx=14+rand(20), sz=14+rand(3), ox, oz likewise
grid_site: lattice = (short)def.minwaterdepth>=0 ? water : land; 30 tries:
  r=rand(R); a=rand(0x10000); dx=sin(a,r<<16); dz=cos(a,r<<16)
  cx=(short)((S.x-dx-fpx*0x80000+0x80000)>>20)/sx*sx + ox + rand(sx-margin-fpx)   # trunc toward 0
  cz likewise; accept if buildable(0x47db70) && footprintMetal(0x47c770) <= SurfaceMetal*fpx*fpz*2
extractor_site: c0=((S-fp*0x80000+0x80000)>>20); cand = spots with d2<=(R*4)^2; heapify if >=2 (key -d2)
  pop nearest; stop if found && d2 > firstValidD2+160 (test before validation)
  tile = spot-(fp-3)/2; if 0x47d2e0(def,tile) && metal > best: best=..., record firstValidD2 on first improvement
  return best>0
spots (0x40a7b0 at start): cells with feature idx<0xfffb, feature.metal(+0xf0)!=0, feature+0xff&2
```

### 2.11 Group 2/6: attack force (0x4077e0, V)
```
wake=tick+300; cohesion(src, K); n=count; if n==0 return
if (n>3 && (attacking || n>=6)) || no base group:
   attacking=1; c=centroid(); T=nearest_enemy(c); if T: group_order(mode3 ATTACK, queue0, target=T)
else: b = centroid(g5) || centroid(g1) || centroid(g4); attacking=0; group_order(mode2 MOVE, queue0, pos=b, p7=0xa0)
cohesion(src,K): if src is self: return; if empty: take first src unit
  c=int16 centroid; while n>1: f=farthest; if d2(f)>=K*n: move f->src, recompute c else break
  for u in src: if d2(u,c) < K*n: join
nearest_enemy(pos): best=0x7fffffff; for players 0..9 present, type 1..3, +0x146!=10, not allied:
   for u: active && layer!=2 && !(f&0x8000) && !(u10e&4): d=(dx*dx>>32)+(dz*dz>>32); if d<best (strict): pick
```

### 2.12 Groups 3/7 feeders (0x4079f0, V) and group 8 aircraft (0x407ae0, V)
```
feeder: wake=tick+150; if n(self)>0 && n(force)>0: group_order(self, MOVE, queue0, pos=centroid(force)<<16)
air: wake=tick+30+rand(900)
  if n<5 && ((s16)B.x | (s16)B.z): k=rand(2)+2; for i<k: p=B+((rand(W/8)-(W/8)/2)<<16, ?, (rand(H/8)-(H/8)/2)<<16)
         group_order(i==0? MOVE q0 : PATROL q1, p)
  elif n<5: T=nearest_enemy(centroid); group_order(PATROL, q1, T.pos)   # native no null check -> port: guard
  else: if rand(2): x=rand(W)<<16; z=rand(2)?0:(H-1)<<16 else: x=rand(2)?0:(W-1)<<16; z=rand(H)<<16
        group_order(PATROL, q0, (x,?,z))
```

### 2.13 Group order dispatch (0x480460 → 0x43f0e0 → 0x43adc0, V)
```
group_order(p, g, mode, queue, target, pos, p7, p8):
  for u in own units with u+0xa6!=0 && u.group==g:
     sel = cursor_select(mode, u, target, pos)    # no sel==0 check (result type 0, STOP per I)
     insert_order(sel, queue, u, target, pos, p7, p8)
```
`insert_order` behaviour (V):
- queue 0 deletes every order except those with flag bit 4, and the new order gets flags 0x2001.
- queue 1 appends.

This local path does not go through the network order path 0x48cf30.

### 2.14 Damage hook (0x406f80, called from the hit handler at 0x489da2; V)
```
call 0x4897b0(unit,0x10)
if def.cancapture && owner.type==2: brain.cmd_block = tick+30+rand(300); clear_queue_except_flag4(unit)  # even w/o attacker
return-fire (owner type 1/2, armed|kamikaze, complete, attacker non-allied): see military facts (0x43b1f0 / 0x48a060)
```

### 2.15 Weapon scheduler (0x4089a0 → 0x40b7b0; V)
- Units handled per tick = (s16 game+0x37ee6)/30 + 1, round-robin from `weapon_cursor`.
- A weapon slot is skipped if its weapon is `dropped`, or if it is commandfire and allow_commandfire == 0.
- For type 2, the commandfire weapons are: ARM_DISINTEGRATOR, CORE_DISINTEGRATOR, NUCLEAR_MISSILE, CRBLMSSL, ARMEMP_WEAPON, CORTRON_WEAPON.
- Target selection: at most 50 random draws from LOS candidates in range. Score = rand(d²). Targets not in the def+0x231[slot] bitset are preferred.
- AI owners may target units without `shootme`.
- Radar blips are used only when the candidate list is empty and `has_targeting_facility` is set.

### 2.16 Difficulty income scale (V)
Every credit to a type-2 owner is multiplied by 0.5 (easy), 0.7 (medium) or 1.0 (hard). The native code computes `acc -= amt * (-0.5 | -0.7)`. Credit sites:
- settlement at 0x401441..0x40178b: energymake, negative energyuse, wind, tidal, extractor, maker, metalmake
- salvage at 0x4026ab
- reclaim at 0x4237d0
- 0x41bbbd
- death salvage at 0x486ce6
- transfers at 0x464b30 / 0x464c60
- 0x465443 / 0x4654af, whose object is unidentified

---

## 3. Game setup for the enemy (skirmish)

1. **Schema.** Difficulty is `game+0x37eee` (0 easy, 1 medium, 2 hard). It picks the OTA `[Schema]` whose `Type=` is Easy/Medium/Hard (0x436860, V).
   - From that schema: `aiprofile` (0x435da0, TDF read at 0x4366d5), `ComputerMetal` / `ComputerEnergy` as the AI's starting stored resources, and `SurfaceMetal` (settings+0xd30, default 0).
2. **Commander.** The enemy's Commander (armcom/corcom by side) spawns at OTA start position 2 from the schema's `specials` StartPos2. The port should read this from the OTA rather than hard-coding it. Whether starting storage max equals the Commander's storage, and which Computer* field sets it, is unverified (see U8).
3. **Order of events** (V addresses; relative RNG order I):
   1. Brain construction 0x464700: for each present non-remote player, build the ctx (0x409160 → 0x409470 defaults, 0x40a150 lattice rolls, 0x40b320 → 0x409730).
   2. Profile load 0x4648e0.
   3. Spot lists 0x4649d0 → 0x40b370 → 0x40a7b0 (call at 0x497c4a).
   4. Ticks start: the first AI tick runs every handler.
4. **Retire `opponent.gd` behaviour.** It builds solar/mex directly, uses nearest-metal sorting and attacks with every unit. All of that is replaced by the handlers above. Keep only its role as the per-step entry point.

---

## 4. Dependencies on other port systems (must exist first)

1. **Shared Park-Miller RNG** with the n<2 no-advance rule, exposed to the simulation. The COB rand test exists; make sure the AI uses the same stream.
2. **Per-player economy record:** stored, produced, requested and storage max, matching the 0x401360 settlement semantics, plus the type-2 income scale at every credit site.
3. **Order queue model:**
   - order records with a flags word (bits 4, 8, 0x20000, 0x4000) and p7/p8;
   - queue 0 = replace except flag 4, queue 1 = append;
   - cursor-mode resolver for modes 2 (MOVE / QMOVE / VTOL_MOVE), 3 (ATTACK_CHASE / NOMOVE / SUPPRESS / air variants / KAMIKAZE), 9 (PATROL / REPAIRPATROL / VTOL variants) and 0xE (MOBILEBUILD / VTOL_MOBILEBUILD);
   - PATROL and REPAIRPATROL movement.

   The current `combat.attack` / `world.move_unit` / `begin_build` calls are not enough. The AI needs patrol and queue replacement.
4. **Unit state fields:** group number, standing move/fire state bits, active/structure/armed flags, build progress (+0x104), head order. Human Ctrl+N must share the same group field.
5. **Factory `addbuild` (0x419b00):** queue a unit by name ×1, idle defined as head order null.
6. **Placement validation equal to player placement:** 0x47db70 / 0x47d2e0 buildability and yard checks, footprint metal sum 0x47c770, and the metal-feature grid (feature +0xf0 metal, +0xff&2 indestructible).
7. **Knowledge context:** visibility query 0x465ac0 for `known_enemies`, radar fallback, and alliance bytes player+0x108. The 30-tick LOS/radar rebuild order relative to the brain tick matters: brain first, then refresh.
8. **Weapon scheduler and target selector** 0x4089a0 / 0x40b7b0 with an allow_commandfire flag, and D-gun / nuke / EMP firing for AI owners.
9. **Damage notify:** `damage_notify.gd` must call the AI hook (0x406f80), including the Commander queue clear and the return-fire rules.
10. **Wind state** (live wind for effEU) and the tidal value.
11. **Map dimensions:** W, H in pixels at game+0x14223/0x14227 and the game+0x1422b/0x1422f leash values (W−32, H−128, per 0x4833b0/0x416730). The game+0x1425f / 0x37ec8 wind gate fields are also needed.
12. **Archive overlay and TDF parser** for `ai/*.txt`, including `tamechpi2004.ccx` and `.ufo` profiles.

---

## 5. Oracles worth building (native TotalA.exe instrumentation)

| # | Oracle | What to capture | Validates |
|---|---|---|---|
| O1 | Profile parser | Break after 0x4648e0; dump [ctx+0xb1]/[ctx+0xd1] and both locks for all types, per difficulty, for totala1 / rev31 default, missions, airbattle and an FBI-field unit (corflak, armmark) | parser, plan flag, lock order, ai_limit bug |
| O2 | Type bytes | Dump [ctx+0x69] and [ctx+0x91] after 0x409730, or use the in-game `PrintWeights` command (0x418bb0) / debug dump 0x40c250 | the 0x409730 formulas incl. the 0.002 / 0.0025 constants, wind dependence, count multipliers |
| O3 | Score and chooser | Log args and return of 0x40bb00 and 0x40bdb0, plus RNG state before and after | need-level math, /10000, weighted pick, RNG consumption |
| O4 | RNG trace | Log every 0x4b6c30 call (caller return address, n, result) for the first ~3000 ticks of a 1v1 skirmish on a fixed seed | whole-AI call order; the most valuable single oracle |
| O5 | Placement | Log 0x40bfe0 inputs/outputs, R, lattice params, 0x40a260 candidate pops | grid and extractor site choice |
| O6 | Group assignment | Snapshot unit+0xac and 0x110 state bits every 30 ticks | 0x408830 and the unknown bits 0x20 / 0x4000 |
| O7 | Order stream | Hook 0x43adc0: tick, unit, order type, queue flag, pos, p7/p8 | builder replace cadence, attack/retreat hysteresis, patrols, aircraft |
| O8 | Base centre and counts | Dump ctx+0x35..0x3d, ctx+0x75, [ctx+0x81] after 0x40aa40 | knowledge refresh |
| O9 | Economy handicap | AI income per tick on easy/medium/hard, same base | 0.5 / 0.7 scaling sites |
| O10 | Commander hit | Damage the AI Commander; log brain+0xd and the queue before and after | 0x406f80 |
| O11 | Weapon scheduler | AI Commander D-gun auto-fire and an AI nuke silo target choice | allow_commandfire, 0x40b7b0 |

Port-side comparators should follow the existing `compare_native_*.gd` pattern: `compare_native_ai_profile.gd`, `…_ai_bytes`, `…_ai_choose`, `…_ai_placement`, `…_ai_rng_trace`, `…_ai_orders`.

---

## 6. Ordered checkpoints (commit and push each verified one)

1. **CP1 RNG and AI plumbing.** Shared rand with n<2 no-advance; AIContext/AIBrain skeleton; brain tick order inside the sim step (brain then refresh, players 0..9). Test: wake ticks and cadence counters.
2. **CP2 Profile interpreter.** Tokenizer, `plan` / `weight` / `limit`, unitname vs category resolution (implicit ALL, unknown name = empty set), locks, the FBI ai_weight double-run bug, default fallback. Oracle O1.
3. **CP3 Skirmish setup.** Difficulty → schema, aiprofile, ComputerMetal/Energy, SurfaceMetal; enemy Commander at StartPos2 with side; ctx construction RNG order (lattice rolls, first 0x409730). Oracle O4 (setup prefix).
4. **CP4 Knowledge refresh.** Completed counts, builder_capable_count, base centre with float32 accumulation, enemy lists, 1/30 recompute. Oracle O8.
5. **CP5 Type bytes and score/chooser.** 0x409730, 0x40bb00, 0x40bdb0. Oracles O2, O3.
6. **CP6 Economy handicap.** 0.5/0.7/1.0 at every type-2 credit site. Oracle O9.
7. **CP7 Group assignment and state forcing.** 0x408830. Oracle O6.
8. **CP8 Group 1.** Factory addbuild and metal-maker toggle.
9. **CP9 Placement.** Metal spot list, lattice, grid_site, extractor_site, radius growth. Oracle O5.
10. **CP10 Group 4 builders and Commander.** Pass 1 MOBILEBUILD with replace, commander gate and leash; pass 2 patrols and commander out-and-back. Needs the order queue flags and PATROL/REPAIRPATROL. Oracle O7.
11. **CP11 Damage hook.** Commander block and queue clear, return fire. Oracle O10.
12. **CP12 Groups 2/3/6/7.** Cohesion, feeders, attack/retreat with omniscient nearest_enemy, group_order dispatch with no sel check. Oracle O7.
13. **CP13 Group 8 aircraft.** Base patrol, edge sweep, no-base patrol (guard the null).
14. **CP14 Weapon scheduler for AI.** allow_commandfire (D-gun, nukes, EMP) and the non-shootme permission. Oracle O11.
15. **CP15 Full-match RNG/order trace parity.** First N thousand ticks vs native (O4 + O7), then group 9 for completeness.

---

## 7. Unknowns (inferred or unverified; resolve with the oracles)

- **U1** Meanings of unit+0x110 bits 0x20 (AI-eligible?), 0x4000, 0x8000 and 0x100, unit+0x10e bits 0 and 4, and `layer==2` = airborne.
- **U2** order+0x42 bits: 8 (builder busy / no re-plan?) and 0x4000 (idle-equivalent?). Also whether pass 1's replace really interrupts builds in progress every 90 ticks, and whether sel==0 gives STOP.
- **U3** Uninitialised stack values:
  - the pass-1 C.y (0x40bfe0 never writes out.y; copied at 0x408250) and its effect on later 3D builder distances;
  - the aircraft edge-sweep y (esp+0x20).

  Pick a deterministic stand-in (for example the previous C.y, or the unit y) and confirm it with O7.
- **U4** Default `minwaterdepth` for land units. With `>= 0` land/water lattice selection and the ×3 general multiplier, a default of 0 would give every land unit ×3 and the water lattice. Check the FBI/moveinfo defaults, since the port's placement depends on it.
- **U5** Heap tie ordering in 0x40d620/0x40d700; strict-min tie order in nearest_enemy (first-found wins, I).
- **U6** Fields game+0x1425f and game+0x37ec8 (wind gate), player+0x144 and game+0x1434f (the general-byte value term), and game+0x37ee6 (scheduler divisor, probably the unit limit).
- **U7** The spawn-bonus object at 0x465443 ([esp+0x34]+0xa1/+0xa3 ×100 ×0.5/0.7 added to a new unit's accumulators). Also the difficulty reads not yet examined: 0x41ee9a, 0x4311d1, 0x4327cf, 0x4368e3, 0x45f53b, 0x477431.., 0x478435.., 0x47b93f...
- **U8** How ComputerMetal/ComputerEnergy map to stored vs max storage at start, and what StartPos numbering means for player slot assignment.
- **U9** Archive precedence for `ai/*.txt`, and whether a missing named profile falls back to default at 0x435430 (the empty-name case is V).
- **U10** Whether 0x487270 (restore/copy) can put units into group 9. Group 9 is otherwise dead. Also 0x408620/0x408670 and 0x408bf0 have no direct callers.
- **U11** Multiplayer with hosted AI: type-3 players have no brain, and AI orders bypass 0x48cf30, so the sync model is unknown. It is not needed for single-player skirmish.
- **U12** The interior of 0x43b1f0 return fire (hold-position refusal, maneuver leash def+0x214), and 0x4897b0(unit, 0x10).
- **U13** Weapon-definition presence byte +0x10a (I) in the value-byte loop.

---

## 8. Relevant paths

- Port target: `C:\Users\garet\Documents\ChatGPT\Total Annihilation\godot\opponent.gd` (replace), with new AI modules and `compare_native_ai_*.gd` next to it.
- Executable and analysis: `C:\Users\garet\Documents\ChatGPT\Total Annihilation\local\original\TotalA.exe`, `...\local\decompiled\TotalA.decompiled.c`, `...\local\decompiled\string-references.tsv`, `%TEMP%\claude\text.asm`.
- Data: `C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation\{totala1.hpi, ccdata.ccx, btdata.ccx, rev31.gp3, tamechpi2004.ccx}` under `ai/*.txt`; FBI `ai_weight` / `ai_limit` in `units/*.fbi`; `C:\Users\garet\Documents\ChatGPT\Total Annihilation\local\unit-assets\index.json`.
- Scratch profile extracts: `%TEMP%\claude\re-scratch\ai\<archive>\`.

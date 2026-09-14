# Player controls

## Group selection and orders

The development viewer now supports squad control alongside its single-unit and Commander controls:

- **Shift + left-drag** draws a selection box and selects every completed, owned, mobile unit inside it; the Commander is excluded. **A** selects the whole army: every owned, completed, mobile unit with supported weapons. Selected units show green rings, and the panel reports the count.
- **Left-click terrain** with a group selected issues a formation move. Units are laid out on a grid around the clicked point with 40-unit spacing, and each destination goes to that unit type's nearest open cell. A move cancels each unit's attack order without stopping the new route.
- **Left-click an enemy** orders every selected unit to attack with pursuit. **Left-click an owned unit** clears the group and selects that unit. **Select Commander** also clears the group.
- **S or right-click** stops every unit in the group: its attack order and its movement.
- Plain left-drag still pans the map. The **D** key D-gun, placement and single-unit behaviors are unchanged.

`--verify-group-orders` on Comet Catcher (also `--faction core`) spawns four of the faction's vehicle combat units, box-selects exactly those four, and moves them 360 units into formation. It requires every unit within 90 units of the goal with no two closer than 16 units. It then spawns an enemy and group-attacks it until it is destroyed with no script faults. Both factions pass and run in NORMAL verification. A rendered capture was inspected: four Flash tanks in a 2×2 formation with selection rings.

## Limits

Formation layout and pathing use the provisional host navigation and are not the original group-movement behavior: no speed matching, formation keeping or original grid choice. There are no control groups (Ctrl+number), no command queue (Shift+click orders), no right-click-to-move convention, and no double-click type selection.


## Squads and selection keys

Recovered by the command-layer research workflow (analyst + adversarial verifier).

- **Storage.** Squads ("control groups") are an integer per unit (`unit+0xac`): -1 in a free slot, 0 at creation. Each player also keeps per-squad vectors.
- **Create (`0x48d920`).** Every selected own unit is put in squad n. Units already in n that are not selected move to squad 0.
- **Select (`0x48d9a0`).** Selects the squad's selectable members, deselecting everything else unless Shift is held.
  - If the squad contains both factories and armed units, the factories are left out.
  - Dead or unfinished units are never selectable.
- **Default key binding (`SwitchAlt` off, `game+0x37f06` bit 0x100).** Ctrl+1..9 creates a squad and Alt+1..9 selects it. A plain digit changes the build-menu page, and SwitchAlt swaps the two.
- **Other keys (game key handler `0x495e90`).** Ctrl+A selects all, Ctrl+Z adds all units of the selected types (there is no double-click select in the game view), Ctrl+S selects own units on screen, and Esc cancels an order mode or deselects.
- **Order hotkeys.** S, M, A, P, G and the rest are not global. They are quickkey fields in the per-unit order GUI files.

**Implementation.** `viewer.gd` adds `create_squad`, `select_squad(n, add)`, `select_same_types`, `select_all_own`, and the Ctrl/Alt digit, Ctrl+A, Ctrl+Z and Esc bindings.

**Evidence.** `--verify-squads` passes for both factions in NORMAL. It checks:
- assigning squad 2 and squad 3;
- Alt-selecting squad 2 only;
- Shift adding squad 3;
- reassigning squad 2 moving the unselected member to squad 0;
- Ctrl+Z adding the same type;
- a dead member no longer being selected.

**Limits.**
- The Commander and factories are outside the viewer's selectable group.
- Squad inheritance for factory-built units, Ctrl+S, camera bookmarks and the SwitchAlt option are not implemented.
- Order hotkeys await the unified order queue and order GUI port (research plan recorded in HANDOFF.md).

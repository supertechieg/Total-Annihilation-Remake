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

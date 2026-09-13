# Simulation piece origins

`piece_origin.gd` reconstructs the coordinate traversal at `0x0043def0`, using supplied model offsets, movement offsets and runtime rotations. This is a simulation origin calculation, not a replacement renderer matrix or a full piece mesh transform.

The selected piece starts at its model offset plus movement. Its own rotation does not move its origin. For each parent, the routine rotates the current point in XY by the parent's Z rotation, then YZ by X rotation, then XZ by Y rotation. Each two-coordinate rotation rounds to nearest/even integers. It then adds the parent's model and movement offsets. On the root parent, the unit's roll/heading/pitch are added to the corresponding piece angles before rotation. The final Z coordinate is negated. A root piece's own origin therefore returns its offset without applying unit rotation. The caller adds unit world position separately.

The pair-rotation helper at `0x004b7173` uses original x87 sin/cos with angle scale `0.00009587379924285`; it does not use the 512-entry integer table used by launch velocity. The current implementation uses binary64 sin/cos and explicit nearest/even rounding. Untested precision boundaries remain unproven.

`native_piece_origin.py` executes the unmodified traversal and rotation helpers on 600 synthetic hierarchies of one to six pieces. It supplies native model records, geometry offsets, pose values and unit angles. All outputs match. Six normal checks cover root offsets, child origins, combined root/unit angles, invalid indices and rounding. The oracle does not replace arithmetic or transforms. The compact report is `native-piece-origin-validation.json`; raw synthetic traces remain under ignored local/piece-origin.

Native model pose layout is geometry pointer at record+0, movement XYZ at +4/+8/+12, rotation XYZ as shorts at +0x10/+0x12/+0x14, and parent pointer at +0x32. Records begin at model+0x22 with stride0x36. Native unit model pointer is +0x9e and roll/heading/pitch are +0x64/+0x66/+0x68.

This primitive is not yet connected to Flash or Raider muzzle queries. Next verify COB pose-to-model binding and real unit hierarchies, then replace combat's current provisional renderer-derived origin. That integration must preserve the native query and AimFrom callback choices; renderer transforms remain separately unverified. Full cannon collision/damage and opponent work also remain.

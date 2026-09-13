# Team economy foundation

ConstructionWorld now keeps separate resource accounts by team. Existing public
energy/metal fields represent team 0 for viewer compatibility; resources(team)
and store_resources(team, account) expose other accounts. Each team's completed
units supply its income, upkeep and storage. Construction charges the builder's
team. Newly created structures and factory products inherit the creator's team.
add_unit accepts an optional team argument, defaulting to zero.

Six isolation checks cover enemy solar income, player commander income, enemy
construction stalling despite player funds, spending only the enemy account,
and factory product ownership. Existing construction/factory tests also pass.
This is a host prerequisite for base-building opponents, not reconstructed
original AI. Immediate payment and base starting storage/resources remain
provisional. Diplomacy, shared resources, per-player unit limits, capture,
selection permissions and an autonomous base-building policy remain unfinished.

Ownership checks now reject cross-team resume and construction spending, including calls directly into advance_construction. The viewer rejects direct selection of enemy units; enemy map clicks already route to attack orders. Nine team-economy checks and 48 mobile-builder checks pass. Allied assistance is not implemented; the current rule requires the same team.


## Per-team unit limits

Construction placement and factory product creation now compare the owner's
unit count with unit_limit. Existing unfinished units count; pending queue
entries do not consume slots until a product is created. The default remains
1000 per team. add_unit is a setup primitive and intentionally does not enforce
the limit. This does not establish a tested performance ceiling of 1000 units.

Seven checks verify independent counts, construction despite an opponent at its
cap, refusal when the player's own cap is reached, queued factory waiting and
resumption after a same-team slot is freed. All pass, along with the 36 factory
checks. Original limit configuration/UI and large-battle benchmarking remain.

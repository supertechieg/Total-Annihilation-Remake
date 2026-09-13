extends RefCounted
## Completion rules for the current opt-in opponent scenario.
var outcome := "active"
func update(units: Dictionary, commander_id: int, enemy_team := 1) -> String:
	if outcome != "active":
		return outcome
	if not units.has(commander_id):
		outcome = "defeat"
		return outcome
	for unit: Dictionary in units.values():
		if int(unit.get("team", 0)) == enemy_team:
			return outcome
	outcome = "victory"
	return outcome

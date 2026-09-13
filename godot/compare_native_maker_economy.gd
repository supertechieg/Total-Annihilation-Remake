extends SceneTree
const Allocation = preload("res://resource_allocation.gd")
const Gate = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/economy.json"))
	var differences: Array = []
	var count := 0
	for item: Dictionary in trace.cases:
		var energy: float = item.stock
		var metal := 0.0
		var debts := [0.0, 0.0, 0.0]
		for snapshot: Dictionary in item.snapshots:
			count += 1
			var ledgers: Array = [{"income": snapshot.income, "requested": 0.0, "accepted": 0.0, "debt": debts[0]}]
			var metal_ledgers: Array = [{"income": 0.0, "requested": 0.0, "accepted": 0.0, "debt": 0.0}]
			for i in [1, 2]:
				var active: bool = snapshot.active if i == 1 else true
				var gate := Gate.apply(60.0, debts[i], 0.0, 0.0) if active else {"requested": 0.0, "accepted": 0.0, "productive": 0}
				ledgers.append({"income": 0.0, "requested": gate.requested, "accepted": gate.accepted, "debt": debts[i]})
				metal_ledgers.append({"income": float(gate.productive), "requested": 0.0, "accepted": 0.0, "debt": 0.0})
			var e := Allocation.settle_account(energy, 1000.0, ledgers)
			var m := Allocation.settle_account(metal, 1000.0, metal_ledgers)
			energy = e.stock
			metal = m.stock
			for i in range(3):
				debts[i] = e.ledgers[i].debt
			var actual := {"energy": energy, "metal": metal, "energy_income": e.income, "energy_requested": e.requested, "metal_income": m.income}
			var mismatch := false
			for key in actual:
				mismatch = mismatch or Gate.float32(actual[key]) != Gate.float32(snapshot[key])
			for i in range(3):
				mismatch = mismatch or Gate.float32(debts[i]) != Gate.float32(snapshot.debts[i])
			if mismatch:
				differences.append({"snapshot": snapshot, "actual": actual, "debts": debts.duplicate()})
	FileAccess.open("res://../analysis/native-maker-economy-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"snapshots": count, "mismatches": differences.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Full original settlement for completed generator and two makers, stock shortages, recovery and toggling; player type 3 skips cloak callback; excludes construction, extractor yield, handicap and scheduler"}, "  ") + "\n")
	print("MAKER_ECONOMY %d / %d match" % [count - differences.size(), count])
	quit(0 if differences.is_empty() else 1)

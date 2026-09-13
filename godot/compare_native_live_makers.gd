extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var removal := "--remove-maker" in OS.get_cmdline_user_args()
	var filename := "economy-removal.json" if removal else "economy.json"
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/" + filename))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	# Match the supplied native fixture definitions, retaining real maker scripts.
	for type: String in ["armcom", "armmakr"]:
		var fields: Dictionary = catalog.definition(type)
		for field: String in ["energymake", "metalmake", "energyuse", "energystorage", "metalstorage"]:
			fields[field] = "0"
	catalog.definition("armmakr").energyuse = "60"
	catalog.definition("armcom").energystorage = "1000"
	catalog.definition("armcom").metalstorage = "1000"
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var count := 0
	var failures: Array = []
	for item: Dictionary in trace.cases:
		var world := World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
		world.base_energy_storage = 0
		world.base_metal_storage = 0
		world.energy = item.stock
		world.metal = 0
		var maker := world.add_unit("armmakr", Vector2(256, 256), 0)
		var other := world.add_unit("armmakr", Vector2(384, 384), 0)
		for snapshot: Dictionary in item.snapshots:
			catalog.definition("armcom").energymake = str(snapshot.income)
			if snapshot.get("removed", false) and world.units.has(maker):
				world.remove_unit(maker)
			if world.units.has(maker):
				world.set_active(maker, snapshot.active)
			world.step()
			var mismatch := Float.float32(world.energy) != Float.float32(snapshot.energy) or Float.float32(world.metal) != Float.float32(snapshot.metal)
			var ids := [world.builder_id, maker, other]
			for i in range(3):
				if not world.units.has(ids[i]):
					continue
				mismatch = mismatch or Float.float32(world.units[ids[i]].energy_ledger.debt) != Float.float32(snapshot.debts[i])
			if mismatch:
				failures.append({"stock": item.stock, "snapshot": count, "energy": world.energy, "metal": world.metal})
			count += 1
			for tick in range(29):
				world.step()
			if (world.scripts.has(maker) and not world.scripts[maker].fault.is_empty()) or not world.scripts[other].fault.is_empty():
				failures.append({"script_fault": true})
	var report := "native-live-maker-removal-validation.json" if removal else "native-live-maker-validation.json"
	FileAccess.open("res://../analysis/" + report, FileAccess.WRITE).store_string(JSON.stringify({"snapshots": count, "failures": failures, "scope": "Live World.step against native settlement: balances and surviving-unit debt, optionally clearing one maker valid flag; excludes original destruction callbacks"}, "  ") + "\n")
	print("LIVE_MAKERS %d snapshots, %d failures" % [count, failures.size()])
	quit(0 if failures.is_empty() else 1)

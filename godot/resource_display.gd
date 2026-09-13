extends RefCounted

static func describe(account: Dictionary) -> String:
	var lines := PackedStringArray()
	for resource: String in ["metal", "energy"]:
		lines.append("%s %.0f / %.0f" % [resource.capitalize(), account[resource], account[resource + "_storage"]])
		lines.append("Income %.1f/s  Demand %.1f/s" % [account.get(resource + "_income", 0.0), account.get(resource + "_requested", 0.0)])
		lines.append("Unpaid %.1f" % account.get(resource + "_debt", 0.0))
	return "\n".join(lines)

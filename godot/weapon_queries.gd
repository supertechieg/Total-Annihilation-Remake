extends RefCounted
## Synchronous primary piece queries with the original AimFrom fallback.
var vm: RefCounted
var fault := ""

func _init(script: RefCounted) -> void:
	vm = script

func output(callback: String, initial: int) -> int:
	if not vm.functions.has(callback):
		return initial
	var invocation: int = vm.invoke(callback, [initial])
	if not vm.fault.is_empty() or not vm.completions.has(invocation):
		fault = "Weapon piece query did not finish synchronously: " + callback
		return -1
	var completion: Dictionary = vm.completions[invocation]
	var result := int(completion.locals[0])
	vm.completions.erase(invocation)
	return result

func piece_name(aim_from := false) -> String:
	var piece := output("AimFromPrimary", -1) if aim_from else -1
	if piece == -1 and fault.is_empty():
		piece = output("QueryPrimary", 0)
	if not fault.is_empty():
		return ""
	if piece < 0 or piece >= vm.pieces.size():
		fault = "Weapon query returned an invalid piece"
		return ""
	return str(vm.pieces[piece].name)

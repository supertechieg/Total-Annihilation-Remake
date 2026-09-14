extends RefCounted
## LosTables (preload by path): true-LOS ray tables from gamedata/los.tdf, as loaded by the original
## 0x433130 -> 0x433380 (per TABLE%d) -> 0x4336f0 (per line%d and rotation) into the ray object 0x51e6a0,
## and the accessor 0x433500.
##
## tables[i] (TABLE i+1) is an Array of rays; each ray is a PackedInt32Array of flattened absolute offsets
## [dx0, dy0, dx1, dy1, ...] from the viewer cell (native: 4-byte entries {int16 x, int16 y}).
##
## Native layout facts reproduced here (confirmed in the disassembly and by tools/native_los_tables.py):
## * numtables (TABLEINFO), numlines (TABLE%d) and each line's pair count are atoi results used as int16.
## * A table with numlines n holds 4n rays ordered by ROTATION first: ray index = rot * n + line.
##   (0x433380 calls 0x4336f0 for rays j, n+j, 2n+j, 3n+j with rot 0,1,2,3.)
## * Jump table 0x4339a4 is sequential: rot 0 (a,-b) 0x4337db, rot 1 (b,a) 0x43383a, rot 2 (-a,b) 0x433897,
##   rot 3 (-b,-a) 0x4338f6. Negation is 32-bit on the atoi value, then the entry is truncated to int16.
## * Line text: 0x4c48c0 copies at most 0x1ff characters of the (whitespace-trimmed) TDF value; tokens come from
##   strtok(", ") and CRT atoi (leading C-locale whitespace, optional sign, decimal digits, 32-bit wrap).
##   The first token is the pair count; each pair reads a then b; extra tokens are ignored.
## * A missing line%d key clears that ray; a present line without tokens leaves the ray untouched (empty on a
##   fresh load). A missing TABLE%d section leaves that table empty. A missing TABLEINFO gives no tables.
## Undefined or fatal native behaviour is reported as a fault and loading stops:
## * "tdf_parse_error": malformed TDF text; the original calls the fatal handler 0x4b6290 (MessageBox, exit).
## * "missing_token": fewer tokens than 1 + 2*count (atoi(NULL) reads address 0).
## * "negative_size": numtables, numlines or a pair count that is negative as int16 (vector resize to 2^32-k).
## * "ray_index_wrap": numlines > 8192, where rot*n + j exceeds 32767 and the int16 ray index goes negative.

const STRTOK_DELIMITERS := [44, 32]  # ", " at 0x504a00
const LINE_BUFFER := 0x200  # 0x4c48c0 size argument; byte 0x1ff forced to 0

static func s16(v: int) -> int:
	return ((v & 0xFFFF) ^ 0x8000) - 0x8000

static func s32(v: int) -> int:
	return ((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000

## C-locale isspace (_SPACE in the CRT ctype table): 0x09..0x0d and 0x20.
static func _is_space(c: int) -> bool:
	return c == 32 or (c >= 9 and c <= 13)

## CRT atoi 0x4e4ed0: skip isspace, optional '-' or '+', decimal digits with 32-bit wrap, negate for '-'.
static func atoi(s: String) -> int:
	var n := s.length()
	var i := 0
	while i < n and _is_space(s.unicode_at(i)):
		i += 1
	var sign := s.unicode_at(i) if i < n else 0
	if sign == 45 or sign == 43:
		i += 1
	var total := 0
	while i < n:
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			break
		total = (total * 10 + c - 48) & 0xFFFFFFFF
		i += 1
	if sign == 45:
		total = -total
	return s32(total)

## strtok(value, ", ") over the whole string: maximal runs of non-delimiter characters.
static func strtok_all(s: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var start := -1
	for i in range(s.length()):
		var delimiter: bool = STRTOK_DELIMITERS.has(s.unicode_at(i))
		if delimiter:
			if start >= 0:
				tokens.append(s.substr(start, i - start))
				start = -1
		elif start < 0:
			start = i
	if start >= 0:
		tokens.append(s.substr(start))
	return tokens

## TDF reader reproducing the original in-memory parse 0x4c3120 (comment stripper 0x4c33a0, tree builder 0x4c3e40)
## and the lookups this loader uses (section enter 0x4c3410, key lookup 0x4c4630 in the int/string getters).
## Returns {"root": node, "error": String or null}; node = {"keys": {folded key: value}, "children": [[name, node]]}.
## * The text ends at the first NUL (the stripper and the parser are C-string scans).
## * Comments: "//" blanks every byte up to (not including) '\n' ('\r' is blanked too); "/*" blanks every byte,
##   newlines included, through the closing "*/" or to the end of the text. Lengths are preserved (spaces).
## * Parser whitespace is only ' ', '\t', '\r', '\n'. At the cursor: NUL ends the root (inside a section it is the
##   fatal "End of file - nextblock not zero"); '[' reads a name up to the next ']' then requires '{' after
##   whitespace; '}' ends the current block (at the root too: the rest of the text is ignored); anything else is a
##   field: the key runs to the next '=' anywhere further on and the value to the next ';' after it, both trimmed.
## * Keys: _stricmp order (ASCII-only case folding); a repeated key overwrites, so the LAST assignment wins.
##   Sections: kept in order and looked up linearly with _stricmp, so the FIRST matching section wins.
## * Parse errors call the fatal handler 0x4b6290 (MessageBox then exit(1)) - reported here as an error string.
const TDF_ERRORS := {
	"eof": "End of file - nextblock not zero",
	"open": "Sub-record - opening '{' not found",
	"close": "Sub-record - closing ']' not found",
	"semi": "Data field - ';' not found",
	"eq": "Data field - '=' not found",
}

static func parse_tdf(text: String) -> Dictionary:
	var t := strip_comments(text)
	var root := {"keys": {}, "children": []}
	var state := {"pos": 0, "error": null}
	_parse_block(t, state, root, false)
	return {"root": root, "error": state.error}

## 0x4c33a0, in place on a copy; returns the text with comment bytes replaced by spaces.
static func strip_comments(text: String) -> String:
	var b := text.to_utf32_buffer().to_int32_array()
	var nul := b.find(0)
	if nul >= 0:
		b.resize(nul)  # C-string scan: the text ends at the first NUL
	var n := b.size()
	var i := 0
	while i < n:
		if b[i] == 47 and i + 1 < n and b[i + 1] == 47:
			while i < n and b[i] != 10:
				b[i] = 32
				i += 1
			continue
		if b[i] == 47 and i + 1 < n and b[i + 1] == 42:
			b[i] = 32
			b[i + 1] = 32
			i += 2
			# [i-1] is checked in its original form except the '*' of the opener, which is already blank, so "/*/"
			# does not close. An unterminated comment blanks up to but not including the final byte.
			while i < n:
				if b[i - 1] == 42 and b[i] == 47:
					b[i] = 32
					b[i - 1] = 32
					break
				b[i - 1] = 32
				i += 1
			if i >= n:
				break
		i += 1
	return b.to_byte_array().get_string_from_utf32()

static func _tdf_space(c: int) -> bool:
	return c == 32 or c == 9 or c == 13 or c == 10

## _stricmp C-locale folding: only 'A'..'Z'.
static func fold(s: String) -> String:
	var b := s.to_utf32_buffer().to_int32_array()
	for i in range(b.size()):
		if b[i] >= 65 and b[i] <= 90:
			b[i] += 32
	return b.to_byte_array().get_string_from_utf32()

## 0x4c4340: trim ' ', '\t', '\r', '\n' from both ends of t[start, end).
static func _tdf_trim(t: String, start: int, end: int) -> String:
	while start < end and _tdf_space(t.unicode_at(start)):
		start += 1
	while end > start and _tdf_space(t.unicode_at(end - 1)):
		end -= 1
	return t.substr(start, end - start)

static func _parse_block(t: String, state: Dictionary, node: Dictionary, nested: bool) -> void:
	var n := t.length()
	while true:
		var p: int = state.pos
		while p < n and _tdf_space(t.unicode_at(p)):
			p += 1
		state.pos = p
		if p >= n:
			if nested:
				state.error = TDF_ERRORS.eof
			return
		var c := t.unicode_at(p)
		if c == 91:
			var close := t.find("]", p)
			if close < 0:
				state.error = TDF_ERRORS.close
				return
			var name := _tdf_trim(t, p + 1, close)
			var q := close + 1
			while q < n and _tdf_space(t.unicode_at(q)):
				q += 1
			if q >= n or t.unicode_at(q) != 123:
				state.error = TDF_ERRORS.open
				return
			var child := {"keys": {}, "children": []}
			state.pos = q + 1
			_parse_block(t, state, child, true)
			if state.error != null:
				return
			node.children.append([name, child])
		elif c == 125:
			state.pos = p + 1
			return
		else:
			var eq := t.find("=", p)
			if eq < 0:
				state.error = TDF_ERRORS.eq
				return
			var semi := t.find(";", eq + 1)
			if semi < 0:
				state.error = TDF_ERRORS.semi
				return
			node.keys[fold(_tdf_trim(t, p, eq))] = _tdf_trim(t, eq + 1, semi)
			state.pos = semi + 1

## 0x4c3410 from the root: first child whose name matches case-insensitively, or null.
static func find_section(node: Dictionary, name: String):
	var key := fold(name)
	for entry in node.children:
		if fold(entry[0]) == key:
			return entry[1]
	return null

static func _has_key(section: Dictionary, key: String) -> bool:
	return section.keys.has(fold(key))

static func _get_key(section: Dictionary, key: String) -> String:
	return section.keys[fold(key)]

## 0x4c46c0: atoi of the key, or the default when absent.
static func _int_key(section: Dictionary, key: String, default_value: int) -> int:
	return atoi(_get_key(section, key)) if _has_key(section, key) else default_value

## Full loader result: {"tables": Array, "line_values": Array (per line, rotation 0 call: text or null),
## "fault": Dictionary or null}.
static func parse_detailed(tdf_text: String) -> Dictionary:
	var parsed := parse_tdf(tdf_text)
	var tables := []
	var line_values := []
	var result := {"tables": tables, "line_values": line_values, "fault": null}
	if parsed.error != null:
		# 0x4c3e40 -> fatal handler 0x4b6290: the game shows the message and exits before any table is built.
		result.fault = {"kind": "tdf_parse_error", "what": parsed.error, "table": -1, "line": -1, "rotation": -1}
		return result
	var root: Dictionary = parsed.root
	var tableinfo = find_section(root, "TABLEINFO")
	if tableinfo == null:
		return result
	var numtables := s16(_int_key(tableinfo, "numtables", 0))
	if numtables < 0:
		result.fault = {"kind": "negative_size", "what": "numtables", "table": -1, "line": -1, "rotation": -1}
		return result
	for i in range(numtables):
		tables.append([])
	for i in range(numtables):
		var found = find_section(root, "TABLE%d" % (i + 1))
		if found == null:
			continue
		var section: Dictionary = found
		var numlines := s16(_int_key(section, "numlines", 0))
		if numlines < 0:
			result.fault = {"kind": "negative_size", "what": "numlines", "table": i, "line": -1, "rotation": -1}
			return result
		var rays := []
		for r in range(numlines * 4):
			rays.append(PackedInt32Array())
		tables[i] = rays
		for j in range(numlines):
			var key := "line%d" % (j + 1)
			var present: bool = _has_key(section, key)
			var text: String = _get_key(section, key).substr(0, LINE_BUFFER - 1) if present else ""
			line_values.append(text if present else null)
			for rot in range(4):
				var index := rot * numlines + j
				if index > 32767:
					# 0x433380 computes the ray index as int16(rot*n + j): past 32767 it goes negative and the
					# original addresses a ray object before the vector (heap corruption or an access violation).
					result.fault = {"kind": "ray_index_wrap", "what": "ray index %d" % index, "table": i, "line": j, "rotation": rot}
					return result
				if not present:
					rays[index] = PackedInt32Array()
					continue
				var tokens := strtok_all(text)
				if tokens.is_empty():
					continue
				var count := s16(atoi(tokens[0]))
				if count < 0:
					result.fault = {"kind": "negative_size", "what": "pair count", "table": i, "line": j, "rotation": rot}
					return result
				if tokens.size() < 1 + 2 * count:
					result.fault = {"kind": "missing_token", "what": "pair tokens", "table": i, "line": j, "rotation": rot}
					return result
				var ray := PackedInt32Array()
				ray.resize(count * 2)
				for p in range(count):
					var a := atoi(tokens[1 + 2 * p])
					var b := atoi(tokens[2 + 2 * p])
					var dx: int
					var dy: int
					match rot:
						0:
							dx = a; dy = -b
						1:
							dx = b; dy = a
						2:
							dx = -a; dy = b
						_:
							dx = -b; dy = -a
					ray[p * 2] = s16(dx)
					ray[p * 2 + 1] = s16(dy)
				rays[index] = ray
	return result

## Ray tables only (loading stops at a fault; see parse_detailed for the fault record).
static func parse(tdf_text: String) -> Array:
	var detailed := parse_detailed(tdf_text)
	if detailed.fault != null:
		push_error("LosTables: native-undefined LOS.TDF content: %s" % [detailed.fault])
	return detailed.tables

## 0x433500: tables[int16(k - 1)]. Null when that index is outside the table vector (native returns a pointer
## outside the vector, e.g. begin - 16 for k = 0).
static func table_index(k: int) -> int:
	return s16(k - 1)

static func rays_for(tables: Array, k: int):
	var index := table_index(k)
	if index < 0 or index >= tables.size():
		return null
	return tables[index]

extends RefCounted
## Port of the original AI profile interpreter (ai\<profile>.txt plus FBI ai_weight / ai_limit strings).
##
## Native routines (TotalA.exe, verified in the disassembly and by tools/native_ai_profile.py):
##   0x4b7a30 script runner: lines split on '\n' only; a final line without '\n' runs; a trailing '\n' adds no line.
##   0x4b7440 tokenizer: C-locale isspace (0x09-0x0d, 0x20) separates tokens; '#' at a token start ends the line and
##            '#' inside a token ends the token and the line; at most 20 argv entries are kept, but every token's
##            characters (plus a NUL each) still use the 0x7e-byte storage: if a token does not fit completely the
##            tokenizer loops forever writing NULs past the command object (native crash) -> fault here.
##            NUL bytes are ordinary token characters (the runner passes explicit lengths); consumers read C strings.
##   0x4b74f0 %n substitution: the profile/FBI source command object is empty, so it never substitutes here.
##   0x4b7900 dispatch (mask -1 for profiles): case-insensitive (_stricmp 0x4f8a70) lookup in the command table that
##            holds plan/weight/limit (0x406f00) AND every console command (0x4195c4..); unmatched names go to the
##            fallback 0x417890: every type whose unitname wildcard-matches argv[0] (0x4bc370, '?' '*', A-Z folded)
##            is spawned for player atoi(argv[1]); with no match it opens debugdat\<argv0>.txt into a 60-byte stack
##            buffer (argv0 longer than 46 characters overflows it: native crash -> fault here) and would run it.
##   0x406c90 plan: flag = 0; for i in 1..argc-1: argv[1] (not argv[i]) == "any" -> 1; argv[i] names the current
##            difficulty (0 easy, 1 medium, 2 hard) -> 1. The flag is the global 0x501774 (initially 1) and persists
##            across scripts and reloads; only the FBI passes force it back to 1.
##   0x406db0 weight: if flag: set = resolve(argv[1]); w = float32(atof(argv[2])) (0.0 when missing); for every slot
##            whose AI object pointer is non-zero: 0x409dc0.
##   0x406e40 limit: if flag: set = resolve(argv[1]); v = atoi(argv[2]) (0 when missing); for every present slot of
##            type 2: 0x409e90.
##   0x488d30 resolve: unitname (_stricmp binary search over ids 1..count-1) -> {id}, explicit; else the category set
##            (FBI category tokens via sscanf " %s %n", plus ALL; unknown -> empty), not explicit.
##   0x409dc0 for id in set, weight_lock == 0: weight = clamp(low32(fistp64(byte * w)), 0, 100); explicit -> lock.
##            byte(8 bits) * float32(24-bit mantissa) is exact in double, so x87 precision control does not matter.
##   0x409e90 for id in set, limit_lock == 0: limit = v; explicit -> lock.
##   0x409470 defaults: weight 100, limit -1, locks 0 for ids 0..count-1.
##   0x4648e0 load: run the slot-7 profile file, else ai\default.txt; then for each present type-2 slot i:
##            0x409f80(i) and 0x40a040(i). Both set flag = 1 and run the ai_weight string (+0xbe) of every
##            downloadable type with a non-empty string; the first skips types weight-locked in slot i, the second
##            types limit-locked in slot i. ai_limit (+0xfe) is never run (native bug).
##   0x40a100 ReloadAIProfiles: defaults for present type-2 slots only, then 0x4648e0.
##   0x409f20 limit test: id word in 1..count-1; limit -1 -> true; else count < limit.

const SLOTS := 10
const MAX_TOKENS := 20
const TOKEN_STORAGE := 0x7f  # sum of (token length + 1) must not exceed this
const FALLBACK_TOKEN_MAX := 46  # "debugdat\" + token + ".txt" + NUL must fit 60 bytes
const MAX_TYPES := 512  # category and resolve sets are 16 x 32 bits

var type_names: Array = [PackedByteArray()]  # index = type id; 0 reserved
var type_keys: Array = [""]
var downloadable := PackedByteArray([0])
var ai_weight_strings: Array = [PackedByteArray()]
var ai_limit_strings: Array = [PackedByteArray()]
var name_ids := {}
var categories := {}
var console_commands := {}
var difficulty := 0
var players: Array = []  # [present, type, has AI object] per slot
var weight: Array = []
var weight_lock: Array = []
var limit: Array = []
var limit_lock: Array = []
var plan_flag := 1
var files := {}
var profile_name := "ai\\default.txt"
var events: Array = []
var fault = null


static func bytes_of(text: String) -> PackedByteArray:
	# Latin-1: one byte per code point.
	var out := PackedByteArray()
	out.resize(text.length())
	for i in text.length():
		out[i] = text.unicode_at(i) & 0xff
	return out


static func text_of(data: PackedByteArray) -> String:
	var chars := PackedStringArray()
	for b in data:
		chars.append(String.chr(b))
	return "".join(chars)


static func c_string(data: PackedByteArray) -> PackedByteArray:
	var end := data.find(0)
	return data if end < 0 else data.slice(0, end)


static func fold_key(data: PackedByteArray) -> String:
	var lowered := c_string(data).duplicate()
	for i in lowered.size():
		if lowered[i] >= 65 and lowered[i] <= 90:
			lowered[i] += 32
	return lowered.hex_encode()


static func is_space(b: int) -> bool:
	return b == 0x20 or (b >= 0x09 and b <= 0x0d)


static func stricmp_less(a: PackedByteArray, b: PackedByteArray) -> bool:
	var x := c_string(a)
	var y := c_string(b)
	for i in mini(x.size(), y.size()):
		var p: int = x[i] + (32 if x[i] >= 65 and x[i] <= 90 else 0)
		var q: int = y[i] + (32 if y[i] >= 65 and y[i] <= 90 else 0)
		if p != q:
			return p < q
	return x.size() < y.size()


## CRT atoi 0x4e4f70 (atol): whitespace, one sign, decimal digits with 32-bit wraparound.
static func atoi(data: PackedByteArray) -> int:
	var s := c_string(data)
	var i := 0
	while i < s.size() and is_space(s[i]):
		i += 1
	var negative := false
	if i < s.size() and (s[i] == 45 or s[i] == 43):
		negative = s[i] == 45
		i += 1
	var total := 0
	while i < s.size() and s[i] >= 48 and s[i] <= 57:
		total = (total * 10 + s[i] - 48) & 0xffffffff
		i += 1
	if negative:
		total = (-total) & 0xffffffff
	return total - 0x100000000 if total >= 0x80000000 else total


# ---------------------------------------------------------------- CRT atof 0x4e4560
# Bit-exact port of the statically linked MSVC conversion, NOT a correctly rounded decimal parser:
#   0x4e4560 atof: skip ctype-space bytes, then _fltin2 0x4eaf00 -> __strgtold12 0x4f3d10 -> _ld12tod 0x4f3990.
#   0x4f3d10 state machine: at most 25 mantissa digits (extra integer digits only bump the exponent, extra fraction
#            digits are ignored); a 25th digit is dropped after "digit[23] >= 5 -> digit[23] += 1" (tests and
#            increments the 24th digit, which may become 10); trailing zeros stripped; exponent digits capped at
#            5201; |exponent| > 5200 -> infinity / zero; else __mtold12 0x4f8c40 (96-bit integer, normalized into
#            an 80-bit mantissa + exponent word) and __multtenpow12 0x4f9390 (clears the low 16 mantissa bits, then
#            multiplies by 12-byte powers of ten with __ld12mul 0x4f90d0: truncated 5x5-word product, round on the
#            low word).
#   0x4f37c0 _ld12cvt(53, 11): _RoundMan 0x4f3610 looks at bit 53 and increments only when a bit from 55 on is
#            set (0x4f3530 skips bit 54), so ties and "bit 54 only" truncate.
# Power-of-ten tables 0x5116f0 (10^k) / 0x511850 (10^-k), k = (j + 1) * 8^g for entry 7g + j: derived here as the
# 64-bit round-to-nearest mantissa with the low 16 bits of the 80-bit round-to-nearest mantissa (little-endian
# 12-byte values); tools/native_ai_profile.py asserts the derivation equals the executable's tables.
const _POW10_POS := ["000000000000000000a00240", "000000000000000000c80540", "000000000000000000fa0840",
	"0000000000000000409c0c40", "000000000000000050c30f40", "000000000000000024f41240", "000000000000008096981640",
	"0000000000000020bcbe1940", "000000000004bfc91b8e3440", "000000a1edccce1bc2d34e40", "20f09eb5702ba8adc59d6940",
	"d05dfd25e51a8e4f19eb8340", "7196d795430e058d29af9e40", "f9bfa044ed81128f8182b940", "bf3cd5a6cfff491f78c2d340",
	"6fc6e08ce980c947ba93a841", "bc856b5527398df770e07c42", "bcdd8edef99dfbeb7eaa5143", "a1e676e3ccf2292f84812644",
	"281017aaf8ae10e3c5c4fa44", "eba7d4f3f7ebe14a7a95cf45", "65ccc7910ea6aea019e3a346", "0d65170c7581867576c9484d",
	"5842e4a793393b35b8b2ed53", "4da7e55d3dc55d3b8b9e925a", "ff5da6f0a120c054a58c3761", "d1fd8b5a8bd8255d89f9db67",
	"aa95f8f327bfa2c85ddd806e", "4cc99b97208a025260c42575"]
const _POW10_NEG := ["cdcccdccccccccccccccfb3f", "713d0ad7a3703d0ad7a3f83f", "5a643bdf4f8d976e1283f53f",
	"c3d32c6519e25817b7d1f13f", "d00f2384471b47acc5a7ee3f", "40a6b6696caf05bd3786eb3f", "333dbc427ae5d594bfd6e73f",
	"c2fdfdce61841177ccabe43f", "2f4c5be14dc4be9495e6c93f", "92c4533b7544cd14be9aaf3f", "de67ba943945ad1eb1cf943f",
	"2423c6e2bcba3b31618b7a3f", "615559c17eb1537c12bb5f3f", "d7ee2f8d06be928515fb443f", "243fa5e939a527ea7fa82a3f",
	"7daca1e4bc647c46d0dd553e", "637b06cc23547783ff91813d", "91fa3a197a63254331c0ac3c", "2189d138824797b800fdd73b",
	"dc8858081bb1e8e386a6033b", "c684454207b6997537db2e3a", "33711cd223db32ee49905a39", "a687bec057daa582a6a2b532",
	"e268b211a7529f4459b7102c", "2549e42d36344f53aece6b25", "8f5904a4c0dec27dfbe8c61e", "9ee7885a57913cbf50832218",
	"4e4b6562fd838faf06947d11", "e42dde9fced2c804dda6d80a"]
const _M32 := 0xffffffff


static func atof(data: PackedByteArray) -> float:
	var s := c_string(data)
	var i := 0
	while i < s.size() and is_space(s[i]):
		i += 1
	var parsed := strgtold12(s.slice(i))
	if parsed.flags & 4:
		return 0.0
	var bits := ld12_to_double_bits(parsed.ld)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, bits[1])
	out.encode_u32(4, bits[0])
	return out.decode_double(0)


static func _at(s: PackedByteArray, index: int) -> int:
	return s[index] if index < s.size() else 0


static func _digit(c: int) -> bool:
	return c >= 48 and c <= 57


## 0x4f3d10 with multiplier 0 and flag 0. Returns {"ld": 6 little-endian 16-bit words, "flags": int}.
static func strgtold12(s: PackedByteArray) -> Dictionary:
	var p := 0
	while _at(s, p) in [32, 9, 10, 13]:
		p += 1
	var man := PackedInt32Array()
	man.resize(25)
	var manlen := 0
	var exp_adj := 0
	var found_digits := false
	var exp_value := 0
	var exp_negative := false
	var sign := 0
	var state := 0
	while state != 10:
		var c := _at(s, p)
		p += 1
		match state:
			0:
				if c >= 49 and c <= 57:
					state = 3
					p -= 1
				elif c == 46:
					state = 5
				elif c == 43 or c == 45:
					state = 2
					sign = 0x8000 if c == 45 else 0
				elif c == 48:
					state = 1
				else:
					state = 10
			1:
				found_digits = true
				if c >= 49 and c <= 57:
					state = 3
					p -= 1
				elif c == 46:
					state = 4
				elif c == 48:
					state = 1
				elif c in [68, 69, 100, 101]:
					state = 6
				else:
					state = 10  # includes '+'/'-' (state 11 ends the scan when the flag argument is 0)
			2:
				if c >= 49 and c <= 57:
					state = 3
					p -= 1
				elif c == 46:
					state = 5
				elif c == 48:
					state = 1
				else:
					state = 10
			3:
				found_digits = true
				while _digit(c):
					if manlen < 25:
						man[manlen] = c - 48
						manlen += 1
					else:
						exp_adj += 1
					c = _at(s, p)
					p += 1
				if c == 46:
					state = 4
				elif c in [68, 69, 100, 101]:
					state = 6
				else:
					state = 10
			4:
				found_digits = true
				if manlen == 0:
					while c == 48:
						exp_adj -= 1
						c = _at(s, p)
						p += 1
				while _digit(c):
					if manlen < 25:
						man[manlen] = c - 48
						manlen += 1
						exp_adj -= 1
					c = _at(s, p)
					p += 1
				state = 6 if c in [68, 69, 100, 101] else 10
			5:
				if _digit(c):
					state = 4
					p -= 1
				else:
					state = 10
			6:
				if c >= 49 and c <= 57:
					state = 9
					p -= 1
				elif c == 43 or c == 45:
					state = 7
					exp_negative = c == 45
				elif c == 48:
					state = 8
				else:
					state = 10
			7:
				if c >= 49 and c <= 57:
					state = 9
					p -= 1
				elif c == 48:
					state = 8
				else:
					state = 10
			8:
				while c == 48:
					c = _at(s, p)
					p += 1
				if c >= 49 and c <= 57:
					state = 9
					p -= 1
				else:
					state = 10
			9:
				exp_value = 0
				while _digit(c):
					exp_value = exp_value * 10 + c - 48
					if exp_value > 5200:
						exp_value = 5201
						break
					c = _at(s, p)
					p += 1
				state = 10
	var ld := [0, 0, 0, 0, 0, 0]
	var flags := 0
	if not found_digits:
		ld[5] = sign
		return {"ld": ld, "flags": 4}
	if manlen > 24:
		if man[23] >= 5:
			man[23] += 1
		manlen = 24
		exp_adj += 1
	if manlen > 0:
		while man[manlen - 1] == 0:
			manlen -= 1
			exp_adj += 1
		ld = mtold12(man, manlen)
		var exponent := (-exp_value if exp_negative else exp_value) + exp_adj
		if exponent > 5200:
			ld = [0, 0, 0, 0, 0x8000, 0x7fff]
			flags = 2
		elif exponent < -5200:
			ld = [0, 0, 0, 0, 0, 0]
			flags = 1
		else:
			multtenpow12(ld, exponent)
	ld[5] |= sign
	return {"ld": ld, "flags": flags}


static func _words_to_dwords(w: Array) -> Array:
	return [w[0] | (w[1] << 16), w[2] | (w[3] << 16), w[4] | (w[5] << 16)]


static func _dwords_to_words(d: Array) -> Array:
	return [d[0] & 0xffff, d[0] >> 16, d[1] & 0xffff, d[1] >> 16, d[2] & 0xffff, d[2] >> 16]


## 0x4f8be0 / 0x4f8c10 on three 32-bit words (low first).
static func _shl96(d: Array) -> void:
	d[2] = ((d[2] << 1) | (d[1] >> 31)) & _M32
	d[1] = ((d[1] << 1) | (d[0] >> 31)) & _M32
	d[0] = (d[0] << 1) & _M32


static func _shr96(d: Array) -> void:
	d[0] = (d[0] >> 1) | ((d[1] << 31) & _M32)
	d[1] = (d[1] >> 1) | ((d[2] << 31) & _M32)
	d[2] = d[2] >> 1


## 0x4f8b70
static func _add96(d: Array, s: Array) -> void:
	var sum: int = d[0] + s[0]
	d[0] = sum & _M32
	if sum > _M32:
		var med: int = d[1] + 1
		d[1] = med & _M32
		if med > _M32:
			d[2] = (d[2] + 1) & _M32
	sum = d[1] + s[1]
	d[1] = sum & _M32
	if sum > _M32:
		d[2] = (d[2] + 1) & _M32
	d[2] = (d[2] + s[2]) & _M32


## 0x4f8c40
static func mtold12(man: PackedInt32Array, manlen: int) -> Array:
	var d := [0, 0, 0]
	var exponent := 0x404e
	for k in manlen:
		var copy := d.duplicate()
		_shl96(d)
		_shl96(d)
		_add96(d, copy)
		_shl96(d)
		_add96(d, [man[k] & _M32, 0, 0])
	while d[2] == 0:
		exponent -= 16
		d[2] = d[1] >> 16
		d[1] = ((d[1] << 16) & _M32) | (d[0] >> 16)
		d[0] = (d[0] << 16) & _M32
	while (d[2] & 0x8000) == 0:
		_shl96(d)
		exponent -= 1
	var w := _dwords_to_words(d)
	w[5] = exponent & 0xffff
	return w


static func _pow10(negative: bool, index: int) -> Array:
	var data: PackedByteArray = ((_POW10_NEG if negative else _POW10_POS)[index] as String).hex_decode()
	return [data.decode_u16(0), data.decode_u16(2), data.decode_u16(4), data.decode_u16(6), data.decode_u16(8), data.decode_u16(10)]


## 0x4f9390 with mult12 = 0.
static func multtenpow12(ld: Array, power: int) -> void:
	if power == 0:
		return
	var negative := power < 0
	if negative:
		power = -power
	ld[0] = 0
	var group := 0
	while power != 0:
		var last3 := power & 7
		power >>= 3
		if last3 != 0:
			var factor := _pow10(negative, 7 * group + last3 - 1)
			if factor[0] >= 0x8000:
				var low: int = ((factor[1] | (factor[2] << 16)) - 1) & _M32
				factor[1] = low & 0xffff
				factor[2] = low >> 16
			ld12mul(ld, factor)
		group += 1


static func _s16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value >= 0x8000 else value


## 0x4f90d0 (px *= py), both as 6 words.
static func ld12mul(px: Array, py: Array) -> void:
	var sign: int = (px[5] ^ py[5]) & 0x8000
	var ex: int = px[5] & 0x7fff
	var ey: int = py[5] & 0x7fff
	var expsum: int = ex + ey
	if ex >= 0x7fff or ey >= 0x7fff or expsum > 0xbffd:
		_assign(px, [0, 0, 0, 0, 0x8000, 0x7fff | sign])
		return
	if expsum <= 0x3fbf:
		_assign(px, [0, 0, 0, 0, 0, 0])
		return
	if ex == 0:
		expsum += 1
		if (px[5] & 0x7fff) == 0 and px[4] == 0 and px[3] == 0 and px[2] == 0 and px[1] == 0 and px[0] == 0:
			px[5] = 0
			return
	if ey == 0:
		expsum += 1
		if (py[5] & 0x7fff) == 0 and py[4] == 0 and py[3] == 0 and py[2] == 0 and py[1] == 0 and py[0] == 0:
			_assign(px, [0, 0, 0, 0, 0, 0])
			return
	var t := [0, 0, 0, 0, 0, 0, 0]  # 12-byte temp; a carry into word 6 cannot occur (the full product fits)
	for i in 5:
		for m in 5 - i:
			var product: int = px[i + m] * py[4 - m]
			var sum: int = (t[i] | (t[i + 1] << 16)) + product
			t[i] = sum & 0xffff
			t[i + 1] = (sum >> 16) & 0xffff
			if sum > _M32:
				t[i + 2] = (t[i + 2] + 1) & 0xffff
	expsum = (expsum + 0xc002) & 0xffff
	var d := _words_to_dwords(t)
	while _s16(expsum) > 0 and (d[2] & 0x80000000) == 0:
		_shl96(d)
		expsum = (expsum - 1) & 0xffff
	if _s16(expsum) <= 0:
		expsum = (expsum - 1) & 0xffff
		if _s16(expsum) < 0:
			var count := -_s16(expsum)
			expsum = 0
			var sticky := 0
			for k in count:
				if d[0] & 1:
					sticky += 1
				_shr96(d)
			if sticky:
				d[0] |= 1
	var w := _dwords_to_words(d)
	if w[0] > 0x8000 or (d[0] & 0x1ffff) == 0x18000:
		if (w[1] | (w[2] << 16)) == _M32:
			w[1] = 0
			w[2] = 0
			if (w[3] | (w[4] << 16)) == _M32:
				w[3] = 0
				w[4] = 0
				if w[5] == 0xffff:
					w[5] = 0x8000
					expsum = (expsum + 1) & 0xffff
				else:
					w[5] += 1
			else:
				var hi: int = (w[3] | (w[4] << 16)) + 1
				w[3] = hi & 0xffff
				w[4] = hi >> 16
		else:
			var lo: int = (w[1] | (w[2] << 16)) + 1
			w[1] = lo & 0xffff
			w[2] = lo >> 16
	if expsum >= 0x7fff:
		_assign(px, [0, 0, 0, 0, 0x8000, 0x7fff | sign])
	else:
		_assign(px, [w[1], w[2], w[3], w[4], w[5], expsum | sign])


static func _assign(target: Array, values: Array) -> void:
	for k in values.size():
		target[k] = values[k]


## 0x4f3530: 1 when every mantissa bit from position nbit + 1 on (MSB = position 0) is zero; bit nbit is not tested.
static func _tail_is_zero(man: Array, nbit: int) -> bool:
	var index := nbit >> 5
	var mask := ~(_M32 << (31 - (nbit & 31))) & _M32
	if man[index] & mask:
		return false
	for k in range(index + 1, 3):
		if man[k] != 0:
			return false
	return true


## 0x4f35a0: add 1 at position nbit; returns the carry out of word 0.
static func _increment_man(man: Array, nbit: int) -> int:
	var index := nbit >> 5
	var sum: int = man[index] + (1 << (31 - (nbit & 31)))
	man[index] = sum & _M32
	var carry := 1 if sum > _M32 else 0
	index -= 1
	while index >= 0 and carry:
		sum = man[index] + 1
		man[index] = sum & _M32
		carry = 1 if sum > _M32 else 0
		index -= 1
	return carry


## 0x4f3610
static func _round_man(man: Array, precision: int) -> int:
	var index := precision >> 5
	var shift := 31 - (precision & 31)
	var result := 0
	if man[index] & (1 << shift):
		if not _tail_is_zero(man, precision + 1):
			result = _increment_man(man, precision - 1)
	man[index] = man[index] & ((_M32 << shift) & _M32)
	for k in range(index + 1, 3):
		man[k] = 0
	return result


## 0x4f3700
static func _shr_man(man: Array, count: int) -> void:
	var words := count >> 5
	var bits := count & 31
	var carry := 0
	for k in 3:
		var value: int = man[k]
		var low := value & ((1 << bits) - 1)
		man[k] = (value >> bits) | carry
		carry = (low << (32 - bits)) & _M32 if bits != 0 else 0
	for k in range(2, -1, -1):
		man[k] = man[k - words] if k >= words else 0


## 0x4f37c0 with the double format 0x510ce0 (max 0x400, min -0x3ff, precision 53, exponent width 11, bias 0x3ff).
## Returns [high 32 bits, low 32 bits].
static func ld12_to_double_bits(ld: Array) -> Array:
	var exponent: int = (ld[5] & 0x7fff) - 0x3fff
	var sign: int = ld[5] & 0x8000
	var man := [ld[3] | (ld[4] << 16), ld[1] | (ld[2] << 16), (ld[0] << 16) & _M32]
	var biased := 0
	if exponent == -0x3fff:
		man = [0, 0, 0]
	else:
		var saved := man.duplicate()
		if _round_man(man, 53):
			exponent += 1
		if exponent < -0x3ff - 53:
			man = [0, 0, 0]
		elif exponent <= -0x3ff:
			man = saved
			_shr_man(man, -0x3ff - exponent)
			_round_man(man, 53)
			_shr_man(man, 12)
		elif exponent >= 0x400:
			man = [0x80000000, 0, 0]
			_shr_man(man, 11)
			biased = 0x7ff
		else:
			biased = exponent + 0x3ff
			man[0] &= 0x7fffffff
			_shr_man(man, 11)
	var high: int = ((biased << 20) & _M32) | (0x80000000 if sign else 0) | man[0]
	return [high, man[1]]


static func to_float32(value: float) -> float:
	return PackedFloat32Array([value])[0]


## x87 fistp qword truncation (0x4e43a0 with RC=chop) followed by the low 32 bits in eax.
static func ftol_low32(value: float) -> int:
	if is_nan(value) or absf(value) >= 9223372036854775808.0:
		return 0
	var whole := int(value)
	whole &= 0xffffffff
	return whole - 0x100000000 if whole >= 0x80000000 else whole


static func weight_result(old_byte: int, w32: float) -> int:
	var product := float(old_byte) * w32  # 0 * inf is NaN, like the x87 invalid operation
	var eax := ftol_low32(product)
	var positive := eax if eax > 0 else 0
	return positive if positive < 100 else 100


## 0x4bc370(string, pattern): NFA wildcard match with A-Z upper-case folding, '?' and '*', at most 100 states.
static func wildcard_match(string: PackedByteArray, pattern: PackedByteArray) -> bool:
	var s := c_string(string)
	var p := c_string(pattern).duplicate()  # packed arrays are passed by reference
	p.append(0)
	p.append(0)
	var states := PackedInt32Array([0])
	for index in s.size():
		var c := _upper(s[index])
		var i := 0
		while i < states.size():
			var at := states[i]
			var pc := _upper(p[at])
			if pc == 63 or pc == c:
				states[i] = at + 1
			elif pc == 42:
				if states.size() < 100:
					states.append(at + 1)
			else:
				var last := states.size() - 1
				if last == 0:
					return false
				states[i] = states[last]
				states.resize(last)
				i -= 1
			i += 1
	for at in states:
		if p[at] == 0:
			return true
		if p[at] == 42 and p[at + 1] == 0:
			return true
	return false


static func _upper(b: int) -> int:
	return b - 32 if b >= 97 and b <= 122 else b


## 0x4b7440 on one line. Returns {"argv": Array[PackedByteArray], "overflow": bool}.
static func tokenize(line: PackedByteArray) -> Dictionary:
	var argv: Array = []
	var used := 0
	var i := 0
	var n := line.size()
	while true:
		while i < n and is_space(line[i]):
			i += 1
		if i == n or line[i] == 35:
			break
		var start := i
		while i < n and not is_space(line[i]) and line[i] != 35:
			i += 1
		var length := i - start
		if used + length + 1 > TOKEN_STORAGE:
			return {"argv": argv, "overflow": true}
		used += length + 1
		if argv.size() < MAX_TOKENS:
			argv.append(line.slice(start, i))
	return {"argv": argv, "overflow": false}


# ---------------------------------------------------------------- setup

## units: Array of {unitname, category, ai_weight, ai_limit, downloadable(int)} in any order.
func setup(units: Array, console_names: Array = []) -> void:
	var entries: Array = []
	for unit: Dictionary in units:
		var name := bytes_of(str(unit.get("unitname", "")))
		entries.append({"name": name.slice(0, mini(name.size(), 31)), "unit": unit})
	entries.sort_custom(func(a, b): return stricmp_less(a.name, b.name))
	type_names = [PackedByteArray()]
	type_keys = [""]
	downloadable = PackedByteArray([0])
	ai_weight_strings = [PackedByteArray()]
	ai_limit_strings = [PackedByteArray()]
	name_ids = {}
	categories = {}
	for entry: Dictionary in entries:
		var type_id := type_names.size()
		type_names.append(entry.name)
		var key := fold_key(entry.name)
		type_keys.append(key)
		if not name_ids.has(key):
			name_ids[key] = type_id
		downloadable.append(int(entry.unit.get("downloadable", 0)) & 1)
		ai_weight_strings.append(_field(entry.unit.get("ai_weight", ""), 63))
		ai_limit_strings.append(_field(entry.unit.get("ai_limit", ""), 63))
		# 0x488e70: sscanf(" %s %n") over the category string, then ALL
		var category := _field(entry.unit.get("category", ""), 99)
		var i := 0
		while true:
			while i < category.size() and is_space(category[i]):
				i += 1
			if i >= category.size():
				break
			var start := i
			while i < category.size() and not is_space(category[i]):
				i += 1
			_category(fold_key(category.slice(start, i)))[type_id] = true
		_category(fold_key(bytes_of("ALL")))[type_id] = true
	console_commands = {}
	for name in console_names:
		console_commands[fold_key(bytes_of(str(name)))] = str(name)
	set_players([])


func _field(value, size: int) -> PackedByteArray:
	var data := c_string(bytes_of(str(value)))
	return data.slice(0, mini(data.size(), size))


func _category(key: String) -> Dictionary:
	if not categories.has(key):
		categories[key] = {}
	return categories[key]


func type_count() -> int:
	return type_names.size()


## list of [present, type, has_ai_object]; missing slots are empty.
func set_players(list: Array) -> void:
	players = []
	for slot in SLOTS:
		var entry: Array = list[slot] if slot < list.size() else [0, 0, 0]
		players.append([int(entry[0]) != 0, int(entry[1]), int(entry[2]) != 0])
	if weight.size() != SLOTS or (weight[0] as PackedByteArray).size() != type_count():
		weight = []
		weight_lock = []
		limit = []
		limit_lock = []
		for slot in SLOTS:
			weight.append(PackedByteArray())
			weight_lock.append(PackedByteArray())
			limit.append(PackedInt32Array())
			limit_lock.append(PackedByteArray())
			reset_context(slot)


## 0x409470 (the per-type parts the profile uses).
func reset_context(slot: int) -> void:
	var count := type_count()
	var w := PackedByteArray()
	w.resize(count)
	w.fill(100)
	var wl := PackedByteArray()
	wl.resize(count)
	var l := PackedInt32Array()
	l.resize(count)
	l.fill(-1)
	var ll := PackedByteArray()
	ll.resize(count)
	weight[slot] = w
	weight_lock[slot] = wl
	limit[slot] = l
	limit_lock[slot] = ll


# ---------------------------------------------------------------- interpreter

## 0x4b7a30 with an empty substitution source and mask -1. Returns false after a native-crash fault.
func run_script(text: PackedByteArray) -> bool:
	var start := 0
	var remaining := text.size()
	while remaining > 0:
		var end := text.find(10, start)
		if end < 0 or end >= start + remaining:
			end = start + remaining
		var line := text.slice(start, end)
		var tokens := tokenize(line)
		if tokens.overflow:
			fault = {"kind": "token_storage_overflow", "line": text_of(line)}
			return false
		if not dispatch(tokens.argv):
			return false
		remaining -= end - start + 1
		start = end + 1
	return true


func dispatch(argv: Array) -> bool:
	if argv.is_empty():
		return true
	var key := fold_key(argv[0])
	match key:
		"706c616e":  # plan
			_plan(argv)
		"776569676874":  # weight
			_weight(argv)
		"6c696d6974":  # limit
			_limit(argv)
		_:
			if console_commands.has(key):
				var names := []
				for token in argv:
					names.append(text_of(c_string(token)))
				events.append(["console", console_commands[key], names])
			else:
				return _fallback(argv)
	return true


func _arg(argv: Array, index: int) -> PackedByteArray:
	return c_string(argv[index]) if index < argv.size() else PackedByteArray()


func _plan(argv: Array) -> void:
	plan_flag = 0
	var names := {0: "easy", 1: "medium", 2: "hard"}
	for i in range(1, argv.size()):
		if fold_key(argv[1]) == fold_key(bytes_of("any")):
			plan_flag = 1
		if names.has(difficulty) and fold_key(argv[i]) == fold_key(bytes_of(names[difficulty])):
			plan_flag = 1


## 0x488d30: returns {"ids": Array, "explicit": bool}.
func resolve(name: PackedByteArray) -> Dictionary:
	var key := fold_key(name)
	if name_ids.has(key):
		return {"ids": [name_ids[key]], "explicit": true}
	var set: Dictionary = _category(key)
	return {"ids": set.keys(), "explicit": false}


func _weight(argv: Array) -> void:
	if plan_flag == 0:
		return
	var target := resolve(_arg(argv, 1))
	var w := to_float32(atof(argv[2])) if argv.size() > 2 else 0.0
	for slot in SLOTS:
		if players[slot][2]:
			apply_weight(slot, target, w)


func _limit(argv: Array) -> void:
	if plan_flag == 0:
		return
	var target := resolve(_arg(argv, 1))
	var value := atoi(argv[2]) if argv.size() > 2 else 0
	for slot in SLOTS:
		if players[slot][0] and players[slot][1] == 2:
			apply_limit(slot, target, value)


## 0x409dc0
func apply_weight(slot: int, target: Dictionary, w32: float) -> void:
	var ids: Array = target.ids.duplicate()
	ids.sort()
	var weights: PackedByteArray = weight[slot]
	var locks: PackedByteArray = weight_lock[slot]
	for type_id in ids:
		if type_id < 1 or type_id >= type_count() or locks[type_id] != 0:
			continue
		weights[type_id] = weight_result(weights[type_id], w32)
		if target.explicit:
			locks[type_id] = 1


## 0x409e90
func apply_limit(slot: int, target: Dictionary, value: int) -> void:
	var limits: PackedInt32Array = limit[slot]
	var locks: PackedByteArray = limit_lock[slot]
	for type_id in target.ids:
		if type_id < 1 or type_id >= type_count() or locks[type_id] != 0:
			continue
		limits[type_id] = value
		if target.explicit:
			locks[type_id] = 1


## 0x417890
func _fallback(argv: Array) -> bool:
	var command := c_string(argv[0])
	var owner := atoi(argv[1]) if argv.size() > 1 else 0
	var matched := 0
	for type_id in range(1, type_count()):
		if wildcard_match(type_names[type_id], command):
			events.append(["spawn", owner, type_id])
			matched += 1
	if matched == 0:
		# the open 0x4bb5b0 still runs with the overflowed path; the crash comes when 0x417890 returns through the
		# overwritten return address (what a real process does next is not established; the port stops)
		events.append(["script_file", "debugdat\\" + text_of(command) + ".txt"])
		if command.size() > FALLBACK_TOKEN_MAX:
			fault = {"kind": "fallback_path_overflow", "token": text_of(command)}
			return false
	return true


## 0x4648e0. Returns false after a fault.
func load_profile() -> bool:
	if type_count() > MAX_TYPES:
		# not native evidence: ids >= 512 would write past the 512-bit set in 0x406db0 (untested); the port refuses
		fault = {"kind": "unmodelled_type_set_overflow"}
		return false
	var text = _load_file(profile_name)
	if text == null:
		text = _load_file("ai\\default.txt")
	if text != null and not run_script(text):
		return false
	for slot in SLOTS:
		if players[slot][0] and players[slot][1] == 2:
			if not fbi_pass(slot, weight_lock) or not fbi_pass(slot, limit_lock):
				return false
	return true


func _load_file(name: String):
	var found := files.has(name.to_lower())
	events.append(["load_file", name, found])
	return files[name.to_lower()] if found else null


## 0x409f80 (locks = weight_lock) and 0x40a040 (locks = limit_lock): both run ai_weight.
func fbi_pass(slot: int, locks: Array) -> bool:
	plan_flag = 1
	var type_id := 1
	while type_id < type_count():
		if downloadable[type_id] and (locks[slot] as PackedByteArray)[type_id] != 1 and not (ai_weight_strings[type_id] as PackedByteArray).is_empty():
			if not run_script(ai_weight_strings[type_id]):
				return false
		type_id += 1
	return true


## 0x40a100
func reload_profiles() -> bool:
	for slot in SLOTS:
		if players[slot][0] and players[slot][1] == 2:
			reset_context(slot)
	return load_profile()


## 0x409f20 (through 0x406ee0).
func limit_allows(slot: int, type_id: int, count: int) -> bool:
	if (slot & 0xff) >= SLOTS:
		# not native evidence: 0x409f20 would read a context pointer past 0x5119c0 + 9 * 4 (unmodelled)
		fault = {"kind": "unmodelled_limit_slot", "slot": slot & 0xff}
		return false
	var word := type_id & 0xffff
	if word < 1 or word >= type_count():
		return false
	var value: int = (limit[slot & 0xff] as PackedInt32Array)[word]
	return value == -1 or count < value


func weight_of(slot: int, type_id: int) -> int:
	return (weight[slot] as PackedByteArray)[type_id]

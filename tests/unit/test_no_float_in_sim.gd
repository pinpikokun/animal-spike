extends "res://tests/test_case.gd"

# シミュレーション層のfloat禁止を静的スキャンで強制する。
# SyncTest(同一プロセス2回実行)はfloat混入を構造的に検出できないため、
# ソーステキストの検査で塞ぐ。正当な例外行は「float-ok」コメントを付ける

const SIM_DIR := "res://src/sim"
const BANNED := [
	"float", "randf", "randi",
	"lerp", "sin(", "cos(", "tan(", "sqrt(", "exp(",
	"floor(", "ceil(", "round(",
	"pow(", "atan2(", "fmod(", "smoothstep(", "ease(", "deg_to_rad(",
	# float返しの組込み。整数引数でもTYPE_FLOATを返すので網に入れる
	"clampf(", "minf(", "maxf(", "absf(", "snappedf(", "wrapf(",
	"fposmod(", "pingpong(", "remap(", "move_toward(",
]

var _string_re: RegEx
var _decimal_re: RegEx
var _const_re: RegEx
var _log_re: RegEx
var _float_vector_re: RegEx

func test_sim_sources_are_float_free() -> void:
	_string_re = RegEx.new()
	_string_re.compile("\"[^\"]*\"")
	# 小数リテラル(0.5)・指数表記(1e3)。識別子の一部(x1e3等)は誤検出しない
	_decimal_re = RegEx.new()
	_decimal_re.compile("(?<![A-Za-z0-9_.])(\\d+\\.\\d+|\\d+[eE][-+]?\\d+|\\.\\d+)")
	# float定数。containsだと他の識別子に誤爆するため単語境界で判定
	_const_re = RegEx.new()
	_const_re.compile("\\b(PI|TAU|INF|NAN)\\b")
	# 自然対数log(。debug_log(等は_が単語文字なので\bで弾かれず誤爆しない
	_log_re = RegEx.new()
	_log_re.compile("\\blog\\(")
	# Vector2i/Vector3iは整数型なので、部分一致で拒否しない。
	_float_vector_re = RegEx.new()
	_float_vector_re.compile("\\b(Vector2|Vector3)\\b")
	var scanned := _scan_dir(SIM_DIR)
	check(scanned >= 4, "simファイルの走査数=" + str(scanned))

func _scan_dir(dir_path: String) -> int:
	# サブディレクトリも再帰走査する(将来src/sim/ai/等を切っても網に入る)
	var dir := DirAccess.open(dir_path)
	check(dir != null, dir_path + "が開ける")
	if dir == null:
		return 0
	var scanned := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				scanned += _scan_dir(dir_path + "/" + f)
		elif f.ends_with(".gd"):
			scanned += 1
			_scan_file(dir_path + "/" + f)
		f = dir.get_next()
	return scanned

func _scan_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		# 文字列リテラルを先に潰す(文字列内の#でコメント誤判定しない)
		var masked: String = _string_re.sub(line, "\"\"", true)
		var hash_pos := masked.find("#")
		var code := masked if hash_pos < 0 else masked.substr(0, hash_pos)
		var comment := "" if hash_pos < 0 else masked.substr(hash_pos)
		if comment.contains("float-ok"):
			continue
		for token in BANNED:
			if code.contains(token):
				check(false, "%s:%d 禁止トークン'%s': %s" % [path, i + 1, token, line.strip_edges()])
		if _decimal_re.search(code) != null:
			check(false, "%s:%d 小数/指数リテラル: %s" % [path, i + 1, line.strip_edges()])
		if _const_re.search(code) != null:
			check(false, "%s:%d float定数(PI/TAU/INF/NAN): %s" % [path, i + 1, line.strip_edges()])
		if _log_re.search(code) != null:
			check(false, "%s:%d float返しlog(: %s" % [path, i + 1, line.strip_edges()])
		if _float_vector_re.search(code) != null:
			check(false, "%s:%d floatベクトル型: %s" % [path, i + 1, line.strip_edges()])

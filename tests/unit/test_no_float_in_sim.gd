extends "res://tests/test_case.gd"

# シミュレーション層のfloat禁止を静的スキャンで強制する。
# SyncTest(同一プロセス2回実行)はfloat混入を構造的に検出できないため、
# ソーステキストの検査で塞ぐ。正当な例外行は「float-ok」コメントを付ける

const SIM_DIR := "res://src/sim"
const BANNED := [
	"float", "randf", "randi", "Vector2", "Vector3",
	"lerp", "sin(", "cos(", "tan(", "sqrt(", "exp(",
	"floor(", "ceil(", "round(",
]

func test_sim_sources_are_float_free() -> void:
	var dir := DirAccess.open(SIM_DIR)
	check(dir != null, "src/simが開ける")
	if dir == null:
		return
	var scanned := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			scanned += 1
			_scan_file(SIM_DIR + "/" + f)
		f = dir.get_next()
	check(scanned >= 4, "simファイルの走査数=" + str(scanned))

func _scan_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var hash_pos := line.find("#")
		var code := line if hash_pos < 0 else line.substr(0, hash_pos)
		var comment := "" if hash_pos < 0 else line.substr(hash_pos)
		if comment.contains("float-ok"):
			continue
		for token in BANNED:
			if code.contains(token):
				check(false, "%s:%d 禁止トークン'%s': %s" % [path, i + 1, token, line.strip_edges()])

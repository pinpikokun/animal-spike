# ヘッドレステストランナー
# 使い方: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const TEST_DIR := "res://tests/unit"

func _init() -> void:
	var failed := 0
	var total := 0
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("テストディレクトリが開けない: " + TEST_DIR)
		quit(1)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	for name in names:
		var script: GDScript = load(TEST_DIR + "/" + name)
		var t: Object = script.new()
		for m in script.get_script_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_"):
				continue
			total += 1
			t.failures.clear()
			t.call(method)
			if t.failures.is_empty():
				print("PASS  %s.%s" % [name, method])
			else:
				failed += 1
				print("FAIL  %s.%s" % [name, method])
				for msg in t.failures:
					print("      " + msg)
	print("----")
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)

extends "res://tests/test_case.gd"

# 表示層スクリプトのパース健全性。ユニットテストはsim層しか実行しないため、
# 表示層のパースエラー(型推論不能など)を全gdのloadで早期検出する。
# load()はパース失敗でも非nullのGDScriptを返すため、`!= null`では検出できない。
# can_instantiate()でインスタンス化可能なパース状態まで確認する。
# root.gdも対象に含める(#106 CONTRACT-106-012)。除外を戻さない。

func test_display_scripts_parse() -> void:
	var dir := DirAccess.open("res://src/display")
	check(dir != null, "src/displayが開ける")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var res := load("res://src/display/" + f)
		check(res is GDScript and res.can_instantiate(), "パース成功: " + f)

# 注: src/netはSyncManager(rollbackアドオンのautoload)前提のためヘッドレスの
# ユニットテストではloadできない。net層のパース検証はscripts/run_net_test.ps1が担う

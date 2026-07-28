extends "res://tests/test_case.gd"

# 表示層スクリプトのパース健全性。ユニットテストはsim層しか実行しないため、
# 表示層のパースエラー(型推論不能など)がテスト全緑のままゲームだけ壊す事故が
# 実際に起きた(game_view.gdの`var on :=`)。全gdをloadして早期検出する
# root.gdもヘッドレスのテスト用SceneTreeでload成功を実測済み。除外しない。

func test_display_scripts_parse() -> void:
	var dir := DirAccess.open("res://src/display")
	check(dir != null, "src/displayが開ける")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var res := load("res://src/display/" + f)
		check(res != null, "パース成功: " + f)

# 注: src/netはSyncManager(rollbackアドオンのautoload)前提のためヘッドレスの
# ユニットテストではloadできない。net層のパース検証はscripts/run_net_test.ps1が担う

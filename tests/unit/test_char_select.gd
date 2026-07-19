extends "res://tests/test_case.gd"

const CharSelect := preload("res://src/display/char_select.gd")

func test_stats_label_lists_all_player_facing_abilities() -> void:
	var view = CharSelect.new()
	view._ready()
	var shown: String = view._stats_label.text
	var names := ["トス", "アタック", "ジャンプ", "ウェイト", "移動", "ブレーキ",
		"ガード", "ジャスト判定", "ジャスト威力", "勢い吸収", "トス安定",
		"レシーブ安定", "アタック安定", "ブロック安定", "固有技"]
	for name in names:
		check(shown.contains(name), "%sをキャラ選択画面へ表示する" % name)
	view.free()

func test_stats_label_shows_levels_as_numbers() -> void:
	var view = CharSelect.new()
	view._ready()
	var shown: String = view._stats_label.text
	check(shown.contains("トス 2"), "パンダのトスLv2を数値表示する")
	check(shown.contains("アタック 8"), "パンダのアタックLv8を数値表示する")
	check(shown.contains("ジャンプ 3"), "パンダのジャンプLv3を数値表示する")
	check(shown.contains("ウェイト 8"), "パンダのウェイトLv8を数値表示する")
	view.free()

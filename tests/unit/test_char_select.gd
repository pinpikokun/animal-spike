extends "res://tests/test_case.gd"

const CharSelect := preload("res://src/display/char_select.gd")
const Chars := preload("res://src/sim/chars.gd")

func test_stats_label_lists_five_ranked_abilities() -> void:
	var shown := CharSelect.stats_text(Chars.CHAR_PANDA)
	var names := ["パワー C", "ジャンプ C", "スピード C", "ブレーキ C", "ガード C"]
	for name in names:
		check(shown.contains(name), "%sをキャラ選択画面へ表示する" % name)

func test_stats_label_lists_assigned_trait_names() -> void:
	var panda := CharSelect.stats_text(Chars.CHAR_PANDA)
	check(panda.contains("付与能力: トス下手 / レシーブ下手 / むらっけ"),
		"パンダの付与能力を列挙する")
	var mario := CharSelect.stats_text(Chars.CHAR_MARIO)
	check(mario.contains("付与能力: トス上手 / レシーブ上手"),
		"マリオの付与能力を列挙する")
	var fox := CharSelect.stats_text(Chars.CHAR_FOX)
	check(fox.contains("付与能力: なし"), "付与能力なしを明示する")

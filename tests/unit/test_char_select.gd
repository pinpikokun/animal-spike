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

func test_original_character_rank_labels_are_displayed() -> void:
	var tome := CharSelect.stats_text(Chars.CHAR_TOME)
	check(tome.contains("ジャンプ A"), "トメのジャンプAを表示")
	check(tome.contains("スピード E"), "トメのスピードEを表示")
	var ume := CharSelect.stats_text(Chars.CHAR_UME)
	check(ume.contains("ジャンプ E"), "ウメのジャンプEを表示")
	check(ume.contains("スピード A"), "ウメのスピードAを表示")
	check(ume.contains("ガード A"), "ウメのガードAを表示")
	var carby := CharSelect.stats_text(Chars.CHAR_CARBY)
	check(carby.contains("ジャンプ B"), "カービィのジャンプBを表示")
	check(carby.contains("ガード D"), "カービィのガードDを表示")
	check(carby.contains("付与能力: なし"), "原作キャラの付与能力なしを表示")

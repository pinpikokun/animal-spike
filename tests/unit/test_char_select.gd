extends "res://tests/test_case.gd"

const CharSelect := preload("res://src/display/char_select.gd")
const Chars := preload("res://src/sim/chars.gd")
const ScoreUI := preload("res://src/display/score_ui.gd")

func test_every_selectable_character_has_canonical_face() -> void:
	for cid in Chars.SELECTABLE:
		check(ScoreUI.FACES.has(cid), "選択可能キャラの顔をScoreUI.FACESへ登録: %d" % cid)

func test_original_faces_use_back_cells_square_regions() -> void:
	var originals := [Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO,
		Chars.CHAR_UME, Chars.CHAR_CARBY, Chars.CHAR_DUO, Chars.CHAR_SEC1,
		Chars.CHAR_SEC2]
	for k in originals.size():
		var face: Dictionary = ScoreUI.FACES[originals[k]]
		check_eq(face["tex"], "res://assets/reference/vb2211/back_cells.png",
			"原作顔はback_cellsを正本にする")
		check_eq(face["region"], Rect2(384 + 64 * k, 192, 64, 64),
			"原作顔セル位置: %d" % k)
		check_eq(CharSelect.portrait_rect(face), Rect2(12.0, 0.0, 64.0, 64.0),
			"64x64原作顔を等倍でセル中央へ配置")

func test_every_portrait_fits_inside_cell_face_area() -> void:
	for cid in Chars.SELECTABLE:
		var rect: Rect2 = CharSelect.portrait_rect(ScoreUI.FACES[cid])
		check(rect.position.x >= 0.0, "portrait左端がセル内: %d" % cid)
		check(rect.end.x <= CharSelect.CELL_W - 12.0, "portrait右端がセル内: %d" % cid)
		check(rect.position.y >= 0.0 and rect.end.y <= 64.0,
			"portraitを名前ラベルより上へ収める: %d" % cid)

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

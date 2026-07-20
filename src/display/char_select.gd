# キャラ選択画面(起動時)。自チーム2体(手前→奥の順)を選ぶ。敵チームはランダム。
# Escでスキップ=既定ロスター。表示層のみでsimには触らない
extends Control

signal done(roster: Array)

const Chars := preload("res://src/sim/chars.gd")
const ScoreUI := preload("res://src/display/score_ui.gd")

const PORTRAIT_SCALE := 4.0
const ORIGINAL_PORTRAIT_SCALE := 2.0
const CELL_W := 100.0
const COLUMNS := 6
const BASE_W := 640.0
const BASE_H := 360.0

var _cursor := 0
var _picks: Array[int] = []  # 選んだchar_id(0=手前, 1=奥)
var _stage_label: Label
var _stats_label: Label
var _pick_labels: Array[Label] = []
var _cursor_rect: ColorRect
var _cells: Array[Control] = []

const ORIGINAL_SHEETS := {
	Chars.CHAR_TOME: "res://assets/reference/vb2211/tome_sheet.png",
	Chars.CHAR_HITO: "res://assets/reference/vb2211/hito_sheet.png",
	Chars.CHAR_PIYO: "res://assets/reference/vb2211/piyo_sheet.png",
	Chars.CHAR_UME: "res://assets/reference/vb2211/ume_sheet.png",
	Chars.CHAR_CARBY: "res://assets/reference/vb2211/carby_sheet.png",
	Chars.CHAR_DUO: "res://assets/reference/vb2211/duo_sheet.png",
	Chars.CHAR_SEC1: "res://assets/reference/vb2211/sec1_sheet.png",
	Chars.CHAR_SEC2: "res://assets/reference/vb2211/sec2_sheet.png",
}

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.14)
	bg.size = Vector2(BASE_W, BASE_H)
	add_child(bg)

	var title := Label.new()
	title.text = "CHARACTER SELECT"
	title.position = Vector2(0, 4)
	title.size = Vector2(BASE_W, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	_stage_label = Label.new()
	_stage_label.position = Vector2(0, 38)
	_stage_label.size = Vector2(BASE_W, 22)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_stage_label)

	var n := Chars.SELECTABLE.size()
	var columns: int = mini(n, COLUMNS)
	var x0 := (BASE_W - CELL_W * columns) * 0.5
	_cursor_rect = ColorRect.new()
	_cursor_rect.color = Color(1.0, 0.85, 0.2, 0.35)
	_cursor_rect.size = Vector2(CELL_W - 12, 84)
	add_child(_cursor_rect)
	for i in n:
		var cid: int = Chars.SELECTABLE[i]
		var cell := Control.new()
		cell.position = Vector2(x0 + (i % COLUMNS) * CELL_W,
			70 + (i / COLUMNS) * 86)
		add_child(cell)
		_cells.append(cell)
		var face: Dictionary
		if ScoreUI.FACES.has(cid):
			face = ScoreUI.FACES[cid]
		else:
			face = {"tex": ORIGINAL_SHEETS[cid], "region": Rect2(0, 0, 32, 32)}
		var at := AtlasTexture.new()
		at.atlas = load(face["tex"])
		at.region = face["region"]
		var tr := TextureRect.new()
		tr.texture = at
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var portrait_scale: float = ORIGINAL_PORTRAIT_SCALE \
			if ORIGINAL_SHEETS.has(cid) else PORTRAIT_SCALE
		tr.scale = Vector2(portrait_scale, portrait_scale)
		tr.position = Vector2((CELL_W - 12 - at.region.size.x * portrait_scale) * 0.5, 0)
		cell.add_child(tr)
		var name_l := Label.new()
		name_l.text = Chars.NAMES.get(cid, "?")
		name_l.position = Vector2(0, 64)
		name_l.size = Vector2(CELL_W - 12, 20)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_l)

# カーソル中キャラの能力表示(A-E基礎能力+付与能力+固有技)
	_stats_label = Label.new()
	_stats_label.position = Vector2(0, 240)
	_stats_label.size = Vector2(BASE_W, 60)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 11)
	add_child(_stats_label)

	for s in 2:
		var l := Label.new()
		l.position = Vector2(0, 300 + s * 15)
		l.size = Vector2(BASE_W, 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 11)
		add_child(l)
		_pick_labels.append(l)

	var help := Label.new()
	help.text = "←→:選ぶ  スペース/Enter:決定  Backspace:やり直し  Esc:スキップ(既定編成)"
	help.position = Vector2(0, 336)
	help.size = Vector2(BASE_W, 20)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(0.7, 0.7, 0.8)
	add_child(help)
	_refresh()

const ABILITY_NAMES := {
	1: "帽子投げ", 2: "ヒップアタック", 4: "壁張り付き", 8: "ダッシュ",
}

static func stats_text(cid: int) -> String:
	var lines: Array[String] = []
	lines.append("パワー %s   ジャンプ %s   スピード %s" % [
		Chars.Profile.rank_name(Chars.rank(cid, Chars.Profile.ABILITY_POWER)),
		Chars.Profile.rank_name(Chars.rank(cid, Chars.Profile.ABILITY_JUMP)),
		Chars.Profile.rank_name(Chars.rank(cid, Chars.Profile.ABILITY_SPEED))])
	lines.append("ブレーキ %s   ガード %s   ウェイト 標準" % [
		Chars.Profile.rank_name(Chars.rank(cid, Chars.Profile.ABILITY_BRAKE)),
		Chars.Profile.rank_name(Chars.rank(cid, Chars.Profile.ABILITY_GUARD))])
	var trait_names := Chars.Profile.trait_names(cid)
	lines.append("付与能力: " + (" / ".join(trait_names) if trait_names.size() > 0 else "なし"))
	var moves: Array[String] = []
	for bit in ABILITY_NAMES:
		if Chars.has_ability(cid, bit):
			moves.append(ABILITY_NAMES[bit])
	lines.append("固有技: " + (" / ".join(moves) if moves.size() > 0 else "なし"))
	return "\n".join(lines)

func _refresh() -> void:
	_stage_label.text = "手前(操作キャラ)を選べ!" if _picks.size() == 0 else "奥(相方)を選べ!"
	_cursor_rect.position = _cells[_cursor].position + Vector2(0, 4)
	var cid: int = Chars.SELECTABLE[_cursor]
	_stats_label.text = stats_text(cid)
	for s in 2:
		if s < _picks.size():
			var role := "手前" if s == 0 else "奥"
			_pick_labels[s].text = "%s: %s" % [role, Chars.NAMES.get(_picks[s], "?")]
		else:
			_pick_labels[s].text = ""

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			_cursor = (_cursor - 1 + _cells.size()) % _cells.size()
			_refresh()
		KEY_RIGHT, KEY_D:
			_cursor = (_cursor + 1) % _cells.size()
			_refresh()
		KEY_SPACE, KEY_ENTER:
			_picks.append(Chars.SELECTABLE[_cursor])
			if _picks.size() >= 2:
				_finish()
			else:
				_refresh()
		KEY_BACKSPACE:
			if _picks.size() > 0:
				_picks.pop_back()
				_refresh()
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			done.emit(Chars.ROSTER.duplicate())

func _finish() -> void:
	# 敵チーム2体はランダム(操作感確認が目的なので毎回顔ぶれが変わってよい)
	var pool: Array[int] = Chars.SELECTABLE.duplicate()
	var roster: Array = [_picks[0], _picks[1],
		pool[randi() % pool.size()], pool[randi() % pool.size()]]
	done.emit(roster)

# スコア・フェーズ・勝敗の文字表示+画面下端の顔HUD(耐久/ドライブゲージ)。
# 表示層。sim_stateを読むだけ
extends CanvasLayer

const SimState := preload("res://src/sim/sim_state.gd")
const Chars := preload("res://src/sim/chars.gd")

# 顔アイコンの唯一の正本。HUDとキャラ選択が同じchar_id定義を参照する。
# 既存4体は従来素材、原作8体はback_cellsの原作顔セルを使う。
const FACES := {
	Chars.CHAR_PANDA: {
		"tex": "res://assets/characters/panda/walk/walk.png",
		"region": Rect2(4, 7, 16, 13)},  # 22x29 walk先頭の耳+顔(実測y7〜19)
	Chars.CHAR_MARIO: {
		"tex": "res://assets/characters/mario/walk/walk.png",
		"region": Rect2(4, 9, 15, 13)},  # 22x29 walk先頭の帽子+顔(実測y9〜21)
	Chars.CHAR_FOX: {
		"tex": "res://assets/third_party/sunny_land/PNG/sprites/player/idle/player-idle-1.png",
		"region": Rect2(9, 10, 18, 13)},  # 33x32 idleの耳+顔(実測y10〜22)
	Chars.CHAR_FROG: {
		"tex": "res://assets/third_party/sunny_land/PNG/sprites/frog/idle/frog-idle-1.png",
		"region": Rect2(6, 4, 22, 22)},  # 35x32素材の顔(目玉が主役)
	Chars.CHAR_TOME: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(384, 192, 64, 64)},
	Chars.CHAR_HITO: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(448, 192, 64, 64)},
	Chars.CHAR_PIYO: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(512, 192, 64, 64)},
	Chars.CHAR_UME: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(576, 192, 64, 64)},
	Chars.CHAR_CARBY: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(640, 192, 64, 64)},
	Chars.CHAR_DUO: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(704, 192, 64, 64)},
	Chars.CHAR_SEC1: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(768, 192, 64, 64)},
	Chars.CHAR_SEC2: {
		"tex": "res://assets/reference/vb2211/back_cells.png",
		"region": Rect2(832, 192, 64, 64)},
}

# HUD帯レイアウト(内部解像度640x360の最下段)。格ゲー定石: 自チーム左・敵チーム右
const PANEL_XS: Array[float] = [10.0, 104.0, 458.0, 552.0]
const PANEL_Y := 332.0
const PANEL_W := 88.0
const PANEL_H := 24.0

var _score: Label
var _msg: Label
var _hud: Control
var _cfg
var _state
var _face_cache: Dictionary = {}  # char_id → Texture2D(遅延ロード)
var _missing_face_warned: Dictionary = {}

func _ready() -> void:
	_score = Label.new()
	_score.position = Vector2(0, 6)
	_score.size = Vector2(640, 24)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 18)
	add_child(_score)
	_msg = Label.new()
	_msg.position = Vector2(0, 140)
	_msg.size = Vector2(640, 24)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 16)
	add_child(_msg)
	_hud = HudLayer.new()
	_hud.ui = self
	_hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

func setup(cfg) -> void:
	# game_viewが_ready時に呼ぶ(スタン値ゲージの分母などcfgを参照するため)
	_cfg = cfg

func update_from(state) -> void:
	_score.text = "%d - %d" % [state.score_l, state.score_r]
	if state.phase == SimState.PHASE_SERVE:
		_msg.text = "SERVE!"
	elif state.phase == SimState.PHASE_GAME_OVER:
		_msg.text = "LEFT WINS!" if state.winner == 0 else "RIGHT WINS!"
	else:
		_msg.text = ""
	_state = state
	_hud.queue_redraw()

class HudLayer:
	extends Control
	var ui

	func _draw() -> void:
		if ui != null:
			ui.draw_hud(self)

func draw_hud(c: Control) -> void:
	# 4キャラ分のパネル: 顔アイコン+耐久バー+ドライブゲージ。
	# 全てsim状態からの毎フレーム導出(ロールバック安全)
	if _state == null or _cfg == null:
		return
	for i in 4:
		var p = _state.players[i]
		var x: float = PANEL_XS[i]
		var team := 0 if i < 2 else 1
		# パネル地(半透明の紺)。原作の顔帯の青枠を意識
		c.draw_rect(Rect2(x, PANEL_Y, PANEL_W, PANEL_H), Color(0.05, 0.05, 0.30, 0.72))
		# 操作中スロットは黄枠(▽マーカーと同色)、それ以外は青枠
		var controlled: int = _state.controlled_l if team == 0 else 2 + _state.controlled_r
		var border := Color(1.0, 0.90, 0.20) if i == controlled else Color(0.30, 0.40, 0.85)
		c.draw_rect(Rect2(x, PANEL_Y, PANEL_W, PANEL_H), border, false, 1.0)
		# 顔アイコン(スタン中は点滅させて状態を顔でも伝える)。char_idから正本辞書で引く。
		var cid: int = p.char_id
		if FACES.has(cid):
			var face: Dictionary = FACES[cid]
			if not _face_cache.has(cid):
				_face_cache[cid] = load(face["tex"])
			var tex: Texture2D = _face_cache[cid]
			var region: Rect2 = face["region"]
			var face_mod := Color.WHITE
			if p.stun > 0 and (_state.tick / 4) % 2 == 0:
				face_mod = Color(1.0, 0.5, 0.5)
			var draw_size := Vector2(20.0, 20.0)  # 正方形の原作顔もHUD枠へ収める
			var draw_pos := Vector2(x + 2.0, PANEL_Y + 2.0) \
				+ (Vector2(20.0, 20.0) - draw_size) * 0.5
			c.draw_texture_rect_region(tex, Rect2(draw_pos, draw_size), region, face_mod)
		else:
			if not _missing_face_warned.has(cid):
				push_warning("顔アイコン未登録 char_id=%d" % cid)
				_missing_face_warned[cid] = true
			var missing := Rect2(x + 2.0, PANEL_Y + 2.0, 20.0, 20.0)
			c.draw_rect(missing, Color(0.3, 0.3, 0.3))
			c.draw_line(missing.position, missing.end, Color(0.7, 0.7, 0.7), 2.0)
			c.draw_line(Vector2(missing.end.x, missing.position.y),
				Vector2(missing.position.x, missing.end.y), Color(0.7, 0.7, 0.7), 2.0)
		# 耐久力バー: アタックを受けると減り、尽きるとスタン。ジャストトスで回復。
		# 残量で緑→黄→赤と変わる(あと1発で倒れる緊張感の可視化)
		var bar_x := x + 26.0
		var bar_w := PANEL_W - 30.0
		c.draw_rect(Rect2(bar_x, PANEL_Y + 4.0, bar_w, 7.0), Color(0.15, 0.15, 0.2, 0.9))
		if p.guard_max > 0:
			var frac := clampf(float(p.guard) / float(p.guard_max), 0.0, 1.0)
			var col := Color(0.30, 0.85, 0.35)
			if frac <= 0.25:
				col = Color(0.95, 0.25, 0.20)
			elif frac <= 0.5:
				col = Color(0.95, 0.80, 0.25)
			# スタン中はゼロから回復済みだが、点滅で「今は行動不能」を示す
			if p.stun > 0 and (_state.tick / 4) % 2 == 0:
				col = Color(0.6, 0.6, 0.6)
			c.draw_rect(Rect2(bar_x, PANEL_Y + 4.0, bar_w * frac, 7.0), col)
		c.draw_rect(Rect2(bar_x, PANEL_Y + 4.0, bar_w, 7.0), Color(0.45, 0.45, 0.55), false, 1.0)
		# ドライブゲージ(水色): 既存の第2ゲージ枠を6本のセグメントとして使う。
		var burnout: bool = p.burnout_ticks > 0
		var burnout_dim: bool = burnout and (_state.tick / 6) % 2 == 0
		var drive_bg := Color(0.3, 0.3, 0.32, 0.45) \
			if burnout_dim else Color(0.22, 0.22, 0.24, 0.9) \
			if burnout else Color(0.15, 0.15, 0.2, 0.9)
		c.draw_rect(Rect2(bar_x, PANEL_Y + 13.0, bar_w, 7.0), drive_bg)
		var segment_gap := 1.0
		var segment_w := (bar_w - segment_gap * 5.0) / 6.0
		for segment in 6:
			var segment_x := bar_x + float(segment) * (segment_w + segment_gap)
			var fill_units: int = clampi(
				p.drive_gauge - segment * _cfg.drive_gauge_stock,
				0, _cfg.drive_gauge_stock)
			var fill_w := segment_w * float(fill_units) / float(_cfg.drive_gauge_stock)
			if fill_units > 0:
				var drive_color := Color(0.35, 0.35, 0.38, 0.45) \
					if burnout_dim else Color(0.45, 0.45, 0.48, 0.9) \
					if burnout else Color(0.25, 0.75, 1.0, 0.95)
				c.draw_rect(Rect2(segment_x, PANEL_Y + 13.0, fill_w, 7.0),
					drive_color)
			c.draw_rect(Rect2(segment_x, PANEL_Y + 13.0, segment_w, 7.0),
				Color(0.4, 0.4, 0.42) if burnout else Color(0.35, 0.65, 0.85),
				false, 1.0)

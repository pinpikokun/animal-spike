# スコア・フェーズ・勝敗の文字表示+画面下端の顔HUD(スタン値/必殺ゲージ)。
# 表示層。sim_stateを読むだけ
extends CanvasLayer

const SimState := preload("res://src/sim/sim_state.gd")

# 顔アイコン(仮): 既存スプライトのidle1フレームから頭部を切り出して使う。
# 本番キャラ(トラックB)が入ったら専用の顔アイコンに差し替える
const FACE_FOX := "res://assets/third_party/sunny_land/PNG/sprites/player/idle/player-idle-1.png"
const FACE_FROG := "res://assets/third_party/sunny_land/PNG/sprites/frog/idle/frog-idle-1.png"
const FACE_REGION_FOX := Rect2(8, 5, 18, 18)   # 33x32素材の頭部(8倍拡大で実測)
const FACE_REGION_FROG := Rect2(6, 4, 22, 22)  # 35x32素材の顔(目玉が主役)

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
var _face_tex: Array = []  # [キツネ, カエル]

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
	_face_tex = [load(FACE_FOX), load(FACE_FROG)]
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
	# 4キャラ分のパネル: 顔アイコン+スタン値バー(赤)+必殺ゲージ(水色、値は未実装で0)。
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
		# 顔アイコン(スタン中は点滅させて状態を顔でも伝える)
		var tex: Texture2D = _face_tex[team]
		var region: Rect2 = FACE_REGION_FOX if team == 0 else FACE_REGION_FROG
		var face_mod := Color.WHITE
		if p.stun > 0 and (_state.tick / 4) % 2 == 0:
			face_mod = Color(1.0, 0.5, 0.5)
		c.draw_texture_rect_region(tex, Rect2(x + 2.0, PANEL_Y + 2.0, 20.0, 20.0),
			region, face_mod)
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
		# 必殺ゲージ(水色): 値はまだsimに無いので枠と空バーのみ(M3bで接続)
		c.draw_rect(Rect2(bar_x, PANEL_Y + 13.0, bar_w, 7.0), Color(0.15, 0.15, 0.2, 0.9))
		c.draw_rect(Rect2(bar_x, PANEL_Y + 13.0, bar_w, 7.0), Color(0.35, 0.65, 0.85), false, 1.0)

# 本番ゲームビュー。sim状態を読んでスプライトを駆動する。表示層(float可)。
extends Node2D

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const ViewTransform := preload("res://src/display/view_transform.gd")
const SpriteFactory := preload("res://src/display/sprite_factory.gd")
const AnimSelect := preload("res://src/display/anim_select.gd")
const InputPoll := preload("res://src/display/input_poll.gd")

const SPRITE_HALF_H := 16.0  # キャラ素材32px高の半分(足元をノード原点に合わせる)
const RECEIVE_HOP_PX := 4.0  # レシーブ時の小ホップ量(接地ヒットの手続き演出)

var cfg
var state
var _sprites: Array = []  # AnimatedSprite2D x4
var _ball: Sprite2D
var _fx: Node2D  # エフェクト最前面レイヤー(FxLayer)
var _ball_frame_w := 0     # 転がりシート1フレームの辺(px)
var _ball_roll_frames := 1  # 転がりシートのフレーム数
# ネット対戦モード。cfg/stateは外部(SimRoot)が所有しtickも外部が回す。
# ここは状態を読んでスプライトを駆動する表示専任になる
var external_sim := false

func attach_external(cfg_in, state_ref) -> void:
	# instantiate直後・add_child前に呼ぶこと(_readyがcfg/stateを自前生成しないため)
	external_sim = true
	cfg = cfg_in
	state = state_ref

func _ready() -> void:
	if not external_sim:
		cfg = SimConfig.new()
		if not cfg.valid:
			push_error("rules.jsonの読み込みに失敗したため起動を中止する")
			return
		state = SimState.new()
		Simulation.reset_match(state, cfg, 0)
	# 表示のみの一括シフト(ScoreUIはCanvasLayerで不動):
	# 下寄せ(原作準拠)+コートが画面より狭いぶん中央寄せ
	position = Vector2((640.0 - ViewTransform.to_px(cfg.court_width)) * 0.5, 16.0)
	Engine.physics_ticks_per_second = cfg.tick_rate
	$Court.setup(cfg)
	var fox := SpriteFactory.build_fox()
	var frog := SpriteFactory.build_frog()
	for i in 4:
		var s := AnimatedSprite2D.new()
		# チーム0(左, index0,1)=キツネ、チーム1(右)=カエル
		s.sprite_frames = fox if Simulation.team_of(i) == 0 else frog
		# 奇数幅(33px)のセンター配置は常に半ピクセルずれてぼやける。
		# 非センター+整数オフセットで足元原点・整数ピクセル描画にする
		s.centered = false
		s.offset = Vector2(-16, -32)
		# 手前レーン(偶数slot)を前面に描く(奥のキャラと重なった時に自然な前後関係)
		s.z_index = 1 if i % 2 == 0 else 0
		s.play("idle")
		$Players.add_child(s)
		_sprites.append(s)
	_ball = $Ball
	_ball.centered = true
	# ボール素材はscripts/gen_ball.gdがゲーム実寸へ直接ラスタした焼き込みPNG。
	# 転がり回転は焼き込みフレームを差し替える方式(実行時回転はドット絵が
	# ガビガビになるため使わない)。シートは横並びROLL_FRAMES枚、フレームは正方。
	# rules.jsonのball_radius_pxを変えたらジェネレーター再実行が必要
	var roll: Texture2D = load("res://assets/ball/volleyball_roll.png")
	_ball.texture = roll
	_ball.region_enabled = true
	_ball_frame_w = roll.get_height()  # フレームは正方なので高さ=1フレーム辺
	_ball_roll_frames = int(roll.get_width() / _ball_frame_w)
	_ball.region_rect = Rect2(0, 0, _ball_frame_w, _ball_frame_w)
	var ball_px := ViewTransform.to_px(cfg.ball_radius) * 2.0
	if _ball_frame_w != int(ball_px):
		push_warning("ボール素材(%dpx)と表示直径(%dpx)が不一致。scripts/gen_ball.gdを再実行推奨" % [_ball_frame_w, int(ball_px)])
	_ball.scale = Vector2.ONE * (ball_px / float(_ball_frame_w))
	# エフェクトレイヤーは最後に追加し、z_indexでも最前面を保証する
	_fx = FxLayer.new()
	_fx.view = self
	_fx.z_index = 10
	add_child(_fx)

func _physics_process(_delta: float) -> void:
	if external_sim:
		# ネット対戦: tickはSimRootがSyncManager経由で回す。ここは表示だけ
		_sync_sprites()
		$ScoreUI.update_from(state)
		return
	var input := InputPoll.poll()
	# 右チームは完全CPU(1人プレイ)。操作キャラ枠の入力もsim層のCPUが決定論的に生成する
	var cpu_r: int = SimCpu.decide(state, 2 + state.controlled_r, cfg)
	Simulation.tick(state, [input, cpu_r], cfg)
	_sync_sprites()
	$ScoreUI.update_from(state)

# 2軸の見た目(原作準拠): 後衛slotは手前(下)、前衛slotは奥(上)。
# court.gdの中央対称収束に沿った表示専用の上下オフセット。simには影響しない
static func _depth_offset(i: int) -> Vector2:
	if i % 2 == 0:
		return Vector2(0.0, 5.0)
	return Vector2(0.0, -5.0)

func _sync_sprites() -> void:
	for i in _sprites.size():
		var p = state.players[i]
		var spr: AnimatedSprite2D = _sprites[i]
		var pos := ViewTransform.pos_of(p) + _depth_offset(i)
		# レシーブの小ホップ: 接地ヒット中はhit_cooldownから上下オフセットを導出。
		# 打った瞬間(cooldown最大)に最も持ち上がり、硬直が抜けるにつれ着地する。
		# 状態から導出するのでロールバック再描画でも一貫する
		if p.on_ground == 1 and p.hit_cooldown > 0:
			var t := float(p.hit_cooldown) / float(cfg.hit_cooldown_ticks)
			pos.y -= RECEIVE_HOP_PX * t
		spr.flip_h = AnimSelect.flip_for_team(Simulation.team_of(i))
		var anim := AnimSelect.anim_for(p)
		if spr.animation != anim:
			spr.play(anim)
		# カエル素材はidle系の足元に5pxの透明余白があり浮いて見える。
		# キツネの接地軸に合わせる表示補正(jump素材は余白なしなので補正しない)
		if Simulation.team_of(i) == 1 and anim != "jump":
			pos.y += 5.0
		# 整数ピクセルにスナップ(小数座標のままだとドットが滲む)
		spr.position = pos.round()
	var ball_pos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	if state.phase == SimState.PHASE_SERVE:
		# 保持中はサーバーの奥行きオフセットに合わせる(頭上からずれないように)
		ball_pos += _depth_offset(state.serving_team * 2)
	_ball.position = ball_pos.round()
	# 転がり回転: simが積むball_spin(横の勢いの累積)からフレームを導出する。
	# 真上のトスはほぼ無回転、前へ強く飛ぶほど速く回る。右へ進めば時計回り。
	# 状態から導出しビューに角度を溜めない(ロールバック安全)
	var frame := 0
	if state.phase != SimState.PHASE_SERVE:
		var radius_px := ViewTransform.to_px(cfg.ball_radius)
		if radius_px > 0.0:
			var angle := ViewTransform.to_px(state.ball_spin) / radius_px
			var step := TAU / float(_ball_roll_frames)
			frame = posmod(roundi(angle / step), _ball_roll_frames)
	_ball.region_rect = Rect2(frame * _ball_frame_w, 0, _ball_frame_w, _ball_frame_w)
	_fx.queue_redraw()  # 壁の波紋とマーカーはsim状態から毎フレーム導出する

# エフェクト専用の最前面レイヤー。親ノード自身の_drawは子(コート背景)の下に
# 描かれて埋もれるため、必ず最後の子ノードとして重ねる
class FxLayer:
	extends Node2D
	var view

	func _draw() -> void:
		if view != null:
			view.draw_fx(self)

func draw_fx(c: CanvasItem) -> void:
	# 透明な壁(コート端)の「ブイン」: 壁で跳ね返った直後=壁の近くで壁から離れる向きに
	# 飛んでいる時だけ描く。強さは壁からの距離で減衰。
	# 全てsim状態からの導出でビュー側に状態を持たない(ロールバック安全)
	if state == null or cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var bx := ViewTransform.to_px(state.ball_x)
	var by := ViewTransform.to_px(state.ball_y)
	var vx := ViewTransform.to_px(state.ball_vx)
	var reach := 70.0
	if bx < reach and vx > 0.01:
		_draw_wall_ripple(c, 0.0, by, 1.0 - bx / reach, 1.0)
	elif bx > w - reach and vx < -0.01:
		_draw_wall_ripple(c, w, by, 1.0 - (w - bx) / reach, -1.0)
	_draw_control_marker(c)

func _draw_wall_ripple(c: CanvasItem, wall_x: float, y: float, strength: float, dir: float) -> void:
	# 透明な壁の「ブイン」: 壁全体が光り、大きな同心の弧が広がる。strength 0..1
	var s := clampf(strength, 0.0, 1.0)
	# 壁面のグロウ(縦の光の帯。接触直後ほど太く明るい)
	var glow_w := 4.0 + 10.0 * s
	var gx := wall_x if dir > 0.0 else wall_x - glow_w
	c.draw_rect(Rect2(gx, y - 90.0, glow_w, 180.0), Color(0.70, 0.90, 1.0, 0.35 * s))
	c.draw_rect(Rect2(wall_x - 1.0, y - 120.0, 2.0, 240.0), Color(0.85, 0.95, 1.0, 0.6 * s))
	# 大きな同心の弧が壁からコート内側へ広がる
	var center_angle := 0.0 if dir > 0.0 else PI
	for k in 4:
		var r := 14.0 + 16.0 * float(k) + 24.0 * (1.0 - s)
		var a := s * (0.85 - 0.18 * float(k))
		if a <= 0.0:
			continue
		c.draw_arc(Vector2(wall_x, y), r, center_angle - 1.1, center_angle + 1.1, 24, Color(0.80, 0.93, 1.0, a), 3.0)

func _draw_control_marker(c: CanvasItem) -> void:
	# 操作中キャラの頭上に▽(黄)。sim状態のcontrolled_lから導出(表示専用)
	# TODO(ネット対戦): 右チーム操作時はcontrolled_rを見る配線が要る
	var idx: int = state.controlled_l
	var p = state.players[idx]
	var pos := ViewTransform.pos_of(p) + _depth_offset(idx)
	var top := pos + Vector2(0.0, -44.0)
	var pts := PackedVector2Array([
		top + Vector2(-7.0, -8.0), top + Vector2(7.0, -8.0), top + Vector2(0.0, 2.0)])
	c.draw_colored_polygon(pts, Color(1.0, 0.90, 0.20))
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.45, 0.30, 0.0), 1.0)

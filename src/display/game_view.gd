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

# 2軸の見た目(原作準拠): 後衛slotは手前(下+左)、前衛slotは奥(上+右)。
# court.gdのオブリーク(SHEAR=0.5)に沿った表示専用オフセット。simには影響しない
static func _depth_offset(i: int) -> Vector2:
	if i % 2 == 0:
		return Vector2(-2.0, 4.0)
	return Vector2(2.0, -4.0)

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
		# 整数ピクセルにスナップ(小数座標のままだとドットが滲む)
		spr.position = pos.round()
		spr.flip_h = AnimSelect.flip_for_team(Simulation.team_of(i))
		var anim := AnimSelect.anim_for(p)
		if spr.animation != anim:
			spr.play(anim)
	var ball_pos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	if state.phase == SimState.PHASE_SERVE:
		# 保持中はサーバーの奥行きオフセットに合わせる(頭上からずれないように)
		ball_pos += _depth_offset(state.serving_team * 2)
	_ball.position = ball_pos.round()
	# 転がり回転(原作準拠): 保持中(サーブ)は回さず、飛行/転がり中だけ水平位置から
	# フレームを選ぶ。角度=位置px/半径px→フレーム番号。右へ進むほど番号が進み時計回り
	# =右回転、左へ進めば左回転。状態から導出しビューに角度を溜めない(ロールバック安全)
	var frame := 0
	if state.phase != SimState.PHASE_SERVE:
		var radius_px := ViewTransform.to_px(cfg.ball_radius)
		if radius_px > 0.0:
			var angle := ViewTransform.to_px(state.ball_x) / radius_px
			var step := TAU / float(_ball_roll_frames)
			frame = posmod(roundi(angle / step), _ball_roll_frames)
	_ball.region_rect = Rect2(frame * _ball_frame_w, 0, _ball_frame_w, _ball_frame_w)

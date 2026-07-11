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
	# 実寸一致ならscale=1でニアレスト描画され、縮小ぼやけが出ない。
	# rules.jsonのball_radius_pxを変えたらジェネレーター再実行が必要
	var ball_px := ViewTransform.to_px(cfg.ball_radius) * 2.0
	if _ball.texture.get_width() != int(ball_px):
		push_warning("ボール素材(%dpx)と表示直径(%dpx)が不一致。scripts/gen_ball.gdを再実行推奨" % [_ball.texture.get_width(), int(ball_px)])
	_ball.scale = Vector2.ONE * (ball_px / float(_ball.texture.get_width()))

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

func _sync_sprites() -> void:
	for i in _sprites.size():
		var p = state.players[i]
		var spr: AnimatedSprite2D = _sprites[i]
		var pos := ViewTransform.pos_of(p)
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
	_ball.position = Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y)).round()
	# ラリー中のボール回転(原作準拠): 転がり角を水平位置から一意に導く。右へ進むほど
	# 角度が増え時計回り=右回転、左へ進めば左回転。状態から導出しビューに角度を溜めない
	var radius_px := ViewTransform.to_px(cfg.ball_radius)
	if radius_px > 0.0:
		_ball.rotation = ViewTransform.to_px(state.ball_x) / radius_px

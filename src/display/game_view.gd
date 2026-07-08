# 本番ゲームビュー。sim状態を読んでスプライトを駆動する。表示層(float可)。
extends Node2D

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const ViewTransform := preload("res://src/display/view_transform.gd")
const SpriteFactory := preload("res://src/display/sprite_factory.gd")
# const AnimSelect := preload("res://src/display/anim_select.gd")  # Task2で有効化

const BALL_SRC_PX := 144.0  # ボール素材(volleyball_144.png)の実寸
const SPRITE_HALF_H := 16.0  # キャラ素材32px高の半分(足元をノード原点に合わせる)

var cfg
var state
var _sprites: Array = []  # AnimatedSprite2D x4
var _ball: Sprite2D

func _ready() -> void:
	cfg = SimConfig.new()
	if not cfg.valid:
		push_error("rules.jsonの読み込みに失敗したため起動を中止する")
		return
	state = SimState.new()
	Simulation.reset_rally(state, cfg, 0)
	Engine.physics_ticks_per_second = cfg.tick_rate
	var fox := SpriteFactory.build_fox()
	var frog := SpriteFactory.build_frog()
	for i in 4:
		var s := AnimatedSprite2D.new()
		# チーム0(左, index0,1)=キツネ、チーム1(右)=カエル
		s.sprite_frames = fox if Simulation.team_of(i) == 0 else frog
		s.centered = true
		s.offset = Vector2(0, -SPRITE_HALF_H)
		s.play("idle")
		$Players.add_child(s)
		_sprites.append(s)
	_ball = $Ball
	_ball.centered = true
	# 当たり判定半径(fp)から表示直径pxを求め、素材実寸に対する縮小率を決める
	var ball_px := ViewTransform.to_px(cfg.ball_radius) * 2.0
	_ball.scale = Vector2.ONE * (ball_px / BALL_SRC_PX)

func _physics_process(_delta: float) -> void:
	var input := 0
	if Input.is_key_pressed(KEY_LEFT):
		input |= Simulation.IN_LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		input |= Simulation.IN_RIGHT
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_SPACE):
		input |= Simulation.IN_JUMP
	if Input.is_key_pressed(KEY_X):
		input |= Simulation.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= Simulation.IN_SWITCH
	Simulation.tick(state, [input, 0], cfg)
	_sync_sprites()

func _sync_sprites() -> void:
	for i in _sprites.size():
		var p = state.players[i]
		var spr: AnimatedSprite2D = _sprites[i]
		spr.position = ViewTransform.pos_of(p)
		# Task2でアニメ選択・左右反転を接続する。Task1では位置反映とidle固定のみ
	_ball.position = Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))

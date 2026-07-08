# SIM DEBUG VIEW。シミュレーション層の動作確認用の開発計器
# ゲームとしての見た目はM1でフリー素材を入れて作る。ここは表示層なのでfloat使用OK
extends Node2D

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

var cfg
var state
var label: Label

func _ready() -> void:
	cfg = SimConfig.new()
	state = SimState.new()
	for p in state.players:
		p.y = cfg.floor_y
	state.players[0].x = FP.from_int(100)
	state.players[1].x = FP.from_int(220)
	state.players[2].x = FP.from_int(420)
	state.players[3].x = FP.from_int(540)
	state.ball_x = FP.from_int(320)
	state.ball_y = FP.from_int(60)
	Engine.physics_ticks_per_second = cfg.tick_rate
	label = Label.new()
	label.position = Vector2(4, 4)
	add_child(label)

func _physics_process(_delta: float) -> void:
	var input := 0
	if Input.is_key_pressed(KEY_LEFT):
		input |= Simulation.IN_LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		input |= Simulation.IN_RIGHT
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_SPACE):
		input |= Simulation.IN_JUMP
	Simulation.step(state, [input, 0, 0, 0], cfg)
	label.text = "SIM DEBUG VIEW (開発用計器)\ntick=%d\nhash=%s\n矢印キーで移動 Zでジャンプ" % [
		state.tick, String.num_uint64(state.state_hash(), 16)]
	queue_redraw()

func _draw() -> void:
	var fy := float(FP.to_int(cfg.floor_y))
	draw_line(Vector2(0, fy), Vector2(640, fy), Color(0.4, 0.4, 0.55))
	for p in state.players:
		draw_circle(Vector2(FP.to_int(p.x), FP.to_int(p.y)), 6.0, Color(0.9, 0.8, 0.3))
	draw_circle(
		Vector2(FP.to_int(state.ball_x), FP.to_int(state.ball_y)),
		float(FP.to_int(cfg.ball_radius)), Color(0.95, 0.95, 0.95))

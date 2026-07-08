# スコア・フェーズ・勝敗の文字表示。表示層。sim_stateを読むだけ
extends CanvasLayer

const SimState := preload("res://src/sim/sim_state.gd")

var _score: Label
var _msg: Label

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

func update_from(state) -> void:
	_score.text = "%d - %d" % [state.score_l, state.score_r]
	if state.phase == SimState.PHASE_SERVE:
		_msg.text = "SERVE!"
	elif state.phase == SimState.PHASE_GAME_OVER:
		_msg.text = "LEFT WINS!" if state.winner == 0 else "RIGHT WINS!"
	else:
		_msg.text = ""

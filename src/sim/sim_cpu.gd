# CPU相方の入力生成。シミュレーション層の一部なので完全決定論・int演算のみ
# 状態を読むだけで書き換えない(副作用禁止)。v0: ボール追跡と単純ヒット
# simulation.gdをpreloadしない(循環防止)。定数はsim_input.gdから取る
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

static func _spawn_x(idx: int, cfg) -> int:
	var back: int = FP.from_int(cfg.spawn_back_px)
	var front: int = FP.from_int(cfg.spawn_front_px)
	var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
	return positions[idx]

static func _walk_to(p, target_x: int, deadzone: int) -> int:
	if p.x < target_x - deadzone:
		return SimInput.IN_RIGHT
	elif p.x > target_x + deadzone:
		return SimInput.IN_LEFT
	return 0

static func decide(s, idx: int, cfg) -> int:
	var team: int = idx / 2
	var p = s.players[idx]
	var deadzone: int = cfg.player_reach / 2
	if s.phase == SimStateScript.PHASE_SERVE:
		# サーブ遅延タイマーはsimulation.gdのstep()が減算する(ここは読むだけ)
		if idx == s.serving_team * 2 and s.timer <= 0:
			# サーブ=前トス(ネット方向)で緩く越す。CPUは自分でアタックせず確実に返す
			var toss_dir: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
			return SimInput.IN_ACTION | toss_dir
		return 0
	if s.phase == SimStateScript.PHASE_POINT_PAUSE:
		# ポーズ中は棒立ちせず持ち場へ歩いて戻る(次ラリーの準備)
		return _walk_to(p, _spawn_x(idx, cfg), deadzone)
	if s.phase != SimStateScript.PHASE_RALLY:
		return 0
	var on_own_side: bool = (s.ball_x < cfg.net_x) == (team == 0)
	var target_x: int
	if on_own_side:
		target_x = s.ball_x
	else:
		target_x = _spawn_x(idx, cfg)
	var input: int = _walk_to(p, target_x, deadzone)
	if on_own_side:
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		# simulation.gdの_resolve_hitと同じ楕円判定(横reach・縦reach_up)
		var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= cfg.player_reach * cfg.player_reach:
			input |= SimInput.IN_ACTION
	return input

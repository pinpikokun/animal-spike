# シミュレーション本体。1tick進める純粋ロジック
# int演算のみ。ここにfloatを書いたらSyncTest以前にレビューで即アウト
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_JUMP := SimInput.IN_JUMP
const IN_ACTION := SimInput.IN_ACTION
const IN_SWITCH := SimInput.IN_SWITCH

static func team_of(i: int) -> int:
	return i / 2

static func _dir_of_team(team: int) -> int:
	return 1 if team == 0 else -1

static func step(state, inputs: Array[int], cfg) -> void:
	state.tick += 1
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg, team_of(i))
		_try_hit(state, i, input, cfg)
	_step_ball(state, cfg)

static func _try_hit(s, i: int, input: int, cfg) -> void:
	if s.phase != SimStateScript.PHASE_RALLY:
		return
	if not (input & IN_ACTION):
		return
	var p = s.players[i]
	if p.hit_cooldown > 0:
		return
	var dx: int = s.ball_x - p.x
	var dy: int = s.ball_y - p.y
	var reach: int = cfg.player_reach
	# 両辺ともfp生値の積((fp)^2単位)で比較しスケールを揃える。
	# オーバーフロー検討: dx最大640<<16≈4.2e7、二乗≈1.8e15 < int64上限9.2e18で安全
	if dx * dx + dy * dy > reach * reach:
		return
	var team: int = team_of(i)
	var dir: int = _dir_of_team(team)
	if p.on_ground == 1:
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = dir * cfg.bump_fwd_speed
	else:
		s.ball_vy = cfg.spike_vy
		s.ball_vx = dir * cfg.spike_vx
	p.hit_cooldown = cfg.hit_cooldown_ticks
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team

static func _step_player(p, input: int, cfg, team: int) -> void:
	p.vx = 0
	if input & IN_LEFT:
		p.vx = -cfg.move_speed
	if input & IN_RIGHT:
		p.vx = cfg.move_speed
	if (input & IN_JUMP) and p.on_ground == 1:
		p.vy = -cfg.jump_speed
		p.on_ground = 0
	if p.on_ground == 0:
		p.vy += cfg.gravity
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w
	else:
		min_x = cfg.net_x + cfg.net_half_w
	p.x = clampi(p.x + p.vx, min_x, max_x)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1

static func _step_ball(s, cfg) -> void:
	var prev_x: int = s.ball_x
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	if s.ball_x < left:
		s.ball_x = left + (left - s.ball_x)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif s.ball_x > right:
		s.ball_x = right - (s.ball_x - right)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	if s.ball_y > floor_limit:
		s.ball_y = floor_limit - (s.ball_y - floor_limit)
		s.ball_vy = -s.ball_vy * cfg.ball_bounce_num / cfg.ball_bounce_den
	var ceil_limit: int = cfg.ball_radius
	if s.ball_y < ceil_limit:
		s.ball_y = ceil_limit + (ceil_limit - s.ball_y)
		s.ball_vy = -s.ball_vy * cfg.ball_bounce_num / cfg.ball_bounce_den
	_ball_vs_net(s, cfg, prev_x)

static func _ball_vs_net(s, cfg, prev_x: int) -> void:
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	var net_right: int = cfg.net_x + cfg.net_half_w + cfg.ball_radius
	var below_top: bool = s.ball_y > cfg.net_top_y
	var was_left: bool = prev_x < cfg.net_x
	var is_left: bool = s.ball_x < cfg.net_x
	if below_top:
		# ネット下部は壁。来た側へ押し返す
		if s.ball_x >= net_left and s.ball_x <= net_right:
			if was_left:
				s.ball_x = net_left - (s.ball_x - net_left)
				if s.ball_vx > 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
			else:
				s.ball_x = net_right + (net_right - s.ball_x)
				if s.ball_vx < 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif was_left != is_left:
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット
		s.touches = 0

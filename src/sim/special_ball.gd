# 特殊球の排他的な同期状態と、原作座標・時間換算の正本。
extends RefCounted

const Chars := preload("res://src/sim/chars.gd")

static func set_special(s, special_id: int, owner_idx: int,
		origin_vx: int = 0) -> void:
	s.ball_special_id = special_id
	s.ball_special_phase = 0
	s.ball_special_ticks = 0
	s.ball_special_owner_idx = owner_idx
	s.ball_special_origin_vx = origin_vx
	s.ball_held_by = -1

static func clear_special(s) -> void:
	s.ball_special_id = 0
	s.ball_special_phase = 0
	s.ball_special_ticks = 0
	s.ball_special_owner_idx = -1
	s.ball_special_origin_vx = 0
	s.ball_held_by = -1

static func is_visible(s) -> bool:
	return s.ball_special_id != Chars.SUPER_DISAPPEARING_BALL \
		and s.ball_special_id != Chars.SUPER_TRANSFER_BALL

static func is_contactable(s) -> bool:
	return is_visible(s) and s.ball_held_by < 0

static func step(s, cfg) -> bool:
	if s.ball_held_by >= 0:
		return true
	match s.ball_special_id:
		Chars.SUPER_GHOST_BALL:
			_step_ghost(s, cfg)
			return true
		Chars.SUPER_DISAPPEARING_BALL:
			_step_disappearing(s, cfg)
			return true
		Chars.SUPER_FEINT_ATTACK:
			return _step_feint(s, cfg)
		Chars.SUPER_GUST_BALL, Chars.SUPER_SNAKE_BALL:
			_step_wave_ball(s, cfg)
			return true
		Chars.SUPER_TRANSFER_BALL:
			_step_transfer(s, cfg)
			return true
	return false

static func original_ticks(original_tick_count: int, cfg) -> int:
	var numerator: int = original_tick_count * cfg.tick_rate * 1000
	return (numerator + cfg.original_tick_rate_milli / 2) \
		/ cfg.original_tick_rate_milli

static func is_above_original_y(s, original_y: int, cfg) -> bool:
	var ball_height: int = cfg.floor_y - s.ball_y
	var current_net_height: int = cfg.floor_y - cfg.net_top_y
	return ball_height * 33 > (291 - original_y) * current_net_height

static func _is_below_original_y(s, original_y: int, cfg) -> bool:
	var ball_height: int = cfg.floor_y - s.ball_y
	var current_net_height: int = cfg.floor_y - cfg.net_top_y
	return ball_height * 33 < (291 - original_y) * current_net_height

static func _original_vx(original_vx: int, cfg) -> int:
	var converted: int = original_vx * (cfg.court_width / 2) \
		* cfg.original_tick_rate_milli / (72 * cfg.tick_rate * 1000)
	return _preserve_nonzero_sign(converted, original_vx)

static func _original_vy(original_vy: int, cfg) -> int:
	var converted: int = original_vy * (cfg.floor_y - cfg.net_top_y) \
		* cfg.original_tick_rate_milli / (33 * cfg.tick_rate * 1000)
	return _preserve_nonzero_sign(converted, original_vy)

static func _preserve_nonzero_sign(converted: int, original: int) -> int:
	if converted != 0 or original == 0:
		return converted
	return 1 if original > 0 else -1

static func _step_half_speed(s, cfg) -> void:
	s.ball_special_ticks += 1
	# 原作0x4054: counterを先に増やし、奇数回だけ横へ進める。
	if s.ball_special_ticks % 2 == 1:
		s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy / 2
	s.ball_vy += cfg.gravity / 2

static func _step_disappearing(s, cfg) -> void:
	if s.ball_special_phase == 0:
		_step_half_speed(s, cfg)
		if s.ball_special_ticks >= original_ticks(10, cfg):
			s.ball_special_phase = 1
		return
	# 減速だけを終え、不可視・非接触のまま通常速度で下降線を待つ。
	s.ball_special_ticks += 1
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	if s.ball_vy > 0 and _is_below_original_y(s, 224, cfg):
		_reappear_as_normal(s, cfg)

static func _step_feint(s, cfg) -> bool:
	if s.ball_special_phase != 0:
		return false
	_step_half_speed(s, cfg)
	if s.ball_special_ticks >= original_ticks(10, cfg):
		s.ball_special_phase = 1
		var direction: int = _direction_of(s.ball_special_origin_vx)
		if direction == 0:
			direction = _direction_of(s.ball_vx)
		s.ball_vx += direction * _original_vx(2, cfg)
		s.ball_vy = _original_vy(16, cfg)
	return true

static func _step_transfer(s, cfg) -> void:
	s.ball_special_ticks += 1
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	if s.ball_special_ticks >= original_ticks(6, cfg) \
			or _is_below_original_y(s, 240, cfg):
		_reappear_as_normal(s, cfg)

static func _reappear_as_normal(s, cfg) -> void:
	var vx: int = s.ball_vx / 2
	clear_special(s)
	s.ball_vx = vx
	s.ball_vy = _original_vy(8, cfg)

static func _step_wave_ball(s, cfg) -> void:
	s.ball_special_ticks += 1
	var cycle_ticks: int = original_ticks(16, cfg)
	# 1..15,0という原作位相を34tickへ時間比で広げる。対称なので一周期の
	# 波形成分は厳密に0へ戻り、基礎速度を勝手に加減速させない。
	var original_phase: int = \
		((s.ball_special_ticks * 16 + cycle_ticks - 1) / cycle_ticks) % 16
	var wave_units: int
	if original_phase < 8:
		wave_units = original_phase - 4
	else:
		wave_units = 12 - original_phase
	if s.ball_special_id == Chars.SUPER_SNAKE_BALL:
		wave_units *= 2
	s.ball_vx = s.ball_special_origin_vx + _original_vx(wave_units, cfg)
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy

static func _step_ghost(s, cfg) -> void:
	s.ball_special_ticks += 1
	var old_vy: int = s.ball_vy
	s.ball_x += s.ball_vx
	s.ball_y += old_vy
	s.ball_vy += cfg.gravity
	var direction: int = _direction_of(s.ball_vx)
	if direction == 0:
		return
	var future_on_target_side: bool = \
		(s.ball_x + s.ball_vx * 2 > cfg.net_x) == (direction > 0)
	if not future_on_target_side or not is_above_original_y(s, 224, cfg):
		return
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	# 回避判断だけ原作の壁内座標へ丸める。実座標は残し、後段の共通壁判定で
	# 反射と特殊解除を必ず処理する。
	var clamped_x: int = clampi(s.ball_x, left, right)
	var target_team: int = 1 if direction > 0 else 0
	var first_idx: int = target_team * 2
	var first_x: int = s.players[first_idx].x
	var second_x: int = s.players[first_idx + 1].x
	var playable_width: int = right - left
	var near_distance: int = 12 * playable_width / (148 - 4)
	var far_from_both: bool = absi(clamped_x - first_x) > near_distance \
		and absi(clamped_x - second_x) > near_distance
	if far_from_both:
		# 原作0x44a4: 通常縦移動の半分を戻し、相手方向へ3進める。
		s.ball_y -= old_vy / 2
		s.ball_x += direction * _original_vx(3, cfg)
		return
	# 原作0x4451: 壁際を除き、守備者のいる側と反対へ横補正する。
	if clamped_x > left and clamped_x < right:
		if (clamped_x > first_x) == (direction > 0):
			s.ball_x += direction * _original_vx(2, cfg)
		else:
			s.ball_x -= s.ball_vx / 2
	s.ball_y += _original_vy(8, cfg)

static func _direction_of(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0

# 体力スタン・泡・感電・炎上の共通時計と、入力不能中の専用物理。
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

const PLAYER_HALF_W_PX := 8
const PLAYER_HALF_W := PLAYER_HALF_W_PX << FP.SHIFT

static func input_locked(p) -> bool:
	return (p.stun_ticks | p.bubble_ticks | p.shock_ticks | p.burn) != 0

static func apply_shock(p, team: int, cfg) -> void:
	p.shock_ticks = maxi(p.shock_ticks, cfg.shock_ticks)
	_clear_reactions(p)
	var team_dir: int = SimStateScript._dir_of_team(team)
	var original_velocity: int = -team_dir * 2
	p.vx = original_vx(original_velocity, cfg)
	p.vy = original_vy(original_velocity, cfg)
	p.on_ground = 0

static func apply_bubble(p, cfg) -> void:
	p.bubble_ticks = maxi(p.bubble_ticks, cfg.bubble_ticks)
	_clear_reactions(p)
	p.vx = 0
	p.vy = 0
	p.on_ground = 0

static func step(p, cfg, team: int, _state_tick: int, actor: int, rng: int) -> bool:
	var stun_active: bool = p.stun_ticks > 0
	var bubble_before: int = p.bubble_ticks
	var bubble_active: bool = bubble_before > 0
	var shock_active: bool = p.shock_ticks > 0
	var burn_active: bool = p.burn > 0
	# 優先表示・物理とは独立に、付与済みの時計は同じtickに全て進める。
	if stun_active:
		p.stun_ticks -= 1
		if p.stun_ticks == 0:
			CombatResources.recover_health_stun(p, SimStateScript.STUN_END_TIMED)
	if bubble_active:
		p.bubble_ticks -= 1
	if shock_active:
		p.shock_ticks -= 1
	if burn_active:
		p.burn -= 1
	if stun_active:
		# スタン物理は既存の通常移動へ入力0で渡す。
		return false
	if bubble_active:
		_step_bubble(p, cfg, bubble_before, actor, rng)
		return true
	if shock_active or burn_active:
		_step_friction_fall(p, cfg, team)
		return true
	return false

static func original_vx(value: int, cfg) -> int:
	var converted: int = value * (cfg.court_width / 2) \
		* cfg.original_tick_rate_milli / (72 * cfg.tick_rate * 1000)
	return _preserve_sign(converted, value)

static func original_vy(value: int, cfg) -> int:
	var converted: int = value * (cfg.floor_y - cfg.net_top_y) \
		* cfg.original_tick_rate_milli / (33 * cfg.tick_rate * 1000)
	return _preserve_sign(converted, value)

static func _preserve_sign(converted: int, original: int) -> int:
	if converted != 0 or original == 0:
		return converted
	return 1 if original > 0 else -1

static func _clear_reactions(p) -> void:
	p.flinch = 0
	p.push = 0
	p.dive = 0
	p.dive_contact_ticks = 0
	p.dive_age_ticks = 0
	p.dive_resource_mode = SimStateScript.DIVE_NONE
	p.special_action = 0
	p.special_action_ticks = 0

static func _step_friction_fall(p, cfg, team: int) -> void:
	p.vx = p.vx * 3 / 4
	p.vy += cfg.gravity
	var minimum: int = 0
	var maximum: int = cfg.court_width
	if team == 0:
		maximum = cfg.net_x - cfg.net_half_w - PLAYER_HALF_W
	else:
		minimum = cfg.net_x + cfg.net_half_w + PLAYER_HALF_W
	p.x = clampi(p.x + p.vx, minimum, maximum)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = -p.vy * 2 / 3
		if -p.vy <= cfg.gravity:
			p.vy = 0
			p.on_ground = 1
		else:
			p.on_ground = 0
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1

static func _step_bubble(p, cfg, bubble_before: int, actor: int, rng: int) -> void:
	var age: int = cfg.bubble_ticks - bubble_before + 1
	var cycle_ticks: int = _original_ticks(16, cfg)
	var original_phase: int = ((age * 16 + cycle_ticks - 1) / cycle_ticks) % 16
	var wave_units: int = original_phase - 4 \
		if original_phase < 8 else 12 - original_phase
	# 原作0x7B20は共通乱数%5-2。現tickの同期rngへactorを混ぜ、
	# 状態を追加消費せず4人の泡を決定論的に分離する。
	var scatter: int = ((rng + actor * 17) & 0xFFFF) % 5 - 2
	p.x = clampi(p.x + original_vx(wave_units + scatter, cfg),
		0, cfg.court_width)
	p.y -= original_vy(8, cfg)
	if p.y < 0:
		p.y = 0
		p.bubble_ticks = 0
	if p.bubble_ticks == 0:
		p.vx = 0
		p.vy = 0
		p.on_ground = 0
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1

static func _original_ticks(original_tick_count: int, cfg) -> int:
	var numerator: int = original_tick_count * cfg.tick_rate * 1000
	return (numerator + cfg.original_tick_rate_milli / 2) \
		/ cfg.original_tick_rate_milli

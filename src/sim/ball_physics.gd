# int演算のみ。球単体の移動、壁、ネット、自由球減衰を扱う。
extends RefCounted

const SimStateScript := preload("res://src/sim/sim_state.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const PossessionTracker := preload("res://src/sim/possession_tracker.gd")
const LOOSE_BOUNCE_PCT := 50   # ポーズ中の床バウンド反発%(勢い半分で早く落ち着く)

class _BallProbe:
	var ball_x: int = 0
	var ball_y: int = 0
	var ball_vx: int = 0
	var ball_vy: int = 0
	var ball_spin: int = 0
	var ball_power: int = 0
	var ball_attack_kind: int = 0
	var ball_guard_damage: int = 0
	var ball_defense_class: int = 0
	var ball_ghost: int = 0
	var ball_flame: int = 0
	var touches: int = 0
	var serve_flight: int = 0
	var last_touch_team: int = -1
	var ball_attack_id: int = 0
	var ball_last_contact_id: int = 0
	var ball_attacker_id: int = -1
	var ball_attack_commit_tick: int = -1
	var ball_normal_gain_granted: int = 0
	var ball_original_attack_pressure_consumed: int = 0
	var ball_soft_block_action_id: int = 0

static func wall_reflect_vx(vx: int, cfg) -> int:
	return -vx * cfg.wall_bounce_num / cfg.ball_bounce_den

static func predict_first_floor_x(s, cfg, max_ticks: int = 240) -> int:
	var probe := _BallProbe.new()
	probe.ball_x = s.ball_x
	probe.ball_y = s.ball_y
	probe.ball_vx = s.ball_vx
	probe.ball_vy = s.ball_vy
	probe.ball_spin = s.ball_spin
	probe.ball_power = s.ball_power
	probe.ball_attack_kind = s.ball_attack_kind
	probe.ball_guard_damage = s.ball_guard_damage
	probe.ball_defense_class = s.ball_defense_class
	probe.ball_ghost = s.ball_ghost
	probe.ball_flame = s.ball_flame
	probe.touches = s.touches
	probe.serve_flight = s.serve_flight
	probe.last_touch_team = s.last_touch_team
	probe.ball_attack_id = s.ball_attack_id
	probe.ball_last_contact_id = s.ball_last_contact_id
	probe.ball_attacker_id = s.ball_attacker_id
	probe.ball_attack_commit_tick = s.ball_attack_commit_tick
	probe.ball_normal_gain_granted = s.ball_normal_gain_granted
	probe.ball_original_attack_pressure_consumed = \
		s.ball_original_attack_pressure_consumed
	probe.ball_soft_block_action_id = s.ball_soft_block_action_id
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	for _tick in max_ticks:
		_step_ball(probe, cfg)
		if probe.ball_y >= floor_limit and probe.ball_vy > 0:
			return probe.ball_x
	return -1

static func normal_attack_reaches_opponent_playable(s, cfg, attacker_team: int,
		max_ticks: int = 240) -> bool:
	if s.ball_attack_kind != SimStateScript.BALL_ATTACK_NORMAL:
		return false
	var probe := _BallProbe.new()
	probe.ball_x = s.ball_x
	probe.ball_y = s.ball_y
	probe.ball_vx = s.ball_vx
	probe.ball_vy = s.ball_vy
	probe.ball_spin = s.ball_spin
	probe.ball_power = s.ball_power
	probe.ball_attack_kind = s.ball_attack_kind
	probe.ball_guard_damage = s.ball_guard_damage
	probe.ball_defense_class = s.ball_defense_class
	probe.ball_ghost = s.ball_ghost
	probe.ball_flame = s.ball_flame
	probe.touches = s.touches
	probe.serve_flight = s.serve_flight
	probe.last_touch_team = s.last_touch_team
	probe.ball_attack_id = s.ball_attack_id
	probe.ball_last_contact_id = s.ball_last_contact_id
	probe.ball_attacker_id = s.ball_attacker_id
	probe.ball_attack_commit_tick = s.ball_attack_commit_tick
	probe.ball_normal_gain_granted = s.ball_normal_gain_granted
	probe.ball_original_attack_pressure_consumed = \
		s.ball_original_attack_pressure_consumed
	probe.ball_soft_block_action_id = s.ball_soft_block_action_id
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	for _tick in max_ticks:
		_step_ball(probe, cfg)
		if probe.ball_attack_kind != SimStateScript.BALL_ATTACK_NORMAL:
			return false
		if probe.ball_y >= floor_limit and probe.ball_vy > 0:
			var landing_team: int = 0 if probe.ball_x < cfg.net_x else 1
			return landing_team != attacker_team
	return false

static func _clear_attack_effect(s) -> void:
	s.ball_attack_kind = SimStateScript.BALL_ATTACK_NONE
	s.ball_guard_damage = 0
	s.ball_attack_id = 0
	s.ball_last_contact_id = 0
	s.ball_attacker_id = -1
	s.ball_attack_commit_tick = -1
	s.ball_normal_gain_granted = 0
	s.ball_original_attack_pressure_consumed = 0
	s.ball_soft_block_action_id = 0

static func _step_ball(s, cfg, inputs: Array[int] = []) -> void:
	var prev_x: int = s.ball_x
	var prev_y: int = s.ball_y
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	# 回転は横の勢いに比例して累積する(真上のトスはほぼ無回転、前へ飛ぶほど回る)
	s.ball_spin += s.ball_vx
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	var hit_wall := false
	if s.ball_x < left:
		s.ball_x = left + (left - s.ball_x)
		s.ball_vx = wall_reflect_vx(s.ball_vx, cfg)
		hit_wall = true
	elif s.ball_x > right:
		s.ball_x = right - (s.ball_x - right)
		s.ball_vx = wall_reflect_vx(s.ball_vx, cfg)
		hit_wall = true
	if hit_wall and s.ball_power == 1:
		s.ball_vy = s.ball_vy * cfg.wall_bounce_num / cfg.ball_bounce_den
		s.ball_power = 0
	if hit_wall:
		s.ball_flame = 0
		_clear_attack_effect(s)
		if s.ball_defense_class != 0:
			s.ball_defense_class = 0
	# 床の反射はしない。RALLY中の床接触は_check_floor_pointが得点として処理する。
	# 天井の反射もしない(原作準拠): ボールは画面上端を突き抜けて出てよい。重力で必ず
	# 戻るため見失わない。跳ね返るのは左右の壁だけ。
	_ball_vs_net(s, cfg, prev_x, prev_y)

static func _step_ball_loose(s, cfg) -> void:
	# ポーズ中・勝敗確定後のボール。得点処理はせず、床で減衰バウンドして転がる
	_step_ball(s, cfg)
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	if s.ball_y > floor_limit:
		s.ball_y = floor_limit - (s.ball_y - floor_limit)
		if s.ball_vy > 0:
			# 床バウンドは勢い半分(原作の「着地したら死ぬ球」の感触に寄せた減衰)
			s.ball_vy = -s.ball_vy * LOOSE_BOUNCE_PCT / 100
			# 乗算減衰だけだと閾値近傍で微小バウンドが長く続く速度帯がある(共振、
			# レビュー指摘: 特定入射で数千tick跳ね続けた)。反発のたびに固定量も
			# 減衰させ、有限バウンド回数で必ず閾値を割らせる
			s.ball_vy = mini(s.ball_vy + cfg.ball_rest_speed / 4, 0)
		# 床接触のたびに横速度も減衰(転がって自然に止まる)
		s.ball_vx = s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		# 微小な跳ね/転がりは静止させ床にスナップ(小刻みな跳ねの継続を断つ)
		if absi(s.ball_vy) < cfg.ball_rest_speed:
			s.ball_vy = 0
			s.ball_y = floor_limit
		if absi(s.ball_vx) < cfg.ball_rest_speed:
			s.ball_vx = 0

static func _ball_vs_net(s, cfg, prev_x: int, prev_y: int) -> void:
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	var net_right: int = cfg.net_x + cfg.net_half_w + cfg.ball_radius
	var was_left: bool = prev_x < cfg.net_x
	var is_left: bool = s.ball_x < cfg.net_x
	var move_x: int = s.ball_x - prev_x
	var move_y: int = s.ball_y - prev_y
	var hits_net_side := false
	if move_x == 0:
		# 垂直移動は補間せず、帯内で経路の下端が上端を越えたかを見る。
		hits_net_side = s.ball_x >= net_left and s.ball_x <= net_right \
			and maxi(prev_y, s.ball_y) > cfg.net_top_y
	else:
		# 水平移動距離を分母とし、帯と重なる線分上で最も下側のyを整数補間する。
		var travel: int = absi(move_x)
		var enter_dist: int
		var exit_dist: int
		if move_x > 0:
			enter_dist = maxi(net_left - prev_x, 0)
			exit_dist = mini(net_right - prev_x, travel)
		else:
			enter_dist = maxi(prev_x - net_right, 0)
			exit_dist = mini(prev_x - net_left, travel)
		if enter_dist <= exit_dist:
			var probe_dist: int = exit_dist if move_y > 0 else enter_dist
			var probe_y: int = prev_y + move_y * probe_dist / travel
			hits_net_side = probe_y > cfg.net_top_y
	if hits_net_side:
		# ネット下部は壁。来た側へ押し返す
		s.ball_flame = 0
		_clear_attack_effect(s)
		if s.ball_defense_class != 0:
			s.ball_defense_class = 0
		# 減衰反射しつつ最低反発速度を保証(ネットに当たったら必ず少し跳ね返る)
		if was_left:
			s.ball_x = net_left - (s.ball_x - net_left)
			if s.ball_vx > 0:
				s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
			s.ball_vx = mini(s.ball_vx, -cfg.net_repel)
		else:
			s.ball_x = net_right + (net_right - s.ball_x)
			if s.ball_vx < 0:
				s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
			s.ball_vx = maxi(s.ball_vx, cfg.net_repel)
	elif s.ball_vy > 0 \
			and s.ball_x >= net_left and s.ball_x <= net_right \
			and s.ball_y >= cfg.net_top_y - cfg.ball_radius:
		# 原作式ネットイン: 上端(白帯)に当たると縦の勢いが半減して跳ね、
		# ネットから離れる向きへ押し出される=ポトリと落ちる緊張感
		s.ball_y = cfg.net_top_y - cfg.ball_radius
		s.ball_flame = 0
		_clear_attack_effect(s)
		if s.ball_defense_class != 0:
			s.ball_defense_class = 0
		s.ball_vy = -s.ball_vy / 2
		var out_dir: int = -1 if is_left else 1
		if s.ball_vx * out_dir < cfg.net_repel / 2:
			s.ball_vx = out_dir * cfg.net_repel / 2
	is_left = s.ball_x < cfg.net_x
	if was_left != is_left:
		# ネットを越えた: 高さにかかわらず攻守交代。実衝突で跳ね返った球は
		# ball_xが来た側へ戻されているため、この条件には入らない。
		var entered_team: int = 0 if is_left else 1
		if s.has_method("alloc_possession_id") \
				and s.possession_id != 0 and entered_team != s.possession_team:
			PossessionTracker.resolve_opponent_transfer(
				s, s.possession_team, cfg)
		s.touches = 0
		s.serve_flight = 0
		if s.has_method("alloc_attack_id"):
			for i in s.players.size():
				if SimStateScript.team_of(i) == entered_team:
					CombatResources.stop_attack_recovery(s.players[i])
		_clear_ghost_on_opponent_entry(s, is_left)

static func _clear_ghost_on_opponent_entry(s, is_left: bool) -> void:
	var entered_team: int = 0 if is_left else 1
	if s.ball_ghost == 1 and s.last_touch_team >= 0 and entered_team != s.last_touch_team:
		s.ball_ghost = 0
		s.ball_guard_damage = 0
		s.ball_defense_class = 0

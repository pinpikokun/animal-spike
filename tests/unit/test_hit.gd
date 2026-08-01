extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const Chars := preload("res://src/sim/chars.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const STANDARD_CHAR := 99
const SPIKE_SAMPLE_STEP_PX := 20
const SPIKE_NEAREST_D_PX := 30
const SPIKE_FARTHEST_D_PX := 270
const SPIKE_SAMPLE_HEIGHTS_PX: Array[int] = [80, 140]

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.char_id = STANDARD_CHAR
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = cfg.net_x - FP.from_int(124)
	s.players[1].x = cfg.net_x - FP.from_int(49)
	s.players[2].x = cfg.net_x + FP.from_int(156)
	s.players[3].x = cfg.net_x + FP.from_int(46)
	return [s, cfg]

func _config_with_standard_toss_speed(speed_px_s: int):
	var source := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(source.get_as_text())
	raw["ally_ground_toss_up_px_s"] = speed_px_s
	var path := "user://test_standard_ground_toss_rules.json"
	var custom := FileAccess.open(path, FileAccess.WRITE)
	custom.store_string(JSON.stringify(raw))
	custom.close()
	var cfg = SimConfig.new(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return cfg

func _normal_spike_vx(team: int, relative_hdir: int,
		distance_px: int, height_px: int) -> int:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var actor: int = team * 2
	var dir: int = SimState._dir_of_team(team)
	var p = s.players[actor]
	p.on_ground = 0
	s.ball_x = cfg.net_x - dir * FP.from_int(distance_px)
	s.ball_y = cfg.floor_y - FP.from_int(height_px)
	p.x = s.ball_x
	p.y = s.ball_y + cfg.player_reach
	s.ball_vx = 0
	s.ball_vy = 0
	var hdir: int = relative_hdir * dir
	var input: int = Simulation.IN_ACTION | Simulation.IN_DOWN
	if hdir < 0:
		input |= Simulation.IN_LEFT
	elif hdir > 0:
		input |= Simulation.IN_RIGHT
	HitResolver._apply_hit(
		s, actor, cfg, input, cfg.player_reach * cfg.player_reach)
	return s.ball_vx

func _preview_air_spike_world(team: int) -> Array:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var actor: int = team * 2
	var p = s.players[actor]
	p.on_ground = 0
	p.x = cfg.net_x - SimState._dir_of_team(team) * FP.from_int(48)
	p.y = cfg.net_top_y - FP.from_int(48)
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg, actor]

func _air_spike_input(team: int, relative_hdir: int) -> int:
	var input: int = Simulation.IN_ACTION | Simulation.IN_DOWN
	var hdir: int = relative_hdir * SimState._dir_of_team(team)
	if hdir < 0:
		input |= Simulation.IN_LEFT
	elif hdir > 0:
		input |= Simulation.IN_RIGHT
	return input

func _air_spike_input_with_vertical(
		team: int, relative_hdir: int, vertical: int) -> int:
	return (_air_spike_input(team, relative_hdir) & ~Simulation.IN_DOWN) | vertical

func _block_input(team: int) -> int:
	return Simulation.IN_ACTION | (Simulation.IN_RIGHT if team == 0 \
		else Simulation.IN_LEFT)

func test_up_attack_matches_nonjust_down_in_preview_and_apply() -> void:
	for team in 2:
		for relative_hdir in [-1, 0, 1]:
			var safe_world := _preview_air_spike_world(team)
			var safe_state = safe_world[0]
			var cfg = safe_world[1]
			var actor: int = safe_world[2]
			var safe_input: int = _air_spike_input_with_vertical(
				team, relative_hdir, Simulation.IN_UP)
			var wager_input: int = _air_spike_input_with_vertical(
				team, relative_hdir, Simulation.IN_DOWN)
			var safe_preview: Vector2i = HitResolver.preview_air_spike_velocity(
				safe_state, actor, cfg, safe_input, 0)
			var normal_preview: Vector2i = HitResolver.preview_air_spike_velocity(
				safe_state, actor, cfg, wager_input,
				cfg.player_reach * cfg.player_reach)
			check_eq(safe_preview, normal_preview,
				"上と非ジャスト下の予測速度一致 team=%d dir=%d" % [
					team, relative_hdir])
			HitResolver._apply_hit(safe_state, actor, cfg, safe_input, 0)
			var wager_world := _preview_air_spike_world(team)
			var wager_state = wager_world[0]
			HitResolver._apply_hit(wager_state, actor, cfg, wager_input,
				cfg.player_reach * cfg.player_reach)
			check_eq(Vector2i(safe_state.ball_vx, safe_state.ball_vy),
				Vector2i(wager_state.ball_vx, wager_state.ball_vy),
				"上と非ジャスト下の実打球速度一致 team=%d dir=%d" % [
					team, relative_hdir])
			check_eq(safe_state.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
				"上は芯でも通常属性")
			check_eq(safe_state.ball_power, 0, "上は芯でもパワー球にしない")

func test_preview_air_spike_velocity_matches_fixed_normal_values() -> void:
	for team in 2:
		var w := _preview_air_spike_world(team)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var dir: int = SimState._dir_of_team(team)
		var d2: int = cfg.player_reach * cfg.player_reach
		var pct: int = cfg.spike_normal_pct
		var rows: Array[Array] = [
			[-1, dir * cfg.spike_steep_vx * pct / 100,
				cfg.spike_steep_vy * pct / 100],
			[0, dir * cfg.spike_mid_vx * pct / 100,
				(cfg.spike_steep_vy + cfg.spike_vy) * pct / 200],
			[1, dir * cfg.spike_vx * pct / 100,
				cfg.spike_vy * pct / 100],
		]
		for row in rows:
			var before: Array[int] = s.to_int_array()
			var actual: Vector2i = HitResolver.preview_air_spike_velocity(
				s, actor, cfg, _air_spike_input(team, row[0]), d2)
			check_eq(actual, Vector2i(row[1], row[2]),
				"通常空中打撃の固定速度 team=%d direction=%d" % [team, row[0]])
			check_eq(s.to_int_array(), before, "速度予測は同期状態を変更しない")

func test_preview_air_spike_velocity_applies_sweet_and_inertia() -> void:
	var w := _preview_air_spike_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var p = s.players[actor]
	s.ball_vx = cfg.inertia_min_speed * 2
	s.ball_vy = -cfg.inertia_min_speed
	var pct: int = cfg.spike_power_pct \
		* Chars.stat(p.char_id, "just_reward") / 100
	pct = pct * Chars.stat(p.char_id, "atk") / 100
	var inertia: int = cfg.hit_inertia_just_num \
		* (200 - Chars.stat(p.char_id, "absorb")) / 100
	var expected := Vector2i(
		cfg.spike_mid_vx * pct / 100 \
			- s.ball_vx * inertia / cfg.hit_inertia_den,
		(cfg.spike_steep_vy + cfg.spike_vy) * pct / 200 \
			- s.ball_vy * inertia / cfg.hit_inertia_den)
	var actual: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, _air_spike_input(0, 0), 0)
	check_eq(actual, expected, "ジャスト倍率と入射慣性を順番どおり適用")

func test_preview_air_spike_velocity_serve_ignores_inertia() -> void:
	var w := _preview_air_spike_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	s.phase = SimState.PHASE_SERVE
	s.serve_tossed = 1
	s.serving_team = 0
	s.ball_vx = cfg.inertia_min_speed * 3
	s.ball_vy = cfg.inertia_min_speed * 2
	var pct: int = cfg.spike_normal_pct
	var expected := Vector2i(
		cfg.spike_vx * pct / 100,
		cfg.spike_vy * pct / 100)
	var actual: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, _air_spike_input(0, 1),
		cfg.player_reach * cfg.player_reach)
	check_eq(actual, expected, "サーブ打撃は入射慣性をゼロにする")

func test_preview_air_spike_velocity_mangles_opponent_power_ball() -> void:
	var w := _preview_air_spike_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_vx = cfg.inertia_min_speed * 2
	s.ball_vy = cfg.inertia_min_speed
	var pct: int = cfg.spike_normal_pct
	var expected := Vector2i(
		cfg.spike_mid_vx * pct / 100 * HitResolver.MANGLE_AIM_PCT / 100 \
			- s.ball_vx,
		(cfg.spike_steep_vy + cfg.spike_vy) * pct / 200 \
			* HitResolver.MANGLE_AIM_PCT / 100 - s.ball_vy)
	var actual: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, _air_spike_input(0, 0),
		cfg.player_reach * cfg.player_reach)
	check_eq(actual, expected, "相手パワー球の芯外しは狙い30%と全反射")

func test_preview_air_spike_velocity_applies_attack_and_mura_once() -> void:
	var w := _preview_air_spike_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var p = s.players[actor]
	p.char_id = Chars.CHAR_PANDA
	s.aitick = 0xABCD
	check_eq(HitResolver._mura_power_pct(s, actor, p.char_id), 150,
		"固定aitickはむらっけ150%側")
	var pct: int = cfg.spike_normal_pct * Chars.stat(p.char_id, "atk") / 100
	pct = pct * 150 / 100
	var expected := Vector2i(
		cfg.spike_mid_vx * pct / 100,
		(cfg.spike_steep_vy + cfg.spike_vy) * pct / 200)
	var actual: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, _air_spike_input(0, 0),
		cfg.player_reach * cfg.player_reach)
	check_eq(actual, expected, "攻撃値とむらっけを最終倍率へ一度だけ適用")

func test_air_spike_application_matches_preview_velocity() -> void:
	for mode in ["normal", "sweet", "mangled"]:
		var w := _preview_air_spike_world(0)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var d2: int = cfg.player_reach * cfg.player_reach
		s.ball_vx = cfg.inertia_min_speed * 2
		s.ball_vy = -cfg.inertia_min_speed
		if mode == "sweet":
			d2 = 0
		elif mode == "mangled":
			s.last_touch_team = 1
			s.ball_power = 1
		var input: int = _air_spike_input(0, 1)
		var expected: Vector2i = HitResolver.preview_air_spike_velocity(
			s, actor, cfg, input, d2)
		HitResolver._apply_hit(s, actor, cfg, input, d2)
		check_eq(Vector2i(s.ball_vx, s.ball_vy), expected,
			"実打球は速度予測と一致: " + mode)

func test_tome_ghost_ball_matches_plain_up_toss_trajectory() -> void:
	var normal := _rally_world()
	var ghost := _rally_world()
	for w in [normal, ghost]:
		w[0].players[0].char_id = Chars.CHAR_TOME
		w[0].players[0].drive_gauge = w[1].drive_gauge_max
		w[0].ball_x = w[0].players[0].x + FP.from_int(5)
		w[0].ball_y = w[1].floor_y - FP.from_int(10)
	Simulation.step(normal[0], [Simulation.IN_ACTION, 0, 0, 0], normal[1])
	Simulation.step(ghost[0], [Simulation.IN_ABILITY1 | Simulation.IN_JUMP |
		Simulation.IN_UP, 0, 0, 0], ghost[1])
	check_eq(ghost[0].ball_ghost, 1, "地上の上+Dでゴーストボール")
	check_eq(ghost[0].players[0].on_ground, 1, "Dを技モディファイアとして押す間は跳ばない")
	check_eq(ghost[0].ball_vx, normal[0].ball_vx, "通常ニュートラルトスと横軌道が同一")
	check_eq(ghost[0].ball_vy, normal[0].ball_vy, "通常ニュートラルトスと縦軌道が同一")
	check_eq(ghost[0].players[0].drive_gauge, ghost[1].drive_gauge_max - 1000,
		"ゴーストボールはゲージ1本消費")
	check_eq(ghost[0].ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"必殺技は相手ドライブを削らない")

func test_up_without_ability_still_jumps() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "D無しの上入力は従来どおりジャンプ")

func test_ghost_ball_clears_after_crossing_to_opponent_court() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_ghost = 1
	s.last_touch_team = 0
	s.ball_x = cfg.net_x - FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(30)
	s.ball_vx = FP.from_int(3)
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_ghost, 0, "相手コートへ渡ったゴースト表示は解除")

func test_tome_flame_attack_requires_high_air_down_ability() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.char_id = Chars.CHAR_TOME
	p.drive_gauge = cfg.drive_gauge_max
	p.on_ground = 0
	p.y = cfg.net_top_y - FP.from_int(1)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ABILITY1 | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 1, "高所の下+Dはパワーボール")
	check_eq(s.ball_flame, 1, "高所の下+Dは燃えるアタック")

	check_eq(s.ball_guard_damage, 40, "カタログ固定威力40を記録")
	check_eq(s.ball_defense_class, Chars.DEFENSE_UNBLOCKABLE,
		"防御不能分類を飛来球へ記録")
	check_eq(p.drive_gauge, cfg.drive_gauge_max - 3000,
		"殺人燃えるアタックはゲージ3本消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"必殺技は相手ドライブを削らない")

func test_flame_super_spends_all_remaining_drive_and_starts_burnout() -> void:
	var w := _rally_world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.char_id = Chars.CHAR_TOME
	p.drive_gauge = 2999
	p.on_ground = 0
	p.y = cfg.net_top_y - FP.from_int(1)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_ABILITY1 | Simulation.IN_DOWN, 0)
	check_eq(s.ball_flame, 1, "残量が1以上なら3本未満でも必殺技になる")
	check_eq(s.ball_guard_damage, 40, "使い切り発動でも固定威力40")
	check_eq(p.drive_gauge, 0, "不足分を問わず残量を全消費")
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks, "使い切ってバーンアウト突入")

func test_flame_super_at_zero_drive_falls_back_to_normal_spike() -> void:
	var w := _rally_world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.char_id = Chars.CHAR_TOME
	p.drive_gauge = 0
	p.on_ground = 0
	p.y = cfg.net_top_y - FP.from_int(1)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_ABILITY1 | Simulation.IN_DOWN, 0)
	check_eq(s.ball_flame, 0, "ゲージ0では必殺技にならない")
	check_eq(s.ball_guard_damage, 25, "通常ジャストスパイクへフォールバック")

func test_tome_flame_input_below_net_top_stays_normal_spike() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.char_id = Chars.CHAR_TOME
	p.on_ground = 0
	p.y = cfg.net_top_y
	s.ball_x = p.x + FP.from_int(30)
	s.ball_y = p.y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_ABILITY1 | Simulation.IN_DOWN,
		0, 0, 0], cfg)
	check_eq(s.touches, 1, "高度不足でも通常アタック入力は維持")
	check_eq(s.ball_flame, 0, "ネット上端以下では炎にならない")
	check_eq(s.ball_power, 0, "スイート外の通常アタックのまま")

func test_non_tome_ability_input_does_not_hit() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].char_id = Chars.CHAR_FOX
	s.ball_x = s.players[0].x + FP.from_int(2)
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ABILITY1 | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "必殺技未定義キャラのDは何も起こさない")
	check_eq(s.ball_ghost, 0, "必殺技未定義キャラはゴースト化しない")

func test_tome_ability_input_out_of_range_does_nothing() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].char_id = Chars.CHAR_TOME
	s.ball_x = s.players[0].x + cfg.player_reach * 2
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ABILITY1 | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "打球圏外のDは空振りしない")
	check_eq(s.ball_ghost, 0, "打球圏外ではゴースト化しない")

func test_flame_receive_deals_catalog_fixed_guard_damage() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_power = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_flame = 1
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 60,
		"燃える球のレシーブはカタログ固定40ダメージ")
	check_eq(s.players[0].flinch, 0, "炎上専用の行動不能が通常しりもちを置き換える")
	check_eq(s.players[0].burn, cfg.burn_stun_ticks, "炎被弾で90tick行動不能")
	check_eq(s.ball_flame, 0, "レシーブで炎球効果を消費")

func test_just_receive_cannot_cancel_flame_guard_damage() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].receive_stance = 1
	s.players[0].drive_gauge = cfg.drive_gauge_max
	s.ball_power = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_flame = 1
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(2)
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 60,
		"防御不能系は芯でレシーブしても固定40ダメージ")
	check_eq(s.players[0].burn, cfg.burn_stun_ticks, "芯受けでも90tick行動不能")
	check_eq(s.ball_flame, 0, "芯レシーブでも炎球効果を消費")
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.players[0].burn, cfg.burn_stun_ticks - 1, "炎上残り時間は毎tick減衰")

func test_flame_block_deals_catalog_fixed_guard_damage() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_flame = 1
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	Simulation.step(s, [_block_input(0), 0, 0, 0], cfg)
	check_eq(p.guard, 60,
		"燃える球のブロックはカタログ固定40ダメージ")
	check_eq(p.burn, cfg.burn_stun_ticks, "炎球ブロックでも90tick行動不能")
	check_eq(s.ball_flame, 0, "ブロック接触でも炎球効果を消費")

func test_flame_friendly_touch_damages_burns_and_consumes_flame() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var teammate = s.players[1]
	s.last_touch_team = 0
	s.ball_power = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_flame = 1
	s.ball_x = teammate.x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [0, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(teammate.guard, 60, "味方の炎球でもカタログ固定40ダメージ")
	check_eq(teammate.burn, cfg.burn_stun_ticks, "味方の炎球でも90tick行動不能")
	check_eq(s.ball_flame, 0, "味方接触で炎球効果を消費")

func test_air_attack_return_clears_flame_and_power() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.guard = 40
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_flame = 1
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_flame, 0, "アタックで燃える効果を解除")
	check_eq(s.ball_power, 0, "アタック返しは通常球へ戻る")
	check_eq(p.guard, 40, "アタック返しはガード無傷かつ回復もしない")
	check_eq(p.burn, 0, "アタック返しした本人は燃えない")

func test_flame_ball_wall_contact_consumes_flame_without_damage() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_flame = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_guard_damage = 25
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(30)
	s.ball_vx = -FP.from_int(5)
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_flame, 0, "壁接触で炎球効果を消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"壁接触でアタック種別を消去")
	check_eq(s.ball_guard_damage, 0, "壁接触でアタックのガード削り値を消去")
	for p in s.players:
		check_eq(p.guard, 100, "壁接触ではガードダメージなし")

func test_flame_ball_net_contact_consumes_flame() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_flame = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_guard_damage = 25
	s.ball_x = cfg.net_x - cfg.net_half_w - cfg.ball_radius - FP.from_int(1)
	s.ball_y = cfg.net_top_y + FP.from_int(20)
	s.ball_vx = FP.from_int(4)
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_flame, 0, "ネット側面接触で炎球効果を消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"ネット側面接触でアタック種別を消去")
	check_eq(s.ball_guard_damage, 0, "ネット側面接触でガード削り値を消去")

func test_flame_ball_net_top_contact_consumes_flame() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_flame = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_guard_damage = 25
	s.ball_x = cfg.net_x
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(4)
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_flame, 0, "ネット上端接触で炎球効果を消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"ネット上端接触でアタック種別を消去")
	check_eq(s.ball_guard_damage, 0, "ネット上端接触でガード削り値を消去")

func test_wall_softened_attack_neither_drains_drive_nor_triggers_just_receive() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 3000
	p.receive_stance = cfg.just_receive_window_ticks
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_guard_damage = 25
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(30)
	s.ball_vx = -FP.from_int(5)
	BallPhysics._step_ball(s, cfg)
	HitResolver._apply_hit(
		s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.drive_gauge, 3000, "壁で弱った球のレシーブはドライブを削らない")
	check_eq(p.just_receive_event, 0, "壁で弱った球にはジャストレシーブが成立しない")

func test_unimpeded_attack_still_drains_drive_on_receive() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 3000
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	HitResolver._apply_hit(
		s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.drive_gauge, 2000, "何にも当たっていない通常アタックは従来どおり1本削る")

func test_bump_on_ground() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(3)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "バンプでボールが上昇する")
	check(s.ball_vx > 0, "左チームのバンプは右向き成分")
	check_eq(s.touches, 1, "タッチ数1")
	check_eq(s.last_touch_team, 0, "最終タッチは左チーム")
	check(s.players[0].hit_cooldown > 0, "クールダウン開始")

func _ground_receive_vx(offset_px: int, input: int = 0, aitick: int = 0) -> int:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.aitick = aitick
	s.ball_x = s.players[0].x + FP.from_int(offset_px)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN | input, 0)
	return s.ball_vx

func test_ground_receive_vx_follows_contact_offset_sign() -> void:
	check(_ground_receive_vx(40) > 0, "右で捉えたレシーブは右へ返る")
	check(_ground_receive_vx(-40) < 0, "左で捉えたレシーブは左へ返る")
	check(absi(_ground_receive_vx(0)) <= FP.from_int(12) / 60,
		"中心で捉えたレシーブは散り幅内でほぼ真上へ返る")

func test_ground_receive_vx_is_clamped() -> void:
	var cfg = SimConfig.new()
	check(absi(_ground_receive_vx(200, Simulation.IN_RIGHT)) <= cfg.receive_vx_max,
		"右端を越える接触と右操舵でも横速度上限を超えない")
	check(absi(_ground_receive_vx(-200, Simulation.IN_LEFT)) <= cfg.receive_vx_max,
		"左端を越える接触と左操舵でも横速度上限を超えない")

func test_ground_receive_scatter_is_deterministic() -> void:
	check_eq(_ground_receive_vx(0, 0, 137), _ground_receive_vx(0, 0, 137),
		"同じaitick・actor・入力のレシーブ散りは同じ値になる")
	check(_ground_receive_vx(0, 0, 0) != _ground_receive_vx(0, 0, 137),
		"通常レシーブはaitickに応じた散りを残す")

func test_ground_receive_has_no_forward_bias() -> void:
	var cfg = SimConfig.new()
	var vx: int = _ground_receive_vx(0, 0, 0)
	check(absi(vx) <= cfg.receive_scatter,
		"中心接触・入射なしの横速度は固定前方値でなく散り幅内に収まる")

func test_neutral_receive_uses_normal_receive_height() -> void:
	# 下+アクションは通常レシーブ。トスとは独立した専用高度を使う。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_vy, -cfg.normal_receive_up + cfg.gravity,
		"ニュートラルレシーブのvyは通常レシーブ専用高度で跳ねる")

func test_neutral_receive_reflects_vertical_inertia() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(12)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(-s.ball_vy > cfg.normal_receive_up - cfg.gravity,
		"落下球のニュートラルレシーブは縦の勢いも跳ね返す: actual=%d base=%d" % [
			-s.ball_vy, cfg.normal_receive_up - cfg.gravity])

func test_normal_receive_uses_dedicated_600_speed() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x
	s.ball_y = s.players[0].y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(s.ball_vy, -cfg.normal_receive_up,
		"通常レシーブは専用の600px/sで上げる")

func test_just_receive_uses_680_speed_without_vertical_inertia_or_scatter() -> void:
	var results: Array[Vector2i] = []
	for row in [[0, 0], [137, FP.from_int(20)]]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.receive_stance = cfg.just_receive_window_ticks
		s.last_touch_team = 1
		s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
		s.ball_x = p.x + FP.from_int(8)
		s.ball_y = p.y - FP.from_int(10)
		s.ball_vx = 0
		s.ball_vy = row[1]
		s.aitick = row[0]
		HitResolver._apply_hit(s, 0, cfg,
			Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
		check_eq(s.ball_vy, -cfg.just_receive_up,
			"ジャストレシーブは入射縦速度にかかわらず680px/s")
		results.append(Vector2i(s.ball_vx, s.ball_vy))
	check_eq(results[0], results[1],
		"ジャストレシーブは乱数散りを使わず接触位置だけで決まる")
	check(results[0].x > 0, "ジャストレシーブも右側接触の決定的な横成分は残す")

func test_neutral_ground_toss_targets_own_front() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "ニュートラルトスは自陣前方へ進む")
	check(s.ball_vy < 0, "ニュートラルトスは上向き")

func test_early_standard_ground_toss_uses_initial_height_for_both_teams() -> void:
	for row in [[0, 0], [0, 1], [2, 0], [2, 1]]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var actor: int = row[0]
		var touches_before: int = row[1]
		var team: int = actor / 2
		var p = s.players[actor]
		s.last_touch_team = team if touches_before > 0 else 1 - team
		s.touches = touches_before
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		HitResolver._apply_hit(s, actor, cfg, Simulation.IN_ACTION, 0)
		check_eq(s.ball_vy, -FP.from_int(680) / 60,
			"両チームの1・2打目標準トスは680px/s: %s" % [row])

func test_standard_ground_toss_has_same_height_for_every_toss_trait() -> void:
	var actual: Array[int] = []
	for char_id in [Chars.CHAR_MARIO, Chars.CHAR_FOX, Chars.CHAR_PANDA]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		s.players[0].char_id = char_id
		s.aitick = 0
		s.ball_x = s.players[0].x + FP.from_int(5)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
		actual.append(s.ball_vy)
	check_eq(actual, [
		-FP.from_int(680) / 60,
		-FP.from_int(680) / 60,
		-FP.from_int(680) / 60,
	], "標準トスの高さにトス能力差を付けない")

func test_standard_ground_toss_real_trajectory_matches_playtest_baseline() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = HitResolver.toss_target_x(0, 0, cfg)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	var start_y: int = s.ball_y
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
	var min_y: int = s.ball_y
	var rising_ticks: int = 0
	while s.ball_vy < 0:
		BallPhysics._step_ball(s, cfg)
		min_y = mini(min_y, s.ball_y)
		rising_ticks += 1
	var rise: int = start_y - min_y
	check_eq(rising_ticks, 36, "680px/s標準トスは36tick上昇")
	check(rise >= FP.from_int(195) and rise < FP.from_int(196),
		"680px/s標準トスの実上昇量は195px以上196px未満: %d" % rise)

func test_standard_ground_toss_follows_dedicated_config_override() -> void:
	var cfg = _config_with_standard_toss_speed(600)
	var w := _rally_world()
	var s = w[0]
	var p = s.players[0]
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
	check_eq(s.ball_vy, -FP.from_int(600) / 60,
		"味方地上標準トスだけが専用設定へ追従")

func test_standard_toss_override_does_not_change_third_ground_return() -> void:
	var cfg = _config_with_standard_toss_speed(600)
	var w := _rally_world()
	var s = w[0]
	var p = s.players[0]
	s.last_touch_team = 0
	s.touches = cfg.max_touches - 1
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
	check_eq(s.ball_vy, -cfg.bump_up_speed,
		"専用設定を変えても3打目地上返球は520px/s")

func test_standard_toss_override_does_not_change_ground_receive() -> void:
	var cfg = _config_with_standard_toss_speed(600)
	var w := _rally_world()
	var s = w[0]
	var p = s.players[0]
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	HitResolver._apply_hit(
		s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(s.ball_vy, -cfg.normal_receive_up,
		"標準トス設定を変えても通常レシーブは600px/s")

func test_mura_applies_to_normal_just_and_attack_serve() -> void:
	var aitick := 0xABCD
	var contract_world := _rally_world()
	var contract_state = contract_world[0]
	contract_state.aitick = aitick
	check_eq(HitResolver._trait_roll_pct(
		contract_state, 0, HitResolver.SALT_MURA), 96,
		"固定aitick=0xABCDはむらっけ150%側")
	check_eq(HitResolver._mura_power_pct(
		contract_state, 0, Chars.CHAR_PANDA), 150,
		"固定入力のむらっけ倍率は150%")
	for sweet in [false, true]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.char_id = Chars.CHAR_PANDA
		p.on_ground = 0
		s.aitick = aitick
		var d2: int = 0 if sweet else cfg.player_reach * cfg.player_reach
		HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, d2)
		# むらっけは通常/ジャスト共に最終pctへ1回だけ乗る。横速度は着地点から
		# 逆算される新体系では比例しないため、比例が保存される縦速度で検証する。
		var pct: int = cfg.spike_power_pct if sweet else cfg.spike_normal_pct
		if sweet:
			pct = pct * Chars.stat(Chars.CHAR_PANDA, "just_reward") / 100
		pct = pct * Chars.stat(Chars.CHAR_PANDA, "atk") / 100
		pct = pct * 150 / 100
		check_eq(s.ball_vy, (cfg.spike_steep_vy + cfg.spike_vy) * pct / 200,
			"%sアタックへむらっけ最終倍率を一度だけ適用" %
			("ジャスト" if sweet else "通常"))
	var ws := _rally_world()
	var ss = ws[0]
	var cfgs = ws[1]
	ss.phase = SimState.PHASE_SERVE
	ss.serve_tossed = 1
	ss.aitick = aitick
	ss.players[0].char_id = Chars.CHAR_PANDA
	var safe_vx: int = HitResolver.opponent_return_vx(
		ss.ball_x, ss.ball_y, 0, 0, ss.players[0].char_id, cfgs)
	HitResolver._apply_hit(ss, 0, cfgs, Simulation.IN_ACTION | Simulation.IN_RIGHT, 0)
	check_eq(ss.ball_vx, safe_vx, "地上安全サーブはトス軌道で、むらっけを適用しない")
	var wa := _rally_world()
	var sa = wa[0]
	var cfga = wa[1]
	sa.phase = SimState.PHASE_SERVE
	sa.serve_tossed = 1
	sa.aitick = aitick
	sa.players[0].char_id = Chars.CHAR_PANDA
	sa.players[0].on_ground = 0
	HitResolver._apply_hit(sa, 0, cfga, Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfga.player_reach * cfga.player_reach)
	var serve_pct: int = cfga.spike_normal_pct
	serve_pct = serve_pct * Chars.stat(Chars.CHAR_PANDA, "atk") / 100
	serve_pct = serve_pct * 150 / 100
	check_eq(sa.ball_vy, (cfga.spike_steep_vy + cfga.spike_vy) * serve_pct / 200,
		"空中アタックサーブへむらっけ最終倍率を一度だけ適用")

func test_attack_speed_follows_rules_json_percentages() -> void:
	# 数値はバランス調整で動くのでテスト名や本文に埋めない。rules.jsonを唯一の出所とし、
	# 「設定どおりに適用されるか」と「ジャストが通常より速いか」だけを固定する。
	var outputs: Array[int] = []
	for sweet in [false, true]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.on_ground = 0
		p.y = cfg.floor_y - FP.from_int(60)
		s.ball_x = p.x
		s.ball_y = p.y
		HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN,
			0 if sweet else cfg.player_reach * cfg.player_reach)
		var expected_pct: int = cfg.spike_power_pct if sweet else cfg.spike_normal_pct
		var expected_vy: int = (cfg.spike_steep_vy + cfg.spike_vy) * expected_pct / 200
		check_eq(s.ball_vy, expected_vy,
			"%s速度倍率はrules.jsonの%d%%" %
			["ジャスト" if sweet else "通常", expected_pct])
		outputs.append(s.ball_vy)
	var live = SimConfig.new()
	check(live.spike_normal_pct > 0, "通常アタック倍率が正")
	check(live.spike_power_pct > live.spike_normal_pct,
		"ジャストは通常より速い(SimConfigの検証と同じ不変条件)")
	check(outputs[0] < outputs[1], "通常アタックはジャストアタックより遅い")

func test_receive_reach_is_trait_aware_only_for_receive_intent() -> void:
	var base := FP.from_int(40)
	check_eq(HitResolver.reach_for_intent(Chars.CHAR_MARIO, base,
		HitResolver.INTENT_GROUND_RECEIVE), base * 115 / 100, "レシーブ上手115%")
	check_eq(HitResolver.reach_for_intent(Chars.CHAR_FOX, base,
		HitResolver.INTENT_GROUND_RECEIVE), base, "レシーブ特性なし100%")
	check_eq(HitResolver.reach_for_intent(Chars.CHAR_PANDA, base,
		HitResolver.INTENT_GROUND_RECEIVE), base * 85 / 100, "レシーブ下手85%")
	for intent in [HitResolver.INTENT_GROUND_TOSS, HitResolver.INTENT_GROUND_FORWARD,
		HitResolver.INTENT_AIR_SPIKE, HitResolver.INTENT_AIR_TOSS_UP,
		HitResolver.INTENT_AIR_TOSS_SIDE, HitResolver.INTENT_AIR_FEINT]:
		check_eq(HitResolver.reach_for_intent(Chars.CHAR_MARIO, base, intent), base,
			"レシーブ以外のリーチは不変: %d" % intent)

func test_receive_reach_changes_actual_hit_detection() -> void:
	for row in [[Chars.CHAR_MARIO, 110, 1], [Chars.CHAR_FOX, 110, 0],
		[Chars.CHAR_FOX, 90, 1], [Chars.CHAR_PANDA, 90, 0]]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.char_id = row[0]
		s.ball_x = p.x + cfg.player_reach * row[1] / 100
		s.ball_y = p.y
		var result: int = HitResolver._resolve_hit(s,
			[Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
		check_eq(1 if result != HitResolver.NO_HIT else 0, row[2],
			"レシーブ実判定: %s" % [row])
	var wt := _rally_world()
	var st = wt[0]
	var cfgt = wt[1]
	st.players[0].char_id = Chars.CHAR_MARIO
	st.ball_x = st.players[0].x + cfgt.player_reach * 110 / 100
	st.ball_y = st.players[0].y
	check_eq(HitResolver._resolve_hit(st,
		[Simulation.IN_ACTION, 0, 0, 0], cfgt), HitResolver.NO_HIT,
		"トス意図はレシーブ上手でもリーチ不変")

func test_own_toss_zone_mapping_mirrors_both_teams() -> void:
	var cfg = SimConfig.new()
	check_eq(HitResolver.toss_target_x(0, 0, cfg), FP.from_int(248),
		"左・無方向=原作の自陣前")
	check_eq(HitResolver.toss_target_x(0, -1, cfg), FP.from_int(136),
		"左・ネット逆=原作の自陣後")
	check_eq(HitResolver.toss_target_x(1, 0, cfg), FP.from_int(328),
		"右・無方向=原作の自陣前を鏡写し")
	check_eq(HitResolver.toss_target_x(1, 1, cfg), FP.from_int(440),
		"右・ネット逆=原作の自陣後を鏡写し")

func test_third_ground_toss_forces_opponent_return_for_every_direction() -> void:
	for row in [
		[0, Simulation.IN_LEFT],
		[0, 0],
		[0, Simulation.IN_RIGHT],
		[2, Simulation.IN_LEFT],
		[2, 0],
		[2, Simulation.IN_RIGHT],
	]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var actor: int = row[0]
		var team: int = actor / 2
		var p = s.players[actor]
		s.touches = cfg.max_touches - 1
		s.last_touch_team = team
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = p.y - FP.from_int(10)
		var expected_vx: int = HitResolver.opponent_return_vx(
			s.ball_x, s.ball_y, 0, team, p.char_id, cfg)
		HitResolver._apply_hit(
			s, actor, cfg, Simulation.IN_ACTION | row[1], 0)
		check_eq(s.ball_vx, expected_vx,
			"3打目の地上トスは方向入力によらず敵陣へ返す: %s" % [row])
		check_eq(s.ball_vy, -cfg.bump_up_speed,
			"3打目の上向き速度は既存値を維持: %s" % [row])

func test_first_and_second_ground_toss_keep_backward_aim() -> void:
	for row in [
		[0, Simulation.IN_LEFT, 1, 2, 136],
		[0, Simulation.IN_LEFT, 0, 1, 136],
		[2, Simulation.IN_RIGHT, 0, 2, 440],
		[2, Simulation.IN_RIGHT, 1, 1, 440],
	]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var actor: int = row[0]
		var p = s.players[actor]
		s.last_touch_team = row[2]
		s.touches = row[3]
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = p.y - FP.from_int(10)
		var expected_target: int = FP.from_int(row[4])
		var expected_vx: int = HitResolver.toss_aim_vx(
			s.ball_x, s.ball_y, -FP.from_int(680) / 60, expected_target, cfg)
		HitResolver._apply_hit(
			s, actor, cfg, Simulation.IN_ACTION | row[1], 0)
		check_eq(s.ball_vx, expected_vx,
			"1・2打目の地上トスは後方入力を維持: %s" % [row])

func test_standard_ground_toss_recomputed_velocity_lands_at_fixed_target() -> void:
	for row in [
		[0, 0, 248],
		[0, Simulation.IN_LEFT, 136],
		[2, 0, 328],
		[2, Simulation.IN_RIGHT, 440],
	]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var actor: int = row[0]
		var p = s.players[actor]
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		HitResolver._apply_hit(
			s, actor, cfg, Simulation.IN_ACTION | row[1], 0)
		var launch_vx: int = s.ball_vx
		var landed := false
		for _tick in 180:
			BallPhysics._step_ball(s, cfg)
			if s.ball_vy >= 0 and s.ball_y >= cfg.floor_y - cfg.ball_radius:
				landed = true
				break
		var target: int = FP.from_int(row[2])
		check(landed, "標準トスが180tick以内に着地高度へ戻る: %s" % [row])
		check(absi(s.ball_x - target) <= absi(launch_vx),
			"実ボール物理でも既存の自陣目標へ着地: %s" % [row])

func _air_toss_world(team: int, touches_before: int) -> Array:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var actor: int = team * 2
	var p = s.players[actor]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(80)
	s.ball_x = p.x + SimState._dir_of_team(team) * FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	s.ball_vx = 0
	s.ball_vy = 0
	s.last_touch_team = team if touches_before > 0 else 1 - team
	s.touches = touches_before
	return [s, cfg, actor, s.ball_x, s.ball_y]

func test_first_and_second_air_toss_target_own_front_mirrors_teams() -> void:
	for team in 2:
		for touches_before in [0, 1]:
			var w := _air_toss_world(team, touches_before)
			var s = w[0]
			var cfg = w[1]
			var expected_vy: int = -cfg.toss_fwd_vy
			var expected_vx: int = HitResolver.toss_aim_vx(
				w[3], w[4], expected_vy,
				HitResolver.toss_target_x(team, 0, cfg), cfg)
			HitResolver._apply_hit(s, w[2], cfg, Simulation.IN_ACTION, 0)
			check_eq(s.ball_vx, expected_vx,
				"1・2打目の空中トスは自陣前方: team=%d touch=%d"
				% [team, touches_before + 1])
			check_eq(s.ball_vy, expected_vy,
				"1・2打目の空中トスは既存の上向き速度")

func test_third_air_toss_returns_to_opponent_mirrors_teams() -> void:
	for team in 2:
		var w := _air_toss_world(team, 2)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var expected_vx: int = HitResolver.opponent_return_vx(
			s.ball_x, s.ball_y, 0, team, s.players[actor].char_id, cfg)
		HitResolver._apply_hit(s, actor, cfg, Simulation.IN_ACTION, 0)
		check_eq(s.ball_vx, expected_vx, "3打目の空中トスは敵陣返球式")
		var landing_x: int = SimCpu._predict_landing_x(
			s, cfg, cfg.floor_y - cfg.ball_radius, 3)
		check((landing_x > cfg.net_x) == (team == 0),
			"3打目の空中トスは相手コートへ着地")
		check_eq(s.touches, cfg.max_touches,
			"3打目は4回目接触にせず最大タッチ数で止まる")

func test_air_toss_serve_returns_to_opponent_mirrors_teams() -> void:
	for team in 2:
		var w := _air_toss_world(team, 0)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var dir: int = SimState._dir_of_team(team)
		s.phase = SimState.PHASE_SERVE
		s.serving_team = team
		s.serve_tossed = 1
		var expected_vx: int = HitResolver.opponent_return_vx(
			s.ball_x, s.ball_y, 0, team, s.players[actor].char_id, cfg)
		var input: int = Simulation.IN_ACTION \
			| (Simulation.IN_RIGHT if dir > 0 else Simulation.IN_LEFT)
		HitResolver._apply_hit(s, actor, cfg, input, 0)
		check_eq(s.ball_vx, expected_vx,
			"空中通常サーブはタッチ数によらず敵陣返球式")
		var landing_x: int = SimCpu._predict_landing_x(
			s, cfg, cfg.floor_y - cfg.ball_radius, 3)
		check((landing_x > cfg.net_x) == (team == 0),
			"空中通常サーブは相手コートへ着地")

func test_third_touch_does_not_change_air_spike() -> void:
	var first := _air_toss_world(0, 0)
	var third := _air_toss_world(0, 2)
	var input: int = Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT
	for w in [first, third]:
		HitResolver._apply_hit(
			w[0], w[2], w[1], input, w[1].player_reach * w[1].player_reach)
	check_eq(third[0].ball_vx, first[0].ball_vx,
		"3打目でも空中スパイクの横速度は通常時と同じ")
	check_eq(third[0].ball_vy, first[0].ball_vy,
		"3打目でも空中スパイクの縦速度は通常時と同じ")
	check(third[0].ball_vy > 0, "3打目でも空中+下はスパイク")
	check_eq(third[0].ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"3打目の通常スパイク分類を維持")

func test_toss_good_aims_own_ground_trajectory_at_zone() -> void:
	var cfg = SimConfig.new()
	var target := HitResolver.toss_target_x(0, 0, cfg)
	for start_y in [cfg.floor_y - FP.from_int(10), cfg.floor_y - FP.from_int(90)]:
		var start_x: int = FP.from_int(100)
		var vy: int = -cfg.bump_up_speed
		var vx: int = HitResolver.toss_aim_vx(start_x, start_y, vy, target, cfg)
		var landed: int = HitResolver.trajectory_x_at_y(start_x, start_y, vx, vy,
			cfg.floor_y - cfg.ball_radius, cfg)
		check(absi(landed - target) <= absi(vx),
			"異なる打点から自陣設定ゾーンへ着地: %d" % start_y)
	for actor in [0, 2]:
		var w := _rally_world()
		var s = w[0]
		var actual_cfg = w[1]
		var p = s.players[actor]
		p.char_id = Chars.CHAR_MARIO
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = p.y - FP.from_int(10)
		HitResolver._apply_hit(s, actor, actual_cfg, Simulation.IN_ACTION, 0)
		var expected_target: int = HitResolver.toss_target_x(actor / 2, 0, actual_cfg)
		var expected_vx: int = HitResolver.toss_aim_vx(
			p.x + FP.from_int(5), p.y - FP.from_int(10), s.ball_vy,
			expected_target, actual_cfg)
		check_eq(s.ball_vx, expected_vx,
			"トス上手の両チーム自陣照準: actor=%d" % actor)

func test_toss_vy_for_apex_pct_targets_requested_height() -> void:
	var cfg = SimConfig.new()
	var normal_vy: int = -cfg.bump_up_speed
	var low_vy: int = HitResolver.toss_vy_for_apex_pct(normal_vy, cfg.gravity, 70)
	var normal_h: int = HitResolver.apex_height(normal_vy, cfg.gravity)
	var low_h: int = HitResolver.apex_height(low_vy, cfg.gravity)
	check(absi(low_h * 100 - normal_h * 70) <= cfg.gravity * 100,
		"低トスは通常頂点の70%%: %d/%d" % [low_h, normal_h])

func test_fast_incoming_ball_does_not_raise_standard_toss_above_initial_height() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(700) / cfg.tick_rate
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.ball_vy, -FP.from_int(680) / 60 + cfg.gravity,
		"強い入射でも標準トスは680px/s基準を越えない")

func test_toss_forward_goes_far() -> void:
	# 横入力+アクション: 前トス(横速度が素レシーブより大きく、入力方向へ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "前トスは敵陣方向へ進む")
	check(s.ball_vx > cfg.bump_fwd_speed, "前トスは素レシーブより横に速い")

func test_toss_backward_follows_input() -> void:
	# 左入力で左チームでも後ろ(相方側)へ返せる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_LEFT, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "左入力なら左チームでも後ろ向きに返せる")

func test_toss_mid_is_between() -> void:
	# ニュートラルは自陣前方、前入力は敵陣返球の別方式を使う。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var neutral_target := HitResolver.toss_target_x(0, 0, cfg)
	check_eq(neutral_target, FP.from_int(cfg.toss_zone_front_px),
		"ニュートラルトスは自陣前方を狙う")
	check(s.ball_vx > 0, "ニュートラルトスは自陣前方へ進む")

func test_receive_reflects_incoming_inertia() -> void:
	# 相手の強打(横入射)を真上狙いで受けても、慣性が反発して前へ逸れる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(8)  # 右から左へ来る強打
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "真上狙いでも入射の反発で前(右)へ逸れる")

func test_no_incoming_toss_stays_on_aim() -> void:
	# 入射速度ゼロなら慣性成分ゼロ=ニュートラルの自陣前方狙いどおり。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "入射ゼロならニュートラル狙いどおり前へ進む")

func test_no_hit_out_of_reach() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + cfg.player_reach * 3
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "届かなければヒットしない")

func test_reach_is_tighter_vertically() -> void:
	# 楕円判定: 横ならreach内だが、同じ距離でも真上はreach_upを超えると届かない
	# (頭のかなり上でボールを打てる違和感の回帰テスト)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var d: int = (cfg.player_reach + cfg.player_reach_up) / 2  # reach_upとreachの間
	s.ball_x = s.players[0].x
	s.ball_y = s.players[0].y - d
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "真上はreach_upを超えると届かない")
	# 同じ距離を横に置けば届く
	var w2 := _rally_world()
	var s2 = w2[0]
	s2.ball_x = s2.players[0].x + d
	s2.ball_y = s2.players[0].y
	Simulation.step(s2, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s2.touches, 1, "横なら同じ距離で届く")

func test_spike_in_air() -> void:
	# 下のみ=中央スパイク。横速度は中央専用値を使う
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "スパイク(空中+下)は下向き")
	check(s.ball_vx > 0, "左チームのスパイクは右向き")
	check_eq(s.ball_vx, cfg.spike_mid_vx * cfg.spike_power_pct / 100,
		"中央入力は中央専用の固定横速度を使う")
	# 「急角度」は緩角との比較で定義する(縦/横の比が緩角より大きい)。
	# 整数のまま比較: steep_vy*flat_vx > flat_vy*steep_vx
	check(cfg.spike_steep_vy * cfg.spike_vx > cfg.spike_vy * cfg.spike_steep_vx,
		"鋭角は緩角より角度が急")

func test_flat_spike_goes_farther() -> void:
	# 下+横=緩角スパイク(後面へ低く遠く)。鋭角より横が速く縦が浅い
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	Simulation.step(s,
		[Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "緩角スパイクも下向き")
	check_eq(s.ball_vx, cfg.spike_vx * cfg.spike_power_pct / 100,
		"ネット方向入力は専用の固定横速度を使う")
	check(s.ball_vx > 0, "後面アタックも敵陣方向へ飛ぶ")
	check(s.ball_vy < cfg.spike_steep_vy, "緩角の縦速度は鋭角より浅い")

func test_flat_spike_direction_is_always_net() -> void:
	# 緩角の横キーは「緩角の宣言」であって向きではない。左キーでも飛ぶ向きはネット方向
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s,
		[Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "左チームのスパイクは左キーでも右(ネット方向)へ飛ぶ")

func test_spike_horizontal_speed_is_independent_of_contact_position() -> void:
	var cases := 0
	for team in 2:
		for relative_hdir in [-1, 0, 1]:
			var reference_vx: int = 0
			var has_reference := false
			for height_px in SPIKE_SAMPLE_HEIGHTS_PX:
				var previous_distance := -1
				for distance_px in range(
						SPIKE_NEAREST_D_PX,
						SPIKE_FARTHEST_D_PX + 1,
						SPIKE_SAMPLE_STEP_PX):
					if previous_distance >= 0 and distance_px > previous_distance:
						check(distance_px - previous_distance <= SPIKE_SAMPLE_STEP_PX,
							"打点距離の刻みは20px以下")
					previous_distance = distance_px
					var vx: int = _normal_spike_vx(
						team, relative_hdir, distance_px, height_px)
					if not has_reference:
						reference_vx = vx
						has_reference = true
					check_eq(vx, reference_vx,
						("同じ入力なら打点距離・高さによらず横速度一定: "
						+ "team=%d dir=%d distance=%d height=%d") % [
							team, relative_hdir, distance_px, height_px,
						])
					cases += 1
	check(cases > 0, "位置・高さの網羅検査が1通り以上を実行する")

func test_standard_normal_spike_final_speeds_px_s() -> void:
	var cfg = SimConfig.new()
	for team in 2:
		var dir: int = SimState._dir_of_team(team)
		for row in [
			[-1, 388],
			[0, 582],
			[1, 679],
		]:
			var vx: int = _normal_spike_vx(team, row[0], 120, 80)
			var actual_px_s: int = (absi(vx) * cfg.tick_rate) >> 16
			check_eq(actual_px_s, row[1],
				"通常25%後の実横速度を固定: team=%d relative_dir=%d" % [
					team, row[0],
				])
			check(vx * dir > 0,
				"スパイクは常にネット方向へ飛ぶ: team=%d dir=%d" % [
					team, row[0],
				])

func test_spike_horizontal_speed_is_deterministic() -> void:
	for team in 2:
		for relative_hdir in [-1, 0, 1]:
			var first: int = _normal_spike_vx(team, relative_hdir, 120, 80)
			var second: int = _normal_spike_vx(team, relative_hdir, 120, 80)
			check_eq(second, first,
				"同じ状態と入力なら横速度が完全一致: team=%d dir=%d" % [
					team, relative_hdir,
				])

func test_perfect_spike_boosts_power() -> void:
	# ジャストミート(スイートスポット内)のスパイクは速度ボーナス+パワーボール化
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(2)
	s.ball_y = p.y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 1, "ジャストミートはパワーボールになる")
	var normal_vy: int = (cfg.spike_steep_vy + cfg.spike_vy) \
		* cfg.spike_normal_pct / 200
	check(s.ball_vy > normal_vy + cfg.gravity, "ジャスト110%は通常80%より速い")
	check(s.ball_vx > 0, "横速度も敵陣方向へ出る")

func test_edge_spike_is_normal() -> void:
	# スイートスポットの外(リーチ内ギリギリ)のスパイクは通常威力
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	var sweet: int = cfg.player_reach * cfg.spike_sweet_pct / 100
	s.ball_x = p.x + sweet + FP.from_int(4)  # スイート外・リーチ内
	s.ball_y = p.y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 0, "ズレたスパイクはパワーボールにならない")
	check(s.ball_vy <= cfg.spike_steep_vy + cfg.gravity, "ズレたスパイクは通常威力")

func test_sweet_boundary_is_forty_five_percent() -> void:
	var inside := _rally_world(); var si = inside[0]; var cfg = inside[1]
	var pi = si.players[0]
	pi.on_ground = 0
	var sweet_r: int = cfg.player_reach * 45 / 100
	HitResolver._apply_hit(si, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, sweet_r * sweet_r)
	check_eq(si.ball_power, 1, "45%境界内はジャスト")
	var outside := _rally_world(); var so = outside[0]
	var po = so.players[0]
	po.on_ground = 0
	var old_window_r: int = cfg.player_reach * 50 / 100
	HitResolver._apply_hit(so, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, old_window_r * old_window_r)
	check_eq(so.ball_power, 0, "旧45-60%帯は通常アタック")

func test_spike_reflects_incoming_inertia() -> void:
	# 空中アタックにも慣性反射: 上がり際(上昇中)のボールを叩くと反発が乗って
	# 静止球より速く鋭く飛ぶ(打つタイミングが着弾を変える物理)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	var sweet: int = cfg.player_reach * cfg.spike_sweet_pct / 100
	s.ball_x = p.x + sweet + FP.from_int(4)  # スイート外(慣性30%が丸ごと出る)
	s.ball_y = p.y
	s.ball_vy = -FP.from_int(8)  # 上昇中
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	var expect: int = (cfg.spike_steep_vy + cfg.spike_vy) \
		* cfg.spike_normal_pct / 200 \
		+ FP.from_int(8) * cfg.hit_inertia_num / cfg.hit_inertia_den + cfg.gravity
	check_eq(s.ball_vy, expect, "上がり際の反発が縦速度に乗る")

func test_just_meet_cuts_inertia() -> void:
	# ジャストミート(芯)は慣性の影響が10%に落ちる=狙い通りに飛ぶ
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(2)  # スイート内
	s.ball_y = p.y - FP.from_int(2)
	s.ball_vy = -FP.from_int(8)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	var expect: int = (cfg.spike_steep_vy + cfg.spike_vy) \
		* cfg.spike_power_pct / 200 \
		+ FP.from_int(8) * cfg.hit_inertia_just_num / cfg.hit_inertia_den + cfg.gravity
	check_eq(s.ball_vy, expect, "芯なら慣性がjust値まで落ちる")

func test_just_receive_holds_aim() -> void:
	# 地上のジャスト受け(芯)も慣性カット: 強い入射でも狙いがブレにくい
	var no_incoming := _rally_world()
	var incoming := _rally_world()
	var receive_input: int = Simulation.IN_ACTION | Simulation.IN_DOWN
	for w in [no_incoming, incoming]:
		var s = w[0]
		var cfg = w[1]
		# タイミング式の正規手順: 静止中の下+ボタン押下エッジで有効窓を開く。
		Simulation._update_receive_stances(s, [receive_input, 0, 0, 0], cfg)
		s.last_touch_team = 1
		s.ball_attack_kind = SimState.BALL_ATTACK_JUST
		s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内
		s.ball_y = s.players[0].y - FP.from_int(2)
	no_incoming[0].ball_vx = 0
	incoming[0].ball_vx = -FP.from_int(20)
	Simulation.step(no_incoming[0], [receive_input, 0, 0, 0], no_incoming[1])
	Simulation.step(incoming[0], [receive_input, 0, 0, 0], incoming[1])
	var inertia_vx: int = FP.from_int(20) \
		* incoming[1].hit_inertia_just_num / incoming[1].hit_inertia_den
	check_eq(incoming[0].ball_vx - no_incoming[0].ball_vx, inertia_vx,
		"同じ接触項と散りにjust慣性分だけが加わる")

func test_forward_action_blocks_on_ground_and_in_air_for_both_teams() -> void:
	for team in 2:
		for on_ground in [0, 1]:
			var w := _rally_world()
			var s = w[0]
			var cfg = w[1]
			var blocker_idx: int = 1 if team == 0 else 3
			var dir: int = SimState._dir_of_team(team)
			var p = s.players[blocker_idx]
			p.x = cfg.net_x - dir * FP.from_int(30)
			p.y = cfg.floor_y if on_ground == 1 \
				else cfg.floor_y - FP.from_int(140)
			p.on_ground = on_ground
			s.last_touch_team = 1 - team
			s.ball_x = p.x
			s.ball_y = p.y - cfg.player_reach_up
			s.ball_vx = -dir * FP.from_int(8)
			s.ball_vy = FP.from_int(6)
			var inputs: Array[int] = [0, 0, 0, 0]
			inputs[blocker_idx] = _block_input(team)
			Simulation.step(s, inputs, cfg)
			check(s.ball_vx * dir > 0,
				"前+ボタンで相手球を反射 team=%d ground=%d" % [team, on_ground])
			check_eq(s.last_touch_team, team, "反射球はブロッカー側の球")
			check_eq(s.last_touch_idx, blocker_idx, "最後に触った選手を記録")
			check_eq(SimState.team_of(s.last_touch_idx), s.last_touch_team,
				"ブロッカーと最終タッチチームが一致")
			check_eq(s.touches, 1, "原作どおりブロックも1タッチに数える")
			check_eq(s.cpu_hit_count, 1,
				"ブロックでもCPU位置取り用カウンタを1増やす")

func test_jump_alone_does_not_block() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 1
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "ネット際でジャンプしただけではブロックしない")

func test_up_and_down_actions_do_not_create_block_context() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 1
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	for vertical in [Simulation.IN_UP, Simulation.IN_DOWN]:
		check(not HitResolver._is_active_block(
			s, 0, _block_input(0) | vertical, cfg),
			"上下入力を含むアクションはブロックしない")

func test_neutral_ground_action_does_not_block() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.floor_y
	p.on_ground = 1
	s.last_touch_team = 1
	s.ball_vx = -FP.from_int(8)
	check(not HitResolver._is_active_block(s, 0, Simulation.IN_ACTION, cfg),
		"地上の方向なしボタンはブロックしない")

func test_failed_forward_block_falls_through_to_forward_toss() -> void:
	for team in 2:
		for on_ground in [0, 1]:
			var w := _rally_world()
			var s = w[0]
			var cfg = w[1]
			var actor: int = team * 2
			var dir: int = SimState._dir_of_team(team)
			var p = s.players[actor]
			p.x = cfg.net_x - dir * FP.from_int(100)
			p.y = cfg.floor_y if on_ground == 1 \
				else cfg.floor_y - FP.from_int(100)
			p.on_ground = on_ground
			s.last_touch_team = team
			s.ball_x = p.x
			s.ball_y = p.y - FP.from_int(5)
			s.ball_vx = 0
			s.ball_vy = 0
			var inputs: Array[int] = [0, 0, 0, 0]
			inputs[actor] = _block_input(team)
			check_eq(HitResolver._resolve_hit(s, inputs, cfg),
				HitResolver.HIT_NO_POINT, "条件外の前入力は空振りにしない")
			check(s.ball_vx * dir > 0,
				"条件外の前入力は敵陣方向へのトス team=%d ground=%d" % [
					team, on_ground])
			check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
				"条件外の前トスはアタック属性を持たない")

func test_own_shot_is_not_blocked() -> void:
	# 自チームの打球は自分たちの空中の体に当たらない(空中戦の自滅防止)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 0  # 自チームの打球
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	var before_vx: int = s.ball_vx
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "自チームの球は体を素通りする")
	check_eq(s.ball_vx, before_vx, "速度も変わらない(重力以外)")

func test_serve_cannot_be_blocked() -> void:
	# サーブ飛行中の打球はブロック不可(バレーのルール準拠)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.serve_flight = 1
	s.serve_ball = 1
	var p = s.players[2]  # 右チームのブロッカー
	p.x = cfg.net_x + FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 0
	s.ball_x = p.x - FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(8)
	Simulation.step(s, [0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0], cfg)
	check(s.ball_vx > 0, "サーブはブロックされず通り抜ける")

func test_crossed_serve_cannot_be_blocked_before_receiver_touch() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.serving_team = 0
	s.serve_flight = 0
	s.serve_ball = 1
	s.touches = 0
	s.last_touch_team = 0
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.ball_x = p.x - FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(600) / cfg.tick_rate
	var block_input: int = _block_input(1)
	check(not HitResolver._is_active_block(s, 2, block_input, cfg),
		"ネット越え後も受球前のサーブには有効ブロックを作らない")
	var before_vx: int = s.ball_vx
	HitResolver._ball_vs_block(s, cfg, [0, 0, block_input, 0])
	check_eq(s.ball_vx, before_vx, "受球前のサーブをブロック反射しない")

func test_normal_rally_ball_can_still_be_blocked() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.serve_flight = 0
	s.serve_ball = 0
	s.touches = 1
	s.last_touch_team = 0
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.ball_x = p.x - FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(600) / cfg.tick_rate
	var block_input: int = _block_input(1)
	check(HitResolver._is_active_block(s, 2, block_input, cfg),
		"通常ラリー球には有効ブロックが成立する")
	HitResolver._ball_vs_block(s, cfg, [0, 0, block_input, 0])
	check(s.ball_vx < 0, "通常ラリー球は従来どおりブロック反射する")

func test_receiver_touch_clears_serve_ball_and_restores_blocking() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.serving_team = 0
	s.serve_ball = 1
	s.serve_flight = 0
	s.touches = 0
	s.last_touch_team = 0
	var receiver = s.players[2]
	receiver.x = cfg.net_x + FP.from_int(100)
	receiver.y = cfg.floor_y
	receiver.on_ground = 1
	s.ball_x = receiver.x
	s.ball_y = receiver.y - FP.from_int(10)
	s.ball_vx = FP.from_int(8)
	HitResolver._resolve_hit(
		s, [0, 0, Simulation.IN_ACTION | Simulation.IN_DOWN, 0], cfg)
	check_eq(s.serve_ball, 0, "受け手チームの最初の接触でサーブ由来球状態を解除")
	var blocker = s.players[0]
	blocker.x = cfg.net_x - FP.from_int(30)
	blocker.y = cfg.floor_y - FP.from_int(140)
	blocker.on_ground = 0
	blocker.hit_cooldown = 0
	s.last_touch_team = 1
	s.ball_x = blocker.x + FP.from_int(5)
	s.ball_y = blocker.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(600) / cfg.tick_rate
	var block_input: int = _block_input(0)
	HitResolver._ball_vs_block(s, cfg, [block_input, 0, 0, 0])
	check(s.ball_vx > 0, "受球後に返ってきた球はブロックできる")

func test_receiving_power_ball_damages_guard() -> void:
	# パワーボールを(スイート外で)受けるとヒットは成立し、耐久力が削れる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_power = 1
	s.ball_guard_damage = cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C)
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)  # スイート外
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "パワーボールでもレシーブ自体は成立する")
	check_eq(s.players[0].guard, 75, "POWER Cの絶対値25だけ耐久力が削れる")
	# 芯を外してパワーボールを受けたら必ずよろけ(小スタン)
	check(s.players[0].flinch > 0, "しりもちリアクションが入る")
	check(s.players[0].vx < 0, "後ろ(左)へノックバック")
	check_eq(s.ball_power, 0, "パワーはヒットで消費される")

func test_guard_zero_causes_stun_and_refill() -> void:
	# 耐久力が尽きるとスタンし、耐久力は満タンへ戻る(気絶サイクル)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C)
	s.ball_power = 1
	s.ball_guard_damage = cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C)
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.players[0].stun, cfg.stun_ticks, "耐久力が尽きてスタン")
	check_eq(s.players[0].guard, s.players[0].guard_max, "スタン後は満タンへ戻る")

func test_normal_spike_receive_no_damage() -> void:
	# 通常スパイク(パワーなし)の受けはノーダメージ(削るのはパワーボールだけ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(9)  # スパイク級の入射でも
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 100, "通常スパイク受けはノーダメージ")

func test_just_receive_of_power_ball_does_not_heal() -> void:
	# 回復全廃(ラチェット原則)。2026-07-20設計会仕様
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = 40
	s.players[0].receive_stance = 1
	s.ball_power = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 40, "ジャスト受けでも回復しない")
	check_eq(s.players[0].stun, 0, "ダメージは受けない")
	# 上限は満タンまで
	var w2 := _rally_world()
	var s2 = w2[0]
	s2.players[0].guard = 95
	s2.players[0].receive_stance = 1
	s2.ball_power = 1
	s2.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s2.last_touch_team = 1
	s2.ball_x = s2.players[0].x + FP.from_int(2)
	s2.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s2, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s2.players[0].guard, 95, "芯受けでも耐久は増えない")

func test_plain_toss_does_not_heal() -> void:
	# パワーボール以外はスイートで取っても回復しない(ご褒美はジャスト防御だけ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = 40
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内・パワーなし
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "ヒットは成立")
	check_eq(s.players[0].guard, 40, "普通のボールは回復しない")

func test_stunned_player_cannot_hit_or_move() -> void:
	# スタン中は移動もヒットもできない
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.stun = 10
	p.stun_action_held = 1  # 押下済みの保持入力。新規エッジではない
	var x0: int = p.x
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "スタン中はヒットしない")
	check_eq(p.x, x0, "スタン中は動けない")
	check_eq(p.stun, 9, "スタンはtickごとに回復へ向かう")

func test_air_neutral_sends_soft_over() -> void:
	# 空中ニュートラル+アクション: 緩やかに相手コート方向へ送る(下向きではない)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "空中ニュートラルは上向きの緩い弧")
	check(s.ball_vx > 0, "左チームはネット方向(右)へ送る")
	check(s.ball_vx < cfg.spike_mid_vx * cfg.spike_normal_pct / 100,
		"通常の中央スパイクより遅い")

func test_air_side_tosses_far_arc() -> void:
	# 空中+横: きつめの角度の山なりで遠くへ
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	# 同step内で重力が1tick分加わるため厳密一致ではなく範囲で見る
	check(s.ball_vy <= -cfg.toss_fwd_vy + cfg.gravity, "山なりの上向き成分")
	check(s.ball_vx > 0, "前入力で敵陣後面方向へ進む")

func test_air_neutral_toss_lifts_instead_of_spike() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "空中ニュートラルトスは上向き")

func test_up_action_jumps_and_attacks_in_the_same_tick() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(40)
	Simulation.step(s,
		[Simulation.IN_ACTION | Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(p.on_ground, 0, "上+ボタンでジャンプする")
	check_eq(s.touches, 1, "ジャンプした同tickから届く球を攻撃できる")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"同tickの上アタックも通常属性")

func test_up_side_action_moves_jumps_and_attacks_without_ground_toss() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	var x0: int = p.x
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(40)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_JUMP
		| Simulation.IN_UP | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(p.x > x0, "上+横+ボタンでも横移動は抑制しない")
	check_eq(p.on_ground, 0, "上入力でジャンプする")
	check_eq(s.touches, 1, "横移動を含めても同tickから上アタックする")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"地上トスではなく空中通常アタックになる")

func test_jump_cut_on_release() -> void:
	# 可変ジャンプ: 上昇中に上キーを離すと失速し、押し続けより早く落下に転じる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(400)  # ボールは遠く(ヒットさせない)
	var hold = SimState.new()
	hold.load_int_array(s.to_int_array())
	# 双方1tick目でジャンプ、以降5tick: 片方は保持、片方は離す
	Simulation.step(s, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	Simulation.step(hold, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	for i in 5:
		Simulation.step(s, [0, 0, 0, 0], cfg)
		Simulation.step(hold, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check(s.players[0].vy > hold.players[0].vy, "離した側は上昇速度が失われている")
	check(s.players[0].y > hold.players[0].y, "離した側は高く上がれない")

func test_jump_without_action_is_full() -> void:
	# アクションなしの上入力はキャラクター別のフルジャンプを開始する
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	s.ball_x = FP.from_int(400)  # ボールは遠く
	Simulation.step(s, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(p.on_ground, 0, "フルジャンプで浮く")
	check(p.vy < 0, "フルジャンプは上向きの初速を持つ")

func test_reach_edge_toss_does_not_reuse_dive_state() -> void:
	# 通常リーチ内の横トスは従来どおり拾うが、横っ飛び状態は予測発動だけに使う。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	var edge: int = cfg.player_reach * 3 / 4
	s.ball_x = p.x + edge + FP.from_int(4)  # 縁の外側・リーチ内
	s.ball_y = cfg.floor_y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "ギリギリでも拾える")
	check(s.ball_vy < 0, "リーチ縁のトスも上向きに拾う")
	check_eq(p.dive, 0, "通常トスは横っ飛び状態を立てない")

func test_near_toss_is_not_jumping_toss() -> void:
	# 体の近くの横トスは通常の前トス(演出フラグなし)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(p.dive, 0, "近距離トスは飛びつかない")
	check(s.ball_vx > 0, "通常の前トスは敵陣方向へ進む")

func test_cooldown_blocks_double_hit() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "1回目でタッチ1")
	check_eq(s.cpu_hit_count, 1, "通常打球でCPU位置取り用カウンタを1増やす")
	# ボールを引き戻して連打
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "クールダウン中は再ヒットしない")
	check_eq(s.cpu_hit_count, 1, "不成立の再打撃ではカウンタを増やさない")

func test_same_tick_closest_teammate_wins() -> void:
	# 同tickに複数人がリーチ内なら最も近い1人だけがヒットする(1tick1ヒット)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(110)
	s.ball_x = FP.from_int(103)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(s.touches, 1, "同チーム同時タッチでも1タッチ")
	check(s.players[0].hit_cooldown > 0, "近い方がヒットする")
	check_eq(s.players[1].hit_cooldown, 0, "負けた側は硬直しない")
	check_eq(s.last_touch_idx, 0, "最後に打ったのは近い左後衛")
	check_eq(SimState.team_of(s.last_touch_idx), s.last_touch_team,
		"通常打球者と最終タッチチームが一致")

func test_same_tick_tie_ball_side_team_wins() -> void:
	# 距離が同点なら、ボールがある側のチームが優先(ネット際ジョストの公平化)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[1].x = cfg.net_x - cfg.net_half_w - FP.from_int(4)
	s.players[2].x = cfg.net_x + cfg.net_half_w + FP.from_int(4)
	s.ball_x = cfg.net_x
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [0, Simulation.IN_ACTION, Simulation.IN_ACTION, 0], cfg)
	check_eq(s.last_touch_team, 1, "ボール側(右)のチームが同距離タイを制す")
	check(s.players[2].hit_cooldown > 0, "右前衛がヒットする")
	check_eq(s.players[1].hit_cooldown, 0, "左前衛は硬直しない")
	check_eq(s.last_touch_idx, 2, "最後に打ったのは右後衛")
	check_eq(SimState.team_of(s.last_touch_idx), s.last_touch_team,
		"同距離打球者と最終タッチチームが一致")

func test_touch_count_resets_on_team_change() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.touches = 2
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "チームが替わればタッチ数は1から")

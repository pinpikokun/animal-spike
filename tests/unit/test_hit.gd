extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const Chars := preload("res://src/sim/chars.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const STANDARD_CHAR := 99

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.char_id = STANDARD_CHAR
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(175)
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	return [s, cfg]

func test_bump_on_ground() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(3)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "バンプでボールが上昇する")
	check(s.ball_vx > 0, "左チームのバンプは右向き成分")
	check_eq(s.touches, 1, "タッチ数1")
	check_eq(s.last_touch_team, 0, "最終タッチは左チーム")
	check(s.players[0].hit_cooldown > 0, "クールダウン開始")

func test_neutral_receive_keeps_legacy_bounce() -> void:
	# 方向なしアクションはトスではなく素レシーブ。トス技能の低軌道補正を受けない。
	for seed_tick in 201:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		s.tick = seed_tick
		s.ball_x = s.players[0].x + FP.from_int(30)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		s.ball_vy = 0
		Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
		check_eq(s.ball_vy, -cfg.bump_up_speed + cfg.gravity,
			"ニュートラルレシーブはトス技能に関係なく従来の高さで跳ねる")

func test_neutral_receive_reflects_vertical_inertia() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(12)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(-s.ball_vy > cfg.bump_up_speed - cfg.gravity,
		"落下球のニュートラルレシーブは縦の勢いも跳ね返す: actual=%d base=%d" % [
			-s.ball_vy, cfg.bump_up_speed - cfg.gravity])

func test_toss_up_is_vertical() -> void:
	# 上入力+アクション: 真上トス(横成分ゼロ、高く上がる)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.ball_vx, 0, "真上トスは横成分ゼロ")
	# step内で重力が1回乗るため厳密等値は避け、前トスより高い初速であることを見る
	check(s.ball_vy < -cfg.toss_fwd_vy, "真上トスは前トスより高く上がる")

func test_only_toss_bad_can_produce_low_toss() -> void:
	var low_count := 0
	for seed_tick in 201:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		s.players[0].char_id = Chars.CHAR_PANDA
		s.tick = seed_tick
		s.ball_x = s.players[0].x + FP.from_int(30)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		s.ball_vy = 0
		Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
		var upward: int = -s.ball_vy
		check(upward <= cfg.bump_up_speed, "下手なトスでも基準より高くしない")
		if upward < cfg.bump_up_speed * 90 / 100:
			low_count += 1
	check(low_count > 0, "トス下手は低いトスを出すことがある")
	var w2 := _rally_world()
	var s2 = w2[0]
	var cfg2 = w2[1]
	s2.players[0].char_id = Chars.CHAR_FOX
	s2.ball_x = s2.players[0].x + FP.from_int(5)
	s2.ball_y = cfg2.floor_y - FP.from_int(10)
	Simulation.step(s2, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg2)
	check_eq(s2.ball_vy, -cfg2.bump_up_speed + cfg2.gravity,
		"特性なしは低トス失敗なし")

func test_mura_roll_is_deterministic_and_has_10_80_10_distribution() -> void:
	var w := _rally_world()
	var s = w[0]
	var counts := {50: 0, 100: 0, 150: 0}
	var seen := {}
	for tick in 100000:
		s.tick = tick
		var roll: int = HitResolver._trait_roll_pct(s, 0, HitResolver.SALT_MURA)
		if not seen.has(roll):
			seen[roll] = true
			var pct: int = HitResolver._mura_power_pct(s, 0, Chars.CHAR_PANDA)
			counts[pct] += 1
			check_eq(pct, HitResolver._mura_power_pct(s, 0, Chars.CHAR_PANDA),
				"同じtickとactorならむらっけ結果が同じ")
			if seen.size() == 100:
				break
	check_eq(seen.size(), 100, "決定論サンプルが全ロール値を覆う")
	check_eq([counts[50], counts[100], counts[150]], [10, 80, 10],
		"むらっけは10%/80%/10%")
	check_eq(HitResolver._mura_power_pct(s, 0, Chars.CHAR_MARIO), 100,
		"むらっけ無しは常に100%")

func _tick_for_mura_pct(target_pct: int) -> int:
	var w := _rally_world()
	var s = w[0]
	for tick in 10000:
		s.tick = tick
		if HitResolver._mura_power_pct(s, 0, Chars.CHAR_PANDA) == target_pct:
			return tick
	return -1

func test_mura_applies_to_normal_just_and_attack_serve() -> void:
	var tick := _tick_for_mura_pct(150)
	check(tick >= 0, "150%の決定論tickが見つかる")
	for sweet in [false, true]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.char_id = Chars.CHAR_PANDA
		p.on_ground = 0
		s.tick = tick
		var d2: int = 0 if sweet else cfg.player_reach * cfg.player_reach
		HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, d2)
		var base: int = cfg.spike_steep_vx * (cfg.spike_power_pct if sweet else 100) / 100
		check_eq(s.ball_vx, base * 150 / 100,
			"%sアタックへむらっけ最終倍率" % ("ジャスト" if sweet else "通常"))
	var ws := _rally_world()
	var ss = ws[0]
	var cfgs = ws[1]
	ss.phase = SimState.PHASE_SERVE
	ss.serve_tossed = 1
	ss.tick = tick
	ss.players[0].char_id = Chars.CHAR_PANDA
	HitResolver._apply_hit(ss, 0, cfgs, Simulation.IN_ACTION | Simulation.IN_RIGHT, 0)
	check_eq(ss.ball_vx, cfgs.serve_vx, "地上安全サーブへむらっけを適用しない")
	var wa := _rally_world()
	var sa = wa[0]
	var cfga = wa[1]
	sa.phase = SimState.PHASE_SERVE
	sa.serve_tossed = 1
	sa.tick = tick
	sa.players[0].char_id = Chars.CHAR_PANDA
	sa.players[0].on_ground = 0
	HitResolver._apply_hit(sa, 0, cfga, Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfga.player_reach * cfga.player_reach)
	check_eq(sa.ball_vx, cfga.spike_steep_vx * 150 / 100,
		"空中アタックサーブへむらっけ最終倍率を一度だけ適用")

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
			[Simulation.IN_ACTION, 0, 0, 0], cfg)
		check_eq(1 if result != HitResolver.NO_HIT else 0, row[2],
			"レシーブ実判定: %s" % [row])
	var wt := _rally_world()
	var st = wt[0]
	var cfgt = wt[1]
	st.players[0].char_id = Chars.CHAR_MARIO
	st.ball_x = st.players[0].x + cfgt.player_reach * 110 / 100
	st.ball_y = st.players[0].y
	check_eq(HitResolver._resolve_hit(st,
		[Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfgt), HitResolver.NO_HIT,
		"トス意図はレシーブ上手でもリーチ不変")

func test_toss_good_zone_mapping_mirrors_both_teams() -> void:
	var cfg = SimConfig.new()
	check_eq(HitResolver.toss_target_x(0, 0, cfg), FP.from_int(157), "左・無方向=自陣前")
	check_eq(HitResolver.toss_target_x(0, -1, cfg), FP.from_int(56), "左・ネット逆=自陣後")
	check_eq(HitResolver.toss_target_x(0, 1, cfg), FP.from_int(448 - 157),
		"左・ネット方向=敵陣前")
	check_eq(HitResolver.toss_target_x(1, 0, cfg), FP.from_int(448 - 157),
		"右・無方向=自陣前")
	check_eq(HitResolver.toss_target_x(1, 1, cfg), FP.from_int(448 - 56),
		"右・ネット逆=自陣後")
	check_eq(HitResolver.toss_target_x(1, -1, cfg), FP.from_int(157),
		"右・ネット方向=敵陣前")

func test_toss_good_aims_ground_and_air_trajectory_at_zone() -> void:
	var cfg = SimConfig.new()
	var target := HitResolver.toss_target_x(0, 0, cfg)
	for start_y in [cfg.floor_y - FP.from_int(10), cfg.floor_y - FP.from_int(90)]:
		var start_x: int = FP.from_int(100)
		var vy: int = -cfg.bump_up_speed
		var vx: int = HitResolver.toss_aim_vx(start_x, start_y, vy, target, cfg)
		var landed: int = HitResolver.trajectory_x_at_y(start_x, start_y, vx, vy,
			cfg.floor_y - cfg.ball_radius, cfg)
		check(absi(landed - target) <= absi(vx),
			"地上/空中トスが設定ゾーンへ着地: %d" % start_y)
	for row in [[0, 1, Simulation.IN_UP], [2, 1, Simulation.IN_UP],
		[0, 0, Simulation.IN_UP], [2, 0, Simulation.IN_UP]]:
		var w := _rally_world()
		var s = w[0]
		var actual_cfg = w[1]
		var actor: int = row[0]
		var p = s.players[actor]
		p.char_id = Chars.CHAR_MARIO
		p.on_ground = row[1]
		if p.on_ground == 0:
			p.y = actual_cfg.floor_y - FP.from_int(80)
		s.ball_x = p.x + FP.from_int(5)
		s.ball_y = p.y - FP.from_int(10)
		HitResolver._apply_hit(s, actor, actual_cfg,
			Simulation.IN_ACTION | row[2], 0)
		var expected_target: int = HitResolver.toss_target_x(actor / 2, 0, actual_cfg)
		var expected_vx: int = HitResolver.toss_aim_vx(
			p.x + FP.from_int(5), p.y - FP.from_int(10), s.ball_vy,
			expected_target, actual_cfg)
		check_eq(s.ball_vx, expected_vx,
			"トス上手の両チーム地上/空中統合照準: %s" % [row])

func test_toss_bad_is_exactly_30_percent_and_targets_70_percent_apex() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var seen := {}
	var low_count := 0
	for tick in 100000:
		s.tick = tick
		var roll: int = HitResolver._trait_roll_pct(s, 0, HitResolver.SALT_TOSS_BAD)
		if not seen.has(roll):
			seen[roll] = true
			if HitResolver._toss_apex_pct(s, 0, Chars.CHAR_PANDA) == 70:
				low_count += 1
			if seen.size() == 100:
				break
	check_eq(low_count, 30, "トス下手は決定論サンプルの30%")
	check_eq(HitResolver._toss_apex_pct(s, 0, Chars.CHAR_MARIO), 100,
		"トス上手は失敗なし")
	check_eq(HitResolver._toss_apex_pct(s, 0, Chars.CHAR_FOX), 100,
		"特性なしは失敗なし")
	var normal_vy: int = -cfg.bump_up_speed
	var low_vy: int = HitResolver.toss_vy_for_apex_pct(normal_vy, cfg.gravity, 70)
	var normal_h: int = HitResolver.apex_height(normal_vy, cfg.gravity)
	var low_h: int = HitResolver.apex_height(low_vy, cfg.gravity)
	check(absi(low_h * 100 - normal_h * 70) <= cfg.gravity * 100,
		"低トスは通常頂点の70%: %d/%d" % [low_h, normal_h])

func test_toss_bad_normal_roll_keeps_unskilled_air_toss_inertia() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	for tick in 10000:
		s.tick = tick
		if HitResolver._toss_apex_pct(s, 0, Chars.CHAR_PANDA) == 100:
			break
	var outputs: Array[int] = []
	for cid in [Chars.CHAR_PANDA, Chars.CHAR_FOX]:
		var sample := _rally_world()
		var state = sample[0]
		var sample_cfg = sample[1]
		state.tick = s.tick
		var p = state.players[0]
		p.char_id = cid
		p.on_ground = 0
		p.y = sample_cfg.floor_y - FP.from_int(40)
		state.ball_x = p.x + FP.from_int(30)
		state.ball_y = p.y
		state.ball_vy = FP.from_int(700) / sample_cfg.tick_rate
		HitResolver._apply_hit(state, 0, sample_cfg,
			Simulation.IN_ACTION | Simulation.IN_UP,
			sample_cfg.player_reach * sample_cfg.player_reach)
		outputs.append(state.ball_vy)
	check_eq(outputs[0], outputs[1],
		"トス下手の通常ロールは特性なしと同じ空中慣性反射")

func test_fast_incoming_ball_does_not_launch_toss_offscreen() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(700) / cfg.tick_rate
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check(-s.ball_vy <= cfg.bump_up_speed, "強い入射でもトスを基準より高くしない")

func test_toss_forward_goes_far() -> void:
	# 横入力+アクション: 前トス(横速度が素レシーブより大きく、入力方向へ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.ball_vx, cfg.toss_fwd_vx, "前トスは入力方向(右)へ遠く")
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
	# 上+横: 中間トス(高さは真上トス級、横は前トスより小さい)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vy < -cfg.toss_fwd_vy, "中間トスの高さは前トスより高い(真上トス級)")
	check_eq(s.ball_vx, cfg.toss_mid_vx, "中間トスの横は中程度")
	check(s.ball_vx < cfg.toss_fwd_vx, "中間トスは前トスより横が小さい")

func test_receive_reflects_incoming_inertia() -> void:
	# 相手の強打(横入射)を真上狙いで受けても、慣性が反発して前へ逸れる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(8)  # 右から左へ来る強打
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "真上狙いでも入射の反発で前(右)へ逸れる")

func test_no_incoming_toss_stays_on_aim() -> void:
	# 入射速度ゼロなら慣性成分ゼロ=狙いどおり真上(横成分ゼロ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.ball_vx, 0, "入射ゼロなら真上狙いは横ゼロのまま")

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
	# 下のみ=鋭角スパイク(前面へ鋭く落とす)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "スパイク(空中+下)は下向き")
	check(s.ball_vx > 0, "左チームのスパイクは右向き")
	check(s.ball_vx >= cfg.spike_steep_vx, "鋭角スパイクの横速度")
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
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s,
		[Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "緩角スパイクも下向き")
	check(s.ball_vx >= cfg.spike_vx, "緩角は横に速い(遠くへ届く)")
	check(s.ball_vx > cfg.spike_steep_vx, "緩角の横速度は鋭角より大きい")
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
	# 同step内の重力1tick分を考慮して通常スパイクより明確に速いことを見る
	check(s.ball_vy > cfg.spike_steep_vy + cfg.gravity, "ジャストミートは通常鋭角より速い")
	check(s.ball_vx > cfg.spike_steep_vx, "横速度もボーナスが乗る")

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
	var expect: int = cfg.spike_steep_vy \
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
	var expect: int = cfg.spike_steep_vy * cfg.spike_power_pct / 100 \
		+ FP.from_int(8) * cfg.hit_inertia_just_num / cfg.hit_inertia_den + cfg.gravity
	check_eq(s.ball_vy, expect, "芯なら慣性がjust値まで落ちる")

func test_just_receive_holds_aim() -> void:
	# 地上のジャスト受け(芯)も慣性カット: 強い入射でも狙いがブレにくい
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内
	s.ball_y = s.players[0].y - FP.from_int(2)
	s.ball_vx = -FP.from_int(20)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	var expect: int = FP.from_int(20) * cfg.hit_inertia_just_num / cfg.hit_inertia_den
	check_eq(s.ball_vx, expect, "真上トスの横ブレがjust慣性分だけに収まる")

func test_block_reflects_opponent_shot() -> void:
	# 原作どおり、ネット際でネット方向+アクションを押した時だけブロックする。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]  # 左チームのブロッカー
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 1  # 相手の打球
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up  # 手のひらゾーン
	s.ball_vx = -FP.from_int(8)  # 左(自陣)へ向かう強打
	s.ball_vy = FP.from_int(6)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "ブロックで打球が跳ね返る")
	check_eq(s.last_touch_team, 0, "跳ね返した球はブロッカー側の球になる")
	check_eq(s.touches, 1, "原作どおりブロックも1タッチに数える")

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

func test_block_requires_net_direction() -> void:
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
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_LEFT, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "ネットと逆方向+アクションではブロックしない")

func test_ground_block_works_with_original_input() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.floor_y
	p.on_ground = 1
	s.last_touch_team = 1
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "原作どおり地上でもネット方向+アクションでブロックできる")

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

func test_receiving_power_ball_damages_guard() -> void:
	# パワーボールを(スイート外で)受けるとヒットは成立し、耐久力が削れる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_power = 1
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)  # スイート外
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "パワーボールでもレシーブ自体は成立する")
	check_eq(s.players[0].guard, 100 - cfg.guard_dmg_power, "耐久力が削れる")
	# 芯を外してパワーボールを受けたら必ずよろけ(小スタン)
	check(s.players[0].flinch > 0, "しりもちリアクションが入る")
	check(s.players[0].vx < 0, "後ろ(左)へノックバック")
	check_eq(s.ball_power, 0, "パワーはヒットで消費される")

func test_guard_zero_causes_stun_and_refill() -> void:
	# 耐久力が尽きるとスタンし、耐久力は満タンへ戻る(気絶サイクル)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = cfg.guard_dmg_power  # あと1発で尽きる
	s.ball_power = 1
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
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
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 100, "通常スパイク受けはノーダメージ")

func test_just_receive_of_power_ball_heals() -> void:
	# パワーボールをスイートスポットで受け切る(ジャストトス)と逆に回復する
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = 40
	s.ball_power = 1
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.players[0].guard, 40 + cfg.guard_heal_just, "ジャスト受けで回復")
	check_eq(s.players[0].stun, 0, "ダメージは受けない")
	# 上限は満タンまで
	var w2 := _rally_world()
	var s2 = w2[0]
	s2.players[0].guard = 95
	s2.ball_power = 1
	s2.last_touch_team = 1
	s2.ball_x = s2.players[0].x + FP.from_int(2)
	s2.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s2, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s2.players[0].guard, 100, "回復は満タンで頭打ち")

func test_plain_toss_does_not_heal() -> void:
	# パワーボール以外はスイートで取っても回復しない(ご褒美はジャスト防御だけ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].guard = 40
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(2)  # スイート内・パワーなし
	s.ball_y = cfg.floor_y - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "ヒットは成立")
	check_eq(s.players[0].guard, 40, "普通のボールは回復しない")

func test_stunned_player_cannot_hit_or_move() -> void:
	# スタン中は移動もヒットもできない
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.stun = 10
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
	check(s.ball_vx < cfg.spike_vx, "スパイクより遅い")

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
	check_eq(s.ball_vx, cfg.toss_fwd_vx, "入力方向へ遠くへ")

func test_jump_toss_lifts_instead_of_spike() -> void:
	# 空中でも上入力ならスパイク(下向き)でなくジャンプトス(上向き)になる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "ジャンプトスは上向き(スパイクの下向きと逆)")

func test_up_toss_stays_grounded() -> void:
	# ↑+アクション(横なし): 真上トス。simでは跳ばない(ホップは表示層の演出のみ)。
	# 実ジャンプにすると空中ヒット扱いになり地上トス表(慣性込み)から外れるため
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s,
		[Simulation.IN_ACTION | Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(p.on_ground, 1, "トス構えでは跳ばない(地上ヒット扱い)")
	check_eq(s.ball_vx, 0, "真上トスは横成分ゼロ")
	check(s.ball_vy < 0, "ボールは上へトスされる")

func test_toss_stance_locks_movement() -> void:
	# ↑+横+アクション: 移動はしない(横キーはトス方向指定専用)。跳びもしない
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	var x0: int = p.x
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_JUMP
		| Simulation.IN_UP | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(p.x, x0, "トス構え中は横キーで移動しない")
	check_eq(p.on_ground, 1, "トス構えでは跳ばない(地上ヒット扱い)")
	check_eq(s.touches, 1, "トスが成立する")
	check_eq(s.ball_vx, cfg.toss_mid_vx, "上+横=中間トス(緩やかな前目)")

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

func test_jumping_toss_on_reach_edge() -> void:
	# 横+アクションでボールがリーチ縁ギリギリ: ジャンピングトス(緩め軌道+演出フラグ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	var edge: int = cfg.player_reach * 3 / 4
	s.ball_x = p.x + edge + FP.from_int(4)  # 縁の外側・リーチ内
	s.ball_y = cfg.floor_y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "ギリギリでも拾える")
	check(s.ball_vy < 0, "救済トスは低い失敗時でも上向きに拾う")
	check(p.dive > 0, "飛びつき演出フラグ(右向き)が立つ")

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
	check_eq(s.ball_vx, cfg.toss_fwd_vx, "通常の前トスのまま")

func test_cooldown_blocks_double_hit() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "1回目でタッチ1")
	# ボールを引き戻して連打
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "クールダウン中は再ヒットしない")

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

extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	return [s, cfg]

func test_cpu_chases_ball_on_own_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = FP.from_int(100)
	# players[1](左チーム相方、spawn_front=157)から見てボールは左
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "ボールへ向かって左移動")

func test_cpu_hits_in_reach() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x + FP.from_int(3)
	s.ball_y = s.players[1].y - FP.from_int(10)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION, "リーチ内でACTION")

func test_cpu_ignores_ball_on_other_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(350)
	s.ball_y = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ACTION), "敵陣のボールは打たない")

func test_cpu_auto_serves() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左チームのサーバーはplayers[0]。人間が相方(index1)を操作している想定で
	# tick経由でCPUサーバーの自動サーブを検証する
	s.controlled_l = 1
	var served := false
	# 2段階サーブ(トス→追走→打撃)のため猶予は遅延+トス滞空ぶん広く取る
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUサーバーが自動サーブする")

func test_cpu_team_serves_via_team_input() -> void:
	# 1人プレイの配線(左=人間、右=完全CPU)で右チームにサーブ権が移っても
	# 試合が止まらないことの回帰テスト。表示層はこのパターンでtickを呼ぶ
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	Simulation.reset_match(s, cfg, 1)
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右チーム(完全CPU)のサーブで試合が進む")

func test_cpu_serve_crosses_net() -> void:
	# セルフトス方式のサーブでも、CPUは前トス(ネット方向)で確実にネットを越え自滅しない
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左=人間が相方(index1)操作、CPUサーバー(index0)が自動サーブする配線
	s.controlled_l = 1
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUがサーブ(トス→打撃)を実行")
	var crossed := false
	for i in 300:
		Simulation.tick(s, [0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "CPUのサーブがネットを越え相手コートへ渡る(自滅しない)")

func test_cpu_serve_crosses_net_right_team() -> void:
	# 右チーム(serving_team=1)のCPUサーブも鏡像でネットを越え左コートへ渡る
	# (_serve_xやトス方向の符号ミスをゴールデンハッシュ頼みにしない直接検証)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	Simulation.reset_match(s, cfg, 1)
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右CPUがサーブ(トス→打撃)を実行")
	var crossed := false
	for i in 300:
		var cpu_r2: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r2], cfg)
		if s.ball_x < cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "右CPUのサーブがネットを越え左コートへ渡る")

func _prof(ab: int, delay := 0, aim := 0, miss := 0, sweet := 255, depth := 3, tiq := 0) -> int:
	# テスト用: 誤差・ミス・遅延のない純粋な能力プロファイル(既定)
	return SimCpu.make_profile(ab, delay, aim, miss, sweet, depth, tiq)

func test_profile_pack_roundtrip() -> void:
	# プロファイルの詰め込み/取り出しが欄ごとに正しく往復する
	var prof: int = SimCpu.make_profile(117, 13, 15, 13, 153, 2, 2)
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_AB), 117, "能力")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_DELAY), 13, "遅延")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_AIM), 15, "誤差")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_MISS), 13, "ミス率")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_SWEET), 153, "ジャスト率")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_DEPTH), 2, "予測深度")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_TIQ), 2, "配球IQ")
	check_eq(prof, SimCpu.PRESET_STRONG, "強プリセットと一致")

func test_state_default_profile_is_max() -> void:
	# sim_state.gdの既定リテラルがsim_cpu.PRESET_MAXからずれない番人
	var s = SimState.new()
	check_eq(s.players[0].cpu, SimCpu.PRESET_MAX, "既定プロファイル=最強")

func test_weak_chases_current_ball_predict_chases_landing() -> void:
	# 弱(能力なし)は現在のボール位置を追い、予測持ちは落下点を追う
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(120)  # 今はplayers[1](x=157)の左
	s.ball_y = FP.from_int(100)
	s.ball_vx = FP.from_int(8)   # 右へ強く飛んでいる=落下点は右
	s.players[1].cpu = _prof(0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "弱は現在位置(左)を追う")
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_RIGHT, "予測持ちは落下点(右)へ動く")

func test_roles_split_receiver_and_support() -> void:
	# 役割分担: 落下点に近い相方(p0)がレシーバー、遠いp1は持ち場へ戻る
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(56)   # 奥(p0の守備範囲)に落ちる
	s.ball_y = FP.from_int(100)
	s.players[1].x = FP.from_int(100)
	var mask: int = SimCpu.AB_PREDICT | SimCpu.AB_ROLES
	s.players[0].cpu = _prof(mask)
	s.players[1].cpu = _prof(mask)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_RIGHT, "非レシーバーは持ち場(157)へ離れる")
	# 役割なしなら同じ状況でボールへ突っ込む(=みんなで追いかける問題)
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "役割なしはボールへ向かう")

func test_yields_to_human_mate() -> void:
	# 人間の相方が同じ球を取れるならCPUは譲る(人間優先、お見合い事故の防止)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(90)
	s.ball_y = FP.from_int(100)
	s.controlled_l = 0           # slot0=人間
	s.players[0].x = FP.from_int(100)  # 人間: 落下点から10px
	s.players[1].x = FP.from_int(85)   # CPU: 5pxでより近いが…
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ROLES)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_LEFT), "人間が取れる球にCPUは突っ込まない")

func test_attack_cpu_jumps_to_meet_toss() -> void:
	# 味方が上げた球に対し、会合できるならジャンプする(アタック準備)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	var p = s.players[1]
	p.x = FP.from_int(176)  # ネット際の前衛位置
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)  # 頭上高くから落ちてくる
	s.ball_vy = 0
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "会合可能な球へジャンプする")
	# アタック能力なしなら跳ばない
	p.cpu = _prof(SimCpu.AB_PREDICT)
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "能力なしは跳ばない")

func test_support_zone_complements_human_mate() -> void:
	# 相方が操作キャラの時、CPUは相方の居ない前後ゾーンを守る
	# (相方に張り付いて随伴しない)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.controlled_l = 0
	var cpu = s.players[1]
	cpu.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ROLES | SimCpu.AB_ATTACK)
	# ボールは操作キャラ(slot0)のすぐ側=レシーバーは相方、CPUは支援位置へ
	s.players[0].x = FP.from_int(200)  # 相方は前衛圏(ネット224の近く)
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(150)
	cpu.x = FP.from_int(157)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "相方が前なのでCPUは後衛ゾーンへ下がる")
	# 相方が後衛に居るならCPUは前衛ゾーンへ出て、ゾーン内でボールを横に追う
	s.players[0].x = FP.from_int(60)
	s.ball_x = FP.from_int(60)
	cpu.x = FP.from_int(90)
	input = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "相方が後ろなのでCPUは前衛ゾーンへ出る")

func test_cpu_jumps_to_block() -> void:
	# ブロック能力: 相手アタッカーがネット際で空中+ボールが打点圏なら、
	# ネット際に着いているCPUは跳ぶ
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 1
	s.tick = 200
	s.last_hit_tick = 100  # 反応遅延は消化済み
	var atk = s.players[2]  # 右チームのアタッカー
	atk.x = cfg.net_x + FP.from_int(40)
	atk.y = cfg.floor_y - FP.from_int(140)
	atk.on_ground = 0
	s.ball_x = atk.x + FP.from_int(5)
	s.ball_y = atk.y - FP.from_int(10)
	var blk = s.players[1]  # 左チームの前衛
	blk.x = cfg.net_x - FP.from_int(20)  # ネット際ポストに到着済み
	blk.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_BLOCK)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "ブロックで跳ぶ")
	# 能力なしは跳ばない
	blk.cpu = _prof(SimCpu.AB_PREDICT)
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "能力なしは跳ばない")

func test_no_jump_at_serve_in_flight() -> void:
	# サーブ打球がまだネットを越えていない間(serve_flight)は、味方の上げ球と
	# 同じ観測条件でもジャンプアタックしない(サーブに跳びつく誤反応の抑止)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	var p = s.players[1]
	p.x = FP.from_int(176)
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)
	s.ball_vy = 0
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK)
	s.serve_flight = 1
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "サーブ飛行中は跳ばない")
	s.serve_flight = 0
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "越えた後は通常通り跳ぶ")

func test_reaction_delay_freezes_movement() -> void:
	# 相手の打球直後、遅延tickの間は移動しない(0tick超反応の禁止)。遅延後は動く
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(60)
	s.ball_y = FP.from_int(100)
	s.last_touch_team = 1     # 相手が打った
	s.tick = 100
	s.last_hit_tick = 96      # 4tick前
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT, 10)  # 遅延10tick
	check_eq(SimCpu.decide(s, 1, cfg) & (Simulation.IN_LEFT | Simulation.IN_RIGHT), 0,
		"遅延中は動かない")
	s.tick = 110              # 14tick経過=遅延明け
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "遅延明けは動く")

func test_predict_depth_zero_ignores_wall_bounce() -> void:
	# 予測深度0は壁反射を読めない=壁バウンド球の着地を壁側と誤認する
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.players[1].x = FP.from_int(100)
	s.ball_x = FP.from_int(40)
	s.ball_y = FP.from_int(60)
	s.ball_vx = -FP.from_int(6)  # 左壁へ向かい反射して右へ戻る球
	var deep: int = SimCpu._predict_landing_x(s, cfg, cfg.floor_y, 3)
	var shallow: int = SimCpu._predict_landing_x(s, cfg, cfg.floor_y, 0)
	check(deep > shallow, "深い予測は反射後(右)、浅い予測は壁際で止まる")

func test_miss_roll_is_stable_within_touch() -> void:
	# 乱数はタッチ毎1抽選: 同じlast_hit_tickなら何tick経っても同じ値(震えない)
	var w := _world()
	var s = w[0]
	s.last_hit_tick = 777
	var a: int = SimCpu._roll(SimCpu.SALT_AIM, s, 1)
	s.tick += 30
	var b: int = SimCpu._roll(SimCpu.SALT_AIM, s, 1)
	check_eq(a, b, "タッチ内で値が変わらない")
	s.last_hit_tick = 778
	check(SimCpu._roll(SimCpu.SALT_AIM, s, 1) != a, "次のタッチでは変わる")
	check(SimCpu._roll(SimCpu.SALT_MISS, s, 1) != SimCpu._roll(SimCpu.SALT_AIM, s, 1),
		"saltで判定種別が分離される")

func test_serve_variation_reaches_target_and_crosses() -> void:
	# サーブ多様化: スコアで狙いが変わり、選んだ角度/威力は安全域(24..40/100..125)。
	# 実際にその照準までスイープしてサーブし、ネットを越える
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.score_l = 2
	s.score_r = 1
	s.controlled_l = 1  # サーバー(index0)はCPU
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "多様化サーブでもサーブは実行される")
	check(s.serve_aim >= 8 and s.serve_aim <= 24, "角度が安全域内: " + str(s.serve_aim))
	check(s.serve_pow >= 100 and s.serve_pow <= 125, "威力が安全域内: " + str(s.serve_pow))
	check(s.serve_aim != 25 or s.serve_pow != 100, "既定(25/100)から狙いが変わっている")
	var crossed := false
	for i in 300:
		Simulation.tick(s, [0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "多様化サーブもネットを越える(自滅しない)")

func test_serve_variation_differs_by_score() -> void:
	# 違うスコアなら違う狙いになる(決定論の疑似乱数)
	var w := _world()
	var s = w[0]
	s.score_l = 0
	s.score_r = 0
	var a: Array[int] = SimCpu._serve_target(s, 0)
	s.score_l = 5
	s.score_r = 3
	var b: Array[int] = SimCpu._serve_target(s, 0)
	check(a[0] != b[0] or a[1] != b[1], "スコアが違えば狙いも変わる")

func test_cpu_walks_home_during_pause() -> void:
	# 得点後のポーズ中、CPUは棒立ちせず持ち場へ歩いて戻る
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.players[1].x = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "ポーズ中は持ち場(spawn_front=157)へ戻る")

func test_cpu_returns_to_spawn() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(350)
	s.ball_y = FP.from_int(100)
	s.players[1].x = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "持ち場(spawn_front=157)へ戻る")

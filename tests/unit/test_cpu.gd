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
	for i in cfg.serve_delay_ticks + 10:
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
	for i in cfg.serve_delay_ticks + 10:
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
	for i in cfg.serve_delay_ticks + 5:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUがサーブ(トス)を実行")
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
	for i in cfg.serve_delay_ticks + 5:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右CPUがサーブ(トス)を実行")
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

func test_skill_pack_roundtrip() -> void:
	# 能力マスクの詰め込み/取り出しが4人分正しく往復する
	var w := _world()
	var s = w[0]
	s.cpu_skill_bits = SimCpu.pack_skills(
		SimCpu.LEVEL_WEAK, SimCpu.LEVEL_NORMAL, SimCpu.LEVEL_STRONG, SimCpu.LEVEL_MAX)
	check_eq(SimCpu.skill_of(s, 0), SimCpu.LEVEL_WEAK, "slot0=弱")
	check_eq(SimCpu.skill_of(s, 1), SimCpu.LEVEL_NORMAL, "slot1=普通")
	check_eq(SimCpu.skill_of(s, 2), SimCpu.LEVEL_STRONG, "slot2=強")
	check_eq(SimCpu.skill_of(s, 3), SimCpu.LEVEL_MAX, "slot3=最強")

func test_weak_chases_current_ball_predict_chases_landing() -> void:
	# 弱(能力なし)は現在のボール位置を追い、予測持ちは落下点を追う
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(120)  # 今はplayers[1](x=157)の左
	s.ball_y = FP.from_int(100)
	s.ball_vx = FP.from_int(8)   # 右へ強く飛んでいる=落下点は右
	s.cpu_skill_bits = SimCpu.pack_skills(0, SimCpu.LEVEL_WEAK, 0, 0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "弱は現在位置(左)を追う")
	s.cpu_skill_bits = SimCpu.pack_skills(0, SimCpu.AB_PREDICT, 0, 0)
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
	s.cpu_skill_bits = SimCpu.pack_skills(mask, mask, 0, 0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_RIGHT, "非レシーバーは持ち場(157)へ離れる")
	# 役割なしなら同じ状況でボールへ突っ込む(=みんなで追いかける問題)
	s.cpu_skill_bits = SimCpu.pack_skills(SimCpu.AB_PREDICT, SimCpu.AB_PREDICT, 0, 0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "役割なしはボールへ向かう")

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
	s.cpu_skill_bits = SimCpu.pack_skills(0, SimCpu.LEVEL_MAX, 0, 0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "会合可能な球へジャンプする")
	# アタック能力なしなら跳ばない
	s.cpu_skill_bits = SimCpu.pack_skills(0, SimCpu.AB_PREDICT, 0, 0)
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "能力なしは跳ばない")

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
	for i in cfg.serve_delay_ticks + 30:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "多様化サーブでもサーブは実行される")
	check(s.serve_aim >= 24 and s.serve_aim <= 40, "角度が安全域内: " + str(s.serve_aim))
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

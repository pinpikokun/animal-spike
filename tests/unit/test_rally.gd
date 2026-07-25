extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

func _serve_world(serving: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, serving)
	return [s, cfg]

func test_reset_match_positions() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	check_eq(s.phase, SimState.PHASE_SERVE, "SERVEフェーズ")
	# サーバー(左後衛)は白線(サービスライン)に着く。相手側の後衛は通常スポーン
	check_eq(s.players[0].x, cfg.serve_line, "サーバーはサービスライン")
	check_eq(s.players[2].x, cfg.court_width - FP.from_int(cfg.spawn_back_px), "右後衛の初期位置")
	check_eq(s.touches, 0, "タッチ0")
	check_eq(s.human_team_mask, 0, "試合初期化時は人間チームなし")
	check_eq(s.rally_seq, 0, "試合開始直後のラリー番号は0")
	check_eq(s.last_touch_idx, -1, "試合開始直後は打球者なし")
	check_eq(s.cpu_hit_count, 0, "試合開始直後の打球回数は0")
	check_eq(s.cpu_back_role_mask, 5, "両チームのslot0を初期後衛役にする")

func test_reset_match_clears_cpu_positioning_state() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.human_team_mask = 3
	s.rally_seq = 99
	s.last_touch_idx = 2
	s.cpu_hit_count = 99
	s.cpu_back_role_mask = 15
	Simulation.reset_match(s, cfg, 0)
	check_eq(s.human_team_mask, 0, "試合初期化で人間チームを消す")
	check_eq(s.rally_seq, 0, "試合初期化でラリー番号を0に戻す")
	check_eq(s.last_touch_idx, -1, "試合初期化で打球者を消す")
	check_eq(s.cpu_hit_count, 0, "試合初期化で打球回数を0に戻す")
	check_eq(s.cpu_back_role_mask, 5, "試合初期位置から後衛役を決め直す")

func test_reset_rally_keeps_player_positions() -> void:
	# ラリー再開でキャラをワープさせない(気持ちよさ優先、ユーザー決定)。
	# キャラは自分の足でしか動かない。定位置への帰還はCPUの歩行が担う
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	var moved_x: int = FP.from_int(123)
	s.players[0].x = moved_x
	s.players[0].burn = 30
	s.serve_ball = 1
	s.human_team_mask = 1
	s.last_touch_idx = 3
	s.cpu_hit_count = 13
	var back_role_mask_before: int = s.cpu_back_role_mask
	var rally_seq_before: int = s.rally_seq
	Simulation.reset_rally(s, cfg, 1)
	check_eq(s.players[0].x, moved_x, "reset_rallyでキャラ位置が変わらない")
	check_eq(s.players[0].burn, 0, "reset_rallyで炎上を解除")
	check_eq(s.phase, SimState.PHASE_SERVE, "フェーズはSERVEに戻る")
	check_eq(s.touches, 0, "タッチはリセット")
	check_eq(s.serve_ball, 0, "新ラリーではサーブ由来球状態をリセット")
	check_eq(s.human_team_mask, 1, "ラリー初期化は人間チームを維持")
	check_eq(s.rally_seq, rally_seq_before + 1, "ラリー初期化ごとに通し番号を増やす")
	check_eq(s.last_touch_idx, -1, "ラリー初期化で打球者を消す")
	check_eq(s.cpu_hit_count, 13, "ラリー初期化は打球回数を維持")
	check_eq(s.cpu_back_role_mask, back_role_mask_before, "ラリー初期化は前衛後衛役を維持")

func test_ball_held_by_server() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 10:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_x, s.players[0].x, "ボールはサーバー頭上に固定(x)")
	check_eq(s.ball_y, s.players[0].y - cfg.serve_hold_height, "ボールはサーバー頭上に固定(y)")

func test_serve_toss_stays_in_serve_phase() -> void:
	# 2段階サーブ: アクション1回目はトス。フェーズはSERVEのまま打撃待ちになる
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_SERVE, "トスだけではRALLYにならない")
	check_eq(s.serve_tossed, 1, "トス済みフラグが立つ")
	check(s.ball_vx > 0, "左のトスは右向き(ネット方向)")
	check(s.ball_vy < 0, "トスは上向き")
	check_eq(s.touches, 0, "トスはタッチ数に数えない")

func test_serve_toss_never_crosses_net() -> void:
	# トス単体では絶対にネットを越えない(最悪ケース: 角度上限+高さ上限)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.serve_aim = Simulation.AIM_MAX
	s.serve_pow = Simulation.POW_MAX
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	for i in 300:
		if s.phase != SimState.PHASE_SERVE or s.serve_tossed == 0:
			break  # 空振り得点でサーブ局面を抜けた、または次のトス待ちへ戻った
		check(s.ball_x < cfg.net_x, "トスがネットを越えない(tick %d)" % i)
		Simulation.step(s, [0, 0, 0, 0], cfg)

# ボールの真下へ歩き、近づいたら前トス打ち(アクション+ネット方向)する
# 「人間らしい」サーブ打撃入力
func _chase_and_hit_input(s) -> int:
	var dx: int = s.ball_x - s.players[0].x
	if absi(dx) <= FP.from_int(24):
		return Simulation.IN_ACTION | Simulation.IN_RIGHT
	return Simulation.IN_RIGHT if dx > 0 else Simulation.IN_LEFT

func test_serve_strike_starts_rally() -> void:
	# トス→打撃でRALLY開始。打撃は通常のヒットルール(前トス打ちで越す)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var struck := false
	for i in 600:
		Simulation.step(s, [_chase_and_hit_input(s), 0, 0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			struck = true
			break
	check(struck, "トスを打ってラリーが始まる")
	check_eq(s.touches, 1, "サーブ打撃はタッチ1")
	check_eq(s.last_touch_team, 0, "最終タッチはサーブ側")
	check_eq(s.last_touch_idx, 0, "サーブ打撃者は左後衛")
	check_eq(SimState.team_of(s.last_touch_idx), s.last_touch_team,
		"サーブ打撃者と最終タッチチームが一致")

func test_serve_toss_floor_scores_for_opponent_and_changes_serve() -> void:
	# サーブ空振りを点数なし再トスから相手得点+相手ボールへ変更。2026-07-20設計会仕様
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.serve_tossed, 1, "トス済み")
	for i in 300:
		Simulation.step(s, [0, 0, 0, 0], cfg)  # 打たずに放置
		if s.phase == SimState.PHASE_POINT_PAUSE:
			break
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "床に落ちたら得点間インターバル")
	check_eq(s.score_r, 1, "相手へ1点")
	check_eq(s.score_l, 0, "サーブ側は無得点")
	check_eq(s.serving_team, 1, "次のサーブ権は得点した相手")

func test_serve_strike_only_by_server() -> void:
	# トス済みのボールを打てるのはサーバー本人だけ(相方は不可)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	# 相方(idx1)をボールの真横に置いてアクションさせても打てない
	s.players[1].x = s.ball_x
	s.players[1].y = cfg.floor_y
	var inputs: Array[int] = [0, Simulation.IN_ACTION, 0, 0]
	Simulation.step(s, [0, 0], cfg)  # チーム入力APIでは相方はCPU化するため直接step
	HitResolver._resolve_hit(s, inputs, cfg)
	check_eq(s.phase, SimState.PHASE_SERVE, "相方はサーブ打撃できない")
	check_eq(s.touches, 0, "タッチも発生しない")

func test_serve_in_flight_is_untouchable() -> void:
	# サーブは一発で相手コートへ。打たれたサーブがネットを越えるまでは
	# 味方もサーバー自身も触れない(中継トス・2度打ちの禁止)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.serve_flight = 1
	s.last_touch_team = 0
	s.touches = 1
	s.ball_x = FP.from_int(160)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.players[1].x = s.ball_x
	s.players[1].y = cfg.floor_y
	s.players[1].hit_cooldown = 0
	HitResolver._resolve_hit(s, [0, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(s.touches, 1, "サーブ飛行中は味方が触れない")
	# ネットを越えたらserve_flightが消え、通常通り触れる
	s.serve_flight = 0
	HitResolver._resolve_hit(s, [0, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(s.touches, 2, "越えた後は触れる")

func test_serve_flight_clears_on_net_cross() -> void:
	# サーブ打球がネット上空を越えた瞬間にserve_flightが下りる
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.serve_flight = 1
	s.ball_x = cfg.net_x - FP.from_int(4)
	s.ball_y = cfg.net_top_y - FP.from_int(40)
	s.ball_vx = FP.from_int(480) / 60
	s.ball_vy = 0
	Simulation.step(s, [0, 0], cfg)
	check_eq(s.serve_flight, 0, "ネット越えでサーブ飛行が終わる")

func test_serve_strike_marks_ball_until_receiver_touch() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	var server = s.players[0]
	s.serve_tossed = 1
	s.ball_x = server.x
	s.ball_y = server.y - FP.from_int(10)
	server.hit_cooldown = 0
	Simulation._step_players_and_hits(
		s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_RALLY, "サーブ打撃成立でラリーへ移る")
	check_eq(s.serve_flight, 1, "ネット越え前の接触禁止状態を立てる")
	check_eq(s.serve_ball, 1, "受け手の初接触までサーブ由来球状態を立てる")

func test_server_is_pinned_during_serve() -> void:
	# サーブ照準中、横キーは角度調整に使うためサーバーは移動しない(白線の位置に固定)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 30:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.players[0].x, cfg.serve_line, "左サーバーは白線の位置から動かない")
	# 右チームも鏡像で検証
	var w2 := _serve_world(1)
	var s2 = w2[0]
	for i in 30:
		Simulation.step(s2, [0, 0, Simulation.IN_LEFT, 0], cfg)
	check_eq(s2.players[2].x, cfg.court_width - cfg.serve_line, "右サーバーも白線に固定")

func test_serve_aim_up_becomes_vertical() -> void:
	# ネットと逆方向キーで照準を立てて真上(0度)にできる。真上サーブは横成分ゼロ
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 40:
		Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], cfg)
	check_eq(s.serve_aim, 0, "逆方向キー長押しで照準が真上(0度)まで立つ")
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.serve_tossed, 1, "アクションでトスが上がる")
	check_eq(s.ball_vx, 0, "真上トスは横成分ゼロ")
	check(s.ball_vy < 0, "真上トスは上向き")

func test_serve_power_adjust_with_up_down() -> void:
	# 上キーでトスが高くなり(上限130%)、下キーで低くなる(下限60%)。
	# 高さ%は縦成分にのみ効く(横はネット到達不能の固定威力)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 60:
		Simulation.step(s, [Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.serve_pow, Simulation.POW_MAX, "上キー長押しで高さ上限")
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var strong_vy: int = s.ball_vy
	var strong_vx: int = s.ball_vx
	var w2 := _serve_world(0)
	var s2 = w2[0]
	for i in 60:
		Simulation.step(s2, [Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s2.serve_pow, Simulation.POW_MIN, "下キー長押しで高さ下限")
	Simulation.step(s2, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(strong_vy < s2.ball_vy, "高さ%が大きいほど高く上がる(上向き=負が大きい)")
	# 横速度は着弾距離固定のため滞空(高さ)に反比例する。高いトスほど横は遅い
	check(strong_vx < s2.ball_vx, "高いトスほど横は遅い(着弾距離を保つ)")

func test_serve_aim_flattens_toward_net() -> void:
	# ネット方向キーで照準が倒れ(上限60度)、トスが遠く(前方)へ飛ぶ
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 80:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.serve_aim, Simulation.AIM_MAX, "ネット方向キー長押しで上限60度")
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var far_vx: int = s.ball_vx
	check(far_vx > 0, "倒した照準はネット方向へ飛ぶ")
	# 既定角(25度)と比べ、倒した分だけ横速度が大きい(=遠くへ落ちる)
	var w2 := _serve_world(0)
	var s2 = w2[0]
	Simulation.step(s2, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(far_vx > s2.ball_vx, "60度のトスは既定角より遠くへ飛ぶ")

func test_serve_default_aim_crosses_net() -> void:
	# 既定角(25度)でトス→アクション押しっぱなし+前進で打つとネットを越えて届く
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var crossed := false
	for i in 600:
		var input: int = _chase_and_hit_input(s) if s.phase == SimState.PHASE_SERVE \
			else Simulation.IN_RIGHT
		Simulation.step(s, [input, 0, 0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
	check(crossed, "既定角のトス→打撃でネットを越える")

func test_server_jump_suppressed_until_toss() -> void:
	# 上キー=ジャンプ+照準のため、トス前のサーバーは上を押してもジャンプしない
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_JUMP | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 1, "トス前のサーバーはジャンプできない")
	check_eq(s.phase, SimState.PHASE_SERVE, "アクション無しではサーブされない")

func test_floor_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.serve_ball = 1
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "左コートに落ちたら右チームの得点")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "得点後はポーズ")
	check_eq(s.serve_ball, 0, "得点時にサーブ由来球状態を解除")

func test_flame_ball_resets_when_it_lands_for_a_point() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_power = 1
	s.ball_flame = 1
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_flame, 0, "着地得点で燃える状態を解除")
	check_eq(s.ball_power, 0, "着地得点でパワー状態も解除")

func test_pause_then_new_serve_by_scorer() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	for i in cfg.point_pause_ticks + 1:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_SERVE, "ポーズ後は次のサーブ")
	check_eq(s.serving_team, 1, "得点チームがサーブ")

func test_players_move_during_point_pause() -> void:
	# 得点後のポーズ中も操作は生かす(操作が死ぬ時間を作らない)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	var x0: int = s.players[0].x
	Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x > x0, "ポーズ中も右移動できる")

func test_players_jump_during_point_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "ポーズ中もジャンプできる")

func test_ball_bounces_on_floor_during_pause() -> void:
	# 得点後のポーズ中、ボールは凍結せず床で減衰バウンドする(得点はしない)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = FP.from_int(300)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "ポーズ中の床接触で上向きに反射")
	check_eq(s.score_l, 0, "ポーズ中の床接触は得点にならない(左)")
	check_eq(s.score_r, 0, "ポーズ中の床接触は得点にならない(右)")

func test_ball_bounce_damps_during_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = FP.from_int(300)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	var v0: int = FP.from_int(100)
	s.ball_vy = v0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(-s.ball_vy < v0, "バウンドで速度が減衰する")

func test_ball_settles_at_rest_during_pause() -> void:
	# ポーズ中、転がるボールは小刻みに跳ね続けず、いずれ床上で完全静止する
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = 1000000  # 収束を観察するためポーズを維持(reset_rallyに入らない)
	s.ball_x = FP.from_int(150)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(40)
	s.ball_vx = FP.from_int(3)
	s.ball_vy = FP.from_int(2)
	for i in 600:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vy, 0, "縦速度が完全に止まる")
	check_eq(s.ball_vx, 0, "横速度が完全に止まる")
	check_eq(s.ball_y, cfg.floor_y - cfg.ball_radius, "床にスナップして静止")

func test_ball_settles_from_resonant_bounce() -> void:
	# 共振速度帯(レビュー指摘: vy=7px/tick・高さ40pxで数千tick跳ね続けた)でも
	# 固定量減衰により有限時間で静止することの回帰テスト
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = 1000000
	s.ball_x = FP.from_int(200)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(40)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(7)
	for i in 600:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vy, 0, "共振速度帯でも600tick以内に縦速度が止まる")
	check_eq(s.ball_y, cfg.floor_y - cfg.ball_radius, "床にスナップして静止")

func test_ball_rolls_into_wall_during_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_y = cfg.floor_y - cfg.ball_radius
	s.ball_vx = -FP.from_int(5)
	s.ball_vy = 0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "ポーズ中も壁で跳ね返る(慣性維持)")

func test_players_move_after_game_over() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_GAME_OVER
	s.winner = 1
	var x0: int = s.players[0].x
	Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x > x0, "ゲームオーバー後も移動できる")

func test_touch_over_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches
	s.last_touch_team = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "4タッチ目で相手の得点")

func test_third_touch_is_legal() -> void:
	# 仕様2.3「3回以内に相手コートへ返球」= 3タッチ目は合法、4タッチ目が反則
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches - 1
	s.last_touch_team = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, cfg.max_touches, "3タッチ目が数えられる")
	check_eq(s.score_r, 0, "3タッチ目では失点しない")
	check_eq(s.phase, SimState.PHASE_RALLY, "ラリーは続行する")

func test_touch_over_at_floor_scores_once() -> void:
	# タッチ超過失点と床接触が同一tickに重なっても得点は1回だけ(1ラリー2点の禁止)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches
	s.last_touch_team = 0
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(10)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "同一tickの床接触で二重得点しない")

func test_hit_disabled_during_point_pause() -> void:
	# 掟1の但し書き: ポーズ中は移動・ジャンプ可でもヒットは無効(転がり演出と得点整合を守る)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "ポーズ中はタッチが増えない")
	check_eq(s.players[0].hit_cooldown, 0, "ポーズ中は硬直も付かない")
	check_eq(s.ball_vx, 0, "ポーズ中のヒット入力でボールが加速しない")

func test_hit_disabled_after_game_over() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_GAME_OVER
	s.winner = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "勝敗確定後はタッチが増えない")
	check_eq(s.ball_vx, 0, "勝敗確定後のヒット入力でボールが加速しない")

func test_win_at_points_to_win() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_r = cfg.points_to_win - 1
	s.score_l = 5
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.winner, 1, "勝利点到達で右チームの勝ち")
	check_eq(s.phase, SimState.PHASE_GAME_OVER, "ゲーム終了フェーズ")

func test_deuce_requires_two_point_lead() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_l = cfg.points_to_win - 1
	s.score_r = cfg.points_to_win - 1
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(350)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_l, cfg.points_to_win, "左が勝利点に到達")
	check_eq(s.winner, -1, "1点差はデュースで未決着")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "続行")

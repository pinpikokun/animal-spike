extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")

func test_server_index_is_derived_from_serving_team() -> void:
	var s = SimState.new()
	s.serving_team = 0
	check_eq(SimState._server_index(s), 0, "左チームのサーバー")
	s.serving_team = 1
	check_eq(SimState._server_index(s), 2, "右チームのサーバー")

func test_equal_states_equal_hash() -> void:
	var a = SimState.new()
	var b = SimState.new()
	check_eq(a.state_hash(), b.state_hash(), "初期状態のハッシュが一致")

func test_hash_changes_on_diff() -> void:
	var a = SimState.new()
	var b = SimState.new()
	b.ball_x = 1
	check(a.state_hash() != b.state_hash(), "1bitの差でハッシュが変わる")
	var c = SimState.new()
	c.players[3].vy = -1
	check(a.state_hash() != c.state_hash(), "プレイヤー差分でも変わる")
	var d = SimState.new()
	d.players[1].drive_recovery_delay = 1
	check(a.state_hash() != d.state_hash(), "回復ディレイ差分でも変わる")

func test_serialize_length() -> void:
	# tick(1) + プレイヤー4体x36(回復ディレイを含む)
	# + 全体37(CPU打球回数/後衛役を含む) + エンティティ8スロットx8欄
	# 1 + 4x36 + 37 + 8x8 = 246
	check_eq(SimState.new().to_int_array().size(), 246,
		"直列化長(ドライブ残量/回復端数/飛来アタック属性を含む)")

func test_load_int_array_roundtrip() -> void:
	# to_int_array→load_int_arrayの往復で全フィールドが復元される(ロールバックの土台)
	var a = SimState.new()
	a.tick = 123
	a.ball_x = 456789
	a.ball_ghost = 1
	a.ball_flame = 1
	a.serve_ball = 1
	a.phase = SimState.PHASE_RALLY
	a.score_l = 7
	a.winner = 1
	a.players[2].x = 999
	a.players[2].burn = 37
	a.players[2].drive_gauge = 3456
	a.players[2].drive_recovery_progress = 78
	a.players[2].drive_recovery_delay = 123
	a.players[2].receive_stance = 2
	a.players[2].just_receive_flash = 7
	a.players[2].just_receive_event = 11
	a.players[2].burnout_ticks = 456
	a.players[2].quake_stun = 5
	a.players[2].stun_action_held = 1
	a.players[2].stun_mash_event = 4
	a.hip_quake_event = 9
	a.ball_guard_damage = 35
	a.ball_defense_class = 2
	a.human_team_mask = 3
	a.rally_seq = 17
	a.last_touch_idx = 2
	a.cpu_hit_count = 23
	a.cpu_back_role_mask = 6
	a.players[3].hit_cooldown = 5
	var b = SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.state_hash(), a.state_hash(), "往復でハッシュ一致")
	check_eq(b.players[2].x, 999, "プレイヤー座標の復元")
	check_eq(b.players[2].burn, 37, "炎上残りtickの復元")
	check_eq(b.players[2].drive_gauge, 3456, "ドライブゲージ残量の復元")
	check_eq(b.players[2].drive_recovery_progress, 78, "ドライブ回復端数の復元")
	check_eq(b.players[2].drive_recovery_delay, 123, "ドライブ回復ディレイの復元")
	check_eq(b.players[2].receive_stance, 2, "レシーブ構えの復元")
	check_eq(b.players[2].just_receive_flash, 7, "ジャストレシーブフラッシュの復元")
	check_eq(b.players[2].just_receive_event, 11, "ジャストレシーブ演出イベントの復元")
	check_eq(b.players[2].burnout_ticks, 456, "バーンアウト残りtickの復元")
	check_eq(b.players[2].quake_stun, 5, "地震硬直残りtickの復元")
	check_eq(b.players[2].stun_action_held, 1, "気絶連打入力ラッチの復元")
	check_eq(b.players[2].stun_mash_event, 4, "気絶連打演出イベントの復元")
	check_eq(b.hip_quake_event, 9, "着地地震イベントの復元")
	check_eq(b.ball_guard_damage, 35, "飛来球の絶対ガード削り値の復元")
	check_eq(b.ball_defense_class, 2, "飛来球の防御分類の復元")
	check_eq(b.human_team_mask, 3, "人間チームマスクの復元")
	check_eq(b.rally_seq, 17, "ラリー通し番号の復元")
	check_eq(b.last_touch_idx, 2, "最終打球者の復元")
	check_eq(b.cpu_hit_count, 23, "CPU位置取り用の打球回数の復元")
	check_eq(b.cpu_back_role_mask, 6, "CPU前衛後衛役の復元")
	check_eq(b.tick, 123, "tickの復元")
	check_eq(b.ball_ghost, 1, "ゴースト状態の復元")
	check_eq(b.ball_flame, 1, "炎状態の復元")
	check_eq(b.serve_ball, 1, "サーブ由来球状態の復元")

func test_load_int_array_overwrites_everything() -> void:
	# 汚れた状態に読み込んでも完全に上書きされる(ロールバック時は必ず過去へ戻す)
	var clean = SimState.new()
	var snapshot: Array[int] = clean.to_int_array()
	var dirty = SimState.new()
	dirty.tick = 555
	dirty.ball_vy = -777
	dirty.players[0].on_ground = 0
	dirty.load_int_array(snapshot)
	check_eq(dirty.state_hash(), clean.state_hash(), "汚れが完全に消える")

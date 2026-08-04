extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const ScoreUI := preload("res://src/display/score_ui.gd")
const DebugView := preload("res://src/display/main.gd")

func test_drive_segments_show_continuous_zero_to_one_hundred_values() -> void:
	var helper := Callable(ScoreUI, "drive_segment_fill_percents")
	check(helper.is_valid(), "ドライブ連続塗りの純粋helperが存在する")
	if not helper.is_valid():
		return
	var cases := [
		[0, [0, 0, 0, 0, 0, 0]],
		[5, [30, 0, 0, 0, 0, 0]],
		[15, [90, 0, 0, 0, 0, 0]],
		[25, [100, 50, 0, 0, 0, 0]],
		[35, [100, 100, 10, 0, 0, 0]],
		[99, [100, 100, 100, 100, 100, 94]],
		[100, [100, 100, 100, 100, 100, 100]],
	]
	for row in cases:
		check_eq(helper.call(row[0], 100), row[1],
			"6区画は本数でなく連続値の目盛り: drive=%d" % row[0])

func test_burnout_blink_reads_only_remaining_ticks_and_state_tick() -> void:
	var helper := Callable(ScoreUI, "burnout_is_dim")
	check(helper.is_valid(), "バーンアウト点滅の純粋helperが存在する")
	if not helper.is_valid():
		return
	check_eq(helper.call(0, 0), false, "残り0は点滅しない")
	check_eq(helper.call(1, 0), true, "残り正かつ明滅位相0は暗くする")
	check_eq(helper.call(1, 5), false, "同じ残り値でもtick位相だけで明滅する")

func test_burnout_has_no_full_screen_red_flash() -> void:
	var source := FileAccess.get_file_as_string("res://src/display/game_view.gd")
	check(not source.contains("burnout_screen_flash"),
		"バーンアウト突入時に全画面フラッシュを発火しない")
	check(not source.contains("Color(0.75, 0.08, 0.08, 0.38)"),
		"目に強い全画面赤レイヤーを描画しない")

func test_development_meter_exposes_resource_and_resolution_diagnostics() -> void:
	var helper := Callable(DebugView, "combat_debug_text")
	check(helper.is_valid(), "戦闘リソース開発表示の純粋helperが存在する")
	if not helper.is_valid():
		return
	var s = SimState.new()
	var p = s.players[0]
	p.health = 73
	p.max_health = 100
	p.drive_gauge = 24
	p.drive_reserved = 5
	p.attack_recovery_delay_ticks = 30
	p.attack_recovery_window_ticks = 180
	p.attack_recovery_fraction_ticks = 29
	p.attack_recovery_granted = 2
	p.stance_action_id = 11
	p.stance_pre_read_candidate = 1
	p.stance_cost_resolved = 1
	p.burnout_ticks = 321
	p.stun_ticks = 45
	p.set("last_stance_result", 2)
	p.set("last_stance_cost_resolution", 2)
	p.set("last_health_damage", 10)
	p.set("last_health_multiplier_pct", 40)
	p.set("last_stun_end_reason", 1)
	s.possession_id = 7
	s.ball_attack_id = 9
	var out: String = helper.call(s)
	for token in ["P0", "HP=73/100", "DMG=10", "MUL=40",
			"DRV=24", "RES=5", "REC=30/180/29/2", "POS=7", "ATK=9",
			"STANCE=11", "PRE=1", "RESULT=2", "COST=2", "BO=321",
			"STUN=45", "END=1"]:
		check(out.contains(token), "開発表示に診断値を含む: " + token)

func test_diagnostic_values_follow_production_resource_transitions() -> void:
	var cfg = SimConfig.new()
	var p = SimState.new().players[0]
	p.drive_gauge = 10
	check(CombatResources.reserve_stance(p, 1, 10, cfg), "先読み構えを予約")
	p.stance_committed_attack_id = 7
	p.stance_pre_read_candidate = 1
	check_eq(CombatResources.resolve_stance_contact(p, 7, 10, cfg),
		SimState.STANCE_RESULT_PRE_READ, "先読み結果")
	check_eq(p.last_stance_cost_resolution, SimState.STANCE_COST_RELEASED,
		"先読みは予約解放")
	p.stance_exit_recovery_ticks = 0
	check(CombatResources.reserve_stance(p, 2, 20, cfg), "反応構えを予約")
	check_eq(CombatResources.resolve_stance_contact(p, 8, 19, cfg),
		SimState.STANCE_RESULT_REACTION, "反応結果")
	check_eq(p.last_stance_cost_resolution, SimState.STANCE_COST_SPENT,
		"反応は予約消費")
	p.health = 100
	check_eq(CombatResources.apply_health_damage(p, 10, cfg, 40), 10,
		"体力損害を適用")
	check_eq(p.last_health_damage, 10, "最後の実損害")
	check_eq(p.last_health_multiplier_pct, 40, "最後の防御倍率")
	p.health = 10
	CombatResources.apply_health_damage(p, 10, cfg)
	CombatResources.recover_health_stun(p, SimState.STUN_END_TIMED)
	check_eq(p.last_stun_end_reason, SimState.STUN_END_TIMED, "時間復帰理由")

extends "res://tests/test_case.gd"

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const Chars := preload("res://src/sim/chars.gd")

func test_rank_tables_are_absolute_monotonic_and_evenly_spaced() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.guard_max_by_rank, [120, 110, 100, 90, 80],
		"GUARDランクは絶対値")
	check_eq(cfg.power_guard_damage_by_rank, [35, 30, 25, 20, 15],
		"POWERランクはジャスト削り絶対値")
	for rank in 4:
		check_eq(cfg.guard_max_by_rank[rank] - cfg.guard_max_by_rank[rank + 1], 10,
			"耐久は10刻みで単調減少")
		check_eq(cfg.power_guard_damage_by_rank[rank]
			- cfg.power_guard_damage_by_rank[rank + 1], 5,
			"削りは5刻みで単調減少")

func test_absolute_damage_hit_count_matrix() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.guard_max_for_rank(Chars.Profile.RANK_C)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C), 4,
		"C対Cは4発")
	check_eq((cfg.guard_max_for_rank(Chars.Profile.RANK_E)
		+ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_A) - 1)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_A), 3,
		"POWER A対GUARD Eは3発")
	check_eq(cfg.guard_max_for_rank(Chars.Profile.RANK_A)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_E), 8,
		"POWER E対GUARD Aは8発")

func test_reset_reads_guard_rank_as_absolute_value() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_UME, Chars.CHAR_PIYO, Chars.CHAR_PANDA, Chars.CHAR_CARBY])
	check_eq(s.players[0].guard_max, 120, "GUARD A")
	check_eq(s.players[1].guard_max, 80, "GUARD E")
	check_eq(s.players[2].guard_max, 100, "GUARD C")
	check_eq(s.players[3].guard_max, 90, "GUARD D")

func test_stun_mash_uses_action_press_edges_only() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.stun = 20
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 16, "初回押下は通常1tick+連打3tick短縮")
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 15, "押しっぱなしは通常減衰のみ")
	PlayerMovement._step_player(p, 0, cfg, 0)
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 10, "離して再押下すると再び短縮")
	check_eq(p.stun_mash_event, 2, "表示用イベントも押下エッジだけ進む")

func test_stun_mashing_recovers_faster_than_no_input() -> void:
	var cfg = SimConfig.new()
	var mashed = SimState.Player.new()
	var idle = SimState.Player.new()
	mashed.stun = 20
	idle.stun = 20
	for tick in 8:
		var input: int = Simulation.IN_ACTION if tick % 2 == 0 else 0
		PlayerMovement._step_player(mashed, input, cfg, 0)
		PlayerMovement._step_player(idle, 0, cfg, 0)
	check_eq(mashed.stun, 0, "交互連打は8tick以内に復帰")
	check(idle.stun > 0, "非連打は同じ時間では気絶中")

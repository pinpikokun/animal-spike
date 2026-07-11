extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")

func test_loads_default_rules() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.tick_rate, 60, "tick_rate")
	check_eq(cfg.court_width, FP.from_int(448), "court_width")
	check_eq(cfg.floor_y, FP.from_int(320), "floor_y")
	check_eq(cfg.points_to_win, 15, "15点先取")
	check_eq(cfg.deuce, true, "デュース有")

func test_default_rules_valid() -> void:
	check_eq(SimConfig.new().valid, true, "既定ルールはvalid")

func test_invalid_rules_detected() -> void:
	# 下のUSER ERROR出力はこのテストが意図的に出させているもの(異常系の検証)
	var cfg = SimConfig.new("res://tests/fixtures/bad_rules.json")
	check_eq(cfg.valid, false, "floatを含むルールはinvalidになる")

func test_m1a_keys_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.net_x, FP.from_int(224), "net_x")
	check_eq(cfg.max_touches, 3, "max_touches")
	check(cfg.spike_vx > 0, "spike_vxが正")
	check(cfg.serve_vy > 0, "serve_vy(上向き量)が正")
	check(cfg.hit_cooldown_ticks > 0, "hit_cooldownが正")
	check_eq(cfg.spawn_back_px, 56, "spawn_back_px")

func test_values_are_int() -> void:
	var cfg = SimConfig.new()
	check(typeof(cfg.gravity) == TYPE_INT, "gravityがint")
	check(typeof(cfg.move_speed) == TYPE_INT, "move_speedがint")
	check(typeof(cfg.jump_speed) == TYPE_INT, "jump_speedがint")
	check(cfg.gravity > 0, "gravityが正")
	check(cfg.move_speed > 0, "move_speedが正")

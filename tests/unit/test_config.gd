extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")

func test_loads_default_rules() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.tick_rate, 60, "tick_rate")
	check_eq(cfg.court_width, FP.from_int(640), "court_width")
	check_eq(cfg.floor_y, FP.from_int(320), "floor_y")
	check_eq(cfg.points_to_win, 15, "15点先取")
	check_eq(cfg.deuce, true, "デュース有")

func test_values_are_int() -> void:
	var cfg = SimConfig.new()
	check(typeof(cfg.gravity) == TYPE_INT, "gravityがint")
	check(typeof(cfg.move_speed) == TYPE_INT, "move_speedがint")
	check(typeof(cfg.jump_speed) == TYPE_INT, "jump_speedがint")
	check(cfg.gravity > 0, "gravityが正")
	check(cfg.move_speed > 0, "move_speedが正")

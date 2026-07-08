extends "res://tests/test_case.gd"

func test_runner_works() -> void:
	check_eq(1 + 1, 2, "算数が壊れていない")

extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")

func test_roundtrip() -> void:
	check_eq(FP.to_int(FP.from_int(5)), 5, "5の往復")
	check_eq(FP.to_int(FP.from_int(-3)), -3, "-3の往復")
	check_eq(FP.ONE, 65536, "ONE")

func test_mul() -> void:
	check_eq(FP.mul(FP.from_int(3), FP.from_int(4)), FP.from_int(12), "3x4")
	check_eq(FP.mul(FP.ONE / 2, FP.from_int(6)), FP.from_int(3), "0.5x6")
	check_eq(FP.mul(FP.from_int(-3), FP.from_int(4)), FP.from_int(-12), "負の積")

func test_div() -> void:
	check_eq(FP.div(FP.from_int(12), FP.from_int(4)), FP.from_int(3), "12/4")
	check_eq(FP.div(FP.from_int(1), FP.from_int(2)), FP.ONE / 2, "1/2")

func test_to_int_floors_negative() -> void:
	# 算術シフトなので負数は床方向。この挙動を回帰検知のため固定する
	check_eq(FP.to_int(-1), -1, "微小負数の床")

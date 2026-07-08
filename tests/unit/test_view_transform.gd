extends "res://tests/test_case.gd"

const ViewTransform := preload("res://src/display/view_transform.gd")

func test_to_px_whole() -> void:
	check_eq(ViewTransform.to_px(65536), 1.0, "1.0fp=1px")

func test_to_px_fraction() -> void:
	check_eq(ViewTransform.to_px(98304), 1.5, "1.5fp=1.5px")

func test_to_px_zero() -> void:
	check_eq(ViewTransform.to_px(0), 0.0, "0fp=0px")

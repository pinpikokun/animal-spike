extends "res://tests/test_case.gd"

const DisplayScale := preload("res://src/display/display_scale.gd")

func test_1080p_is_3x() -> void:
	check_eq(DisplayScale.max_integer_scale(1920, 1080, 640, 360), 3, "1080pで3倍")

func test_1440p_is_4x() -> void:
	check_eq(DisplayScale.max_integer_scale(2560, 1440, 640, 360), 4, "1440pで4倍")

func test_4k_is_6x() -> void:
	check_eq(DisplayScale.max_integer_scale(3840, 2160, 640, 360), 6, "4Kで6倍")

func test_small_screen_min_1x() -> void:
	check_eq(DisplayScale.max_integer_scale(700, 400, 640, 360), 1, "小画面でも最低1倍")

func test_wide_screen_limited_by_height() -> void:
	check_eq(DisplayScale.max_integer_scale(3440, 1440, 640, 360), 4, "ウルトラワイドは高さ律速")

func test_clamp_intensity_low() -> void:
	check_eq(DisplayScale.clamp_intensity(-0.5), 0.0, "下限0")

func test_clamp_intensity_high() -> void:
	check_eq(DisplayScale.clamp_intensity(2.0), 1.0, "上限1")

func test_clamp_intensity_mid() -> void:
	check_eq(DisplayScale.clamp_intensity(0.4), 0.4, "範囲内はそのまま")

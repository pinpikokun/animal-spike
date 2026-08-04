# 標準ジャンプの決定論的な縦軌道。キャラ性能値と入力判断は呼び出し側が渡す。
extends RefCounted

const FP := preload("res://src/sim/fp.gd")

const REFERENCE_HEIGHT_PX := 110
const REFERENCE_RISE_TICKS := 25
const REFERENCE_FALL_TICKS := 27
const MAX_ARC_TICKS := 512
const FP_ONE := 1 << 16
const RISE_GRAVITY := \
	REFERENCE_HEIGHT_PX * 2 * FP_ONE \
	/ (REFERENCE_RISE_TICKS * (REFERENCE_RISE_TICKS - 1))
const FALL_GRAVITY := \
	REFERENCE_HEIGHT_PX * 2 * FP_ONE \
	/ (REFERENCE_FALL_TICKS * (REFERENCE_FALL_TICKS + 1))

static func gravity(rising: bool) -> int:
	return RISE_GRAVITY if rising else FALL_GRAVITY

static func _duration_product(duration: int, rising: bool) -> int:
	var neighbor := duration - 1 if rising else duration + 1
	return gravity(rising) * duration * neighbor

static func ticks(height_px: int, rising: bool) -> int:
	var target := FP.from_int(maxi(height_px, 1) * 2)
	var low := 1
	var high := 2
	while high < MAX_ARC_TICKS and _duration_product(high, rising) < target:
		low = high
		high = mini(high * 2, MAX_ARC_TICKS)
	while high - low > 1:
		var middle := (low + high) / 2
		if _duration_product(middle, rising) < target:
			low = middle
		else:
			high = middle
	var low_error := absi(_duration_product(low, rising) - target)
	var high_error := absi(_duration_product(high, rising) - target)
	# 同誤差は長い側を選び、速い側へ丸めない。
	return low if low_error < high_error else high

static func launch_velocity(height_px: int) -> int:
	var duration := ticks(height_px, true)
	if duration <= 1:
		return 0
	var rise_gravity := gravity(true)
	var half_arc := rise_gravity * duration * (duration - 1) / 2
	var speed := (FP.from_int(height_px) + half_arc) / (duration - 1)
	return -speed

static func advance_velocity(vy: int, jump_held: bool) -> int:
	if vy < 0 and not jump_held:
		vy = vy / 2
	return vy + gravity(vy < 0)

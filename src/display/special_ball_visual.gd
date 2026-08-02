# 原作BALL.DAT由来の特殊球セルを同期状態から選ぶ純粋関数。
# 専用絵がない技は通常球へ戻し、表示層からsim状態は変更しない。
extends RefCounted

const Chars := preload("res://src/sim/chars.gd")

const FRAME_HOLD_TICKS := 4
const CELLS := {
	Chars.SUPER_GUST_BALL: [4, 5],
	Chars.SUPER_GUST_ATTACK: [4, 5],
	Chars.SUPER_FLAME_ATTACK: [12, 13],
	Chars.SUPER_THUNDER_BALL: [18, 19, 20],
	Chars.SUPER_BUBBLE_PACK: [21, 22],
}

static func uses_special_sheet(s) -> bool:
	return s.ball_special_id in CELLS

static func cell_for(s) -> int:
	var frames: Array = CELLS.get(s.ball_special_id, [])
	if frames.is_empty():
		return -1
	var frame: int = int(s.tick / FRAME_HOLD_TICKS) % frames.size()
	return int(frames[frame])

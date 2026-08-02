# 特殊球の排他的な同期状態と、原作座標・時間換算の正本。
extends RefCounted

const Chars := preload("res://src/sim/chars.gd")

static func set_special(s, special_id: int, owner_idx: int,
		origin_vx: int = 0) -> void:
	s.ball_special_id = special_id
	s.ball_special_phase = 0
	s.ball_special_ticks = 0
	s.ball_special_owner_idx = owner_idx
	s.ball_special_origin_vx = origin_vx
	s.ball_held_by = -1

static func clear_special(s) -> void:
	s.ball_special_id = 0
	s.ball_special_phase = 0
	s.ball_special_ticks = 0
	s.ball_special_owner_idx = -1
	s.ball_special_origin_vx = 0
	s.ball_held_by = -1

static func is_visible(s) -> bool:
	return s.ball_special_id != Chars.SUPER_DISAPPEARING_BALL \
		and s.ball_special_id != Chars.SUPER_TRANSFER_BALL

static func is_contactable(s) -> bool:
	return is_visible(s) and s.ball_held_by < 0

static func step(s, _cfg) -> bool:
	# Task 4で各専用軌道を接続する。保持中だけは今から通常積分を止める。
	return s.ball_held_by >= 0

static func original_ticks(original_tick_count: int, cfg) -> int:
	var numerator: int = original_tick_count * cfg.tick_rate * 1000
	return (numerator + cfg.original_tick_rate_milli / 2) \
		/ cfg.original_tick_rate_milli

static func is_above_original_y(s, original_y: int, cfg) -> bool:
	var ball_height: int = cfg.floor_y - s.ball_y
	var current_net_height: int = cfg.floor_y - cfg.net_top_y
	return ball_height * 33 > (291 - original_y) * current_net_height

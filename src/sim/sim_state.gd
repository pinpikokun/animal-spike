# シミュレーションの全状態。全フィールドint(fp)。float禁止
# フィールドを増やしたら必ずto_int_arrayにも足すこと(ハッシュ対象漏れはデシンクの温床)
extends RefCounted

const PLAYER_COUNT := 4

class Player:
	var x: int = 0
	var y: int = 0
	var vx: int = 0
	var vy: int = 0
	var on_ground: int = 1

var tick: int = 0
var players: Array[Player] = []
var ball_x: int = 0
var ball_y: int = 0
var ball_vx: int = 0
var ball_vy: int = 0

func _init() -> void:
	for i in PLAYER_COUNT:
		players.append(Player.new())

func to_int_array() -> Array[int]:
	var out: Array[int] = [tick]
	for p in players:
		out.append(p.x)
		out.append(p.y)
		out.append(p.vx)
		out.append(p.vy)
		out.append(p.on_ground)
	out.append(ball_x)
	out.append(ball_y)
	out.append(ball_vx)
	out.append(ball_vy)
	return out

func state_hash() -> int:
	# FNV-1a 64bit。オフセット値はint64符号付き表現
	# GDScriptのint64はオーバーフロー時にラップするのでそのまま使える
	var h := -3750763034362895579
	for v in to_int_array():
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h

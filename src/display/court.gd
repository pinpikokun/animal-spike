# コート背景・床・ネットの描画。表示層(float可)。sim_configの寸法(fp)を読む。
# 原作準拠のオブリーク(斜め見下ろし)投影: 床を奥へ後退するグリッド面として描く。
# キャラ/ボールのドット絵は傾けない(直立=クリスプ維持)。遠近は床の描画だけで出す。
extends Node2D

const ViewTransform := preload("res://src/display/view_transform.gd")

const VIEW_H := 360.0
const FLOOR_DEPTH := 110.0   # 床が手前の立ち位置から奥(地平)へ後退する高さ(px)
const BACK_CONVERGE := 0.30  # 奥端が中央へ寄る率(0=平行, 大きいほど強い遠近)
const DEPTH_ROWS := 6        # 床の奥行き線(横線)の本数
const LANES := 8             # 床のレーン線(縦線)の本数

var cfg

func setup(config) -> void:
	cfg = config
	queue_redraw()

func _draw() -> void:
	if cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var fy := ViewTransform.to_px(cfg.floor_y)      # キャラが立つ手前の床ライン
	var horizon := fy - FLOOR_DEPTH                  # 床の奥端(地平)
	var cx := w * 0.5
	var back_l := lerpf(0.0, cx, BACK_CONVERGE)      # 奥端の左
	var back_r := lerpf(w, cx, BACK_CONVERGE)        # 奥端の右

	# 奥の壁(濃い青)
	draw_rect(Rect2(0.0, 0.0, w, VIEW_H), Color(0.09, 0.11, 0.52))
	# 壁の薄い横グリッド(地平より上)
	var wy := 0.0
	while wy < horizon:
		draw_line(Vector2(0.0, wy), Vector2(w, wy), Color(0.16, 0.19, 0.62), 1.0)
		wy += 14.0

	# 床面(明るい青の台形): 手前は全幅、奥は中央へ収束
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, VIEW_H), Vector2(w, VIEW_H),
		Vector2(back_r, horizon), Vector2(back_l, horizon),
	]), Color(0.14, 0.28, 0.72))

	# 奥行き線(横): 手前ほど広く、奥ほど間隔が詰まる(遠近圧縮)
	for i in range(1, DEPTH_ROWS + 1):
		var t := float(i) / float(DEPTH_ROWS)
		var tt := t / (t + (1.0 - t) * 0.45)  # 奥ほど圧縮
		var ly := lerpf(fy, horizon, tt)
		var ll := lerpf(0.0, back_l, tt)
		var lr := lerpf(w, back_r, tt)
		draw_line(Vector2(ll, ly), Vector2(lr, ly), Color(0.42, 0.60, 0.92), 1.0)

	# レーン線(縦): 手前の等間隔から奥の収束点へ伸びる
	for i in range(0, LANES + 1):
		var fx := w * float(i) / float(LANES)
		var bx := lerpf(back_l, back_r, float(i) / float(LANES))
		draw_line(Vector2(fx, fy), Vector2(bx, horizon), Color(0.30, 0.46, 0.82), 1.0)

	# 手前の床エッジ(キャラが立つ最前線を強調)
	draw_line(Vector2(0.0, fy), Vector2(w, fy), Color(0.78, 0.87, 1.0), 2.0)

	# サービスライン(白線): サーバーはこの線の端側からサーブする
	var sl := ViewTransform.to_px(cfg.serve_line)
	draw_line(Vector2(sl, fy - 16.0), Vector2(sl, fy), Color(0.95, 0.95, 0.98), 1.0)
	draw_line(Vector2(w - sl, fy - 16.0), Vector2(w - sl, fy), Color(0.95, 0.95, 0.98), 1.0)

	# ネット: 支柱+網目(手前の中央に立てる)
	var nx := ViewTransform.to_px(cfg.net_x)
	var nty := ViewTransform.to_px(cfg.net_top_y)
	var half := ViewTransform.to_px(cfg.net_half_w)
	draw_rect(Rect2(nx - half, nty, half * 2.0, fy - nty), Color(0.85, 0.85, 0.92, 0.9))
	draw_line(Vector2(nx - half - 1.0, nty), Vector2(nx + half + 1.0, nty), Color(0.98, 0.98, 1.0), 2.0)
	var y := nty + 6.0
	while y < fy:
		draw_line(Vector2(nx - half, y), Vector2(nx + half, y), Color(0.60, 0.60, 0.72), 1.0)
		y += 8.0

# コート背景・床・ネットの描画。表示層(float可)。sim_configの寸法(fp)を読む。
# 原作準拠のオブリーク(平行投影)描画: 床は浅い帯、奥行き方向の線は全て同じ向きの
# 斜め(SHEAR)に流す。サーブ線もネットもコートと同じ斜めに沿う。
# キャラ/ボールのドット絵は傾けない(直立=クリスプ維持)。
extends Node2D

const ViewTransform := preload("res://src/display/view_transform.gd")

const VIEW_H := 360.0
const DEPTH_BACK := 38.0   # キャラ基準線(floor_y)から奥へ延びる床の量(px)
const DEPTH_FRONT := 14.0  # 基準線から手前(画面下側)へ延びる床の量(px)
const SHEAR := 0.5         # 奥へ1px上がるごとにxが右へずれる量(オブリークの傾き)
const LANE_W := 64.0       # 床レーン線の間隔(sim px)
const ROW_H := 13.0        # 床の横線間隔(平行投影なので等間隔)

var cfg

func setup(config) -> void:
	cfg = config
	queue_redraw()

# sim x=X の奥行き線が画面yで通る描画x(オブリークの水平シフト)
func _ox(x: float, y: float, fy: float) -> float:
	return x + SHEAR * (fy - y)

func _draw() -> void:
	if cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var fy := ViewTransform.to_px(cfg.floor_y)   # キャラが立つ基準線
	var back_y := fy - DEPTH_BACK                # 床の奥端(壁との境界)
	var front_y := fy + DEPTH_FRONT              # コート手前の白線位置

	# 奥壁(濃い青): 縦パネル線+薄い横線(原作の壁パネル風)
	draw_rect(Rect2(0.0, 0.0, w, back_y), Color(0.13, 0.13, 0.50))
	var wy := 12.0
	while wy < back_y:
		draw_line(Vector2(0.0, wy), Vector2(w, wy), Color(0.18, 0.19, 0.58), 1.0)
		wy += 24.0
	for i in 5:
		var px := 64.0 + 128.0 * float(i)
		draw_line(Vector2(px, 0.0), Vector2(px, back_y), Color(0.55, 0.55, 0.62), 2.0)

	# 床(明るい青の浅い帯): 画面下端まで
	draw_rect(Rect2(0.0, back_y, w, VIEW_H - back_y), Color(0.15, 0.31, 0.78))
	# 床の横線(水平のまま等間隔)
	var ry := back_y
	while ry <= VIEW_H:
		draw_line(Vector2(0.0, ry), Vector2(w, ry), Color(0.33, 0.50, 0.93), 1.0)
		ry += ROW_H
	# 床のレーン線(奥行き線): 全て同じ向きの斜め
	var lx := 0.0
	while lx <= w:
		draw_line(
			Vector2(_ox(lx, VIEW_H, fy), VIEW_H),
			Vector2(_ox(lx, back_y, fy), back_y),
			Color(0.33, 0.50, 0.93), 1.0)
		lx += LANE_W

	# サーブ線(白): コートに合わせて同じ斜め。床の帯の範囲に描く
	var sl := ViewTransform.to_px(cfg.serve_line)
	for x in [sl, w - sl]:
		draw_line(
			Vector2(_ox(x, front_y, fy), front_y),
			Vector2(_ox(x, back_y, fy), back_y),
			Color(0.96, 0.96, 0.99), 2.0)

	# ネット: 手前支柱と奥支柱の間の帯。コートと同じ斜めに流れる
	var nx := ViewTransform.to_px(cfg.net_x)
	var nty := ViewTransform.to_px(cfg.net_top_y)
	var net_h := fy - nty
	var fx := _ox(nx, front_y, fy)
	var bx := _ox(nx, back_y, fy)
	# 網の帯(半透明)
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx, front_y), Vector2(bx, back_y),
		Vector2(bx, back_y - net_h), Vector2(fx, front_y - net_h),
	]), Color(0.80, 0.82, 0.90, 0.5))
	# 網目(横糸)
	for i in range(1, 5):
		var t := float(i) / 5.0
		draw_line(
			Vector2(fx, front_y - net_h * t), Vector2(bx, back_y - net_h * t),
			Color(0.62, 0.64, 0.76), 1.0)
	# 上端の白帯
	draw_line(Vector2(fx, front_y - net_h), Vector2(bx, back_y - net_h), Color(0.98, 0.98, 1.0), 2.0)
	# 支柱(手前/奥)。手前支柱の頭は赤(原作準拠)
	draw_rect(Rect2(fx - 1.5, front_y - net_h, 3.0, net_h), Color(0.30, 0.45, 0.95))
	draw_rect(Rect2(bx - 1.5, back_y - net_h, 3.0, net_h), Color(0.30, 0.45, 0.95))
	draw_rect(Rect2(fx - 1.5, front_y - net_h, 3.0, 6.0), Color(0.90, 0.20, 0.15))

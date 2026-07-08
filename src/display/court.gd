# コート背景・地面・ネットの描画。表示層(float可)。sim_configの寸法(fp)を読む
extends Node2D

const ViewTransform := preload("res://src/display/view_transform.gd")
const BACK := "res://assets/third_party/sunny_land/PNG/environment/layers/back.png"

const VIEW_H := 360.0

var cfg
var _back: Texture2D

func setup(config) -> void:
	cfg = config
	_back = load(BACK)
	queue_redraw()

func _draw() -> void:
	if cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var fy := ViewTransform.to_px(cfg.floor_y)
	# 遠景(空と森)。384x240素材を画面いっぱいに拡大
	if _back != null:
		draw_texture_rect(_back, Rect2(0.0, 0.0, w, VIEW_H), false)
	# 地面帯(土)と草のライン
	draw_rect(Rect2(0.0, fy, w, VIEW_H - fy), Color(0.36, 0.28, 0.20))
	draw_line(Vector2(0.0, fy), Vector2(w, fy), Color(0.45, 0.62, 0.30), 2.0)
	# 仮ネット: 支柱+網目(横糸と縦糸)。本格的な見た目はトラックB段階で差し替え
	var nx := ViewTransform.to_px(cfg.net_x)
	var nty := ViewTransform.to_px(cfg.net_top_y)
	var half := ViewTransform.to_px(cfg.net_half_w)
	draw_rect(Rect2(nx - half, nty, half * 2.0, fy - nty), Color(0.75, 0.75, 0.82, 0.85))
	draw_line(Vector2(nx - half - 1.0, nty), Vector2(nx + half + 1.0, nty), Color(0.95, 0.95, 0.98), 2.0)
	var y := nty + 6.0
	while y < fy:
		draw_line(Vector2(nx - half, y), Vector2(nx + half, y), Color(0.55, 0.55, 0.65), 1.0)
		y += 8.0

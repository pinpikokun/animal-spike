# コート背景・床・ネットの描画。表示層(float可)。sim_configの寸法(fp)を読む。
# 原作準拠: 床に白線でバレーコートの矩形(囲い+中央線)を描く。投影は中央対称の
# 緩い収束=左コートは左斜め、右コートは右斜め、中央線とネットは垂直(傾かない)。
# ネットは手前ポール(頭が赤)+真後ろへの奥行きだけを持つ垂直の帯。
# キャラ/ボールのドット絵は傾けない(直立=クリスプ維持)。
extends Node2D

const ViewTransform := preload("res://src/display/view_transform.gd")

const VIEW_H := 360.0
const WALL_Y_OFF := 32.0   # 壁と床の境界(キャラ基準線から上へ)。原作は床が画面の約2割
const ROW_H := 11.0        # 床タイルの横線間隔(車線1本の幅)。原作は細い
const COURT_BACK := 14.0   # コート奥ライン(基準線から上へ)
const COURT_FRONT := 8.0   # コート手前ライン(基準線から下へ)。奥+手前=ちょうど2車線
const CONV := 0.0015       # 中央への収束率(奥行き1pxあたり)。原作実測に合わせた控えめな値
const LANE_W := 32.0       # 床タイルの縦線間隔(sim px)。原作は格子が細かい

var cfg

func setup(config) -> void:
	cfg = config
	queue_redraw()

# 中央対称収束: sim x の奥行き線が画面 y で通る描画x。中央(cx)は不動=垂直
func _px(x: float, y: float, fy: float, cx: float) -> float:
	return x + (cx - x) * CONV * (fy - y)

func _draw() -> void:
	if cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var fy := ViewTransform.to_px(cfg.floor_y)   # キャラが立つ基準線
	var cx := w * 0.5
	var wall_y := fy - WALL_Y_OFF
	var back_y := fy - COURT_BACK
	var front_y := fy + COURT_FRONT

	# 奥壁(濃い青): 薄い横線+縦パネル線(原作の壁パネル風)
	draw_rect(Rect2(0.0, 0.0, w, wall_y), Color(0.13, 0.13, 0.50))
	var wy := 12.0
	while wy < wall_y:
		draw_line(Vector2(0.0, wy), Vector2(w, wy), Color(0.18, 0.19, 0.58), 1.0)
		wy += 24.0
	for i in 5:
		var px := 64.0 + 128.0 * float(i)
		draw_line(Vector2(px, 0.0), Vector2(px, wall_y), Color(0.55, 0.55, 0.62), 2.0)

	# 床(明るい青の帯)
	draw_rect(Rect2(0.0, wall_y, w, VIEW_H - wall_y), Color(0.15, 0.31, 0.78))
	# 床タイルの横線(水平・等間隔)
	var grid_col := Color(0.36, 0.62, 0.96)  # 原作の明るいシアン寄りの格子
	# 横線はコート奥ラインに揃えて敷く(白線が格子に乗る=車線がコートと一致する)
	var ry := back_y - ROW_H * floorf((back_y - wall_y) / ROW_H)
	while ry <= VIEW_H:
		draw_line(Vector2(0.0, ry), Vector2(w, ry), grid_col, 1.0)
		ry += ROW_H
	# 床タイルの縦線: 中央対称の収束(左半分は左斜め、右半分は右斜め、中央は垂直)
	var lx := 0.0
	while lx <= w:
		draw_line(
			Vector2(_px(lx, VIEW_H, fy, cx), VIEW_H),
			Vector2(_px(lx, wall_y, fy, cx), wall_y),
			grid_col, 1.0)
		lx += LANE_W

	# コートの白線(原作準拠): 矩形の囲い+中央線。サイドラインはサーブ線と同一
	var sx := ViewTransform.to_px(cfg.serve_line)
	var line_col := Color(0.96, 0.96, 0.99)
	var fl := Vector2(_px(sx, front_y, fy, cx), front_y)
	var fr := Vector2(_px(w - sx, front_y, fy, cx), front_y)
	var bl := Vector2(_px(sx, back_y, fy, cx), back_y)
	var br := Vector2(_px(w - sx, back_y, fy, cx), back_y)
	draw_line(fl, fr, line_col, 2.0)  # 手前ライン
	draw_line(bl, br, line_col, 2.0)  # 奥ライン
	draw_line(fl, bl, line_col, 2.0)  # 左サイドライン(左斜め)
	draw_line(fr, br, line_col, 2.0)  # 右サイドライン(右斜め)
	draw_line(Vector2(cx, front_y), Vector2(cx, back_y), line_col, 2.0)  # 中央線(垂直)

	# ネット: 中央で傾かない。手前ポール+奥行きだけの垂直な帯(原作準拠)
	var nty := ViewTransform.to_px(cfg.net_top_y)
	var net_h := fy - nty
	var band_top := back_y - net_h          # 奥側の網上端(奥=画面上方向)
	# 天井まで伸びる細いケーブル(原作: ポールの上から画面上端まで)
	draw_line(Vector2(cx, 0.0), Vector2(cx, band_top), Color(0.55, 0.55, 0.62), 2.0)
	# 奥行きの帯(網。手前ポールの背後で上に伸びる)
	draw_rect(Rect2(cx - 2.0, band_top, 4.0, (front_y - band_top)), Color(0.72, 0.75, 0.86))
	# 手前ポール(太い青)。手前ほど下が基準なのでポールは手前ラインに立つ
	var pole_top := nty
	draw_rect(Rect2(cx - 3.0, pole_top, 6.0, front_y - pole_top), Color(0.25, 0.42, 0.95))
	# ポール上部の赤(原作は頭のすぐ下に赤いブロック)
	draw_rect(Rect2(cx - 3.0, pole_top + 3.0, 6.0, 10.0), Color(0.90, 0.18, 0.12))

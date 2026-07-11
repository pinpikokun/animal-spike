# コート背景・床・ネットの描画。表示層(float可)。sim_configの寸法(fp)を読む。
# 原作準拠: 床に白線でバレーコートの矩形(囲い+中央線)を描く。投影は中央対称の
# 緩い収束=左コートは左斜め、右コートは右斜め、中央線とネットは垂直(傾かない)。
# ネットは手前ポール(頭が赤)+真後ろへの奥行きだけを持つ垂直の帯。
# キャラ/ボールのドット絵は傾けない(直立=クリスプ維持)。
extends Node2D

const ViewTransform := preload("res://src/display/view_transform.gd")

const VIEW_H := 360.0
const TOP_EXT := 16.0      # ビュー全体を下に寄せるぶん、壁を上へ描き足す
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
	var mgn := (640.0 - w) * 0.5  # コートが画面より狭いぶんの場外マージン(左右)

	# 奥壁(濃い青): 薄い横線+縦パネル線(原作の壁パネル風)。場外まで画面全域に描く
	draw_rect(Rect2(-mgn, -TOP_EXT, w + mgn * 2.0, wall_y + TOP_EXT), Color(0.13, 0.13, 0.50))
	var wy := 12.0 - TOP_EXT
	while wy < wall_y:
		draw_line(Vector2(-mgn, wy), Vector2(w + mgn, wy), Color(0.18, 0.19, 0.58), 1.0)
		wy += 24.0
	for i in 5:
		var px := -mgn + 64.0 + 128.0 * float(i)
		draw_line(Vector2(px, -TOP_EXT), Vector2(px, wall_y), Color(0.55, 0.55, 0.62), 2.0)

	# 床(明るい青の帯)。場外まで敷き、場外は一段暗くする
	draw_rect(Rect2(-mgn, wall_y, w + mgn * 2.0, VIEW_H - wall_y), Color(0.15, 0.31, 0.78))
	var out_col := Color(0.10, 0.21, 0.55)
	draw_rect(Rect2(-mgn, wall_y, mgn, VIEW_H - wall_y), out_col)
	draw_rect(Rect2(w, wall_y, mgn, VIEW_H - wall_y), out_col)
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
	# 場外との境界: サイドボード(ボールはここで跳ね返る)
	_draw_side_board(0.0, fy, cx)
	_draw_side_board(w, fy, cx)

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

	# ネット: 中央で傾かない。奥ポール+網メッシュ+手前ポール(配置は原作準拠、質感は作り込む)
	var nty := ViewTransform.to_px(cfg.net_top_y)
	var net_h := fy - nty
	# ポールは白線の外に立つ(実際のバレーコートと同じ)。
	# 奥ポールは奥ラインの奥、手前ポールは手前ラインの手前。
	# 遠いものは小さく: 奥ポールの見かけ高さには奥行き縮尺を掛ける
	var back_base := back_y - 3.0
	var back_h := net_h * 0.85
	var back_top := back_base - back_h   # 奥ポール上端
	var front_base := front_y + 4.0
	var pole_top := front_base - net_h   # 手前ポール上端
	# 天井まで伸びる細いケーブル(原作: ネットの上から画面上端まで)
	draw_line(Vector2(cx, -TOP_EXT), Vector2(cx, back_top + 2.0), Color(0.50, 0.50, 0.58), 1.0)
	draw_line(Vector2(cx + 1.0, -TOP_EXT), Vector2(cx + 1.0, back_top + 2.0), Color(0.30, 0.30, 0.40), 1.0)
	# 奥ポール(細め・暗め・低め=遠い)。頭が網の上に覗く
	_draw_pole(cx, back_top, back_h, 5.0, 0.72)
	# 網: 上端の白テープリボン(奥ポール頭→手前ポール頭の奥行き)に網目を透かす
	var tape_col := Color(0.93, 0.94, 0.98)
	var rib_top := back_top + 2.0
	draw_rect(Rect2(cx - 2.0, rib_top, 4.0, pole_top - rib_top), tape_col)
	draw_rect(Rect2(cx + 1.0, rib_top, 1.0, pole_top - rib_top), Color(0.68, 0.70, 0.80))
	var ry2 := rib_top + 3.0
	while ry2 < pole_top - 1.0:
		draw_line(Vector2(cx - 2.0, ry2), Vector2(cx + 2.0, ry2), Color(0.72, 0.75, 0.86), 1.0)
		ry2 += 3.0
	# 網目メッシュ: 手前ポールの両脇に覗く(網はポールより奥に垂れている)
	var mesh_top := pole_top + 2.0
	var mesh_hw := 6.0
	draw_rect(Rect2(cx - mesh_hw, mesh_top, mesh_hw * 2.0, front_y - 2.0 - mesh_top), Color(0.85, 0.88, 0.96, 0.28))
	# 菱形の網目: 45度の斜線クロスハッチを帯の中にクリップして描く
	var mcol := Color(0.90, 0.92, 0.99, 0.70)
	var xl := cx - mesh_hw
	var xr := cx + mesh_hw
	var mh := front_y - 2.0 - mesh_top
	var x0 := xl - mh
	while x0 <= xr:
		# 右下がり: (x0+t, mesh_top+t)
		var t1 := maxf(0.0, xl - x0)
		var t2 := minf(mh, xr - x0)
		if t2 > t1:
			draw_line(Vector2(x0 + t1, mesh_top + t1), Vector2(x0 + t2, mesh_top + t2), mcol, 1.0)
		# 左下がり: (x0r-t, mesh_top+t)
		var x0r := xl + (x0 - xl) + mh  # 対称の始点
		var s1 := maxf(0.0, x0r - xr)
		var s2 := minf(mh, x0r - xl)
		if s2 > s1:
			draw_line(Vector2(x0r - s1, mesh_top + s1), Vector2(x0r - s2, mesh_top + s2), mcol, 1.0)
		x0 += 4.0
	# 網の下端の縁ロープ
	draw_line(Vector2(cx - mesh_hw, front_y - 2.0), Vector2(cx + mesh_hw, front_y - 2.0), Color(0.78, 0.81, 0.90), 1.0)
	# 手前ポール(太め・明るめ=近い)
	_draw_pole(cx, pole_top, net_h, 8.0, 1.0)

func _draw_side_board(x: float, fy: float, cx: float) -> void:
	# コート側端に立つボード(場外との仕切り。ボールはここで反射する)
	var h := 22.0
	var a := Vector2(_px(x, VIEW_H, fy, cx), VIEW_H)
	var b := Vector2(_px(x, fy - WALL_Y_OFF, fy, cx), fy - WALL_Y_OFF)
	var pts := PackedVector2Array([a, b, b + Vector2(0, -h), a + Vector2(0, -h)])
	draw_colored_polygon(pts, Color(0.20, 0.32, 0.72))
	draw_line(a + Vector2(0, -h), b + Vector2(0, -h), Color(0.62, 0.72, 0.95), 2.0)
	draw_line(a, b, Color(0.08, 0.14, 0.40), 2.0)

func _draw_pole(cx: float, top: float, h: float, w: float, lum: float) -> void:
	# 円柱らしい縦の陰影4段+赤い頭(ハイライト付き)+銀の継ぎ目リング+台座
	var hw := w * 0.5
	var bottom := top + h
	var c_dark := Color(0.10 * lum, 0.19 * lum, 0.48 * lum)
	var c_mid := Color(0.22 * lum, 0.40 * lum, 0.92 * lum)
	var c_lit := Color(0.48 * lum, 0.66 * lum, 1.0 * lum)
	var c_spec := Color(0.72 * lum, 0.84 * lum, 1.0 * lum)
	# シャフト: 左から 影・スペキュラ・明・中・影 の縦帯
	draw_rect(Rect2(cx - hw, top, w, h), c_mid)
	draw_rect(Rect2(cx - hw, top, 1.0, h), c_dark)
	draw_rect(Rect2(cx - hw + 1.0, top, 1.0, h), c_spec)
	draw_rect(Rect2(cx - hw + 2.0, top, 1.0, h), c_lit)
	draw_rect(Rect2(cx + hw - 2.0, top, 2.0, h), c_dark)
	# 継ぎ目リング(銀): 高さ1/3ごと
	for k in 2:
		var ryy := top + h * (0.38 + 0.30 * float(k))
		draw_rect(Rect2(cx - hw, ryy, w, 1.0), Color(0.80 * lum, 0.83 * lum, 0.90 * lum))
		draw_rect(Rect2(cx - hw, ryy + 1.0, w, 1.0), Color(0.08, 0.15, 0.38))
	# 赤い頭: 丸み(上1px窄める)+左ハイライト+右影+下の銀カラー
	var rh := maxf(7.0, h * 0.20)
	draw_rect(Rect2(cx - hw + 1.0, top, w - 2.0, 1.0), Color(1.0, 0.45, 0.38))
	draw_rect(Rect2(cx - hw, top + 1.0, w, rh - 1.0), Color(0.82, 0.14, 0.10))
	draw_rect(Rect2(cx - hw + 1.0, top + 1.0, 1.0, rh - 1.0), Color(1.0, 0.50, 0.42))
	draw_rect(Rect2(cx + hw - 2.0, top + 1.0, 2.0, rh - 1.0), Color(0.52, 0.07, 0.05))
	draw_rect(Rect2(cx - hw, top + rh, w, 2.0), Color(0.85 * lum, 0.87 * lum, 0.93 * lum))
	# 台座: ひと回り広い暗色プレート+接地の影
	draw_rect(Rect2(cx - hw - 2.0, bottom - 3.0, w + 4.0, 3.0), Color(0.13, 0.22, 0.52))
	draw_rect(Rect2(cx - hw - 2.0, bottom - 3.0, w + 4.0, 1.0), Color(0.35 * lum, 0.50 * lum, 0.90 * lum))
	draw_rect(Rect2(cx - hw - 3.0, bottom, w + 6.0, 1.0), Color(0.06, 0.10, 0.30, 0.55))

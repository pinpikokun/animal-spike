extends SceneTree

# エフェクト検証用プレビュー生成(表示層ツール。float可)。
# 実ゲームと同一の描画関数(game_view.gdの_draw_fx_shape/_draw_wall_spark/_glow_*)を
# 加算合成レイヤーに呼び、各エフェクトを寿命進行t=0..1で横に並べたシートをPNG出力する。
# これで「表示→ピーク→フェードアウト」の流れを静止画で自己検証できる(ROUNDS解析と同形式)。
# 使い方: tools\godot\Godot_v4.6-stable_win64_console.exe --headless --path . -s res://scripts/gen_fx_preview.gd -- OUT.png
# 引数を省くと res://fx_preview.png に出力する。

const GameView := preload("res://src/display/game_view.gd")

const COLS := [0.06, 0.2, 0.4, 0.6, 0.8, 0.95]  # 寿命進行tの列(左=出た瞬間/右=消え際)
const CELL_W := 150
const CELL_H := 122
const LABEL_W := 96
const SEED := 12345

# 描画対象: [ラベル, 種別]。種別"wall"は壁火花(_draw_wall_spark)、それ以外は_draw_fx_shape
const ROWS := [
	["JUST", "just"],
	["WALL", "wall"],
	["BLOCK", "block"],
	["SCORE", "score"],
	["ATTACK", "attack"],
	["RING", "ring"],
	["JUMP", "jump"],
]

class FxCanvas:
	extends Node2D
	var gv
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for r in ROWS.size():
			var row: Array = ROWS[r]
			var cy := r * CELL_H + CELL_H * 0.5
			# 行ラベル(通常合成でも加算でも白は見える)
			draw_string(font, Vector2(6, cy + 4), row[0],
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 10, 14, Color(1, 1, 1))
			for ci in COLS.size():
				var t: float = COLS[ci]
				var cx := LABEL_W + ci * CELL_W + CELL_W * 0.5
				if r == 0:
					# 上端にt値の見出し
					draw_string(font, Vector2(cx - 24, 14), "t=%.2f" % t,
						HORIZONTAL_ALIGNMENT_LEFT, CELL_W, 12, Color(0.7, 0.8, 1.0))
				if row[1] == "wall":
					# 壁火花: 左寄り中心から右へ扇状に飛ばす(center_angle=0)
					gv._draw_wall_spark(self, Vector2(cx - 40, cy), 0.0, t, SEED)
				else:
					gv._draw_fx_shape(self, row[1], Vector2(cx, cy), t, 1.0, SEED)

func _init() -> void:
	var out_path := "res://fx_preview.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	var gv = GameView.new()  # 描画関数の持ち主(ツリーに入れないので_readyは走らない)
	var w := LABEL_W + COLS.size() * CELL_W
	var h := ROWS.size() * CELL_H
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 背景: ゲームのコートに近い紺(通常合成のColorRect)。この上に加算で発光を重ねる
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.065, 0.13)
	bg.size = Vector2(w, h)
	vp.add_child(bg)
	# グリッド線(セル境界の目安、うっすら)
	var grid := FxGrid.new()
	grid.w = w
	grid.h = h
	vp.add_child(grid)
	# 加算合成レイヤー(実ゲームの_fxgと同じ設定)
	var canvas := FxCanvas.new()
	canvas.gv = gv
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	canvas.material = mat
	vp.add_child(canvas)
	root.add_child(vp)
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(out_path)
	print("fx preview saved: ", out_path, " (", w, "x", h, ")")
	quit()

class FxGrid:
	extends Node2D
	var w := 0
	var h := 0
	func _draw() -> void:
		var line := Color(1, 1, 1, 0.06)
		for r in range(1, ROWS.size()):
			draw_line(Vector2(0, r * CELL_H), Vector2(w, r * CELL_H), line, 1.0)
		for ci in range(COLS.size() + 1):
			var x := LABEL_W + ci * CELL_W
			draw_line(Vector2(x, 0), Vector2(x, h), line, 1.0)

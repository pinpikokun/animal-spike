extends SceneTree

# ゲームが実際に使うfx_particles.gdモジュールの見た目を直接検証する(表示層ツール)。
# 使い方: tools\godot\...console.exe --path . -s res://scripts/gen_fx_check.gd -- OUTDIR

const FxParticles := preload("res://src/display/fx_particles.gd")
const W := 900
const H := 360
const GROUND := 300.0
const FRAMES := 150

# [発火frame, kind, pos, dir, inertia]
const SHOTS := [
	[6,   "jump",   Vector2(130, GROUND), -1.5708, Vector2(0, 0)],
	[6,   "jump",   Vector2(300, GROUND), -1.5708, Vector2(3, 0)],   # 右移動の慣性
	[40,  "land",   Vector2(500, GROUND), -1.5708, Vector2(2, 0)],
	[40,  "dash",   Vector2(700, GROUND), 3.14159, Vector2(-3, 0)],
	[80,  "attack", Vector2(300, 150),    3.14159, Vector2(-6, 0)],
	[80,  "just",   Vector2(600, 150),    3.14159, Vector2(-6, 2)],
	[115, "wall",   Vector2(40, 180),     0.0,     Vector2(6, 1)],
	[115, "score",  Vector2(650, 200),    -1.5708, Vector2(1, 0)],
]

func _init() -> void:
	var outdir := "res://fx_check"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		outdir = a[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new(); bg.color = Color(0.055, 0.065, 0.13); bg.size = Vector2(W, H)
	vp.add_child(bg)
	var opaque := Layer.new(); opaque.mode = "opaque"
	vp.add_child(opaque)
	var glow := Layer.new(); glow.mode = "glow"
	var gm := CanvasItemMaterial.new(); gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	vp.add_child(glow)
	root.add_child(vp)
	for f in FRAMES:
		opaque.frame = f; glow.frame = f
		opaque.queue_redraw(); glow.queue_redraw()
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		img.save_png("%s/c_%03d.png" % [outdir, f])
	print("fx_check saved ", FRAMES, " frames to ", outdir)
	quit()

class Layer:
	extends Node2D
	var frame := 0
	var mode := "opaque"
	func _draw() -> void:
		for s in SHOTS:
			if mode == "opaque":
				FxParticles.draw_opaque(self, s[1], s[2], s[3], s[4], s[0], frame, GROUND)
			else:
				FxParticles.draw_glow(self, s[1], s[2], s[3], s[4], s[0], frame, GROUND)

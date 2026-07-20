extends SceneTree
# キャラ選択画面のスクリーンショットを撮る一時ツール(レビュー用)。
# 使い方: Godot本体(非ヘッドレス)で --script scripts/shot_select.gd

func _init() -> void:
	var root_win := get_root()
	root_win.size = Vector2i(1280, 720)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root_win.add_child(vp)
	var sel = load("res://src/display/char_select.gd").new()
	vp.add_child(sel)
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	img.save_png("user://select_preview.png")
	print("SAVED user://select_preview.png")
	quit()

extends SceneTree
# 原作キャラ4体の試合画面スクリーンショット(レビュー用)。
# 使い方: Godot本体(非ヘッドレス)で --script scripts/shot_match.gd

func _init() -> void:
	var root_win := get_root()
	root_win.size = Vector2i(1280, 720)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root_win.add_child(vp)
	var game = load("res://src/display/game_view.tscn").instantiate()
	game.roster = [4, 5, 6, 7]  # TOME, HITO, PIYO, UME
	vp.add_child(game)
	# ラリーが動き出すまで回す(サーブ→打ち合い)
	for shot in [240, 240, 240]:
		for i in shot:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		img.resize(1280, 720, Image.INTERPOLATE_NEAREST)
		img.save_png("user://match_preview_%d.png" % Engine.get_process_frames())
		print("SAVED match_preview_%d" % Engine.get_process_frames())
	quit()

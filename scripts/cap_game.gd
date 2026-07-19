extends SceneTree

# 実ゲーム(root.tscn)を起動して数秒回し、エフェクトが出るか・実行時エラーが無いかを
# 連番PNGで確認する検証ツール(表示層)。CPU対戦で自動進行する。
# 使い方: tools\godot\...console.exe --path . -s res://scripts/cap_game.gd -- OUTDIR

func _init() -> void:
	var outdir := "res://cap_game"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var scene: Node = load("res://src/display/root.tscn").instantiate()
	root.add_child(scene)
	# 立ち上げ待ち
	for i in 90:
		await process_frame
	# ラリー中のフレームを間引いて保存(ジャンプ/着地/ヒットの土煙を捉える)
	var saved := 0
	for i in 300:
		await process_frame
		if i % 5 == 0:
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png("%s/g_%03d.png" % [outdir, saved])
			saved += 1
	print("cap_game saved ", saved, " frames to ", outdir)
	quit()

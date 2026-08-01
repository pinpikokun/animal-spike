extends "res://tests/test_case.gd"

const SpriteFactory := preload("res://src/display/sprite_factory.gd")

func test_every_animation_has_fallback_entry() -> void:
	for anim: String in SpriteFactory.ANIMATIONS:
		check(anim in SpriteFactory.FALLBACK, anim + " のFALLBACK登録")
	check_eq(SpriteFactory.FALLBACK.size(), SpriteFactory.ANIMATIONS.size(),
		"アニメ一覧とFALLBACK辞書の件数一致")

func test_block_animation_is_registered_with_fallback() -> void:
	check("block" in SpriteFactory.ANIMATIONS, "blockをアニメ一覧へ登録")
	check("block" in SpriteFactory.FALLBACK, "blockの代役連鎖を登録")
	var fallbacks: Dictionary = SpriteFactory.FALLBACK
	if "block" in fallbacks:
		check_eq(fallbacks.get("block"), ["ground_swing", "attack", "idle"],
			"専用絵がないキャラは地上打撃、空中打撃、待機の順に代用")

func test_original_block_uses_cell_nine() -> void:
	var sf: SpriteFrames = SpriteFactory.build_original(
		SpriteFactory.ORIGINAL + "/tome_sheet.png")
	check(sf.has_animation("block"), "原作キャラは専用blockアニメを持つ")
	if not sf.has_animation("block"):
		return
	check_eq(sf.get_frame_count("block"), 1, "blockは原作セル9の1コマ")
	var frame := sf.get_frame_texture("block", 0) as AtlasTexture
	check(frame != null, "blockフレームはシート切り出し")
	if frame != null:
		check_eq(frame.region, Rect2(9 * 32, 0, 32, 32), "原作セル9を切り出す")

func test_missing_block_prefers_generated_ground_swing_fallback() -> void:
	var sf: SpriteFrames = SpriteFactory.build_for(-1)
	var block_frame: Texture2D = sf.get_frame_texture("block", 0)
	var ground_frame: Texture2D = sf.get_frame_texture("ground_swing", 0)
	check(block_frame != null and ground_frame != null, "代役フレームが生成される")
	if block_frame != null and ground_frame != null:
		check_eq(block_frame.resource_path, ground_frame.resource_path,
			"専用blockがないキャラは生成済みground_swingを最優先で使う")

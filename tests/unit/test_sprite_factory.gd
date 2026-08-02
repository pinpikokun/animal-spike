extends "res://tests/test_case.gd"

const SpriteFactory := preload("res://src/display/sprite_factory.gd")

const ORIGINAL_IDS := [4, 5, 6, 7, 8, 9, 10, 11]
const ORIGINAL_CELL_ROWS := {
	"idle": [0, 1],
	"run": [0, 1],
	"jump": [2],
	"attack": [3, 4, 5],
	"block": [9],
	"receive_stance": [6],
	"ground_swing": [9, 8, 7, 6],
	"toss": [7],
	"toss_fwd": [9, 8, 7, 6],
	"dive": [11, 10, 7, 0],
	"hurt": [12],
	"shock": [12, 13],
	"stun": [14, 15],
	"burn": [16, 17],
	"fly": [18, 19, 20, 19],
	"fly_hover": [18],
	"victory": [21, 22],
	"fall_special": [23],
}
const ORIGINAL_DURATIONS := {
	"attack": [2.0, 2.0, 2.0],
	"ground_swing": [2.0, 2.0, 2.0, 4.0],
	"toss_fwd": [2.0, 2.0, 2.0, 4.0],
	"dive": [2.0, 2.0, 2.0, 2.0],
	"shock": [3.0, 3.0],
	"stun": [3.0, 3.0],
	"burn": [3.0, 3.0],
	"fly": [3.0, 3.0, 3.0, 3.0],
	"victory": [1.0, 1.0],
}

func _cell_indices(sf: SpriteFrames, anim: String) -> Array[int]:
	var result: Array[int] = []
	for frame_index in sf.get_frame_count(anim):
		var frame := sf.get_frame_texture(anim, frame_index) as AtlasTexture
		if frame == null:
			result.append(-1)
			continue
		result.append(int(frame.region.position.y / 32.0) * 12
			+ int(frame.region.position.x / 32.0))
	return result

func _frame_durations(sf: SpriteFrames, anim: String) -> Array[float]:
	var result: Array[float] = []
	for frame_index in sf.get_frame_count(anim):
		result.append(sf.get_frame_duration(anim, frame_index))
	return result

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

func test_all_original_characters_register_the_source_cell_contract() -> void:
	for char_id: int in ORIGINAL_IDS:
		check(SpriteFactory.is_original_char(char_id), "原作ID判定: %d" % char_id)
		var sf: SpriteFrames = SpriteFactory.build_for(char_id)
		for anim: String in ORIGINAL_CELL_ROWS:
			check(sf.has_animation(anim), "ID %d は %s を登録" % [char_id, anim])
			if sf.has_animation(anim):
				check_eq(_cell_indices(sf, anim), ORIGINAL_CELL_ROWS[anim],
					"ID %d の %s セル順" % [char_id, anim])

func test_original_character_action_timing_matches_the_source_contract() -> void:
	for char_id: int in ORIGINAL_IDS:
		var sf: SpriteFrames = SpriteFactory.build_for(char_id)
		for anim: String in ORIGINAL_DURATIONS:
			check_eq(_frame_durations(sf, anim), ORIGINAL_DURATIONS[anim],
				"ID %d の %s 保持tick" % [char_id, anim])

func test_piyo_uses_its_own_bubble_cell_and_other_originals_use_cell_twenty() -> void:
	for char_id: int in ORIGINAL_IDS:
		var expected := [4] if char_id == 6 else [20]
		var sf: SpriteFrames = SpriteFactory.build_for(char_id)
		check_eq(_cell_indices(sf, "bubble"), expected,
			"ID %d の泡セル" % char_id)

func test_special_runtime_animations_exist_for_every_original_character() -> void:
	for char_id: int in ORIGINAL_IDS:
		var sf: SpriteFrames = SpriteFactory.build_for(char_id)
		for anim in ["shock", "burn", "bubble", "fly", "fly_hover"]:
			check(sf.has_animation(anim),
				"ID %d は必殺状態アニメ %s を持つ" % [char_id, anim])

func test_missing_block_prefers_generated_ground_swing_fallback() -> void:
	var sf: SpriteFrames = SpriteFactory.build_for(-1)
	var block_frame: Texture2D = sf.get_frame_texture("block", 0)
	var ground_frame: Texture2D = sf.get_frame_texture("ground_swing", 0)
	check(block_frame != null and ground_frame != null, "代役フレームが生成される")
	if block_frame != null and ground_frame != null:
		check_eq(block_frame.resource_path, ground_frame.resource_path,
			"専用blockがないキャラは生成済みground_swingを最優先で使う")

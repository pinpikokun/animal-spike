extends "res://tests/test_case.gd"

const SpriteFactory := preload("res://src/display/sprite_factory.gd")

func test_every_animation_has_fallback_entry() -> void:
	for anim: String in SpriteFactory.ANIMATIONS:
		check(anim in SpriteFactory.FALLBACK, anim + " のFALLBACK登録")
	check_eq(SpriteFactory.FALLBACK.size(), SpriteFactory.ANIMATIONS.size(),
		"アニメ一覧とFALLBACK辞書の件数一致")

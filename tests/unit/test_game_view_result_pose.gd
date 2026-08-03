extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const GameView := preload("res://src/display/game_view.gd")

func test_original_characters_use_team_result_pose_for_all_four_slots() -> void:
	for player_index in 4:
		var expected := "victory" if player_index < 2 else "defeat"
		check_eq(GameView.result_animation_for(
			player_index, Chars.CHAR_TOME, 0, true), expected,
			"スロット%dの勝敗ポーズ" % player_index)

func test_result_pose_handles_right_team_as_winner() -> void:
	for player_index in 4:
		var expected := "defeat" if player_index < 2 else "victory"
		check_eq(GameView.result_animation_for(
			player_index, Chars.CHAR_UME, 1, true), expected,
			"右勝利時のスロット%d" % player_index)

func test_non_original_loser_keeps_existing_display() -> void:
	check_eq(GameView.result_animation_for(2, Chars.CHAR_MARIO, 0, true), "",
		"非原作の敗者表示は変更しない")

func test_result_pose_is_disabled_before_result_animation_starts() -> void:
	check_eq(GameView.result_animation_for(0, Chars.CHAR_TOME, 0, false), "",
		"結果演出開始前は結果ポーズを選ばない")

func test_result_pose_is_disabled_when_winner_is_not_decided() -> void:
	check_eq(GameView.result_animation_for(0, Chars.CHAR_TOME, -1, true), "",
		"勝者未確定なら敗北ポーズを選ばない")

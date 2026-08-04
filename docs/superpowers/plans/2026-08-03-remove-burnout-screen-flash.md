# Burnout Screen Flash Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** バーンアウト突入時の赤い全画面発光だけを完全撤去する。

**Architecture:** 表示層 `game_view.gd` にある突入直後2tickの全画面矩形だけを削除する。シミュレーションとHUDの局所表示は変更せず、ソース回帰検査と全件検査で境界を守る。

**Tech Stack:** Godot 4.6、GDScript、PowerShell

## Global Constraints

- 設計正本は `docs/superpowers/specs/2026-08-03-remove-burnout-screen-flash-design.md`。
- 全画面赤レイヤーだけを削除する。
- HUD点滅、`BURNOUT` 文字、キャラ灰色表示、シミュレーション状態は維持する。
- 正規検証入口は `run_tests.ps1`。

---

### Task 1: 全画面赤フラッシュの撤去

**Files:**
- Modify: `src/display/game_view.gd:656-664`
- Test: `tests/unit/test_score_ui.gd`

**Interfaces:**
- Consumes: `GameView._draw_drive_feedback(c: CanvasItem)` と `ScoreUI.burnout_is_dim()`
- Produces: バーンアウト時に全画面赤矩形を描かず、既存の局所表示だけが残る画面描画

- [x] **Step 1: Write the failing test**

```gdscript
func test_burnout_has_no_full_screen_red_flash() -> void:
	var source := FileAccess.get_file_as_string("res://src/display/game_view.gd")
	check(not source.contains("burnout_screen_flash"),
		"バーンアウト突入時に全画面フラッシュを発火しない")
	check(not source.contains("Color(0.75, 0.08, 0.08, 0.38)"),
		"目に強い全画面赤レイヤーを描画しない")
```

- [x] **Step 2: Run test to verify it fails**

Run: `.\run_tests.ps1`
Expected: `test_burnout_has_no_full_screen_red_flash` だけが旧描画を検知して失敗する。

- [x] **Step 3: Write minimal implementation**

`_draw_drive_feedback()` 冒頭から次の全画面描画判定だけを削除する。

```gdscript
var burnout_screen_flash: bool = false
for p in state.players:
	burnout_screen_flash = burnout_screen_flash \
		or p.burnout_ticks > cfg.burnout_recovery_ticks - 2
var screen_rect := Rect2(-position, Vector2(640.0, 360.0))
if burnout_screen_flash:
	c.draw_rect(screen_rect, Color(0.75, 0.08, 0.08, 0.38))
```

- [ ] **Step 4: Run tests and verify the boundary**

Run: `.\run_tests.ps1`
Expected: 全件成功、`SCRIPT ERROR: 0`。`test_burnout_blink_reads_only_remaining_ticks_and_state_tick` も成功し、HUD点滅が維持される。

- [ ] **Step 5: Review without committing**

Run: `git diff --check`
Run: `git diff -- src/display/game_view.gd tests/unit/test_score_ui.gd docs/superpowers/specs/2026-08-03-remove-burnout-screen-flash-design.md docs/superpowers/plans/2026-08-03-remove-burnout-screen-flash.md`
Expected: 承認範囲外の変更なし。Claude Codeへ同じ差分の査読を依頼する。ユーザーからコミット指示がないためコミットしない。

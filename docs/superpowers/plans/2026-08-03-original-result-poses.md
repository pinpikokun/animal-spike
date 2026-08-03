# 原作8キャラ結果ポーズ修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原作8キャラのセル21を勝利静止画、セル22を敗北静止画として分離し、2対2の勝敗へ正しく接続する。

**Architecture:** 素材契約は `SpriteFactory` の `victory` / `defeat` に分離する。結果演出の選択を `GameView.result_animation_for()` という純粋関数へ切り出し、表示経路と単体テストが同じ判断を使う。

**Tech Stack:** Godot 4.6、GDScript、既存ヘッドレステストランナー、PowerShell

## Global Constraints

- 承認設計は `docs/superpowers/specs/2026-08-02-original-sprite-action-mapping-design.md`、160行、SHA-256 `e2d2b1b68dbddf495906ca7ae6d9f41ae077da1be5ae78318ad9070826738cb1`。
- 原作8キャラだけを対象にし、マリオなど非原作キャラの勝利アニメと敗者表示は変えない。
- 物理、入力、当たり判定、同期状態、ゲージ、乱数は変えない。
- 隔離ワークツリーは使わず、現在の `codex/original-character-specials` ブランチで作業する。

---

### Task 1: 結果ポーズ契約の赤テスト

**Files:**
- Modify: `tests/unit/test_sprite_factory.gd`
- Create: `tests/unit/test_game_view_result_pose.gd`

**Interfaces:**
- Consumes: `SpriteFactory.build_for(char_id)`, `SpriteFactory.is_original_char(char_id)`, `Simulation.team_of(player_index)`
- Produces: `GameView.result_animation_for(player_index: int, char_id: int, winner: int, result_on: bool) -> String`

- [ ] **Step 1: SpriteFactoryの期待契約を勝敗へ分離する**

```gdscript
"victory": [21],
"defeat": [22],
```

`victory` と `defeat` のフレーム数が1、`get_animation_loop()` が `false` であることを原作8人について検査する。マリオの `victory` が17フレームのままであることも検査する。

- [ ] **Step 2: 2対2の結果選択テストを書く**

```gdscript
for player_index in 4:
    var expected := "victory" if player_index < 2 else "defeat"
    check_eq(GameView.result_animation_for(player_index, Chars.CHAR_TOME, 0, true), expected)
check_eq(GameView.result_animation_for(2, Chars.CHAR_MARIO, 0, true), "")
check_eq(GameView.result_animation_for(0, Chars.CHAR_TOME, 0, false), "")
check_eq(GameView.result_animation_for(0, Chars.CHAR_TOME, -1, true), "")
```

- [ ] **Step 3: 正規入口で赤を確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: `defeat` 未登録、勝利セル列、結果選択関数の不足で失敗し、SCRIPT ERRORはテスト対象の未実装以外に増えない。

### Task 2: 最小実装

**Files:**
- Modify: `src/display/sprite_factory.gd`
- Modify: `src/display/game_view.gd`

**Interfaces:**
- Consumes: `SpriteFactory.is_original_char()`, `Simulation.team_of()`
- Produces: 原作キャラ専用の静止 `victory` / `defeat` と結果選択関数

- [ ] **Step 1: 素材契約を分離する**

```gdscript
_add_original_sheet(sf, "victory", sheet_path, [21], [1], false)
_add_original_sheet(sf, "defeat", sheet_path, [22], [1], false)
```

`ANIMATIONS` と `FALLBACK` に `defeat` を追加し、非原作は既存素材の代役で挙動を維持する。

- [ ] **Step 2: 結果選択を表示経路へ接続する**

```gdscript
static func result_animation_for(player_index: int, char_id: int,
        winner: int, result_on: bool) -> String:
    if not result_on:
        return ""
    if winner != 0 and winner != 1:
        return ""
    if Simulation.team_of(player_index) == winner:
        return "victory"
    return "defeat" if SpriteFactory.is_original_char(char_id) else ""
```

既存の状態ロック優先順位を維持し、その関数が返した文字列が空でない場合だけ `anim` を上書きする。

- [ ] **Step 3: 正規入口で緑を確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件合格、失敗0件、SCRIPT ERROR 0件。

### Task 3: 正本資料、査読、コミット

**Files:**
- Modify: `00_sprite-sample/スプライトセル対応表.txt`
- Modify: `00_sprite-sample/README.md`
- Modify: `docs/reference/original-vb22.md`
- Modify: `docs/tasks/57.md`

**Interfaces:**
- Consumes: Task 1とTask 2の実測結果
- Produces: セル21=勝利静止、セル22=敗北静止の検索可能な記録

- [ ] **Step 1: 誤記を全資料で訂正する**

旧資料の「セル21と22を勝利アニメとして交互再生する」という誤記を削除し、`21=victory=勝利静止`、`22=defeat=敗北静止` と記録する。タスク#57には訂正後の設計行数、SHA-256、テスト件数を記録する。

- [ ] **Step 2: Claude Codeへ差分レビューを依頼する**

勝敗セル、原作限定分岐、2対2、非原作不変、テストの抜けを確認させ、指摘はコードと契約へ照合する。

- [ ] **Step 3: 最終検証と差分監査を行う**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Run: `git diff --check`

Expected: 全件合格、失敗0件、SCRIPT ERROR 0件、空白エラーなし。

- [ ] **Step 4: コミットする**

```powershell
git add docs/superpowers/specs/2026-08-02-original-sprite-action-mapping-design.md docs/superpowers/plans/2026-08-03-original-result-poses.md tests/unit/test_sprite_factory.gd tests/unit/test_game_view_result_pose.gd src/display/sprite_factory.gd src/display/game_view.gd 00_sprite-sample/スプライトセル対応表.txt 00_sprite-sample/README.md docs/reference/original-vb22.md docs/tasks/57.md
git commit -m "fix: 原作キャラの勝敗ポーズを分離"
```

## Self-Review

- Spec coverage: 原作8人、勝利21、敗北22、両方静止、2対2、非原作不変を各タスクへ対応済み。
- Placeholder scan: TBD、TODO、未定の実装手順なし。
- Type consistency: `result_animation_for()` の引数と戻り値をテスト、実装、呼び出しで統一済み。

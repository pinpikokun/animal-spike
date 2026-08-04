# 全キャラ共通ジャンプランク高度 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 固有ジャンプ高度を撤廃し、全キャラの実高度をAからEの共通ランク表へ一本化する。

**Architecture:** `character_profile.gd` が共通ランク表だけを所有し、`Chars.jump_height_px(char_id)` がキャラのランクから実高度を返す。既存の `JumpArc` が新しい高さから初速と滞空時間を再計算し、プレイヤー実動とCPU予測は同じ公開APIを使い続ける。

**Tech Stack:** Godot 4.6 / GDScript / 16.16固定小数点 / PowerShell

## Global Constraints

- 実装元は `docs/superpowers/specs/2026-08-03-shared-jump-rank-heights-design.md` 70行、SHA-256 `C0D9BBE20BF8AEE36052BE49BB2BCD3AD531AC6D1EC3BF2C4EAA437049EEB18C`。
- 共通ランク表はA=200、B=170、C=140、D=120、E=110pxとする。
- UMEはE=110pxと上昇25tick、下降27tickを維持する。
- ジャンプランク割り当て、共通重力、早離し、空中制御は変更しない。
- 隔離ワークツリーを使わず、現在のブランチで作業する。

---

### Task 1: 共通ランク契約の失敗テスト

**Files:**
- Modify: `tests/unit/test_character_profile.gd`
- Modify: `tests/unit/test_char_stats.gd`
- Modify: `tests/unit/test_jump_arc.gd`

**Interfaces:**
- Consumes: `Profile.jump_height_px(rank) -> int`、`Chars.jump_height_px(char_id) -> int`
- Produces: 共通表、全キャラ適用、自然な滞空時間を固定する回帰検査

- [ ] **Step 1: ランク表の期待値を独立した固定値へ変更する**

`test_rank_tables_match_accepted_values()` と `test_jump_level_height_table()` の期待高度を
`[200, 170, 140, 120, 110]` へ変更する。

- [ ] **Step 2: 固有高度検査を全キャラ共通ランク検査へ置換する**

TOME=200、CARBY=170、UME=110、その他Cランクキャラ=140を固定値で検査する。
`Profile.jump_height_px_for_char()` は期待APIに含めず、公開境界 `Chars.jump_height_px()` を使う。

- [ ] **Step 3: 実動と自然軌道の期待値を変更する**

実測足元高度をランク値の±2pxで検査する。UMEの52tickを固定し、A、B、C、D、Eの
フルジャンプ滞空時間がこの順に単調減少することを検査する。

- [ ] **Step 4: 正規テストを実行し、REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 旧ランク表 `[155, 145, 135, 120, 100]` と固有高度が残っているため、
ランク表・全キャラ適用・実動高度の検査が期待値違いで失敗する。

### Task 2: 固有高度の撤廃と共通表への一本化

**Files:**
- Modify: `src/sim/character_profile.gd`
- Modify: `src/sim/chars.gd`

**Interfaces:**
- Consumes: `Profile.rank(char_id, Profile.ABILITY_JUMP) -> int`
- Produces: `Chars.jump_height_px(char_id) -> int`

- [ ] **Step 1: 共通ランク表を更新する**

```gdscript
const JUMP_HEIGHT_PX: Array[int] = [200, 170, 140, 120, 110]
```

- [ ] **Step 2: 全プロフィールの固有高度を削除する**

`PROFILES` 内の `jump_height_px` キーを全件削除し、
`Profile.jump_height_px_for_char()` も削除する。

- [ ] **Step 3: 公開APIをランク表へ直結する**

```gdscript
static func jump_height_px(char_id: int) -> int:
	return Profile.jump_height_px(rank(char_id, Profile.ABILITY_JUMP))
```

- [ ] **Step 4: Task 1の検査を再実行し、GREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: ランク表、実高度、自然軌道、CPU検査が合格する。意図的な物理変更による
ゴールデン値だけが残る場合は、差分位置と機能検査の合格を確認してから実測更新する。

### Task 3: 高打点返球の安全帯再調整

**Files:**
- Modify: `src/sim/hit_resolver.gd`
- Test: `tests/unit/test_return_over_net.gd`

**Interfaces:**
- Consumes: 距離 `d`、打点高さ `h`、入射横速度、既存特性係数
- Produces: 高さ200pxまでネット・壁へ当てず敵陣へ入る横速度

- [ ] **Step 1: 既存網羅検査のREDを確認する**

距離280px、高さ180px、最大入射、上向き520px/sの左右対称6件が、
旧上限483px/sで奥壁へ当たり失敗することを確認する。

- [ ] **Step 2: 実測安全帯から上限式だけを最小補正する**

```gdscript
var upper_px_s: int = 248 + d_px * 9 / 8 - (h_px - 20) * 13 / 25
```

下限、距離係数、入射係数、上向き速度は変更しない。

- [ ] **Step 3: 網羅検査のGREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 高さ200pxまでの全組み合わせが合格する。

### Task 4: 契約資料と回帰値の整合

**Files:**
- Modify: `docs/superpowers/specs/2026-08-03-original-character-jump-heights-design.md`
- Modify if required: `tests/unit/test_refactor_characterization.gd`
- Modify if required: `tests/unit/test_sync.gd`

**Interfaces:**
- Consumes: Task 2で確定した全キャラ共通高度
- Produces: 旧契約の廃止表示と説明付きゴールデン値

- [ ] **Step 1: 旧設計を廃止済みと明記する**

旧設計の冒頭に、本設計がキャラ別高度表を置き換えたことを記録する。

- [ ] **Step 2: ゴールデン差分の原因を確認する**

状態連鎖のどのチェックポイントが変わったかを確認し、高度変更以外の失敗がないことを示す。

- [ ] **Step 3: 必要なゴールデン値だけを更新する**

変更理由、機能検査件数、SCRIPT ERROR 0件をコメントへ記録する。

### Task 5: 最終検証と査読

**Files:**
- Verify: `src/sim/character_profile.gd`
- Verify: `src/sim/chars.gd`
- Verify: `src/sim/jump_arc.gd`
- Verify: `src/sim/sim_cpu.gd`
- Verify: `src/sim/hit_resolver.gd`
- Verify: `tests/unit/test_character_profile.gd`
- Verify: `tests/unit/test_char_stats.gd`
- Verify: `tests/unit/test_jump_arc.gd`

**Interfaces:**
- Consumes: 全タスクの実装と検査
- Produces: 正規検証結果とClaude Code査読結果

- [ ] **Step 1: 差分検査を実行する**

Run: `git diff --check`

Expected: 出力なし、終了コード0。

- [ ] **Step 2: 正規全件検証を実行する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件合格、SCRIPT ERROR 0件、性能上限内。

- [ ] **Step 3: Claude Codeへ実装査読を依頼する**

共通表の唯一性、固有値の残存、自然軌道、CPU予測一致、テストの独立性を確認する。

- [ ] **Step 4: プレイ画面で確認できる状態へ渡す**

ユーザーはTOME、CARBY、UME、Cランクキャラを比較し、高度と滞空時間の手触りを確認する。

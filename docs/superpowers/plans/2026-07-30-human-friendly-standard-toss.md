# Human-Friendly Standard Toss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 味方へ上げる地上標準トスだけを680px/sの試遊開始値にし、他の打球と能力差を変えない。

**Architecture:** `rules.json` と `SimConfig` に味方地上トス専用速度を追加し、`HitResolver` の既存 `returns_to_opponent` 分岐でだけ選択する。固定小数点の実軌道と打球経路を単体テストで観測し、共通ヘルパーで期待値を再計算する自己一致を避ける。

**Tech Stack:** Godot 4.6、GDScript、16.16固定小数点、PowerShellテスト入口

## Global Constraints

- 承認済み設計書は125行、SHA-256 `c5c9c006b462c443b75af6836bc3233a4675f9d47fc1f3118a62eb2661e893f7`。
- `ally_ground_toss_up_px_s` の初回試遊値は680で、最終値ではない。
- 専用値は地上トスかつ `returns_to_opponent == false` のときだけ使う。
- 地上レシーブ520、敵陣返球520、空中トス470、サーブトス620は変えない。
- 標準トスの高さに `TRAIT_TOSS_GOOD` と `TRAIT_TOSS_BAD` を適用しない。
- 低いトスの再導入は `docs/tasks/112.md` の別タスクとする。

---

### Task 1: 味方地上標準トスの専用高さ

**Files:**
- Modify: `data/rules.json:26-27`
- Modify: `src/sim/sim_config.gd:33-34,125-126`
- Modify: `src/sim/hit_resolver.gd:560-624`
- Modify: `tests/unit/test_config.gd:14-24`
- Modify: `tests/unit/test_hit.gd:591-648,784-835,923-968`
- Modify: `tests/unit/test_original_toggles.gd:121-146`
- Modify: `tests/unit/test_refactor_characterization.gd:93-125`
- Modify: `tests/unit/test_sync.gd:140-156`

**Interfaces:**
- Consumes: `HitResolver` の `returns_to_opponent`、`toss_aim_vx()`、`toss_target_x()`。
- Produces: `SimConfig.ally_ground_toss_up: int`。単位は16.16固定小数点/tick。

- [ ] **Step 1: 設定キーの赤い検査を書く**

`tests/unit/test_config.gd` の既定ルール検査に、コード側の変換を使わずJSON境界を直接確認する検査を追加する。

```gdscript
func test_standard_ground_toss_rule_uses_initial_playtest_value() -> void:
	var file := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	check_eq(raw.get("ally_ground_toss_up_px_s"), 680,
		"味方地上標準トスは初回試遊値680px/s")
```

- [ ] **Step 2: 全件テストを実行して設定キー不足で失敗することを確認する**

Run: `./run_tests.ps1`

Expected: 新規検査だけが `null != 680` でFAILし、`SCRIPT ERROR summary` は0件。

- [ ] **Step 3: 設定キーを最小追加する**

`data/rules.json` の `bump_up_speed_px_s` 直後へ追加する。

```json
"bump_up_speed_px_s": 520,
"ally_ground_toss_up_px_s": 680,
```

- [ ] **Step 4: 設定境界の検査が通ることを確認する**

Run: `./run_tests.ps1`

Expected: 既存を含む全検査がPASSし、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 5: 標準トス経路の赤い検査を書く**

`tests/unit/test_hit.gd` へ以下の観測を追加・置換する。

1. 両チームの1・2打目で、地上味方トスの打球直後 `ball_vy` がリテラル `-FP.from_int(680) / 60` になる。
2. `TRAIT_TOSS_GOOD`、能力なし、`TRAIT_TOSS_BAD` の縦初速が同じになる。`aitick=0` を使い、旧30%低下が呼ばれた場合に失敗させる。
3. 実際の `BallPhysics._step_ball()` を真上の標準トスへ反復し、上昇が36tick、上昇量が195px以上196px未満になる。期待値計算に `apex_height()` は使わない。
4. 専用値だけをテスト内で600px/sへ差し替え、味方地上トスだけが600へ追従し、3打目返球と地上レシーブは520のままになる。
5. 既存の1・2打目横照準検査は、新しい縦初速から `toss_aim_vx()` を呼ぶ期待へ変更する。
6. 実ボール物理で両チームの前後トスが既存の自陣目標へ着地することを確認する。
7. 既存の三打目地上返球、空中トス、サーブ、地上レシーブの不変検査は残す。
8. 意図的に変わる慣性検査、速度スナップショット、同期ゴールデン値は実測差分を記録して更新する。

主要な新規検査の形:

```gdscript
func test_standard_ground_toss_has_same_height_for_every_toss_trait() -> void:
	var upward_values: Array[int] = []
	for char_id in [Chars.CHAR_MARIO, Chars.CHAR_FOX, Chars.CHAR_PANDA]:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		s.players[0].char_id = char_id
		s.aitick = 0
		s.ball_x = s.players[0].x + FP.from_int(5)
		s.ball_y = cfg.floor_y - FP.from_int(10)
		HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
		upward_values.append(s.ball_vy)
	check_eq(upward_values, [
		-FP.from_int(680) / 60,
		-FP.from_int(680) / 60,
		-FP.from_int(680) / 60,
	], "標準トスの高さにトス能力差を付けない")
```

軌道検査は標準トスを真上へ発射後、`ball_vy < 0` の間だけ `BallPhysics._step_ball()` を呼び、開始Yと最小Yの差を直接比較する。これにより専用設定の選択、固定小数点変換、実ボール物理を一度に検出する。

- [ ] **Step 6: 全件テストを実行して標準トスが旧520か能力差付きのため失敗することを確認する**

Run: `./run_tests.ps1`

Expected: 新しい標準トス速度・能力差・軌道検査がFAILする。既存の三打目返球、レシーブ、空中トス、サーブはPASSする。

- [ ] **Step 7: `SimConfig` と地上トス分岐を最小実装する**

`src/sim/sim_config.gd` に専用フィールドと変換を追加する。

```gdscript
var bump_up_speed: int
var ally_ground_toss_up: int

bump_up_speed = FP.from_int(_int_of(raw, "bump_up_speed_px_s")) / tick_rate
ally_ground_toss_up = FP.from_int(_int_of(raw, "ally_ground_toss_up_px_s")) / tick_rate
```

`src/sim/hit_resolver.gd` の地上トス初速を分岐し、標準経路から低トス抽選を外す。

```gdscript
if intent_kind == INTENT_GROUND_TOSS:
	desired_vy = -cfg.bump_up_speed if returns_to_opponent \
		else -cfg.ally_ground_toss_up
	if returns_to_opponent:
		# 既存の opponent_return_vx() を維持
	else:
		desired_vx = toss_aim_vx(s.ball_x, s.ball_y, desired_vy,
			toss_target_x(team, ground_toss_hdir, cfg), cfg)
```

`toss_bad` のローカル変数と `toss_vy_for_apex_pct()` 呼出しだけを標準トス経路から削除する。能力定義、抽選ヘルパー、`toss_good` の横照準・慣性無効化は残す。

- [ ] **Step 8: 全件テストを実行して緑になることを確認する**

Run: `./run_tests.ps1`

Expected: 全検査PASS、失敗0、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 9: 自己査読とClaude Codeレビューを行う**

Run:

```powershell
git diff --check
git diff -- data/rules.json src/sim/sim_config.gd src/sim/hit_resolver.gd tests/unit/test_config.gd tests/unit/test_hit.gd tests/unit/test_original_toggles.gd tests/unit/test_refactor_characterization.gd tests/unit/test_sync.gd
rg -n "ally_ground_toss_up|toss_bad|returns_to_opponent" data src/sim tests/unit
```

確認事項:
- 専用値を読む本番経路は味方地上トスだけ。
- 旧低トスヘルパーと能力定義は残るが標準トスから呼ばれない。
- 680は試遊開始値のままで、最終確定と記述しない。
- Claude Codeには差分とテスト結果を渡し、仕様逸脱・自己一致・対象外経路の変化だけを査読させる。

- [ ] **Step 10: 検証済み実装をコミットする**

```powershell
git add data/rules.json src/sim/sim_config.gd src/sim/hit_resolver.gd tests/unit/test_config.gd tests/unit/test_hit.gd tests/unit/test_original_toggles.gd tests/unit/test_refactor_characterization.gd tests/unit/test_sync.gd docs/superpowers/plans/2026-07-30-human-friendly-standard-toss.md
git commit -m "feat: 味方の標準トスを高くする"
```

コミット後に `./run_tests.ps1` を再実行し、作業ツリーがクリーンであることを確認する。

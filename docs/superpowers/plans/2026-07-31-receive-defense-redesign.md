# Ground Toss and Receive Defense Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 相手の通常・ジャストアタック球に対し、地上トス、通常レシーブ、ジャストレシーブ、飛びつきの防御結果を承認済み契約へ分ける。

**Architecture:** 接触入力をローカルな防御接触種別へ分類し、ガード損害と被弾反応をその種別から一度だけ解決する。攻撃属性、返球物理、表示用状態は既存の正本を維持し、後続の#70で空中接触を追加できる境界にする。

**Tech Stack:** Godot 4.6、GDScript、固定小数点sim、PowerShellテスト入口 `run_tests.ps1`

## Global Constraints

- 承認済み設計書: `docs/superpowers/specs/2026-07-30-receive-defense-redesign-design.md`
- 承認時行数: 270
- 承認時SHA-256: `b0a0373dd6c1d85caba2b4f584935fb38edc5bb5be9109f1409ca0e9c858b452`
- 隔離ワークツリーは使わず、現在の `codex/issue-113-receive-damage` ブランチで実装する。
- 防御不能、ブロック、空中接触、返球軌道、能力値、CPU判断、直列化形式を変更しない。
- 新しい損害期待値は本番補助関数で再計算せず、設計書のリテラルから独立に検査する。

---

### Task 1: 通常アタックへPOWER基礎ガード損害を保持する

**Files:**
- Create: `tests/unit/test_receive_defense.gd`
- Modify: `src/sim/hit_resolver.gd:670-676`

**Interfaces:**
- Consumes: `Chars.rank(char_id, Chars.Profile.ABILITY_POWER) -> int`
- Produces: 通常・ジャストアタック成立後の `SimState.ball_guard_damage: int`

- [x] **Step 1: 通常アタックの失敗テストを書く**

```gdscript
func test_normal_attack_carries_power_guard_damage() -> void:
	for row in [[Chars.CHAR_SEC2, 35], [Chars.CHAR_PANDA, 25], [Chars.CHAR_PIYO, 15]]:
		var w := _world()
		var s = w[0]
		var cfg = w[1]
		s.players[0].char_id = row[0]
		_air_attack(s, cfg, false)
		check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL, "通常アタック属性")
		check_eq(s.ball_guard_damage, row[1], "POWER基礎ガード損害")
```

- [x] **Step 2: 正規入口を実行して期待どおり赤になることを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: `test_normal_attack_carries_power_guard_damage` が現行の0に対して15/25/35を期待してFAILする。

- [x] **Step 3: 通常アタックにも基礎値を保持する**

```gdscript
s.ball_guard_damage = cfg.power_guard_damage_for_rank(
	Chars.rank(p.char_id, Chars.Profile.ABILITY_POWER))
```

`ball_power` は従来どおりジャスト成立時だけ1とする。

- [x] **Step 4: 正規入口を再実行してTask 1を緑にする**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 新規テストを含む全件PASS、`SCRIPT ERROR summary: 0 occurrence(s)`。

### Task 2: 地上四接触の防御結果を一度だけ解決する

**Files:**
- Modify: `tests/unit/test_receive_defense.gd`
- Modify: `src/sim/hit_resolver.gd:426-559`
- Modify: `tests/unit/test_dive_receive.gd:270-310`

**Interfaces:**
- Consumes: `intent_kind`、`just_receive`、`force_dive_receive`、`incoming_attack_kind`、`incoming_guard_damage`
- Produces: ローカル防御接触種別、guard/drive/flinch/stun/vx/push/diveの一回限りの状態遷移

- [x] **Step 1: 標準Cの通常・ジャスト攻撃結果表を失敗テストにする**

```gdscript
func test_standard_c_contact_matrix() -> void:
	for row in [
		[SimState.BALL_ATTACK_NORMAL, CONTACT_TOSS, 75, 6000, true],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_RECEIVE, 90, 5000, false],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_JUST, 100, 6000, false],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_DIVE, 75, 6000, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_TOSS, 75, 6000, true],
		[SimState.BALL_ATTACK_JUST, CONTACT_RECEIVE, 90, 4000, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_JUST, 100, 6000, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_DIVE, 75, 6000, false],
	]:
		var result := _resolve_contact(row[0], row[1], 25)
		check_eq(result.guard, row[2], "標準C guard")
		check_eq(result.drive_gauge, row[3], "標準C drive")
		check_eq(result.flinch > 0, row[4], "標準C しりもち")
```

- [x] **Step 2: POWER A-Eとバーンアウトの失敗テストを書く**

通常時の地上トス/飛びつきは `[35,30,25,20,15]`、通常レシーブは `[14,12,10,8,6]`、バーンアウト時はそれぞれ `[52,45,37,30,22]` と `[21,18,15,12,9]` をリテラルで検査する。ジャストレシーブは全ランク0を検査する。

- [x] **Step 3: 飛びつきとガードブレイクの失敗テストを書く**

```gdscript
func test_dive_takes_full_guard_damage_without_butt_drop() -> void:
	var p = _resolve_contact(SimState.BALL_ATTACK_JUST, CONTACT_DIVE, 25)
	check_eq(p.guard, 75, "飛びつきは全量")
	check_eq(p.drive_gauge, 6000, "飛びつきはdrive 0")
	check_eq(p.flinch, 0, "飛びつき後にしりもちしない")
	check(p.dive != 0, "dive表示は着地まで残す")
	check_eq(p.vx, 0, "接触成功で専用水平速度は終了")

func test_guard_break_stuns_without_any_blowback() -> void:
	var p = _resolve_guard_break(CONTACT_TOSS)
	check(p.stun > 0, "ブレイクは気絶")
	check_eq(p.guard, p.guard_max, "guard満タン復帰")
	check_eq(p.vx, 0, "後方初速なし")
	check_eq(p.push, 0, "壁方向押し出しなし")
```

- [x] **Step 4: 正規入口を実行して新契約だけが赤になることを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 新しいguard値、飛びつきdrive 0、飛びつきflinch 0、ブレイクvx/push 0が現行挙動に対してFAILする。

- [x] **Step 5: 防御接触種別と損害解決を最小実装する**

`hit_resolver.gd` にローカル分類定数と純粋分類関数を置く。

```gdscript
static func _defense_contact_kind(intent_kind: int, just_receive: bool,
		force_dive_receive: bool) -> int:
	if force_dive_receive:
		return DEFENSE_CONTACT_DIVE
	if intent_kind == INTENT_GROUND_TOSS:
		return DEFENSE_CONTACT_GROUND_TOSS
	if intent_kind == INTENT_GROUND_RECEIVE:
		return DEFENSE_CONTACT_JUST_RECEIVE if just_receive \
			else DEFENSE_CONTACT_GROUND_RECEIVE
	return DEFENSE_CONTACT_NONE
```

`opposing_drive_attack && !incoming_unblockable` の地上四接触だけを新分岐で処理し、処理済みなら旧パワー球損害を重ねない。通常レシーブだけ基礎値の `2 / 5`、ジャストだけ0、地上トスと飛びつきは全量とする。飛びつきはdrive消費条件から除外し、残存時の被弾反応を付けない。ブレイク時は `stun` とguard復帰後に `flinch=0`、`vx=0`、`push=0` とする。

- [x] **Step 6: Task 2の全件を緑にする**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件PASS、`SCRIPT ERROR summary: 0 occurrence(s)`。

### Task 3: 対象外経路と返球制御を固定する

**Files:**
- Modify: `tests/unit/test_receive_defense.gd`
- Modify: `tests/unit/test_hit.gd`

**Interfaces:**
- Consumes: 既存のパワー球、防御不能、ブロック、空中接触、壁減衰経路
- Produces: #113の新分岐へ入らないことを示す回帰証拠

- [x] **Step 1: 対象外経路の回帰テストを書く**

次を実状態で検査する。

- `BALL_ATTACK_NONE` のアタック返しパワー球は通常レシーブでも旧全量損害としりもちを維持する。
- `BALL_ATTACK_NORMAL` の空中トス、空中アタック返し、ブロックはguardを削らない。
- 防御不能球は新40%分岐へ入らず、固定損害と専用被弾を一度だけ受ける。
- 壁で攻撃属性を失った球はguardもdriveも削らない。
- ジャストアタック球の地上トスと通常レシーブは既存の `mangled` 制御を維持する。

- [x] **Step 2: 回帰テストを実行する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件PASS。FAILした場合は新分岐の条件を狭め、対象外経路の挙動は変更しない。

- [x] **Step 3: 設計書の固定値を再照合する**

Run:

```powershell
$spec='docs\superpowers\specs\2026-07-30-receive-defense-redesign-design.md'
(Get-Content -Encoding UTF8 $spec).Count
(Get-FileHash -Algorithm SHA256 $spec).Hash.ToLowerInvariant()
```

Expected: 270行、`b0a0373dd6c1d85caba2b4f584935fb38edc5bb5be9109f1409ca0e9c858b452`。

### Task 4: 完了記録、全件検証、レビュー

**Files:**
- Modify: `docs/tasks/113.md`
- Modify: `docs/superpowers/plans/2026-07-31-receive-defense-redesign.md`

**Interfaces:**
- Consumes: 全テスト結果、設計書照合、git diff、Claude Codeレビュー
- Produces: 検証可能な#113完了記録と次の#70への引き継ぎ

- [x] **Step 1: 正規入口を新規実行する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 0 failed、`SCRIPT ERROR summary: 0 occurrence(s)`、同期ゴールデンと性能門を含む全件完走。

- [x] **Step 2: 差分検査を実行する**

Run: `git diff --check; git status --short; git diff --stat; git diff`

Expected: 空白エラーなし、依頼範囲だけの差分。

- [x] **Step 3: Claude Codeへ仕様・実装・テストの最終レビューを依頼する**

設計書、実装差分、全件テスト結果を提示し、対象外経路の混入、二重損害、mangled消失、飛びつき状態遷移、ガードブレイク反応を確認させる。指摘は証拠と照合して修正する。

- [x] **Step 4: #113へ実装結果と検証証拠を記録する**

行数、SHA-256、変更全件、実差分、全件テスト件数、未検証事項、次タスクが#70であることを書く。

- [x] **Step 5: コミットする**

```powershell
git add docs/superpowers/specs/2026-07-30-receive-defense-redesign-design.md `
  docs/superpowers/plans/2026-07-31-receive-defense-redesign.md `
  docs/tasks/70.md docs/tasks/113.md src/sim/hit_resolver.gd `
  tests/unit/test_receive_defense.gd tests/unit/test_dive_receive.gd tests/unit/test_hit.gd
git commit -m "feat: 地上トスとレシーブの防御結果を分ける"
```

# 戦闘リソース統合再設計 v2.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 体力、ドライブ、攻撃、防御、ブロック、バーンアウト、スタンを、0から100の数値制と決定論ロールバックに対応した一つの戦闘経済へ統合する。

**Architecture:** `SimState` を全同期状態の正本とし、新しい `combat_resources.gd` がドライブ予約・消費・回復・バーンアウト・体力スタンの純粋な状態遷移を担当する。`simulation.gd` はtick順序と構え、`hit_resolver.gd` は接触分類と攻撃結果、`ball_physics.gd` はコート移動境界、表示層とCPUは確定状態の利用だけを担当する。

**Tech Stack:** Godot 4.6、GDScript、整数固定tick、決定論ロールバック、PowerShell正規テスト入口

## Global Constraints

- 正式仕様は `docs/superpowers/specs/2026-08-02-combat-resource-system-v2-1-design.md` 574行、SHA-256 `1c0d5a501c9c73b8943a39b4792d7227d7c9c0f5a4d7bdf59d9fc622dba39d6d`。
- 各タスク開始前に上記行数とSHA-256を照合し、不一致なら停止する。
- ドライブは整数0から100。旧1ストック1000、最大6000を判定へ残さない。
- 1秒は60tick。シミュレーションへ浮動小数を追加しない。
- 新IDは `SimState` 内の単調カウンタから採番し、全新規状態を直列化・ハッシュ化する。
- 新しい操作ボタン、アニメーション、必殺技、キャラクター差、CPU難易度補正を追加しない。
- 各タスクは契約テストを先に赤くし、最小実装後に `run_tests.ps1` を終了コード0まで通す。
- 固定配列とゴールデンの変化は実測して原因を一つに絞る。想定外の変化では停止する。
- 実装コミット前にClaude Codeへ仕様適合と回帰リスクのレビューを依頼する。
- 隔離worktreeは使わず、`codex/combat-resource-system` ブランチで作業する。

## File Map

- Create `src/sim/combat_resources.gd`: ドライブ、予約、回復窓、バーンアウト、体力スタンの状態遷移。
- Modify `src/sim/sim_state.gd`: ID、保持、攻撃、構え、回復、スタンの同期状態。
- Modify `src/sim/sim_config.gd`: 0から100契約の設定読込と検証。
- Modify `data/rules.json`: 正式仕様の設定キーと値。
- Modify `src/sim/simulation.gd`: tick順序、保持、構え、タイマー、ラリーリセット。
- Modify `src/sim/hit_resolver.gd`: 攻撃ID、コスト、体力倍率、ブロック、接触結果。
- Modify `src/sim/ball_physics.gd`: 相手コート移行と有効通常アタック結果の通知。
- Modify `src/sim/player_movement.gd`: 構え移動固定、解除硬直、スタン連打短縮撤去。
- Modify `src/sim/sim_cpu.gd`: 数値しきい値と人間同等コスト。
- Modify `src/display/score_ui.gd`: 0から100の連続塗りと6区画目盛り。
- Modify `src/display/game_view.gd`: 構え、バーンアウト、スタンの確定状態表示。
- Update existing tests and create six focused contract suites under `tests/unit/`。

---

### Task 1: 決定論IDと同期状態の基盤

**Files:**
- Modify: `src/sim/sim_state.gd:31-302`
- Create: `tests/unit/test_combat_resource_state.gd`
- Modify: `tests/unit/test_state.gd:38-112`
- Modify: `tests/unit/test_state_coverage.gd:1-60`
- Modify: `tests/unit/test_sync.gd`

**Interfaces:**
- Produces: `SimState.alloc_possession_id() -> int`, `alloc_attack_id() -> int`, `alloc_contact_id() -> int`, `alloc_action_id() -> int`
- Produces: 全プレイヤー資源状態と保持・攻撃状態を含む既存 `to_int_array() -> Array[int]`
- Consumes: 既存 `state_hash()`、`load_int_array(arr)`、4人固定プレイヤー配列

- [ ] **Step 1: 承認済み設計書を照合する**

Run:

```powershell
$p = 'docs/superpowers/specs/2026-08-02-combat-resource-system-v2-1-design.md'
(Get-Content -LiteralPath $p -Encoding UTF8).Count
(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
```

Expected: `574` と `1c0d5a501c9c73b8943a39b4792d7227d7c9c0f5a4d7bdf59d9fc622dba39d6d`。

- [ ] **Step 2: IDと全新規状態の赤い往復テストを書く**

`tests/unit/test_combat_resource_state.gd` に、4つのIDが1から単調増加し、ロード後も次番号が一致するテストを書く。プレイヤー1へ予約、回復窓、構え、スタンを非既定値で設定し、保持と攻撃状態も含めて往復一致させる。

```gdscript
func test_combat_ids_and_resource_state_roundtrip() -> void:
    var a := SimState.new()
    check_eq(a.alloc_possession_id(), 1, "最初の保持ID")
    check_eq(a.alloc_attack_id(), 1, "最初の攻撃ID")
    a.players[1].drive_reserved = 5
    a.players[1].stance_action_id = a.alloc_action_id()
    a.players[1].stunned_this_rally = 1
    a.possession_id = a.alloc_possession_id()
    a.ball_attack_id = a.alloc_attack_id()
    var b := SimState.new()
    b.load_int_array(a.to_int_array())
    check_eq(b.to_int_array(), a.to_int_array(), "戦闘資源状態を完全復元")
    check_eq(b.alloc_attack_id(), a.alloc_attack_id(), "復元後もID列が一致")
```

- [ ] **Step 3: 正規入口で意図した赤を確認する**

Run: `.\run_tests.ps1`

Expected: 新フィールドまたはID関数未定義だけで失敗し、`SCRIPT ERROR` に依存して偽PASSしない。

- [ ] **Step 4: `SimState` へ整数状態と採番関数を実装する**

プレイヤーへ仕様書12章のうち既存状態と同義でない新規フィールドを追加する。`health`、`max_health`、`stun_ticks` は、現行の `guard`、`guard_max`、`stun` と同義なのでTask 1では二重化せず、Task 8の純粋改名で導入する。状態本体へ保持情報、攻撃情報、4つの次IDを追加する。IDは0を未設定値として予約し、最初の採番を1にする。

```gdscript
func alloc_attack_id() -> int:
    var value := next_attack_id
    next_attack_id += 1
    return value
```

全フィールドを宣言順と同じ順序で `to_int_array()` と `load_int_array()` へ追加する。

- [ ] **Step 5: 状態列変化を独立監査する**

`test_state.gd` の直列化長と、`test_state_coverage.gd` の全intフィールド検査を更新する。旧入力列のボール位置、速度、得点、乱数値が同じで、新規フィールドだけ初期値であることを検査する。同期ゴールデンが変わった場合、この構造追加だけを理由として新旧値を記録する。

- [ ] **Step 6: 全件検証とClaudeレビューを行う**

Run: `.\run_tests.ps1`

Expected: 全件合格、`SCRIPT ERROR summary: 0 occurrence(s)`。Claudeへ `sim_state.gd` と状態テスト差分を渡し、未直列化フィールドと非決定論IDがないことを確認する。

- [ ] **Step 7: Task 1をコミットする**

```powershell
git add src/sim/sim_state.gd tests/unit/test_combat_resource_state.gd tests/unit/test_state.gd tests/unit/test_state_coverage.gd tests/unit/test_sync.gd
git commit -m "refactor: 戦闘リソースの同期状態を追加"
```

---

### Task 2: 0から100のドライブ設定と共通消費API

**Files:**
- Create: `src/sim/combat_resources.gd`
- Modify: `src/sim/chars.gd`
- Modify: `src/sim/sim_config.gd:55-245`
- Modify: `data/rules.json:45-76`
- Modify: `src/sim/hit_resolver.gd:298-416,706-740`
- Modify: `src/sim/player_movement.gd:220-245`
- Modify: `src/sim/simulation.gd:359-390`
- Modify: `src/sim/sim_cpu.gd:590-1125`
- Modify: `src/display/score_ui.gd:160-186`
- Modify: `tests/unit/test_config.gd`
- Modify: `tests/unit/test_chars.gd`
- Create: `tests/unit/test_combat_drive_values.gd`
- Update: `tests/unit/test_drive_gauge.gd`, `test_hat.gd`, `test_hip_cling.gd`, `test_hit.gd`

**Interfaces:**
- Produces: `CombatResources.available_drive(p) -> int`
- Produces: `CombatResources.special_drive_cost(cfg) -> int`
- Produces: `CombatResources.can_pay(p, amount: int) -> bool`
- Produces: `CombatResources.spend_committed(p, amount: int, cfg) -> Dictionary`
- Produces: `CombatResources.spend_mandatory(p, amount: int, cfg) -> int`
- Produces: result `{authorized: bool, spent: int, depleted: bool}`
- Produces: `CombatResources.start_burnout(p, cfg) -> void` の0到達発火。Task 4までは解除時100の旧復帰だけを暫定維持する。
- Consumes: Task 1の `drive_reserved` と既存 `burnout_ticks`

- [ ] **Step 1: 最終設定値の赤い検査を書く**

```gdscript
func test_numeric_drive_contract() -> void:
    var cfg := SimConfig.load_default()
    check_eq(cfg.drive_gauge_max, 100, "最大値")
    check_eq(cfg.just_attack_drive_cost, 25, "ジャスト")
    check_eq(cfg.special_drive_cost_default, 35, "必殺")
    check_eq(cfg.receive_stance_reserve_cost, 5, "構え")
    check_eq(cfg.dive_receive_drive_cost, 15, "飛びつき")
    check_eq(cfg.block_start_drive_cost, 5, "ブロック開始")
    check_eq(cfg.block_contact_drive_cost, 5, "ブロック接触")
```

旧 `drive_gauge_stock` を設定へ再追加すると赤くなる検査も加える。

- [ ] **Step 2: 全額前払い境界の赤い検査を書く**

`test_combat_drive_values.gd` で24のジャストは通常へフォールバック、25は成立して0、34の必殺は不成立、35は成立して0、構え予約中は `drive-reserved` だけ利用可能になることを固定する。

- [ ] **Step 3: 正規入口で赤を確認する**

Run: `.\run_tests.ps1`

Expected: 旧設定値と部分消費挙動だけが契約違反として失敗する。

- [ ] **Step 4: 設定キーと共通APIを実装する**

`rules.json` のドライブキーを設計書3章へ置換し、`SimConfig` で全値を正整数として検証する。`drive_gauge_stock` と旧受動回復設定は読まない。体力とスタンの旧キーはTask 8で参照元と同時に削除するまで維持する。

```gdscript
static func available_drive(p) -> int:
    if p.burnout_ticks > 0:
        return 0
    return maxi(p.drive_gauge - p.drive_reserved, 0)

static func spend_committed(p, amount: int, cfg) -> Dictionary:
    if amount < 0 or available_drive(p) < amount:
        return {"authorized": false, "spent": 0, "depleted": false}
    p.drive_gauge -= amount
    var depleted := p.drive_gauge == 0
    if depleted:
        start_burnout(p, cfg)
    return {"authorized": true, "spent": amount, "depleted": depleted}

static func spend_mandatory(p, amount: int, cfg) -> int:
    var spent := mini(maxi(amount, 0), available_drive(p))
    p.drive_gauge -= spent
    if spent > 0 and p.drive_gauge == 0:
        start_burnout(p, cfg)
    return spent
```

- [ ] **Step 5: 全攻撃系消費を数値へ接続する**

ジャストアタックは25全額がなければ通常へ戻す。帽子、ヒップ、炎など現行全必殺技を35へ揃え、不足時は開始しない。技カタログから旧 `gauge_cost` を削除し、行動可否、実消費、CPU判断は `CombatResources.special_drive_cost(cfg)` だけを通す。旧1、2、3ストックと残量全消費成立をテストごと撤去する。
旧受動回復ロジックはこのTaskで停止し、Task 3の攻撃後回復が入るまで自動回復0とする。CPUと6分割表示も `drive_gauge_stock` を読まず、0から100の値を直接扱う。
旧stock参照を使っていたブロックの被弾側ドライブ削りは0へ置換し、Task 7の開始5・接触5へ移すまで無料ブロックとして固定する。飛びつきは現行どおり無料のままTask 7へ送る。全消費経路は実体値0で `start_burnout()` を呼び、予約による利用可能値0では呼ばない。
Task 2単体は攻撃後回復がまだ無い一時状態であり、Task 3と対で最終経済を構成することをコミット説明とタスク記録へ明記する。

- [ ] **Step 6: 全件検証とClaudeレビューを行う**

Run: `.\run_tests.ps1`

Expected: 全件合格。Claudeへ設定、共通消費API、全必殺技呼出差分を渡し、旧ストック参照と部分成立経路が0件であることを確認する。この段の数値変更で同期ゴールデンが変わる場合、新旧値と0から100移行だけを原因として記録する。

- [ ] **Step 7: Task 2をコミットする**

```powershell
git add data/rules.json src/sim/sim_config.gd src/sim/combat_resources.gd src/sim/hit_resolver.gd src/sim/player_movement.gd src/sim/simulation.gd src/sim/sim_cpu.gd src/display/score_ui.gd tests/unit
git commit -m "feat: ドライブを0から100の数値制へ移行"
```

---

### Task 3: 通常アタック15と攻撃後回復窓

**Files:**
- Modify: `src/sim/combat_resources.gd`
- Modify: `src/sim/hit_resolver.gd:473-775`
- Modify: `src/sim/ball_physics.gd:1-190`
- Modify: `src/sim/simulation.gd:120-241`
- Create: `tests/unit/test_attack_drive_recovery.gd`
- Modify: `tests/unit/test_hit_boundary.gd`
- Modify: `tests/unit/test_return_over_net.gd`

**Interfaces:**
- Produces: `CombatResources.start_attack_recovery(p, delay_ticks: int, cfg) -> void`
- Produces: `CombatResources.stop_attack_recovery(p) -> void`
- Produces: `CombatResources.tick_attack_recovery(p, active: bool, cfg) -> void`
- Produces: `HitResolver._grant_valid_normal_attack(s, attack_id: int, owner: int, cfg) -> void`
- Consumes: Task 1の攻撃ID状態、Task 2の0から100値と0到達バーンアウト

- [ ] **Step 1: 有効通常アタック境界の赤い検査を書く**

相手プレイ可能領域へ向かう通常アタック、相手ブロック接触、相手選手接触は15を一度だけ回復する。空振り、自陣ネット、直接アウト、ジャスト、必殺、ブロック返球、バーンアウト通常アタックは0とする。

- [ ] **Step 2: 回復tick順の赤い検査を書く**

29tickで0、30tickで1、179tickで5、180tickで6。防御開始、接触、ラリー終了、バーンアウトで窓と端数を0にする。ジャストは60tick遅延、必殺は効果発生後90tick遅延を検査する。

- [ ] **Step 3: 赤を確認する**

Run: `.\run_tests.ps1`

Expected: 通常15と回復窓未実装だけで失敗する。

- [ ] **Step 4: 攻撃IDと有効結果を実装する**

通常アタック生成時に `ball_attack_id` と所有者を記録する。打球設定後に床予測が相手プレイ可能領域なら即時に15を一度付与する。予測では未確定でも相手選手またはブロックへ接触した時点で未付与なら付与する。ネットまたはアウト確定時に未付与のまま攻撃を終了する。

- [ ] **Step 5: 回復窓を整数tickで実装する**

仕様書5.3の順に端数加算、30到達付与、窓減算、終了判定を行う。6点目を180tick目に付与する。防御開始関数から必ず `stop_attack_recovery()` を呼ぶ。

- [ ] **Step 6: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Claudeへ有効アタック境界、攻撃ID一度性、180tick目の順序をレビュー依頼する。

```powershell
git add src/sim/combat_resources.gd src/sim/hit_resolver.gd src/sim/ball_physics.gd src/sim/simulation.gd tests/unit
git commit -m "feat: 攻撃によるドライブ再建を追加"
```

---

### Task 4: バーンアウト600tickと30復帰

**Files:**
- Modify: `src/sim/combat_resources.gd`
- Modify: `src/sim/simulation.gd:208-241,480-550`
- Modify: `src/sim/hit_resolver.gd:406-416,429-456,566-622,832-860`
- Rewrite: `tests/unit/test_drive_burnout.gd:117-205`
- Modify: `tests/unit/test_receive_defense.gd:113-127`
- Modify: `tests/unit/test_super_catalog.gd:74-84`

**Interfaces:**
- Finalizes: Task 2の `CombatResources.start_burnout(p, cfg) -> void`
- Produces: `CombatResources.tick_burnout(p, active: bool, cfg) -> void`
- Consumes: Task 2の `spend_committed().depleted` とTask 3の回復窓停止API

- [ ] **Step 1: 新バーンアウト契約の赤い検査を書く**

600ラリーtickで30復帰、得点演出とサーブ待機で停止、ポイントをまたいで残量維持、通常攻撃と炎球の体力損害へ1.5倍が掛からないことを固定する。

```gdscript
func test_burnout_exits_at_thirty_without_damage_multiplier() -> void:
    p.drive_gauge = 0
    CombatResources.start_burnout(p, cfg)
    for i in 600:
        CombatResources.tick_burnout(p, true, cfg)
    check_eq(p.burnout_ticks, 0, "600tickで解除")
    check_eq(p.drive_gauge, 30, "30で復帰")
```

- [ ] **Step 2: 赤を確認する**

Run: `.\run_tests.ps1`

Expected: 旧全回復と1.5倍を期待するテストが新契約で赤になる。

- [ ] **Step 3: バーンアウト遷移を最終化する**

実体 `drive_gauge==0` だけで開始し、予約による利用可能値0では開始しない。終了時30、古い回復窓は0。現在行動保護は呼出側のaction modeで保持する。

- [ ] **Step 4: 1.5倍経路を除去する**

`_burnout_guard_damage()` と全呼出を削除し、通常体力ダメージをそのまま使う。炎、通常、ジャスト、地上トス、通常レシーブで倍率が残らないことを検査する。

- [ ] **Step 5: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Expected: 全件合格、固定バーンアウト時間600は維持、復帰値だけ30。Claudeへ現在行動保護とtick停止条件をレビュー依頼する。この挙動変更で同期ゴールデンが変わる場合、新旧値と原因を記録する。

```powershell
git add src/sim/combat_resources.gd src/sim/simulation.gd src/sim/hit_resolver.gd tests/unit
git commit -m "feat: バーンアウトを30復帰へ再設計"
```

---

### Task 5: 自陣保持と防御返球ペナルティ10

**Files:**
- Create: `src/sim/possession_tracker.gd`
- Modify: `src/sim/simulation.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/ball_physics.gd`
- Create: `tests/unit/test_passive_return_penalty.gd`
- Modify: `tests/unit/test_rally.gd`

**Interfaces:**
- Produces: `PossessionTracker.on_team_contact(s, actor: int, action_kind: int) -> void`
- Produces: `PossessionTracker.mark_aggressive(s) -> void`
- Produces: `PossessionTracker.mark_dive_exempt(s) -> void`
- Produces: `PossessionTracker.resolve_opponent_transfer(s, owner: int, cfg) -> void`
- Produces: `PossessionTracker.reset_for_rally(s) -> void`
- Consumes: Task 1の保持IDとTask 2の強制消費API

- [ ] **Step 1: 保持単位の赤い検査を書く**

2人が同じ保持で触って直接返しても最後の接触者だけ10を一度払う。通常、ジャスト、必殺、直接ブロック返球、全飛びつき版では払わない。残量7は0になりバーンアウトする。バーンアウト中の返球はタイマーをリセットしない。

- [ ] **Step 2: コート移行境界の赤い検査を書く**

相手接触がなくてもボール中心がネット境界を越えたtickでペナルティを確定する。ネットへ戻っただけ、自陣内トス、壁接触では確定しない。得点終了と同tickでも一度だけ払う。

- [ ] **Step 3: 赤を確認する**

Run: `.\run_tests.ps1`

- [ ] **Step 4: 保持追跡を実装する**

相手またはサーブ由来球への最初のチーム接触でIDを採番する。接触ごとに最後のactorを更新し、攻撃分類成立で `aggressive_action_resolved=1`、飛びつきで免除を立てる。ボールがネット境界を相手方向へ越えたとき、未解決保持を一度解決する。
得点とラリーリセットでは `reset_for_rally()` が保持ID、team、最後の接触者、攻撃成立、適用済みを初期値へ戻す。次IDカウンタは試合中に巻き戻さず、snapshot復元時だけ保存値へ戻す。ラリーをまたいでも次IDが再利用されない赤い検査を先に追加する。

- [ ] **Step 5: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Claudeへ得点同tick、壁、ブロック、複数接触、ロールバック一度性をレビュー依頼する。

```powershell
git add src/sim/possession_tracker.gd src/sim/simulation.gd src/sim/hit_resolver.gd src/sim/ball_physics.gd tests/unit
git commit -m "feat: 防御返球ペナルティを追加"
```

---

### Task 6: 構え予約、先読み、反応、10tickジャスト

**Files:**
- Modify: `src/sim/combat_resources.gd`
- Modify: `src/sim/simulation.gd:243-357`
- Modify: `src/sim/player_movement.gd:1-150`
- Modify: `src/sim/hit_resolver.gd:473-545,761-780`
- Modify: `src/display/anim_select.gd:30-45`
- Create: `tests/unit/test_receive_stance_resource.gd`
- Rewrite: `tests/unit/test_drive_burnout.gd:1-117`
- Modify: `tests/unit/test_cpu_offense_receive.gd`

**Interfaces:**
- Produces: `CombatResources.reserve_stance(p, action_id: int, tick: int, cfg) -> bool`
- Produces: `CombatResources.release_stance_reservation(p) -> void`
- Produces: `CombatResources.commit_stance_reservation(p, cfg) -> void`
- Produces: `Simulation._resolve_stance_contact(state, actor: int, attack_id: int, cfg) -> int`
- Consumes: Task 1の構え状態、Task 3の攻撃IDとcommit tick

- [ ] **Step 1: 構え開始と維持の赤い検査を書く**

5以上で下+ACTIONの押下エッジから5予約、1秒保持しても実体値不変、左右とジャンプで位置不変、10tick後も通常構え継続、離すと5確定と9tick硬直、再入力には一度解放が必要、と固定する。

- [ ] **Step 2: 先読みと反応の赤い検査を書く**

攻撃commit前または同tickに開始して同じ球を介在接触なしで拾えば予約解放。commit後なら5確定。別方向、壁、味方、ブロック、解除、ラリー終了は5確定。開始5の先読みは5維持、反応は0後にバーンアウトする。

- [ ] **Step 3: ジャスト窓の赤い検査を書く**

構え開始1から10tickの接触だけジャスト、11tick以降は体力倍率0.30の通常構え。先読みかつ10tick以内ならジャストが成立する。バーンアウトと残量1から4は構えなしへフォールバックする。

- [ ] **Step 4: 赤を確認する**

Run: `.\run_tests.ps1`

- [ ] **Step 5: 構え状態機械を実装する**

`receive_stance` はジャスト受付の残りtickだけを保持し、長押し構え本体は `stance_active` へ分離する。`simulation.gd` で移動処理より先に構え入力を確定し、`player_movement.gd` は確定状態だけを見て移動とジャンプを封じる。

別行動入力は予約5を確定し、そのtickでは新行動を開始しない。解除硬直中も下なしACTIONによる構えなしレシーブだけ許可する。

- [ ] **Step 6: attackCommitと接触解決を接続する**

攻撃commit時に有効構えへ攻撃IDを記録する。接触時に同一ID、開始tick、介在接触を照合し、解放か消費を一度だけ行う。サーブ打撃前構えは新設しない。

- [ ] **Step 7: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Claudeへ同tick処理順、解除同tick入力、予約一度性、ロールバック復元を重点レビュー依頼する。
構え状態が固定入力列へ現れることで同期ゴールデンが変わる場合、新旧値と構え契約だけを原因として記録する。

```powershell
git add src/sim/combat_resources.gd src/sim/simulation.gd src/sim/player_movement.gd src/sim/hit_resolver.gd src/display/anim_select.gd tests/unit
git commit -m "feat: 先読みと反応のレシーブ構えを追加"
```

---

### Task 7: 飛びつき15、ブロック5+5、ソフトブロック

**Files:**
- Modify: `src/sim/simulation.gd:288-337`
- Modify: `src/sim/player_movement.gd:127-150`
- Modify: `src/sim/hit_resolver.gd:320-397,473-622,790-860`
- Rewrite: `tests/unit/test_dive_receive.gd`
- Create: `tests/unit/test_block_drive_resource.gd`
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_receive_defense.gd`

**Interfaces:**
- Consumes: Task 2の消費API、Task 4の現在行動保護、Task 5の保持免除
- Produces: `current_block_mode` 値 `BLOCK_NONE`, `BLOCK_NORMAL`, `BLOCK_BURNOUT`
- Produces: `ball_original_attack_pressure_consumed` と `ball_soft_block_action_id`
- Transitional naming: このTaskでは現行 `guard` と `ball_guard_damage` を体力値として使い、Task 8で挙動を変えず `health` と `ball_health_damage` へ機械的に改名する。

- [ ] **Step 1: 飛びつき境界の赤い検査を書く**

16から15消費、15ちょうどは通常版後バーンアウト、1から14は全消費弱体版、0またはバーンアウトは弱体版、全版が防御返球10免除、空振り返却なしを固定する。弱体版は距離80%、硬直130%、体力倍率1.00、通常版0.50。

- [ ] **Step 2: ブロック境界の赤い検査を書く**

開始100から5、接触で追加5、空振りは5。開始5は通常版を維持し接触追加0、開始1から4は全消費バーンアウト版、既にバーンアウトなら0消費で体力倍率0.50。直接返球は10免除、回復15なし。

- [ ] **Step 3: ソフトブロックの赤い検査を書く**

元攻撃が後衛へ到達しても同じ攻撃IDの体力ダメージを再適用しない。後続通常アタックは15、後続受動返球は10になる。

- [ ] **Step 4: 赤を確認して最小実装する**

Run: `.\run_tests.ps1`

飛びつき開始時にモードと消費を確定する。ブロック開始時にmodeを固定し、接触時はmodeを優先する。ソフトブロックで攻撃圧力消費済みフラグを立てる。

- [ ] **Step 5: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Claudeへ残量0接触、現在行動保護、直接返球免除、後衛二重損害をレビュー依頼する。

```powershell
git add src/sim/simulation.gd src/sim/player_movement.gd src/sim/hit_resolver.gd tests/unit
git commit -m "feat: 飛びつきとブロックの資源契約を統合"
```

---

### Task 8: 体力100とスタン300tick

**Files:**
- Modify: `src/sim/sim_state.gd`
- Modify: `src/sim/combat_resources.gd`
- Modify: `src/sim/sim_config.gd`
- Modify: `src/sim/simulation.gd:450-550`
- Modify: `src/sim/player_movement.gd:60-125`
- Modify: `src/sim/hit_resolver.gd:429-622,832-860`
- Modify: `src/sim/ball_physics.gd`
- Modify: `src/display/score_ui.gd:140-165`
- Rewrite: `tests/unit/test_absolute_damage.gd`
- Create: `tests/unit/test_health_stun.gd`
- Modify: `tests/unit/test_receive_defense.gd`, `test_super_catalog.gd`, `test_state.gd`

**Interfaces:**
- Produces: `CombatResources.apply_health_damage(p, amount: int, cfg) -> int`
- Produces: `CombatResources.start_health_stun(p, cfg) -> void`
- Produces: `CombatResources.recover_health_stun(p) -> void`
- Consumes: Task 4のバーンアウトtimer、Task 7の防御倍率

- [ ] **Step 1: 体力名称と最大100の赤い検査を書く**

全キャラの `max_health==100`、セット開始100、ポイント終了維持、自然回復なしを固定する。旧 `guard_max_by_rank` と `stun_mash_bonus` を設定へ戻すと赤くする。

- [ ] **Step 2: スタン開始・終了の赤い検査を書く**

0到達で300tickスタン、299tickでは継続、300tickで100復帰。ラリー終了が先なら即100。ACTION連打でも同じ300tick。同一ラリー復帰後は最低1、次ラリーで再スタン可能。スタン中もバーンアウトtickは進み、ドライブは変わらない。

- [ ] **Step 3: 同tick接触の赤い検査を書く**

スタン解除tickに接触する場合、100復帰後に一度だけ体力ダメージを適用し、最低1へクランプする。スタン中は接触ダメージ0、同じ攻撃IDを二重適用しない。

- [ ] **Step 4: 赤を確認する**

Run: `.\run_tests.ps1`

- [ ] **Step 5: 既存状態を体力名称へ純粋改名する**

`Player.guard/guard_max/stun` を `health/max_health/stun_ticks`、`ball_guard_damage` を `ball_health_damage` へ一括移行する。宣言順と直列化位置を維持し、この段階では値、状態遷移、直列化長、同期ゴールデンを変えない。表示ラベルとテスト名も体力へ揃える。

- [ ] **Step 6: スタン状態機械を実装する**

純粋改名の検証後に、全キャラの最大体力を100へ統一する。連打処理と `stun_action_held/stun_mash_event` を削除する。ラリー中だけ残りtickを進め、300到達またはラリー終了で100復帰。同一ラリー最低1クランプを体力損害の共通関数で保証する。

- [ ] **Step 7: 全件検証、Claudeレビュー、コミット**

Run: `.\run_tests.ps1`

Claudeへ炎上終了からのスタン、同tick接触、再スタン防止、ラリー終了順をレビュー依頼する。
体力100とスタン挙動で同期ゴールデンが変わる場合、新旧値とこのTaskの状態遷移だけを原因として記録する。名称変更だけで追加の値変化を認めない。

```powershell
git add src/sim src/display/score_ui.gd tests/unit data/rules.json
git commit -m "feat: 体力100と5秒スタンへ移行"
```

---

### Task 9: UI、CPU、ログ、最終統合

**Files:**
- Modify: `src/display/score_ui.gd:140-190`
- Modify: `src/display/game_view.gd:500-660`
- Modify: `src/sim/sim_cpu.gd:590-1125`
- Modify: `src/sim/simulation.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`
- Modify: `tests/unit/test_cpu_offense_receive.gd`
- Create: `tests/unit/test_combat_resource_integration.gd`
- Create: `tests/unit/test_score_ui.gd`
- Modify: `tests/unit/test_sync.gd`, `test_zz_performance.gd`, `test_no_float_in_sim.gd`
- Modify: `docs/tasks/114.md`, `docs/remaining-tasks.md`

**Interfaces:**
- Consumes: Tasks 1から8の確定状態と共通API
- Produces: 人間とCPUで同一の行動可否、連続バー表示、最終同期契約

- [ ] **Step 1: 連続バー表示の赤い検査を書く**

0、5、15、25、35、99、100の各値を6区画へ連続比例で描画し、区画をコスト判定へ使わない。デバッグ表示は整数値と予約値を出す。バーンアウト点滅は残りtickだけを読む。

- [ ] **Step 2: CPUしきい値の赤い検査を書く**

CPUは24でジャストを選ばず、25で選択可能。34で必殺を選ばず、35で選択可能。4で構えを選ばず、5で選択可能。バーンアウトでは通常攻撃、弱体飛びつき、体力版ブロックだけを選ぶ。CPUだけ予約やコストを免除しない。

- [ ] **Step 3: 1ラリー統合検査を書く**

通常アタック15、反応構え5、防御返球10、飛びつき15、ブロック5+5、バーンアウト30復帰、体力スタン100復帰を一つの固定入力列で通し、各IDと一度性を検証する。同じ入力列をserialize/load後に再生して最終hash一致を確認する。

- [ ] **Step 4: 赤を確認してUIとCPUを実装する**

Run: `.\run_tests.ps1`

`score_ui.gd` は `fill_ratio = drive_gauge / 100.0` を表示層だけで使い、シミュレーションへfloatを戻さない。CPUは設定値を直接比較し、最終可否は必ず共通APIへ委ねる。

- [ ] **Step 5: 旧契約残存を検索する**

Run:

```powershell
rg -n "drive_gauge_stock|6000|stun_mash|guard_max_by_rank|_burnout_guard_damage|1\.5倍|0\.5本|1本|2本|3本" src data tests
```

Expected: 移行履歴を説明するテスト名や文書以外、実行ロジック0件。

- [ ] **Step 6: 正規全件検証を行う**

Run:

```powershell
.\run_tests.ps1
git diff --check
```

Expected: 全件合格、`SCRIPT ERROR summary: 0 occurrence(s)`、同期ゴールデン一致、性能門合格、diff check無出力。

- [ ] **Step 7: Claude最終レビューを行う**

設計書、全コミット一覧、最終差分、テスト結果を渡し、仕様取りこぼし、旧契約残存、二重適用、ロールバック非決定論を査読させる。指摘は証拠とコードで判定し、修正後に正規全件検証を再実行する。

- [ ] **Step 8: タスク文書を完了状態へ更新してコミットする**

`docs/tasks/114.md` に変更全件、最終設計書行数・SHA-256、テスト件数、同期ゴールデン新旧値、未検証の人間試遊を記録する。`docs/remaining-tasks.md` の#114を完了へ更新する。

```powershell
git add src data tests docs/tasks/114.md docs/remaining-tasks.md
git commit -m "feat: 戦闘リソース統合を完成"
```

## Execution Choice

ユーザーは本タスクをCodex主体、Claude Codeサポート、隔離worktreeなし、追加確認なしで
ノンストップ実行するよう指定している。したがって `superpowers:executing-plans` を使い、
このセッションでTask 1から順に実行する。各TaskのClaudeレビューと正規全件検証は省略しない。

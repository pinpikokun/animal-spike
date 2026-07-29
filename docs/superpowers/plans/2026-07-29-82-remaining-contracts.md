# #82 仮想打球テスト残契約 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ジャンプサーブを既存の3候補・4政策へ合流し、両120px制限を撤去し、将来の難易度調整用の幅格子を挙動不変のk=0で実装する。

**Architecture:** `HitResolver.preview_air_spike_velocity()` を中心速度の正本として維持し、`SimCpu._air_spike_candidate()` の内部だけを十字格子へ拡張する。`_pick_air_shot()` は末尾引数でkを候補層へ渡し、productionは既定値0を使う。ジャンプサーブは独自入力を廃止して `_pick_air_shot()` へ委譲し、距離制限は攻撃とブロックから一行ずつ除く。

**Tech Stack:** Godot 4.6、GDScript、PowerShell、既存 `tests/test_case.gd`、正規入口 `run_tests.ps1`

## Global Constraints

- 承認設計: `docs/superpowers/specs/2026-07-29-82-remaining-contracts-design.md` 449行、SHA-256 `5a4a9e26b685781816854f1b6895db705323bcaf4de48b221b9aca7e732dcb8f`
- productionの幅段数は全員 `0`。非ゼロ値をプリセット、キャラクター、rules.jsonへ配線しない。
- 地上通常サーブ、ジャンプ発火、`hit_resolver.gd`、設定値、CPUプリセット、キャラクター値を変更しない。
- 候補選択は同期状態を書き換えず、整数演算だけを使う。
- 固定値変更は一理由ごとに分離し、原因不明の値へ合わせない。
- 正規入口は常に `run_tests.ps1`。対象test自身の赤とSCRIPT ERROR 0を確認する。
- Claude Codeへ各主要段の差分レビューと最終レビューを依頼する。

---

### Task 1: 実ジャンプサーブの成立前提を診断する

**Files:**
- Temporarily create and delete: `tests/zz_probe_82_serve_contract.gd`
- Read: `tests/unit/test_cpu.gd`
- Read: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: `SimCpu._air_spike_candidate(s, actor, cfg, team, input, d2) -> Array[int]`
- Produces: 全得点・formation・左右について、候補数と政策甲実球の診断表

- [ ] **Step 1: 承認設計の同一性と基準テストを確認する**

```powershell
$p='docs/superpowers/specs/2026-07-29-82-remaining-contracts-design.md'
(Get-Content -Encoding UTF8 $p).Count
(Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
& .\run_tests.ps1
```

Expected: 449行、承認SHA、494 tests, 0 failed、SCRIPT ERROR 0、終了コード0。

- [ ] **Step 2: 実サーブ接触直前を採取する一時プローブを書く**

`test_cpu.gd::_cpu_serve_result()` と同じ11×11得点、formation 3種、左右2組を走らせる。
`serve_tossed == 1` かつサーバーが空中で、`_decide_serve()` がACTIONを返す直前に次を記録する。

```gdscript
var d2: int = dx * dx + dy_n * dy_n
var inputs: Array[int] = [
	SimInput.IN_ACTION | SimInput.IN_DOWN | back,
	SimInput.IN_ACTION | SimInput.IN_DOWN,
	SimInput.IN_ACTION | SimInput.IN_DOWN | fwd,
]
var valid := 0
for candidate_input in inputs:
	if not SimCpu._air_spike_candidate(
			state, server, cfg, serving_team, candidate_input, d2).is_empty():
		valid += 1
```

同じsnapshotを複製し、`IN_ACTION` の空中トスを `HitResolver._resolve_hit()` へ適用して、
BallPhysicsを床または得点まで進め、ネット通過と相手コート着地を記録する。

- [ ] **Step 3: 診断を3独立プロセスで実行する**

```powershell
$godot='tools\godot\Godot_v4.6-stable_win64_console.exe'
1..3 | ForEach-Object { & $godot --headless --path . --script res://tests/zz_probe_82_serve_contract.gd }
```

Expected: 全726組で候補数1以上、政策甲実球が全件ネット越え・相手コート着地、3回同一。
1組でも不成立なら一時プローブを削除して停止し、Claude Codeとユーザーへ証拠を報告する。

- [ ] **Step 4: 一時プローブを削除して作業ツリーを確認する**

```powershell
git status --short --ignored
```

Expected: `tests/zz_probe_82_serve_contract.gd` が存在せず、作業差分0。

---

### Task 2: 幅格子をk=0挙動不変で実装する

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`

**Interfaces:**
- Produces: `SimCpu._trial_band_velocities(actual: Vector2i, k: int) -> Array[Vector3i]`
- Modifies: `SimCpu._air_spike_candidate(..., d2: int, k: int = TRIAL_BAND_CURRENT_STEPS) -> Array[int]`
- Modifies: `SimCpu._pick_air_shot(..., d2: int, k: int = TRIAL_BAND_CURRENT_STEPS) -> int`
- Preserves: 戻り値 `[actual_input, believed_land_x]`

- [ ] **Step 1: 格子の失敗テストを書く**

次の固定期待値を本番helperを使わずに置く。

```gdscript
func test_trial_band_cross_order_counts_and_zero_axis() -> void:
	check_eq(SimCpu._trial_band_velocities(Vector2i(1000, -500), 1), [
		Vector3i(1000, -550, 1),
		Vector3i(900, -500, 1),
		Vector3i(1000, -500, 0),
		Vector3i(1100, -500, 1),
		Vector3i(1000, -450, 1),
	], "iy外側・ix内側の十字")
	check_eq(SimCpu._trial_band_velocities(Vector2i(0, -500), 1).size(), 3,
		"vxゼロは横座標を除外")
	check_eq(SimCpu._trial_band_velocities(Vector2i(1000, -500), 3).size(), 13,
		"k3は13論理点")
	check_eq(SimCpu.TRIAL_BAND_CURRENT_STEPS, 0, "production幅はゼロ")
```

左右鏡像、歩幅0の重複保持、k=-1とk=4の空配列も同じtest群へ追加する。
3方向それぞれの正確速度からk=3の論理点を数え、政策3の構造上限が
`3候補 * 13点 = 39点` であることも本番helperの返却数から固定する。

- [ ] **Step 2: 対象testを実行して赤を確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 新しい格子helper未実装の対象testだけがFAIL、SCRIPT ERROR 0。

- [ ] **Step 3: 十字速度列を最小実装する**

```gdscript
const TRIAL_BAND_STEP_PCT := 10
const TRIAL_BAND_K_MAX := 3
const TRIAL_BAND_CURRENT_STEPS := 0

static func _trial_band_velocities(actual: Vector2i, k: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if k < 0 or k > TRIAL_BAND_K_MAX:
		return out
	var step_x: int = absi(actual.x) * TRIAL_BAND_STEP_PCT / 100
	var step_y: int = absi(actual.y) * TRIAL_BAND_STEP_PCT / 100
	for iy in range(-k, k + 1):
		for ix in range(-k, k + 1):
			if ix != 0 and iy != 0:
				continue
			if actual.x == 0 and ix != 0:
				continue
			out.append(Vector3i(
				actual.x + signi(actual.x) * ix * step_x,
				actual.y + iy * step_y,
				absi(ix) + absi(iy)))
	return out
```

- [ ] **Step 4: 候補を格子評価へ拡張する**

`_air_spike_candidate()` は速度列を全走査し、有効点の最小 `point.z` を採る。
同距離では `<` だけで更新し、先着点を維持する。

```gdscript
var best: Array[int] = []
var best_distance := 0x7FFFFFFFFFFFFFFF
for point in _trial_band_velocities(actual_velocity, k):
	var land := _land_x_from(s.ball_x, s.ball_y, point.x, point.y, cfg,
		cfg.floor_y - cfg.ball_radius, 3)
	var in_opponent_court: bool = land > cfg.net_x if team == 0 else land < cfg.net_x
	if not in_opponent_court:
		continue
	if not already_crossed and not _clears_net(
			s.ball_x, s.ball_y, point.x, point.y, cfg):
		continue
	if point.z < best_distance:
		best = [input, land]
		best_distance = point.z
return best
```

`_pick_air_shot()` に末尾既定引数 `k = TRIAL_BAND_CURRENT_STEPS` を追加し、
候補を呼ぶ全経路でそのkを `_air_spike_candidate(..., d2, k)` へ渡す。

- [ ] **Step 5: k=0回帰と非ゼロ幅の契約testを通す**

中心有効ならkを増やしても同じ中心landを信じること、中心無効・幅点有効のfixture、
左右鏡像、k単調、状態配列不変、snapshot復元一致を検査する。
意図的ミスfixtureでは `_pick_air_shot(..., 3)` が幅点を信じて実入力を採用し、
その中心実球が独立した着地・ネット判定ではネットへ衝突することまで確認する。
中心無効・幅点有効fixtureをk=3までで作れなければ停止する。

- [ ] **Step 6: 正規全件と固定値不変を確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 全件緑、GOLDEN_COMBINED_HASH不変、PERF_GATE緑。変化すれば停止。

- [ ] **Step 7: Claude Codeへk=0同値性レビューを依頼してコミットする**

```powershell
git add src/sim/sim_cpu.gd tests/unit/test_cpu_trial_shot.gd
git commit -m "feat: #82の仮想打球幅格子を追加する"
```

---

### Task 3: ジャンプサーブを3候補・4政策へ共通化する

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`
- Modify: `tests/unit/test_cpu.gd`
- Modify only when the golden result changes: `tests/unit/test_sync.gd`
- Create only when the golden result changes: `docs/tasks/82-golden-evidence.md`

**Interfaces:**
- Consumes: `_pick_air_shot(s, actor, cfg, team, can_spike, d2, k = TRIAL_BAND_CURRENT_STEPS) -> int`
- Preserves: `_decide_serve(s, idx, cfg, prof) -> int`

- [ ] **Step 1: サーブ共通化の失敗テストを書く**

空中・`serve_tossed=1` の左右サーバーfixtureを作り、固定aitickの政策1/2/3/甲を検査する。

```gdscript
var actual: int = SimCpu._decide_serve(s, actor, cfg, profile)
check_eq(actual & (Simulation.IN_LEFT | Simulation.IN_RIGHT |
	Simulation.IN_UP | Simulation.IN_DOWN | Simulation.IN_ACTION),
	expected_input, "ジャンプサーブも共通政策入力")
```

全候補有効fixtureの政策甲は `IN_ACTION` だけとし、早期returnを一時削除すると赤になることを確認する。
同じaitickの左右サーバーで `_air_shot_policy()` が同じことも直接検査する。
同じ `aitick` のまま接触窓内の球位置とtickだけを進めても政策が変わらないことを検査する。

- [ ] **Step 2: 正規全件で③奥固定の赤を確認する**

Expected: 政策1/甲など新しいサーブ入力testがFAIL、既存494件はゴールデン以外維持。

- [ ] **Step 3: 空中接触枝だけを共通helperへ委譲する**

```gdscript
if dx * dx + dy_n * dy_n <= reach * reach:
	if attack_serve and p.on_ground == 0:
		return _pick_air_shot(s, idx, cfg, s.serving_team, true,
			dx * dx + dy_n * dy_n, TRIAL_BAND_CURRENT_STEPS)
	return SimInput.IN_ACTION | fwd
```

地上枝、ジャンプ計画、`P_TIQ >= 2` は変更しない。

- [ ] **Step 4: 実サーブ全組合せtestを通す**

11×11得点、formation 3、左右2で候補1以上、政策甲のネット越え・相手着地、
政策甲サーブが1回目の合法なサーブ接触となり4回目接触扱いにならないこと、
通常地上サーブ不変、ジャンプランクA/B/C/Eの発火不変を検査する。

- [ ] **Step 5: ゴールデン変化を単独調査する**

ゴールデンだけが赤なら旧値、新値、checkpoint差、次checkpointでの再合流を
`docs/tasks/82-golden-evidence.md` へ「ジャンプサーブ共通化」1理由として記録する。
他の赤がある間は値を更新しない。

- [ ] **Step 6: 全件緑にしてレビュー後コミットする**

```powershell
git add src/sim/sim_cpu.gd tests/unit/test_cpu_trial_shot.gd tests/unit/test_cpu.gd tests/unit/test_sync.gd
if (Test-Path 'docs/tasks/82-golden-evidence.md') { git add docs/tasks/82-golden-evidence.md }
git commit -m "feat: #82の仮想打球政策をジャンプサーブへ適用する"
```

存在しないファイルや不変ファイルは `git add` から除く。

---

### Task 4: 攻撃側120px制限を撤去する

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`
- Modify only when the golden result changes: `tests/unit/test_sync.gd`
- Modify only when the golden result changes: `docs/tasks/82-golden-evidence.md`

**Interfaces:**
- Modifies: `_decide_air_hit()` の `can_spike`
- Preserves: `_attack_ok()`、`_should_use_flame()`、打撃楕円

- [ ] **Step 1: 深位置の失敗テストを書く**

ネットから120px超の選手と楕円内の球を置き、有効候補がある前提を直接検査してから
`IN_ACTION | IN_DOWN` を期待する。楕円外と全候補無効の対照も置く。
炎必殺は既存専用条件を満たすfixtureで `IN_ABILITY1 | IN_DOWN` を期待する。
同じfixtureで `HitResolver.preview_air_spike_velocity()` の返値を距離撤去前の固定期待値と
直接比較し、炎必殺の速度が試し打ち格子や距離撤去で変わらないことを固定する。

- [ ] **Step 2: 対象testが距離条件だけで赤になることを確認する**

Expected: 深位置通常攻撃と深位置炎必殺だけがFAIL、SCRIPT ERROR 0。

- [ ] **Step 3: 共有距離条件を一箇所だけ除く**

```gdscript
var can_spike: bool = _attack_ok(s, idx, prof)
```

必殺専用条件、候補、速度、楕円へ他の変更を加えない。

- [ ] **Step 4: 全件、決定論、ゴールデンを一理由で処理する**

ゴールデンが動けば「攻撃側120px撤去」の節を証拠文書へ追加し、他の赤が無い状態で更新する。

- [ ] **Step 5: Claude Codeレビュー後コミットする**

```powershell
git add src/sim/sim_cpu.gd tests/unit/test_cpu_trial_shot.gd tests/unit/test_sync.gd
if (Test-Path 'docs/tasks/82-golden-evidence.md') { git add docs/tasks/82-golden-evidence.md }
git commit -m "fix: #82の深位置アタック制限を撤去する"
```

---

### Task 5: ブロック側120px制限と消滅検査を直す

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Modify: `tests/unit/test_cpu.gd`
- Modify only when the golden result changes: `tests/unit/test_sync.gd`
- Modify only when the golden result changes: `docs/tasks/82-golden-evidence.md`

**Interfaces:**
- Modifies: `_decide_block()` の相手距離continueだけ
- Preserves: role、mate meet、post、jump、walk、physics

- [ ] **Step 1: 消滅した2契約と対照の失敗テストを書く**

既存 `_block_priority_world()` を深位置へ拡張し、次を独立に検査する。

```gdscript
attacker.x = cfg.net_x + FP.from_int(160)
s.ball_x = attacker.x
s.ball_y = attacker.y
check(SimCpu._decide_block(s, blocker_idx, blocker, cfg, 0,
	SimCpu.AB_BLOCK, 0) & Simulation.IN_JUMP,
	"120px超のアタッカーにもブロックへ反応")
```

役持ちだけ、相方会合不能時の代役、能力なし、相手地上、球圏外、相手2人同時も検査する。

- [ ] **Step 2: 深位置ブロックだけが赤になることを確認する**

Expected: 120pxの既存continueにより新規深位置testがFAIL。

- [ ] **Step 3: 距離continueだけを削除する**

```gdscript
# Delete only:
if absi(o.x - cfg.net_x) > FP.from_int(120):
	continue
```

- [ ] **Step 4: 既存優先順位と全件を確認する**

ゴールデンが動けば「ブロック側120px撤去」の一理由だけで証拠を追加する。

- [ ] **Step 5: Claude Codeレビュー後コミットする**

```powershell
git add src/sim/sim_cpu.gd tests/unit/test_cpu.gd tests/unit/test_sync.gd
if (Test-Path 'docs/tasks/82-golden-evidence.md') { git add docs/tasks/82-golden-evidence.md }
git commit -m "fix: #82の深位置ブロック制限を撤去する"
```

---

### Task 6: #83性能上限を承認式で締め直す

**Files:**
- Temporarily create and delete: `tests/zz_probe_82_geometry_perf.gd`
- Modify: `tests/unit/test_zz_performance.gd`
- Modify: `docs/tasks/83.md`

**Interfaces:**
- Consumes: 既存 `test_zz_performance.gd` のpolicy 2・3候補fixture
- Produces: 新しい `AIR_UPPER_NS`

- [ ] **Step 1: 既存fixtureを5独立プロセスで測る**

各プロセスの5サンプル最小値を記録し、次で計算する。

```text
new_limit_ns = ceil(max(process_min_ns) * 1.20 / 1000) * 1000
```

65,000nsを超えたら停止する。

- [ ] **Step 2: 遠距離とジャンプサーブ幾何を診断する**

一時プローブで各fixtureを5独立プロセス測定する。
どちらかの `process_min` が新上限を超えたら、上限やfixtureを変えず停止する。

- [ ] **Step 3: 恒久上限だけを新値へ変更する**

`AIR_UPPER_NS` の右辺をStep 1の5実測値から承認式で算出した整数へ変更する。
変更前に5値、最大値、1.20倍、1000ns単位の切り上げ結果を `docs/tasks/83.md` へ記録し、
コードにはその計算結果をそのまま使う。

- [ ] **Step 4: mutationと独立5回を実行する**

- 上限1nsで対象性能test自身が赤
- `_decide_air_hit()` 2倍呼び出しで対象性能test自身が赤
- 正式値で独立5回すべて494件以上、0 failed、SCRIPT ERROR 0、PERF_GATE 1行

- [ ] **Step 5: #83へ締め直し証拠を追記してコミットする**

```powershell
git add tests/unit/test_zz_performance.gd docs/tasks/83.md
git commit -m "test: #82完了後の性能上限を締め直す"
```

---

### Task 7: #82を完了記録へ移す

**Files:**
- Modify: `docs/tasks/82.md`
- Modify: `docs/remaining-tasks.md`
- Modify only when the file was created by Tasks 3〜5: `docs/tasks/82-golden-evidence.md`

**Interfaces:**
- Consumes: Tasks 1〜6の実測、commit、Claude Codeレビュー
- Produces: #82完了記録

- [ ] **Step 1: 静的契約を確認する**

```powershell
rg -n "120|TRIAL_BAND|_pick_air_shot|_decide_serve" src/sim/sim_cpu.gd tests/unit
git diff 1f6808d..HEAD -- src/sim/hit_resolver.gd data
git diff --check
```

Expected: 120px距離条件2箇所なし、幅current=0、hit_resolver/data差分0。

- [ ] **Step 2: 正規全件を新たに実行する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 全件0 failed、SCRIPT ERROR 0、終了コード0、PERF_GATE 1行。

- [ ] **Step 3: Claude Codeへ最終レビューを依頼する**

設計適合、幅k=0、サーブ共通化、両距離撤去、ゴールデン因果、性能停止条件、
production範囲をレビュー対象にする。P0/P1があれば修正後に全検証をやり直す。

- [ ] **Step 4: 完了文書を更新する**

`docs/tasks/82.md` に全変更、全test、mutation、5回性能値、ゴールデン証拠、
Claude Code最終判定、#84への非ゼロk引継ぎを記録する。
`docs/remaining-tasks.md` から #82を除く。

- [ ] **Step 5: 文書をコミットしてcleanを確認する**

```powershell
git add docs/tasks/82.md docs/remaining-tasks.md
if (Test-Path 'docs/tasks/82-golden-evidence.md') { git add docs/tasks/82-golden-evidence.md }
git commit -m "docs: #82の完了結果を記録する"
git status --short
```

Expected: status出力なし。

# Original Ground Special Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CPUの地上打球必殺だけを原作の難易度別許可ゲートへ合わせ、空中打球必殺、吸い込み、亜空間ブロックの現行方針を維持する。

**Architecture:** `activation.contact` を必殺技分類の正本とし、`SpecialMoves` の合法性と `SimCpu` の使用方針を分離する。CPUプロファイルのbit 56から58へ地上必殺方針を明示し、地上打球だけ原作ゲート、他カテゴリは既存方針へ送る。

**Tech Stack:** Godot 4.6、GDScript、固定小数シミュレーション、PowerShellテスト入口

## Global Constraints

- 正式仕様は `docs/superpowers/specs/2026-08-03-original-ground-special-permission-design.md` 250行、SHA-256 `f18f034486b545c032315c512f3474c757fd18dc2555c2886179b5571f06ecff`。
- 実装開始前と各コミット前に上記行数とSHA-256を照合し、不一致なら停止する。
- 原作率は地上打球必殺だけへ適用する。
- イージーは `aitick % 8 == 0`、ノーマルは `rng % 4 == 0`、ハードは `aitick % 3 < 2`、スーパーは `rng % 4 < 3`。
- 許可判定は `rng`、`aitick`、球、プレイヤー、ゲージを変更しない。
- 空中打球必殺、DUO吸い込み、SEC1亜空間ブロックは現行方針を維持する。
- CPUプロファイルの新フィールドはbit 56から58だけを使い、bit 63へ触れない。
- 対象外の未追跡 `vb2211/` は変更、追加、削除、ステージしない。
- ワークツリーは使用せず、現在のブランチで作業する。
- 既存ベースラインでは706件中、性能検査だけが3回連続で54,000nsを118から1,967ns超過した。閾値は変更せず、機能検査と最終全件結果を分けて報告する。

---

## File Structure

- Modify: `src/sim/special_moves.gd` - 打球接触分類を一か所へ集約する。
- Create: `src/sim/cpu_profile.gd` - CPUプロファイルのビット割当、プリセット、組立関数を一元管理する。
- Modify: `src/sim/sim_cpu.gd` - プロファイル互換API、原作地上ゲート、カテゴリ別方針を実装する。
- Modify: `src/sim/sim_state.gd` - CPU既定値の巨大な複製リテラルを正本参照へ置き換える。
- Modify: `tests/unit/test_cpu.gd` - プロファイル正本と互換APIの往復を検査する。
- Modify: `tests/unit/test_original_special_cpu.gd` - 原作率、カテゴリ分離、状態非破壊の回帰検査を置く。
- Modify only if expected: `tests/unit/test_sync.gd` - プロファイル整数変更で同期ゴールデンだけが変わった場合に、原因を確認して更新する。

## Task 1: RED - 利用者から見える許可ゲート契約を固定する

**Files:**
- Modify: `tests/unit/test_original_special_cpu.gd`

**Interfaces:**
- Consumes: `SimCpu.decide(s, idx, cfg) -> int`、`SpecialMoves.select_hit_special(s, actor, input, cfg) -> int`
- Produces: 原作ゲート、カテゴリ分離、不正値拒否を実装前に赤くする検査

- [ ] **Step 1: 設計正本を照合する**

Run:

```powershell
$f='docs/superpowers/specs/2026-08-03-original-ground-special-permission-design.md'
(Get-Content -LiteralPath $f -Encoding utf8).Count
(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
```

Expected: `250` と `f18f034486b545c032315c512f3474c757fd18dc2555c2886179b5571f06ecff`。

- [ ] **Step 2: 原作4方針を作るテスト用プロファイル補助を追加する**

`test_original_special_cpu.gd` に追加する。

```gdscript
const GROUND_POLICY_SHIFT := 56
const GROUND_POLICY_MASK := 0x7

func _profile_with_ground_policy(base: int, policy: int) -> int:
	return (base & ~(GROUND_POLICY_MASK << GROUND_POLICY_SHIFT)) \
		| ((policy & GROUND_POLICY_MASK) << GROUND_POLICY_SHIFT)
```

期待値はテスト側のリテラルで作り、本番の新定数を再利用しない。

- [ ] **Step 3: 4難易度の剰余表を公開入力経路で検査する**

次のテーブルを手書きし、各行でTOMEの地上状態を作る。`aitick` と `rng` を設定して `SimCpu.decide()` を呼び、許可行はD入力あり、拒否行はD入力なしを確認する。

```gdscript
var rows: Array[Array] = [
	[SimCpu.PRESET_WEAK, 0, 1, true],
	[SimCpu.PRESET_WEAK, 1, 0, false],
	[SimCpu.PRESET_NORMAL, 7, 0, true],
	[SimCpu.PRESET_NORMAL, 0, 1, false],
	[SimCpu.PRESET_STRONG, 0, 2, true],
	[SimCpu.PRESET_STRONG, 1, 3, true],
	[SimCpu.PRESET_STRONG, 2, 0, false],
	[SimCpu.PRESET_MAX, 9, 0, true],
	[SimCpu.PRESET_MAX, 0, 2, true],
	[SimCpu.PRESET_MAX, 4, 3, false],
]
```

各worldでプレイヤーと球を接触位置へ置き、`last_touch_team = 0`、ドライブ100、ラリー中を維持する。

- [ ] **Step 4: 乱数源と状態非破壊を検査する**

イージーとハードでは同じ `aitick` のまま `rng` を0から3へ変えて結果が一定、ノーマルとスーパーでは同じ `rng` のまま `aitick` を0から7へ変えて結果が一定であることを確認する。各判断前後で `to_int_array()` が一致することも確認する。

- [ ] **Step 5: 同一技IDの地上と空中が別方針になることを検査する**

HITOの `SUPER_DISAPPEARING_BALL` を使う。AB_ATTACK、AB_SWEET、TIQ3を持つ既存許可プロファイルへイージー方針1をbit 56から58へ設定し、`aitick = 1` とする。

```gdscript
var prof := _profile_with_ground_policy(
	SimCpu.make_profile(SimCpu.AB_ATTACK | SimCpu.AB_SWEET,
		0, 0, 0, 255, 3, 3), 1)
```

Expected:

- 地上の上+Dは原作イージーゲートで拒否される。
- 空中の下+Dは現行プロファイル判定で許可される。
- どちらも `SpecialMoves.select_hit_special()` の合法性を共有する。

- [ ] **Step 6: 独立行動、ブロック、不正値の境界を検査する**

- DUO吸い込みは、既存の `test_duo_cpu_can_choose_suction_outside_normal_hit_reach_without_mutation()` を方針値の追加後も成功させる。
- SEC1強化ブロックは、既存の費用境界テストを成功させる。
- 方針5から7の地上TOMEはD入力を返さない。
- `on_ground = 2` のHITOへ空中入力を渡しても `select_hit_special()` は0を返す。

- [ ] **Step 7: REDを確認する**

Run:

```powershell
$o = & .\run_tests.ps1 2>&1
$o | Select-String 'test_original_special_cpu|tests,|PERF_GATE|SCRIPT ERROR summary'
exit $LASTEXITCODE
```

Expected: 新しい原作ゲート検査が現行0/0/約59.8/常時のため失敗する。性能検査の既知失敗とは別に、実装対象の失敗名を確認する。

## Task 2: GREEN - 接触分類とCPU方針を分離して実装する

**Files:**
- Modify: `src/sim/special_moves.gd`
- Create: `src/sim/cpu_profile.gd`
- Modify: `src/sim/sim_cpu.gd`
- Modify: `src/sim/sim_state.gd`
- Modify: `tests/unit/test_cpu.gd`

**Interfaces:**
- Consumes: `Chars.SpecialContact`、`p.on_ground`、`s.aitick`、`s.rng`、パック済みCPUプロファイル
- Produces: `SpecialMoves.hit_contact_for_player(p) -> int`、カテゴリ別CPU許可関数

- [ ] **Step 1: 接触分類をSpecialMovesへ集約する**

`special_moves.gd` に追加する。

```gdscript
static func hit_contact_for_player(p) -> int:
	if p.on_ground == 1:
		return Chars.SPECIAL_CONTACT_GROUND_HIT
	if p.on_ground == 0:
		return Chars.SPECIAL_CONTACT_AIR_HIT
	return -1
```

`select_hit_special()` の三項演算子をこの関数へ置き換える。`-1` はどのactivationにも一致しないため不正状態を拒否する。

- [ ] **Step 2: CPUプロファイルを専用正本へ分離する**

`cpu_profile.gd` を作り、`sim_cpu.gd` から能力フラグ、ビットシフト、4プリセット、`make_profile()`、`prof_byte()` を移す。地上必殺方針は次の3bit定義を使う。

```gdscript
const P_GROUND_SPECIAL_POLICY_SHIFT := 56
const GROUND_SPECIAL_POLICY_MASK := 0x7
const GROUND_SPECIAL_PROFILE := 0
const GROUND_SPECIAL_EASY := 1
const GROUND_SPECIAL_NORMAL := 2
const GROUND_SPECIAL_HARD := 3
const GROUND_SPECIAL_SUPER := 4
```

4プリセットへ1から4を設定する。`make_profile()` の末尾へ `ground_special_policy: int = GROUND_SPECIAL_PROFILE` を追加し、3bitだけをパックする。

`sim_cpu.gd` は `CpuProfile` をpreloadし、既存公開名を次の形で参照する。

```gdscript
const AB_PREDICT := CpuProfile.AB_PREDICT
const P_AB := CpuProfile.P_AB
const PRESET_MAX := CpuProfile.PRESET_MAX
const PRESETS := CpuProfile.PRESETS

static func make_profile(ab: int, delay: int, aim: int, miss: int, sweet: int,
		depth: int, tiq: int,
		ground_special_policy: int = GROUND_SPECIAL_PROFILE) -> int:
	return CpuProfile.make_profile(ab, delay, aim, miss, sweet, depth, tiq,
		ground_special_policy)
```

互換APIには数値を複製しない。

- [ ] **Step 3: SimStateの複製リテラルを正本参照へ置き換える**

`sim_state.gd` で `CpuProfile` をpreloadし、`Player.cpu` を次へ変更する。

```gdscript
var cpu: int = CpuProfile.PRESET_MAX
```

コメントも8bit 7欄という旧説明から、3bit地上必殺方針を含むパック済みプロファイルへ更新する。

`test_cpu.gd.test_profile_pack_roundtrip()` は強プリセットを組むとき `CpuProfile.GROUND_SPECIAL_HARD` 相当の引数を明示し、既定引数0が旧方針を保持する検査も追加する。

- [ ] **Step 4: 現行方針を名前付き関数として保存する**

現行 `_wants_special()` を `_profile_special_allowed()` へ改名し、本文を変えない。DUO吸い込み、`_should_use_flame()`、空中打球必殺はこの関数を使う。

```gdscript
static func _profile_special_allowed(s, idx: int, prof: int) -> bool:
	var ab: int = prof_byte(prof, P_AB)
	if not (ab & AB_ATTACK) or not (ab & AB_SWEET):
		return false
	return prof_byte(prof, P_TIQ) >= 3 \
		or _derived_roll(SALT_SUPER, s, idx) % 256 < prof_byte(prof, P_SWEET)
```

- [ ] **Step 5: 原作地上ゲートを純粋関数で実装する**

```gdscript
static func _ground_hit_special_allowed(s, idx: int, prof: int) -> bool:
	var policy: int = (prof >> P_GROUND_SPECIAL_POLICY_SHIFT) \
		& GROUND_SPECIAL_POLICY_MASK
	match policy:
		GROUND_SPECIAL_PROFILE:
			return _profile_special_allowed(s, idx, prof)
		GROUND_SPECIAL_EASY:
			return s.aitick % 8 == 0
		GROUND_SPECIAL_NORMAL:
			return s.rng % 4 == 0
		GROUND_SPECIAL_HARD:
			return s.aitick % 3 < 2
		GROUND_SPECIAL_SUPER:
			return s.rng % 4 < 3
		_:
			return false
```

この関数で状態を書き換えない。

- [ ] **Step 6: 接触カテゴリで方針を選ぶ**

```gdscript
static func _hit_special_allowed(s, idx: int, prof: int, contact: int) -> bool:
	match contact:
		Chars.SPECIAL_CONTACT_GROUND_HIT:
			return _ground_hit_special_allowed(s, idx, prof)
		Chars.SPECIAL_CONTACT_AIR_HIT:
			return _profile_special_allowed(s, idx, prof)
	return false
```

`_special_hit_input()` は `SpecialMoves.hit_contact_for_player(p)` を一度取得し、この関数が許可した場合だけ既存候補を走査する。候補配列と `select_hit_special()` の合法判定は変えない。

- [ ] **Step 7: GREENを確認する**

Run:

```powershell
$o = & .\run_tests.ps1 2>&1
$o | Select-String 'test_original_special_cpu|test_super_catalog|test_sync|tests,|PERF_GATE|SCRIPT ERROR summary'
exit $LASTEXITCODE
```

Expected: 新規機能検査と対象回帰検査はPASS。同期ゴールデンがプロファイル整数の変更だけで失敗した場合はTask 3へ進む。性能検査の既知失敗は値を記録する。

## Task 3: 同期差分の説明、レビュー、最終検証

**Files:**
- Modify if required: `tests/unit/test_sync.gd`
- Create: none

**Interfaces:**
- Consumes: Task 2の緑の実装、同期ゴールデン、Claude Codeレビュー
- Produces: 説明可能な同期基準、最終コミット

- [ ] **Step 1: 同期ゴールデン差分を原因まで確認する**

`test_sync.gd.test_golden_hash_regression` だけが固定ハッシュ差分で失敗した場合、同じseedの2回実行で同じ新値になること、プレイヤーCPUプロファイル以外の状態配列長と順序が変わっていないことを確認する。原因がbit 56から58の方針追加に限定できた場合だけ期待値を一度更新する。

Unexpected: 同期ゴールデン以外の固定配列、入力ゴールデン、物理値が変わった場合は実装を停止する。

- [ ] **Step 2: 対象テストを再実行する**

Run:

```powershell
$o = & .\run_tests.ps1 2>&1
$o | Select-String 'test_original_special_cpu|test_super_catalog|test_rng_draw_contracts|test_sync|tests,|PERF_GATE|SCRIPT ERROR summary'
exit $LASTEXITCODE
```

Expected: 機能検査、カテゴリ境界、乱数非破壊、同期検査はPASS。既知の性能検査が残る場合は実測値を保持する。

- [ ] **Step 3: Claude Codeへ実差分を査読依頼する**

レビュー依頼には次を含める。

- 仕様書パス、250行、SHA-256
- 原作4ゲートと `aitick` / `rng` の使い分け
- 接触カテゴリを正本にしたこと
- bit 56から58以外を使わないこと
- 空中打球必殺、吸い込み、強化ブロックが変わらないこと
- `git diff` と対象テスト結果

CriticalとImportantは修正し、指摘が誤りならコードとテストを根拠に反証する。

- [ ] **Step 4: 正規入口で最終全件検証する**

Run:

```powershell
.\run_tests.ps1
```

Expected: `SCRIPT ERROR summary: 0 occurrence(s)`。機能検査は全件PASS。性能検査が54,000nsを超える場合、今回差分前から3回再現した既存ベースライン失敗として実測値を報告し、閾値は変更しない。

- [ ] **Step 5: 差分検査とコミットを行う**

Run:

```powershell
git diff --check
git status --short
git diff --stat
git diff -- src/sim/cpu_profile.gd src/sim/special_moves.gd src/sim/sim_cpu.gd src/sim/sim_state.gd tests/unit/test_cpu.gd tests/unit/test_original_special_cpu.gd tests/unit/test_sync.gd
```

Expected: `vb2211/` 以外は仕様、計画、対象production、対象testだけ。対象外差分なし。

Commit:

```powershell
git add -- src/sim/cpu_profile.gd src/sim/special_moves.gd src/sim/sim_cpu.gd src/sim/sim_state.gd tests/unit/test_cpu.gd tests/unit/test_original_special_cpu.gd tests/unit/test_sync.gd docs/superpowers/specs/2026-08-03-original-ground-special-permission-design.md docs/superpowers/plans/2026-08-03-original-ground-special-permission.md
git commit -m "feat: CPU地上必殺技を原作許可率へ変更"
```

コミットフックが既知の性能検査だけで失敗する場合は、最終実測を報告へ残したうえで `--no-verify` を使う。機能検査、同期検査、スクリプトエラーが失敗している場合は迂回しない。

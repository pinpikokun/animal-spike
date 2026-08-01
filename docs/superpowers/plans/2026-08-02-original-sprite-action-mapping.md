# Original Sprite Action Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原作8キャラの全24セルを正しいアニメ資産として完成させ、実装済みのブロック、トス、アタック、レシーブ、横っ飛びへ正しく接続する。

**Architecture:** `SpriteFactory` が原作セルとアニメ名の唯一の登録場所になり、`HitResolver` が成立した動作種別を既存の `hit_kind` へ必ず記録する。`AnimSelect` はその種別からアニメ名と決定論的なコマ番号を選び、`GameView` は原作8キャラだけに原作のコマ進行を適用する。

**Tech Stack:** Godot 4.6、GDScript、PowerShellテスト入口 `run_tests.ps1`

## Global Constraints

- 承認設計は `docs/superpowers/specs/2026-08-02-original-sprite-action-mapping-design.md` の147行、SHA-256 `6cab4115dc0dde490259fba59f917d0144b7f498228165d7407767cd267c9428`。
- 正本は `00_sprite-sample/スプライトセル対応表.txt`。
- 原作8キャラ以外の画像ファイルとセル割り当てを変えない。
- 打球物理、入力、当たり判定、ゲージ、乱数を変えない。
- `hit_kind` の直列化形式は変えず、成立動作に応じた値だけを正す。
- 固定ハッシュが変化した時点で停止し、旧値と実測値をユーザーへ報告する。
- Claude Codeへ実装後レビューを依頼し、回答を契約とコードへ照合する。

---

### Task 1: 原作8キャラの全セル登録を契約化する

**Files:**
- Modify: `src/display/sprite_factory.gd`
- Modify: `tests/unit/test_sprite_factory.gd`

**Interfaces:**
- Consumes: `SpriteFactory.build_for(char_id: int) -> SpriteFrames`
- Produces: `SpriteFactory.ORIGINAL_IDS: Array[int]`、`SpriteFactory.is_original_char(char_id: int) -> bool`、全原作アニメ名を持つ `SpriteFrames`

- [ ] **Step 1: 全セルと保持tickの失敗テストを書く**

`test_sprite_factory.gd` に、原作8 IDをリテラルで列挙し、各アニメの期待セルを次の表で検査する。期待値は実装の辞書を再利用せず、テスト内のリテラルにする。

```gdscript
const ORIGINAL_IDS := [4, 5, 6, 7, 8, 9, 10, 11]
const ORIGINAL_CELL_ROWS := {
	"idle": [0, 1], "run": [0, 1], "jump": [2],
	"attack": [3, 4, 5], "block": [9], "receive_stance": [6],
	"ground_swing": [9, 8, 7, 6], "toss": [7],
	"toss_fwd": [9, 8, 7, 6], "dive": [11, 10, 7, 0],
	"hurt": [12], "shock": [12, 13], "stun": [14, 15],
	"burn": [16, 17], "fly": [18, 19, 20, 19],
	"fly_hover": [18], "victory": [21, 22], "fall_special": [23],
}
```

各 `AtlasTexture.region` から `(region.position.y / 32) * 12 + region.position.x / 32` を手計算し、上表と一致させる。`bubble` はPIYOだけ4、他7体は20と別検査にする。`attack`、`ground_swing`、`dive`、`shock`、`stun`、`burn`、`fly`、`victory` の `frame_duration` もリテラルで検査する。

- [ ] **Step 2: 正規入口を実行してREDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: `ground_swing`、`toss_fwd`、`fly_hover`、PIYOの`bubble`、`stun`、`burn`、`victory`のいずれかでFAIL。パースエラーではなく現行契約との差で失敗すること。

- [ ] **Step 3: 最小のセル登録修正を行う**

`sprite_factory.gd` に原作8 IDと判定関数を追加する。

```gdscript
const ORIGINAL_IDS: Array[int] = [
	Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO, Chars.CHAR_UME,
	Chars.CHAR_CARBY, Chars.CHAR_DUO, Chars.CHAR_SEC1, Chars.CHAR_SEC2,
]

static func is_original_char(char_id: int) -> bool:
	return char_id in ORIGINAL_IDS
```

`build_original` を `build_original(sheet_path: String, bubble_cell: int = 20)` とし、PIYOの `build_for` だけ第2引数へ4を渡す。登録を次へ合わせる。

```gdscript
_add_original_sheet(sf, "ground_swing", sheet_path, [9, 8, 7, 6], [2, 2, 2, 4], false)
_add_original_sheet(sf, "toss_fwd", sheet_path, [9, 8, 7, 6], [2, 2, 2, 4], false)
_add_original_sheet(sf, "stun", sheet_path, [14, 15], [3, 3], true)
_add_original_sheet(sf, "burn", sheet_path, [16, 17], [3, 3], true)
_add_original_sheet(sf, "fly_hover", sheet_path, [18], [1], false)
_add_original_sheet(sf, "bubble", sheet_path, [bubble_cell], [1], false)
_add_original_sheet(sf, "victory", sheet_path, [21, 22], [1, 1], true)
```

`fly_hover` を `ANIMATIONS` と `FALLBACK` に追加し、原作以外では `fly`、`jump`、`idle` の順に代用する。

- [ ] **Step 4: 正規入口を実行してGREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 新しいセル契約テストを含め全件PASS、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 5: コミットする**

```powershell
git add -- src/display/sprite_factory.gd tests/unit/test_sprite_factory.gd
git commit -m "fix: 原作8キャラの全セル登録を正す"
```

### Task 2: 成立した打球動作を `hit_kind` へ必ず記録する

**Files:**
- Modify: `src/sim/sim_state.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_anim_select.gd`

**Interfaces:**
- Consumes: 既存 `Player.hit_kind: int`
- Produces: `SimState.HIT_KIND_ATTACK := 4` と、全地上・空中打球で更新済みの `hit_kind`

- [ ] **Step 1: 動作種別の失敗テストを書く**

`test_controls_original.gd` の既存 `test_next_air_hit_clears_previous_block_hit_kind` を、入力と期待値の表へ変更する。

```gdscript
for row in [
	[SimInput.IN_ACTION, SimState.HIT_KIND_TOSS],
	[SimInput.IN_ACTION | SimInput.IN_UP, SimState.HIT_KIND_ATTACK],
]:
	# hit_kind=BLOCKから_apply_hitし、row[1]へ更新されることを検査する
```

同じ実打球経路で次を検査する。

- 地上ニュートラル・後方トスは `HIT_KIND_TOSS`
- 敵陣へ返す地上打撃は `HIT_KIND_FORWARD`
- 空中ニュートラル・後方トスは `HIT_KIND_TOSS`
- 敵陣へ返す空中トスは `HIT_KIND_FORWARD`
- 上・下の空中アタックは `HIT_KIND_ATTACK`
- レシーブは `HIT_KIND_RECEIVE`
- ブロックは既存 `HIT_KIND_BLOCK`

- [ ] **Step 2: 正規入口を実行してREDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 空中トスが旧 `BLOCK` または `RECEIVE` を保持し、空中アタックが `ATTACK` にならず、前方地上打撃が `FORWARD` にならないFAIL。

- [ ] **Step 3: `hit_kind` を全成立経路で設定する**

`sim_state.gd` に追加する。

```gdscript
const HIT_KIND_ATTACK := 4
```

`hit_resolver.gd` の地上トス分岐は `returns_to_opponent` で `FORWARD` と `TOSS` を分ける。

```gdscript
p.hit_kind = SimStateScript.HIT_KIND_FORWARD if returns_to_opponent \
	else SimStateScript.HIT_KIND_TOSS
```

空中アタック分岐の先頭で `HIT_KIND_ATTACK` を設定する。空中トス分岐では、既存の `returns_to_opponent` 計算後に `FORWARD` または `TOSS` を設定する。ブロックとレシーブの既存代入は維持する。

- [ ] **Step 4: 正規入口を実行してGREENまたは固定ハッシュ停止を判定する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected action tests: PASS。

固定ハッシュが変わった場合: 実装を続けず、旧値、実測値、`hit_kind` 以外の状態差がないことを報告し、ユーザー承認を待つ。固定ハッシュが変わらなければ次へ進む。

- [ ] **Step 5: 承認後に必要なら固定ハッシュだけを更新し、再実行する**

固定ハッシュ更新はユーザー承認後のみ行う。期待値以外を緩和しない。

- [ ] **Step 6: コミットする**

```powershell
git add -- src/sim/sim_state.gd src/sim/hit_resolver.gd tests/unit/test_controls_original.gd tests/unit/test_anim_select.gd tests/unit/test_sync.gd
git commit -m "fix: 成立した打球種別を表示状態へ記録する"
```

### Task 3: 動作種別から正しいアニメとコマを選ぶ

**Files:**
- Modify: `src/display/anim_select.gd`
- Modify: `src/display/game_view.gd`
- Modify: `tests/unit/test_anim_select.gd`

**Interfaces:**
- Consumes: `Player.hit_kind`、`Player.hit_cooldown`、`cfg.hit_cooldown_ticks`
- Produces: `AnimSelect.attack_frame_for(p, total_ticks: int) -> int`、`AnimSelect.ground_swing_frame_for(p, total_ticks: int) -> int`

- [ ] **Step 1: アニメ名選択とコマ進行の失敗テストを書く**

`test_anim_select.gd` で地上・空中の組合せをリテラル表にする。

```gdscript
for row in [
	[1, SimState.HIT_KIND_RECEIVE, "ground_swing"],
	[1, SimState.HIT_KIND_TOSS, "toss"],
	[1, SimState.HIT_KIND_FORWARD, "toss_fwd"],
	[0, SimState.HIT_KIND_TOSS, "toss"],
	[0, SimState.HIT_KIND_FORWARD, "toss"],
	[0, SimState.HIT_KIND_ATTACK, "attack"],
	[0, SimState.HIT_KIND_BLOCK, "block"],
]:
	# on_ground、hit_kind、hit_cooldown=10を設定し、row[2]を検査する
```

`attack_frame_for` は、硬直中の経過tick 0〜9に対して `[0,0,1,1,2,2,1,1,2,2]` を期待する。`ground_swing_frame_for` は `[0,0,1,1,2,2,3,3,3,3]` を期待する。

- [ ] **Step 2: 正規入口を実行してREDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 地上トスと空中トスのアニメ名、未定義のコマ選択関数でFAIL。

- [ ] **Step 3: アニメ選択を動作種別へ合わせる**

`anim_select.gd` の打撃中分岐を次の契約へ揃える。

```gdscript
if p.hit_cooldown > 0 and p.hit_kind == SimStateScript.HIT_KIND_BLOCK:
	return "block"
if p.on_ground == 0:
	if p.hit_cooldown > 0:
		if p.hit_kind == SimStateScript.HIT_KIND_ATTACK:
			return "attack"
		return "toss"
	return "jump"
if p.hit_cooldown > 0:
	match p.hit_kind:
		SimStateScript.HIT_KIND_TOSS:
			return "toss"
		SimStateScript.HIT_KIND_FORWARD:
			return "toss_fwd"
		_:
			return "ground_swing"
```

コマ関数は `age = maxi(total_ticks - p.hit_cooldown, 0)` から導出する。アタックは `age < 6` なら `age / 2`、以後 `1 + ((age - 6) / 2) % 2`。地上スイングは `clampi(age / 2, 0, 3)`。

- [ ] **Step 4: `GameView` を原作8キャラの決定論的コマ選択へ接続する**

`game_view.gd` の `dive` と同じ `animation` 設定、`pause()`、`frame` 代入方式を使う。`SpriteFactory.is_original_char(cid)` かつ `anim` が `attack`、`ground_swing`、`toss_fwd` の場合だけ新関数を使い、既存キャラの時間再生は変えない。

炎上の直接フレーム選択は原作8キャラだけ `state.tick / 3`、それ以外は現行 `state.tick / 4` とする。

- [ ] **Step 5: 正規入口を実行してGREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件PASS、`SCRIPT ERROR summary: 0 occurrence(s)`、固定ハッシュはTask 2承認値から不変。

- [ ] **Step 6: コミットする**

```powershell
git add -- src/display/anim_select.gd src/display/game_view.gd tests/unit/test_anim_select.gd
git commit -m "fix: 原作アクションを正しいスプライトへ接続する"
```

### Task 4: Claude Codeレビューと完了検証を通す

**Files:**
- Modify if needed: Task 1〜3で変更したファイル
- Modify: `docs/tasks/57.md`
- Test: `run_tests.ps1`

**Interfaces:**
- Consumes: Task 1〜3の完成差分
- Produces: レビュー済み実装、検証結果、原作スプライト対応の完了記録

- [ ] **Step 1: Claude Codeへ差分レビューを依頼する**

次を明示してレビューさせる。

```text
承認設計147行・SHA-256 6cab4115dc0dde490259fba59f917d0144b7f498228165d7407767cd267c9428 と差分を照合する。
全24セル、既存6動作の接続、stale BLOCK、PIYO bubble、原作だけの再生速度、
固定ハッシュ以外の物理不変、テストの空振りを確認する。git変更は禁止。
```

- [ ] **Step 2: 指摘を証拠へ照合し、必要なら失敗テストから修正する**

指摘を無条件採用せず、設計、セル表、実コードに一致するものだけを採用する。修正が必要なら該当テストを先に赤くし、最小修正後に緑へ戻す。

- [ ] **Step 3: 正規入口で最終全件検証する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件PASS、`SCRIPT ERROR summary: 0 occurrence(s)`、性能門PASS。

- [ ] **Step 4: 差分と契約を監査する**

Run:

```powershell
git diff --check
git diff --stat main...HEAD
git status --short --branch
```

全24セルの各動作について、画像切り出し、順番、保持tick、アニメ名、表示選択口、原作8キャラ全員のテストが存在することをチェックする。未実装の技や状態へセル調査、素材登録、再生処理を残していないことを確認する。

- [ ] **Step 5: タスク記録を更新してコミットする**

`docs/tasks/57.md` に実装コミット、承認設計の147行とSHA-256、全件テスト結果、Claude Codeレビュー結果、未実装なのは感電・泡・飛行・特殊落下のゲーム発火条件だけであることを記録する。

```powershell
git add -- docs/tasks/57.md
git commit -m "docs: 原作スプライト動作対応の完了を記録する"
```

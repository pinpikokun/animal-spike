# Three-Tier Receive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通常、ジャスト、ギリギリの三段階レシーブを、失敗可能な横っ飛びとともに実装する。

**Architecture:** 既存の決定論的simを維持し、設定とロールバック状態を先に拡張する。球の着地予測は本番の `BallPhysics._step_ball` を小さな一時状態へ適用し、横っ飛びは `Simulation` が開始と受付時間を、`PlayerMovement` が専用移動を、`HitResolver` が実接触と打球結果を担当する。

**Tech Stack:** Godot 4.6、GDScript、整数固定小数点、PowerShellテスト入口 `run_tests.ps1`

## Global Constraints

- 承認済み設計書は388行、SHA-256 `67FEDF1599AEEB3A5EA310E1E55231D64F42EDBBFA3A43518EF7AA939329DC54`。
- 基準縦速度はギリギリ520px/s、通常600px/s、ジャスト680px/s。
- 横っ飛びは追加発動幅32px、水平360px/s、上向き280px/s、接触受付14tick。
- 発動距離の内端は開区間とし、通常リーチちょうどまでは従来の即時打球へ譲る。
- 横っ飛びはACTION押下エッジで開始し、下・左右入力を要求しない。
- 開始tickには打球せず、次の物理tickから通常レシーブ楕円へ実接触した場合だけ成功する。
- 成否に新しい乱数を使わない。失敗時も着地まで操作不能とする。
- 通常レシーブは散りと入射慣性を残す。ジャストは散り0、縦入射慣性0とする。
- 地上トスとレシーブのガード・ドライブ差は変更しない。これは `docs/tasks/113.md` で次に扱う。
- CPU専用判断、CPU難易度差、新しいパッシブ能力差は追加しない。
- simは整数演算だけを使い、追加状態を直列化とハッシュへ含める。
- 各本番変更は、先に対応テストを追加して意図した失敗を確認してから実装する。

---

### Task 1: 設定値とロールバック状態

**Files:**
- Modify: `data/rules.json`
- Modify: `src/sim/sim_config.gd`
- Modify: `src/sim/sim_state.gd`
- Modify: `tests/unit/test_config.gd`
- Modify: `tests/unit/test_state.gd`
- Modify: `tests/unit/test_sync.gd`

**Interfaces:**
- Produces: `cfg.normal_receive_up`, `cfg.just_receive_up`, `cfg.dive_receive_up`, `cfg.dive_receive_extra_reach`, `cfg.dive_receive_speed`, `cfg.dive_receive_hop`, `cfg.dive_receive_contact_ticks`
- Produces: `Player.dive`, `Player.dive_contact_ticks`, `Player.dive_age_ticks`, `Player.action_latch`

- [ ] **Step 1: 設定と状態の失敗テストを書く**

`test_config.gd` でJSONの七値と固定小数点変換をリテラル比較する。`test_state.gd` で追加3欄を設定し、保存復元とハッシュ差、および直列化長262を検査する。

```gdscript
check_eq(cfg.normal_receive_up, FP.from_int(600) / cfg.tick_rate, "通常600")
check_eq(cfg.just_receive_up, FP.from_int(680) / cfg.tick_rate, "ジャスト680")
check_eq(cfg.dive_receive_up, FP.from_int(520) / cfg.tick_rate, "ギリギリ520")
check_eq(cfg.dive_receive_extra_reach, FP.from_int(32), "発動幅32")
check_eq(cfg.dive_receive_speed, FP.from_int(360) / cfg.tick_rate, "飛込速度360")
check_eq(cfg.dive_receive_hop, FP.from_int(280) / cfg.tick_rate, "飛込上昇280")
check_eq(cfg.dive_receive_contact_ticks, 14, "受付14tick")
check_eq(SimState.new().to_int_array().size(), 262, "追加3欄x4人")
```

- [ ] **Step 2: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 新設定プロパティまたは直列化長の検査が失敗する。

- [ ] **Step 3: 最小実装を入れる**

七値を読み込み、すべて正数かつ `dive_receive_up <= normal_receive_up <= just_receive_up` を検証する。`Player` へ `dive_contact_ticks`、`dive_age_ticks`、`action_latch` を追加し、`to_int_array` と `load_int_array` の同じ位置へ並べる。`dive` の意味は残り時間から方向 `-1/0/1` へ変更する。追加されたゼロ値もハッシュ入力になるため、60秒同期goldenを実測した新しい値へ更新する。

- [ ] **Step 4: GREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 追加検査を含む全件成功。

- [ ] **Step 5: コミットする**

```powershell
git add data/rules.json src/sim/sim_config.gd src/sim/sim_state.gd tests/unit/test_config.gd tests/unit/test_state.gd tests/unit/test_sync.gd
git commit -m "feat: レシーブ三段階の設定と状態を追加する"
```

### Task 2: 本番物理と一致する着地予測

**Files:**
- Modify: `src/sim/ball_physics.gd`
- Create: `tests/unit/test_dive_receive.gd`

**Interfaces:**
- Produces: `BallPhysics.predict_first_floor_x(s, cfg, max_ticks: int = 240) -> int`
- Contract: 最初の床到達x、予測不能は`-1`。入力状態、乱数、イベントを変更しない。

- [ ] **Step 1: 予測器の失敗テストを書く**

通常放物線、左右壁反射、パワー球の壁減衰、ネット側面、ネット上端、240tick無効をそれぞれ固定fixtureにする。本番状態の複製を `_step_ball` で床まで進めた結果と、予測器のリテラル結果を比較し、元状態の配列が不変であることも検査する。

```gdscript
var before: Array[int] = s.to_int_array()
var predicted: int = BallPhysics.predict_first_floor_x(s, cfg)
check_eq(predicted, FP.from_int(known_x_px), "最初の床到達x")
check_eq(s.to_int_array(), before, "予測は本番状態を変更しない")
```

- [ ] **Step 2: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: `predict_first_floor_x` 未定義で失敗する。

- [ ] **Step 3: 最小実装を入れる**

`BallPhysics` 内へ `_BallProbe` を定義し、`_step_ball` が読む球関連intだけを現在状態からコピーする。最大240回 `_step_ball(probe, cfg)` を呼び、`ball_y >= floor_y-ball_radius && ball_vy > 0` でxを返す。到達しなければ`-1`を返す。

- [ ] **Step 4: GREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 予測テストと既存球物理テストが成功する。

- [ ] **Step 5: コミットする**

```powershell
git add src/sim/ball_physics.gd tests/unit/test_dive_receive.gd
git commit -m "feat: 横っ飛び用の着地予測を追加する"
```

### Task 3: ACTIONエッジと横っ飛び開始・移動

**Files:**
- Modify: `src/sim/simulation.gd`
- Modify: `src/sim/player_movement.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `tests/unit/test_dive_receive.gd`
- Modify: `tests/unit/test_stateful_rng_part_a.gd`
- Modify: `tests/unit/test_refactor_characterization.gd`

**Interfaces:**
- Produces: `Simulation._consume_action_edges(state, inputs) -> Array[bool]`
- Produces: `Simulation._try_start_dive_receives(state, inputs, action_edges, cfg) -> void`
- Produces: `Simulation._advance_dive_contact_windows(state) -> void`
- Consumes: `BallPhysics.predict_first_floor_x`

- [ ] **Step 1: エッジと開始境界の失敗テストを書く**

通常リーチ内は即時打球を優先、予測距離`reach+1`と`reach+32`は開始、`reach+33`は不開始、左右鏡像、逆方向入力でも球側、同チーム球と無効予測では不開始を検査する。保持入力、ヒットストップ、スロー停止、行動不能中の押下を着地後へ持ち越さないことも検査する。

```gdscript
Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_LEFT, 0, 0, 0], cfg)
check_eq(p.dive, 1, "逆入力でも予測着地点の右へ飛ぶ")
check_eq(p.dive_contact_ticks, 14, "開始tickは14のまま")
check_eq(p.dive_age_ticks, 0, "開始tickは移動しない")
```

- [ ] **Step 2: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 横っ飛び状態が開始せず失敗する。

- [ ] **Step 3: ACTIONエッジを実装する**

`Simulation.step` の早期returnより前で、直列化済みの前tick `action_latch` と現在入力から押下エッジを作り、その後ラッチを現在レベルへ更新する。ロールバックは保存されたラッチから同じエッジを再構築する。物理を進めないtick、行動不能中、発動条件外で生じたエッジは予約せず破棄し、保持入力で後から発動させない。ラリー初期化ではラッチを消さない。

- [ ] **Step 4: 横っ飛び開始を実装する**

通常ヒット解決が `NO_HIT` の場合だけ、ラリー中、接地、硬直なし、相手球、予測着地点が自陣、距離が `(receive_reach, receive_reach+32]` の選手を開始する。内端を除外するのは通常リーチ内の即時打球を奪わないためで、32は `dive_receive_extra_reach` 設定を使う。`dive=sign(predicted_x-p.x)`、接触残り14、経過0、`vx` と `vy` を設定し、`receive_stance=0`、`on_ground=0` とする。同じtickに複数選手が条件を満たした場合はindex昇順ですべて開始できる。開始自体は打球ではなく、後続接触では既存の一打球制約が働く。旧 `_classify_intent` の外周地上トス用 `dive_dir` と、打球後に `p.dive` を立てる演出処理は撤去し、特徴固定テストを新しい分類へ更新する。

- [ ] **Step 5: 専用移動を実装する**

`PlayerMovement._step_player` は被弾・スタン処理の後、`dive != 0` なら通常入力、ジャンプ、固有技を処理せず専用移動する。受付中は水平速度を維持して重力を加え、受付後は水平0で落下する。`Simulation` は既存横っ飛びだけを各物理tickの解決後に、残りが正の場合だけ1減らし、新規開始tickは減らさない。14回目の後で0となり水平を止める。既存着地条件 `p.y >= cfg.floor_y` で床へクランプしたtickに `dive`、接触残り、経過を0へ戻し、次tickから通常操作へ戻す。

- [ ] **Step 6: GREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 開始境界、入力消費、専用移動が成功し、同期テストも成功する。

- [ ] **Step 7: コミットする**

```powershell
git add src/sim/simulation.gd src/sim/player_movement.gd src/sim/hit_resolver.gd tests/unit/test_dive_receive.gd tests/unit/test_stateful_rng_part_a.gd tests/unit/test_refactor_characterization.gd
git commit -m "feat: 予測式の横っ飛び状態を追加する"
```

### Task 4: 実接触と三段階の打球品質

**Files:**
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/simulation.gd`
- Modify: `tests/unit/test_dive_receive.gd`
- Modify: `tests/unit/test_hit.gd`
- Modify: `tests/unit/test_drive_burnout.gd`

**Interfaces:**
- Modify: `HitResolver._apply_hit(..., force_dive_receive: bool = false) -> void`
- Contract: 活動中の横っ飛びはACTION保持なしで通常楕円へ実接触し、最初の一回だけ通常レシーブ系結果を出す。

- [ ] **Step 1: 三段階速度の失敗テストを書く**

静止球でギリギリ520、通常600、ジャスト680の基準縦速度を直接検査する。通常は`aitick`で散りが変わり、ジャストは変わらず、下降球でもジャストの縦速度が変わらないことを検査する。

- [ ] **Step 2: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 通常とジャストが既存520を使うため失敗する。

- [ ] **Step 3: 三段階の打球式を実装する**

通常レシーブは600と既存散り・操舵・入射慣性、ジャストは680と散り0・縦慣性0、強制横っ飛びは520と通常散り・操舵・入射慣性を使う。ジャストの既存防御報酬、通常のガード・ドライブ処理は変えない。

- [ ] **Step 4: 横っ飛び接触の失敗テストを書く**

開始の次tickから14回だけ判定する、途中で楕円へ入れば成功、最後の1回でも成功、15回目は失敗、成功後は二度打球しない、ACTIONを離しても成功、ジャストにならない、同じ被弾処理を受けることを検査する。

```gdscript
check_eq(p.dive_contact_ticks, 1, "最後の受付")
Simulation.step(s, [0, 0, 0, 0], cfg)
check_eq(s.touches, 1, "14回目の実接触は成功")
check_eq(p.dive_contact_ticks, 0, "成功後は受付終了")
```

- [ ] **Step 5: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 活動中の横っ飛びが打球候補にならず失敗する。

- [ ] **Step 6: 実接触と受付減算を実装する**

`_resolve_hit` は `dive != 0 && dive_contact_ticks > 0` の選手をACTIONなしでも候補にし、通常操作の候補と同じ集合で既存の最近距離優先を使い、一人だけ選ぶ。同距離は既存どおり球側チームを優先し、それでも同じなら低いindexを維持する。強制横っ飛びとして `_apply_hit` し、`receive_stance=0` と強制フラグによりジャスト判定を必ず無効化する。成功時は接触残りと水平速度を0にし、解決後の減算は `contact_ticks > 0` の未成功者だけへ適用する。パワー球の被弾は接触成功による通常レシーブ結果の中で決まり、flinch、stun、burnへ移った場合はその結果を適用した後に横っ飛び状態を解除して被弾状態を優先する。

- [ ] **Step 7: GREENを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 三段階、14回境界、被弾回帰、1tick一打球がすべて成功する。

- [ ] **Step 8: コミットする**

```powershell
git add src/sim/hit_resolver.gd src/sim/simulation.gd tests/unit/test_dive_receive.gd tests/unit/test_hit.gd tests/unit/test_drive_burnout.gd
git commit -m "feat: 三段階レシーブと実接触を実装する"
```

### Task 5: 横っ飛び表示と回帰固定

**Files:**
- Modify: `src/display/game_view.gd`
- Modify: `src/display/anim_select.gd`
- Modify: `tests/unit/test_anim_select.gd`

**Interfaces:**
- Consumes: `Player.dive` と `Player.dive_age_ticks`
- Produces: `AnimSelect.dive_frame_for(p) -> int`
- Contract: セル11、10、7、0をsim経過tickから決定し、ロールバック後も同じフレームを選ぶ。

- [ ] **Step 1: 表示状態の失敗テストを書く**

`dive != 0` が既存どおり他の通常動作より優先され、被弾状態だけが横っ飛びより優先されることを検査する。`dive_age_ticks` が0、2、4、6以上のとき表示フレームが0、1、2、3となることを検査する。

- [ ] **Step 2: REDを確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: `dive_frame_for` 未定義で失敗する。

- [ ] **Step 3: 表示を状態駆動へ変更する**

`AnimSelect.dive_frame_for` は `dive_age_ticks / 2` を0..3へ丸める。`game_view.gd` は横っ飛びアニメを一時停止してこのフレームを固定し、`dive` の符号で傾き方向を決める。Task 3と4の中間コミットでも既存 `anim_for` は `dive != 0` を読んで従来の横っ飛びアニメを再生するため、表示が消える期間は作らない。

- [ ] **Step 4: GREENと性能を確認する**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全件成功、`SCRIPT ERROR summary: 0 occurrence(s)`、性能ゲート成功。

- [ ] **Step 5: コミットする**

```powershell
git add src/display/game_view.gd src/display/anim_select.gd tests/unit/test_anim_select.gd
git commit -m "feat: 横っ飛び表示をsim状態へ同期する"
```

### Task 6: Claude Code査読と試遊引き渡し

**Files:**
- Modify only if review finds an in-scope defect.

**Interfaces:**
- Produces: 実装差分、全件検証結果、試遊項目、未調整値の報告。

- [ ] **Step 1: Claude Codeへ仕様適合レビューを依頼する**

設計書、実装計画、`git diff`、関連テスト結果を渡し、ゲーム性ではなく仕様逸脱、状態遷移、off-by-one、ロールバック、通常操作の回帰に絞って査読させる。

- [ ] **Step 2: 指摘をコードで検証する**

正しい指摘は再現する失敗テストから修正し、誤った指摘はコード行とテスト結果を根拠に退ける。

- [ ] **Step 3: 最終全件検証を行う**

Run: `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1`

Expected: 全テスト成功、失敗0、SCRIPT ERROR 0、性能ゲート成功。

- [ ] **Step 4: 試遊項目を報告する**

ジャストの高さ、通常の高さと散り、横っ飛びの適正入力、早すぎ・遅すぎの空振り、低い救済球、通常トスを奪わないことをユーザーへ渡す。試遊完了後は `docs/tasks/113.md` を次タスクとして開始する。

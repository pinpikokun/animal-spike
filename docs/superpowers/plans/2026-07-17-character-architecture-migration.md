# キャラ拡張アーキテクチャ移行 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仕様書 `docs/superpowers/specs/2026-07-17-character-architecture-design.md` の7段階移行を実装し、キャラ追加が「キャラ定義1つの追加」で完結する構造にする。

**Architecture:** 物理コア1つ+キャラ定義(chars.gd)の4層構造(共通動作/性能シート/固有技ビット/パッシブ)。char_idをsim状態に持ち、slot=キャラの暗黙対応を全廃する。帽子はエンティティ枠(固定8スロット)へ移植。

**Tech Stack:** Godot 4.6 / GDScript / 決定論int simレイヤー / run_tests.ps1 (pre-commitフックで全テスト実行)

## Global Constraints

- sim層は64bit int演算のみ(float禁止、test_no_float_in_simが番人)
- 全sim状態はto_int_array/load_int_arrayに登録(test_state_coverageが強制)
- 乱数はstateless keyed hash(sim_cpu方式)のみ。Math.random系禁止
- 各タスク完了時に全テスト緑(意図的挙動変更時のみゴールデンハッシュを更新し、コミットメッセージに明記)
- sim_cpu.gdはsimulation.gdをpreload不可(循環)。chars.gdは葉(何もpreloadしない)として両方から参照可
- 復帰地点: git tag `pre-char-arch`

---

### Task 1: chars.gd(キャラ定義)+ char_id導入

**Files:**
- Create: `src/sim/chars.gd`
- Modify: `src/sim/sim_state.gd`(Player.char_id追加+直列化)
- Modify: `src/sim/simulation.gd`(reset_matchでROSTERからchar_id設定、HAS_HAT_STARTをchars参照に)
- Test: `tests/unit/test_chars.gd`(新規)、`tests/unit/test_state.gd`(直列化長)、`tests/unit/test_sync.gd`(ゴールデン)

**Interfaces:**
- Produces: `Chars.CHAR_PANDA/CHAR_MARIO/CHAR_FOX/CHAR_FROG/CHAR_DEBUG`、`Chars.CA_HAT/CA_HIP/CA_CLING/CA_DASH`、`Chars.ROSTER: Array[int]`、`Chars.has_ability(char_id:int, bit:int)->bool`、`Chars.stat(char_id:int, key:String)->int`(未定義キーは100)

- [ ] chars.gdを作成: CHAR定数、CA_ビット、DEFS辞書(abilities int + stats辞書、全キャラstats={}=全項目100)、ROSTER=[0,1,2,3]、CHAR_DEBUG=15(全能力持ち、テスト専用)
- [ ] test_chars.gd: has_ability(マリオ=帽子/ヒップ/壁貼り、パンダ=無し)、stat未定義キー=100、ROSTER長=4
- [ ] sim_state.gd: Player.char_id追加+to_int_array/load_int_array両方に追加
- [ ] simulation.gd: reset_matchで`p.char_id = Chars.ROSTER[i]`、has_hat初期値=`1 if Chars.has_ability(...CA_HAT) else 0`、HAS_HAT_START定数削除
- [ ] test_state.gdの直列化長、test_sync.gdゴールデンハッシュ更新(char_id追加=形式変更のみ、挙動不変をSyncTestで確認)
- [ ] 全テスト実行→緑→コミット `feat: char_id導入+キャラ定義chars.gd(挙動不変)`

### Task 2: 固有技のビットゲート化(帽子/ヒップ/壁張り付き)

**Files:**
- Modify: `src/sim/simulation.gd`(_update_hat/_step_playerのhip/clingゲート)
- Modify: `src/sim/sim_cpu.gd`(_decide_hatにcan-gate追加)
- Test: `tests/unit/test_hip_cling.gd`(パンダ不可テスト追加)、`tests/unit/test_sync.gd`

**Interfaces:**
- Consumes: `Chars.has_ability`

- [ ] ヒップ: `p.has_hat == 1`要求を`Chars.has_ability(p.char_id, Chars.CA_HIP)`に置換(帽子相乗り廃止)
- [ ] 壁張り付き: `Chars.has_ability(p.char_id, Chars.CA_CLING)`ゲート追加(現状の全キャラ可はバグとして修正)
- [ ] 帽子投げ: _update_hatに`CA_HAT`ゲート追加(has_hat状態と二重防御)
- [ ] sim_cpu._decide_hat冒頭に`if not Chars.has_ability(p.char_id, Chars.CA_HAT): return 0`(can AND wants)
- [ ] テスト: パンダ(char_id=0)がhip/cling不可、CHAR_DEBUGは全部可
- [ ] 壁張り付きの固有技化は仕様変更→ゴールデンハッシュ更新、コミット `feat: 固有技ビットゲート化(ヒップ独立/壁貼りキャラ限定)`

### Task 3: 技スロット予約+IN_ABILITY1改名

**Files:**
- Modify: `src/sim/sim_input.gd`、`src/sim/simulation.gd`、`src/sim/sim_cpu.gd`、`src/display/input_poll.gd`、関連テスト

- [ ] sim_input.gd: `IN_ABILITY1 := 128`(旧IN_HAT_THROW)、`IN_ABILITY2 := 256`、`IN_ABILITY3 := 512`、`IN_ABILITY4 := 1024`。IN_HAT_THROWは削除し全参照を改名
- [ ] grepでIN_HAT_THROW全参照を置換(simulation/sim_cpu/input_poll/tests)
- [ ] 挙動不変(ビット値同じ)→ゴールデン不変を確認、コミット `refactor: IN_ABILITY1改名+技スロット4予約`

### Task 4: 表示層のchar_id辞書化+代役ルール

**Files:**
- Modify: `src/display/sprite_factory.gd`(char_id→builder辞書+代役ルール関数)
- Modify: `src/display/game_view.gd`(is_mario/i==0ハードコード排除、char_id参照)
- Modify: `src/display/score_ui.gd`(顔テクスチャ/regionをchar_id辞書化)
- Test: `tests/unit/test_display_parse.gd`(パース確認は既存)、目視確認

**Interfaces:**
- Produces: `SpriteFactory.build_for(char_id:int)->SpriteFrames`、`SpriteFactory.ensure_fallbacks(sf:SpriteFrames)->void`(標準アクション+固有技アクションの代役連鎖: attack→jump→run→idle等。不足はpush_warning)

- [ ] sprite_factory: `build_for(char_id)`辞書分岐+`ensure_fallbacks`(FALLBACK連鎖表)。既存build_xxxの明示流用行を代役ルールに置換できるものは置換
- [ ] game_view: スプライト生成を`build_for(state.players[i].char_id)`に。帽子スプライト差し替え/勝利演出/オフセットの`is_mario`/`i != 0`判定を`char_id == Chars.CHAR_MARIO`等に置換
- [ ] score_ui: `FACE_TEX/FACE_REGION`をchar_idキーの辞書に
- [ ] 全テスト+ゲーム起動目視(パンダ/マリオ/キツネ/カエルが従来どおり)、コミット `refactor: 表示層char_id辞書化+代役ルール`

### Task 5: エンティティ枠(固定8スロット)+帽子移植

**Files:**
- Modify: `src/sim/sim_state.gd`(cap_*7欄→entities 8スロット×8欄)
- Modify: `src/sim/simulation.gd`(_update_hatをエンティティ操作に)
- Modify: `src/sim/sim_cpu.gd`(cap_phase参照をエンティティ参照に)
- Modify: `src/display/game_view.gd`(帽子表示)
- Test: `tests/unit/test_entities.gd`(新規: スポーン/満杯失敗/直列化)、`test_hat.gd`/`test_cpu_hat.gd`更新、ゴールデン更新

**Interfaces:**
- Produces: sim_state: `ENT_SLOTS := 8`、Entクラス(kind/phase/x/y/vx/vy/owner/timer 全int)、`entities: Array[Ent]`。simulation: `KIND_NONE := 0`、`KIND_CAP := 1`、`static func ent_spawn(s, kind:int)->int`(先頭空きslot、満杯-1)、`static func ent_find(s, kind:int)->int`

- [ ] sim_stateにEntクラス+entities[8]追加、cap_*削除、直列化を全欄常時直列化で書き換え
- [ ] simulation: ent_spawn/ent_find実装、_update_hatの帽子ロジックをKIND_CAPエンティティで書き直し(phase 1飛行/2滞在/3帰還は踏襲)
- [ ] sim_cpu: `s.cap_phase`参照を`Simulation定数ミラー`ではなくent_find相当のインライン走査に(循環回避のためsim_cpu内にKIND_CAP=1ミラー+番人テスト)
- [ ] game_view: `state.cap_*`参照をエンティティ走査に
- [ ] test_entities.gd: 満杯時spawn失敗、直列化ラウンドトリップ、ハッシュ感度
- [ ] test_hat/test_cpu_hat/test_state(直列化長)更新、ゴールデン再生成は本タスク1コミットに束ねて1回
- [ ] コミット `feat: エンティティ枠(8スロット)導入+帽子移植`

### Task 6: ステータス%適用(全キャラ100=挙動不変)

**Files:**
- Modify: `src/sim/simulation.gd`(移動/ジャンプ/重さ/滑走/威力/ジャスト窓/報酬/受け流し/ばらつき)
- Modify: `src/sim/chars.gd`(statキー正式一覧をコメントで)
- Test: `tests/unit/test_char_stats.gd`(新規: CHAR_DEBUG亜種で数値が効くこと+100で不変なこと)

**Interfaces:**
- Produces: statキー: `"speed" "jump" "weight" "guard_max" "slide" "atk" "just_reward" "just_window" "absorb"(受け流し=慣性の逆数側) "sc_toss" "sc_recv" "sc_atk" "sc_blk"`(ばらつき%は既定0)。`Chars.scatter(char_id, key)->int`(既定0)
- ばらつき実装: `Simulation._scatter_roll(s, idx, salt)->int`(sim_cpuと同じkeyed hash: last_hit_tick+actor+salt、-100..100を返す)

- [ ] _step_player: move_speed/jump_speed/gravity(重さ)/BRAKE滑走にstat%を乗算
- [ ] reset_match: guard_maxにstat適用
- [ ] _apply_hit: スパイク威力にatk%、sweet窓にjust_window%、パワー倍率にjust_reward%、慣性inertiaにabsorb%(100=現行)
- [ ] ばらつき: 地上トス/レシーブ/アタック/ブロック反射の速度に`± vx*sc%*roll/100/100`を加算。ジャスト成立時(sweet)はばらつき0
- [ ] test_char_stats.gd: 全キャラ100/0で従来値と完全一致(ゴールデン不変)、CHAR_DEBUG(速度130等)で数値が効く
- [ ] コミット `feat: キャラ性能シート適用(全員100=挙動不変)`

### Task 7: 入力履歴(ダブルタップ検知)+ダッシュ

**Files:**
- Modify: `src/sim/sim_state.gd`(Player.tap_dir/tap_tick追加)
- Modify: `src/sim/simulation.gd`(ダブルタップ検知+CA_DASH)
- Test: `tests/unit/test_dash.gd`(新規)

**Interfaces:**
- Produces: `Chars.CA_DASH := 8`。ダブルタップ窓 `DASH_TAP_WINDOW := 12`(tick)、ダッシュ速度=move_speed*175/100、持続 `DASH_TICKS := 14`(Player.dash残tick、直列化)

- [ ] sim_state: Player.tap_dir/tap_tick/dash追加+直列化(ゴールデン更新は本タスク1回)
- [ ] simulation._step_player: 方向キーの押し始めエッジを検知し、同方向2回が窓内ならdash発動(CA_DASH持ちのみ)。dash中はvx=ダッシュ速度
- [ ] test_dash.gd: CHAR_DEBUGで発動、窓外/逆方向/CA_DASH無しで不発、ダッシュジャンプで空中に横速度が乗る
- [ ] コミット `feat: 入力履歴ダブルタップ+ダッシュ(CA_DASH、現ロスターは未所持)`

---

## 検証方法

- 各タスク末に全テスト実行(pre-commitフックが強制)
- 挙動不変タスク(1,3,4,6)はゴールデンハッシュ不変で証明(1はフォーマット変更のみ許容)
- 最後にゲーム起動して目視: 4キャラ表示/帽子投げ/ヒップ/壁貼り(マリオのみ)/CPU帽子AI

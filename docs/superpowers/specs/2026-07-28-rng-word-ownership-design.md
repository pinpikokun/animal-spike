# #106 乱数2ワード所有権 設計書

## 1. 目的

原作 `VOLLEY BALL 2on2` と同じく、乱数2ワード `rng` / `aitick` をプロセスを通して継続させる。
ローカル再戦で前試合の終了時点を回収し、次試合の開始値として渡す。

この設計で新しく固定する挙動は次の1点だけである。

- ローカル再戦は、破棄する `GameView.state` の `rng` / `aitick` を次のローカル試合へ継承する。

## 2. 範囲

### 2.1 対象

- `Simulation.reset_match()` の契約を、1ワード `seed` から必須の2ワードへ変更する。
- 全57直接呼び出しを6引数へ変更する。
- `root.gd` にローカル試合間だけ2ワードを保持する受け渡し口を置く。
- `GameView` が2ワードを必須入力として受け取る。
- ネット初戦では既存の合意済み1ワードを2ワードへ展開して適用する。
- `test_display_scripts_parse` の古い `root.gd` 除外を撤去し、表示層の主たるパース保護へ戻す。
- 既存テスト2本を新契約へ改訂し、ローカル再戦の結合テストを1本追加する。

### 2.2 対象外

- ネット再戦の追加。
- `boot_seed_handshake.gd` のメッセージ、状態遷移、ハッシュ契約の変更。
- リプレイ形式の決定または実装。
- デバッグビューを実ゲームの乱数系列へ接続すること。
- 乱数式、ゲームプレイ、物理、CPU判断、固定期待値の再採取。

## 3. 根拠の区分

### 3.1 原作由来

原作のプロセス起動時初期化は次の1回だけである。

```text
9c00  mov ah,0x2c / int 0x21
9c04  mov [RND], cx
9c0b  mov [aitick], ax
```

- `RND` はアドレス `0x1108`。
- `aitick` はアドレス `0x0EB8`。
- 初期値は `(時 << 8) | 分`。
- `RND` と `aitick` は同じ初期値から始まる。
- 試合、セット、ラリーの開始時に再初期化しない。

したがって原作では2ワードは試合単位ではなくプロセス単位の系列である。

### 3.2 現行コード由来

- `src/sim/simulation.gd:438-481` の `reset_match()` は、現状1ワード `seed` を
  `src/sim/simulation.gd:478-480` で正規化し、`rng` と `aitick` の双方へ代入する。
- 同関数は最後に `reset_rally()` を呼ぶ。
- `src/sim/simulation.gd:386-389` の `reset_rally()` は
  `SimRng.advance_role_roll()` を2回呼び、`rng` だけを2回進める。
- `src/sim/sim_rng.gd:18-19` の式は
  `(rng * 2 + 1) & WORD_MASK` である。
- `src/display/root.gd:58-60,91-102` にはローカル再戦導線がある。
- `src/display/game_view.gd:97-110` は新しいローカル `SimState` を作り、
  `_ready()` 内で `reset_match()` を呼ぶ。
- `src/sim/sim_state.gd:71-72,144-146,233-238,325-329` により、
  `rng` / `aitick` はロールバック保存、復元、state hash の対象である。
- `tests/unit/test_display_parse.gd:15-18` は現状 `root.gd` を除外しているが、
  `root.gd` のloadと `root.tscn` のinstantiateはヘッドレスのテスト用SceneTreeで成功する。
  除外理由の「SyncManagerのautoloadが無いためコンパイル不能」は実測で否定されている。
- #105 のコミット `0561153` で、起動時計種は `root.gd` からローカルとネットへ配線済みである。

### 3.3 本作で決定した事項

- 所有とは「値を決め、次の試合へ供給する責任」であり、代入処理を外すことではない。
- `reset_match()` は必須引数の2ワードを個別に正規化し、`reset_rally()` より先に代入する。
- 試合中の正本は `SimState` だけである。
- `root.gd` はローカル試合間の短い受け渡し期間だけ2ワードを保持する。
- ネット初戦の1ワード合意は維持し、適用時に同じ値を2回渡す。
- デバッグビューは固定値 `0, 0` の独立系列を維持する。

## 4. 必須契約

### CONTRACT-106-001: `reset_match()` の署名

署名を次へ変更する。

```gdscript
static func reset_match(
		s,
		cfg,
		serving_team: int,
		roster: Array,
		rng_word: int,
		aitick_word: int
	) -> void:
```

- `roster`、`rng_word`、`aitick_word` に既定値を置かない。
- 引数順は既存4引数の後ろへ2ワードを追加する順で固定する。
- `roster` を2ワードより後ろへ移動しない。
- `preserve` フラグや別オーバーロードを追加しない。
- 呼び出し前に `SimState` へ暗黙入力を書き込む方式にしない。

必須化の目的は、供給漏れをパース時に検出することである。値 `0` は正当な乱数ワードなので、
暗黙の初期値を実行時に判別することはできない。

### CONTRACT-106-002: 2ワードの代入順

`src/sim/simulation.gd` は次の順序を守る。

```gdscript
s.rng = SimRng.normalize_word(rng_word)
s.aitick = SimRng.normalize_word(aitick_word)
reset_rally(s, cfg, serving_team)
```

- 2ワードは別々に `SimRng.normalize_word()` へ渡す。
- 片方を正規化して他方へ複製しない。
- `reset_rally()` より後に代入しない。
- `reset_rally()` の2回消費を省略、追加、並べ替えしない。
- `aitick` は開始ラリーの役割抽選では変化しない。

### CONTRACT-106-003: 値の供給元

| 経路 | `rng_word` | `aitick_word` |
|---|---:|---:|
| ローカル初戦 | `boot_seed` | `boot_seed` |
| ローカル再戦 | 破棄する `GameView.state.rng` | 破棄する `GameView.state.aitick` |
| ネット合意適用 | `agreed_seed` | `agreed_seed` |
| デバッグビュー | `0` | `0` |
| 旧3・4引数のテストとプローブ | `0` | `0` |
| 旧5引数で明示seedを使うテストとプローブ | 旧seed式 | 同じ旧seed式 |

「テストは `0, 0`」は、従来の既定値 `seed = 0` に依存していた旧3・4引数呼び出しを指す。
旧5引数で明示していた `seed` を `0, 0` へ変更すると既存挙動が変わるため、
そこは同じ式を2回渡して従来の `rng == aitick` を維持する。

## 5. 所有権とローカル受け渡し

### CONTRACT-106-004: `root.gd` の待機フィールド

`src/display/root.gd` に次の2フィールドを置く。

```gdscript
var _pending_rng_word: Variant = null
var _pending_aitick_word: Variant = null
```

意味は「次のローカル試合へまだ渡していない値」である。試合中の現在値の写しではない。

不変条件:

- ローカル `GameView` が動作中は、両フィールドとも `null` である。
- キャラ選択中で次のローカル試合を待つ間だけ、両フィールドとも非 `null` である。
- 片方だけが `null` の状態でローカル試合を開始してはならない。
- `GameView` へ渡した直後に両フィールドを `null` へ戻す。
- root は試合中に `SimState` の生きた写しを保持、更新、監視してはならない。

回収から `GameView` の除去と `queue_free()` までは同期的な受け渡し区間である。
この区間で処理をyieldせず、シミュレーションtickを挟まない。除去後の正本は待機2ワード、
次の `GameView` へ渡した後の正本は新しい `SimState` である。

### CONTRACT-106-005: 起動時初期化

ローカル起動時だけ、#105 で取得済みの `boot_seed` から待機2ワードを1回初期化する。

```text
_pending_rng_word = boot_seed
_pending_aitick_word = boot_seed
```

- 再戦時に `boot_seed` から再初期化しない。
- host / join のネット経路では待機2ワードを初期化しない。
- join は `_ready()` 時点で `boot_seed == null` であり、握手後に
  `_on_net_boot_seed_agreed()` で `boot_seed` を受け取るが、それでも待機2ワードへ複製しない。

### CONTRACT-106-006: ローカル試合開始

`src/display/root.gd:_start_local_game()` は開始前に次をすべて検査する。

- `boot_seed != null`
- `_pending_rng_word != null`
- `_pending_aitick_word != null`

1つでも満たさなければ既存の fail-closed 方針に合わせて `push_error()`、
`get_tree().quit(1)`、`return` とし、`GameView` を作らない。
これにより join から誤ってローカル開始へ入った場合も停止する。

正常時の順序は次で固定する。

1. キャラ選択ノードを除去する。
2. 新しい `GameView` をinstantiateする。
3. roster、`rng_word`、`aitick_word` を `add_child()` 前に設定する。
4. root の待機2ワードを両方 `null` にする。
5. `GameView` を `_viewport` へ追加し、`_ready()` で新しい `SimState` を初期化する。
6. CPUレベルとポーズ状態を反映する。

手順4を `add_child()` 後へ遅らせない。`add_child()` は `GameView._ready()` を同期的に呼び得るため、
試合開始時点でrootに生きた写しを残さないためである。

### CONTRACT-106-007: ローカル再戦の回収

`src/display/root.gd:_restart_to_select()` は次の順序を守る。

1. `_showing_debug` が真なら、既存どおり最初に `_toggle_debug()` を呼ぶ。
2. 本物の `_game.state.rng` と `_game.state.aitick` を、それぞれ対応する待機フィールドへ読む。
3. 読み取り後に `_game` を `_viewport` から除去し、`queue_free()` する。
4. `_game = null` とする。
5. キャラ選択ノードを作る。

`_toggle_debug()` は `src/display/root.gd:152-163` で、デバッグノードを除去して本物の
`_game` を `_viewport` へ戻す。したがって手順1の直後に読む `_game.state` は
デバッグビューのstateではなく、停止していた本物のローカル試合のstateである。
順序を逆にしてデバッグビューのstateを回収してはならない。

### CONTRACT-106-008: `GameView` の入力

`src/display/game_view.gd` のローカル入力を次へ変更する。

```gdscript
var rng_word: Variant = null
var aitick_word: Variant = null
```

- ローカル `_ready()` は両方が非 `null` であることを検査する。
- 片方でも `null` なら既存の起動停止方針で停止する。
- `reset_match(state, cfg, 0, r, int(rng_word), int(aitick_word))` として渡す。
- `external_sim` 経路は2ワードを検査せず、外部stateへ一切書き込まない。
- 旧 `GameView.boot_seed` 入力は削除する。`boot_seed` を2ワードへ展開する責任はrootにある。

## 6. ネット対戦

### CONTRACT-106-009: 初戦だけを等値展開

`src/net/sim_root.gd` は次の2箇所だけを等価に拡張する。

- `setup(seed)` は `reset_match(..., seed, seed)`。
- `apply_agreed_start(..., agreed_seed, ...)` は
  `reset_match(..., agreed_seed, agreed_seed)`。

`setup()` の既定引数 `seed = 0` は `SimRoot` 自身のAPIであり、
`Simulation.reset_match()` の既定引数ではないため維持する。

### CONTRACT-106-010: 握手契約を変えない

次を変更しない。

- `src/net/boot_seed_handshake.gd`
- 合意する値が1ワード `boot_seed` であること
- roster、serving team、initial hash の既存契約
- RPCの引数と順序
- `SyncManager.start()` の開始条件

ネット再戦の導線が無い根拠:

- `src/display/root.gd:58-60` は `_is_net` のとき再戦要求を通さない。
- `src/net/net_match.gd:32` は握手を `_ready()` で1回だけ構築する。
- `src/net/net_match.gd:185-193` のうち `SyncManager.start()` は
  `_receive_start_ack()` 内の1箇所だけである。
- `src/net/net_match.gd:236-238` の `_on_sync_stopped()` は状態を表示するだけで、
  再接続または再戦を開始しない。

原文走査で「ネット再戦が無いこと」を固定するテストは追加しない。
既存の `_is_net` fail-closed 経路とコードレビューで守る。

### CONTRACT-106-011: 将来のネット再戦停止条件

ネット再戦を追加する場合、`boot_seed` の再利用や各peerのローカル値だけで開始してはならない。
2ワードを含む再戦合意が設計されるまで停止する。

確定tickでは、2ワードはロールバック状態とstate hashに含まれるため両peerの一致が保証される。
しかし将来、各peerが独立に「現在値」を回収すると、予測中の異なるtickを回収し得る。
したがってローカル再戦の回収方法をネットへそのまま転用してはならない。

### CONTRACT-106-012: `root.gd` のパース保護

`tests/unit/test_display_parse.gd:test_display_scripts_parse` から
`root.gd` だけを除外する `if f == "root.gd"`、古い理由コメント、`continue` を撤去する。
代わりに、`root.gd` もヘッドレスのテスト用SceneTreeでload可能なことを実測済みであり、
他の `src/display/*.gd` と同じく除外しない旨へコメントを更新する。

- `root.gd` を個別の特別処理へ移さず、既存の全displayスクリプト走査へ含める。
- `load("res://src/display/root.gd")` の結果に対する既存の `check()` を通す。
- `root.tscn` のinstantiateだけをパース保護の代用にしない。
- `TEST-106-003` も `root.tscn` をloadするため二重の保護になるが、
  `root.gd` の主たるパース保護は `test_display_scripts_parse` とする。
- `TEST-106-003` が将来変更または弱化されても、`root.gd` のload検査を失ってはならない。

## 7. 全57直接呼び出しの変更

調査時点の直接呼び出しは57件、38ファイルである。
内訳は3引数21件、4引数23件、旧5引数13件である。
以下の行番号は実装前の行番号である。

### 7.1 実行コード 4件

| ファイル:行 | 変更前 | 変更後 |
|---|---|---|
| `src/display/game_view.gd:109` | `Simulation.reset_match(state, cfg, 0, r, int(boot_seed))` | `Simulation.reset_match(state, cfg, 0, r, int(rng_word), int(aitick_word))` |
| `src/display/main.gd:22` | `Simulation.reset_match(state, cfg, 0)` | `Simulation.reset_match(state, cfg, 0, Chars.ROSTER, 0, 0)` |
| `src/net/sim_root.gd:27` | `Simulation.reset_match(state, cfg, 0, Chars.ROSTER, seed)` | `Simulation.reset_match(state, cfg, 0, Chars.ROSTER, seed, seed)` |
| `src/net/sim_root.gd:36` | `Simulation.reset_match(fresh, cfg, agreed_serving_team, agreed_roster, agreed_seed)` | `Simulation.reset_match(fresh, cfg, agreed_serving_team, agreed_roster, agreed_seed, agreed_seed)` |

### 7.2 unitテスト 36件

| ファイル:行 | 変更前 | 変更後 |
|---|---|---|
| `tests/unit/test_absolute_damage.gd:40` | `Simulation.reset_match(s, cfg, 0, [Chars.CHAR_UME, Chars.CHAR_PIYO, Chars.CHAR_PANDA, Chars.CHAR_CARBY])` | `Simulation.reset_match(s, cfg, 0, [Chars.CHAR_UME, Chars.CHAR_PIYO, Chars.CHAR_PANDA, Chars.CHAR_CARBY], 0, 0)` |
| `tests/unit/test_char_stats.gd:14` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_char_stats.gd:41` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_char_stats.gd:58` | `Sim.reset_match(s, cfg, 0, roster)` | `Sim.reset_match(s, cfg, 0, roster, 0, 0)` |
| `tests/unit/test_char_stats.gd:64` | `Sim.reset_match(s2, cfg, 0)` | `Sim.reset_match(s2, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_char_stats.gd:71` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_cpu.gd:15` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_cpu.gd:26` | `Simulation.reset_match(s, cfg, serving_team, roster)` | `Simulation.reset_match(s, cfg, serving_team, roster, 0, 0)` |
| `tests/unit/test_cpu.gd:121` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_cpu.gd:161` | `Simulation.reset_match(s, cfg, 0, [Chars.CHAR_CARBY, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [Chars.CHAR_CARBY, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_cpu.gd:188` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_cpu.gd:237` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0x1234)` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0x1234, 0x1234)` |
| `tests/unit/test_cpu_balance.gd:21` | `Simulation.reset_match(s, cfg, serve_first, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], seed)` | `Simulation.reset_match(s, cfg, serve_first, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], seed, seed)` |
| `tests/unit/test_cpu_hat.gd:12` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_cpu_offense_receive.gd:15` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0)` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_cpu_offense_receive.gd:323` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0)` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/unit/test_dash.gd:13` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_drive_burnout.gd:14` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_drive_gauge.gd:12` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hat.gd:10` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hip_cling.gd:11` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hit_boundary.gd:45` | `Simulation.reset_match(actual, cfg, 0)` | `Simulation.reset_match(actual, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hit_boundary.gd:67` | `Simulation.reset_match(actual, cfg, 0)` | `Simulation.reset_match(actual, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hit_boundary.gd:93` | `Simulation.reset_match(actual, cfg, 0)` | `Simulation.reset_match(actual, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_hit_boundary.gd:108` | `Simulation.reset_match(actual, cfg, 0)` | `Simulation.reset_match(actual, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_rally.gd:12` | `Simulation.reset_match(s, cfg, serving)` | `Simulation.reset_match(s, cfg, serving, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_rally.gd:53` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_sim_root.gd:38` | `Simulation.reset_match(expected, r.cfg, 1, Chars.ROSTER, 0x173B)` | `Simulation.reset_match(expected, r.cfg, 1, Chars.ROSTER, 0x173B, 0x173B)` |
| `tests/unit/test_skid.gd:9` | `Sim.reset_match(s, cfg, 0)` | `Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_stateful_rng_part_a.gd:15` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, seed)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, seed, seed)` |
| `tests/unit/test_stateful_rng_part_a.gd:68` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0x12345)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0x12345, 0x12345)` |
| `tests/unit/test_stateful_rng_part_a.gd:83` | `Simulation.reset_match(s, cfg, 1, Chars.ROSTER, -1)` | `Simulation.reset_match(s, cfg, 1, Chars.ROSTER, -1, -1)` |
| `tests/unit/test_super_catalog.gd:13` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_switch.gd:11` | `Simulation.reset_match(s, cfg, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_sync.gd:156` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |
| `tests/unit/test_sync.gd:201` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0)` | `Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)` |

### 7.3 `zz_*` 開発プローブ 17件

| ファイル:行 | 変更前 | 変更後 |
|---|---|---|
| `tests/zz_ace_map.gd:37` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_ace_map.gd:76` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_ace_trace.gd:27` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_ace_why.gd:49` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_bench_noise.gd:18` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_bench_rollback.gd:22` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_counter_attack.gd:24` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_die.gd:25` | `Simulation.reset_match(s2, c2, 1, [99, 99, 99, 99])` | `Simulation.reset_match(s2, c2, 1, [99, 99, 99, 99], 0, 0)` |
| `tests/zz_die2.gd:16` | `Simulation.reset_match(s, cfg, 1, [99, 99, 99, 99])` | `Simulation.reset_match(s, cfg, 1, [99, 99, 99, 99], 0, 0)` |
| `tests/zz_find_case.gd:37` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_probe_block.gd:15` | `Simulation.reset_match(s, cfg, team, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, team, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_serve_land.gd:29` | `Simulation.reset_match(s, cfg, 1, [CARBY, CARBY, CARBY, CARBY])` | `Simulation.reset_match(s, cfg, 1, [CARBY, CARBY, CARBY, CARBY], 0, 0)` |
| `tests/zz_serve_trace.gd:14` | `Simulation.reset_match(s, cfg, 0, [99, 99, 99, 99])` | `Simulation.reset_match(s, cfg, 0, [99, 99, 99, 99], 0, 0)` |
| `tests/zz_serve_vs_human_pos.gd:28` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_spike_kpi.gd:39` | `Simulation.reset_match(s, cfg, m % 2, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, m % 2, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_team_kpi.gd:45` | `Simulation.reset_match(s, cfg, m % 2, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])` | `Simulation.reset_match(s, cfg, m % 2, [STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR], 0, 0)` |
| `tests/zz_wait_vs_chase.gd:35` | `Simulation.reset_match(s, mcfg, m % 2)` | `Simulation.reset_match(s, mcfg, m % 2, Chars.ROSTER, 0, 0)` |

### 7.4 `Chars` preloadを追加する10ファイル

旧3引数呼び出しを `Chars.ROSTER` へ明示化するため、次の10ファイルへ既存形式の
`const Chars := preload("res://src/sim/chars.gd")` を追加する。

1. `src/display/main.gd`
2. `tests/unit/test_cpu_hat.gd`
3. `tests/unit/test_drive_gauge.gd`
4. `tests/unit/test_hat.gd`
5. `tests/unit/test_hip_cling.gd`
6. `tests/unit/test_hit_boundary.gd`
7. `tests/unit/test_rally.gd`
8. `tests/unit/test_skid.gd`
9. `tests/unit/test_switch.gd`
10. `tests/zz_wait_vs_chase.gd`

既に `Chars` をpreloadしているファイルへ重複定義を追加しない。

## 8. テスト設計

### TEST-106-001: `reset_match()` の2ワード契約

改訂対象:

`tests/unit/test_stateful_rng_part_a.gd`

改訂するテスト名:

```text
test_reset_match_uses_two_words_and_reset_rally_advances_rng_only
```

検証内容:

1. 既存の `seed = 0x12345` を `rng_word = 0x12345`、
   `aitick_word = 0x12345` として等価に渡す。
2. 両入力は既存どおり `0x2345` へ正規化される。
3. 開始ラリーにより `rng` だけが2回進む。
4. `0x2345 -> 0x468B -> 0x8D17` なので、終了時 `rng == 0x8D17`。
5. `aitick == 0x2345`。
6. 既存の手動 `reset_rally()` 部分は `rng = 0x1111`、`aitick = 0x2222` を維持し、
   `0x1111 -> 0x2223 -> 0x4447` と `aitick == 0x2222` を引き続き検査する。
7. 既存の `seed = -1` は `rng_word = -1`、`aitick_word = -1` として渡す。
   正規化後は双方 `0xFFFF` であり、`rng` は役割抽選を2回通しても `0xFFFF`、
   `aitick` も `0xFFFF` のままである。

期待値を本番ヘルパーから再計算して比較しない。上記の既知値を直接比較する。
2ワードの非対称入力、独立性、入れ替え拒否は `TEST-106-003` が固定する。

### TEST-106-002: `GameView` の2ワード入力

改訂対象:

`tests/unit/test_boot_seed.gd`

改訂するテスト名:

```text
test_game_view_consumes_rng_words_and_external_state_is_untouched
```

ローカル `GameView` へ既存の `boot_seed = 0x173B` と等価な
`rng_word = 0x173B`、`aitick_word = 0x173B` を設定してからツリーへ追加する。
開始ラリー後も既存の検査値を動かさず、次を検査する。

- `state.aitick == 0x173B`

`external_sim` 部分は既存どおり、外部stateの参照と全内容が変わらないことを検査する。
既存の `test_debug_main_keeps_fixed_seed_zero` は削除も緩和もしない。

### TEST-106-003: ローカル再戦の結合テスト

追加先:

`tests/unit/test_boot_seed.gd`

追加するpreload:

```gdscript
const RootScene := preload("res://src/display/root.tscn")
```

追加するテスト名:

```text
test_local_rematch_inherits_two_words_and_clears_root_handoff
```

手順:

1. `RootScene` をinstantiateし、実際の `SceneTree` へ追加する。
2. `_start_local_game([])` で最初のローカル `GameView` を作る。
   空rosterは既存の `GameView` 契約により `Chars.ROSTER` へ解決される。
3. 破棄前の本物のstateを `rng = 0x1234`、`aitick = 0x5678` に設定する。
4. `_toggle_debug()` でデバッグ表示中にしてから `_restart_to_select()` を呼び、
   デバッグ復帰順序も同じテストで通す。
5. 回収直後にrootの待機2ワードが `0x1234`、`0x5678` であることを検査する。
6. 再度 `_start_local_game([])` を呼ぶ。
7. 新しい `GameView.state` が `rng == 0x48D3`、`aitick == 0x5678` であることを検査する。
8. rootの待機2ワードが双方 `null` に戻っていることを検査する。
9. completion guardを正常終了時だけ解除し、追加したノードとtick rateを後始末する。

途中検査が失敗した場合、値が欠けたまま `_start_local_game()` を呼んで
テストプロセスをquitさせない。失敗を記録し、後始末してreturnする。

### TEST-106-004: `0x48D3` の計算根拠

`src/sim/sim_rng.gd:18-19` の式を2回適用する。

```text
初期値: 0x1234
1回目: (0x1234 * 2 + 1) & 0xFFFF
      = 0x2469
2回目: (0x2469 * 2 + 1) & 0xFFFF
      = 0x48D3
```

`src/sim/simulation.gd:386-389` はこの更新をteam 0、team 1の順で2回実行する。
同区間は `aitick` を書かないため、`0x5678` は不変である。

### TEST-106-005: 変異検査対応

| 壊す内容 | 赤くなるべきテスト | 必須の失敗点 |
|---|---|---|
| `_restart_to_select()` の2ワード回収を削除する | `test_local_rematch_inherits_two_words_and_clears_root_handoff` | 回収直後の待機値、または再戦開始値 |
| 再戦時も `boot_seed` から開始する | `test_local_rematch_inherits_two_words_and_clears_root_handoff` | 待機値または `0x48D3 / 0x5678` |
| `rng` と `aitick` を入れ替えて渡す | `test_local_rematch_inherits_two_words_and_clears_root_handoff` | 非対称ベクタ `0x48D3 / 0x5678` の両assert |
| `root.gd` へ型推論不能になる式を一時的に入れる | `test_display_scripts_parse` | `root.gd` のload結果に対する既存 `check()` |

Claude Codeは4変異を同時に入れず、1つずつ入れて対象テストが赤くなることを確認し、
各変異を完全に戻してから次へ進む。

### TEST-106-006: テスト本数

実装前の静的本数は461本である。
既存テストの削除または分割は0本、新規追加は1本なので、実装後は462本でなければならない。
`test_display_scripts_parse` の `root.gd` 除外撤去は既存テスト内の `check()` を1回増やすだけで、
`func test_` を追加しない。したがって静的本数と実行本数の目標462本は変わらない。

### TEST-106-007: `root.gd` の主パース保護

改訂対象:

`tests/unit/test_display_parse.gd`

既存の `test_display_scripts_parse` は `src/display` 直下の全 `.gd` をloadし、
各結果が非nullであることを `check()` する。`root.gd` 除外を撤去することで、
`root.gd` の型推論不能や構文エラーをこの既存テストが直接赤にする。

`TEST-106-003` は `root.tscn` のinstantiateを通じて `root.gd` を二重に守る。
ただし再戦結合テストの責務は所有権の受け渡しであり、パース保護の主責務は
`test_display_scripts_parse` に置く。結合テストだけへ依存してはならない。

## 9. 固定値契約

### GOLDEN-106-001: 固定値変更ゼロ

次を含む既存の固定期待値を1つも変更してはならない。

- `tests/unit/test_sync.gd::GOLDEN_COMBINED_HASH`
- `test_sync.gd.test_golden_hash_regression`
- `test_scatter_stream_snapshot` の60要素
- 固定配列
- 固定ハッシュ
- その他、挙動をpinするハードコード期待値

旧3・4引数経路は `0, 0`、旧5引数経路は旧seedを2回渡すため、
ローカル再戦以外の開始状態と乱数系列は従来と同じである。
固定値が1つでも赤くなった場合、期待値を更新せず発見として停止する。

本番ヘルパーから期待値を再計算して本番と同時に変わるテストも、固定値の代用にしない。

## 10. リプレイ拡張条件

リプレイは今回決めない。将来に対して次の1文だけを残す。

> 任意の試合開始点は boot_seed だけでは再現できず、開始時の rng / aitick が必要になり得る。

## 11. 停止条件

### STOP-106-001: 承認版不一致

実装開始前に、この設計書の行数またはSHA-256がClaude Codeの承認時固定値と違う場合は停止する。

### STOP-106-002: 契約不足または矛盾

2ワードの供給元、回収順、必須引数、失敗時動作のいずれかがコードへ適用できない、
または相互に矛盾すると判明した場合は推測せず停止する。

### STOP-106-003: 57件不一致

実装前の直接呼び出しが57件、38ファイル、3引数21件、4引数23件、旧5引数13件と
一致しない場合は停止する。実装後に6引数でない直接呼び出しが1件でも残る場合も停止する。

### STOP-106-004: rootの二重所有

動作中のローカル試合とrootの待機フィールドが同時に生きた現在値を持つ実装になる場合は停止する。
回収から除去までの同期的な受け渡し区間は除く。

### STOP-106-005: 不完全な待機値

待機2ワードの片方だけが `null`、または `boot_seed` と待機2ワードのいずれかが欠けたまま
ローカル試合を開始できる場合は停止する。

### STOP-106-006: デバッグstateの回収

`_showing_debug` 時に `_toggle_debug()` より前にstateを読み、
デバッグビューの系列をローカル再戦へ渡す実装になる場合は停止する。

### STOP-106-007: ネット握手の変更

`boot_seed_handshake.gd`、RPC契約、1ワード合意、initial hash契約の変更が必要になった場合は停止する。

### STOP-106-008: ネット再戦

ネット再戦導線を追加する、または各peerが独立回収した2ワードで再戦を始める必要が出た場合は停止する。
2ワードを含む再戦合意の別設計が先に必要である。

### STOP-106-009: 固定値の赤

固定配列、固定ハッシュ、固定ベクタ、`GOLDEN_COMBINED_HASH` のいずれかが変化した場合、
値を再採取または書き換えず停止する。

### STOP-106-010: 正規テスト入口の失敗

`run_tests.ps1` の終了コードが0でない、要約が `462 tests, 0 failed` でない、
または `SCRIPT ERROR summary: 0 occurrence(s)` でない場合は停止する。

### STOP-106-011: 範囲拡大

リプレイ、ネット再戦、乱数式、物理、CPU判断、ゲームプレイ値、テストランナーの変更が
必要になった場合は停止し、Claude Codeへ相談する。

### STOP-106-012: テスト数不一致

実装後の静的テスト数または実行テスト数が462でない場合は停止する。
既存テストを削除、改名によって非発見化、または統合して帳尻を合わせてはならない。

### STOP-106-013: `root.gd` のパース保護欠落

`test_display_scripts_parse` に `root.gd` の除外が残る、別の除外が追加される、
または `root.gd` のload結果を `check()` しない実装になる場合は停止する。
`TEST-106-003` が `root.tscn` をinstantiateできることだけで代用してはならない。

## 12. 検証手順

Codexは実装後に変更内容と静的確認を報告するが、この環境ではGodotとテストを実行しない。
動的検証はClaude Codeが行う。

### VERIFY-106-001: 承認版の照合

実装前に次を実行し、Claude Codeが承認時に示した行数とSHA-256へ一致することを確認する。

```powershell
$path = 'docs/superpowers/specs/2026-07-28-rng-word-ownership-design.md'
(Get-Content -Encoding UTF8 $path).Count
(Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant()
```

不一致なら `STOP-106-001`。

### VERIFY-106-002: 直接呼び出し

実装前は57件、38ファイル、引数内訳21 / 23 / 13と一致することを確認する。
実装後は57件すべてが6引数であることを、括弧と配列のネストを考慮して数える。

```powershell
rg -n --glob '*.gd' '\b(Simulation|Sim)\.reset_match\s*\(' src tests
```

目視だけでなく、ネストを考慮する静的集計でも確認する。`simulation.gd` の関数定義と
コメント中の文字列は直接呼び出しへ数えない。

合格条件:

- 直接呼び出し57件。
- 対象38ファイル。
- 全57件が6引数。
- 旧3 / 4 / 5引数呼び出し0件。

### VERIFY-106-003: 必須引数とpreload

確認項目:

- `reset_match()` の `roster`、`rng_word`、`aitick_word` に既定値がない。
- 7.4節の10ファイルだけに必要な `Chars` preloadが追加されている。
- `Chars` の重複定義がない。
- `GameView.boot_seed` の参照が0件である。
- `GameView.rng_word` / `aitick_word` がrootから `add_child()` 前に設定される。
- rootの待機2ワードが `add_child()` 前に `null` へ戻る。

### VERIFY-106-004: 静的テスト本数

```powershell
$count = 0
git ls-files 'tests/*.gd' | ForEach-Object {
	$count += @(Select-String -LiteralPath $_ -Pattern '^func test_').Count
}
$count
```

合格条件は `462`。

### VERIFY-106-005: 正規のフルテスト

Claude Codeがリポジトリルートで次を実行する。

```powershell
.\run_tests.ps1
```

合格条件:

- PowerShellプロセスの終了コードが0。
- 要約がちょうど1行の `462 tests, 0 failed`。
- `SCRIPT ERROR summary: 0 occurrence(s)`。

`root.tscn` をヘッドレスで生成、破棄した終了時に
`WARNING: 2 RIDs ... leaked` や `ERROR: N RID allocations ... leaked at exit` が
出ることがある。これは実測済みの既知leakであり、Godotの終了コード0、
要約1行、`SCRIPT ERROR` 0件を満たす限り、`run_tests.ps1` の合否へ影響しない。
このleak表示だけを #106 の失敗と判定しない。

Godot単体の表示またはGodot単体の終了コードは合格証拠にしない。
`run_tests.ps1` の終了コードを正規の合否入口とする。

### VERIFY-106-006: 変異検査

Claude Codeが `TEST-106-005` の4変異を1つずつ適用し、指定したテストだけを含む実行で
それぞれ赤を確認する。各変異を戻した後、最後に `run_tests.ps1` で全462本を確認する。

### VERIFY-106-007: 固定値変更ゼロ

`git diff` で固定期待値への変更が0件であることを確認する。
固定値テストが赤の場合は期待値変更を行わず、`STOP-106-009` として報告する。

### VERIFY-106-008: 実ゲーム起動

必要とClaude Codeが判断した場合だけ、ローカル実ゲームを起動して次を確認する。

- 初戦を開始できる。
- オプションメニューからキャラ選択へ戻れる。
- 再戦を開始できる。
- 起動、再戦、終了にSCRIPT ERRORがない。

この手動確認は `run_tests.ps1` の代わりにならない。

### VERIFY-106-009: `root.gd` のパース保護

`tests/unit/test_display_parse.gd` を静的確認し、次を満たすことを確認する。

- `if f == "root.gd"` と、その `continue` が0件。
- 「SyncManagerのautoloadが無いためコンパイル不能」という古いコメントが0件。
- `root.gd` も他のdisplayスクリプトと同じloopでloadされ、非nullを `check()` される。
- コメントは `root.gd` のload成功がヘッドレスで実測済みであり、除外しない契約を示す。

動的には `test_display_scripts_parse` が緑であることを確認する。
変異検査では `root.gd` へ型推論不能になる式を一時的に入れ、
`test_display_scripts_parse` が赤になることを確認する。変異を完全に戻してから
正規の `run_tests.ps1` を実行する。

## 13. 変更ファイルの責務

| ファイル | 責務 |
|---|---|
| `src/sim/simulation.gd` | 必須2ワードを個別正規化して開始ラリー前に代入する |
| `src/display/root.gd` | 起動時初期化、ローカル試合間の回収と一回限りの引き渡し |
| `src/display/game_view.gd` | ローカル2ワードを必須入力として `reset_match()` へ渡す |
| `src/display/main.gd` | デバッグ系列を明示的な `0, 0` で維持する |
| `src/net/sim_root.gd` | 既存の1ワードseedを適用点で等値2ワードへ展開する |
| `tests/unit/test_stateful_rng_part_a.gd` | 2ワードの独立正規化と開始ラリー消費を固定する |
| `tests/unit/test_boot_seed.gd` | `GameView` 入力、外部state不変、ローカル再戦継承を固定する |
| `tests/unit/test_display_parse.gd` | `root.gd` を含む表示層全体の主たるパース保護を担う |
| 7節の残りの呼び出し元 | 必須署名へ等価に追随する |

## 14. 完了条件

次をすべて満たしたときだけ #106 の実装完了とする。

- 承認時の行数とSHA-256を実装前に照合済み。
- 全57直接呼び出しが6引数。
- ローカル初戦は `boot_seed, boot_seed`。
- ローカル再戦は破棄した試合の `rng, aitick`。
- ネット初戦は `agreed_seed, agreed_seed`。
- デバッグビューは `0, 0`。
- 試合中のroot待機2ワードは双方 `null`。
- `test_display_scripts_parse` が `root.gd` を除外せずloadする。
- 既存テスト削除0、新規テスト1、合計462本。
- 4つの変異が指定テストを赤くする。
- `run_tests.ps1` が終了コード0。
- `462 tests, 0 failed`。
- `SCRIPT ERROR summary: 0 occurrence(s)`。
- 固定期待値の変更0。
- ネット握手、ネット再戦、リプレイ、ゲームプレイ値の変更0。

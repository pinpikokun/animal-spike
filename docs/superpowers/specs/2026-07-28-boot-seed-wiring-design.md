# #105 起動時時計種配線 設計書

## 1. 文書情報

- 対象: issue #105
- 作成日: 2026-07-28
- 対象リポジトリ: Animal Spike
- 実装言語: Godot 4.6 / GDScript
- 設計入力:
  - `docs/tasks/105.md`
  - `docs/tasks/106.md`
  - `docs/tasks/107.md`
  - `docs/tasks/88.md` の (d)
- 設計入力を確定したコミット: `e35fa65`
- 実装前の基準: 448 tests, 0 failed
- この文書は設計契約である。本文を書いただけでは実装を開始しない。
- Claude Code が全文を査読し、行数と SHA-256 を固定して承認した後にだけ実装へ進む。
- Codex はコミットしない。
- 初版作成時と今回の改訂作業では、Codex はテストも Godot も実行しない。
- REVISION-105-001 の実測値は Claude Code が実行したフルテストの報告である。

### REVISION-105-001: 初回実装後の改訂理由

初回実装後のフルテストで次を実測した。

```text
461 tests, 8 failed
SCRIPT ERROR: 17 occurrence(s)
Godot exit code: 1
```

既存テストの失敗は 0 であり、既存のゴールデン hash、固定乱数列、
固定配列、既知ベクタは一つも動かなかった。

失敗原因は次の二つに分離された。

1. `boot_seed_handshake.gd` の ACK 比較結果を `:=` で推論しようとしたため、
   `Variant` を含む式から型を決定できずパースに失敗した
2. `tests/run_tests.gd::_init()` の実行中は
   `Engine.get_main_loop()` がまだ登録されておらず `null` だった

二つ目は STOP-105-002 に該当する。
この改訂版が新しい行数と SHA-256 で承認されるまで実装を再開しない。

### REVISION-105-002: 改訂で変えない契約

追加テスト関数は 13 本、合計は 461 本のままとする。

原文走査、production と同じ式からの expected 再計算、
`main.tscn` だけによる代用へは退避しない。

`boot_seed` の production 契約、ネット合意手順、固定値不変契約、
#106 との境界は変更しない。

### REVISION-105-003: _initialize 改訂後の再実測

REVISION-105-001 の修正後、Claude Code は次を実測した。

```text
godot --headless --script res://tests/run_tests.gd
  461 tests, 0 failed
  exit code 0

powershell -File run_tests.ps1
  exit code 1
  SCRIPT ERROR 2件
```

HANDSHAKE-002A の明示的な `bool` により原因 A は解消し、
ネット合意状態機械テスト 6 本はすべて成功した。

一方、`tests/run_tests.gd::_initialize()` では
`Engine.get_main_loop()` と `SceneTree.root` は取得できるが、
実測で `root.is_inside_tree()` は `false` だった。
この段階で追加した対象ノードの `_ready()` は発火せず、
TEST-L1-002 第3項は `state == null` のまま本命検査へ進んで
SCRIPT ERROR になった。

テストメソッドは、事前ガードの `check()` を 2 回成功させた後に中断した。
そのため既存の `checks_run == 0` 防御は作動せず、
直接起動したランナーは当該テストを `PASS` と誤表示した。

`run_tests.ps1` の `SCRIPT ERROR` 検査はこの偽の緑を拒否した。
よって、この改訂では次を設計契約にする。

1. 全テスト本体は `SceneTree.root` がツリーへ入った最初の `_process()` で一回だけ実行する
2. 対象ノードは同じ `_process()` 呼び出し内で追加、検査、同期解放まで完了する
3. #105 のフルテスト合否は `run_tests.ps1` の終了コードを正とする
4. `checks_run > 0` の後にランタイムエラーで中断すると偽 PASS になり得る一般問題は、
   #105 へ広げず別タスクで扱う

この改訂版が新しい行数と SHA-256 で承認されるまで実装を再開しない。

## 2. 範囲

### SCOPE-001: #105 が扱う範囲

#105 は、プロセス起動時に取得した時計種を最初の実ゲーム sim へ配線し、
ネット対戦で合意することだけを扱う。

ここでいう実ゲーム sim は次の二つである。

- ローカル本編の最初の `GameView`
- ネット対戦の合意後に開始する `SimRoot`

### SCOPE-002: #106 へ残す範囲

プロセス内の後続試合へ、生きた `rng` / `aitick` を継承する契約は扱わない。
これは `docs/tasks/106.md` の対象である。

#105 の完了をもって、
「原作どおりプロセス終了まで再初期化しないことを達成した」としてはならない。
その性質は未達のまま #106 へ残る。

### SCOPE-003: #107 との境界

共有シード入力、シードコード、Seeded Challenge、ランキングは
`docs/tasks/107.md` の対象である。

#105 は OS の時計から取得した `boot_seed` と、
ネット対戦でホストが提示した同じ値だけを扱う。

### SCOPE-004: 変更理由

この変更の理由は一つである。

> 固定種 0 で始まっている最初の実ゲーム sim に、
> 原作の起動時時計種を配線し、ネット対戦では開始前に同じ初期状態へ合意する。

後続試合の乱数寿命、リプレイ形式、共有シード入力を同じ変更へ混ぜない。

## 3. 原作由来の事実

### ORIGINAL-105-001: 起動時の初期化

`docs/tasks/88.md` の (d) にある原作コードは次のとおりである。

```asm
9c00  b42c        mov ah, 0x2c
9c02  cd21        int 0x21
9c04  890e0811    mov [RND], cx
9c08  a10811      mov ax, [RND]
9c0b  a3b80e      mov [aitick], ax
```

DOS の時刻取得は 0x9C00 で一回だけ行われる。
取得結果は `CH=時`、`CL=分`、`DH=秒`、`DL=1/100秒` である。

原作の初期値は次の式である。

```text
RND = CX = (時 << 8) | 分
aitick = RND
```

### ORIGINAL-105-002: 秒以下は使用しない

秒 `DH` と百分秒 `DL` は割り込みの戻り値として受け取るが、
原作の乱数初期値には使用しない。

したがって、次の推測を原作契約としてはならない。

- 起動のたびに必ず別系列へ散らす意図だった
- 秒または百分秒も種へ混ぜるべきだった
- 同一分の再起動を別系列にするべきだった

契約は「起動時の時と分を初期状態にする」である。
同一分の再起動で同じ系列になることも原作挙動の一部である。

### ORIGINAL-105-003: 原作には試合単位の再初期化がない

原作では試合、セット、ラリーのいずれにも
`RND` / `aitick` の再初期化はない。

ただし、#105 はそのプロセス全期間の所有契約を完成させない。
原作のこの事実と、#105 の達成範囲を混同しない。

## 4. 本作で決めた契約

### PROJECT-105-001: 名前は boot_seed に限定する

本作で起動時に取得する値の名前は `boot_seed` とする。

次の呼び方をしてはならない。

- `match_seed`
- 「試合の乱数所有者」
- 「乱数二ワードの所有者」
- 「任意の試合を再生する完全な種」

`boot_seed` は最初の実ゲーム sim を起動点から再現するための
セッションメタデータであり、乱数二ワードそのものの所有者ではない。

### PROJECT-105-002: 値域

有効な時計入力は次の範囲だけである。

```text
0 <= hour < 24
0 <= minute < 60
```

範囲外はプログラマエラーまたはプラットフォーム境界の契約違反である。
別の有効値へ丸めたりマスクしたりして継続してはならない。

### PROJECT-105-003: seed 0 の意味

`boot_seed == 0` は 00:00 から正しく得られる有効値である。

したがって、次を禁止する。

- 0 を未初期化の番兵値として使う
- 時刻取得失敗を 0 へフォールバックする
- 受信失敗を 0 へフォールバックする

未取得または失敗は、`null` または別の明示的な状態で表現する。

## 5. 時計から種への純粋換算

### SEED-001: SimRng の純関数

`src/sim/sim_rng.gd` に次の純関数を追加する。

```gdscript
static func seed_from_clock(hour: int, minute: int) -> int:
	return (hour << 8) | minute
```

式は原作の `CX` の構成そのものである。

### SEED-002: マスクしない

`seed_from_clock()` の式へ `& 0xFF` を足してはならない。

範囲外入力を別の値へ黙って変換する契約を作らないためである。

特に `(255, 255) -> 0xFFFF` を仕様またはテストとして固定してはならない。

### SEED-003: 純関数の責務

`seed_from_clock()` の責務は、有効な `hour` と `minute` を
原作の一ワードへ換算することだけである。

この関数は次を行わない。

- OS 時刻の読み取り
- float の使用
- 時、分の補正
- 秒、百分秒の混入
- キャッシュ
- `SimState` の変更
- `rng` / `aitick` の直接変更

### SEED-004: 範囲保証の境界

リリースビルドで無効になり得る `assert` だけに範囲保証を任せてはならない。

OS 時刻を辞書から整数へ取り出す app 層が、
キー、型、範囲を実行時に検査する。
検査済みの値だけを `SimRng.seed_from_clock()` へ渡す。

`src/sim/` には OS 依存も float も持ち込まない。

## 6. OS 時刻を読む app 層

### BOOT-001: stateless なヘルパー

新規ファイル `src/app/boot_seed.gd` を追加する。

このヘルパーは `RefCounted` とし、static キャッシュを持たない。
役割は次の二つだけである。

1. `Time.get_time_dict_from_system(false)` を一回呼ぶ
2. 取得辞書を検証し、`SimRng.seed_from_clock()` へ渡す

`false` はローカル時刻を取得する指定である。
UTC へ変換してはならない。

### BOOT-002: 検証可能な分割

OS 呼び出しと辞書検証を分ける。
実装上は次と同等の二関数にする。

```gdscript
static func from_time_dict(clock: Dictionary) -> Variant
static func read_from_system() -> Variant
```

`from_time_dict()` は次を検証する。

- `"hour"` が存在する
- `"minute"` が存在する
- 両方が整数である
- `0 <= hour < 24`
- `0 <= minute < 60`

有効なら `int` の `boot_seed` を返す。
無効なら `null` を返す。

`read_from_system()` は `Time.get_time_dict_from_system(false)` の結果を
そのまま `from_time_dict()` へ渡す。

秒キーが存在しても値へ混ぜない。
秒キーの有無を成功条件にしない。

### BOOT-003: app 層の停止

`root.gd` は `read_from_system()` が `null` を返した場合、
エラーを明示して `get_tree().quit(1)` を要求し、
実ゲーム sim を一つも生成せず `_ready()` を終了する。

この停止は `assert` の有効無効に依存してはならない。

次を禁止する。

- seed 0 で続行する
- 現在 tick を代用する
- 秒を代用する
- 再度 OS 時刻を読んで成功するまで試す
- デバッグ sim だけを起動して成功扱いにする

## 7. root.gd による所有

### ROOT-001: boot_seed の所有者

`src/display/root.gd` が `boot_seed` をメンバーとして所有する。

GDScript の実行時値なので `const` にはできないが、
契約上は一度だけ設定され、その後は不変とする。

有効値 0 と未取得を区別するため、初期状態は `null` とする。
型は `Variant`、または同じ区別を保証する明示状態を用いる。

### ROOT-002: ローカルとホストの取得時点

ローカル本編とネット対戦ホストでは、
`root.gd::_ready()` がモード判定後、実ゲームの子ノードを生成する前に
`BootSeed.read_from_system()` を一回だけ呼ぶ。

成功した値を `boot_seed` へ一回だけ設定する。

ローカル本編では、この取得後にキャラクター選択画面を挟むため、
時計取得と最初の試合開始の間に任意の時間が空いてよい。
試合開始時刻ではなくプロセス起動時刻を使う契約なので、選択完了時に読み直さない。

次の場所で読み直してはならない。

- `GameView._ready()`
- `NetMatch._ready()`
- `_start_local_game()`
- `_restart_to_select()`
- `_toggle_debug()`
- 試合、セット、ラリーのリセット処理

### ROOT-003: join はローカル時計を使わない

join 側の `root.gd` は OS 時刻を種として読まない。

初期の `boot_seed` は未取得状態とし、
ホストから合意済みの値を受け取ったときだけ一回設定する。

`NetMatch` は合意完了時に `boot_seed` を通知する signal を持つ。
`root.gd` は子を `add_child()` する前に signal を接続する。

join 側で既に `boot_seed` が設定済みなら、
二度目の通知は同値でも契約違反として扱う。
ネット層の重複パケットに対する冪等性は `NetMatch` 内で吸収し、
所有者へ二度通知しない。

### ROOT-004: _ready はプロセス一回の保証ではない

ノードの `_ready()` はインスタンスごとに一回であり、
プロセス全体で一回ではない。

現在のコードには次の再生成経路がある。

- `src/display/root.gd::_start_local_game()` は
  再戦導線から新しい `GameView` を生成する
- `src/display/root.gd::_toggle_debug()` は
  `src/display/main.tscn` を別 sim として instantiate する

したがって時計取得を `GameView._ready()` や `main.gd::_ready()` に置くと、
プロセス一回の契約にならない。

### ROOT-005: 明示的な受け渡し

`root.gd` は `boot_seed` を次へ明示的に渡す。

- ローカル本編の `GameView`
- ホストの `NetMatch`

join の `NetMatch` には未取得状態を渡し、
ホストから受信した値だけを採用させる。

static キャッシュ、autoload、環境変数、`SimState` を
暗黙の受け渡し経路にしてはならない。

### ROOT-006: host / join 判定を二重化しない

`root.gd` は OS 時刻を読むかどうかを決めるため、
起動引数から local / host / join を区別する。

判定は現在の `net_match.gd` と同じく、
`host` があれば host、なければ `join` があれば join、
どちらもなければ local とする。

この区別を `net_match.gd` が同じ起動引数から独立に再計算してはならない。
`root.gd` が確定した host / join を `NetMatch` へ
`add_child()` 前に明示的に渡し、ネット層はその値を使う。

address、bot、rbdebug など host / join 以外の引数処理は
引き続き `net_match.gd` に置いてよい。

## 8. デバッグビュー

### DEBUG-001: 固定種 0 を維持する

`src/display/main.gd:22` の次の呼び出しは変更しない。

```gdscript
Simulation.reset_match(state, cfg, 0)
```

### DEBUG-002: 対象外とする理由

デバッグビューは開発計器であり、再現性を最優先する。
原作に対応物がないため、原作の乱数ライフサイクルの対象外である。

F1 を押した時刻によってデバッグ結果が変わってはならない。

デバッグビューは次を消費しない。

- 実ゲームの `boot_seed`
- 将来 #106 で決める生きた `rng` / `aitick`
- ネット対戦で合意した値

## 9. ローカル本編への配線

### LOCAL-001: GameView の入力

`src/display/game_view.gd` に `boot_seed` 入力を追加する。

`roster` と同様に、`root.gd` が `add_child()` より前に設定する。
`game_view.gd:87` の
「add_child 前に設定すること」という既存契約に揃える。

有効な seed 0 があるため、
ローカル本編では `boot_seed` の未設定を 0 と同一視しない。
`root.gd` が必ず設定したことを明示状態で検査する。

### LOCAL-002: reset_match へ渡す

`game_view.gd:103` の現在の呼び出し:

```gdscript
Simulation.reset_match(state, cfg, 0, r)
```

を、ローカル本編では次と同等にする。

```gdscript
Simulation.reset_match(state, cfg, 0, r, boot_seed)
```

ロスター選択と serving team 0 の既存契約は変更しない。

### LOCAL-003: external_sim を変更しない

`GameView.attach_external()` は `external_sim = true` とし、
外部の `cfg` と `state` の参照を保持する。

`GameView._ready()` は `external_sim` のとき
`reset_match()` を呼ばない。

したがって、LOCAL-002 の変更はネット対戦の state 初期化には使われない。
ネット対戦は第11節の手順だけを使う。

### LOCAL-004: 現在の再戦挙動を完了条件にしない

現在の配線では、`_restart_to_select()` 後に作る `GameView` も
`root.gd` が保持する同じ `boot_seed` を受け取る。

これは #105 の配線結果として存在するが、
原作の生きた二ワード継承を表していない。

この挙動をテストで固定せず、正しい後続試合の契約を #106 に残す。

## 10. SimRoot の種入力

### SIMROOT-001: setup の既定値

`src/net/sim_root.gd::setup()` は次の形へ変更する。

```gdscript
func setup(seed: int = 0) -> void:
```

初期の `Simulation.reset_match()` へ `seed` を渡す。

既定値 0 は維持する。
`tests/unit/test_sim_root.gd:11` の引数なし呼び出しは
従来どおり固定種 0 で決定論的に初期化される。

### SIMROOT-002: 接続前は仮初期化

`net_match.gd:35` 相当の `setup()` は接続前に走る。
ここは引数なしの `setup()` を維持し、種 0 の仮初期化とする。

仮初期化された state は同期開始状態として採用しない。
画面と入力ノードを安全に構築するための一時状態である。

### SIMROOT-003: 合意初期状態の適用 API

`SimRoot` に、合意済みの開始情報を既存 state へ適用する
単一のメソッドを設ける。

入力は少なくとも次を含む。

- `agreed_seed`
- `agreed_roster`
- `agreed_serving_team`
- app が正式に決めた `human_team_mask`

処理順は第11節の転写契約に従う。
戻り値は転写と app 設定後の `state.state_hash()` とする。

この API は同期開始後に呼んではならない。

## 11. ネット対戦の初期化方式

### NET-INIT-001: 新品 state から転写する

種、ロスター、サーブ側の合意後、
新品の `SimState` を作って初期化し、
その整数列を既存 state へ転写する。

```gdscript
var fresh := SimState.new()
Simulation.reset_match(fresh, cfg, agreed_serving_team, agreed_roster, agreed_seed)
state.load_int_array(fresh.to_int_array())
```

`state` オブジェクトそのものは差し替えない。

### NET-INIT-002: 参照同一性を保つ理由

`GameView.attach_external()` は `SimRoot.state` の参照を保持する。

既存 state に `load_int_array()` することで参照同一性が保たれ、
表示側は合意済み初期状態へ追従する。

`SimRoot.state = fresh` のような参照差し替えをしてはならない。

### NET-INIT-003: 44フィールドの保証

`SimState.to_int_array()` は最上位 44 フィールドをすべて運ぶ。
`load_int_array()` はその逆変換である。

この転写により、少なくとも次が仮状態から残らない。

- `tick`
- players の全直列化欄
- ball 状態
- score
- control と switch latch
- winner
- entities
- `rng`
- `aitick`
- rally role roll

`tick = 0` は「まだ進んでいないはず」という暗黙前提ではなく、
新品の初期状態からの転写で保証する。

### NET-INIT-004: reset_match の生呼び直しを採らない

既存 state に対する `reset_match()` の生呼び直しは採らない。

`reset_match()` と `reset_rally()` が書かない
`SimState` 最上位フィールドは次の 13 個である。

1. `tick`
2. `players`
3. `ball_x`
4. `ball_y`
5. `last_hit_tick`
6. `score_l`
7. `score_r`
8. `controlled_l`
9. `controlled_r`
10. `switch_latch_l`
11. `switch_latch_r`
12. `winner`
13. `entities`

現在は同期開始前に誰も state を進めないため偶然安全に見える。
しかし、接続待ち演出が state へ触れた瞬間に破綻する隠れた前提になる。

### NET-INIT-005: 転写後の四分類

転写後の値は次の四分類で扱う。

#### 現在必須 1: human_team_mask

`reset_match()` は `human_team_mask = 0` を書く。

転写後に `net_match.gd:37` 相当の正式な app 設定、
すなわち現在の
`0 if _is_bot else 3`
を再設定する。

仮 state の値を保存して戻すのではなく、
`_is_bot` という正式な出所から再計算する。

#### 現在必須 2: _team_inputs

`_team_inputs` は `SimState` の直列化外にある。

転写後、同期開始前に必ず次へ戻す。

```gdscript
_team_inputs = [0, 0]
```

接続待ち中の入力を最初の同期 tick へ持ち越してはならない。

#### 将来条件付き: app 所有設定

CPU プロファイルなど、将来 app が所有する設定が増えた場合は、
その値の正式な出所から転写後に設定する。

仮状態からコピーしてはならない。

現在の `p.cpu` にはネット対戦での正式な別出所がない。
したがって #105 で仮状態の `p.cpu` を保存して戻してはならない。
新品 state の値をそのまま採用する。

#### 禁止: 仮状態の無差別復元

仮状態全体を保存し、転写後に無差別に戻してはならない。

仮初期化を新たな情報源にしてしまい、
新品転写の保証を破壊するためである。

### NET-INIT-006: hash を取る時点

初期 `state_hash()` は次をすべて終えた後に取る。

1. 新品 state の `reset_match()`
2. 既存 state への `load_int_array()`
3. 正式な出所からの `human_team_mask` 設定
4. `_team_inputs = [0, 0]`

`_team_inputs` 自体は hash に入らないが、
初回 tick の入力契約を揃えるため、hash 保存より前に消去を完了する。

## 12. 開始情報一式

### START-001: 合意対象

ネット対戦で合意する開始情報は次の一式である。

- `boot_seed`
- roster
- serving team

seed だけを送って、ロスターまたはサーブ側をローカル既定へ暗黙依存させてはならない。

### START-002: 現在の正式な出所

現在のネット対戦では次を正式な出所とする。

- roster: `Chars.ROSTER`
- serving team: 現在のネット初期化と同じ team 0
- `boot_seed`: ホストの `root.gd` が起動時に取得した値

値を別ファイルへ複製せず、既存の定数または現在の呼び出し元を参照する。

### START-003: 受信検証

クライアントは適用前に開始情報を検証する。

- `boot_seed` は 16 bit 非負整数である
- 上位バイトが `0 <= hour < 24` を満たす
- 下位バイトが `0 <= minute < 60` を満たす
- roster の要素数が `SimState.PLAYER_COUNT` と一致する
- 各 roster 要素が `Chars.DEFS` に存在する
- serving team が 0 または 1 である

無効な開始情報を補正して続行してはならない。

### START-004: 重複判定の単位

「同じ種の重複受信」は、
開始情報一式が完全に同一であることを意味する。

同じ seed でも roster または serving team が異なる場合は
異なる開始情報であり、停止する。

## 13. ネット合意状態

### HANDSHAKE-001: 明示状態

合意処理は少なくとも次の状態を明示的に持つ。

- peer 未登録 / 登録済み
- 開始情報 未受信 / 受信済み
- 初期 state 未適用 / 適用済み
- ACK 未受信 / 検証済み
- 同期 未開始 / 開始済み
- 失敗

失敗は終端状態である。
失敗後に別パケットで正常状態へ戻してはならない。

### HANDSHAKE-002: テスト可能な状態機械

`src/net/boot_seed_handshake.gd` を追加し、
RPC や `SyncManager` を直接呼ばない状態機械を置く。

この状態機械は次を入力として受ける。

- role
- 期待する相手 peer ID
- peer 登録完了
- 開始情報受信
- 適用済み hash
- ACK の送信者 ID、seed、hash
- 同期開始通知

出力は次の動作要求を区別する。

- 待機
- 開始情報を state へ適用
- ACK 送信
- 再 ACK
- `SyncManager.start()` 許可
- 停止

`net_match.gd` はこの状態機械の結果に従う。
同じ分岐条件を `net_match.gd` とテストへ二重実装してはならない。

### HANDSHAKE-002A: Variant を含む比較結果の型を明示する

開始情報と ACK の RPC 境界は、不正な型も状態機械で停止できるように
受信値を `Variant` として扱ってよい。

その `Variant` を含む一致判定の結果は、`:=` による型推論へ任せない。
ACK の三点照合は次と同等に `bool` を明示する。

```gdscript
var matches: bool = sender_id == expected_peer_id \
	and seed == agreed_seed \
	and hash_value == initial_hash
```

照合式、照合対象、失敗時の停止契約は変更しない。
これは状態遷移の設計変更ではなく、GDScript のパースを成立させる実装制約である。

### HANDSHAKE-003: root への通知

join が開始情報を初めて正常適用したとき、
`NetMatch` は合意済み `boot_seed` を一度だけ `root.gd` へ通知する。

ホストの `root.gd` は既に自分で取得した同じ値を所有しているため、
`NetMatch` から所有値を設定し直さない。

重複受信による再 ACK では join の `root.gd` へ再通知しない。

## 14. ネット合意の手順

### NET-STEP-001: 手順 1

ホストは接続した peer に対し、次を完了する。

1. InputL、InputR、SimRoot の authority 設定
2. `SyncManager.add_peer(peer_id)`
3. 状態機械への peer 登録済み通知

この三つが完了する前に開始許可を出してはならない。

### NET-STEP-002: 手順 2

ホストは第11節の方式で開始情報を適用する。

転写後設定まで終えた `state.state_hash()` を初期 hash として保存する。

### NET-STEP-003: 手順 3

ホストはクライアントへ開始情報一式を送る。

RPC は次の属性を持つ。

```gdscript
@rpc("authority", "call_remote", "reliable")
```

クライアントが開始情報の送信元になってはならない。

### NET-STEP-004: 手順 4

クライアントは次の両方が揃ってから開始情報を適用する。

- `SyncManager.add_peer(1)` が完了し、状態機械が peer 登録済みである
- 有効な開始情報一式を受信済みである

到着順には依存しない。

- peer 登録が先なら開始情報を待つ
- 開始情報が先なら peer 登録を待つ

片方だけで `reset_match()`、転写、ACK を行ってはならない。

### NET-STEP-005: 手順 5

クライアントは第11節の転写方式で開始情報を適用し、
正式な出所から `human_team_mask` を再設定し、
`_team_inputs` を `[0, 0]` へ戻す。

その後に初期 `state_hash()` を計算する。

### NET-STEP-006: 手順 6

クライアントはホストへ次を ACK として返す。

- `boot_seed`
- 初期 `state_hash()`

ACK RPC はクライアントから呼ぶ必要があるため、受信側属性を次とする。

```gdscript
@rpc("any_peer", "call_remote", "reliable")
```

`any_peer` は送信者を信頼するという意味ではない。

### NET-STEP-007: 手順 7

ホストは ACK 受信時に必ず次の三点を照合する。

1. `multiplayer.get_remote_sender_id()` が期待する peer ID と一致する
2. ACK の `boot_seed` がホストの合意値と一致する
3. ACK の hash がホストの初期 hash と一致する

三点のどれか一つでも違えば停止する。

### NET-STEP-008: 手順 8

全件一致した場合に限り、状態機械を開始済みへ遷移させ、
その直後にホストが `SyncManager.start()` を一回だけ呼ぶ。

開始済みへの遷移を先に行い、
同一フレームの重複 ACK で二重 start する窓を作らない。

現在の `_on_peer_connected()` にある即時 `SyncManager.start()` は撤去する。

## 15. 重複と異常パケット

### NET-DUP-001: 同一開始情報の重複

クライアントが適用済みの開始情報一式と完全に同じものを、
同期開始前に再受信した場合は state を再適用しない。

保存済みの `boot_seed` と初期 hash で ACK を再送する。
これは reliable RPC の再送または処理順に対する冪等性である。

### NET-DUP-002: 異なる開始情報

適用済みの値と異なる開始情報を受信した場合は停止する。

seed、roster、serving team のどれが違っても同じである。
新しい値で上書きして続行してはならない。

### NET-DUP-003: 同期開始後の開始情報

同期開始後に開始情報を受信した場合は、
同一値であっても停止する。

同期開始後の再シードは禁止である。

### NET-DUP-004: ACK の重複

開始許可済みまたは同期開始済みのホストが ACK を再受信しても、
`SyncManager.start()` を二度呼ばない。

同期開始前で、同じ相手から同じ seed と hash の ACK が再送された場合は、
最初の検証結果を維持する。

異なる ACK は停止する。

## 16. 合意結果の観測

### OBSERVE-001: NET_AGREED を一回だけ出す

ホストとクライアントは、合意初期 state の適用と初期 hash の保存が完了した時点で、
次の一行を標準出力へ一回だけ出す。

```text
NET_AGREED role=<host|join> seed=<decimal> roster=<id0,id1,id2,id3> serving=<0|1> hash=<decimal>
```

フィールド順と区切りを固定し、PowerShell から正規表現で解析できる形にする。
roster は `agreed_roster` の順序どおりにカンマ区切りで出す。

ホストは NET-STEP-002 の完了後、クライアントは NET-STEP-005 の完了後に出す。
クライアントの再 ACK では再出力しない。

この行は合意値の観測記録であり、
state hash またはロールバック状態へ新しいフィールドを追加するものではない。

### OBSERVE-002: NET_ACK_VERIFIED を一回だけ出す

ホストは NET-STEP-007 の送信者 ID、seed、hash の三点照合に成功し、
状態機械から開始許可を得た後、`SyncManager.start()` の直前に
次の一行を標準出力へ一回だけ出す。

```text
NET_ACK_VERIFIED peer=<peer_id> seed=<decimal> hash=<decimal>
```

不一致 ACK、重複 ACK、クライアント側では出力しない。

### OBSERVE-003: 出力の限界

`NET_AGREED` は次を観測する。

- 実際に適用した `boot_seed`
- 実際に適用した roster
- 実際に適用した serving team
- 転写後設定を終えた初期 state hash

`NET_AGREED` と `NET_ACK_VERIFIED` のログだけでは
start の回数または不一致入力の拒否を証明しない。
それらは第21節のスクリプト判定と状態機械テストを組み合わせて証明する。

## 17. 停止処理

### FAIL-001: 停止の意味

この設計で「停止」は次をすべて意味する。

- 合意状態を失敗の終端状態へ移す
- `push_error()` で理由を出す
- `SyncManager.start()` を呼ばない
- 既に同期中なら `SyncManager.stop()` を呼ぶ
- multiplayer peer を close する
- 後続パケットで正常状態へ戻さない

単に `return` して接続待ちを続けることを停止とは呼ばない。

### FAIL-002: 停止対象

次のいずれかで停止する。

- OS 時刻辞書のキー、型、範囲が不正
- ホストの `boot_seed` が未取得のまま `NetMatch` を開始
- join がローカル時計を開始種として使用
- 開始情報の seed、roster、serving team が不正
- 適用済みと異なる開始情報を受信
- 同期開始後に開始情報を受信
- ACK の送信者 ID が不一致
- ACK の seed が不一致
- ACK の hash が不一致
- 同期開始前の転写または app 設定が完了していない
- 同期開始後に合意初期状態の適用を要求

### FAIL-003: 固定値が動いた場合

ゴールデン hash、固定乱数列、固定配列、既知ベクタのいずれか一つでも動いた場合、
「テストが実ゲームの経路に依存していた」という発見として停止し、報告する。

値を書き換えて通してはならない。

## 18. リプレイ拡張点

### REPLAY-001: #105 で決めること

#105 では次だけを決める。

- `boot_seed` はセッションのメタデータである
- `boot_seed` は最初の試合をプロセス起動点から再現する材料である
- ネット対戦ではホストが合意した値を保持する
- join の `root.gd` も合意後に同じ値を一度だけ保持する

### REPLAY-002: SimState へ入れない

`boot_seed` を次へ入れてはならない。

- `SimState`
- `SimState.to_int_array()`
- `state_hash()`
- ロールバック保存状態

初期化で得られた `rng` / `aitick` は従来どおり state に入る。
しかし、それを作ったセッションメタデータを state に重複保持しない。

### REPLAY-003: #105 で決めないこと

次は明示的な範囲外である。

- seed だけで途中の再戦を再生できるという契約
- リプレイファイルの正式形式
- 試合開始時に保存するのが seed か `rng` / `aitick` か
- 乱数二ワードの所有者
- 任意の試合を単一 seed だけで再現する契約

これらは #106 または後続のリプレイ設計で決める。

## 19. 変更対象ファイル

### FILE-001: 新規追加

次のファイルを追加する。

- `src/app/boot_seed.gd`
  - OS 時刻取得
  - 時、分の実行時検証
  - `SimRng.seed_from_clock()` への橋渡し
- `src/net/boot_seed_handshake.gd`
  - peer 登録、開始情報、ACK、開始許可、失敗の状態機械
- `tests/unit/test_boot_seed.gd`
  - app 境界と表示配線の契約テスト
- `tests/unit/test_boot_seed_handshake.gd`
  - ネット合意状態機械の契約テスト

### FILE-002: 変更する production ファイル

次のファイルを変更する。

- `src/sim/sim_rng.gd`
  - `seed_from_clock()` を追加
- `src/display/root.gd`
  - `boot_seed` を一回だけ取得、所有
  - `GameView` と `NetMatch` へ明示的に渡す
  - join の合意値を一回だけ受ける
  - host / join の役割を一度だけ判定して `NetMatch` へ渡す
- `src/display/game_view.gd`
  - ローカル本編用 `boot_seed` 入力
  - `reset_match()` への seed 配線
- `src/net/sim_root.gd`
  - `setup(seed: int = 0)`
  - 新品 state 転写と転写後設定
  - `_team_inputs` の初期化
- `src/net/net_match.gd`
  - 開始情報一式の送受信
  - peer 登録との合流
  - ACK 照合
  - 合意後だけ start
  - 失敗時停止
  - `NET_AGREED` の一回出力
  - `NET_ACK_VERIFIED` の一回出力

### FILE-002A: 変更する検証スクリプト

次のファイルを変更する。

- `scripts/run_net_test.ps1`
  - 既存の二窓起動モードを維持
  - `-VerifyBootSeed` の機械検証モードを追加
  - host / join の stdout と stderr を別ファイルへ保存
  - 合意値、開始回数、異常行を機械判定
  - 判定結果を終了コード 0 / 1 で返す
- `run_tests.ps1`
  - Godot の出力にテスト集計行が正確に一つあることを検査
  - 最初の `_process()` でスイートが実行されず蒸発した場合を成功扱いにしない
  - `SCRIPT ERROR` を含む Godot の偽の緑を成功扱いにしない

これらの PowerShell ファイルのコメントは、
既存契約どおり PowerShell 5.1 での文字化けを避けるため ASCII のままにする。

### FILE-003: 変更するテストファイル

次のファイルを変更する。

- `tests/unit/test_sim_rng.gd`
  - `seed_from_clock()` の既知ベクタ
- `tests/unit/test_sim_root.gd`
  - `setup()` の既定 seed 0
  - 新品 state 転写、参照同一性、転写後設定
- `tests/run_tests.gd`
  - テスト本体の実行場所を `_init()` から最初の `_process()` へ移す
  - `SceneTree.root` がツリーへ入った段階で全テストを一回だけ同期実行する
  - 一回実行を守る内部フラグを持つ

### FILE-004: 意図的に変更しないファイル

次のファイルは #105 で変更しない。

- `src/display/main.gd`
  - デバッグビューの固定種 0 を維持
- `src/sim/simulation.gd`
  - `reset_match()` の一ワード seed 契約を維持
- `src/sim/sim_state.gd`
  - `boot_seed` を追加しない
- `tests/unit/test_stateful_rng_part_a.gd`
  - 既存の seed 伝播既知ベクタを維持
- `tests/unit/test_sync.gd`
  - `GOLDEN_COMBINED_HASH` を変更しない
- `project.godot`
  - autoload を追加しない

`src/display/main.gd` の固定種 0 はテスト対象だが、
production ファイル自体には変更を加えない。

## 20. テスト設計

### TEST-COUNT-001: 追加本数

現在の静的テスト数は 448 本である。

#105 ではテスト関数を 13 本追加し、削除しない。
実装後の期待値は次のとおりである。

```text
448 + 13 = 461 tests
```

フルテストの合格条件は次である。

```text
461 tests, 0 failed
SCRIPT ERROR summary: 0 occurrence(s)
```

### TEST-L1-001: 純粋換算

`tests/unit/test_sim_rng.gd` に 1 本追加する。

一つのテストで次の既知ベクタを全件検査する。

```text
(0, 0)   -> 0x0000
(1, 2)   -> 0x0102
(12, 34) -> 0x0C22
(23, 59) -> 0x173B
```

原作の式を production helper から再計算して expected にしてはならない。
期待値はリテラルで固定する。

次は書かない。

- `(255, 255) -> 0xFFFF`
- 範囲外をマスクする検査
- 秒を混ぜた期待値

### TEST-L1-002: app 境界

`tests/unit/test_boot_seed.gd` に 4 本追加する。

1. 有効な時刻辞書から既知の seed を得て、秒の違いが結果を変えない
2. hour/minute の欠落、型不正、`hour < 0`、`hour >= 24`、
   `minute < 0`、`minute >= 60` がすべて失敗になる
3. `GameView` を実行し、add_child 前と同じタイミングで設定した有効な
   `boot_seed` がローカル初期 state へ反映されることを確認する。
   入力には既知の有効値 `0x173B` を使い、`state.aitick == 0x173B` を直接検査する。
   別インスタンスへ `attach_external()` した場合は、渡した state の参照と内容が
   `_ready()` 後も保たれ、ローカル reset を通らないことも確認する
4. load 可能な `src/display/main.gd` を実行し、
   作られた `state.aitick == 0` であることを直接確認する

第3項と第4項は `.gd` ファイルの原文を文字列として走査してはならない。
実際の `_ready()` 初期化を実行し、生成された state を検査する。

`root.gd` は `SyncManager` を前提とする `net_match.tscn` を preload するため、
ヘッドレスのユニットテストでは load できない。
したがって、この4本は `root.gd` が `GameView` への値設定を
`add_child()` より前に行うことまでは証明しない。

その順序はコードレビューと実ゲーム起動で確認する。
証明できない順序を原文走査テストで代用し、
実行時テストであるかのように扱ってはならない。

### TEST-RUNNER-001: 全スイートを最初の _process で実行する

`tests/run_tests.gd` は `SceneTree` を継承し、
Godot の `--script res://tests/run_tests.gd` で main loop として起動される。

`Object._init()` の実行中は、このオブジェクトがまだ
`Engine.get_main_loop()` へ登録されていない。
実測では `_init()` 中の `Engine.get_main_loop()` は `null` であり、
`_initialize()` では同じオブジェクトが `SceneTree` として取得でき、
`root` も存在した。

しかし `_initialize()` の実測では `root.is_inside_tree()` は `false` であり、
そこへ追加したノードの `_ready()` は発火しなかった。

最初の `_process()` の実測では `root.is_inside_tree()` は `true` であり、
同じ callback 内の `add_child()` で対象ノードの `_ready()` が同期発火した。

したがって、現在 `_initialize()` にあるテスト列挙、実行、集計、`quit()` の本体を
名前付きの内部関数へそのまま移し、最初の `_process()` から一回だけ呼ぶ。

```gdscript
var _suite_ran := false

func _process(_delta: float) -> bool:
	if _suite_ran:
		return true
	_suite_ran = true
	_run_suite()
	return true

func _run_suite() -> void:
	# 現在の _initialize() にある全テスト実行本体
```

テストの選別、順序、FAIL 集計、`checks_run == 0` 防御、
`total == 0` 防御、終了コードの決定は変更しない。

`_process()` から `super()` は呼ばない。
`quit(code)` は `_run_suite()` の既存経路で要求し、
その終了コードがプロセスへ伝播することは Godot 4.6 の使い捨てプローブで実測済みである。

`_suite_ran` は二回目の実行を防ぐ安全弁である。
正常経路では最初の `_process()` 内で `quit()` を要求し、二回目へ進まない。

### TEST-RUNNER-002: サポートする起動経路

サポートするフルテスト起動経路は現在と同じ次の一つである。

```text
godot --headless --path . --script res://tests/run_tests.gd
```

リポジトリ内でこの起動を行う正式な入口は `run_tests.ps1` である。

`tests/run_tests.gd` を通常の script として `load()` し、
`script.new()` だけでテストを起動する経路はサポートしない。
その経路では main loop の lifecycle hook である `_process()` が呼ばれないためである。

Godot はコマンドラインで渡された MainLoop script を main loop として初期化し、
root をツリーへ入れた後に `_process()` を呼ぶ。
今回の Godot 4.6 実測でも同じ起動経路で最初の `_process()`、
同期的な `_ready()`、`quit(code)` の終了コード伝播を確認済みである。

### TEST-RUNNER-003: スイート蒸発を外側でも検出する

`total == 0` 防御は `_run_suite()` が呼ばれた後のテスト発見失敗には有効だが、
最初の `_process()` または `_run_suite()` 自体が呼ばれない事故の証拠にはならない。

そのため `run_tests.ps1` は、従来の Godot 終了コードと
`SCRIPT ERROR` 検査に加えて、次の形式の集計行が正確に一つ存在することを要求する。

```text
<正の整数> tests, <0以上の整数> failed
```

集計行が 0 件または 2 件以上なら、Godot の終了コードが 0 でも
`run_tests.ps1` は終了コード 1 にする。

この外側の検査は「最初の `_process()` から `_run_suite()` が呼ばれ、
最後の集計まで到達した」ことを証明する。
461 本という #105 固有の本数と failed 0 は、
従来どおり TEST-COUNT-001 と VERIFY-002 で別に照合する。
将来テストを追加するたびに PowerShell の固定本数を更新する設計にはしない。

### TEST-RUNNER-004: lifecycle を後ろへ移す影響

全テストは従来の `_init()` より後の最初の `_process()` で走る。
この時点では `SceneTree.root` と project の autoload がツリーへ入っている。

「最初の `_process()` の時点でツリーには root しかいない」とは扱わない。
`project.godot` は `SyncManager` を autoload しており、
その `_ready()` は `PingTimer`、`SpawnManager`、`SoundManager` を追加する。

ただし現在の `SyncManager` は同期開始前の `_started == false` であり、
`SyncManager.gd::_process()` と `_physics_process()` は先頭で即時 return する。
テスト開始前の一反復で rollback tick やゲーム sim は進まない。

autoload の timer 等が一反復分の engine 時間を受け得ることまで
「副作用ゼロ」とは主張しない。
#105 が要求する保証は次に限定する。

- テスト対象ノードは runner の最初の `_process()` callback 内で初めて追加する
- `add_child()` で `_ready()` を同期実行する
- 同じ callback 内で検査し、`remove_child()` と `free()` で同期解放する
- runner が engine へ制御を返す時点では対象ノードを残さない
- 対象ノード自身の engine 駆動 `_process()` / `_physics_process()` は一度も発火させない
- 同じ callback 内で `quit()` を要求し、テスト用の二回目の frame を待たない

この lifecycle の差で既存 448 本の結果または固定値が一つでも変わった場合は、
テスト環境変更による発見として停止する。
期待値やゴールデンを書き換えて通してはならない。

将来、autoload の構成または `SyncManager` の開始前処理が変わり、
最初の `_process()` までにゲーム状態を進めるようになった場合も停止する。

### TEST-RUNNER-005: 採らない代案

次は採らない。

- 対象 scene の `_ready()` を直接呼ぶ
  - 子ノードの ready、scene tree 所属、resource 初期化を証明しない
- `_init()` から `SceneTree.new()` を作る
  - Engine が所有する現在の main loop と root を再現しない
- `_initialize()` で全テストを実行する
  - `root` は存在してもツリーへ入っておらず、対象ノードの `_ready()` が発火しない
- `call_deferred()`、二回目以降の `_process()`、frame 待ちへ送る
  - TEST-RUNNER-001 が必要とする一反復を超えて engine 時間を進める
- 第3項と第4項だけを別の Godot subprocess または別ランナーへ分離する
  - テスト数、終了コード、SCRIPT ERROR の証拠が二系統に割れる
- runner が特定のテスト名だけを識別して二段階実行する
  - 共通ランナーへ #105 固有のテスト名を焼き付ける
- 原文走査または `main.tscn` 第4項だけで代用する
  - TEST-L1-002 と STOP-105-002 の証拠契約を満たさない

最初の `_process()` は、REVISION-105-003 の実測により
TEST-L1-002 の実シーン `_ready()` を成立させる最小の lifecycle 境界だと判明した。
したがって、旧版 TEST-RUNNER-005 の一律な不採用判断を撤回し、
TEST-RUNNER-001 と TEST-RUNNER-004 の限定条件で採用する。

### TEST-RUNNER-006: checks_run 防御の既知の限界

`checks_run == 0` 防御が証明するのは、
テストメソッド内で `check()` が一回も完了しないまま中断した事故だけである。

次の事故は防げない。

1. 事前条件用の `check()` が一回以上成功する
2. その後、本命の式評価中に GDScript ランタイムエラーが起きる
3. テストメソッドが中断し、`failures` は空のまま戻る
4. runner が `checks_run > 0` かつ `failures.is_empty()` を `PASS` と表示する

REVISION-105-003 でこの偽 PASS を実測した。
これは全テストに関わる汎用ランナーの検出契約であり、
boot seed 配線そのものではないため #105 では修正しない。
課題番号をこの設計書で発明せず、別タスクとして起票して扱う。

#105 では既存の二段目の防御を正式な合否境界にする。
すなわち `run_tests.ps1` が全出力の `SCRIPT ERROR` を検出し、
一件でもあれば終了コード 1 にする。
直接 Godot を起動したランナーの `PASS` 表示だけを合格証拠にしてはならない。

### TEST-HARNESS-001: シーンを実行する方法

`tests/test_case.gd` は `RefCounted` なので、
テスト object 自身をシーンツリーへ追加しない。

`tests/unit/test_boot_seed.gd` の第3項と第4項は、
次の手順で現在の main loop が所有するシーンツリーへ対象シーンを一時的に追加する。

1. `Engine.get_main_loop()` を取得し、`SceneTree` へ cast する
2. cast 結果と `tree.root` が null でないことを `check()` する
3. テスト専用の空 `Node` を fixture root として作る
4. `tree.root.add_child(fixture_root)` する
5. `Engine.physics_ticks_per_second` を保存する
6. 対象の `PackedScene` を instantiate する
7. `boot_seed` または `attach_external()` を対象ノードへ設定する
8. `fixture_root.add_child(target)` する
9. 同期的に実行された `_ready()` の結果を直ちに検査する
10. `fixture_root.remove_child(target)` 後に `target.free()` する
11. `Engine.physics_ticks_per_second` を保存値へ戻す
12. `tree.root.remove_child(fixture_root)` 後に `fixture_root.free()` する

骨格は次と同等にする。

```gdscript
var main_loop := Engine.get_main_loop()
check(main_loop is SceneTree, "main loopがSceneTreeである")
if not (main_loop is SceneTree):
	return
var tree := main_loop as SceneTree
check(tree.root != null, "SceneTree.rootが存在する")
if tree.root == null:
	return

var fixture_root := Node.new()
tree.root.add_child(fixture_root)
var previous_tick_rate := Engine.physics_ticks_per_second
var target := TargetScene.instantiate()
# boot_seed設定またはattach_external()はここで行う
fixture_root.add_child(target)
# _ready()後のstateをここで検査する
fixture_root.remove_child(target)
target.free()
Engine.physics_ticks_per_second = previous_tick_rate
tree.root.remove_child(fixture_root)
fixture_root.free()
```

設定は必ず手順8より前に行う。
これにより production の「add_child 前に設定する」受け側契約と同じ順序で
`GameView._ready()` を実行する。

`queue_free()` は使わない。
改訂後の `tests/run_tests.gd` は最初の `_process()` 内で全テストを同期実行して
`quit()` を要求し、解放キューを処理する次の反復を待たないためである。

正常経路の後始末は `remove_child()` と `free()` で同期的に完了させる。
各対象ノードは別の fixture root で実行し、前のシーンのノードを次の検査へ残さない。

### TEST-HARNESS-002: 対象ノードのフレームを進めない

`fixture_root.add_child(target)` による `_ready()` は同期的に実行される。

runner 自身は `SceneTree.root` がツリーへ入るために最初の `_process()` を一回受ける。
これは旧版の「process / physics frame は一つも発火しない」という契約を置き換える。

対象ノードは、その runner callback の途中で追加し、
callback から戻る前に同期解放する。
したがって対象ノード自身の engine 駆動 `_process()` と `_physics_process()` は発火しない。

テストのために次を行ってはならない。

- `await process_frame`
- 物理フレームの手動進行
- timer 待ち
- `_physics_process()` の直接呼び出し
- 二回目の runner `_process()` を待つ

第3項と第4項が検査するのは `_ready()` による初期状態だけである。

### TEST-HARNESS-003: 第3項と第4項の難易度を区別する

第3項の `game_view.tscn` は重い結合検査である。
`GameView._ready()` だけでなく、子ノードの ready、`Court.setup()`、
`ScoreUI.setup()`、`_setup_sfx()`、`SpriteFactory.build_for()`、
画像と音声 resource の load まで headless で通る必要がある。

第4項の `main.tscn` は軽い結合検査である。
`main.gd::_ready()` は `SimConfig` と `SimState` の生成、
`reset_match()`、`Label` の追加だけを行う。

したがって、第4項が通っても第3項の成立を証明しない。
第3項だけが headless で成立しない場合も、第4項で代用して完了としてはならない。
その場合は STOP-105-002 に従う。

### TEST-L2-001: 合意状態機械

`tests/unit/test_boot_seed_handshake.gd` に 6 本追加する。

1. peer 登録と開始情報がどちらの順で来ても、
   両方が揃うまで適用要求を出さない
2. 適用済みと完全一致する開始情報の重複は再 ACK になる
3. seed、roster、serving team のいずれかが異なる再受信は失敗になる
4. 同期開始後の開始情報は同一でも失敗になる
5. 期待 peer から同じ seed と hash の ACK が来たときだけ開始許可を一回出す
6. 送信者 ID、seed、hash の各不一致を全件検査し、
   一つでも不一致なら開始許可を出さず失敗になる

失敗ケースを production の照合関数で expected 化してはならない。
各入力と期待する状態遷移をテスト側に固定する。

### TEST-L3-001: SimRoot 結合

`tests/unit/test_sim_root.gd` に 2 本追加する。

1. `SimRoot.setup()` を引数なしで呼ぶと従来どおり seed 0 になり、
   `setup(0)` と同じ初期 state になる
2. 合意初期状態の適用前に既存 state と `_team_inputs` を汚し、
   適用後に次を確認する
   - `state` のオブジェクト参照が同一
   - 内容が独立に作った新品初期 state と一致
   - 正式入力の `human_team_mask` が反映
   - `_team_inputs` が `[0, 0]`
   - 戻り hash が最終 state の hash と一致

第2項の expected は、
新品の `SimState` へ既存 `Simulation.reset_match()` を一回だけ適用し、
正式な `human_team_mask` を設定して作る。
仮 state の値を expected へコピーしてはならない。

### TEST-NOT-001: 重複する seed 伝播テスト

`tests/unit/test_stateful_rng_part_a.gd:65` の
`test_reset_match_seeds_both_words_and_reset_rally_advances_rng_only` は、
既に次を既知ベクタで検査している。

- `0x12345 -> 0x2345` の 16 bit 折り返し
- `rng` と `aitick` への seed 設定
- rally role 抽選二回

#105 で同じテストを追加しない。

### TEST-NOT-002: 異なる seed の一般命題

「異なる seed なら役割 roll が必ず異なる」という一般命題はテストしない。
剰余衝突があるため、契約として偽である。

別 seed の役割結果が必要なら、
衝突しないことを確認した固定二種の既知ベクタとしてだけ書ける。
#105 の必須テストにはしない。

### TEST-NOT-003: #106 の挙動を固定しない

「再戦でも同じ `boot_seed` から再開すること」をテストしない。

それは現在の一時的な配線結果であり、
#106 が変更すべき挙動を焼き付けるためである。

### TEST-NOT-004: マスク検査を書かない

範囲外入力をマスクする検査は一切書かない。

## 21. 実装後の検証

### VERIFY-001: 静的確認

実装後、少なくとも次を静的に確認する。

- `Time.get_time_dict_from_system` の呼び出しは
  `src/app/boot_seed.gd` の一箇所だけ
- `seed_from_clock` は `src/sim/sim_rng.gd` の純関数だけ
- `src/display/main.gd` の `reset_match` は明示的 seed 0
- `boot_seed` は `SimState`、`to_int_array`、`state_hash` に存在しない
- `match_seed` という新名を導入していない
- `SyncManager.start()` は ACK 全件一致の分岐からだけ到達する
- `NET_AGREED` は各 role の正常適用時に一回だけ出る
- `NET_ACK_VERIFIED` はホストの ACK 全件一致後に一回だけ出る
- seed 提示 RPC は authority / call_remote / reliable
- ACK RPC は any_peer / call_remote / reliable
- ACK 受信処理が `get_remote_sender_id()` を検査する
- ACK の `Variant` を含む一致判定結果に明示的な `bool` 型がある
- 生の既存 state への `reset_match()` 呼び直しをしていない
- 転写後に `_team_inputs = [0, 0]` がある
- 仮 state の `p.cpu` を保存、復元していない
- `tests/run_tests.gd` のテスト実行本体は最初の `_process()` から一回だけ呼ばれ、
  `_init()` と `_initialize()` からテストを実行しない
- runner の `_process()` に二回実行防止フラグがある
- `project.godot` の autoload と `SyncManager` の開始前 process が
  TEST-RUNNER-004 の停止中境界を満たす
- `run_tests.ps1` はテスト集計行が正確に一つない場合に終了コード 1
- `run_tests.ps1` は `SCRIPT ERROR` が一件でもあれば終了コード 1
- フルテストの正規合否を `run_tests.ps1` 自身の終了コードで判定する

### VERIFY-002: フルテスト

承認後の実装担当は正式な入口でフルテストを一回通す。

```text
powershell -File run_tests.ps1
```

合否を決める正規の終了コードは `run_tests.ps1` 自身の終了コードである。
内部で起動した Godot の終了コードや、直接 Godot を起動したときの
`461 tests, 0 failed` 表示だけを合格証拠にしてはならない。

次を全件報告する。

- `run_tests.ps1` の終了コード 0
- 実行テスト数 461
- failed 0
- SCRIPT ERROR 0
- `<正の整数> tests, <0以上の整数> failed` 形式の集計行が正確に一つ

Godot が `461 tests, 0 failed` と表示して終了コード 0 を返しても、
`run_tests.ps1` が SCRIPT ERROR その他の外側検査で終了コード 1 を返した場合は不合格である。

部分テストだけで完了としてはならない。

### VERIFY-003: 固定値不変

次が一つも動いていないことを確認する。

- `GOLDEN_COMBINED_HASH`
- 60 要素の scatter 乱数列
- 既存の固定 hash
- 既存の固定配列
- 既存の既知ベクタ

再採取や更新は禁止する。

### VERIFY-004: ネット結合

`scripts/run_net_test.ps1 -VerifyBootSeed` を実行し、
二プロセスの合意証拠をファイルへ保存して機械判定する。

`-VerifyBootSeed` は次を行う。

1. host と join を headless / bot で起動する
2. host と join の stdout と stderr を四つの別ファイルへリダイレクトする
3. 両方の `NET SYNC STARTED` を最大30秒待つ
4. タイムアウトまたは子プロセスの早期終了を失敗にする
5. start 観測後も2秒待ち、重複 start と直後の mismatch を捕捉する
6. `Start-Process -PassThru` で得た二つのプロセス ID だけを終了する
7. stdout の `NET_AGREED`、`NET_ACK_VERIFIED`、
   `NET SYNC STARTED` を解析する
8. stdout と stderr の全ファイルから異常行を検索する
9. 全条件一致ならスクリプト終了コード 0、不一致なら 1 を返す

出力先は `-LogDir` で指定されたディレクトリ、
または `%TEMP%\animal-spike-net-boot-seed-<timestamp>` とする。
スクリプトは最終結果と四ファイルの絶対パスを必ず表示する。

既存の `-Bot` による二窓起動モードは維持する。
`-VerifyBootSeed` は #105 の開始合意を短時間で判定する専用モードであり、
既存 M2 の30分ソークを置き換えない。

合格条件は次である。

- host stdout の `NET_AGREED` が正確に1行
- join stdout の `NET_AGREED` が正確に1行
- 二行の `boot_seed` が一致
- 二行の roster が順序込みで一致
- 二行の serving team が一致
- 二行の初期 state hash が一致
- host stdout の `NET_ACK_VERIFIED` が正確に1行
- `NET_ACK_VERIFIED` の seed と hash が host の `NET_AGREED` と一致
- host stdout の `NET SYNC STARTED` が正確に1行
- join stdout の `NET SYNC STARTED` が正確に1行
- host では `NET_AGREED`、`NET_ACK_VERIFIED`、`NET SYNC STARTED` の順
- join では `NET_AGREED`、`NET SYNC STARTED` の順
- 全四ファイルで `NET STATE MISMATCH` が0行
- 全四ファイルで `NET SYNC ERROR` が0行
- 全四ファイルで `SCRIPT ERROR` が0行
- スクリプトの終了コードが0

この判定により、合意値、初期 hash、ACK 後の開始、開始回数、
直後の mismatch はツール出力と保存ファイルから再確認できる。

ログ行は通過した分岐の観測である。
送信者 ID、seed、hash の各不一致が開始を拒否すること自体は、
TEST-L2-001 の状態機械テストで独立に証明する。

この検証は設計書作成時には実行しない。

### VERIFY-005: ローカル root 配線

ローカル本編を起動し、キャラクター選択後の最初の試合が正常に開始することを確認する。

この実ゲーム確認とコードレビューで、
`root.gd` が取得済み `boot_seed` を `GameView` の `add_child()` より前に設定する順序を確認する。

これは TEST-L1-002 の実行時テストが証明する
「GameView は事前設定された値を消費する」と組み合わせる確認である。
現状の headless ユニットテストだけでは root の順序を直接証明できないことを、
完了報告で明記する。

## 22. 固定値契約

### GOLDEN-105-001: 動くはずの固定値はゼロ

#88b-3 第1段階で既存テストは seed 0 を明示済みである。

#105 によって動くはずの既存固定値はゼロである。

一つでも動いた場合は、
「テストが実ゲームの経路に依存していた」という発見である。

その場合は次を行う。

1. 実装を停止する
2. どの固定値がどう動いたか報告する
3. 原因を切り分ける
4. ゴールデンを更新しない
5. 固定配列を更新しない

## 23. #106 へ先取りしてはならないこと

### FORBID-106-001: 再戦挙動の固定

再戦でも同じ `boot_seed` から再開することをテストで固定してはならない。

### FORBID-106-002: 所有者名への拡大

`boot_seed` を `match_seed` または「乱数所有者」と命名してはならない。

### FORBID-106-003: 状態への追加

seed を `SimState`、state hash、ロールバック状態へ入れてはならない。

### FORBID-106-004: リプレイ仕様の先取り

seed だけで任意の試合を再生できると
リプレイ仕様へ固定してはならない。

### FORBID-106-005: reset_match 契約の拡張

`reset_match()` へ次を先回りで足してはならない。

- `rng` / `aitick` の二ワード入力
- 乱数状態を保持する preserve モード
- 試合終了時の乱数状態返却
- プロセス所有者への書き戻し

## 24. 独立した停止条件

### STOP-105-001: 設計書の承認前

Claude Code がこの設計書の全文、行数、SHA-256 を承認するまで
実装を開始しない。

承認時に固定された行数または SHA-256 と作業開始時の文書が違う場合、
実装せず停止して報告する。

### STOP-105-002: 実装中の契約不一致

次のいずれかを発見した場合は、
代案を独断で実装せず停止して相談する。

- root が `boot_seed` を一回だけ所有できない
- join がローカル時計を読まないと起動できない
- GameView の state 参照を保った転写ができない
- `to_int_array()` が最上位 44 フィールドを運んでいない
- 合意情報へ seed、roster、serving team のいずれかを載せられない
- ACK 受信者が送信者 ID を検証できない
- 同期開始前に state が進む経路がある
- テストを production と同じ式で再計算しないと成立しない
- `GameView` または `main.tscn` を headless の `SceneTree.root` 配下へ
  `add_child()` して `_ready()` を実行できない
- `GameView` または `main.tscn` の headless `_ready()` 実行で
  SCRIPT ERROR が一つでも出る
- `tests/run_tests.gd` の最初の `_process()` が正式な `--script` 起動で呼ばれない
- 最初の `_process()` で `Engine.get_main_loop()` または `SceneTree.root` を取得できない
- 最初の `_process()` でも `root.is_inside_tree()` が `false`
- 最初の `_process()` 内の `add_child()` で対象ノードの `_ready()` が同期発火しない
- autoload または同期開始前の `SyncManager` が最初の `_process()` までに
  rollback tick、ゲーム sim、テスト固定値を進める
- lifecycle の移動だけで既存テストまたは固定値が一つでも変化する
- #106 の二ワード所有契約がないと #105 を実装できない

このシーン実行検査が成立しない場合も、
原文走査テスト、production と同じ式からの expected 再計算、
第4項だけによる代用へ退避してはならない。
実装を停止し、どの初期化段階で成立しなかったかを報告して相談する。

### STOP-105-003: 検証中

次のいずれかで停止して報告する。

- フルテストが 461 本でない
- failed が 1 件以上
- SCRIPT ERROR が 1 件以上
- `run_tests.ps1` の終了コードが非 0
- Godot 直接起動の集計が緑でも `run_tests.ps1` が赤
- 既存固定値が一つでも変化
- ネット初期 hash が不一致
- ACK 前に同期開始
- 同期開始が二回以上
- mismatch が 1 件以上
- `-VerifyBootSeed` が四つの証拠ファイルを残さない
- `-VerifyBootSeed` の終了コードが非 0

## 25. 完了の定義

### DONE-105-001: 実装完了条件

次をすべて満たしたときだけ #105 の実装完了とする。

1. 原作式どおりの `seed_from_clock()` がある
2. OS 時刻読み取りと実行時範囲検査が `src/sim/` の外にある
3. 無効時刻で起動停止し、seed 0 へ黙ってフォールバックしない
4. `root.gd` が `boot_seed` を一回だけ所有する
5. ローカル最初の実ゲームへ `boot_seed` が明示的に渡る
6. デバッグビューは固定種 0 のままである
7. join はローカル時計を開始種に使わない
8. ネット開始情報が seed、roster、serving team を含む
9. 合意初期 state は新品 state から既存 state へ転写される
10. `human_team_mask` は正式な出所から再設定される
11. `_team_inputs` は `[0, 0]` へ戻る
12. 仮状態を無差別に復元しない
13. クライアントは peer 登録と開始情報の両方を待つ
14. ACK の送信者 ID、seed、hash をホストが照合する
15. 全件一致後にだけ同期開始する
16. 異なる開始情報、開始後の開始情報、hash 不一致で停止する
17. 同一開始情報の重複は再 ACK になり、state を再適用しない
18. `boot_seed` は `SimState`、hash、ロールバック状態へ入らない
19. 追加テスト 13 本を含む 461 tests が 0 failed
20. SCRIPT ERROR が 0
21. 既存固定値が一つも動かない
22. `NET_AGREED` が両プロセスの合意値と初期 hash を記録する
23. `NET_ACK_VERIFIED` が ACK 全件一致後、同期開始前に一回だけ記録される
24. `-VerifyBootSeed` が保存ログを機械判定し、終了コード 0
25. ネット二プロセス検証が mismatch 0
26. 全テスト本体が `SceneTree.root` のツリー所属後、最初の `_process()` で一回だけ同期実行される
27. `run_tests.ps1` がテスト集計行の欠落または重複を成功扱いにしない
28. フルテストの正規合否は `run_tests.ps1` の終了コードで判定され、
    SCRIPT ERROR を伴う Godot の偽 PASS を成功扱いにしない

### DONE-105-002: 未達のまま残す性質

#105 は、プロセス起動時に取得した時計種を最初の実ゲーム sim へ配線し、
ネット対戦で合意することだけを扱う。

プロセス内の後続試合へ生きた `rng` / `aitick` を継承する契約は扱わない。

したがって #105 完了時にも、
「原作どおりプロセス終了まで再初期化しないことを達成した」
とは書かない。
その性質は未達のまま #106 へ残る。

## 26. 設計への異議

なし。

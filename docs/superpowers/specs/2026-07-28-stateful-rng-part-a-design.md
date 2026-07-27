# #88a ステートフル乱数の状態基盤 設計書

## 1. 目的

#88a は、原作のステートフル乱数を動かすための状態基盤だけを導入する。

- 原作式で毎tick更新する `rng`
- イベントで更新する `aitick`
- 2フィールドの初期化、保存、復元、複製、同期ハッシュ
- 毎tick更新と、打球・役割入替イベントによる更新

既存の抽選はまだ新状態を読まない。
CPUや打球の抽選結果、入力判断、物理分岐は従来のキー付きハッシュのまま維持する。

したがって #88a は厳密な意味での「挙動不変」ではない。
新状態と同期ハッシュは意図的に変わるが、**ゲームプレイ判断は不変**である。

## 2. #88全体における位置づけ

#88 は原因を切り分けられるよう、次の2段階に分割する。

### #88a

- 原作乱数の状態と更新経路を完成させる。
- 既存抽選は切り替えない。
- 状態追加によるゴールデン変更を1回記録する。

### #88b

- 既存抽選の乱数源を新状態へ切り替える。
- 役割抽選で `rng = (rng * 2 + 1) & 0xFFFF` を実行する。
- 役割を `SimState` に保存する。
- 本作独自抽選へ読み取り専用の派生値方式を導入する。
- テストを三層へ作り直す。
- 抽選切り替えによるゴールデン変更をもう1回記録する。

#88a と #88b のゴールデン更新は合計2回になる。
更新を1回へ減らすために状態追加を #88b へ寄せてはならない。

## 3. 根拠の区分

### 3.1 原作から確認された事実

原作の `RND` と `aitick` は16bitのwordである。

起動時にDOS時刻の「時・分」から得た同じ値を、両方へ設定する。

```text
RND = seed
aitick = RND
```

`RND` は毎フレーム1回、フェーズ判定より前に次式で更新される。

```text
RND = (RND * 7 + 0x4017 + aitick) & 0xFFFF
```

`aitick` は毎フレーム更新ではなく、次のイベントだけで更新される。

- 打球確定時: `aitick = (aitick + RND) & 0xFFFF`
- 役割入替時: `aitick = (aitick + 1) & 0xFFFF`

試合、セット、ラリーの開始時に再初期化する処理は原作に存在しない。

役割抽選以外の原作抽選は `RND` または `aitick` を読むだけで、状態を進めない。
役割抽選だけは `RND * 2 + 1` を書き戻すが、この例外は #88b の範囲とする。

### 3.2 本作で決定した置き換え

原作のDOS時刻は、ロールバック対戦の両ピア一致とテスト再現性を保証できない。
本作では、`reset_match()` に渡す整数をseedとする。

`seed` は `& 0xFFFF` で16bitへ正規化し、`rng` と `aitick` の両方へ設定する。
このseed方式は原作由来ではなく、本作の決定論要件による置き換えである。

## 4. スコープ

### 4.1 #88aで実施すること

- `src/sim/sim_rng.gd` に16bit状態更新関数を追加する。
- `SimState` に `rng: int` と `aitick: int` を追加する。
- 両フィールドを直列化、復元、複製、同期ハッシュの対象にする。
- `reset_match()` で両フィールドを同じseedから初期化する。
- `Simulation.tick()` の先頭で `rng` だけを1回進める。
- 打球確定時に `aitick += rng` を実行する。
- 役割入替イベント時に `aitick++` を実行する。
- すべてのseed・状態更新を16bitへ丸める。
- 状態基盤の単体・統合テストを7本追加する。
- 状態追加による合成ゴールデンハッシュを、定めた手順で1回更新する。

### 4.2 #88aで実施しないこと

- `_noise()`、`_roll()`、`_keyed_hash()` の呼び先を変えない。
- 既存抽選に `rng` または `aitick` を読ませない。
- 既存salt、actor補正、キーの出所を変えない。
- 役割抽選の `rng * 2 + 1` を実装しない。
- 役割の判定結果を `SimState` に保存しない。
- 本作独自抽選の派生値関数を実装しない。
- 既存の抽選を追加、削除、統合しない。
- 既存テストを削除しない。
- テスト三層への全面移行を始めない。

## 5. 用語と不変条件

### RNG-INVARIANT-001: 16bit状態

`rng` と `aitick` はGDScript上では `int` で宣言する。
ただし意味上は符号なし16bit wordであり、値域は常に `0..0xFFFF` とする。

次の全書き込みで `& 0xFFFF` を省いてはならない。

- seedの正規化
- 毎tickの `rng` 更新
- 打球時の `aitick += rng`
- 役割入替時の `aitick++`

### RNG-INVARIANT-002: 毎tick進むのは`rng`だけ

`Simulation.tick()` 1回につき `rng` を正確に1回進める。
`aitick` を毎tick進めてはならない。

`aitick` が変わるのは、`reset_match()`、打球確定、役割入替だけである。

### RNG-INVARIANT-003: ゲームプレイ判断から未参照

#88aでは、新しい2フィールドを次の状態配線からだけ参照する。

- seed初期化
- `rng` の毎tick更新
- `aitick` のイベント更新
- 直列化と復元
- 同期ハッシュ
- #88a専用テスト

CPU判断、打球の散り、むらっけ、狙い誤差、ミス、ジャスト、攻撃、必殺技、
ブロック、トス低軌道、役割抽選からは参照してはならない。

### RNG-INVARIANT-004: 再初期化しない

`reset_match()` でだけseedを設定する。

`reset_rally()`、得点、セット切り替え、サーブ権移動では、
`rng` と `aitick` のどちらも初期化または変更してはならない。

## 6. `src/sim/sim_rng.gd`

既存の `keyed_hash()` は #86 の契約どおり残し、式も呼び口も変更しない。

16bitの丸めを1箇所へ閉じ込めるため、次の関数を追加する。

```gdscript
const WORD_MASK := 0xFFFF

static func normalize_word(value: int) -> int:
	return value & WORD_MASK

static func advance_frame(rng: int, aitick: int) -> int:
	return (rng * 7 + 0x4017 + aitick) & WORD_MASK

static func advance_hit(aitick: int, rng: int) -> int:
	return (aitick + rng) & WORD_MASK

static func advance_role_swap(aitick: int) -> int:
	return (aitick + 1) & WORD_MASK
```

関数名と引数順はこのとおりとする。
すべて `int` だけで計算し、`float` を使わない。

`advance_frame()` は状態を書き換えず、次の `rng` を返す。
`advance_hit()` と `advance_role_swap()` も次の `aitick` を返すだけとする。
`SimState` の書き換えは呼び出し側が行う。

役割抽選用の `rng * 2 + 1` 関数は追加しない。

## 7. `SimState`への状態追加

### STATE-001: フィールド

`src/sim/sim_state.gd` のトップレベルintフィールドへ、次の順で追加する。

```gdscript
var tick: int = 0
var rng: int = 0
var aitick: int = 0
```

`rng` と `aitick` は `tick` の直後に置く。
型なし、`bool`、`float`、配列、Dictionaryにはしない。

デフォルト値0は、`SimState.new()` 直後の未初期化状態のための値である。
試合を開始する経路では `reset_match()` が必ずseedを設定する。

既存の `cpu_hit_count` は削除せず、CPU位置取りの入替周期カウンタとして残す。
同フィールドの「原作aitick相当」というコメントは、実物の `aitick` と混同しない説明へ直す。

### STATE-002: 直列化順序

`to_int_array()` の先頭を次の順にする。

```text
tick, rng, aitick, players..., ball..., match..., entities...
```

`load_int_array()` も、`tick` の直後に `rng`、`aitick` を同じ順で読む。

追加は配列末尾ではなく `tick` の直後へそろえる。
保存側と復元側の片方だけを変更してはならない。

### STATE-003: 複製・保存復元

現行の状態複製・保存復元は `to_int_array()` と `load_int_array()` の往復を基準にする。
両関数へ追加することで、ロールバック前後に `rng` と `aitick` が完全復元されること。

実装時に別の手書きコピー経路が見つかった場合は、同じ2フィールドを通す。
別経路を無視するとロールバック後の乱数系列が分岐するため、停止条件として扱う。

### STATE-004: 同期ハッシュ

`state_hash()` は `to_int_array()` の全値をFNV-1aへ流すため、
配列へ追加した `rng` と `aitick` は自動的に同期ハッシュへ入る。

ハッシュ値を維持するために新フィールドを除外してはならない。
`test_every_int_field_affects_hash` と `test_all_state_fields_are_int` は変更せず通す。

## 8. seed初期化

### SEED-001: `reset_match()`のAPI

既存の第4引数 `roster` の位置と既存呼び出しを壊さないため、
`seed` は末尾の第5引数として追加する。

```gdscript
static func reset_match(s, cfg, serving_team: int,
		roster: Array = Chars.ROSTER, seed: int = 0) -> void:
```

既定値0は、既存呼び出しとの互換性を保つ決定論的な本作既定値である。
時刻、フレーム時刻、OS乱数、Godotの乱数APIから既定seedを作ってはならない。

対戦では両ピアが合意した同じ整数を渡す。
ローカルでは呼び出し側が任意の整数を渡せる。
テストでは必ず意図が分かる固定値を明示してよい。

### SEED-002: 初期化式

`reset_match()` 内で次の順に設定する。

```gdscript
var word_seed: int = SimRng.normalize_word(seed)
s.rng = word_seed
s.aitick = word_seed
```

この設定は、末尾の `reset_rally()` 呼び出しより前に行う。
将来 #88b でラリー開始時の役割抽選が新状態を読むため、順序を逆にしてはならない。

`reset_rally()` にはseed引数を追加しない。
`reset_rally()` の本文でも両フィールドへ書き込まない。

## 9. 毎tick更新

`src/sim/simulation.gd` から `sim_rng.gd` を、リポジトリの慣習どおり
`const SimRng := preload("res://src/sim/sim_rng.gd")` で参照する。
`class_name` は使わない。

`Simulation.tick()` の最初の実行文として、次を置く。

```gdscript
state.rng = SimRng.advance_frame(state.rng, state.aitick)
```

この更新は次の処理より前でなければならない。

- team inputの読み出し
- `_handle_switch()`
- 4人分のCPU判断
- `step()`
- `state.tick += 1`
- phase判定
- `hit_freeze` と `slow_ticks` の早期return

`step()` 内へ置いてはならない。
`step()` は直接呼ばれても `rng` を進めない低レベル物理処理のまま維持する。

通常tick、ヒットストップtick、物理を進めないスローモーションtickのいずれでも、
`Simulation.tick()` が呼ばれたなら `rng` は1回だけ進む。

## 10. `aitick`のイベント更新

### EVENT-001: 打球確定

`src/sim/hit_resolver.gd` の、`s.last_hit_tick = s.tick` を設定する
通常打撃とブロック打撃の2経路を対象にする。

どちらの経路でも、打球が確定したとき正確に1回、次を実行する。

```gdscript
s.aitick = SimRng.advance_hit(s.aitick, s.rng)
```

ミス、空振り、接触不成立、クールダウンによる拒否では更新しない。
サーブ打撃は通常打撃の確定経路を通るため、同じ1回の更新対象とする。
ブロックは原作どおりチームの1タッチに数える現行経路で、同じ1回の更新対象とする。

両経路で、この更新を `_advance_cpu_positioning_after_hit()` より前に置く。
これにより同じ打球が役割入替を起こす場合も更新順が統一される。

既存の `s.last_hit_tick = s.tick` は削除、移動、意味変更しない。
既存キー付き抽選が引き続き必要とするためである。

### EVENT-002: 役割入替

現行の `_advance_cpu_positioning_after_hit()` は、打球回数を増やし、
`CPU_ROLE_SWAP_HITS` の境界でCPU前衛・後衛を入れ替える。

`cpu_hit_count % CPU_ROLE_SWAP_HITS == 0` になったとき、
チーム別のマスク処理へ入る前に次を正確に1回実行する。

```gdscript
s.aitick = SimRng.advance_role_swap(s.aitick)
```

2チームの役割が同時に入れ替わっても、チームごとに2回増やしてはならない。
人間チームをマスク更新から除外する現行条件は変更しない。
グローバルな役割入替周期が到来した時点で1回増やす。

`cpu_hit_count`、`CPU_ROLE_SWAP_HITS`、`cpu_back_role_mask` の既存値と判定を変更しない。
`_advance_cpu_positioning_after_hit()` の「aitickを打球回数で代用する」という既存コメントは、
実物の `aitick` を更新する設計に合わせ、位置取り周期だけを数える説明へ直す。

### EVENT-003: 同一tickの固定順序

同一tickに毎フレーム更新、打球、役割入替が重なった場合は、次の順とする。

1. `Simulation.tick()` 先頭で `rng = advance_frame(rng, aitick)`
2. 既存の入力生成と `step()` を実行
3. 打球確定時に `aitick = advance_hit(aitick, rng)`
4. その打球で役割入替周期へ到達した場合、
   `aitick = advance_role_swap(aitick)` を1回実行
5. 現行のチーム別役割マスク更新を実行

式で書くと、両イベントが起きたtickの最終値は次になる。

```text
rng' = (rng * 7 + 0x4017 + aitick_before_tick) & 0xFFFF
aitick' = (aitick_before_tick + rng' + 1) & 0xFFFF
```

同一tickに複数の確定打球が存在する場合は、実際の確定処理順に
各打球の `advance_hit()` と、それに伴う役割入替判定を繰り返す。

## 11. 既存抽選の維持

#88aの終了時点でも、次を維持する。

- `SimCpu._noise()` は `SimRng.keyed_hash()` を呼ぶ。
- `SimCpu._roll()` は `s.last_hit_tick` をキーにする。
- 役割抽選は `s.rally_seq` とteamをキーにする。
- `HitResolver._keyed_hash()` は `s.tick` と `actor + 1` を渡す。
- `_scatter()` と `_trait_roll_pct()` は `_keyed_hash()` を経由する。
- 全salt値は #86 完了時の値から変えない。

`rng` と `aitick` を既存抽選へ渡してはならない。
新状態を「仮に」読む暫定実装も禁止する。

## 12. テスト設計

既存433本は1本も削除または無効化しない。
新規テストを7本追加し、期待総数を **440本** とする。

### TEST-001: 原作式の既知ベクトル

`tests/unit/test_sim_rng.gd` に
`test_advance_frame_matches_original_vectors` を追加する。

最低限、次の入力と期待値を直接比較する。

| `rng` | `aitick` | 次の`rng` |
|---:|---:|---:|
| `0x0000` | `0x0000` | `0x4017` |
| `0x4017` | `0x0000` | `0x00B8` |
| `0x00B8` | `0x0000` | `0x451F` |
| `0x1234` | `0x1234` | `0xD1B7` |
| `0xFFFF` | `0xFFFF` | `0x400F` |

期待値を実装関数自身で計算してはならない。

### TEST-002: 16bit丸め

同じファイルに `test_word_and_aitick_updates_wrap_to_16_bits` を追加する。

最低限、次を確認する。

- `normalize_word(-1) == 0xFFFF`
- `normalize_word(0x10001) == 1`
- `advance_hit(0xFFFE, 3) == 1`
- `advance_role_swap(0xFFFF) == 0`

### TEST-003: 状態往復とハッシュ

`tests/unit/test_stateful_rng_part_a.gd` に
`test_rng_fields_roundtrip_and_affect_hash` を追加する。

- `rng` と `aitick` に異なる非ゼロ値を設定する。
- `to_int_array()` から別の `SimState` へ `load_int_array()` する。
- 両フィールドが完全一致する。
- `rng` だけ、`aitick` だけを変えた場合の双方で `state_hash()` が変わる。

既存の `test_every_int_field_affects_hash` と
`test_all_state_fields_are_int` も変更せず緑でなければならない。

### TEST-004: reset境界

`test_reset_match_seeds_both_words_and_reset_rally_preserves_them` を追加する。

- 16bitを超える固定seedを `reset_match()` へ渡す。
- `rng` と `aitick` が同じ16bit値になる。
- 両方を別の値へ進めてから `reset_rally()` を呼ぶ。
- `reset_rally()` 前後で両値が変わらない。
- 再度 `reset_match()` した場合だけ、新しいseedで両方が再初期化される。

### TEST-005: 毎tick更新位置

`test_tick_advances_only_rng_once_during_normal_freeze_and_slow_ticks` を追加する。

通常tick、`hit_freeze > 0` のtick、`slow_ticks > 0` かつ物理が早期returnするtickを
それぞれ独立した状態で実行する。

各ケースで次を確認する。

- `rng` は `advance_frame()` 1回分だけ進む。
- `aitick` は変わらない。
- 2回分進んでいない。

`step()` を直接呼んだケースでは、両値が変わらないことも確認する。

### TEST-006: 打球と役割入替の順序

`test_hit_and_role_swap_update_aitick_in_fixed_order` を追加する。

通常打撃とブロック打撃の両方を成立させ、各確定打球につき
`advance_hit()` が1回だけ反映されることを確認する。

役割入替境界の直前に `cpu_hit_count` を置いたケースでは、
最終値が次と一致することを確認する。

```text
(aitick_before + rng_current + 1) & 0xFFFF
```

2チームが同時に役割を変えても `+1` は1回だけであることを確認する。
境界でない打球では `+1` が起きないことも確認する。

### TEST-007: ゲームプレイ判断不変の双子検査

`test_rng_scaffold_keeps_cpu_inputs_and_gameplay_state_seed_independent` を追加する。

次の双子シミュレーションを構成する。

1. roster、config、serve team、全既存状態が同じ2つの `SimState` を作る。
2. seedだけを `0x0000` と `0xFFFF` に分ける。
3. CPU判断が動く同じラリー状態から120tick進める。
4. 各tickの開始前に、4人全員について `SimCpu.decide()` の返す入力を比較する。
5. 両シミュレーションへ同じteam inputを与えて `Simulation.tick()` を実行する。
6. 各tick後、`rng` と `aitick` だけを比較対象から除外した
   `to_int_array()` 相当の全ゲームプレイ状態を比較する。

120tickの全区間で、CPU入力列と新2フィールド以外の全状態が一致しなければならない。
比較のために本番コードへ「rngを無視するハッシュ」を追加してはならない。
テストヘルパーが両フィールドを一時的に同値へ退避・復元して配列比較する。

この検査はseed差がゲームプレイ判断へ漏れていないことの番人であり、
#88bで抽選を切り替える際に役目を終える。
#88bでは削除ではなく、新方式の期待値を検証するシナリオテストへ置き換える。

## 13. ゴールデン更新手順

現在の `GOLDEN_COMBINED_HASH` は次である。

```text
6286455164936831101
```

`rng` と `aitick` を直列化・同期ハッシュへ追加し、毎tick更新するため、
#88aではこの値が変わることが正しい。

更新は次のゲートを厳守する。

1. 新規7本を含むフルテストを、旧ゴールデンのまま実行する。
2. 総数が `440 tests` であることを確認する。
3. 赤が `test_golden_hash_regression` の1本だけであることを確認する。
4. SCRIPT ERRORが0件であることを確認する。
5. 実測された新しい合成ハッシュを記録する。
6. この条件を満たした後にだけ `GOLDEN_COMBINED_HASH` を1回変更する。
7. 既存履歴の次となる「第8回」として、旧値、新値、理由をコメントへ残す。
8. 再度フルテストを実行し、`440 tests, 0 failed` を確認する。

ゴールデン以外に1本でも赤がある場合は、値を変更してはならない。
実測値へ「合わせる」ことで他の不具合を隠してはならない。

コミットには、旧値、新値、状態2フィールド追加が理由であること、
テスト総数440本、更新前1 failed、更新後0 failedを記録する。
Codexはコミットしない。

## 14. 合格条件

### ACCEPT-001: PRNG式

- `advance_frame()` が原作式と既知ベクトルに一致する。
- seed、`rng`、`aitick` の全更新が16bitへ丸められる。
- `aitick` は毎tick更新されない。

### ACCEPT-002: 状態経路

- `rng` と `aitick` が `int` フィールドである。
- `to_int_array()` と `load_int_array()` の同じ位置に入る。
- 保存復元と複製で値が一致する。
- 両方が `state_hash()` に影響する。
- `test_every_int_field_affects_hash` と `test_all_state_fields_are_int` が緑である。

### ACCEPT-003: 更新周期

- `Simulation.tick()` 1回につき `rng` が1回だけ進む。
- CPU判断、phase、hit freeze、slow ticksより前に進む。
- 停止tickでも進む。
- `step()` の直接呼び出しでは進まない。

### ACCEPT-004: イベント更新

- 通常打撃、サーブ打撃、ブロック打撃の確定時に `aitick += rng` が1回起きる。
- 役割入替周期の到来時に `aitick++` が全体で1回起きる。
- 同一tickでは毎tick更新、打球加算、役割入替加算の順になる。
- 空振りや接触不成立では更新しない。

### ACCEPT-005: ゲームプレイ判断不変

- 既存抽選は全てキー付きハッシュのままである。
- `rng` と `aitick` はゲームプレイ判断から参照されない。
- 異なる2seedの双子検査で、120tickのCPU入力列が一致する。
- 同検査で、新2フィールド以外の全状態が一致する。
- 既存433本を削除せず維持する。

### ACCEPT-006: フルテスト

Claude Codeがフルテストを実行し、最終結果が次になる。

```text
440 tests, 0 failed
```

Codexはこの環境でフルテストまたはGodotを起動しない。

### ACCEPT-007: ゴールデン

- 更新前は旧値のまま、ゴールデン以外439本が緑である。
- 更新は状態2フィールド追加を理由とする1回だけである。
- 第8回の履歴に旧値、新値、理由を残す。
- 更新後は新しい値で `440 tests, 0 failed` になる。
- #88bでさらに1回更新する予定を履歴に混ぜない。

## 15. 変更対象

実装で変更または新設する対象は次のとおり。

- `src/sim/sim_rng.gd`
- `src/sim/sim_state.gd`
- `src/sim/simulation.gd`
- `src/sim/hit_resolver.gd`
- `tests/unit/test_sim_rng.gd`（新設）
- `tests/unit/test_stateful_rng_part_a.gd`（新設）
- `tests/unit/test_sync.gd`（ゲート通過後のゴールデン更新）

`tests/unit/test_state_coverage.gd` は動的に全intフィールドを調べるため、変更しない。

Godotが新設GDScriptに対応する `.uid` を生成した場合は、Claude Codeが内容を確認し、
対応するスクリプトと同じコミットへ含める。

## 16. 禁止事項

- `aitick` を毎tick進めない。
- 16bitの丸めを省かない。
- `reset_rally()` でseedまたは状態を初期化しない。
- セットやラリーの切り替えで再初期化しない。
- `step()` で `rng` を進めない。
- 1tickで `rng` を複数回進めない。
- 役割入替でチームごとに `aitick` を増やさない。
- 役割抽選の `rng * 2 + 1` を先取りしない。
- 既存抽選の乱数源を切り替えない。
- 新状態を既存抽選へ混ぜない。
- 既存salt、キー、actor補正を変えない。
- 既存テストを削除、skip、無効化しない。
- ゴールデン以外に赤がある状態でゴールデンを変更しない。
- 新しいゴールデン値を予測または手計算で決めない。
- `float` を使わない。
- `class_name` を導入しない。
- `git stash` を使わない。
- pre-commitを `--no-verify` でスキップしない。
- Codexはコミットしない。
- CodexはフルテストまたはGodotを実行しない。

## 17. 停止条件

次のいずれかが起きた場合は、値やテストを合わせず停止してClaude Codeへ報告する。

- `rng` または `aitick` を既存抽選が読む必要が生じた。
- 役割抽選の `rng * 2 + 1` が必要になった。
- 役割判定結果の状態保存が必要になった。
- `to_int_array()` / `load_int_array()` 以外の状態コピー経路が見つかり、
  追加範囲を確定できない。
- `reset_rally()` で再初期化しないと成立しない。
- 同一tickの更新順を設計どおりに維持できない。
- 既存テストの削除または期待値変更がゴールデン以外にも必要になった。
- 新規7本を含む総数が440本にならない。
- 旧ゴールデンで、ゴールデン回帰以外のテストが1本でも赤になる。
- ゴールデン更新後に `440 tests, 0 failed` にならない。
- 実装範囲が #88b の抽選移行へ広がる。

## 18. 引き渡し

Codexはコード実装後もフルテストとGodotを実行せず、コミットしない。

Claude Codeへ次を引き渡す。

- `git status --porcelain`
- `git diff --stat`
- 変更した全ファイルのdiff
- 新規テスト7本の一覧
- 静的に確認した16bit更新箇所
- 既存抽選が新状態を読んでいないことの検索結果
- 未確認事項と停止条件への接触

Claude Codeが旧ゴールデンで最初のフルテストを実行し、
ゴールデンだけが赤であることを確認してから値を更新する。

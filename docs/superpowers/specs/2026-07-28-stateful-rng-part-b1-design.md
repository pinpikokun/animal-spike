# #88b-1 役割抽選のステートフル化 設計書

## 1. 目的

#88b-1 は、CPUのラリー内役割を決める抽選だけを、
キー付きハッシュによる毎回の再計算から原作準拠のステートフル抽選へ移す。

対象は原作 `role_assign`（`0xBB40`）に対応する役割抽選だけである。

- ラリー開始時にチーム0、チーム1の順で1回ずつ抽選する。
- 抽選のたびに16bitの `rng` を進める。
- 各チームの生の抽選値 `0..8` を `SimState` に保存する。
- CPU判断中は保存値を読むだけにする。
- 保存、復元、ロールバック、同期ハッシュへ新状態を通す。

この変更でCPUの役割決定は実際に変わる。
そのため状態ハッシュ固定検査群は、他の全検査が緑になった後に1回だけ再採取する。

## 2. #88全体における位置づけ

### 2.1 #88aで完了済み

#88a では次の状態基盤を導入済みである。

- `SimState.rng`
- `SimState.aitick`
- 原作フレーム更新式
- 打球時と位置取り入替時の `aitick` 更新
- seedの16bit初期化
- 保存、復元、同期ハッシュ

#88a の終了時点では既存抽選は新状態を読まず、
ゲームプレイ判断は従来のキー付きハッシュのままだった。

### 2.2 #88b-1で行うこと

#88b-1 では、原作抽選のうち状態を進める唯一の例外である
役割抽選だけを切り替える。

役割は毎フレーム再抽選せず、ラリーごとに保存する。
これは原作の `P_aiflag` への保存に対応する。

### 2.3 #88b-1で行わないこと

次は #88b-2 または #88b-3 の範囲であり、本設計へ混ぜない。

- 役割以外の既存抽選の乱数源切り替え
- 原作由来抽選による生の `rng` / `aitick` 読み取り
- 本作独自抽選の読み取り専用派生値方式
- `SALT_ROLE` を含むsalt定数の削除整理
- `SALT_RECEIVE` に依存する6本の是正
- テスト全体の三層構造への再編
- 役割の分岐表変更

## 3. 根拠の区分

### 3.1 原作から確認された事実

`docs/tasks/88.md` の `(b)`、`(b-2)`、`(g)` により次が確定している。

- 役割抽選は `role_assign`（`0xBB40`）でラリーごとに1回走る。
- チーム0、チーム1を `[bp-6]` のループで連続して抽選する。
- 各抽選は先に `RND = RND * 2 + 1` を書き戻し、その後 `% 9` を取る。
- 役割抽選は、原作抽選のうち `RND` を読むだけでなく進める唯一の例外である。
- 抽選結果は `P_aiflag` に保存され、ラリー中は再抽選されない。
- アタッカー、ブロッカーの分岐表は現行実装と完全一致している。

### 3.2 本作で決定した表現

原作のbit形式をそのまま複製せず、各チームの生の `% 9` 結果を
独立した2本の `int` として `SimState` に保存する。

採用するフィールド名は次とする。

```gdscript
var rally_role_roll_team0: int = 0
var rally_role_roll_team1: int = 0
```

生のrollを保存することで、原作と照合済みの分岐表を
`SimCpu` 側にそのまま残せる。
bitへの事前変換や役割別boolの重複保存は行わない。

## 4. 不変条件

### ROLE-INVARIANT-001: 1ラリー2抽選

`reset_rally()` 1回につき `rng` を正確に2回進める。

順序は必ず次とする。

1. チーム0用に1回進め、rollを保存する。
2. その更新後の `rng` をチーム1用にもう1回進め、rollを保存する。

1回だけ進めて両チームで値を共有してはならない。
チームごとに別系列を作ってはならない。
3回以上進めてはならない。

### ROLE-INVARIANT-002: 16bit

各抽選で次の式を使う。

```text
rng = (rng * 2 + 1) & 0xFFFF
roll = rng % 9
```

乗算後の16bit丸めを省いてはならない。
rollは丸め済みの新しい `rng` から求める。

### ROLE-INVARIANT-003: ラリー中は読み取り専用

`_is_rally_attacker()` と `_is_rally_blocker()` は保存済みrollを読むだけとする。

次を行ってはならない。

- `rng` を進める。
- `rally_seq` からroleを再計算する。
- `_noise()` または `_roll()` を呼ぶ。
- 呼び出し回数に応じて結果を変える。

同じラリー中は、tick、`last_hit_tick`、呼び出し回数にかかわらず
同じ保存値から同じ役割を返す。

### ROLE-INVARIANT-004: ラリー境界だけで再抽選

役割抽選のトリガーは `reset_rally()` だけである。

- 試合開始時は、`reset_match()` が最後に呼ぶ `reset_rally()` で初回抽選する。
- 得点後の次ラリーでは、次の `reset_rally()` で再抽選する。
- セット、フレーム、打球、CPU判断の途中では再抽選しない。

`reset_match()` に役割抽選を重複実装してはならない。

### ROLE-INVARIANT-005: seed入口を増やさない

seedを受け取って16bit状態へ設定する入口は、引き続き `reset_match()` だけとする。

`reset_rally()` はseedを受け取らない。
現在の `s.rng` を2回進めるだけである。
`aitick` は役割抽選で変更しない。

### ROLE-INVARIANT-006: 既存分岐表を変えない

分岐表は原作と照合済みであり、内容を一切変更しない。

| 判定 | roll |
|---|---|
| アタッカーがslot0 | `0, 1, 5, 8` |
| アタッカーがslot1 | `2, 3, 4, 6, 7` |
| ブロッカーが2人とも | `0, 2, 5, 8` |
| ブロッカーがslot0だけ | `1, 4, 7` |
| ブロッカー無し | `3, 6` |

変更するのは分岐表へ渡すrollの出所だけである。

## 5. `src/sim/sim_rng.gd`

### RNG-ROLE-001: 専用更新関数

既存の `WORD_MASK` を使い、次を追加する。

```gdscript
static func advance_role_roll(rng: int) -> int:
	return (rng * 2 + 1) & WORD_MASK
```

この関数は次の16bit `rng` だけを返す。
`% 9`、チーム順、状態への書き込みは担当しない。

責務を分ける理由は、原作更新式そのものを単体テストできるようにし、
ラリー初期化側で消費回数とチーム順を明示するためである。

既存の次の関数は変更しない。

- `normalize_word`
- `advance_frame`
- `advance_hit`
- `advance_role_swap`
- `keyed_hash`

### RNG-ROLE-002: 単一系列

チーム別のPRNG状態は追加しない。
両チームとも `SimState.rng` という同じ系列を連続して消費する。

## 6. `SimState`への保存

### ROLE-STATE-001: フィールド

`src/sim/sim_state.gd` のトップレベル状態で、
`tick`、`rng`、`aitick` の直後へ次を置く。

```gdscript
var rally_role_roll_team0: int = 0
var rally_role_roll_team1: int = 0
```

配列、Dictionary、bool、enumへ置き換えない。
`test_all_state_fields_are_int` の契約どおり、どちらも明示的な `int` とする。

### ROLE-STATE-002: 直列化順序

`to_int_array()` の先頭を次の順序にする。

```text
tick, rng, aitick, rally_role_roll_team0, rally_role_roll_team1, players...
```

`load_int_array()` も同じ順で読む。
片方だけを追加したり、順序を逆転させたりしてはならない。

これにより次の経路へ自動的に入る。

- 保存
- 復元
- 複製
- ロールバック
- `state_hash()` による同期検査

### ROLE-STATE-003: 直列化長

既存の直列化長は248である。
トップレベル `int` を2本追加するため、新しい長さは250になる。

`tests/unit/test_state.gd` の `test_serialize_length` は、
実装に合わせた推測ではなく、仕様から次の式で更新する。

```text
5 + 4x36 + 37 + 8x8 = 250
```

先頭の5は次である。

```text
tick + rng + aitick + rally_role_roll_team0 + rally_role_roll_team1
```

期待値と式コメントを同時に250へ更新する。
式を古いまま残して数字だけ変えてはならない。

## 7. `reset_rally()`での抽選

### ROLE-DRAW-001: 挿入位置

`src/sim/simulation.gd` の `reset_rally()` で、
既存の `s.rally_seq += 1` の直後に役割抽選を置く。

この位置に固定する理由は次のとおり。

- 役割は新しいラリーの開始状態である。
- 試合開始時も `reset_match()` 末尾の同じ経路を通る。
- 抽選を1か所へ集約し、二重消費を防げる。

### ROLE-DRAW-002: チーム順と保存

処理は次の順で直接記述する。

```gdscript
s.rng = SimRng.advance_role_roll(s.rng)
s.rally_role_roll_team0 = s.rng % 9
s.rng = SimRng.advance_role_roll(s.rng)
s.rally_role_roll_team1 = s.rng % 9
```

ループで順序を隠さず、チーム0からチーム1という契約をコード上で明示する。

各代入の意味は次のとおり。

1. 最初の更新値をチーム0が使う。
2. 2回目は最初の更新値からさらに進める。
3. 2回目の更新値をチーム1が使う。
4. 最終的な `s.rng` はチーム1抽選後の値である。

### ROLE-DRAW-003: `reset_match()`との関係

`reset_match()` のseed処理は変更しない。

```gdscript
var word_seed: int = SimRng.normalize_word(seed)
s.rng = word_seed
s.aitick = word_seed
reset_rally(s, cfg, serving_team)
```

この既存順序により、初回ラリーもseedから2回進めた役割を得る。
`reset_match()` 内でrollを0へ戻したり、別に抽選したりしてはならない。

## 8. `SimCpu`の読み取り

### ROLE-READ-001: チーム別roll

`_is_rally_attacker(s, idx)` と `_is_rally_blocker(s, idx)` は、
既存どおり `idx / 2` でteam、`idx % 2` でslotを求める。

現在の次の再計算を削除する。

```gdscript
var role_roll: int = _noise(SALT_ROLE, s.rally_seq, team) % 9
```

代わりに、両関数で次の保存値を読む。

```gdscript
var role_roll: int = s.rally_role_roll_team0 \
	if team == 0 else s.rally_role_roll_team1
```

### ROLE-READ-002: 分岐本体

`match role_roll` 以下は変更しない。

特に次を維持する。

- attackerの `0, 1, 5, 8`
- blockerの `0, 2, 5, 8`
- blocker slot0限定の `1, 4, 7`
- その他の既存return

rollをboolへ事前展開する補助状態や、新しい分岐表を追加しない。

### ROLE-READ-003: 呼び出し側

次の既存呼び出しは変更しない。

- アタッカー優先判断で自分を調べる呼び出し
- アタッカー優先判断で相方を調べる呼び出し
- ブロッカー優先判断で自分を調べる呼び出し
- ブロッカー優先判断で相方を調べる呼び出し

呼び出し回数が複数でも、関数が純粋な読み取りになることで
同じラリー中の役割は不変になる。

### ROLE-READ-004: `SALT_ROLE`

`SALT_ROLE := 7` は値も定義も残す。
直前へ次のコメントを追加する。

```gdscript
# unused now that role lottery moved to the new stateful method
```

#88b-1 では削除しない。
他のsaltを詰めたり、番号を振り直したりしない。
削除は #88b-3 のsalt整理で行う。

## 9. テスト方針

### TEST-ORDER-001: テストを先に書く

本番コードを変更する前に、本節の契約テストを先に変更・追加する。

テスト追加後、Claude Codeが対象テストを実行し、
新フィールドまたは新関数が未実装で失敗することを確認する。
失敗理由が本設計の未実装以外なら停止する。

本番実装後は同じ対象テストを再実行し、緑を確認する。
CodexはフルテストまたはGodotを起動しない。

### TEST-ROLE-001: 更新式の単体検査

`tests/unit/test_sim_rng.gd` に
`test_advance_role_roll_matches_original_vectors` を1本追加する。

少なくとも次を直接比較する。

| 入力`rng` | 次の`rng` |
|---:|---:|
| `0x0000` | `0x0001` |
| `0x7FFF` | `0xFFFF` |
| `0x8000` | `0x0001` |
| `0xFFFF` | `0xFFFF` |

期待値を `advance_role_roll()` 自身で計算してはならない。
`0x8000` のケースで16bit桁あふれを直接検証する。

### TEST-ROLE-002: 1ラリーで正確に2回消費

#88a の
`test_rng_scaffold_keeps_cpu_inputs_and_gameplay_state_seed_independent`
は役目を終える。

このテストを削除して本数を減らすのではなく、
同じテスト枠を次へ置き換える。

```text
test_reset_rally_consumes_two_role_rolls_in_team_order
```

手順は次のとおり。

1. `reset_match()` に固定seed `0x1234` を渡す。
2. 初回ラリー抽選後の `rng` を `before` として保存する。
3. `expected_team0_rng = SimRng.advance_role_roll(before)` を求める。
4. `expected_team1_rng = SimRng.advance_role_roll(expected_team0_rng)` を求める。
5. `expected_after_three = SimRng.advance_role_roll(expected_team1_rng)` を求める。
6. `reset_rally()` を1回だけ呼ぶ。
7. `s.rng == expected_team1_rng` を確認する。
8. `s.rng != expected_team0_rng` を確認し、1回消費を拒否する。
9. `s.rng != expected_after_three` を確認し、3回消費を拒否する。
10. team0の保存rollが `expected_team0_rng % 9` と一致することを確認する。
11. team1の保存rollが `expected_team1_rng % 9` と一致することを確認する。
12. この固定seedでは2チームの保存rollが異なることを確認する。

最終 `rng` の一致で消費回数を2回へ固定し、
各保存値の一致でチーム順を固定する。
チームのrollを同じ値へハードコードする実装は、この検査を通らない。

### TEST-ROLE-003: 9通りの分岐表を直接検査

`tests/unit/test_cpu.gd` の
`test_rally_role_table_matches_all_nine_rolls` を維持し、内容を更新する。

seedや `rally_seq` を探索して目的のrollを引かせてはならない。
teamごとの保存フィールドへ `0..8` を直接設定し、
各rollについて両slotの次を比較する。

- `_is_rally_attacker()`
- `_is_rally_blocker()`

期待表は現行の次を変更せず使う。

```gdscript
var expected_attacker_slot: Array[int] = [0, 0, 1, 1, 1, 0, 1, 1, 0]
var expected_blocker_a: Array[bool] = [
	true, true, true, false, true, true, false, true, true,
]
var expected_blocker_b: Array[bool] = [
	true, false, true, false, false, true, false, false, true,
]
```

全9値を直接ループするため、`seen`、`seen_count`、1000回のseed探索は削除する。

### TEST-ROLE-004: ラリー内固定とラリー間更新

既存の `test_rally_roles_are_deterministic` は削除せず、
保存状態の契約を検証する内容へ書き換える。

1. 固定seed `0x1234` で `reset_match()` する。
2. 両チームのrollと4人分のattacker/blocker判定を保存する。
3. tick、`last_hit_tick` を変えながら各関数を繰り返し呼ぶ。
4. 保存rollと判定が変化しないことを確認する。
5. `reset_rally()` を1回呼ぶ。
6. 2チームのroll組が前ラリーと異なることを確認する。
7. 新ラリーでも繰り返し呼び出しに対して値が固定されることを確認する。

「全seedで毎ラリー必ず異なる」とは規定しない。
固定seed `0x1234` で連続2ラリーの組が異なることを検証し、
異なる組を探すseed探索は行わない。

### TEST-ROLE-005: 各ラリーにアタッカー1人

既存の `test_every_rally_has_exactly_one_attacker_per_team` は削除しない。

`rally_seq` を変える方式をやめ、各チームの保存rollへ `0..8` を直接設定する。
全roll、全teamでアタッカーが正確に1人であることを維持する。

### TEST-ROLE-006: 既存シナリオのseed探索撤去

`tests/unit/test_cpu.gd` の次のヘルパーは、
`rally_seq` の探索をやめて保存rollを直接設定する形へ変える。

- `_set_rally_attacker`
- `_set_rally_blocker`

または、両方を次の単純な設定ヘルパーへ統合してよい。

```gdscript
func _set_rally_role_roll(s, team: int, roll: int) -> void:
	if team == 0:
		s.rally_role_roll_team0 = roll
	else:
		s.rally_role_roll_team1 = roll
```

採用するrollは分岐表から直接選び、探索しない。

- slot1を非アタッカーにするケース: `roll = 0`
- slot1をアタッカーにするケース: `roll = 2`
- slot1をブロッカーにするケース: `roll = 0`
- slot0だけをブロッカーにするケース: `roll = 1`

`_block_priority_world()` の1000回探索も `roll = 1` の直接設定へ置き換える。

次のシナリオ検査の意図と期待値は変更しない。

- 非アタッカーが会合可能な相方へ譲る。
- 相方が会合できなければ非アタッカーも跳ぶ。
- 人間相方への自トスでは跳ばない。
- CPU相方なら自トスへ跳ぶ。
- アタック能力を持つCPUがトスへ跳ぶ。
- ブロック能力を持つCPUがブロックへ跳ぶ。
- 非ブロッカーが会合可能な相方へ譲る。
- 相方が会合できなければ非ブロッカーも跳ぶ。
- サーブ飛行中は跳ばない。

### TEST-ROLE-007: 保存復元とロールバック

`tests/unit/test_stateful_rng_part_a.gd` に
`test_role_rolls_roundtrip_and_rollback_restore` を1本追加する。

手順は次のとおり。

1. 固定seedで `reset_match()` し、初回rollを得る。
2. `to_int_array()` の複製と `state_hash()` を保存する。
3. `reset_rally()` を呼び、`rng` と両rollを進める。
4. 保存配列を同じ状態へ `load_int_array()` してロールバックする。
5. `rally_role_roll_team0` と `rally_role_roll_team1` が元へ戻ることを確認する。
6. `rng`、`aitick`、`rally_seq` も元へ戻ることを確認する。
7. `state_hash()` が保存時の値へ完全一致することを確認する。
8. 保存配列から別の `SimState` へ復元しても同じ値とハッシュになることを確認する。

固定ゴールデン値は使わない。
保存前に実測した状態同士を比較する。

### TEST-ROLE-008: テスト総数

開始時点は440本である。

- #88a双子検査の置き換え: 増減0
- PRNG単体検査の追加: +1
- 保存復元・ロールバック検査の追加: +1

期待総数は **442本** とする。
既存テストを削除、skip、無効化して本数を合わせてはならない。

## 10. 実装順序

### STEP-001: ピン留め照合

実装開始前に、Claude Codeが承認した本設計書の行数とSHA-256を照合する。
一致しなければ実装を開始せず停止する。

### STEP-002: 契約テストを先に変更

本番コードより先に次を行う。

1. `test_sim_rng.gd` に更新式の既知ベクトルを追加する。
2. #88a双子検査を2回消費・チーム順検査へ置き換える。
3. 保存復元・ロールバック検査を追加する。
4. `test_cpu.gd` のrole検査を保存rollの直接設定へ変える。
5. seed探索ヘルパーとシナリオ前提を直接設定へ変える。
6. `test_state.gd` の直列化長を250へ更新する。

この時点でテスト総数が静的に442本になることを確認する。

### STEP-003: テストが契約上の理由で赤になることを確認

Claude Codeが対象テストを実行する。

期待する失敗理由は次に限る。

- `advance_role_roll()` が未定義
- role保存フィールドが未定義
- `reset_rally()` が2回消費しない
- role関数が保存rollを読まない
- 直列化長が旧値のまま

構文エラー、無関係な既存テストの赤、別挙動の破壊が出た場合は停止する。

### STEP-004: `SimRng`へ原作更新式を追加

`advance_role_roll(rng: int) -> int` を追加する。
既存乱数関数と `keyed_hash()` は変更しない。

### STEP-005: `SimState`へ2フィールドを追加

`rally_role_roll_team0` と `rally_role_roll_team1` を
`aitick` の直後へ追加する。

`to_int_array()` と `load_int_array()` の同じ位置へ通す。
直列化長は250とする。

### STEP-006: `reset_rally()`へ2回抽選を追加

`rally_seq += 1` の直後に、チーム0、チーム1の順で
`advance_role_roll()` を1回ずつ呼び、`% 9` を保存する。

`reset_match()` のseed処理と末尾の `reset_rally()` 呼び出しは変更しない。

### STEP-007: `SimCpu`を保存値の読み取りへ切り替え

両role関数から `_noise(SALT_ROLE, s.rally_seq, team) % 9` を外す。
チーム別保存フィールドを読む。

分岐表と4か所の呼び出し側は変更しない。
`SALT_ROLE` は指定コメント付きで残す。

### STEP-008: 対象テストを再確認

Claude Codeが次の対象群を実行する。

- `test_sim_rng.gd`
- `test_stateful_rng_part_a.gd`
- `test_cpu.gd`
- `test_state.gd`
- 状態フィールド網羅検査

対象群が全件緑になるまでゴールデンへ進まない。

### STEP-009: 静的な範囲検査

次を検索で確認する。

- `_is_rally_attacker()` と `_is_rally_blocker()` に `_noise` が残っていない。
- role関数が `rally_seq` を読んでいない。
- `advance_role_roll()` の本番呼び出しが `reset_rally()` の2か所だけである。
- 保存rollへの本番書き込みが `reset_rally()` だけである。
- 保存rollの値が両role関数から読み取られる。
- `SALT_ROLE := 7` が残り、指定コメントがある。
- 他のsalt値に差分がない。
- 他の抽選経路に差分がない。
- `reset_match()` 以外にseed入口が増えていない。
- `rng * 2 + 1` の式が `sim_rng.gd` 以外へ重複していない。

### STEP-010: 旧ゴールデンでフルゲート

Claude Codeが旧ゴールデン値のままフルテストを実行する。

期待結果は次である。

```text
442 tests, 2 failed
```

赤でよい検査は、状態ハッシュを固定する次の2本だけである。

- `test_sync.gd.test_golden_hash_regression`
- `test_refactor_characterization.gd.test_hit_chain_second_golden`

この2本以外の **440本が全て緑** でなければ、
ゴールデンを変更せず停止する。

### STEP-011: 状態ハッシュ固定検査群を1回だけ再採取

STEP-010のゲートを通過した後だけ、2本を同じ再採取として更新する。

- `test_sync.gd` の合成ゴールデン値
- `test_refactor_characterization.gd` の打撃連鎖ハッシュ配列

新値はClaude Codeの実測出力をそのまま使う。
予測、手計算、値合わせを行わない。

両方へ次を記録する。

- #88b-1で役割roll2本を状態へ追加したこと
- role抽選がラリーごとのステートフル消費へ変わったこと
- 442本中、この2本以外の440本が緑だったこと
- 旧値
- 新しい実測値

2本の更新は同じコミットへ含める。
これは2回のゴールデン更新ではなく、同一原因に対する1回の再採取である。

### STEP-012: 最終フルゲート

Claude Codeが再度フルテストを実行する。

合格結果は次である。

```text
442 tests, 0 failed
```

Codexはコミットしない。
Claude Codeが差分、テスト出力、ゴールデンの由来を確認してからコミットする。

## 11. 合格条件

### ACCEPT-001: 原作式

- `advance_role_roll()` が `(rng * 2 + 1) & 0xFFFF` と一致する。
- 16bit桁あふれを既知ベクトルで検証する。
- `% 9` は更新後の `rng` に対して行う。

### ACCEPT-002: 消費順

- `reset_rally()` 1回で `rng` が正確に2回進む。
- チーム0が1回目、チーム1が2回目を使う。
- 両チームは同じrollへ固定されない。
- 最終 `rng` は2回目更新後の値である。

### ACCEPT-003: 保存状態

- 2フィールドが明示的な `int` である。
- 生のroll `0..8` を保存する。
- 直列化、復元、複製、ロールバック、同期ハッシュへ入る。
- 直列化長が式と期待値の両方で250になる。

### ACCEPT-004: 読み取り

- role関数が保存rollだけを読む。
- 同じラリー中の反復呼び出しで値が変わらない。
- `rally_seq`、tick、`last_hit_tick` から再計算しない。
- role関数の呼び出し側を変更しない。

### ACCEPT-005: 分岐表

- 9通りを保存rollの直接設定で検証する。
- attackerの `0,1,5,8` を変更しない。
- blockerの `0,2,5,8` と `1,4,7` を変更しない。
- seed探索を分岐表テストに使わない。

### ACCEPT-006: スコープ

- 役割以外の抽選に差分がない。
- 他のsalt値を変えない。
- `SALT_ROLE := 7` を指定コメント付きで残す。
- seed処理を `reset_match()` 以外へ増やさない。
- `aitick` をrole抽選で変更しない。

### ACCEPT-007: テスト

- #88a双子検査が新方式の契約検査へ置き換わっている。
- 既存テストを削除、skip、無効化していない。
- 新規2本を含む総数が442本である。
- ゴールデン再採取前に、固定検査群以外の440本が緑である。
- 再採取後に `442 tests, 0 failed` になる。

### ACCEPT-008: ゴールデン

- 固定検査群2本を同一原因として1回だけ再採取する。
- 両方に旧値、新値、理由、ゲート結果を残す。
- 他の赤を値変更で覆い隠していない。

## 12. 変更対象

実装で変更する対象は次に限定する。

- `src/sim/sim_rng.gd`
- `src/sim/sim_state.gd`
- `src/sim/simulation.gd`
- `src/sim/sim_cpu.gd`
- `tests/unit/test_sim_rng.gd`
- `tests/unit/test_stateful_rng_part_a.gd`
- `tests/unit/test_cpu.gd`
- `tests/unit/test_state.gd`
- `tests/unit/test_sync.gd`（ゲート通過後の再採取だけ）
- `tests/unit/test_refactor_characterization.gd`（ゲート通過後の再採取だけ）

Godotが既存または新設GDScriptに対応する `.uid` を生成しても、
#88b-1で新規スクリプトは作らないため、想定外の `.uid` 差分として確認する。

## 13. 禁止事項

- 役割抽選を `reset_rally()` 以外で行わない。
- 1ラリーで `rng` を1回または3回以上進めない。
- チーム1をチーム0より先に抽選しない。
- 16bit丸めを省かない。
- 更新前の `rng` から `% 9` を取らない。
- チーム別のPRNG状態を追加しない。
- `aitick` をrole抽選で進めない。
- role関数から `rng` を進めない。
- role関数で `_noise()`、`_roll()`、`rally_seq` を使わない。
- 分岐表の `0,1,5,8` / `0,2,5,8` / `1,4,7` を変えない。
- 役割以外の抽選を切り替えない。
- 本作独自抽選の派生値方式を先取りしない。
- `SALT_ROLE` を削除しない。
- salt値を連番へ整理しない。
- `SALT_RECEIVE` 依存テストを本作業へ混ぜない。
- seed入口を `reset_match()` 以外へ追加しない。
- `reset_rally()` でseedを再設定しない。
- 既存テストを削除、skip、無効化しない。
- seed探索で新roleテストを成立させない。
- 固定検査群以外に赤がある状態でゴールデンを変更しない。
- ゴールデン値を予測または手計算で決めない。
- `float` を使わない。
- `class_name` を導入しない。
- `git stash` を使わない。
- pre-commitを `--no-verify` でスキップしない。
- Codexはコミットしない。
- CodexはフルテストまたはGodotを起動しない。

## 14. 停止条件

次のいずれかが起きた場合は、範囲を広げずClaude Codeへ報告して停止する。

- `role_assign` のチーム順がチーム0、チーム1では成立しない証拠が出た。
- 1ラリー2回以外の消費が必要になった。
- role保存に2本の `int` 以外の状態が必要になった。
- 分岐表を変更しないと既存シナリオが成立しない。
- `reset_rally()` 以外でrole再抽選が必要になった。
- seedを `reset_match()` 以外で扱う必要が出た。
- `aitick` をrole抽選で変更する必要が出た。
- 役割以外の抽選変更が必要になった。
- 直列化長が250にならない追加状態経路が見つかった。
- 保存復元またはロールバックが2フィールドを再現できない。
- 新規2本を含む総数が442本にならない。
- 旧ゴールデンで固定検査群以外のテストが1本でも赤になる。
- 2本の固定検査が同一原因ではない証拠が出た。
- 再採取後に `442 tests, 0 failed` にならない。
- #88b-2または#88b-3の作業が必要になった。

## 15. 引き渡し

実装完了後、Codexはコミットせず、次を報告する。

1. `git status --porcelain`
2. `git diff --stat`
3. 変更した全ファイルのdiff
4. 追加・置換・更新したテスト名
5. 静的に確認したrole抽選の書き込み・読み取り箇所
6. `advance_role_roll()` の本番呼び出し箇所
7. `SALT_ROLE` が指定コメント付きで残ったこと
8. 役割以外の抽選へ差分がないこと
9. 直列化長の最終式と期待値
10. 停止条件に触れた点
11. 未確認事項

フルテスト、Godot、ゴールデン再採取、コミットはClaude Codeが行う。

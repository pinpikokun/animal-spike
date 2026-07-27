# #86 決定論乱数ハッシュ混合式の一本化 設計書

## 1. 目的

#86 の目的は、`src/sim/sim_cpu.gd` と `src/sim/hit_resolver.gd` に重複している
決定論乱数の混合式を、`src/sim/sim_rng.gd` の1本へ集約することである。

この変更では乱数の出目、抽選の頻度、キーの寿命、salt、actor補正を変えない。
変更前後でシミュレーションの挙動を1ビットも変えてはならない。

## 2. 範囲

### 2.1 実施すること

- `src/sim/sim_rng.gd` を新設し、混合式を1本だけ置く。
- `SimCpu._noise()` を共通混合式への互換ラッパーにする。
- `HitResolver._keyed_hash()` を共通混合式への互換ラッパーにする。
- 両ファイルから `sim_rng.gd` を `preload` する。
- `SALT_RECEIVE` が現在テストで果たしている役割を、定数付近のコメントに記録する。
- キーの出所が異なる理由を、各ラッパー付近のコメントで明確にする。

### 2.2 実施しないこと

- 既存の抽選呼び出しを新しいAPIへ直接つなぎ替えない。
- `_noise`、`_roll`、`_keyed_hash`、`_scatter`、`_trait_roll_pct` を削除しない。
- saltの追加、削除、改名、改番をしない。
- テストを追加、削除、改変しない。
- 乱数をステートフル化しない。
- `SimState` に乱数状態を追加しない。
- #88 の更新規則、保存復元、同期対象、初期乱数状態を先取りしない。

## 3. 根拠の区分

### 3.1 原作から確認された役割

原作では、打球ごとに変化する `aitick` と、フレームごとに変化する `RND` を
用途に応じて使い分けている。

- `aitick` 系: 同じ打球の間は同じ判断を維持する。
- `RND` 系: フレームごとに判断を振り直す。

本作では、`SimCpu._roll()` が使う `last_hit_tick` が `aitick` 系に対応し、
`HitResolver._keyed_hash()` が使う `s.tick` が `RND` 系に対応する。

### 3.2 本作で決定した設計

共通化するのは数値を混ぜる式だけである。
キーの出所とactor補正は呼び出し側に残し、2系列の意味を保存する。

既存のラッパーを残すのは、#86 の変更範囲を混合式の移動だけに限定し、
既存呼び出しとテストの契約を変えないためである。

## 4. 絶対不変条件

### HASH-INVARIANT-001: キーの出所を統一しない

次の対応を変更してはならない。

| 系列 | 現在の入口 | 共通関数へ渡す `key` | 変化する粒度 |
|---|---|---|---|
| 打球単位 | `SimCpu._roll(salt, s, actor)` | `s.last_hit_tick` | 打球ごと |
| フレーム単位 | `HitResolver._keyed_hash(s, actor, salt)` | `s.tick` | フレームごと |

`last_hit_tick` を `s.tick` に置き換えてはならない。
`s.tick` を `last_hit_tick` に置き換えてはならない。

また、`SimCpu._noise()` は `_roll()` 以外から任意のキーを渡される既存用途がある。
たとえば役割抽選は `s.rally_seq` をキーとしている。
したがって `_noise()` 自体がキーを選んだり、常に `last_hit_tick` を読む形へ変えてはならない。

### HASH-INVARIANT-002: actor補正を変えない

`SimCpu._noise(salt, key, actor)` は次の対応を保つ。

```gdscript
SimRng.keyed_hash(key, salt, actor)
```

`HitResolver._keyed_hash(s, actor, salt)` は次の対応を保つ。

```gdscript
SimRng.keyed_hash(s.tick, salt, actor + 1)
```

`actor + 1` を共通関数内へ隠してはならない。
共通関数の第3引数名を `actor_term` とするのは、この補正済みの値も受けるためである。

### HASH-INVARIANT-003: saltを変えない

`sim_cpu.gd` の既存saltは、現在の定義をそのまま維持する。

- `SALT_AIM = 1`
- `SALT_MISS = 2`
- `SALT_SWEET = 3`
- `SALT_RECEIVE = 4`
- `SALT_SUPER = 5`
- `SALT_ATTACK = 6`
- `SALT_ROLE = 7`

`hit_resolver.gd` の既存saltも、そのまま維持する。

- `SALT_MURA = 23`
- `SALT_TOSS_BAD = 29`
- `SALT_RECEIVE_SCATTER = 31`

数値を連番へ整理したり、ファイル間で共有定数へ移したりしてはならない。
`SALT_AIR_SHOT = 8` は #82 の剥離で既に存在しないため、#86 では復活させない。
必要性と値は #82 の再設計時に決める。

### HASH-INVARIANT-004: `SALT_RECEIVE`を維持する

`SALT_RECEIVE = 4` は、本体の抽選では現在一度も使われていない。
一方、テストは `_select_successful_roll()` からこのsaltを使い、
成功するキーを探索して `s.last_hit_tick` を特定値へ固定している。

この書き込みは、本体が実際に使う `SALT_SWEET` などの出目にも影響する。
そのため `SALT_RECEIVE` または参照箇所を削除するとテストの前提と出目が変わり、
#86 の挙動不変条件を破る。

#86 では定数、値、参照箇所、依存する6テストをすべて残す。
`SALT_RECEIVE` の定数付近には、次の事実が分かるコメントを追加する。

- 本体では引かれていない。
- テストだけが `_select_successful_roll()` 経由で `last_hit_tick` を固定するために使う。
- 依存テストの是正は #88 のテスト三層工程で行う。
- #88 では初期乱数状態を直接与え、種を探索する前提作り自体を廃止する。

対象となる6テストは次のとおりである。

- `_incoming_attack_world()` を使う5テスト
  - `test_max_cpu_presses_receive_inside_predicted_timing_window`
  - `test_max_cpu_can_press_timing_receive_while_reaction_is_frozen`
  - `test_max_cpu_just_receive_actually_fires`
  - `test_max_cpu_still_holds_receive_chord_when_current_x_can_reach`
  - `test_weak_cpu_does_not_prepare_just_receive`
- `test_max_cpu_keeps_walking_when_horizontal_range_hides_ellipse_miss`

## 5. 共通混合式

### RNG-API-001: 新設ファイル

`src/sim/sim_rng.gd` を新設する。
このリポジトリの慣習に従い `class_name` は宣言しない。

公開する混合関数は次の1本だけとする。

```gdscript
static func keyed_hash(key: int, salt: int, actor_term: int) -> int:
```

`hash` という名前はGDScriptの組み込みと紛らわしいため使用しない。

### RNG-FORMULA-001: 式と演算順序

実装は、現在2箇所にある次の混合処理をそのまま移す。

```gdscript
static func keyed_hash(key: int, salt: int, actor_term: int) -> int:
	var z: int = key + salt * 1000003 + actor_term * 998244353
	z = (z ^ (z >> 16)) * 2246822519
	z = (z ^ (z >> 13)) * 3266489917
	z = z ^ (z >> 16)
	return z & 0x7FFFFFFFFFFFFFFF
```

演算順序、乗数、シフト量、XOR、最終マスクを一切変更しない。
途中式を省略、並べ替え、別アルゴリズムへ置換してはならない。
すべて `int` のまま扱い、`float` を導入してはならない。

## 6. ファイル別変更

### FILE-001: `src/sim/sim_rng.gd`

- ファイルを新設する。
- `class_name` は使わない。
- `RNG-API-001` と `RNG-FORMULA-001` の関数だけを置く。
- salt定数やキー選択の知識を持たせない。
- `SimState` を参照させない。

### FILE-002: `src/sim/sim_cpu.gd`

既存のpreload群と同じ形で次を追加する。

```gdscript
const SimRng := preload("res://src/sim/sim_rng.gd")
```

`_noise()` のシグネチャは変更せず、本文だけを次の委譲へ置き換える。

```gdscript
static func _noise(salt: int, key: int, actor: int) -> int:
	return SimRng.keyed_hash(key, salt, actor)
```

`_roll()` は変更しない。引き続き次の経路で `last_hit_tick` を渡す。

```gdscript
return _noise(salt, s.last_hit_tick, actor)
```

`_noise()` を直接呼ぶ既存箇所の引数も変更しない。
特に、役割抽選の `s.rally_seq` を別のキーへ置き換えてはならない。

`SALT_RECEIVE` の定義と値を残し、`HASH-INVARIANT-004` の事実をコメントにする。

### FILE-003: `src/sim/hit_resolver.gd`

既存のpreload群と同じ形で次を追加する。

```gdscript
const SimRng := preload("res://src/sim/sim_rng.gd")
```

`_keyed_hash()` のシグネチャは変更せず、本文だけを次の委譲へ置き換える。

```gdscript
static func _keyed_hash(s, actor: int, salt: int) -> int:
	return SimRng.keyed_hash(s.tick, salt, actor + 1)
```

`_scatter()` と `_trait_roll_pct()` は変更しない。
両関数は引き続き `_keyed_hash()` を経由する。

コメントは、キーが `s.tick` でありフレーム単位の系列であることを明記する。
打球単位または `last_hit_tick` を使うという説明に変えてはならない。

### FILE-004: テスト

テストファイルは一切変更しない。
`SALT_RECEIVE` の直接参照2箇所と、それに依存する6テストをすべて維持する。
テスト総数は433本のままである。

依存テストの前提作りを初期乱数状態の直接指定へ変える作業は #88 で行う。

## 7. 実装順序

1. `src/sim/sim_rng.gd` を新設し、既存式を同じ演算順序で移す。
2. `sim_cpu.gd` に `SimRng` のpreloadを追加する。
3. `SimCpu._noise()` の本文だけを共通関数への委譲へ変える。
4. `SALT_RECEIVE` の現在の用途と #88 送りをコメントに記録する。
5. `hit_resolver.gd` に `SimRng` のpreloadを追加する。
6. `HitResolver._keyed_hash()` の本文だけを共通関数への委譲へ変える。
7. 2系列のキーとactor補正が変更されていないことをdiffで確認する。
8. テストとゴールデンを変更していないことをdiffで確認する。
9. Claude Codeへ引き渡し、フルテストの実行と合否判定を依頼する。

## 8. 合格条件

### ACCEPT-001: フルテスト

Claude Codeが次のフルテストを実行する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1
```

合格結果は次の完全一致である。

```text
433 tests, 0 failed
```

テストは削除しないため、本数も433本から変わってはならない。
本数が変わった場合は、統合範囲を逸脱した証拠として扱う。

### ACCEPT-002: 合成ゴールデンハッシュ

`tests/unit/test_sync.gd` の `GOLDEN_COMBINED_HASH` を変更せず、
次の値のまま `test_golden_hash_regression` が緑になること。

```text
6286455164936831101
```

挙動不変の変更なので、値が変わった場合は混合式、キー、salt、actor補正の
いずれかを変えてしまった証拠である。
新しい実測値へゴールデンを合わせてはならない。
原因を特定し、実装を正してから再判定する。

### ACCEPT-003: 重複式の解消

混合式の乗数 `2246822519` と `3266489917`、および3段のXOR・シフト処理は
`src/sim/sim_rng.gd` にだけ存在すること。

`SimCpu._noise()` と `HitResolver._keyed_hash()` には混合式を残さず、
それぞれ契約どおりの引数で `SimRng.keyed_hash()` を呼ぶこと。

### ACCEPT-004: 差分の限定

実装差分は次の3ファイルだけに限定する。

- `src/sim/sim_rng.gd`
- `src/sim/sim_cpu.gd`
- `src/sim/hit_resolver.gd`

テスト、`SimState`、設定データ、ゴールデンハッシュを変更してはならない。

## 9. 禁止事項

- saltの数値を変更しない。
- saltを連番へ整理しない。
- `SALT_RECEIVE` を削除しない。
- `SALT_AIR_SHOT = 8` を復活させない。
- キーの出所を統一しない。
- actor補正を共通化の名目で変更しない。
- `hash` という関数名を使わない。
- `class_name` を導入しない。
- 既存ラッパーや抽選呼び出しを整理しない。
- ゴールデンハッシュを書き換えない。
- テストを削除、追加、改変しない。
- #88 のステートフル乱数を先取りしない。
- `SimState` にフィールドを追加しない。
- `float` を使わない。
- `git stash` を使わない。
- pre-commitを `--no-verify` でスキップしない。
- Codexはコミットしない。
- CodexはフルテストまたはGodotを実行しない。

## 10. 停止条件

次のいずれかが起きた場合は、値やテストを合わせず作業を停止してClaude Codeへ報告する。

- 共通関数へ移しただけなのに乱数値が変わる。
- `last_hit_tick` と `s.tick` のどちらを渡すべきか既存コードから確定できない。
- 既存呼び出しが `actor + 1` 以外の追加補正を必要としている。
- `SALT_RECEIVE` または依存テストを変更しないと実装できない。
- テスト総数が433本から変わる。
- `GOLDEN_COMBINED_HASH` の変更が必要になる。
- `SimState` や #88 の設計へ変更範囲が広がる。

## 11. 引き渡し

Codexはコード実装後もフルテストを実行しない。
変更した3ファイルのdiffと、未確認事項があればその内容をClaude Codeへ渡す。

Claude Codeがフルテスト、テスト本数、合成ゴールデンハッシュを確認し、
すべての合格条件を満たした場合だけ #86 を完了と判定する。

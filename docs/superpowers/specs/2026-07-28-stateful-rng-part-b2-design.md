# #88b-2 残存抽選の乱数源切替 設計書

## 1. 文書情報

- 対象: issue #88 の part b-2
- 作成日: 2026-07-28
- 対象リポジトリ: Animal Spike
- 実装言語: Godot 4.6 / GDScript
- 数値方針: 整数のみ。`float` は使わない
- 前提:
  - #86 でキー付き混合式は `SimRng.keyed_hash()` に一本化済み
  - #88a で `SimState.rng` と `SimState.aitick`、原作式の毎 tick 更新、イベント更新を導入済み
  - #88b-1 で役割抽選だけをステートフル化済み
  - #88b-1 完了時点のテスト基準は 442 tests, 0 failed

この文書は実装契約である。
本文中の決定を実装者の判断で置き換えてはならない。
矛盾や未記載の抽選を見つけた場合は、推測せず停止条件に従う。

## 2. 目的

#88b-2 の目的は、役割抽選以外に残っている現行抽選の乱数源を、
原作調査で確定した二系列と、本作独自抽選向けの読み取り専用派生値へ切り替えることである。

切り替えるのは乱数源だけである。
次は一切変えない。

- 抽選の存廃
- 抽選が発火する条件
- 比較演算子
- 閾値
- `% 256`、`% 201`、`% 100` などの法
- CPU プロファイルの値
- キャラクター特性の値
- 抽選後に行う処理

CPU の出目と入力列は変わる。
これは、本作独自のキー付きノイズから、原作の生の `aitick` または新しい派生値へ
乱数源を移すことによる、意図した挙動変化である。

## 3. この設計の最重要原則

### RNG-SOURCE-001: 統合しない二系列

原作の `RND` と `aitick` は役目が違う。

- `aitick`
  - 打球イベントで更新される
  - 同じ打球を追っている間は固定される
  - 打球ごとに判断を固定したい抽選に使う
- `RND`
  - フェーズ判定より前に毎フレーム更新される
  - 停止中を含め、フレームごとに変わる
  - 毎フレーム振り直す判断に使う

原作に対応がある抽選は、原作が読む側の値をそのまま読む。
二系列を一つの値へまとめてはならない。

### RNG-SOURCE-002: 本作独自抽選

原作の抽選一覧に対応がない本作独自抽選は、
`aitick`、actor、用途 ID から作る読み取り専用派生値を使う。
`rng` は鍵へ含めない。

これは、現行 `_roll()` が `last_hit_tick` により保証している
「一つのタッチにつき一度だけ出目を決め、tick ごとには振り直さない」という
発火単位を維持するためである。

派生値の計算は、次を絶対に行わない。

- `s.rng` の更新
- `s.aitick` の更新
- `Simulation.tick()` の更新回数の変更
- 抽選の呼び出し順による消費

同じ状態、同じ actor、同じ用途 ID なら同じ値を返す。
呼び出してもグローバル状態は一切進まない。

### RNG-SOURCE-003: #84 と混ぜない

原作には CPU の狙いノイズや意図的ミスがないことは判明している。
しかし、その抽選を残すか廃止するかは #84 の仕様判断である。

#88b-2 では、現行抽選を削除しない。
確率を変えない。
発火条件を変えない。
乱数源だけを機械的に移す。

### RNG-SOURCE-004: 消費する抽選を増やさない

役割抽選は #88b-1 で実装済みの唯一の消費型抽選である。
#88b-2 の抽選はすべて読み取り専用である。

`advance_frame()`、`advance_hit()`、`advance_role_swap()`、
`advance_role_roll()` の呼び出しを追加してはならない。

## 4. 原作調査から来る事実

以下は `docs/tasks/88.md` と `docs/tasks/84.md` の原作調査から来る。

### ORIGINAL-001: 原作抽選は原則として読むだけ

役割抽選を除く原作の判定は、現在の `RND` または `aitick` を読むだけである。
抽選するたびに状態を進める方式ではない。
同じフレームでは複数 actor が同じ基礎値を見る。

### ORIGINAL-002: `aitick` 系

原作で `aitick` を使うことが確定している判定は次である。

- 攻撃球に対するレシーブ許可
- スパイクのジャンプ許可
- ブロックのジャンプ許可
- 難易度によって `aitick` 側を使う地上必殺技許可

これらは一つの打球に対する判断がフレームごとに反転しないための系列である。

### ORIGINAL-003: `RND` 系

原作で `RND` を使うことが確定している判定は次である。

- 特定の硬直を無視する判定
- 3 打目レシーブ許可
- 難易度によって `RND` 側を使う地上必殺技許可
- #88b-1 で移行済みの役割抽選

### ORIGINAL-004: 本作の現在地

今回列挙した現行抽選には、
役割抽選以外の ORIGINAL-003 に直接対応する呼び出し箇所がない。

したがって #88b-2 で生の `s.rng` へ切り替える現行箇所はゼロである。
これは移行漏れではない。
原作にあるからという理由だけで、新しい判定を追加してはならない。

硬直無視、3 打目レシーブ許可、地上必殺技許可の存廃と配置は #84 以降の仕事である。

### ORIGINAL-005: actor 項がないことの逆アセンブル確認

原作資料
`C:\work\PC98\vb2211-analysis\vb22-cpu-ai.asm`
の難易度ゲート `0x7F27` から `0x8071` を確認した。

プレイヤーごとの差が入るのは、入口で `P_skill+bx` を読む箇所だけである。

```asm
7f27  8a875c11         mov al, byte ptr [P_skill+bx]
7f2b  98               cwde
7f2c  e92301           jmp 0x8052
```

ここで選んだ難易度分岐の中では、グローバル `aitick` を直接 `AX` へ読み、
固定した法で割った余りだけを使う。
actor 番号、プレイヤー構造体オフセット、`bx`、`si` を
`aitick` へ加算・乗算・XOR する命令はない。

LEVEL 0 は一度の `aitick % 8` を、
攻撃球レシーブ、スパイクジャンプ、地上必殺技へ共通に書く。

```asm
7f30  b90800           mov cx, 8
7f33  a1b80e           mov ax, word ptr [aitick]
7f36  2bd2             sub dx, dx
7f38  f7f1             div cx
...
7f46  8846f0           mov byte ptr [bp - 0x10], al
7f49  8846f2           mov byte ptr [bp - 0x0e], al
7f4c  8846f4           mov byte ptr [bp - 0x0c], al
```

LEVEL 1 は用途ごとに法だけを変え、いずれも同じ `aitick` を直接読む。

```asm
; スパイクジャンプ: aitick % 2 == 0
7f7a  b90200           mov cx, 2
7f7d  a1b80e           mov ax, word ptr [aitick]
7f80  2bd2             sub dx, dx
7f82  f7f1             div cx
...
7f90  8846f2           mov byte ptr [bp - 0x0e], al

; 攻撃球レシーブ: aitick % 4 == 0
7f93  b90400           mov cx, 4
7f96  a1b80e           mov ax, word ptr [aitick]
7f99  2bd2             sub dx, dx
7f9b  f7f1             div cx
...
7fa8  8846f0           mov byte ptr [bp - 0x10], al

; ブロックジャンプ: aitick % 6 == 0
7fab  b90600           mov cx, 6
7fae  a1b80e           mov ax, word ptr [aitick]
7fb1  2bd2             sub dx, dx
7fb3  f7f1             div cx
...
7fc0  8846ee           mov byte ptr [bp - 0x12], al
```

LEVEL 2 は一度の `aitick % 3 < 2` を、
ブロック、攻撃球レシーブ、スパイクジャンプ、地上必殺技へ共通に書く。

```asm
7fca  b90300           mov cx, 3
7fcd  a1b80e           mov ax, word ptr [aitick]
7fd0  2bd2             sub dx, dx
7fd2  f7f1             div cx
7fd4  83fa02           cmp dx, 2
...
7fe0  8846ee           mov byte ptr [bp - 0x12], al
7fe3  8846f0           mov byte ptr [bp - 0x10], al
7fe6  8846f2           mov byte ptr [bp - 0x0e], al
7fe9  8846f4           mov byte ptr [bp - 0x0c], al
```

LEVEL 3 のブロック、スパイクジャンプ、攻撃球レシーブは抽選せず常時 1 である。

```asm
800c  c646ee01         mov byte ptr [bp - 0x12], 1
8010  b001             mov al, 1
8012  8846f2           mov byte ptr [bp - 0x0e], al
8015  8846f0           mov byte ptr [bp - 0x10], al
```

結論:

- 原作の `aitick` 系判定に actor を乱数項として混ぜる処理はない
- actor ごとの難易度差は `P_skill+bx` が選ぶ分岐と法にだけ現れる
- 同じ難易度、同じ `aitick` なら全 actor が同じ許可結果を見る
- sweet と attack が同じ `aitick` を読み、閾値だけで分かれる相関は原作準拠の帰結である

したがって CPU-RNG-004 / CPU-RNG-005 は、
actor を混ぜず生の `s.aitick` を読む設計で確定する。

## 5. 本作で決めること

以下は原作そのものではなく、決定論と本作独自抽選を両立するための本作側の設計である。

### PROJECT-001: 独自抽選の派生値

原作に対応がない抽選は、生の `rng` を消費しない。
現在の `aitick` を打球系列の状態として読み、
actor と用途 ID を加えた決定論的派生値を使う。

`rng` を混ぜると毎 tick 出目が変わり、
狙い位置とミス位置が毎フレーム揺れる。
それは #84 より先に抽選の実効性を変えるため禁止する。

### PROJECT-002: 現行用途 ID の維持

用途 ID には現行 salt 定数の値をそのまま使う。
値を変えない。
連番へ整理しない。
新しい用途 ID を発明しない。

### PROJECT-003: actor の維持

actor 項の意味も現行どおり維持する。

- `SimCpu`: 現行 `_roll()` が渡している `idx` をそのまま渡す
- `HitResolver`: 現行 `_keyed_hash()` と同じ `actor + 1` を渡す

`HitResolver` の `+ 1` を外してはならない。
actor の番号体系を統一する作業ではない。

## 6. 現行 salt 定数の契約

### 6.1 `src/sim/sim_cpu.gd`

| 定数 | 値 | #88b-2 の扱い |
|---|---:|---|
| `SALT_AIM` | 1 | 維持。派生値の用途 ID |
| `SALT_MISS` | 2 | 維持。派生値の用途 ID |
| `SALT_SWEET` | 3 | 維持。生の `aitick` へ移行後も削除しない |
| `SALT_RECEIVE` | 4 | 維持。#88b-3 までテスト専用契約を触らない |
| `SALT_SUPER` | 5 | 維持。派生値の用途 ID |
| `SALT_ATTACK` | 6 | 維持。生の `aitick` へ移行後も削除しない |
| `SALT_ROLE` | 7 | 維持。#88b-1 の未使用コメントを残す |

値 8 を追加または復活させてはならない。

### 6.2 `src/sim/hit_resolver.gd`

| 定数 | 値 | #88b-2 の扱い |
|---|---:|---|
| `SALT_MURA` | 23 | 維持。派生値の用途 ID |
| `SALT_TOSS_BAD` | 29 | 維持。派生値の用途 ID |
| `SALT_RECEIVE_SCATTER` | 31 | 維持。派生値の用途 ID |

## 7. 抽選箇所の全数対応表

### 7.1 数え方

意味のある抽選箇所は、最終的に法や閾値へ値を渡す呼び出し単位で数える。

- `SimCpu`: `_roll()` の実呼び出し 6 箇所
- `HitResolver`: `_scatter()` 1 箇所、`_trait_roll_pct()` 2 箇所

合計は 9 箇所である。

`_noise()` から `_roll()`、
`_keyed_hash()` から `_scatter()` / `_trait_roll_pct()` という
ヘルパー内部の委譲は、重複して抽選数へ数えない。
ただし 8 節で全呼び出し経路を別に固定する。

### 7.2 `SimCpu` の 6 箇所

行番号は設計時点の `src/sim/sim_cpu.gd` を基準とする。
実装で周辺行が動いた場合は関数名と salt 名で照合する。

| ID | 呼び出し箇所 | salt | 現行の用途 | 原作対応 | 新しい系列 |
|---|---|---|---|---|---|
| CPU-RNG-001 | `sim_cpu.gd:690`、空振り判断内の `_roll()` | `SALT_MISS` | 来球時の意図的な振り遅れ | なし。原作に意図的ミスはない | 派生値 |
| CPU-RNG-002 | `sim_cpu.gd:767`、落下予測位置への `_roll()` | `SALT_AIM` | 予測着地点 x への狙いノイズ | なし。原作に狙いノイズはない | 派生値 |
| CPU-RNG-003 | `sim_cpu.gd:772`、レシーブ位置への `_roll()` | `SALT_MISS` | レシーブ位置の意図的ずらし | なし。原作に意図的ミスはない | 派生値 |
| CPU-RNG-004 | `sim_cpu.gd:998`、`_sweet_ok()` 内の `_roll()` | `SALT_SWEET` | ジャストレシーブ・精密移動・芯打ちの許可 | 攻撃球レシーブ許可とスパイク許可に対応。両方とも `aitick` 系 | 生の `aitick` |
| CPU-RNG-005 | `sim_cpu.gd:1006`、`_attack_ok()` 内の `_roll()` | `SALT_ATTACK` | 攻撃サーブ・攻撃ジャンプ・スパイク許可 | スパイクジャンプ許可に対応 | 生の `aitick` |
| CPU-RNG-006 | `sim_cpu.gd:1064`、`_should_use_flame()` 内の `_roll()` | `SALT_SUPER` | 空中で炎打撃を選ぶ | なし。原作表の地上必殺技許可とは別条件 | 派生値 |

### 7.3 `SALT_SWEET` の判断

`_sweet_ok()` は複数の呼び出し側に共有されている。

- 精密な空中移動
- 精密ジャンプ計画
- ジャストレシーブ計画
- 芯での空中打撃

原作の表で直接対応する名称は一つではないが、
関係する攻撃球レシーブ許可とスパイク許可はいずれも `aitick` 系である。
一つの打球を追っている間に許可が反転しないという役割も一致する。

したがって共有抽選を分割せず、`_sweet_ok()` 全体を生の `aitick` へ移す。
呼び出し側ごとに別抽選へ分解すると、抽選の単位と発火構造が変わるため禁止する。

### 7.4 `SALT_ATTACK` の判断

`_attack_ok()` は攻撃サーブ、攻撃ジャンプ、スパイクに共有されている。
許可抽選の中心的な原作対応はスパイクジャンプ許可であり、系列は `aitick` である。

攻撃サーブだけを別の派生抽選へ分割すると、
現行で共有している抽選を二つに増やし、発火構造と用途 ID の契約を変えてしまう。
それは「乱数源だけを機械的に移す」という #88b-2 の範囲を超える。

したがって共有抽選を分割せず、`_attack_ok()` 全体を生の `aitick` へ移す。
攻撃サーブの存廃や原作準拠の許可条件は #84 で判断する。

### 7.5 `HitResolver` の 3 箇所

行番号は設計時点の `src/sim/hit_resolver.gd` を基準とする。

| ID | 呼び出し箇所 | salt | 現行の用途 | 原作対応 | 新しい系列 |
|---|---|---|---|---|---|
| HIT-RNG-001 | `hit_resolver.gd:93`、`_mura_power_pct()` 内 | `SALT_MURA` | `TRAIT_MURA` の威力 50/100/150% | 原作抽選一覧に対応なし | 派生値 |
| HIT-RNG-002 | `hit_resolver.gd:103`、`_toss_apex_pct()` 内 | `SALT_TOSS_BAD` | `TRAIT_TOSS_BAD` の低いトス判定 | 原作抽選一覧に対応なし | 派生値 |
| HIT-RNG-003 | `hit_resolver.gd:528`、地上レシーブ処理内 | `SALT_RECEIVE_SCATTER` | レシーブ速度の散らし | 原作抽選一覧に対応なし | 派生値 |

3 箇所は、許可抽選ではなく本作のキャラクター特性または物理散らしである。
`docs/tasks/88.md` と `docs/tasks/84.md` の原作抽選一覧には対応がないため、
すべて本作独自の読み取り専用派生値へ移す。

### 7.6 分類の集計

| 分類 | 箇所数 | ID |
|---|---:|---|
| 生の `aitick` | 2 | CPU-RNG-004, CPU-RNG-005 |
| 生の `rng` | 0 | なし |
| 読み取り専用派生値 | 7 | CPU-RNG-001〜003, CPU-RNG-006, HIT-RNG-001〜003 |
| 合計 | 9 | 全件 |

この集計が実装後の静的検査基準である。

## 8. ヘルパー呼び出し経路

### 8.1 `SimCpu`

設計時点の経路は次である。

```text
_noise(salt, key, actor)
  -> SimRng.keyed_hash(key, salt, actor)

_roll(salt, s, actor)
  -> _noise(salt, s.last_hit_tick, actor)
```

`_noise()` の本番外の利用と、
`SALT_RECEIVE` に依存する 6 本の既存テストは #88b-3 の範囲である。

#88b-2 では `_noise()` と `_roll()` を削除しない。
中身も変更しない。
今回対象の 6 本番呼び出しだけを新しい読み口へ移す。

派生値用に、最小のラッパーを `SimCpu` に追加する。

```gdscript
static func _derived_roll(salt: int, s, actor: int) -> int:
	return SimRng.derived_value(s.aitick, actor, salt)
```

CPU-RNG-001〜003 と CPU-RNG-006 は `_derived_roll()` を使う。

CPU-RNG-004 と CPU-RNG-005 は `s.aitick` を直接読む。
actor や salt を生の値へ混ぜてはならない。
比較式と法だけを現行どおり後段へ残す。

### 8.2 `HitResolver`

設計時点の経路は次である。

```text
_scatter(s, actor, salt)
  -> _keyed_hash(s, actor, salt) % 201 - 100

_trait_roll_pct(s, actor, salt)
  -> _keyed_hash(s, actor, salt) % 100

_keyed_hash(s, actor, salt)
  -> SimRng.keyed_hash(s.tick, salt, actor + 1)
```

`_scatter()` と `_trait_roll_pct()` の式と呼び出し側は変えない。
`_keyed_hash()` の委譲先と、その直前にある旧 `s.tick` 説明コメントだけを次へ変える。

```gdscript
return SimRng.derived_value(s.aitick, actor + 1, salt)
```

これにより HIT-RNG-001〜003 は同じ派生値契約へ一括して移る。
`actor + 1` は現行どおりであり、省略禁止である。

## 9. 派生値の厳密な定義

### DERIVED-001: 関数形

`src/sim/sim_rng.gd` に次を追加する。

```gdscript
static func derived_value(
		aitick: int, actor_term: int, purpose_id: int) -> int:
```

`class_name` は追加しない。
既存どおり呼び出し側の `preload("res://src/sim/sim_rng.gd")` を使う。

### DERIVED-002: 入力

入力の意味を次で固定する。

| 引数 | 意味 |
|---|---|
| `aitick` | 現在の打球系列を表す `SimState.aitick` |
| `actor_term` | 呼び出し側が現在使っている actor 項 |
| `purpose_id` | 現行 salt 定数の値 |

引数順を入れ替えてはならない。
`rng` を引数へ追加してはならない。

### DERIVED-003: 16 bit 正規化

`aitick` は関数内で `WORD_MASK` を適用する。

```gdscript
var aitick_word: int = aitick & WORD_MASK
```

これにより、キーは必ず `0x0000` から `0xFFFF` になる。
呼び出し側が正規化済みであることだけに依存してはならない。

### DERIVED-004: 混合

最終値は #86 の既存混合式へ委譲する。

```gdscript
return keyed_hash(aitick_word, purpose_id, actor_term)
```

乗数 `2246822519` と `3266489917` を複製してはならない。
この二つの乗数は `SimRng.keyed_hash()` にだけ置く。

### DERIVED-005: 出力を 16 bit に丸めない理由

16 bit に丸める対象はキーとして読む `aitick` である。
派生値はグローバル PRNG 状態ではなく、法へ渡す正のキー付き混合値である。

したがって出力は `keyed_hash()` と同じ非負 63 bit 範囲を保ち、
追加の `& WORD_MASK` は行わない。
これにより現行の `% 256`、`% 201`、`% 100` に渡す値域を不要に狭めない。

「16 bit の丸めを省かない」という契約は、
`aitick` に `WORD_MASK` を適用することで満たす。

### DERIVED-006: 副作用禁止

`derived_value()` は純粋関数である。

- `SimState` を引数に取らない
- 状態を書かない
- 既存 advance 関数を呼ばない
- 時刻や OS 乱数を読まない
- 呼び出し回数で結果を変えない

### DERIVED-007: `rng` を鍵に含めない理由

`rng` は毎 tick 更新される。
CPU-RNG-001〜003 は一つの来球について複数 tick 評価されるため、
`rng` を混ぜると同じ来球中に出目が変わる。

特に CPU-RNG-002 と CPU-RNG-003 は移動目標へ直接影響する。
毎 tick 出目が変わると、狙い位置が震えるか、異なる誤差を追い続けて
ノイズが平均化される。
どちらも現行の「一度読み違えた位置へ確信を持って向かう」と異なる。

現行 `last_hit_tick` に対応する新状態は、
打球イベントでのみ進む `aitick` である。
したがって独自抽選も `aitick` のみを時間キーにする。

## 10. 派生値の既知ベクトル

### VECTOR-001: 計算規則

`keyed_hash()` の現行式を次の順序で評価する。

```text
key = aitick & 0xFFFF
z0 = i64(key + purpose_id * 1000003 + actor_term * 998244353)
z1 = i64((z0 ^ asr(z0, 16)) * 2246822519)
z2 = i64((z1 ^ asr(z1, 13)) * 3266489917)
z3 = i64(z2 ^ asr(z2, 16))
result = z3 & 0x7FFFFFFFFFFFFFFF
```

- `i64(x)`:
  - `x mod 2^64` でラップする
  - bit 63 が 1 なら `x - 2^64` として符号付き 64 bit に戻す
- `asr(x, n)`:
  - 符号ビットを複製する算術右シフト
  - Python の負整数に対する `>>` と同じ
- 各乗算の直後に `i64` を適用する
- 最終マスクの前までは符号付き 64 bit として扱う
- 係数 `1000003` と `998244353` を、別の係数へ置き換えてはならない

独立計算に使う Python 相当コードは次である。

```python
MASK64 = (1 << 64) - 1
SIGN64 = 1 << 63

def i64(value):
    value &= MASK64
    return value - (1 << 64) if value >= SIGN64 else value

def derived_value(aitick, actor_term, purpose_id):
    key = aitick & 0xFFFF
    z = i64(key + purpose_id * 1000003 + actor_term * 998244353)
    z = i64(i64(z ^ (z >> 16)) * 2246822519)
    z = i64(i64(z ^ (z >> 13)) * 3266489917)
    z = i64(z ^ (z >> 16))
    return z & 0x7FFFFFFFFFFFFFFF
```

### VECTOR-002: 中間値

次の表の `z0`〜`z3` は、各段階を 64 bit 二の補数の 16 進表記で示す。
bit 63 が 1 の値は、次の算術右シフトでは負数として扱う。

| aitick | actor | purpose | key | z0 | z1 | z2 | z3 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `0000` | 0 | 1 | `0000` | `00000000000F4243` | `0007FB7F692BC954` | `292B2DF4EDA94E62` | `292B04DFC05DA3CB` |
| `ABCD` | 2 | 1 | `ABCD` | `00000000770FEE12` | `3E48C40745B00E7B` | `E2BDA9EA50E52CCF` | `1D424B57F90F7C2A` |
| `FFFF` | 4 | 31 | `FFFF` | `00000000EFDA0620` | `7D79A735E5E00736` | `2272A88D2DBD48DE` | `22728AFF85306563` |
| `ABCD` | 3 | 1 | `ABCD` | `00000000B28FEE13` | `5D68F1EF2EEB2484` | `B418334BBE8831A9` | `4BE787538DC38F21` |
| `ABCD` | 2 | 2 | `ABCD` | `00000000771F3055` | `3E50F7F5F0B88766` | `546C6BFD14E9BC9A` | `546C3F917F14A873` |

### VECTOR-003: 契約テストへ固定する値

| aitick | actor_term | purpose_id | expected |
|---:|---:|---:|---:|
| `0x0000` | 0 | 1 | `2966470138605183947` |
| `0xABCD` | 2 | 1 | `2108330416775593002` |
| `0xFFFF` | 4 | 31 | `2482199174690399587` |
| `0xABCD` | 3 | 1 | `5469489065395195681` |
| `0xABCD` | 2 | 2 | `6083307090805565555` |

16 bit 正規化も次で固定する。

```text
derived_value(0x1ABCD, 2, 1)
==
derived_value(0xABCD, 2, 1)
==
2108330416775593002
```

この値は、上記 Python 実装と、別実装の JavaScript `BigInt.asIntN(64, ...)`
による計算が全件一致している。

Codex は Godot を実行しない。
Claude Code は設計書の承認・ピン留め前に Godot 上の
`SimRng.keyed_hash(aitick & WORD_MASK, purpose_id, actor_term)` と全件突き合わせる。
1 件でも異なれば設計書を承認せず、計算過程から原因を特定する。

既知ベクトルは実装結果へ合わせて変更してはならない。

## 11. 呼び出し単位の変更契約

### CHANGE-CPU-001: 意図的空振り

CPU-RNG-001 の `_roll(SALT_MISS, s, idx)` を
`_derived_roll(SALT_MISS, s, idx)` へ置き換える。

後続の法、比較、入力生成は変更しない。

### CHANGE-CPU-002: 着地点ノイズ

CPU-RNG-002 の `_roll(SALT_AIM, s, idx)` を
`_derived_roll(SALT_AIM, s, idx)` へ置き換える。

ノイズ幅、符号、位置計算は変更しない。

### CHANGE-CPU-003: レシーブ位置ずらし

CPU-RNG-003 の `_roll(SALT_MISS, s, idx)` を
`_derived_roll(SALT_MISS, s, idx)` へ置き換える。

CPU-RNG-001 と同じ actor・用途 ID・状態なら同じ基礎値になる現行契約を維持する。

### CHANGE-CPU-004: sweet 許可

CPU-RNG-004 は `_roll()` をやめ、`s.aitick` を生で読む。

```gdscript
s.aitick % 256 < p[P_SWEET]
```

実際には現行コードの式を保ち、左辺の乱数源だけを置き換える。
`keyed_hash()`、actor、salt を混ぜてはならない。

### CHANGE-CPU-005: attack 許可

CPU-RNG-005 は `_roll()` をやめ、`s.aitick` を生で読む。

```gdscript
s.aitick % 256 < current_threshold
```

`current_threshold` は説明用の名前であり、
実装では現行の難易度分岐と閾値式を一文字も変えない。

### CHANGE-CPU-006: 炎打撃

CPU-RNG-006 の `_roll(SALT_SUPER, s, idx)` を
`_derived_roll(SALT_SUPER, s, idx)` へ置き換える。

地上判定、空中判定、閾値、返り値は変更しない。

### CHANGE-HIT-001: 三つの HitResolver 抽選

`_keyed_hash()` の入力を `s.tick` から
`s.aitick`、salt、actor の派生値へ変更する。

次は変更しない。

- `_mura_power_pct()` の 50/100/150
- `_toss_apex_pct()` の確率と返却率
- `_scatter()` の `% 201 - 100`
- `_trait_roll_pct()` の `% 100`
- `_mura_power_pct()` と `_toss_apex_pct()` にある現行の閾値比較
- 三つの salt
- actor の `+ 1`

## 12. 期待する挙動変化

### BEHAVIOR-001: sweet / attack

変更前は、`last_hit_tick`、salt、actor をキー付き混合した値だった。
変更後は、生の `aitick` を全 actor が共有して読む。

結果として次が起こる。

- 同じ打球中は許可結果が固定される
- actor ごとのハッシュ差はなくなる
- salt ごとのハッシュ差はなくなる
- sweet と attack はそれぞれの法と閾値で同じ `aitick` を解釈する
- 打球時の `aitick += rng` 後に次の系列へ移る

これは原作の「打球ごとに固定する判断」への意図した移行である。

同じ難易度・同じ `aitick` では CPU 4 体が同じ許可結果を見る。
sweet と attack も独立した乱数ではなく、
同じ `aitick % 256` を異なる閾値で解釈する相関した判定になる。
この独立性の喪失は ORIGINAL-005 で確認した原作準拠の帰結であり、不具合ではない。

### BEHAVIOR-001A: `aitick == 0` の特異点

`reset_match(seed = 0)` 直後は `aitick == 0` である。
打球イベントがまだ一度も起きていなければ、
CPU-RNG-004 / CPU-RNG-005 が読む値は `0 % 256 == 0` になる。

したがって次が成立する。

- 閾値 0: `0 < 0` は偽なので失敗
- 正の閾値: `0 < threshold` は真なので成功

多くのテストが seed 0 と打球前状態を使うため、
この条件では sweet / attack が成功側へ偏り、
誤った前提でも緑になる可能性がある。

これは生の `aitick` へ移すことから必然的に生じる想定内の挙動変化である。
ハッシュを足して特異点を消してはならない。
テストは `aitick` を明示的に設定し、初期値へ暗黙依存してはならない。

### BEHAVIOR-002: AIM / MISS / SUPER

変更前は `last_hit_tick` をキーにしていたため、同じ打球中は原則固定だった。
変更後は現在の `aitick`、actor、用途 ID を読む。

`aitick` は毎 tick 進まないため、
同じ打球を追っている間は現行どおり出目が固定される。
特に AIM / MISS の目標位置は tick ごとに震えない。

炎打撃も、打球が起きない期間は同じ出目を維持する。
これは現行 `last_hit_tick` 鍵と同じ発火単位である。

この三種は原作に対応がない本作独自抽選である。
原作に存在しない機能を生の `RND` 消費へ変えるのではなく、
打球単位と決定論を保った読み取り専用派生値へ移すという本作側の決定である。

### BEHAVIOR-003: HitResolver の三抽選

変更前は `s.tick`、salt、actor を混合していた。
変更後は `s.aitick`、salt、actor を混合する。

同じ打撃確定時点で同じ状態なら同じ結果になる。
ロールバックで `aitick` が復元されれば、同じ結果を再現できる。
抽選自体は状態を進めない。

設計時点の `src/sim/hit_resolver.gd` で、評価順は次のとおりである。

- `_scatter()`: 528 行
- `_toss_apex_pct()`: 538 行
- `_mura_power_pct()`: 594 行
- 通常打撃の `advance_hit()`: 646 行

三抽選はすべて `advance_hit()` より前に、打撃直前の `aitick` を読む。
三つは地上レシーブ、地上トス、攻撃という排他的な分岐内にある。
`_apply_hit()` の呼び出しは 308 行の一箇所であり、
同じ打撃内で更新前後の値を混在させる経路はない。

ブロック側は 727 行で `advance_hit()` を行うが、この経路には三抽選がない。
この順序を変更してはならない。

### BEHAVIOR-004: 許容理由

この挙動変化は、次の契約を同時に満たすため許容する。

- 原作対応の判断を原作と同じ時間系列へ戻す
- 本作独自抽選を決定論的かつ読み取り専用にする
- 抽選の存廃、確率、発火条件を #84 より先に変えない
- 役割以外の抽選を消費型にしない

出目が変わること自体を不具合と扱って旧出目へ合わせてはならない。
一方、発火回数、法、閾値、後続処理が変わった場合は不具合である。

## 13. 契約テスト先行の二段階方式

実装は #88b-1 と同じ二段階で行う。
本番コードと契約テストを同時に書き終えてはならない。

### STEP-001: ピン留め照合

Claude Code が承認時に示した設計書の行数と SHA-256 を照合する。
一致しなければ停止する。

設計書は実装完了まで編集しない。

### STEP-002: 契約テストだけを書く

本番コードを変更する前に、次の 5 本を追加する。
新規ファイルは `tests/unit/test_stateful_rng_part_b2.gd` とする。

1. `test_derived_value_matches_fixed_vectors_and_masks_aitick`
2. `test_derived_value_separates_actor_and_purpose`
3. `test_cpu_original_lotteries_read_raw_aitick`
4. `test_cpu_remake_lotteries_use_read_only_derived_aitick`
5. `test_hit_resolver_lotteries_use_read_only_derived_aitick`

既存 442 本は削除も改名もしない。
この段階の静的総数は 447 本になる。

### TEST-B2-001: 既知ベクトルと 16 bit 正規化

`test_derived_value_matches_fixed_vectors_and_masks_aitick` は 10 節の
先頭 3 ベクトルと、上位ビットを含む同値性を固定する。

固定するもの:

- `aitick` の 16 bit マスク
- `keyed_hash()` への引数順
- 出力を 16 bit に切らないこと

### TEST-B2-002: actor と用途の分離

`test_derived_value_separates_actor_and_purpose` は 10 節の actor 違いと用途違いを固定する。

同じ入力を繰り返して同じ値になることも確認する。
時刻、呼び出し回数、外部乱数へ依存しないことを固定する。

### TEST-B2-003: 原作対応抽選は生の `aitick`

`test_cpu_original_lotteries_read_raw_aitick` は
`_sweet_ok()` と `_attack_ok()` を直接検査する。

各判定について次を固定する。

- `aitick` と閾値の境界で結果が決まる
- `rng` を変えても結果が変わらない
- `last_hit_tick` を変えても結果が変わらない
- actor を変えても結果が変わらない
- 判定前後で `rng` と `aitick` が変化しない

`aitick == 0` の特異点は初期値へ暗黙依存せず、テスト内で明示的に 0 を代入する。
少なくとも次の四つを直接固定する。

- `_sweet_ok()`
  - `P_TIQ < 3`、`P_SWEET == 0`: `0 < 0` なので失敗
  - `P_TIQ < 3`、`P_SWEET > 0`: 成功
- `_attack_ok()`
  - `AB_ATTACK` 有効、`P_TIQ == 0`: 閾値 0 なので失敗
  - `AB_ATTACK` 有効、`P_TIQ == 1`: 閾値 64 なので成功

同じプロファイルと同じ `aitick` を CPU 4 体へ与え、
actor ごとの差がないことも固定する。
sweet と attack が同じ `aitick % 256` を読むことを直接確認し、
二抽選の独立性を期待するテストにしてはならない。

プロファイルは、現行の名前付き index とフラグを使い、
閾値境界が明確になる最小の整数値を設定する。
既存 preset のゲームプレイ値を書き換えてはならない。

### TEST-B2-004: CPU 独自抽選の派生値

`test_cpu_remake_lotteries_use_read_only_derived_aitick` は
`SALT_AIM`、`SALT_MISS`、`SALT_SUPER` を表形式で検査する。

各用途について次を固定する。

- `_derived_roll(salt, s, idx)` が
  `SimRng.derived_value(s.aitick, idx, salt)` と一致する
- 同一状態で繰り返すと同じ値
- `rng` だけを変えても値が変わらない
- `aitick` だけを変えると選んだ検査ベクトルでは値が変わる
- actor を変えると選んだ検査ベクトルでは値が変わる
- salt を変えると選んだ検査ベクトルでは値が変わる
- 呼び出し前後の `SimState` の全 int 配列が一致する

最後の条件により、派生値がグローバル状態を進めないことを固定する。

### TEST-B2-005: HitResolver の派生値

`test_hit_resolver_lotteries_use_read_only_derived_aitick` は
`SALT_MURA`、`SALT_TOSS_BAD`、`SALT_RECEIVE_SCATTER` を表形式で検査する。

固定するもの:

- `_keyed_hash(s, actor, salt)` が
  `SimRng.derived_value(s.aitick, actor + 1, salt)` と一致する
- `rng` だけを変えても値が変わらない
- `_scatter()` は派生値へ現行の `% 201 - 100` だけを適用する
- `_trait_roll_pct()` は派生値へ現行の `% 100` だけを適用する
- 10、90、30 との比較は `_mura_power_pct()` と `_toss_apex_pct()` に残る
- 3 呼び口の前後で `SimState` が変化しない

`actor + 1` を忘れた実装はこのテストで落とす。

### STEP-003: 契約テストの赤を確認する

契約テストを書いた時点で止め、Claude Code へ第 1 報を渡す。
Codex はテストも Godot も実行しない。

Claude Code が対象テストを実行し、赤の理由が次だけであることを確認する。

- `SimRng.derived_value()` が未定義
- `SimCpu._derived_roll()` が未定義
- `_sweet_ok()` / `_attack_ok()` がまだ `_roll()` を読む
- `HitResolver._keyed_hash()` がまだ `s.tick` を読む

構文エラー、ロードエラーの連鎖、無関係な既存テストの赤が出た場合は本番実装へ進まない。

### STEP-004: 第 1 段階の承認

Claude Code が STEP-003 の失敗理由を承認してから、本番実装へ進む。
承認前に本番コードを書いてはならない。

## 14. 本番実装手順

### STEP-005: `SimRng.derived_value()` を追加

9 節の関数形、16 bit マスク、委譲をそのまま実装する。
既存関数の式を変更しない。

### STEP-006: `SimCpu` の 6 箇所を切り替える

1. `_derived_roll()` を追加する
2. CPU-RNG-001〜003 を派生値へ変更する
3. CPU-RNG-004〜005 を生の `s.aitick` へ変更する
4. CPU-RNG-006 を派生値へ変更する

`_noise()` と `_roll()` は残す。
`SALT_RECEIVE` と `SALT_ROLE` のコメント・値を維持する。

### STEP-007: `HitResolver` の 3 箇所を切り替える

`_keyed_hash()` の委譲先を DERIVED-004 の契約へ変える。
直前のコメントも、`s.tick` が原作の `RND` 系列に対応するという旧説明から、
`aitick` の読み取り専用派生値であることと `actor + 1` を維持する説明へ更新する。
`_scatter()`、`_trait_roll_pct()` とその呼び出し側を変更しない。

### STEP-008: 静的検査

次を検索し、結果を全件報告する。

1. `SimRng.derived_value` の本番呼び出し
   - `SimCpu._derived_roll()` の 1 箇所
   - `HitResolver._keyed_hash()` の 1 箇所
   - それ以外はない
2. `_derived_roll()` の本番呼び出し
   - CPU-RNG-001〜003 と CPU-RNG-006 の 4 箇所
3. `_roll()` の本番呼び出し
   - 今回対象の 6 箇所からはゼロ
   - テスト専用契約以外に残存があれば停止
4. 生の `s.aitick` を使う新規判定
   - `_sweet_ok()` と `_attack_ok()` の 2 箇所だけ
5. 生の `s.rng` を使う新規判定
   - ゼロ
   - `derived_value()` の引数にも `rng` がない
6. advance 系関数の差分
   - ゼロ
7. salt 定数の値
   - 1〜7、23、29、31 が全て不変
8. 乗数
   - `2246822519` と `3266489917` は `sim_rng.gd` の既存 `keyed_hash()` にだけ存在
9. `% 256`、`% 201`、`% 100`
   - 現行箇所と式が不変
10. `float` と `class_name`
    - 新規差分にない

集計は 7.6 節の 2 / 0 / 7 / 合計 9 と一致しなければならない。

## 15. 既存テストの扱い

### TEST-PRESERVE-001: 削除禁止

既存 442 本は一つも削除しない。
テスト関数名を変えて本数をごまかしてはならない。

### TEST-PRESERVE-002: SALT_RECEIVE 依存 6 本

`SALT_RECEIVE` と、これを使って `last_hit_tick` を探索・固定する既存 6 本には触らない。
この是正は #88b-3 のテスト三層工程で行う。

ただし、この 6 本が #88b-2 で赤くならないことは健全性の証拠にならない。
緑のまま通過することを想定する。

`tests/unit/test_cpu_offense_receive.gd:19` の
`_select_successful_roll()` は、次の処理を行っている。

```gdscript
for key in 900:
	if SimCpu._noise(SimCpu.SALT_RECEIVE, key, actor) % 256 < threshold:
		s.last_hit_tick = key
		return
```

しかし本体 `_sweet_ok()` が引く salt は `SALT_SWEET` であり、
`SALT_RECEIVE` ではない。
別用途の成功キーを `last_hit_tick` へ設定しても、
sweet 成功は保証されない。

Godot 実測は `docs/remaining-tasks.md` のコミット `6ceff0a` に記録済みである。
実際に使う PRESET_MAX / actor 1 では、
選択キー 0、`P_SWEET == 191` に対して
`SALT_SWEET` の出目は 227 であり、判定は失敗する。

つまり、現行テストは「ジャストレシーブが成功する状態」を作れていないのに緑である。
#88b-2 で sweet を生の `aitick` へ移しても、
元から効いていない前提なので赤にならない可能性が高い。

#88b-2 の合格判定は、この 6 本の緑ではなく次で行う。

- TEST-B2-003 が生の `aitick` と閾値の契約を直接固定している
- `_sweet_ok()` の本番コードが `_roll()` を呼ばない
- `aitick == 0`、閾値 0、正の閾値を明示入力で検査している
- actor 間の相関を明示入力で検査している

### TEST-PRESERVE-002A: #88b-3 への申し送り

#88b-3 では 900 個のキー探索を撤去する。
新しい sweet 判定は `aitick % 256 < threshold` なので、
テストが必要とする初期乱数状態を直接与える。

- 成功させる場合:
  - `threshold > 0` を確認する
  - `s.aitick = 0` など、`aitick % 256 < threshold` を満たす値を明示代入する
- 失敗させる場合:
  - `s.aitick % 256 >= threshold` となる値を明示代入する
- seed 探索、actor ごとの探索、`last_hit_tick` の偽装は行わない

この置換により真の `_sweet_ok()` が初めて効き始め、
現在緑のシナリオテストが赤くなる可能性がある。
それは検査が壊れたのではなく、偽の前提が消えて真の検査が復活した証拠である。

その場合、期待値を緩める、ジャスト条件を外す、検査範囲を減らすことで通してはならない。
シナリオの本来の期待結果と、新しい sweet 成功時の実挙動を照合し、
実装不具合か古い期待値かを Claude Code と判断してから直す。

依存 6 本が初期 `aitick` の直接指定へ移った後、
`SALT_RECEIVE`、`_noise()`、`_roll()` を同じ #88b-3 で撤去する。
#88b-2 ではこの撤去を先取りしない。

### TEST-PRESERVE-003: 旧乱数源を直接固定するテスト

フルテストで、今回対象の salt に対して
`last_hit_tick` や `s.tick` を種として直接固定する既存テストが赤くなった場合は、
次の順で判定する。

1. そのテストが抽選結果ではなくゲームプレイ契約を検査しているか確認する
2. 前提だけを新しい `aitick` へ置き換えられるか確認する
3. 検査意図、期待するゲームプレイ結果、テスト本数を変えずに済む場合だけ候補差分を提示する
4. Claude Code の明示承認前に変更しない

期待値を弱める、検査範囲を減らす、抽選を迂回することは禁止する。

これは #88b-3 の全体整理を先取りしないための停止ゲートである。

### TEST-PRESERVE-004: 原作相関とゼロ特異点による既存テストの赤

既存テストが次を暗黙または明示に期待して赤くなる場合は、
STOP-007 の「説明不能な非ゴールデン赤」には分類しない。

- sweet と attack が独立したハッシュ出目になる
- 同じ難易度でも actor ごとに許可結果が異なる
- seed 0 / 打球前でも sweet または attack が散らばる

これらは ORIGINAL-005 と BEHAVIOR-001A で説明できる想定内の帰属先である。

明示的な旧乱数源契約テストは、
生の `aitick`、actor 間の共通結果、sweet / attack の相関を検査する契約へ更新する。
テスト本数と検査強度は維持する。

ゲームプレイシナリオの前提だけが旧出目へ依存している場合は、
テストの意図に必要な `aitick` を明示設定する。
seed 0 の偶然へ依存させない。

シナリオ自体が「デフォルト seed での CPU 判断」を固定している場合は、
新しい実挙動が設計どおりであることを確認して期待結果を更新する。
いずれも Claude Code が差分と帰属を確認してから変更する。

相関やゼロ特異点で説明できない赤は STOP-007 とする。

## 16. 合格ゲートとゴールデン再採取

### ACCEPT-001: テスト総数

既存 442 本と新規 5 本の合計 447 本を一つも削除せず、最終的に全件緑にする。

### ACCEPT-002: 先に非ゴールデンを全件緑

ゴールデン再採取前に、状態ハッシュ固定検査群を除く 445 本が全件緑でなければならない。

状態ハッシュ固定検査群は、現時点で正確に次の 2 本である。

- `tests/unit/test_sync.gd.test_golden_hash_regression`
- `tests/unit/test_refactor_characterization.gd.test_hit_chain_second_golden`

この 2 本以外に 1 本でも赤があれば、ゴールデンへ触らない。
原因を特定し、乱数源切替の契約どおりか確認してから進む。

### ACCEPT-003: 二つの赤が同一原因

2 本の実測値を採取する前に、両方の差が #88b-2 の乱数源切替だけから生じたことを確認する。

確認項目:

- 新規契約テスト 5 本が緑
- 既存非ゴールデン 440 本が緑
- 状態フィールドの追加・削除がない
- serialize / restore / clone / state hash の構造変更がない
- 抽選の法・閾値・発火条件に差分がない
- 役割抽選に差分がない

### ACCEPT-004: 一回だけ再採取

ACCEPT-002 と ACCEPT-003 を満たした後、
Claude Code が 2 本を同一の原因による一つのゴールデン検査群として再採取する。

次を両方更新する。

- `GOLDEN_COMBINED_HASH`
- `test_hit_chain_second_golden` の 7 要素配列

片方だけを更新してはならない。
値を予測して書いてはならない。
実測値を採取する。

各箇所のコメントまたはコミット記録に次を残す。

- 旧値
- 新値
- 理由: #88b-2 で残存抽選の乱数源を切り替えた
- 再採取前の結果: 447 本中、状態ハッシュ固定検査群 2 本だけが赤
- 再採取後の結果: 447 tests, 0 failed

Codex はゴールデンを更新しない。
Claude Code がゲート確認後に行う。

### ACCEPT-005: 最終フルテスト

再採取後に Claude Code がフルテストを再実行し、
次を確認する。

```text
447 tests, 0 failed
```

テスト実行時に `SCRIPT ERROR summary` が出ていないことも確認する。

Codex はフルテストも Godot も実行しない。

### ACCEPT-006: CPU 挙動変化の説明可能性

差分レビューで、CPU 入力列の変化を次のどれかへ全件帰属できること。

- sweet / attack が生の `aitick` を読むようになった
- `aitick == 0` かつ正の閾値で sweet / attack が必ず成功する特異点
- sweet / attack が同じ値を共有し、actor 間の独立性も失う原作準拠の相関
- AIM / MISS / SUPER が現在の `aitick`、actor、用途 ID の派生値を読むようになった
- HitResolver の三抽選が `s.tick` ではなく現在の `aitick`、actor、用途 ID の派生値を読むようになった

これらで説明できない変化があれば停止する。
旧ゴールデンへ合わせるために式を調整してはならない。

## 17. 停止条件

次のいずれかに触れたら、その場で変更を止めて Claude Code へ報告する。

### STOP-001: 対応表にない抽選

`_noise`、`_roll`、`_keyed_hash`、`_scatter`、`_trait_roll_pct` の
本番呼び出しで、7 節の 9 箇所にないものを見つけた場合。

勝手に分類しない。

### STOP-002: 原作系列との矛盾

許可された資料から、CPU-RNG-004 または CPU-RNG-005 が
`aitick` 以外を使うと判明した場合。

### STOP-003: 新用途 ID が必要

現行抽選を分割しないと実装できず、新しい salt / 用途 ID が必要になった場合。

#88b-2 では発明しない。

### STOP-004: 消費が必要

役割以外の抽選で `rng` または `aitick` を進める必要が生じた場合。

### STOP-005: 既存条件の変更が必要

乱数源を差し替えるだけではコンパイルまたは契約を満たせず、
閾値、法、比較、発火条件、後続処理の変更が必要になった場合。

### STOP-006: SALT_RECEIVE 依存

禁止された既存 6 本または `SALT_RECEIVE` の値・定義を触る必要が出た場合。

### STOP-007: 非ゴールデンの赤

新規契約テスト以外の非ゴールデンテストが赤くなり、
単なる旧乱数源のテスト前提ではなくゲームプレイ期待値が異なる場合。

ただし TEST-PRESERVE-004 の actor 間相関、sweet / attack 相関、
`aitick == 0` 特異点へ具体的に帰属できる赤は想定内であり、STOP-007 ではない。
その手順で処理しても説明できない赤だけを停止対象とする。

### STOP-008: 状態機構への変更

SimState フィールド、serialize、restore、clone、state hash、
reset_match、reset_rally、rollback 経路の変更が必要になった場合。

#88b-2 は既存状態を読むだけである。

### STOP-009: テスト総数の不一致

実装前 442、本設計の追加後 447 という総数と一致しない場合。

### STOP-010: ゴールデン群の増加

再採取前の赤が、指定した状態ハッシュ固定検査群 2 本以外にも出た場合。

## 18. やってはいけないこと

- 抽選を削除する
- 抽選を新設する
- 確率を変える
- 発火条件を変える
- 法や比較演算子を変える
- salt の値を変える
- salt を連番へ整理する
- `SALT_RECEIVE` を削除する
- `SALT_ROLE` を削除する
- SALT_RECEIVE 依存 6 本を直す
- テスト三層への全体整理を始める
- 役割抽選を変更する
- 派生値の計算でグローバル状態を進める
- 派生値の `aitick` 16 bit マスクを省く
- 派生値の鍵へ `rng` を追加する
- actor の意味を変える
- `HitResolver` の `actor + 1` を外す
- 乗数を複製する
- `last_hit_tick` と `s.tick` の旧キーへ結果を合わせる
- 状態フィールドを追加する
- seed の入口を変更する
- `reset_match` 以外で seed を入れる
- 既存テストを削除する
- ゴールデン以外が赤いまま再採取する
- 旧ゴールデンへ合うよう式を調整する
- `float` を使う
- `class_name` を使う
- `git stash` を使う
- pre-commit をスキップする
- `--no-verify` を使う
- Codex がコミットする
- Codex がフルテストを実行する
- Codex が Godot を起動する

## 19. 変更対象

本番実装で変更する対象は次に限定する。

- `src/sim/sim_rng.gd`
  - `derived_value()` を追加
- `src/sim/sim_cpu.gd`
  - `_derived_roll()` を追加
  - 対応表の 6 箇所だけ乱数源を切り替える
- `src/sim/hit_resolver.gd`
  - `_keyed_hash()` の委譲先を切り替える
  - 直前の乱数源説明コメントを新契約へ合わせる
- `tests/unit/test_stateful_rng_part_b2.gd`
  - 契約テスト 5 本を新設

フルテストで TEST-PRESERVE-003 / TEST-PRESERVE-004 に該当する赤が出た場合に限り、
Claude Code の明示承認後、該当する既存テストの前提または旧乱数源契約を更新対象へ追加できる。

- 検査意図、検査強度、テスト本数は維持する
- `aitick` を明示設定し、seed 0 の偶然へ依存させない
- actor 間相関と sweet / attack 相関は ORIGINAL-005 の契約へ更新する
- SALT_RECEIVE 依存 6 本は、この条件付き追加の対象外である

ゲート通過後に Claude Code が変更する対象:

- `tests/unit/test_sync.gd`
  - `GOLDEN_COMBINED_HASH` の再採取
- `tests/unit/test_refactor_characterization.gd`
  - `test_hit_chain_second_golden` の配列再採取

Godot が新規 `.gd` に対応する `.uid` を自動生成した場合は、
Claude Code が生成物を確認してコミット対象へ含める。
Codex は `.uid` を手で作らない。

上記と、Claude Code が個別承認した条件付き既存テスト以外の
ファイル変更が必要になった場合は停止する。

## 20. 実装引き渡し

Codex の第 1 報は契約テストだけを書いた時点で行う。

第 1 報に含めるもの:

1. 追加した 5 テストのファイル名と関数名
2. 各テストが固定する契約
3. 静的テスト総数が 447 本になること
4. `git diff --stat`
5. 本番コードへまだ触れていないこと
6. テストと Godot を実行していないこと

Claude Code が STEP-003 を承認後、Codex は本番実装を行う。

第 2 報に含めるもの:

1. `git status --porcelain`
2. `git diff --stat`
3. 変更した全ファイルの diff
4. 7 節の全数対応表に対する実装結果
5. 生の `aitick` へ移した 2 箇所
6. 生の `rng` へ移した箇所がゼロであること
7. 派生値へ移した 7 箇所
8. `derived_value()` の本番呼び出し全件
9. advance 系への差分がゼロであること
10. salt の値が不変であること
11. `SALT_RECEIVE` 依存 6 本へ触れていないこと
12. 状態機構へ差分がないこと
13. 停止条件に触れた点
14. 未確認・未検証事項
15. フルテスト、Godot、コミット、ゴールデン再採取を行っていないこと

## 21. 完了の定義

#88b-2 は、次をすべて満たしたときだけ完了する。

- 9 箇所の分類が 2 / 0 / 7 と一致する
- 原作対応 2 箇所が生の `aitick` を読む
- 本作独自 7 箇所が読み取り専用派生値を読む
- 本作独自派生値の時間キーが `aitick` だけであり、`rng` を含まない
- sweet / attack の actor 間相関と `aitick == 0` 特異点を契約テストが固定している
- 役割以外の抽選が状態を進めない
- 抽選の存廃、確率、発火条件が不変
- salt の値が不変
- 既存 442 本が一つも削除されていない
- 新規 5 本を含む 447 本が最終的に全件緑
- 状態ハッシュ固定検査群以外を先に全件緑にした
- 二つの状態ハッシュ固定値を同一原因として一回だけ再採取した
- CPU 挙動変化を ACCEPT-006 の帰属先へ全件帰属できる
- 10 節の既知ベクトルを Claude Code が Godot 実測と突き合わせた
- #84 と #88b-3 の仕事を先取りしていない
- Claude Code が実測結果を確認した
- Codex はコミットしていない

この設計の要点は一つである。
原作対応の判断は原作と同じ時間系列へ戻し、
原作にない判断は状態を消費しない決定論的派生値へ隔離する。
乱数源は変える。抽選の意味は変えない。

# CPUがラリーを組み立てられない問題の実測診断

2026-07-25。ユーザー実機フィードバック「CPUがあまりにも弱くなった / ネット際は
相手陣地に高いトスしかしない / CPU同士でトスを続けてるだけで一向に試合が進まない /
ジャンプサーブしようとしてるけど失敗してる(自爆)」を受けた原因調査の実測記録。

## 測定方法

CPU同士の試合を1タッチずつ記録する使い捨て診断テストを書いて実行した。

- 診断テスト: `tests/unit/test_zz_trace_debug.gd` (コミットしない)
- 単体ランナー: `tests/run_one.gd` (コミットしない)
- 実行: `./tools/godot/Godot_v4.6-stable_win64_console.exe --headless --path . --script res://tests/run_one.gd -- test_zz_trace_debug.gd`
- 条件: 全員 STANDARD_CHAR(99)、`points_to_win=999`、1800tick(30秒)、同一プリセット同士

記録項目: tick / 打った選手 / 接地状態 / 入力キー / ボール座標 / 選手座標 /
打球後の速度(px/s) / タッチ数 / `ball_attack_kind`。得点発生も記録。

## 実測結果

### MAX vs MAX

```
touches=16 points=8 jumps=40
G_RECV=0 G_TOSS=8 A_SPIKE=8 A_TOSS=0 A_BLOCK=0
t  60 p0 G_TOSS in=A  bx= 24 by=292 px= 24 py=320 -> vx=  23 vy=-620 tch=0 atk=0
t 123 p0 A_SPIKE in=RDA bx= 97 by=278 px= 45 py=302 -> vx=2943 vy= 227 tch=1 atk=1
  == POINT 1-0 ==
t 284 p0 G_TOSS in=A  bx= 24 by=292 px= 24 py=320 -> vx=  22 vy=-738 tch=0 atk=0
t 360 p0 A_SPIKE in=RDA bx=108 by=283 px= 48 py=301 -> vx=3398 vy= 227 tch=1 atk=1
  == POINT 1-1 ==
（以下同型。8ラリーすべてサーブ2タッチで決着）
```

**全ラリーが「サーブトス → ジャンプサーブアタック → 即得点」の2タッチで終わる。**
レシーブ側が一度もボールに触れていない。8得点の内訳は、サーブが決まって得点する
ケースとサーブが自爆して相手に得点が入るケースが混在している(スコアが 1-0 → 1-1
→ 1-2 → 2-2 と、サーバー側が失点する回が含まれる)。

打点の高さに注目: `by=278`〜`283`。`net_top_y_px=275` なので**ネット上端より下**
(yは下向き正)。低い打点から 2900〜3400px/s の球を撃っている。

### NORMAL vs NORMAL

```
touches=24 points=0 jumps=6
G_RECV=0 G_TOSS=24 A_SPIKE=0 A_TOSS=0 A_BLOCK=0
t 178 p3 bx=282 px=273 -> vx= -62 vy=-650
t 247 p1 bx=168 px=183 -> vx=  70 vy=-697
t 321 p3 bx=253 px=265 -> vx= -62 vy=-712
t 396 p1 bx=178 px=183 -> vx=  58 vy=-713
（以下 x=183 と x=265 で永久に往復。1800tickで得点0）
```

**30秒で得点ゼロ、空中打撃ゼロ、ジャンプ6回のみ。**
p1(x≈183) と p3(x≈265) がネット(x=224)を挟んで永久にバンプを打ち合う。

### STRONG vs STRONG

実行時クラッシュで CPU の思考が停止する。

```
SCRIPT ERROR: Trying to return an array of type "Array" where expected
  return type is "Array[int]".
  at: _sweet_jump_plan (res://src/sim/sim_cpu.gd:285)
SCRIPT ERROR: Out of bounds get index '0' (on base: 'Array[int]')
  at: _decide_positioning (res://src/sim/sim_cpu.gd:701)
```

## 確定した根因

### 1. 三項式+配列リテラルの実行時型エラー (致命)

`src/sim/sim_cpu.gd:285`

```gdscript
return [-1, p.x] if best_delay == 999 else [best_delay, best_x]
```

関数 `_sweet_jump_plan` の戻り値型は `Array[int]` (sim_cpu.gd:229)。

**GDScript 4.6 では、三項式 (`A if cond else B`) のオペランドになった
配列リテラルは要素型を失い `Array` (untyped) になる。両辺とも純 int リテラルでも失敗する。**

最小再現 (`tests/unit/test_zz_ternary_probe.gd`、実行して確認):

```
pure(true)  = []   SCRIPT ERROR: Trying to return an array of type "Array"
pure(false) = []                 where expected return type is "Array[int]"
mixed(true) = []   同上 (型無しプロパティを混ぜた場合)
via_typed(*)= []   SCRIPT ERROR: Trying to assign an array of type "Array"
                                 to a variable of type "Array[int]"
split(true) = [-1, 7]   ← if/else に割った場合のみ正常
split(false)= [3, 2]
```

**したがって「型付き一時変数に入れてから返す」では直らない。if/else に割る必要がある。**

#### 訂正の記録

本書の初版は「`best_delay == 999` の経路でのみ落ちる」「`p.x` が Variant だから」
と書いていた。**両方とも誤り。** 最小再現で反証された。
条件分岐に関係なく毎回落ちる。原因は Variant 混入ではなく三項式そのもの。

#### 影響範囲 (初版の想定より遥かに広い)

- `_sweet_jump_plan` は**呼ばれるたびに必ず `[]` を返す**
- `_decide_positioning:701` の `plan[0]` が `Out of bounds get index '0'` になる
- GDScript のランタイムエラーは呼び出しフレームを中断するため、
  **`_decide_positioning` が丸ごと中断し、CPUの位置取りとジャンプ判断が消える**
- `src/sim/sim_state.gd:68` の既定値 `var cpu: int = 848543938514047` は
  `PRESET_MAX` (AB_SWEET を含む)。**既定のCPU全員が該当する**
- フルスイート実行時に SCRIPT ERROR が **10198行** (285で5099件、701で5099件) 出ていた

**これが「CPUがあまりにも弱くなった」の直接原因。**

MAXプリセットのトレースで表面化しなかったのは、8ラリー全部がサーブ2タッチで
決着し `_decide_positioning` の該当行に一度も到達しなかったため
(発火ゲート: AB_ATTACK + 接地 + `s.last_touch_team == team` + `s.touches < max_touches` + AB_SWEET)。

`] if 〜 else [` の形は src 全体で `sim_cpu.gd:285` の1箇所のみ。

### 1b. テストがランタイムエラーを構造的に見逃す (中)

- `tests/run_tests.gd:44` の `checks_run == 0` 防御は
  「最初の check より前に死んだ場合」しか効かない。
  ランタイムエラーは最内フレームだけを中断して既定値を返すので、
  sim の奥で吸収され、テスト本体は最後まで走って PASS になる
- `run_tests.ps1:13` の SCRIPT ERROR grep は `$code -eq 0` で門番されている。
  **実テストが落ちて exit 1 のときは grep 自体が走らない**
- `_sweet_jump_plan` は未コミット改修で追加された新規関数で、
  **直接呼ぶテストが1件も存在しない**。「過去に全緑」の報告はこの関数が無い時点のもの

### 2. 地上レシーブが狙いを持たず、ネットを越えてしまう (致命)

`src/sim/hit_resolver.gd:429-432`

```gdscript
else:
    # 下レシーブは既存どおり制御不能になり得る受け軌道。
    desired_vy = -cfg.bump_up_speed
    desired_vx = dir * cfg.bump_fwd_speed
    p.hit_kind = 0
```

`bump_up_speed = 520px/s`、`bump_fwd_speed = 40px/s`、さらに入射速度の30%が
反発として加算される (`hit_inertia_pct = 30`)。

- 滞空時間 ≈ `2 * 520 / 1150` ≈ 0.9秒
- 前進距離 ≈ `(40 + 入射vx*0.3) * 0.9` ≈ 実測で約70px

**打点がネット(x=224)から約70px以内だと、レシーブしたボールが必ず相手コートへ
渡る。** CPUは落下点予測 (`_receive_target_x`) の位置に立つため、相手のバンプが
ネット際に落ちれば自分もネット際に立ち、そこから打つとまた越える。
**自己維持ループが成立し、3タッチ(レシーブ→トス→アタック)が永久に組めない。**

原作は通常ヒットが `vx = (目標x - 現在x) / 滞空時間` で狙った着弾点へ飛ばす。
原作のレシーブがこの式を通るかは調査中
(`docs/reference/original-vb22-controls-vs-current.md` の未解決1・2)。

### 3. ジャンプサーブがネット上端より低い打点で撃たれる

MAX同士の実測で、打点 `by=278`〜`283` に対し `net_top_y_px=275`。
サーブ打撃の前にネット通過の事前検査 (`_clears_net` 相当) が入っているか
未確認。`sim_cpu.gd` の `_decide_serve` の `attack_serve` 経路を調査中。

### 4. 空中で触ったボールは必ず敵陣へ飛ぶ (構造)

`hit_resolver.gd` の空中トス分岐は `air_target_x()` を使い、これは
9マス体系の定義どおり後ろ/なし/前のすべてが敵陣のゾーンを返す。
**空中から自陣へつなぐ手段が物理的に存在しない。**
設計会仕様 `2026-07-20-controls-drive-gauge-damage-design.md` の1節が
これを既知の懸念として明記している:

> 懸念として記録: この体系では空中から自陣へつなぐ手段がない。

## 修正後の実測 (2026-07-25、クラッシュ修正 + サーブのIN_JUMP保持を適用後)

適用した修正:

1. `sim_cpu.gd:285` の三項式を if/else の早期returnに割った
2. `decide()` の PHASE_SERVE 分岐に上昇中の `IN_JUMP` 保持を追加
   (空中 AND 上昇中 AND 打撃入力でない、の3条件)
3. `run_tests.ps1` の SCRIPT ERROR 検出を終了コードに関わらず動くようにした

### フルスイート

```
FAIL  test_cpu.gd.test_sweet_jump_plan_returns_two_values_when_plan_exists
FAIL  test_cpu_offense_receive.gd.test_max_cpu_converts_high_team_toss_to_just_attack
FAIL  test_sync.gd.test_golden_hash_regression
----
355 tests, 3 failed
SCRIPT ERROR summary: 0 occurrence(s)
```

**SCRIPT ERROR が 10198行 → 0件。**

### MAX vs MAX の変化

| 指標 | 修正前 | 修正後 |
|---|---|---|
| タッチ種別 | `G_RECV=0 G_TOSS=8 A_SPIKE=8 A_TOSS=0` | `G_RECV=10 G_TOSS=5 A_SPIKE=10 A_TOSS=9` |
| サーブの打点 | `py=302` (床320から18px) | `py=186` (床から**134px**) |
| スパイク横速度 | 2943 px/s | **956 px/s** |
| ラリーの形 | 全て「サーブ→即得点」の2タッチ | レシーブ→アタック→トスの応酬 |

3タッチのラリーが連続で回るようになった:

```
t1423 p0 G_RECV
t1475 p0 A_SPIKE tch=2 atk=2   (atk=2 = BALL_ATTACK_JUST)
t1483 p1 A_TOSS  tch=3
t1514 p2 G_RECV
t1540 p2 A_SPIKE tch=2
t1570 p0 G_RECV
t1620 p0 A_SPIKE tch=2 atk=2
t1659 p2 G_RECV
t1709 p2 A_SPIKE tch=2 atk=2
```

サーブ修正の因果は予測どおりだった: ジャンプが戻る → 打点が上がる →
`toss_aim_vx` の除数 (床までの落下tick数) が伸びる → 横速度が約1/3に落ちる。

### NORMAL vs NORMAL は未解決のまま

```
G_RECV=0 G_TOSS=24 A_SPIKE=0 A_TOSS=0 A_BLOCK=0
```

無限バンプ往復が継続。**当然の結果**で、NORMAL は AB_SWEET を持たないため
クラッシュを踏んでおらず、その問題は根因2 (レシーブが狙いを持たない物理) と
根因3 (CPUの立ち位置にネット距離下限が無い) にある。
フェーズ1の変更 (`2026-07-25-cpu-rebuild-design.md`) が要る。

### `_sweet_jump_plan` の健全性確認

修正で初めて正常動作するようになった未検証コードなので、返り値を直接実測した
(`tests/zz_plan_probe.gd`、コミットしない)。芯半径9px、高さ160px、静止球、
プレイヤー x=176:

```
横距離 | plan[0](離陸待ちtick) | plan[1]着弾x
   0px |    0    | 176
  20px |    4    | 196
  40px |   12    | 216
  80px |   24    | 256
 160px |   -1    | 176   (到達不能の番兵)
 300px |   -1    | 176
```

**横距離に応じて離陸待ちが単調に伸び、届かない球は番兵を返す。関数は正常。**
真上の球で `plan[0] == 0` (今すぐ跳ぶ) になるのは正しい挙動である
(歩いて移動する必要がないため)。高さ 80/120/160/200px、ボール vy 0/±4、
半径 reach/sweet45 を振っても、ボールが真上にある限り 0 だった。

解析が警告した「芯会合計画が過剰にヒットしてCPUが地上で待ち続ける膠着」は
発生していない。

### ネットすり抜けの実測

`tests/zz_net_probe.gd` (コミットしない) で計測。ネット帯は 207..241px (幅34px)。

修正**前**の MAX同士では、ネット上端 (275) より下を通りながら帯を1tickで
跨ぐ事象が実在した:

```
t130 x:195->244 y:287->292 step=49px flight=1
t592 x:248->200 y:287->292 step=48px flight=1
```

**49px/tick の球が34pxの帯を1tickで跨いでいた。** ネット判定が点サンプルのため。
修正後は横速度が 956px/s (約16px/tick) に落ちたため発生しなくなった。

**ただし根本 (点サンプル判定) は残っている。** 将来また速い球を出すと再発する。
フェーズ2-3 の掃引判定は「今すぐ要る」ではないが、**塞いだ問題ではない**ことを記録しておく。

## ユーザーの方針 (2026-07-25)

> CPUの強さは後回しにしようってしたけど、せめて試合をまともにできるCPUにしてほしい。
> いっかい強さ（弱・普通・強い・最強）の使い分けなくしていいから
> まともにプレイできるCPUにしてくれませんか？

難易度段階(`PRESET_WEAK` / `NORMAL` / `STRONG` / `MAX`)の作り分けは一旦捨てて、
3タッチのラリーが回る単一プロファイルを作ることを優先する。

## 関連タスク

- #62 原作EXEのCPU実装とGAME LEVELの逆アセンブル確認 (実施中)
- #65 sim_cpu.gd の実行時クラッシュ修正
- #66 難易度段階を廃し単一の「まともなCPU」を作る
- #67 ジャンプサーブの自爆を止める
- #68 レシーブ構えポーズの表示 (下ボタン)

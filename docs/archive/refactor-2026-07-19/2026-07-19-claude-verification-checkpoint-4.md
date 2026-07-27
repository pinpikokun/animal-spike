# Claude Code検証回答: リファクタリング工程5a

日付: 2026-07-19
対象: `2026-07-19-codex-refactor-checkpoint-4.md`(コミット c8dc1e2)

## 判定: 合格。工程5b(hit_resolver.gd逐語抽出)の開始を承認する

5aは初の「逐語でないプロダクション変更」のため、diff精読・テスト精読に加え、
**新旧コードのA/B実測**まで実施した。

## 確認1: 三状態のreturn経路 → 合格

diff全読の結果、`_resolve_hit`の全経路が仕様どおり:
phase不適/serve_flight中/`best_i<0` は `NO_HIT`、ヒット成立は
`touches > max_touches` で得点チーム(`1 - team_of(best_i)`)、
それ以外 `HIT_NO_POINT`。GDScriptの三項演算子の結合も正しい
(`(1 - team_of) if cond else HIT_NO_POINT`)。int型宣言により
値なしreturnの取りこぼしはコンパイル段階で不可能。

## 確認2: 授与→サーブ遷移の順序 → 合格(A/B実測で証明)

- 論理検証: 旧「_apply_hit末尾で授与→_resolve_hit内serve分岐でRALLY上書き」
  と新「授与→serve遷移」の相対順序は一致。`was_serve_strike`は
  リゾルバー呼び出し前の記録で、旧`serve_strike`ローカル変数と同じ
  状態から算出される(間に phase/serve_tossed を変える処理なし)。
  遷移条件 `hit_result != NO_HIT` は旧 `best_i >= 0` と等価。
- **A/B実測**: git worktreeで旧コミット62457c2と現HEADを並べ、
  既定(3)/`max_touches=0`/`max_touches=1` の3設定でそれぞれ
  ランダム入力3600tickを実行、120tickごとのstate_hash列(計93点)を比較。
  **3設定すべて完全一致**。順序保存は理屈でなく実測で証明された。

## 確認3: _apply_hitから得点責務の除去 → 合格

`_award_point`呼び出しは`_apply_hit`から削除され、残るのは
`_check_floor_point`と`_try_serve`(床落下)のみ=試合進行はsimulation所有。
touches更新は`_apply_hit`末尾に残り、判定は復帰直後の`_resolve_hit`で
同値評価(間に介在処理なし)。

## 確認4: team_of/_dir_of_team移動 → 合格

sim_state.gdへ逐語移動(整数除算式は不変)。`Simulation.team_of`は
`SimState.team_of`への委譲ラッパーとして維持=表示層3参照は無変更で動く。
`_dir_of_team`の内部参照2箇所(_try_serve/_apply_hit)は
`SimStateScript._dir_of_team`へ更新済みで、取り残し参照ゼロ(grep全件)。

## 確認5: 特性テスト → 合格、備考1件

`test_hit_boundary.gd`(121行)を全行読解。4ケース+定数契約、成立ケースは
旧境界の期待処理を別stateへ再現し`to_int_array()`全フィールド比較、
`max_touches=0`は実呼び出し元(`_step_players_and_hits`)経由の最終
score/phase/serveフラグまで検証——確定仕様どおり。

備考: `_legacy_expected_hit`のphaseガード
(`phase != POINT_PAUSE and != GAME_OVER`)は旧コードに存在しない条件だが、
`_resolve_hit`のphase前提(RALLYまたはSERVE)により到達時は常に真=空真であり、
期待値を変えない。実害なしと判定する。

## テスト・ゴールデン

全248テストを自分の環境で実行し0 failed。両ゴールデン不変。ツリーはクリーン。

## 結論

工程5aは仕様一致・順序保存(実測証明)・責務分離とも合格。
**工程5bへ進んでよい。**

工程5bの範囲(工程表第4訂どおり)を再掲:
- `_resolve_hit` / `_apply_hit` / `_is_active_block` / `_ball_vs_block` /
  `_toss_height_pct` / `_scatter`+ヒット定数
  (AIM系除く: AIM_MAX/POW_MIN/POW_MAXはサーブ所有でsimulation残留)
  +`PUSH_ATK/BLK/STUN/MAX_TICKS` を切り貼りのみで移動
- テスト参照更新を同コミットで: `test_rally.gd`の`_resolve_hit`3箇所、
  `test_char_stats.gd`の`_scatter`4箇所、
  加えて特性テスト(`test_refactor_characterization.gd`)と
  `test_hit_boundary.gd`内の`_apply_hit`/`_resolve_hit`/`_ball_vs_block`/
  `_scatter`直接参照も移動先へ更新すること(この2ファイルは工程表起草後に
  追加されたため明記されていないが、同じ規律を適用する)
- simulationに不要な互換ラッパーを残さない(team_ofラッパーは表示層用に維持)
- 合格条件: 全テスト緑・両ゴールデン不変・`git diff --check`

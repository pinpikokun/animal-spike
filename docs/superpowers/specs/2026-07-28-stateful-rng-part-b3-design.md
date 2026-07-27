# #88b-3 乱数テスト三層化と旧乱数源撤去 設計書

## 1. 文書情報

- 対象: issue #88 の part b-3
- 作成日: 2026-07-28
- 対象リポジトリ: Animal Spike
- 実装言語: Godot 4.6 / GDScript
- 基準:
  - #88b-2 はコミット `fe9246d` で完了
  - #88b-2 完了時点は 447 tests, 0 failed
  - ゴールデン規約の更新はコミット `e31d6bd`
- この文書は設計契約である。書き上げただけでは実装を開始しない。
- Claude Code が全文を査読し、行数と SHA-256 を承認・ピン留めした後だけ実装へ進む。
- Codex はコミット、テスト実行、Godot 実行、ゴールデン再採取を行わない。

## 2. 目的

#88b-3 の目的は次の二つである。

1. 乱数に関係するテストを、実ゲーム処理をどこまで通すかによって三層へ整理する。
2. #88b-2 後も残っている旧乱数源の偽の前提と、そこからしか呼ばれない入口・用途 ID を撤去する。

本段は乱数アルゴリズム、確率、CPU 判断、打撃物理、ゲームプレイ結果を変更する段ではない。
テストを健全にしてから死んだ入口を撤去する。

## 3. 原作由来の事実と本作で決めたこと

### ORIGINAL-B3-001: 原作由来の事実

#88b-2 で確定した原作由来の事実を引き継ぐ。

- sweet 許可と attack 許可は、生の `aitick` を読む。
- 原作のこれらの判定は actor を乱数項へ混ぜない。
- 同じ `aitick` を読む sweet と attack には相関がある。
- これらの判定は読み取り専用であり、判定するために乱数状態を進めない。
- 役割抽選は別系統であり、`rng` を消費する。

この段で原作対応式を変更してはならない。
式の唯一の出所は次である。

- `src/sim/sim_cpu.gd::_sweet_ok()`
- `src/sim/sim_cpu.gd::_attack_ok()`
- `src/sim/sim_rng.gd`
- `src/sim/simulation.gd::reset_rally()`

### PROJECT-B3-001: 本作で決めたこと

次は原作そのものではなく、本作のテスト設計と保守方針である。

- 乱数テストを三層へ分ける。
- 三層の境界は、実ゲーム処理をどこまで通すかで決める。
- 本作独自抽選は `aitick`、actor、用途 ID の読み取り専用派生値を使う。
- salt の用途 ID は連番へ詰めない。
- 廃止した用途 ID は欠番として予約し、再利用しない。
- テスト前提を作るための seed 探索、900 回探索、`last_hit_tick` 偽装を禁止する。
- まずテストの偽の緑を直し、その後で死んだ入口を撤去する。
- #88b-3 では固定値を一つも再採取しない。

## 4. 三層の定義

### LAYER-001: 第1層 PRNG 単体

対象は `SimRng` の純粋関数だけである。

持ち込んでよいもの:

- 整数入力
- 既知ベクトル
- 16 bit 正規化と折り返し
- 同じ入力に対する再現性
- actor 項と用途 ID の分離
- 呼び出し回数に依存しないこと

持ち込んではならないもの:

- `SimState`
- `SimCpu`
- `HitResolver`
- `Simulation`
- CPU プロファイル
- 物理状態
- ゲームシナリオ

この層は「乱数を使ったゲーム結果」を検査しない。
関数が純粋で、既知入力から既知出力を返すことだけを検査する。

### LAYER-002: 第2層 抽選契約

対象は、乱数値をゲーム上の抽選へ変換する直接契約である。

明示入力にするもの:

- `aitick`
- actor
- 用途 ID
- CPU プロファイルまたはキャラクター特性

直接検査するもの:

- 読む乱数源
- actor 補正
- 用途 ID の分離
- `% 256`
- `% 201`
- `% 100`
- 閾値と境界
- 読み取り専用か消費型か
- 同じ入力に対する再現性

禁止:

- 都合のよい seed を探してシナリオを成立させる
- 900 個など任意上限で成功キーを探索する
- `last_hit_tick` を乱数キーとして偽装する
- `s.tick` を乱数キーとして回す
- 物理結果から間接的に抽選契約を推測する
- 本番と同じヘルパーで期待値を再計算し、壊れた実装と一致させる

`test_scatter_stream_snapshot` はこの層である。
「ゴールデン」は層ではなく、固定値で契約を留める検査形式である。

10% / 80% / 10% と 30% の検査もこの層である。
これは統計的な品質検査ではない。
`% 100` の全結果と閾値の対応を全域で検査する抽選法の契約である。

現在の消費型役割抽選は、消費を確認するために `SimState` と
`Simulation.reset_rally()` が必要なので第3層で検査する。
第2層へ消費型であるかの偽の単体入口を作らない。

### LAYER-003: 第3層 シナリオ

対象は、実ゲーム処理を通った結果である。

次のいずれかを通すテストはこの層へ置く。

- `Simulation.tick()`
- `Simulation.step()`
- `SimCpu.decide()`
- `HitResolver._apply_hit()`
- `HitResolver._ball_vs_block()`
- ラリー開始、打撃、CPU 判断、着地までの実処理

検査対象:

- CPU 入力列
- CPU の位置取り
- ジャストレシーブやアタックサーブの成立
- 打球速度と軌道
- むらっけ倍率が実打撃へ一度だけ乗ること
- 乱数状態の更新順
- 同期とロールバック

乱数状態は明示設定する。
「デフォルトがたまたま成功する」「tick を変えれば散る」という前提は禁止する。

### LAYER-004: 三層の外に置く補助単体

乱数に隣接していても、乱数抽選を検査しない単体テストは三層へ無理に入れない。

- `SimState` のシリアライズと `state_hash()` は状態同期単体である。
- `toss_vy_for_apex_pct()` と `apex_height()` の関係は物理単体である。
- `test_hit_chain_second_golden` は物理・状態遷移の固定スナップショットである。

三層へ押し込むために責務を混ぜてはならない。

## 5. テスト配置

### TEST-FILE-001: 第1層の配置

`tests/unit/test_sim_rng.gd` を第1層の唯一の配置先にする。

現行 `tests/unit/test_stateful_rng_part_b2.gd` の次の二本を移す。

- `test_derived_value_matches_fixed_vectors_and_masks_aitick`
- `test_derived_value_separates_actor_and_purpose`

既存の固定ベクトルを変更してはならない。
移動は再採取ではない。

### TEST-FILE-002: 第2層の配置

`tests/unit/test_stateful_rng_part_b2.gd` を
`tests/unit/test_rng_draw_contracts.gd` へ改名する。

このファイルへ第2層のテストを集約する。
移動元で関数を削除し、移動先へ同名または本節で指定した新名で置く。
一時的に両方へ複製してテスト本数を増やしてはならない。

### TEST-FILE-003: 第3層の配置

第3層はドメイン別ファイルへ残す。

- CPU 判断: `tests/unit/test_cpu.gd`
- CPU 攻撃・レシーブ: `tests/unit/test_cpu_offense_receive.gd`
- 打撃: `tests/unit/test_hit.gd`
- CPU 対戦 KPI: `tests/unit/test_cpu_balance.gd`
- RNG 状態遷移: `tests/unit/test_stateful_rng_part_a.gd`
- 同期シナリオ: `tests/unit/test_sync.gd`

第3層を一つの巨大な RNG ファイルへ集めてはならない。
実ゲームのどの契約が壊れたかを、ファイル名から追える状態を保つ。

## 6. 既存 RNG 関連テストの全数分類

### 6.1 数え方

この表へ入れるテストは、次のいずれかを満たす追跡対象テストである。

- 乱数関数、乱数状態、用途 ID、閾値、分布、再現性を直接主張する
- 乱数分岐の成功または失敗をシナリオ前提にしている
- 固定乱数列または乱数を含む状態列を固定する

乱数経路を偶然通るだけで、乱数を検査対象にも前提にもしていない 447 本全部を
「乱数テスト」とは数えない。

`tests/zz_*.gd` は `.gitignore` 済みの使い捨てプローブなので対象に含めない。

### 6.2 第1層

| 現行ファイル | テスト | 実装後 | 判断 |
|---|---|---|---|
| `test_sim_rng.gd` | `test_advance_frame_matches_original_vectors` | 同じ | `SimRng` 既知ベクトル |
| `test_sim_rng.gd` | `test_advance_role_roll_matches_original_vectors` | 同じ | `SimRng` 既知ベクトル |
| `test_sim_rng.gd` | `test_word_and_aitick_updates_wrap_to_16_bits` | 同じ | 16 bit 丸め |
| `test_stateful_rng_part_b2.gd` | `test_derived_value_matches_fixed_vectors_and_masks_aitick` | `test_sim_rng.gd` へ移動 | 純粋関数の既知ベクトル |
| `test_stateful_rng_part_b2.gd` | `test_derived_value_separates_actor_and_purpose` | `test_sim_rng.gd` へ移動 | 純粋関数の入力分離と再現性 |

第1層は 5 本になる。

### 6.3 第2層

| 現行ファイル | 現行テスト | 実装後の名前 | 判断と変更 |
|---|---|---|---|
| `test_stateful_rng_part_b2.gd` | `test_cpu_original_lotteries_read_raw_aitick` | 同じ | 生 `aitick`、`% 256`、境界、読み取り専用 |
| `test_stateful_rng_part_b2.gd` | `test_cpu_remake_lotteries_use_read_only_derived_aitick` | 同じ | CPU 派生値、actor、用途 ID、読み取り専用 |
| `test_stateful_rng_part_b2.gd` | `test_hit_resolver_lotteries_use_read_only_derived_aitick` | 同じ | `actor + 1`、`% 201`、`% 100`、閾値 |
| `test_refactor_characterization.gd` | `test_scatter_stream_snapshot` | 同じ | 60 要素の固定抽選列。値を一つも変えず移動 |
| `test_char_stats.gd` | `test_scatter_is_deterministic` | `test_scatter_is_deterministic_and_separates_actor_and_purpose` | `s.tick` を捨て、明示 `aitick` で再現性と分離を検査 |
| `test_cpu.gd` | `test_miss_roll_is_stable_within_touch` | `test_derived_roll_is_stable_until_aitick_changes` | `_roll` と `last_hit_tick` 契約を、`_derived_roll` と `aitick` 契約へ置換 |
| `test_hit.gd` | `test_mura_roll_is_deterministic_and_has_10_80_10_distribution` | 同じ | 任意上限の探索を全 16 bit `aitick` の全域検査へ変更 |
| `test_hit.gd` | `test_toss_bad_is_exactly_30_percent_and_targets_70_percent_apex` の抽選部分 | `test_toss_bad_is_exactly_30_percent` | 30% 閾値だけを全域検査 |

第2層は 8 本になる。

### 6.4 第3層

| ファイル | テスト | 乱数に関する責務 |
|---|---|---|
| `test_stateful_rng_part_a.gd` | `test_reset_match_seeds_both_words_and_reset_rally_advances_rng_only` | 試合開始とラリー開始の状態遷移 |
| 同上 | `test_tick_advances_only_rng_once_during_normal_freeze_and_slow_ticks` | `Simulation.tick()` の消費回数 |
| 同上 | `test_hit_and_role_swap_update_aitick_in_fixed_order` | 実打撃と役割入替の更新順 |
| 同上 | `test_reset_rally_consumes_two_role_rolls_in_team_order` | チーム順の消費型抽選 |
| `test_cpu.gd` | `test_rally_roles_are_deterministic` | 明示 seed から保存した role roll のラリー内不変と次ラリー更新 |
| `test_cpu_offense_receive.gd` | `test_max_cpu_presses_receive_inside_predicted_timing_window` | sweet 成功を明示した CPU 入力 |
| 同上 | `test_max_cpu_can_press_timing_receive_while_reaction_is_frozen` | sweet 成功と反応遅延の優先順位 |
| 同上 | `test_max_cpu_just_receive_actually_fires` | sweet 成功から実打撃成立まで |
| 同上 | `test_max_cpu_keeps_walking_when_horizontal_range_hides_ellipse_miss` | sweet 成功済みでもリーチ外なら歩く |
| 同上 | `test_max_cpu_still_holds_receive_chord_when_current_x_can_reach` | sweet 成功済みでリーチ内なら構える |
| 同上 | `test_weak_cpu_does_not_prepare_just_receive` | sweet の出目が成功でも能力フラグが優先して拒否 |
| 同上 | `test_strong_cpu_uses_attack_serve_on_successful_profile_roll` | attack 成功を明示したサーブ判断 |
| 同上 | `test_max_cpu_uses_attack_serve` | 最強プロファイルの無条件許可 |
| 同上 | `test_max_cpu_converts_high_team_toss_to_just_attack` | `Simulation.step()` を通るジャスト打撃 |
| 同上 | `test_max_mirror_offense_and_just_receive_kpi` | 実入力列と実ラリーの煙感知器 |
| `test_hit.gd` | `test_ground_receive_scatter_is_deterministic` | 明示 `aitick` で実レシーブの横速度を再現 |
| 同上 | `test_only_toss_bad_can_produce_low_toss` | 明示成功・失敗 `aitick` で実トスを比較 |
| 同上 | `test_mura_applies_to_normal_just_and_attack_serve` | むらっけ倍率が実打撃へ一度だけ乗る |
| `test_cpu_balance.gd` | `test_max_beats_weak_both_sides` | 明示 seed の CPU 対 CPU 結果 |
| 同上 | `test_weak_mirror_match_finishes` | 明示 seed の進行停止検出 |
| `test_sync.gd` | `test_synctest_60_seconds` | 同一入力列の決定論 |
| 同上 | `test_golden_hash_regression` | 実ゲーム全状態の固定値 |
| 同上 | `test_endgame_reaches_game_over_deterministically` | 終局シナリオの決定論 |

### 6.5 三層の外

| ファイル | テスト | 分類 |
|---|---|---|
| `test_stateful_rng_part_a.gd` | `test_rng_fields_roundtrip_and_affect_hash` | RNG 状態のシリアライズ単体 |
| 同上 | `test_role_rolls_roundtrip_and_rollback_restore` | 状態保存・復元単体 |
| `test_cpu.gd` | `test_every_rally_has_exactly_one_attacker_per_team` | 抽選後の role 値を読む CPU 役割表単体 |
| 同上 | `test_rally_role_table_matches_all_nine_rolls` | 9 通りの CPU 役割表単体 |
| `test_hit.gd` | 新設 `test_toss_vy_for_apex_pct_targets_requested_height` | 乱数ではなく物理単体 |
| `test_refactor_characterization.gd` | 改名後 `test_hit_chain_physics_state_transition_golden` | 物理・状態遷移スナップショット |

`tests/unit/test_state.gd` と `tests/unit/test_state_coverage.gd` は、
全フィールド一般の検査であり RNG 固有テストではないため、この全数表には重複掲載しない。

### 6.6 第3層の明示 seed

乱数分岐または乱数状態が主張へ入る第3層では、デフォルト引数へ暗黙依存しない。

- `test_cpu_offense_receive.gd::_world()` は `reset_match()` へ seed 0 を明示して渡す。
- 同ファイルの `test_max_mirror_offense_and_just_receive_kpi` も seed 0 を明示する。
- `test_sync.gd::_run_once()` と `_run_endgame()` は
  `Chars.ROSTER` と seed 0 を明示して `reset_match()` へ渡す。
- `test_cpu_balance.gd::_run_match()` は引数 `seed` を `reset_match()` へ渡す。
- `test_hit.gd` の抽選依存シナリオは、本節で指定した `aitick` を直接設定する。

デフォルト seed 0 を明示 seed 0 へ書き換えただけで固定値が動いた場合は停止する。

## 7. 第2層の全域検査

### CONTRACT-ALL-001: 任意上限探索を廃止する

現行の 100000 回ループと「100 種見つかったら break」は seed 探索に見える。
これを次の全域検査へ置き換える。

1. `aitick` を 0 から `SimRng.WORD_MASK` まで一度ずつ明示設定する。
2. 各 `aitick` で `_trait_roll_pct()` の結果を得る。
3. `roll` ごとの結果を辞書へ保存する。
4. 同じ `roll` が再登場した場合、結果が前回と同じことを確認する。
5. 全 16 bit 入力を最後まで走査する。早期 `break` しない。
6. `roll` の集合が 0 から 99 の全域を覆うことを確認する。
7. `roll` ごとの結果を数え、むらっけは 10 / 80 / 10、
   トス下手は 30 / 70 であることを確認する。

これは都合のよい seed を探す操作ではない。
全入力を走査し、抽選法と閾値の写像を検査する操作である。

### CONTRACT-ALL-002: 独立した期待値

期待する 10 / 80 / 10 と 30 / 70 は、実装ヘルパーから再計算してはならない。
既存の固定期待値を維持する。

本番の `_mura_power_pct()` または `_toss_apex_pct()` を呼んで得た値を、
同じ関数をもう一度呼んだだけの値と比較して「正しい」としてはならない。

### CONTRACT-ALL-003: シナリオ用固定入力

第3層が seed を探索せず抽選結果を明示できるよう、
`test_rng_draw_contracts.gd` で次の actor 0 固定入力を直接固定する。

| 用途 | `aitick` | `_trait_roll_pct()` の期待値 | 第3層での用途 |
|---|---:|---:|---|
| `SALT_TOSS_BAD` | 0 | 10 | 低トス成功 |
| `SALT_TOSS_BAD` | 1 | 65 | 低トス失敗 |
| `SALT_MURA` | `0xABCD` | 96 | 150% むらっけ |

これらは現行 `SimRng.derived_value()` の式を独立計算した固定ベクトルである。
本番ヘルパーから実行時に期待値を作らない。
値が動いた場合は別の便利な入力を探さず、固定値の赤として停止する。

## 8. `SALT_RECEIVE` 依存 6 本の置換

### RECEIVE-001: 現行の偽の入口

`tests/unit/test_cpu_offense_receive.gd::_select_successful_roll()` は、
最大 900 個のキーを `SimCpu._noise()` へ渡し、成功キーを `s.last_hit_tick` へ入れる。

本体 sweet 判定は `src/sim/sim_cpu.gd::_sweet_ok()` であり、
現在は `s.aitick` を直接読む。
このヘルパーは本体が読む状態を作っていない。

### RECEIVE-002: 成功状態を直接作る式

`_sweet_ok()` の優先順位は本番コードを出所とする。

1. プロファイルの `P_TIQ` が最上位条件を満たす場合は無条件成功。
2. それ以外は `s.aitick % 256 < prof_byte(profile, P_SWEET)`。

成功させる手順:

1. 使用するプロファイルと actor を先に決める。
2. 無条件成功プロファイルでなければ、sweet 閾値が正であることを `check()` する。
3. `s.aitick = 0` を明示設定する。
4. `SimCpu._sweet_ok(s, actor, profile)` が真であることをシナリオ実行前に直接確認する。

失敗させる手順:

1. `P_TIQ` が無条件成功条件を満たさないことを確認する。
2. sweet 閾値を取得する。
3. `s.aitick` の下位 8 bit が閾値以上になる値を直接設定する。
4. `_sweet_ok()` が偽であることを直接確認する。

失敗値に便利な seed を探索してはならない。

### RECEIVE-003: 6 本の具体的対応

| テスト | 成功・失敗 | 置換 |
|---|---|---|
| `test_max_cpu_presses_receive_inside_predicted_timing_window` | 成功 | `_incoming_attack_world()` 内で `aitick` を明示し、`_sweet_ok()` 真を確認 |
| `test_max_cpu_can_press_timing_receive_while_reaction_is_frozen` | 成功 | 同上。`last_hit_tick = tick` は反応遅延の前提なので維持 |
| `test_max_cpu_just_receive_actually_fires` | 成功 | 同上。sweet 成功確認後に構えと実打撃を通す |
| `test_max_cpu_keeps_walking_when_horizontal_range_hides_ellipse_miss` | 成功 | ローカルで `aitick` を明示し、sweet 成功でも幾何条件が優先することを確認 |
| `test_max_cpu_still_holds_receive_chord_when_current_x_can_reach` | 成功 | `_incoming_attack_world()` の直接成功前提を使う |
| `test_weak_cpu_does_not_prepare_just_receive` | sweet 出目は成功 | `aitick` を成功側へ置き、`_sweet_ok()` 真を確認した上で、`AB_SWEET` 不在が拒否理由になるようにする |

弱 CPU のテストを sweet 失敗側へ置いてはならない。
それでは「能力がないから使わない」と「抽選に失敗したから使わない」を区別できない。

### RECEIVE-004: attack サーブの同時是正

同じ `_select_successful_roll()` は、強 CPU の attack 成功にも使われている。
`SALT_RECEIVE` 依存 6 本とは別の一箇所だが、ヘルパー撤去に必要なので第1段階で直す。

`_check_attack_serve()` は次の手順へ変える。

1. `s.aitick = 0` を明示設定する。
2. `SimCpu._attack_ok(s, 0, profile)` が真であることを確認する。
3. その後でジャンプ入力と空中打撃入力を検査する。

`_attack_ok()` の能力フラグ、最上位プロファイル、閾値の優先順位は本番コードを出所とし、
テスト側へ別実装を作らない。

### RECEIVE-005: ヘルパー撤去

すべての呼び出しを直接 `aitick` 設定へ移した後、
`_select_successful_roll()` を削除する。

削除後に次が残ってはならない。

- 900 回探索
- `SimCpu._noise()` のテスト呼び出し
- 乱数目的での `last_hit_tick` 代入
- `SALT_RECEIVE` のテスト参照
- `SALT_ATTACK` のテスト参照

## 9. sweet が初めて効いて赤になった場合

### SWEET-RED-001: 赤は握りつぶさない

テスト前提を直したことでシナリオが初めて本当に sweet 成功を通り、
現在緑のテストが赤になる可能性がある。

その赤は「テスト整理だから期待値を更新する」で処理してはならない。

### SWEET-RED-002: 判定手順

Claude Code は第1段階のフルテストで赤が出た場合、テストごとに次を行う。

1. テスト名、actor、プロファイル、設定した `aitick` を記録する。
2. シナリオ実行前の `_sweet_ok()` または `_attack_ok()` 直接確認が通っているか確認する。
3. 直接確認が落ちた場合はテスト前提の誤りである。期待結果へ触れず、直接式に合う `aitick` 設定だけを見直す。
4. 直接確認が通り、シナリオ期待だけが落ちた場合は、実際の CPU 入力、構え状態、打撃結果を記録する。
5. 失敗が sweet 成功による正当な経路変化か、本番実装の不具合かを分ける。
6. 現行のテスト名とメッセージが主張するゲームプレイ契約を維持できるか確認する。
7. 契約変更が必要に見える場合は停止し、Claude Code の設計判断へ戻す。

### SWEET-RED-003: 禁止

赤を消すために次を行ってはならない。

- 期待値を緩める
- assertion を削る
- 検査範囲を減らす
- ループ回数を減らす
- sweet 条件を外す
- attack 条件を外す
- 下位ヘルパーを直接呼んで CPU 判断を迂回する
- プロファイルを別のものへ変えて抽選を迂回する
- 成功 seed を探索する
- ゴールデンを再採取する

## 10. `tests/unit/test_hit.gd` の残る `s.tick` 三箇所

### HIT-TICK-001: `_ground_receive_vx`

現行 `tests/unit/test_hit.gd::_ground_receive_vx()` の `s.tick = tick` は、
実レシーブ内の `_scatter()` を振る意図だったが、#88b-2 後は効かない。

変更:

- 第3引数を `tick` ではなく `aitick` として扱う。
- `s.aitick = aitick` を直接設定する。
- `test_ground_receive_scatter_is_deterministic` のメッセージを
  「同じ aitick・actor・入力」に直す。
- 実 `HitResolver._apply_hit()` を通すため、このテストは第3層へ残す。

他の `_ground_receive_vx()` 呼び出しが省略値 0 を使うことは維持する。

### HIT-TICK-002: `test_neutral_receive_keeps_legacy_bounce`

現行の 201 回ループと `s.tick = seed_tick` は削除する。

理由:

- レシーブ散らしは `ball_vx` にだけ入る。
- このテストが検査するのは `ball_vy` だけである。
- tick を 201 通り回しても、縦バウンドの検査強度は増えない。

テスト関数自体は削除しない。
単一の明示状態で、従来どおり縦速度を検査する。
テスト本数は減らない。

### HIT-TICK-003: `test_only_toss_bad_can_produce_low_toss`

現行 `s.tick = seed_tick` は `SALT_TOSS_BAD` を振らない。
また `upward <= cfg.bump_up_speed` は上限だけなので、
低トスが一度も出なくても通り得る。

次の三ケースを実打撃で比較する。

1. `CHAR_PANDA`、actor 0、`aitick = 0`
   - `_toss_apex_pct()` が低トス側であることを先に直接確認する。
2. `CHAR_PANDA`、actor 0、`aitick = 1`
   - `_toss_apex_pct()` が通常側であることを先に直接確認する。
3. トス下手特性を持たないキャラクター、actor 0、`aitick = 0`
   - 同じ低トス出目でも通常側になることを先に直接確認する。

`aitick` 0 と 1 は、現行 `SimRng.derived_value()`、
actor 0 の `actor + 1` 補正、現行 `SALT_TOSS_BAD` から得た固定契約ベクトルである。
実装時に別の値を探索してはならない。

合格条件:

- パンダの低トス側は、パンダの通常側より上向き速度が小さい。
- パンダの通常側と特性なしは、既存の通常トス速度契約に一致する。
- 特性なしは低トス出目でも低くならない。
- 上限確認だけで終わらず、テスト名の「トス下手だけが低いトスを出せる」を実際に検査する。

### HIT-TICK-004: 物理単体を分離する

現行 `test_toss_bad_is_exactly_30_percent_and_targets_70_percent_apex` のうち、
`toss_vy_for_apex_pct()` と `apex_height()` を使う頂点計算を別テストへ分ける。

新名:

`test_toss_vy_for_apex_pct_targets_requested_height`

既存の計算式、許容差、期待する頂点比は変更しない。
これは三層の外の物理単体である。

この分離によりテストは 1 本増える。

## 11. 追加で見つかった旧乱数源の痕跡

### TRACE-001: `tests/unit/test_char_stats.gd`

`test_scatter_is_deterministic()` は `s.tick = 1234` を設定し、
コメントも「同じ tick / actor / salt」を主張している。

このテストを第2層へ移し、`s.aitick` を明示する。
再現性、範囲、actor と用途 ID の分離という検査強度は維持する。

### TRACE-002: `tests/unit/test_cpu.gd`

`test_miss_roll_is_stable_within_touch()` は、死んだ `_roll()` と
`last_hit_tick` を旧乱数契約として直接固定している。

第2層へ移し、次の契約へ変更する。

- 同じ `aitick`、actor、用途 ID なら同じ値
- `s.tick` と `last_hit_tick` を変えても値は変わらない
- `aitick` を変えれば、承認済み固定ベクトルでは値が変わる
- actor または用途 ID を変えれば分離される
- 呼び出しで `SimState` を変更しない

本番と同じ `_derived_roll()` で期待値を再計算して比較するだけにしてはならない。
既存の #88b-2 固定ベクトルを使う。

### TRACE-003: `tests/unit/test_hit.gd` のむらっけ探索

`_aitick_for_mura_pct()` は最大 10000 個から 150% になる入力を探している。
第3層の `test_mura_applies_to_normal_just_and_attack_serve` が
都合のよい seed を探索する旧形式なので削除する。

置換:

- `aitick = 0xABCD` を直接設定する。
- シナリオ実行前に、actor 0 の `_trait_roll_pct()` が
  CONTRACT-ALL-003 の固定値 96 であることを確認する。
- `_mura_power_pct()` が 150% 側であることを直接確認する。
- その後で通常、ジャスト、アタックサーブへ倍率が一度だけ乗ることを検査する。

別の `aitick` を探索してはならない。

### TRACE-004: `tests/unit/test_cpu_balance.gd`

`_run_match()` は「乱数キー `last_hit_tick` の系列をずらす」とコメントし、
`s.tick = seed * 7919` を設定している。
現在この代入は乱数 seed にならない。

変更:

- `Simulation.reset_match()` の既存 `seed` 引数へ `_run_match()` の `seed` を渡す。
- `s.tick` の偽装を削除する。
- コメントを、試合開始時に `rng` と `aitick` を明示 seed で初期化する説明へ直す。
- `serve_first`、ロスター、CPU プロファイル、勝敗判定は変えない。

数値を新たに作らず、`Simulation.reset_match()` の既存 seed 契約を使う。

### TRACE-005: `src/sim/sim_state.gd`

`last_hit_tick` のコメントから「乱数キーの主軸」を削除する。

このフィールド自体は削除しない。
CPU の反応遅延と、打撃発生の観測に現在も使われている。

### TRACE-006: `src/sim/sim_cpu.gd`

ファイル先頭の「通常抽選は `last_hit_tick`」という説明を削除し、
現在の契約へ直す。

- 原作対応許可は生の `aitick`
- 本作独自抽選は `aitick`、actor、用途 ID の読み取り専用派生値
- 役割判断はラリー開始時に保存した roll
- CPU 判断は乱数状態を書き換えない

## 12. `test_hit_chain_second_golden` の扱い

### HIT-CHAIN-001: 改名

`tests/unit/test_refactor_characterization.gd` の
`test_hit_chain_second_golden` を次へ改名する。

`test_hit_chain_physics_state_transition_golden`

### HIT-CHAIN-002: コメント

テスト直前へ次の事実が分かるコメントを置く。

- `_world()` は `SimState.new()` だけを使う。
- `Simulation.tick()` を通らない。
- 全過程で `tick = 0`、`rng = 0`、`aitick = 0` のままである。
- 旧 `keyed_hash(s.tick = 0, ...)` と新 `keyed_hash(aitick = 0, ...)` は同じ値になる。
- このテストの責務は物理と状態遷移のスナップショットである。
- 乱数源切替は検査対象外である。

### HIT-CHAIN-003: 固定値据え置き

7 要素の配列は一文字も変更しない。
再採取しない。

案 B のように非ゼロ `aitick` を入れて乱数源も同じテストへ混ぜてはならない。
物理・状態遷移・乱数源の三責務を混ぜると、失敗時の帰属が曖昧になる。

## 13. salt 用途 ID

### SALT-B3-001: 連番へ詰めない

用途 ID の値は派生値の一部である。
定数を削除しても、後続の値を詰めてはならない。

存続する CPU 用途 ID の唯一の出所は `src/sim/sim_cpu.gd`、
HitResolver 用途 ID の唯一の出所は `src/sim/hit_resolver.gd` である。
実装前後で存続定数の数値を比較し、一つも変わっていないことを確認する。

### SALT-B3-002: 用途 ID 4

用途 ID 4 は、廃止済みの `SALT_RECEIVE` の欠番として残す。

実装上の定数 `SALT_RECEIVE` は削除するが、用途 ID 4 を別名へ再利用しない。
後続用途を 4 へ詰めない。

ソースには、名前そのものを参照として残さず、
「用途 ID 4 は廃止済み予約番号であり再利用禁止」と分かるコメントを置く。

### SALT-B3-003: 明示承認が必要な未使用 salt

現行参照を全数照合した結果、次も実処理から未使用である。

| 定数 | 未使用になった理由 | 承認後の扱い |
|---|---|---|
| `SALT_SWEET` | `_sweet_ok()` が生 `aitick` を読む | 定数を削除し、用途番号を予約欠番にする |
| `SALT_ATTACK` | `_attack_ok()` が生 `aitick` を読む。残る参照は旧探索テストだけ | 第1段階で参照を消した後、定数を削除し予約欠番にする |
| `SALT_ROLE` | #88b-1 で役割抽選がステートフル方式へ移った | 定数を削除し、用途番号を予約欠番にする |

Claude Code がこの設計書を承認することを、この三定数を撤去する明示承認とする。
一つでも承認しない場合は、その定数を残して設計書を改訂し、再度ピン留めする。
実装者が勝手に承認済みと解釈してはならない。

承認後は、各定数の現行宣言をその位置で予約欠番コメントへ変換する。
予約コメントの整数は削除する宣言からそのまま移し、別の値を打ち直さない。
静的参照ゼロを保つため、予約コメントには削除した識別子名を残さない。

### SALT-B3-004: 存続用途

次は存続する。

- `SALT_AIM`
- `SALT_MISS`
- `SALT_SUPER`
- `SALT_MURA`
- `SALT_TOSS_BAD`
- `SALT_RECEIVE_SCATTER`

名前も値も変えない。
新用途 ID を追加しない。

## 14. 二段階の実装順

### STAGE-001: 第1段階 テスト健全化

第1段階では本番乱数コードを削除しない。

順序:

1. `test_sim_rng.gd` へ第1層二本を移す。
2. `test_stateful_rng_part_b2.gd` を `test_rng_draw_contracts.gd` へ改名する。
3. 第2層テストを対応表どおり移す。
4. 分布テストを全 16 bit 入力の全域検査へ直す。
5. `SALT_RECEIVE` 依存 6 本を直接 `aitick` 設定へ直す。
6. strong attack サーブの旧探索を直接 `aitick` 設定へ直す。
7. `_select_successful_roll()` を削除する。
8. `test_hit.gd` の `s.tick` 三箇所を本設計どおり直す。
9. `_aitick_for_mura_pct()` を固定入力へ置き換えて削除する。
10. トス頂点物理を一テストへ分離する。
11. `test_char_stats.gd`、`test_cpu.gd`、`test_cpu_balance.gd` の旧痕跡を直す。
12. 第3層の `reset_match()` へ seed 0 を明示する。
13. `test_hit_chain_second_golden` を改名し、責務コメントを追加する。
14. 静的テスト数が 448 本であることを確認する。
15. Claude Code がフルテストを実行する。

第1段階で本番コードの乱数式、閾値、物理式を変更してはならない。

### STAGE-002: 第1段階の合格

第1段階の合格条件:

- 静的テスト数 448
- フルテストの実行数 448
- 0 failed
- `SCRIPT ERROR summary` なし
- 6 本すべてで sweet 前提を直接確認
- strong attack サーブで attack 前提を直接確認
- 900 回探索なし
- `s.tick` を乱数 seed にする箇所なし
- 固定値の変更なし

赤が出た場合は 9 節の判定手順を使う。
第1段階が緑になる前に第2段階へ進まない。

### STAGE-003: 第2段階 死んだ入口の撤去

第1段階が緑になった後だけ、次を `src/sim/sim_cpu.gd` から削除する。

- `_noise()`
- `_roll()`
- `SALT_RECEIVE`
- `SALT_SWEET`
- `SALT_ATTACK`
- `SALT_ROLE`
- これらだけを説明する死んだコメント

同時に、現行乱数契約を説明するファイル先頭コメントへ更新する。

`src/sim/sim_state.gd` の `last_hit_tick` コメントも更新する。
フィールドと代入処理は変更しない。

### STAGE-004: 第2段階の性質

第2段階は参照ゼロのコードとコメントだけを撤去する。
そのため、状態ハッシュ、CPU 入力、ゲームプレイ結果、固定乱数列は一つも動かない。

一つでも動いた場合は「死んだコードではなかった」証拠である。
ゴールデンを更新せず停止する。

## 15. 静的検査

### STATIC-001: 第1段階後の参照確認

第2段階へ入る前に、追跡対象の `src` と `tests/unit` で次を確認する。

- `SALT_RECEIVE` は定数定義以外 0
- `SALT_SWEET` は定数定義以外 0
- `SALT_ATTACK` は定数定義以外 0
- `SALT_ROLE` は定数定義以外 0
- `_noise()` は本番定義以外 0
- `_roll()` は本番定義以外 0

`_derived_roll()` と `SALT_RECEIVE_SCATTER` は存続対象なので、
部分文字列検索で誤検出してはならない。
単語境界を使う。

確認例:

```powershell
rg -n --glob '*.gd' '\b(SALT_RECEIVE|SALT_SWEET|SALT_ATTACK|SALT_ROLE|_noise|_roll)\b' src tests/unit
```

合格時は、削除予定の定数定義と本番ヘルパー定義だけが出る。

### STATIC-002: 第2段階後の参照ゼロ

第2段階後、追跡対象の `src` と `tests/unit` で次の識別子が 0 件であること。

- `SALT_RECEIVE`
- `SALT_SWEET`
- `SALT_ATTACK`
- `SALT_ROLE`
- `_noise`
- `_roll`
- `_select_successful_roll`
- `_aitick_for_mura_pct`

歴史資料と過去設計書は当時の事実を記録しているため書き換えない。
静的ゼロ検査の対象は実行コードと追跡対象テストである。

確認例:

```powershell
rg -n --glob '*.gd' '\b(SALT_RECEIVE|SALT_SWEET|SALT_ATTACK|SALT_ROLE|_noise|_roll|_select_successful_roll|_aitick_for_mura_pct)\b' src tests/unit
```

合格時は出力 0 行である。

### STATIC-003: 旧キー表現

次が実行コードと追跡対象テストに残っていないことを確認する。

- `last_hit_tick` を乱数キーと呼ぶ現役コメント
- `s.tick` を乱数 seed と呼ぶ現役コメント
- 「同じ tick / actor / salt」を現行 `_scatter()` 契約として主張するコメント

反応遅延、打撃発生時刻、イベント検出のための `last_hit_tick` 使用は正当であり、
削除対象ではない。

### STATIC-004: salt 値

第2段階の前後で存続する六定数の宣言を比較する。
値が一つでも変わった場合は停止する。

予約欠番へ新しい定数が割り当てられていないことも確認する。

確認対象:

```powershell
rg -n 'const SALT_(AIM|MISS|SUPER) :=' src/sim/sim_cpu.gd
rg -n 'const SALT_(MURA|TOSS_BAD|RECEIVE_SCATTER) :=' src/sim/hit_resolver.gd
```

実装前の同じ宣言と行単位で一致することが合格条件である。

### STATIC-005: テスト数

静的数え方は、追跡対象 `tests/**/*.gd` の行頭 `func test_` である。

- 実装前: 447
- 実装後: 448

増加 1 本は、トス頂点の物理単体を抽選分布テストから分けたためである。
既存テストの削除は 0 本である。

追跡対象だけを数える例:

```powershell
$count = 0
git ls-files 'tests/*.gd' | ForEach-Object {
	$count += @(Select-String -LiteralPath $_ -Pattern '^func test_').Count
}
$count
```

合格時の出力は `448` である。

## 16. ゴールデンと固定値

### GOLDEN-B3-001: 因果で判定する

固定値テストを固定リストだから更新する、または更新しない、とは判断しない。
この変更が実際に何を通るかで判定する。

### GOLDEN-B3-002: #88b-3 で動かない固定値

この段は本番抽選式とゲームプレイを変えないため、次は動かない。

- `tests/unit/test_sync.gd::GOLDEN_COMBINED_HASH`
- `test_scatter_stream_snapshot` の 60 要素配列
- 改名前 `test_hit_chain_second_golden` の 7 要素配列
- その他の固定配列、固定ハッシュ、固定ベクトル

ファイル移動やテスト改名を理由に値を書き直してはならない。

CONTRACT-ALL-003 の 10、65、96 は、新しいシナリオ前提を直接固定する追加検査である。
既存固定値の置換や再採取ではない。
既存の固定期待値は変更 0 件でなければならない。

### GOLDEN-B3-003: 再採取ゼロ

#88b-3 の合格条件はゴールデン再採取ゼロである。

固定値が赤になった場合:

1. 値を変更しない。
2. 何が届いたかを記録する。
3. 他のテストが緑でも停止する。
4. Claude Code が原因を判定する。

## 17. テスト本数

### COUNT-001: 基準

#88b-2 完了時点は 447 本である。

### COUNT-002: 実装後

実装後は 448 本を期待する。

内訳:

- 移動: 本数不変
- 改名: 本数不変
- `test_neutral_receive_keeps_legacy_bounce` の 201 回ループ削除: 本数不変
- 旧探索ヘルパー削除: ヘルパーなので本数不変
- トス頂点物理の分離: 1 本増加
- テスト関数の削除: 0 本

### COUNT-003: 減少時

448 未満になった場合は停止する。

今の設計では削除を承認したテストは一つもない。
将来テストを減らす必要が出た場合は、削除する関数名と理由を一つずつ設計書へ追記し、
再承認・再ピン留めする。
数合わせの削除は禁止する。

## 18. 停止条件

### STOP-B3-001: ピン不一致

実装開始前に、この設計書の行数または SHA-256 が Claude Code の承認値と違う場合。

### STOP-B3-002: 未承認 salt

13.3 節の三定数について、Claude Code の明示承認がない場合。

### STOP-B3-003: 存続 ID の変化

存続 salt の名前または値を変える必要が出た場合。

### STOP-B3-004: 欠番再利用

廃止用途 ID を新用途へ割り当てる必要が出た場合。

### STOP-B3-005: 抽選式の変更

`_sweet_ok()`、`_attack_ok()`、`derived_value()`、`_scatter()`、
`_trait_roll_pct()` の式や閾値を変える必要が出た場合。

### STOP-B3-006: シナリオ契約の赤

直接 sweet / attack 成功を確認した後のシナリオ期待が赤になり、
本番不具合か古い期待かを設計書だけで判定できない場合。

### STOP-B3-007: 固定値の赤

固定配列、固定ハッシュ、固定ベクトルが一つでも赤になった場合。

### STOP-B3-008: 状態またはゲームプレイ変化

第2段階で状態ハッシュ、CPU 入力、打球、勝敗が変わった場合。

### STOP-B3-009: テスト数不一致

実装後の静的数または実行数が 448 でない場合。

### STOP-B3-010: 同一ヘルパー期待値

本番と同じヘルパーから期待値を再計算しないとテストを書けない場合。

### STOP-B3-011: 範囲拡大

本番物理、CPU バランス、キャラクター性能、乱数アルゴリズムの変更が必要になった場合。

### STOP-B3-012: 説明不能な残存参照

静的ゼロ検査で、歴史資料以外の実行コードまたは追跡対象テストに旧入口が残った場合。

## 19. やってはいけないこと

- 設計書承認前に実装する
- 承認後の設計書を無断で変える
- salt を連番へ詰める
- 欠番を再利用する
- 新しい用途 ID を追加する
- seed を探索する
- 900 回探索を別の回数へ変えて残す
- `_aitick_for_mura_pct` を別名で残す
- `last_hit_tick` を乱数キーとして偽装する
- `s.tick` を乱数キーとして回す
- 成功条件を直接確認せずシナリオを実行する
- 赤を消すため期待値を緩める
- 検査範囲を減らす
- 抽選を迂回する
- 既存テストを削除する
- 固定値を再採取する
- 動かなかった値を書き直す
- 60 要素乱数列を更新する
- 7 要素ヒット連鎖配列を更新する
- `GOLDEN_COMBINED_HASH` を更新する
- 本番と同じヘルパーで期待値を作る
- `zz_*` プローブを設計対象へ入れる
- Codex がテストまたは Godot を実行する
- Codex がコミットする

## 20. 変更対象

### 20.1 第1段階

| ファイル | 変更 |
|---|---|
| `tests/unit/test_sim_rng.gd` | 第1層二本を受け入れる |
| `tests/unit/test_stateful_rng_part_b2.gd` | `test_rng_draw_contracts.gd` へ改名 |
| `tests/unit/test_rng_draw_contracts.gd` | 第2層八本を集約 |
| `tests/unit/test_refactor_characterization.gd` | scatter snapshot を移動、ヒット連鎖を改名・注記 |
| `tests/unit/test_char_stats.gd` | scatter 契約を第2層へ移動 |
| `tests/unit/test_cpu.gd` | 旧 `_roll` 契約を第2層へ移動・置換 |
| `tests/unit/test_cpu_offense_receive.gd` | 6 本と attack サーブを直接 `aitick` 設定へ置換、探索ヘルパー削除 |
| `tests/unit/test_hit.gd` | `s.tick` 三箇所是正、むらっけ探索撤去、分布テスト移動、物理単体分離 |
| `tests/unit/test_cpu_balance.gd` | reset の seed 引数を使う |
| `tests/unit/test_sync.gd` | 二つの実行ヘルパーでロスターと seed 0 を明示 |

### 20.2 第2段階

| ファイル | 変更 |
|---|---|
| `src/sim/sim_cpu.gd` | 死んだ入口・明示承認済み未使用 salt・旧コメントを撤去 |
| `src/sim/sim_state.gd` | `last_hit_tick` コメントを現行用途へ訂正 |

### 20.3 変更しない

- `src/sim/sim_rng.gd`
- `src/sim/hit_resolver.gd`
- `src/sim/simulation.gd`
- `data/rules.json`
- 既存の固定期待値
- 過去設計書と歴史資料

## 21. 検証と報告

### VERIFY-B3-001: Codex の実装報告

承認後の実装が完了したら、Codex は次を報告する。

1. 承認時の行数と SHA-256 が実装開始前に一致したこと
2. 変更した全ファイルと全変更
3. 移動・改名した全テスト名
4. 新設した物理単体一テスト
5. 削除したテストが 0 本であること
6. 静的テスト数 448
7. 旧入口の静的参照ゼロ結果
8. 存続 salt の値が不変であること
9. `git diff`
10. 固定値を変更していないこと
11. テスト、Godot、コミット、ゴールデン再採取を行っていないこと

### VERIFY-B3-002: Claude Code の検証

Claude Code は各段階でフルテストを実行する。

第1段階:

- 448 tests
- 0 failed
- `SCRIPT ERROR summary` なし
- sweet / attack 前提が直接確認されている

第2段階:

- 448 tests
- 0 failed
- `SCRIPT ERROR summary` なし
- 固定値の赤なし
- 状態ハッシュとゲームプレイ結果の変化なし

必要な場合はビルドまたはゲーム起動も Claude Code が行い、結果を記録する。

## 22. 完了の定義

#88b-3 は次をすべて満たしたときだけ完了である。

- 乱数関連テストが三層と補助単体へ全数分類されている
- 第1層は `SimRng` 純粋関数だけである
- 第2層は明示 `aitick`、actor、用途 ID、プロファイルで抽選契約を直接検査する
- 第3層は乱数状態を明示した実ゲームシナリオである
- 10 / 80 / 10 と 30 / 70 を全域検査する
- 900 回探索と任意上限 seed 探索がない
- `_aitick_for_mura_pct()` がない
- `SALT_RECEIVE` 依存 6 本が直接 `aitick` 設定へ移っている
- sweet 成功を前提にするシナリオが成功条件を直接確認する
- `test_hit.gd` の旧 `s.tick` 三箇所が本設計どおり是正されている
- トス下手だけが低トスを出せることを実シナリオで検査する
- トス頂点計算が物理単体へ分かれている
- `test_hit_chain_physics_state_transition_golden` が乱数源を責務外と明記する
- `_noise()`、`_roll()`、`_select_successful_roll()` がない
- 明示承認された未使用 salt がない
- 用途 ID 4 と他の廃止番号が予約欠番である
- 存続用途 ID の値が変わっていない
- `last_hit_tick` の正当な反応遅延用途は維持されている
- 静的・実行テスト数が 448
- 448 tests, 0 failed
- 固定値変更 0
- ゴールデン再採取 0
- Codex のコミット 0

この条件を満たさない場合、完了と報告してはならない。

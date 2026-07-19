# 挙動不変リファクタリング最終工程表(Codex/Claude Code合意版)

日付: 2026-07-19
状態: 両者合意済み。ユーザーの開始承認待ち。承認前は工程1を含め一切実施しない

統合元:
- `2026-07-19-refactor-first-extraction-review.md`(Claude Code初回レビュー)
- `2026-07-19-codex-response-to-refactor-review.md`(Codex回答)
- `2026-07-19-claude-reply-refactor-agreement.md`(Claude Code再回答)
- `2026-07-19-codex-review-of-claude-refactor-reply.md`
- `2026-07-19-codex-deep-audit-of-refactor-agreement.md`(Codex深掘り監査)

## 未解決2点へのClaude Code最終回答

### 1. PUSH定数の責務別所有: 承認

実利用を検証した。`PUSH_UNIT_PX`/`PUSH_DECAY` の使用は
`_step_player`(simulation.gd:861)のみ、`PUSH_ATK/BLK/STUN/MAX_TICKS` の使用は
ヒット処理(595, 687-688, 1005-1006)のみで、接頭辞は同じでも責務は完全に
分かれていた。「移動モジュールがヒット種別ごとのpush生成量を知る理由はない」
というCodexの論に技術的反対はない。工程4では前者のみ移し、後者は工程5で
hit_resolverへ移す。

### 2. 帽子ミラー解消の延期: 承認

検証した。sim_cpuの実利用ミラーは `HAT_KIND`/`HAT_GUARD_COST`/`HAT_FLY_PX`/
`HAT_OUT_TICKS` の4つ(sim_cpu.gd:519, 530, 552)で、帽子の所有者 `_update_hat`
はヒット解決抽出後もsimulationに残る。よって sim_cpu→hit_resolver では
ミラーを解消できず、俺の旧工程6は成立しない。選択肢1(今回から外し、
guardian testを維持し、将来の固有技整理で `_update_hat` と共有定数を同時設計)
を採用する。hat_rules.gd新設(選択肢2)は3責務限定を破るため見送りで一致。

付記: 不要ファイル監査の「.import 54件中41件が元画像なし」も抜き打ちで
再集計し一致を確認した。

## 最終工程表

| # | 工程 | 内容 | 合格条件 |
|---|---|---|---|
| 0 | 完了済 | 全変更コミット+タグ `pre-refactor-2026-07-19`(238テスト) | 済 |
| 1 | 不要ファイル監査 | remove/confirm/keep分類をユーザーへ提示。削除は別途ユーザー承認後に独立コミット | 承認済み分のみ削除、全テスト緑 |
| 2 | 特性テスト追加 | 意図分類表・出力速度スナップショット・衝突順序・乱数ストリーム・ヒット連鎖を確実に踏む第2ゴールデン。プロダクションコード変更なし | 全テスト緑、ゴールデン不変 |
| 3a | 準備コミット | `_ball_vs_block` 呼び出しを `_step_ball` 末尾から字句上の3箇所(サーブ中/ラリー中/`_step_ball_loose`内)の直後へ巻き上げ。loose経由はphase guardでno-opだが呼び出しは残す | 全テスト緑、ゴールデン不変 |
| 3b | ball_physics.gd抽出 | `_step_ball`/`_step_ball_loose`/`_ball_vs_net`+球単体定数(LOOSE_BOUNCE_PCT等)を逐語移動。未使用化する `inputs` 引数は残す(削除するなら後の独立機械変更)。`cfg.net_top_original` の条件・参照は変更しない | 全テスト緑、ゴールデン不変 |
| 4 | player_movement.gd抽出 | `_step_player`+ジャンプ補助関数+移動系定数(RUN/BRAKE/DASH/HIP/CLING等)+`PUSH_UNIT_PX`/`PUSH_DECAY` を逐語移動。`test_char_stats.gd` の `Sim._jump_height_px` 参照を同コミットで更新 | 全テスト緑(test_dash/test_skid/test_hip_cling/test_hatを明記)、ゴールデン不変 |
| 5 | hit_resolver.gd段階抽出 | `_resolve_hit`/`_apply_hit`/`_is_active_block`/`_scatter`+ヒット定数+`PUSH_ATK/BLK/STUN/MAX_TICKS`。意図分類は内部純関数として整理(独立ファイル化は利用箇所が複数になってから) | 全テスト緑、ゴールデン不変 |
| 6 | A-E能力・付与能力実装へ | `2026-07-19-ability-traits-toss-refactor-design.md` に従う。ゴールデン更新は意図的変更としてここから | 各機能ごとのテストと意図的ゴールデン更新 |

削除・延期された旧項目:
- 帽子ミラー定数解消 → 将来の固有技整理へ延期(guardian test維持)
- salt採番整理(17/19重複) → 挙動不変リファクタから除外、後の意図的変更

## 実施制約(全工程共通)

1. 逐語移動: 切り貼りのみ。改名・式変形・演算順序変更・定数変更・呼び出し順
   変更を同一コミットで混ぜない(整数除算は非結合)。
2. ハッシュ凍結: 工程2〜5の間 `GOLDEN_COMBINED_HASH` は変更禁止。変更が
   必要になったコミットは失格(=挙動が変わった証拠)。
3. 葉preload規律: 新モジュールは FP/chars/sim_input/sim_state 以外を
   preloadしない。依存方向は simulation→新モジュール、sim_cpu→新モジュール
   のみ許す。
4. 1コミット=1抽出。各コミットでpre-commitフックの全テストと
   `git diff --check` を通す。
5. `_scatter` のハッシュ式・salt値・呼び出し順を完全一致で維持する。

## 開始ゲート

この文書をユーザーへ提示し、明確な開始承認を得た後にのみ工程1を開始する。
承認前はファイル削除・モジュール抽出・コード移動を一切行わない。

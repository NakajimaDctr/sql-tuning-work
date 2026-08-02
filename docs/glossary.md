# 用語集

EXPLAIN・インデックス・オプティマイザ関連の用語を、このリポジトリの
どのステージで扱っているかとあわせてまとめた早見表。

## EXPLAINのカラム

| 用語 | 意味 | 関連ステージ |
|---|---|---|
| `type` | アクセス方法。`const`が最速、`ALL`（フルスキャン）が最も遅い | [Stage 1](../basics/01_explain_basics/) |
| `possible_keys` | 使える可能性があったインデックス | [Stage 1](../basics/01_explain_basics/) |
| `key` | 実際に使われたインデックス（NULLなら未使用） | [Stage 1](../basics/01_explain_basics/) |
| `key_len` | 実際に使われたインデックスのバイト長。複合インデックスの何列目まで使われたかの目安になる | [Stage 4](../basics/04_composite_covering_index/) |
| `rows` | オプティマイザが見積もった、読み取る行数（概算値） | [Stage 1](../basics/01_explain_basics/), [Stage 5](../advanced/05_statistics_cardinality/) |
| `filtered` | `rows`のうちWHERE条件で絞り込まれた後に残る行の割合(%)の見積もり | [Stage 5](../advanced/05_statistics_cardinality/) |
| `Extra` | 補足情報（`Using where`, `Using index`, `Using filesort`など） | [Stage 1](../basics/01_explain_basics/) |
| `partitions` | パーティション化テーブルで、実際にアクセスするパーティション名 | [Stage 8](../advanced/08_partitioning/) |

## typeの値（速い順）

| 値 | 意味 |
|---|---|
| `system` / `const` | 主キー・ユニークキーで1行に確定するアクセス |
| `eq_ref` | JOINで相手側が1行に確定するユニークキー参照 |
| `ref` | 非ユニークインデックスでの等値検索 |
| `range` | インデックスを使った範囲検索 |
| `index` | インデックス全体を走査（フルスキャンよりはまし） |
| `ALL` | フルテーブルスキャン |

## Extraの主な値

| 値 | 意味 |
|---|---|
| `Using where` | ストレージエンジンから受け取った行にサーバー側で追加のフィルタをかけた |
| `Using index` | インデックスだけで結果を返せた（カバリングインデックス） | 
| `Using index condition` | インデックスの条件をストレージエンジン側で先に評価する最適化（ICP） |
| `Using filesort` | ソートのために追加の並べ替え処理が発生した |
| `Using temporary` | 一時テーブルを使用した（`GROUP BY`等で発生しやすい） |
| `Backward index scan` | インデックスを逆順に読むことで、追加のソートなしにORDER BY DESCを満たしている |

## インデックス関連

| 用語 | 意味 | 関連ステージ |
|---|---|---|
| B-Tree | 値をソートして保持する木構造。MySQLの標準的なインデックス実装 | [Stage 2](../basics/02_index_fundamentals/) |
| カーディナリティ | 列に含まれる値の種類の数。多いほど絞り込み効果が高い傾向 | [Stage 5](../advanced/05_statistics_cardinality/) |
| 複合インデックス | 複数の列にまたがるインデックス | [Stage 4](../basics/04_composite_covering_index/) |
| 左端一致の原則 (Leftmost Prefix) | 複合インデックス`(A, B)`は先頭列Aを含む条件でのみ使える | [Stage 4](../basics/04_composite_covering_index/) |
| カバリングインデックス | SELECTする列がすべてインデックスに含まれ、テーブル本体を読まずに済む状態 | [Stage 4](../basics/04_composite_covering_index/) |

## 実行計画・オプティマイザ関連

| 用語 | 意味 | 関連ステージ |
|---|---|---|
| 統計情報 | オプティマイザが実行計画を決めるために使う、テーブル/インデックスのサンプリングに基づく推定情報 | [Stage 5](../advanced/05_statistics_cardinality/) |
| `ANALYZE TABLE` | 統計情報を更新するコマンド | [Stage 5](../advanced/05_statistics_cardinality/) |
| Nested Loop Join | 外側のテーブルを1行ずつ読み、その都度内側のテーブルを検索する結合方式 | [Stage 6](../advanced/06_execution_plan_internals/) |
| Hash Join | 片方のテーブルからハッシュテーブルを構築し、もう片方を1回スキャンして突き合わせる結合方式 | [Stage 6](../advanced/06_execution_plan_internals/) |
| `EXPLAIN ANALYZE` | 実際にクエリを実行し、見積もりと実測値の両方を表示する | [Stage 6](../advanced/06_execution_plan_internals/) |

## ロック・トランザクション関連

| 用語 | 意味 | 関連ステージ |
|---|---|---|
| 行ロック | 変更対象の行にかかる排他ロック | [Stage 7](../advanced/07_locking_transactions/) |
| ギャップロック | インデックスの値と値の「間」の区間にかかるロック。ファントムリードを防ぐ | [Stage 7](../advanced/07_locking_transactions/) |
| デッドロック | 複数のトランザクションが互いにロックを待ち合う状態。InnoDBが自動検知し一方をロールバックする | [Stage 7](../advanced/07_locking_transactions/) |
| 分離レベル (Isolation Level) | トランザクション間でどこまで他の変更が見えるかを決める設定。MySQLのデフォルトは`REPEATABLE READ` | [Stage 7](../advanced/07_locking_transactions/) |

## パーティショニング関連

| 用語 | 意味 | 関連ステージ |
|---|---|---|
| パーティショニング | テーブルを物理的に複数の塊に分割して格納する機能 | [Stage 8](../advanced/08_partitioning/) |
| パーティションプルーニング | WHERE句から判断して、不要なパーティションへのアクセスを省略する最適化 | [Stage 8](../advanced/08_partitioning/) |

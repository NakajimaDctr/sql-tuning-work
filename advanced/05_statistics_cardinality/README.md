# Stage 5: 統計情報とカーディナリティ

## 概要/ゴール

「なぜオプティマイザはこのインデックスを選んだのか（あるいは選ばなかったのか）」を
理解するには、MySQLが内部に持つ「統計情報」を知る必要がある。このステージでは
カーディナリティ（列の値の種類数）と統計情報がどのように作られ、
EXPLAINの`rows`見積もりにどう影響するかを理解する。応用編の出発点として、
オプティマイザを「ブラックボックス」から「推測できる仕組み」に変える。

## 前提知識

基礎編（[Stage 1](../../basics/01_explain_basics/README.md)〜
[Stage 4](../../basics/04_composite_covering_index/README.md)）が完了していること。

## 事前準備

```sql
SHOW INDEX FROM orders;
```

`idx_orders_user_id`, `idx_orders_created_at`, `idx_orders_user_status` が
存在する状態から始める（基礎編で作成済み）。

## 悪いクエリを実行してEXPLAINを見る

`orders.status` は `pending/paid/shipped/completed/cancelled` の5種類しかない
低カーディナリティ列。ここにインデックスを張るとどうなるか確認する。

```sql
CREATE INDEX idx_orders_status ON orders(status);
EXPLAIN SELECT * FROM orders WHERE status = 'completed';
```

`completed`は全体の約70%を占めるため、インデックスを使っても
結局ほとんどの行を読むことになる。「インデックスさえ張れば速くなる」
わけではないことがこのステージのポイント。

## 課題

`exercise.sql` に沿って進める。

1. `status`の実際の値の分布と、`SHOW INDEX`の`Cardinality`を比較する
2. 出現頻度が少ない値（`cancelled`）と多い値（`completed`）でEXPLAINの`rows`を比較する
3. `ANALYZE TABLE`前後でカーディナリティが変化するか確認する
4. `mysql.innodb_table_stats` / `mysql.innodb_index_stats` を直接見て、
   統計情報がどのくらいのサンプリングから作られているか確認する

**達成基準**: EXPLAINの`rows`が実際の件数と完全には一致しないことと、
その理由（サンプリングに基づく推定値であること）を説明できること。

## 解答例

[`solution.sql`](./solution.sql)

## 解説

### カーディナリティとは

列に含まれる「値の種類の数」のこと。一般に、カーディナリティが高い列
（例: `email`、ほぼ全行がユニーク）へのインデックスは絞り込み効果が高く、
カーディナリティが低い列（例: `status`、5種類しかない）へのインデックスは
効果が限定的になりやすい。

### 統計情報は「推定値」である

MySQL（InnoDB）はテーブルの全行を数え上げているわけではなく、
一部のページをサンプリングして統計情報（カーディナリティや行数）を
推定している。そのため:

- `SHOW INDEX`の`Cardinality`は近似値
- EXPLAINの`rows`も近似値
- サンプリングの偏りやデータの偏った分布（今回のように`completed`が70%を
  占めるようなケース）では、推定値と実測値のズレが大きくなりやすい

### なぜこれが重要か

オプティマイザは「統計情報から見積もったコスト」をもとに実行計画（どのインデックスを
使うか、テーブルの結合順序など）を決定する。統計情報が古い・不正確だと、
実際には非効率な実行計画が選ばれてしまうことがある。データが大きく変化した後に
`ANALYZE TABLE`で統計情報を更新するのは、この「オプティマイザの判断材料を
最新化する」ための操作。

## 発展問題（任意）

`innodb_stats_persistent_sample_pages`の値を大きくすると、
カーディナリティの推定精度は上がるはずである。以下を試して
`Cardinality`の値が変化するか確認してみよう（このセッションのみ有効）。

```sql
SET SESSION innodb_stats_persistent_sample_pages = 100;
ANALYZE TABLE orders;
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
```

## 次のステージへ

[Stage 6: 実行計画の内部を読む](../06_execution_plan_internals/README.md) に進む。

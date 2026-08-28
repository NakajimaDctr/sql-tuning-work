# Stage 5: 統計情報とカーディナリティ

## このステージでわかること

「なぜオプティマイザはこのインデックスを選んだ（あるいは選ばなかった）のか」を理解するには、
MySQLが内部に持つ **統計情報** を知る必要がある。
このステージでは **カーディナリティ**（列の値の種類数）と統計情報がどう作られ、
EXPLAINの `rows` 見積もりにどう影響するかを見る。
オプティマイザを「ブラックボックス」から「だいたい推測できる仕組み」に変えるのが狙い。

## 前提

基礎編（[Stage 1](../../basics/01_explain_basics/README.md)〜[Stage 4](../../basics/04_composite_covering_index/README.md)）が終わっていること。

```sql
SHOW INDEX FROM orders;
-- idx_orders_user_id, idx_orders_created_at, idx_orders_user_status がある状態
```

## どんな問題？ ― 身近な例えで

大きな倉庫の在庫を、毎日きっちり全品数えるのは大変だ。ふつうは棚をいくつか抜き取りで見て、
「だいたい"食品"が半分、"飲料"が2割……」と**ざっくり見積もる**。棚卸しは年に数回。

MySQLの統計情報もこれと同じ。テーブルの全行を数え上げるのではなく、
**一部のページをサンプリングして**「この列の値は何種類くらいあるか（カーディナリティ）」
「この条件だと何行くらい返るか」を推定している。だから:

- `SHOW INDEX` の `Cardinality` は近似値
- EXPLAIN の `rows` も近似値
- データの分布が偏っていると、推定と実測のズレが大きくなる

`orders.status` は `pending / paid / shipped / completed / cancelled` の**5種類しかなく**、
しかも `completed` が全体の約7割を占める、という「種類が少なく・偏った棚」である。

## まず現状を見てみる

`status` にインデックスを張り、実際の分布と、MySQLの推定を見比べる。

```sql
CREATE INDEX idx_orders_status ON orders(status);

-- 実際の分布
SELECT status, COUNT(*) AS actual_count
FROM orders
GROUP BY status
ORDER BY actual_count;

-- MySQLが推定した「値の種類数」
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
```

**【結果の見方】** 実際の分布の一例:

| status | 実件数 |
|---|---|
| cancelled | 24,712 |
| pending | 24,794 |
| shipped | 49,997 |
| paid | 50,239 |
| completed | 350,258（全体の約70%） |

一方 `SHOW INDEX` の `Cardinality` 列は **「3」程度** と表示されることが多い。
実際の種類は5つなのに、である。サンプリングした数ページの中に5種類すべてが
出てこなかったための過小推定。

## 見積もりと実測のズレを確認する

出現頻度が大きく違う2つの値で、EXPLAIN の `rows` を比べる。

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'cancelled';   -- 少数派
EXPLAIN SELECT * FROM orders WHERE status = 'completed';   -- 多数派
```

| クエリ | `rows`（見積もり） | 実際の件数 | ズレ |
|---|---|---|---|
| `status = 'cancelled'` | 約49,750 | 24,712 | 約2倍の過大見積もり |
| `status = 'completed'` | 約249,000 | 350,258 | 過小見積もり |

**【何が起きているか】** MySQLはテーブル全体を数えて `rows` を出しているのではなく、
「値の種類数は3くらい」という粗い統計から
「1種類あたり 全行 ÷ 3 ≒ 16.6万」→ 各条件はその前後、というふうに機械的に見積もっている。
だから実測とズレる。特に今回のように分布が偏っていると大きくズレる。

## 統計情報を更新してみる

```sql
ANALYZE TABLE orders;
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
```

**【結果の見方】** `Cardinality` は `ANALYZE TABLE` の前後で**ほとんど変わらない**ことが多い。
サンプリングの方式（見るページ数）が同じなら、同じような推定値に落ち着くためだ。
`ANALYZE TABLE` は「サンプリングをやり直して統計を取り直す」コマンドであって、
「精度を上げる」コマンドではない。

## 統計情報の中身を覗く

InnoDBがどれくらいのサンプルから統計を作っているかを直接見られる。

```sql
SELECT * FROM mysql.innodb_table_stats WHERE table_name = 'orders';
SELECT * FROM mysql.innodb_index_stats
WHERE table_name = 'orders' AND index_name IN ('PRIMARY', 'idx_orders_status');
```

**【結果の見方】** 一例として `idx_orders_status` は
`n_leaf_pages = 576`（索引の全ページ数）に対して `sample_size = 6`。
つまり **576ページ中わずか6ページ（約1%）** だけを見て「種類数は3」と推定している。
実測（5種類）とズレるのは当然、というわけだ。

サンプルページ数は `innodb_stats_persistent_sample_pages`（デフォルト20）で調整できるが、
増やすほど `ANALYZE TABLE` のコストも上がる。

## なぜこれが重要か

オプティマイザは「統計情報から見積もったコスト」をもとに、
どのインデックスを使うか・テーブルをどの順で結合するかを決める。
統計が古い・不正確だと、**実際には非効率な実行計画が選ばれてしまう**ことがある。
データ量や分布が大きく変わった後に `ANALYZE TABLE` するのは、
「オプティマイザの判断材料を最新化する」ためのメンテナンス操作である。

また、**カーディナリティが低い列（`status` のような5種類）へのインデックスは効果が限定的**。
`completed`（7割）で絞っても、索引経由で結局大半の行を読むことになるからだ。
「インデックスを張れば必ず速くなる」わけではない、という感覚が大事。

## まとめ

- 統計情報は「一部ページのサンプリングに基づく推定」。`Cardinality` も `rows` も近似値
- データの分布が偏っていると、見積もりと実測のズレが大きくなる
- `ANALYZE TABLE` は統計を取り直すコマンド。データが大きく変わった後に実行する
- 低カーディナリティ列へのインデックスは、絞り込み効果が薄いことがある

## さらに詳しく

サンプルページ数を増やすと、カーディナリティの推定精度は上がるはず。
このセッション限定で試せる。

```sql
SET SESSION innodb_stats_persistent_sample_pages = 100;
ANALYZE TABLE orders;
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
```

`Cardinality` が「3」から、実際の5に近い値へ動くことがある。
精度が上がる一方、`ANALYZE TABLE` にかかる時間は増える。
本番でこの値をむやみに上げると、統計更新のたびに負荷がかかる点に注意。
（試したら `SET SESSION innodb_stats_persistent_sample_pages = 20;` で戻す。）

## 次のステージへ

[Stage 6: 実行計画の内部を読む](../06_execution_plan_internals/README.md) に進む。

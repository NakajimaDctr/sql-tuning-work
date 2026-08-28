# Stage 8: パーティショニング

## このステージでわかること

テーブルが非常に大きくなったとき、**物理的にデータを分割して格納する**「パーティショニング」
という選択肢がある。このステージでは RANGE パーティションを実際に作り、
**パーティションプルーニング**（不要な塊を丸ごと読み飛ばす最適化）を体験する。
あわせて、効くケースと効かないケースの違いを理解する。

## 前提

[Stage 5: 統計情報とカーディナリティ](../05_statistics_cardinality/README.md) が終わっていること。

**重要**: このステージでは共有の `orders` テーブルは**変更しない**。
`orders_partitioned` という演習専用のコピーを作って進める
（`orders` 本体は他のステージの前提になっているため）。

## どんな問題？ ― 身近な例えで

契約書を1つの巨大なファイルボックスに全部詰め込んでいると、
「2025年1月の契約書」を探すのにも全部めくることになる。

そこで、**年度ごとにキャビネットを分ける**。2024年の引き出し、2025年の引き出し……。
「2025年1月の契約書」なら、2025年の引き出しだけ開ければよく、2024年の引き出しは触らなくていい。

パーティショニングはこの「年度別キャビネット」。
テーブルを、ある列の値（今回は `created_at` の年）でいくつかの塊（パーティション）に分けて格納する。
そして、WHERE句から「どの塊にありそうか」を判断して、関係ない塊へのアクセスを丸ごと省く。
これが **パーティションプルーニング** で、EXPLAIN の `partitions` 列に表れる。

## 比較用に、通常のテーブルの範囲検索を見ておく

```sql
EXPLAIN SELECT * FROM orders
WHERE created_at >= '2025-01-01' AND created_at < '2025-02-01';
```

`idx_orders_created_at`（Stage 3で作成）があるので `type: range` になるはず。
このステージでは「インデックスとは別の軸」として、テーブル自体の物理分割を見ていく。

## こう作る（指示）

`created_at` の年で RANGE パーティション化したコピーテーブルを作る。

```sql
DROP TABLE IF EXISTS orders_partitioned;
CREATE TABLE orders_partitioned (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      INT UNSIGNED NOT NULL,
  status       VARCHAR(20) NOT NULL,
  total_amount INT UNSIGNED NOT NULL,
  created_at   DATETIME NOT NULL,
  PRIMARY KEY (id, created_at)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(created_at)) (
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

INSERT INTO orders_partitioned SELECT * FROM orders;
ANALYZE TABLE orders_partitioned;
```

**【目的とポイント】**

- `PARTITION BY RANGE (YEAR(created_at))` … 「`created_at` の年」で塊を分ける宣言。
  `p2024` は2025年より前（＝2024年）、`p2025` は2026年より前（＝2025年）、
  `pmax` はそれ以外（将来の年など）。
- `PRIMARY KEY (id, created_at)` … 本来 `orders` の主キーは `id` だけ。
  だがMySQLの制約で **パーティションキー（`created_at`）は、テーブルのすべてのユニークキーに
  含まれていなければならない**。そのため主キーを `(id, created_at)` の複合にしている。

## 結果の見方 ― 何が変わったか

### 各パーティションの件数

```sql
SELECT PARTITION_NAME, TABLE_ROWS
FROM information_schema.PARTITIONS
WHERE TABLE_NAME = 'orders_partitioned';
```

一例:

| PARTITION_NAME | TABLE_ROWS |
|---|---|
| p2024 | 約250,816 |
| p2025 | 約248,560 |
| pmax | 0 |

データ生成時の日付範囲（2024-01-01〜2025-12-31）が、ほぼ半分ずつ2つの塊に分かれている。

### パーティションキーで絞る検索

```sql
EXPLAIN SELECT * FROM orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2025-02-01';
```

**【結果】** `partitions` 列が **`p2025` のみ**。
`created_at` が2025年の条件なので、MySQLは「p2024 と pmax は見る必要がない」と判断し、
最初から `p2025` の塊にしかアクセスしない。

（`p2025` の中はまだセカンダリインデックスがないのでフルスキャンだが、
少なくとも他の2つの塊は丸ごとスキップできている。`rows` は `p2025` 全体の行数≒約248,560。）

### パーティションキーと無関係な列で絞る検索

```sql
EXPLAIN SELECT * FROM orders_partitioned WHERE user_id = 100;
```

**【結果】** `partitions` 列が **`p2024,p2025,pmax`（全部）**、`rows` は約499,376（≒全行）。

**【なぜ？】** `user_id` はパーティションキー（`created_at` 由来）と何の関係もない。
どの年の引き出しに `user_id = 100` の注文が入っているか、MySQLには判断できない。
だから全部の引き出しを開けることになる。プルーニングが効かない。

### Before → After（プルーニングの効果）

| 検索条件 | アクセスするパーティション | プルーニング |
|---|---|---|
| `created_at` の範囲 | `p2025` のみ | ○ 効く |
| `user_id` の等値 | 全パーティション | × 効かない |

## 後片付け

```sql
DROP TABLE IF EXISTS orders_partitioned;
```

## まとめ

- パーティショニングは「テーブルを年度別キャビネットのように物理分割する」機能
- パーティションキーに関わる条件で絞れるクエリは、関係ない塊を丸ごとスキップできる（プルーニング）
- パーティションキーと無関係な条件には効果がない
- パーティションキーは全ユニークキーに含める必要がある（今回PKを `(id, created_at)` にした理由）
- **インデックスの代わりではない**。塊の中の絞り込みには従来どおりインデックスが要る。両者は併用するもの

## さらに詳しく

`ALTER TABLE orders_partitioned DROP PARTITION p2024;` を実行すると、
2024年分のデータが**一括で**削除される。
`DELETE FROM orders_partitioned WHERE YEAR(created_at) = 2024` と比べると:

- **速度**: `DROP PARTITION` は塊のファイルを丸ごと外すだけなので一瞬。
  `DELETE` は約25万行を1行ずつ削除し、そのぶんの undo ログ・インデックス更新も走るので遅い
- **安全性・運用**: `DROP PARTITION` は「2024年分」という境界が明確で、消しすぎる事故が起きにくい。
  一方、巨大な `DELETE` は長時間ロックを保持したり、レプリケーション遅延を招いたりしやすい

ログ・履歴データを「古い分から捨てていく」用途では、`DROP PARTITION` が定番の手段になる。
（試すなら必ず演習用の `orders_partitioned` の上で。試したら `DROP TABLE` で片付ける。）

## 次のステージへ

[Stage 9: クエリ書き換え実践（総合演習）](../09_query_rewriting_capstone/README.md) に進む。

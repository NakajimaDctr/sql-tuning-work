# Stage 6: 実行計画の内部を読む

## このステージでわかること

まず、SQLの結合の基本である **INNER JOIN と LEFT JOIN の違い**を整理する。
そのうえで、これまで見てきた `EXPLAIN` の「見積もり」に加えて、
`EXPLAIN ANALYZE` で**実際の実行時間・実行回数**を確認し、
MySQLが結合（JOIN）をどう処理しているか（**Nested Loop Join** / **Hash Join**）の
内部動作を理解する。

## 前提

[Stage 5: 統計情報とカーディナリティ](../05_statistics_cardinality/README.md) が終わっていること。
特別な準備は不要（既存のテーブルとインデックスをそのまま使う）。

---

## 結合の種類のおさらい ― INNER JOIN と LEFT JOIN

### 身近な例えで

「出席者名簿（`users`）」と「提出物リスト（`orders`）」を突き合わせる場面を考える。

- **INNER JOIN** = 「名簿にも提出物リストにも載っている人」だけを結果に残す。
  提出物を1つも出していない人は、結果から**消える**。
  → SQLでいうと「1回以上注文したユーザーだけ」が返る。
- **LEFT JOIN**（LEFT OUTER JOIN）= 「名簿（左のテーブル）の全員」を必ず残す。
  提出物がない人は、提出物の欄を **NULL** で埋めて表示する。
  → SQLでいうと「注文ゼロのユーザーも、注文列がNULLで返る」。

### 小さな例

```sql
-- INNER JOIN: 注文のあるユーザーだけ
SELECT u.id, u.name, o.id AS order_id
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.id IN (1, 2, 3);

-- LEFT JOIN: 注文ゼロのユーザーも残す（その行の order_id は NULL）
SELECT u.id, u.name, o.id AS order_id
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.id IN (1, 2, 3);
```

もし `u.id = 2` のユーザーが1件も注文していなければ、
INNER の結果には `id = 2` の行が**現れない**。LEFT の結果には
`(2, 名前, NULL)` という行が**1行だけ現れる**。

### よくある落とし穴：`ON` と `WHERE`

LEFT JOIN で「右のテーブルの条件」を `WHERE` 句に書くと、
NULL の行がその条件で弾かれてしまい、**実質 INNER JOIN に戻ってしまう**。

```sql
-- これは「注文ゼロのユーザー」も残る（意図どおりの LEFT JOIN）
SELECT u.id, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
GROUP BY u.id;

-- これは status = 'completed' の行がない人が消える（実質 INNER JOIN）
SELECT u.id, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.status = 'completed'
GROUP BY u.id;
```

「対応がない行も残したい」なら、右テーブルの絞り込み条件は `ON` 句に置く。

### 性能の観点

**本当に「対応がない行」も必要な場合以外は、INNER JOIN を使う**。
LEFT JOIN は「左は必ず全部残す」という制約があるぶん、
MySQLが結合の順序を自由に選べなくなる（左を先に読むしかない）ことがあり、
不要な行を保持する手間もかかる。詳しくは
[Stage 10 の「不要なLEFT JOINを避ける」](../10_query_tips/README.md) で扱う。

---

## まず現状を見てみる ― EXPLAIN ANALYZE

単純なJOINを `EXPLAIN ANALYZE` で見る。

```sql
EXPLAIN ANALYZE
SELECT o.id, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.id BETWEEN 1 AND 1000;
```

通常の `EXPLAIN` と違い、`EXPLAIN ANALYZE` は**実際にクエリを実行して**、
`actual time=...`（実測の所要時間）、`rows=...`（実測の行数）、
`loops=...`（そのステップが何回繰り返されたか）を表示する。

> 実際に実行するため、`UPDATE` / `DELETE` を `EXPLAIN ANALYZE` すると本当にデータが変わる。
> このステージでは `SELECT` のみを扱う。

**【結果の見方】** 出力の一例（ツリー形式。内側ほどインデントが深い）:

```
-> Nested loop inner join
     (cost=551 rows=1000) (actual time=0.17..4.03 rows=1000 loops=1)
   -> Filter: (o.id between 1 and 1000)
        (cost=201 rows=1000) (actual time=0.155..0.538 rows=1000 loops=1)
       -> Index range scan on o using PRIMARY over (1 <= id <= 1000)
            (cost=201 rows=1000) (actual time=0.154..0.429 rows=1000 loops=1)
   -> Single-row index lookup on u using PRIMARY (id=o.user_id)
        (cost=0.25 rows=1) (actual time=0.00326..0.00329 rows=1 loops=1000)
```

- 一番外側（`Nested loop inner join`）が最終結果。1000行返している。
- 内側の `Single-row index lookup on u` に **`loops=1000`** とある。
  これは「外側（`orders`）の1000行それぞれについて、内側（`users`）への
  インデックスルックアップを **1回ずつ、合計1000回** 行った」という意味。

## Nested Loop Join の仕組み

### 身近な例えで

「注文リスト（外側）」を1行ずつ見て、その行の `user_id` を持って
「会員名簿（内側）」を索引で1回引き、名前を取ってくる——を1000回繰り返す。

```
for 外側（orders）の各行:
    その user_id で内側（users）を索引で1回引く   ← インデックスがあれば一瞬
    結果を1行出力
```

総コストは **「外側の行数 × 内側1回あたりのコスト」**。
内側にインデックスがあれば1回あたりが軽いので、外側が1000行でも実用的な速度になる。
逆に内側にインデックスがないと、外側の行数だけ内側の全件スキャンを繰り返すことになり、非常に高くつく。

## Hash Join を発生させてみる

結合キーにインデックスがない場合、MySQLは Nested Loop の代わりに **Hash Join** を選ぶ。

```sql
EXPLAIN FORMAT=TREE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;
```

**【結果の見方】** 出力に `Inner hash join (r.product_id = oi.product_id)` が現れる。
`oi.product_id` にも `r.product_id` にもインデックスがないため、
「外側の1行ごとに内側を検索」という Nested Loop はコストが高すぎる。そこでMySQLは:

1. 片方のテーブル（小さい方。ここでは `WHERE` で5000件に絞った `order_items` 側）から
   **ハッシュテーブルをメモリ上に構築する**
2. もう片方（`reviews`）を **1回だけ**スキャンしながら、ハッシュテーブルと突き合わせる

### 身近な例えで

Nested Loop が「名簿Aを1人ずつ見て、その都度、名簿Bを索引で引く」だとすると、
Hash Join は「名簿Aの全員をまずメモ帳（ハッシュ表）に書き写しておき、
名簿Bを最初から最後まで1回だけ通しながら、メモ帳と照合していく」。
どちらの名簿も「全部見る」のは1回で済む（内側を何度も往復しない）。
インデックスがない大規模テーブル同士の結合では、Nested Loop より有利になりやすい。

## コスト見積もりを鵜呑みにしない

```sql
EXPLAIN ANALYZE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;
```

**【結果の見方】** 一例:

```
Inner hash join ... (cost=184e+6 rows=184e+6) (actual time=7.2..125 rows=99467 loops=1)
```

`cost` の見積もり（184,000,000）は非常に大きく見えるが、
実際の `actual time` は **125ミリ秒** 程度。
Hash Join のコスト見積もりは実際の処理時間と乖離することがある。
**`cost` の数字の大きさだけで判断せず、`actual time` などの実測で裏を取る**。

## まとめ

- **INNER JOIN** は両方に対応がある行だけ、**LEFT JOIN** は左を全部残し右をNULLで埋める。
  対応なしの行が要らないなら INNER を使う。右表の条件は `ON` に書く
- `EXPLAIN` は実行前の見積もり、`EXPLAIN ANALYZE` は実際に実行した実測値
- **Nested Loop Join**: 「外側の行数 × 内側1回のコスト」。内側にインデックスがあると効率的（`loops` が回数を示す）
- **Hash Join**（MySQL 8.0.18+）: 結合キーにインデックスがないとき選ばれる。片方をハッシュ化し、もう片方を1回スキャン
- `cost` は内部モデルの見積もり。実測値と併せて判断する

## さらに詳しく

`optimizer_switch` の `hash_join` フラグでHash Joinを無効化できる、と資料にはあるが……

```sql
SET SESSION optimizer_switch = 'hash_join=off';
EXPLAIN ANALYZE
SELECT oi.product_id, COUNT(*) FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id LIMIT 10;
SET SESSION optimizer_switch = 'hash_join=on';  -- 元に戻す
```

実は、このクエリでは `hash_join=off` にしても実行計画は変わらない（Hash Join のまま）。
MySQL 8.0.20 以降、それまであった「インデックスなし結合を力技のループで処理する方式」
（Block Nested-Loop）が廃止されたため、**インデックスが使えない結合では Hash Join が唯一の選択肢**
になっている。`hash_join` スイッチは「インデックスが使える場合に、Nested Loop と Hash Join の
どちらを優先するか」を制御するもので、今回のようにインデックスがないケースには効かない。
「資料の説明と、実際の挙動を照らし合わせる」ことの一例。

## 次のステージへ

[Stage 7: ロックとトランザクション](../07_locking_transactions/README.md) に進む。

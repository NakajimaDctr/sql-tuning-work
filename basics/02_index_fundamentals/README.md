# Stage 2: インデックスの基礎

## このステージでわかること

Stage 1で「インデックスがないと遅い」ことを見た。このステージでは実際に
`CREATE INDEX` でインデックスを1本追加し、EXPLAINの結果が `ALL` から `ref` へ、
`rows` が数万から数件へと変わる様子を自分の目で確認する。
あわせて、インデックスの仕組み（B-Tree）と、タダではないこと（書き込みコスト・ストレージ）を理解する。

## 前提

[Stage 1: EXPLAINの読み方](../01_explain_basics/README.md) が終わっていること。

この時点では `users`, `orders` に主キー以外のインデックスはない。確認するには次を実行する。

```sql
SHOW INDEX FROM users;
SHOW INDEX FROM orders;
```

`Key_name` が `PRIMARY` の行しか出てこなければOK。

## どんな問題？ ― 身近な例えで

もう一度、本の索引の話。索引のない本で1語を探すと全ページめくり（＝`type: ALL`）。
ところが**巻末の索引**があれば、語は五十音順（またはアルファベット順）に並んでいるので、
「か行のあたり」→「き」→「きゃ」…と一気に目的の位置へ飛べる。全ページをめくる必要はない。

データベースのインデックスもこれと同じで、**列の値をあらかじめ並べ替えて別に持っておく**仕組みだ。
MySQL（InnoDB）ではこの並べ替え済みの構造を **B-Tree**（多分岐のバランス木）で実装している。

```
インデックスなし: [行1][行2][行3] ... [行49999][行50000]   ← 先頭から順に確認（最悪5万回の比較）
インデックスあり: 並べ替え済みの木を上から数回たどるだけで、目的の値の位置に着く
```

「全件を1件ずつ（線形探索）」から「木を数回たどるだけ（対数時間に近い探索）」へ。
これがインデックスの効果の正体。

## まず現状を見てみる

Stage 1でも見た、`email` での検索を再確認する。

```sql
EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
```

想定される出力:

| クエリ | `type` | `key` | `rows` |
|---|---|---|---|
| `users WHERE email = '...'` | `ALL` | `NULL` | 約48,000 |
| `orders WHERE user_id = 100` | `ALL` | `NULL` | 約498,000 |

どちらもフルスキャン。ここに索引を足すと何が変わるかを見ていく。

## こう直す（指示）

`email` と `user_id` に、それぞれインデックスを作成する。

```sql
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);
```

**【目的】**
`WHERE email = ?` と `WHERE user_id = ?` という検索を、全行スキャンではなく
「並べ替え済みの木をたどる」形で解決できるようにする。
インデックス名（`idx_users_email` など）は分かりやすければ何でもよい。
慣習として `idx_テーブル名_列名` と付けることが多い。

作成には数万〜数十万行の並べ替えが走るため、`orders` 側は数秒かかることがある。

## 結果の見方 ― 何が変わったか

同じEXPLAINをもう一度実行する。

```sql
EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
```

**Before → After**

| クエリ | `type` | `key` | `rows` |
|---|---|---|---|
| `users WHERE email = '...'` | `ALL` → **`ref`** | `NULL` → **`idx_users_email`** | 約48,000 → **1** |
| `orders WHERE user_id = 100` | `ALL` → **`ref`** | `NULL` → **`idx_orders_user_id`** | 約498,000 → **約9〜10** |

**【変わった点】**

- `type` が `ALL`（全行スキャン）から `ref`（インデックスを使った等値検索）に変わった
- `key` に、いま作ったインデックス名が入った＝実際に使われている
- `rows`（調べる行数の見積もり）が桁違いに減った。
  `orders` の約9〜10 は「1ユーザーあたりの平均注文数（50万件 ÷ 5万人 = 10件）」とほぼ一致する

**【なぜ速くなったか】**
`email` の索引は値がソートされているので、目的の1件へ木をたどって直行できる。
`user_id` の索引も同様で、「`user_id = 100` の行だけ」がまとまって並んでいる場所へ飛び、
そこにある約10件だけを読めば済む。残りの約49万件は一切触らない。

**【トレードオフ / 注意】** インデックスは無料ではない。

- **ストレージ**: インデックス自体もディスク上のデータ構造として保存される（テーブルとは別に容量を食う）
- **書き込みコスト**: `INSERT` / `UPDATE` / `DELETE` のたびに、テーブル本体に加えて
  インデックスの並び順もメンテナンスする必要がある。インデックスが多いほど書き込みは遅くなる

だから「とりあえず全列にインデックスを張る」のは誤り。
**検索条件（WHERE・JOIN・ORDER BY）でよく使われる列**を優先して検討する。

## 現在のインデックスを確認する

```sql
SHOW INDEX FROM users;
SHOW INDEX FROM orders;
```

`Key_name` の列に `idx_users_email` / `idx_orders_user_id` が増えているはず。
`Cardinality`（値の種類数の推定）も表示される。これはStage 5で詳しく扱う。

## まとめ

- インデックスは「並べ替え済みの索引」。全件スキャンを、木を数回たどる探索に変える
- `CREATE INDEX 名前 ON テーブル(列)` で作る
- 効果は EXPLAIN の `type`（`ALL` → `ref` など）と `rows` の減少で確認する
- インデックスはストレージと書き込み性能のコストを伴う。よく検索する列に絞って張る

## さらに詳しく

`products.category_id` にインデックスを追加すると、
`SELECT * FROM products WHERE category_id = 5 AND price > 1000;` のEXPLAINはどうなるか。

```sql
CREATE INDEX idx_products_category_id ON products(category_id);
EXPLAIN SELECT * FROM products WHERE category_id = 5 AND price > 1000;
```

`price` には索引がないままでも、`type` は `ALL` から `ref` に変わる。
MySQLはまず `category_id = 5` の行だけをインデックスで絞り込み（数百件程度）、
そのうえで `price > 1000` はサーバー側でふるい分ける（`Extra: Using where`）。
「複数条件のうち、索引で絞れる条件だけでも先に効かせる」という動きが見える。
なお、2列とも索引で絞りたい場合は複合インデックスが必要になる（Stage 4）。

（このステージで作ったインデックスは後続ステージでも使う。消す場合は
`DROP INDEX idx_products_category_id ON products;` などで戻せる。）

## 次のステージへ

[Stage 3: N+1問題とアンチパターン](../03_antipatterns_n1/README.md) に進む。

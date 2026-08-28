# Stage 9: クエリ書き換え実践（総合演習）

## このステージでわかること

ここまで学んだこと——EXPLAINの読み方、インデックス設計、アンチパターンの回避、
複合インデックス、統計情報、実行計画の内部動作——を総動員して、
**複数の問題を同時に抱えた「悪いクエリ」を一緒に直していく**過程を追う。
1つの魔法のテクニックではなく、小さな改善の積み重ねでクエリが速くなることを体感する。

## 前提

基礎編・応用編 Stage 5〜8 まで。ここまでで作成したインデックスがそのまま使える前提。

## 進め方

各ケースについて、次のサイクルを回す。この「事実確認 → 仮説 → 1つずつ修正 → 再確認」が、
どんな環境でも変わらないチューニングの基本手順である。

1. まず現状のクエリを `EXPLAIN` し、`rows` の大きさと `Extra`（特に `Using filesort`）を見る
2. 含まれている問題を洗い出す
3. クエリの書き換え・インデックスの追加を、根拠とセットで行う
4. もう一度 `EXPLAIN` し、`rows` が減り `Using filesort` が消えたことを確認する

---

## ケースA: 「2024年6月に完了した注文」レポート

**要件**: 2024年6月に完了（`status = 'completed'`）した注文を、
注文者名付きで新しい順に一覧表示したい。

### まず現状を見てみる

```sql
EXPLAIN SELECT * FROM orders o, users u
WHERE o.user_id = u.id
  AND YEAR(o.created_at) = 2024 AND MONTH(o.created_at) = 6
  AND o.status = 'completed'
ORDER BY o.created_at DESC;
```

**【結果の見方】** 一例: `key: idx_orders_status`, `rows: 約249,518`,
`Extra: Using where; Using filesort`。

含まれている問題（Stage 3・4で見たものの組み合わせ）:

1. **`YEAR()` / `MONTH()` を `created_at` にかけている**（Stage 3のパターン3）。
   日付の範囲としての絞り込みができず、`created_at` の索引が使えない。結果、
   まず「`completed` 全体（約35万件）」を対象にしてしまっている
2. **`ORDER BY o.created_at DESC` のための並べ替えが別途必要**で `Using filesort` が出ている。
   `status` 単独の索引では、絞り込みはできても並び順までは保証できない
3. **`SELECT *`**（Stage 3のパターン4）。`email` や `address` など、レポートに不要な列まで取得している
4. 古い書き方の暗黙結合（`FROM a, b WHERE a.x = b.y`）。動くが、結合条件が `WHERE` に紛れて読みにくい

### こう直す（指示）

まず、`status`（等値条件）と `created_at`（範囲条件 かつ 並べ替え対象）の複合インデックスを作る。

```sql
CREATE INDEX idx_orders_status_created ON orders(status, created_at);
```

**【目的】** `status` を先頭、`created_at` を2番目にすることで、
「`completed` に絞る」→「その中は `created_at` 順に並んでいる」という構造にする。
すると、**絞り込みと並べ替えの両方をこの索引1本でまかなえる**。
（範囲・ソート対象の列を後ろに置く、というStage 4の指針そのもの。）

そのうえでクエリを書き換える。

```sql
EXPLAIN SELECT o.id, o.total_amount, o.created_at, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'completed'
  AND o.created_at >= '2024-06-01' AND o.created_at < '2024-07-01'
ORDER BY o.created_at DESC;
```

- `YEAR()/MONTH()` → `created_at` の**範囲条件**に書き換え（索引が使えるようになる）
- `SELECT *` → 必要な4列だけに
- 暗黙結合 → 明示的な `JOIN ... ON` に

### 結果の見方 ― 何が変わったか

一例: `key: idx_orders_status_created`, `rows: 約27,552`,
`Extra: Using index condition; Backward index scan`。

| | Before | After |
|---|---|---|
| `key` | `idx_orders_status` | `idx_orders_status_created` |
| `rows` | 約249,518 | **約27,552**（約9分の1） |
| 並べ替え | `Using filesort` | **消滅**（`Backward index scan`） |

**【なぜ速くなったか】**

- 範囲条件に直したことで、`completed` の中でも「2024年6月」の区間だけを索引でたどれる
- 索引の並び順（`status` の中で `created_at` 昇順）と `ORDER BY created_at DESC` の向きが一致するので、
  索引を**逆からたどるだけ**で並び順が完成する。別テーブルでの並べ替え（`Using filesort`）が不要になる。
  `Backward index scan` は「索引を逆順に読んでいる」というマークで、`filesort` よりずっと軽い
- `SELECT` を4列に絞ったことで、転送量が減る

---

## ケースB: 「商品レビュー一覧」機能

**要件**: 特定の商品（`product_id = 500`）のレビューを、
レビュアー名付きで新しい順に一覧表示したい。

### まず現状を見てみる

```sql
EXPLAIN SELECT * FROM reviews r, users u
WHERE r.user_id = u.id AND r.product_id = 500
ORDER BY r.created_at DESC;
```

**【結果の見方】** 一例: `type: ALL`, `key: NULL`, `rows: 約198,926`,
`Extra: Using where; Using filesort`。

`reviews.product_id` にインデックスがなく、全件スキャン。さらに `ORDER BY` で `Using filesort`。
ケースAと構造がそっくりであることに気づけるとよい。

### こう直す（指示）

```sql
CREATE INDEX idx_reviews_product_created ON reviews(product_id, created_at);
```

**【目的】** ケースAとまったく同じ型。
`product_id`（等値条件）を先頭、`created_at`（並べ替え対象）を2番目にした複合インデックス。

```sql
EXPLAIN SELECT r.id, r.rating, r.comment, r.created_at, u.name
FROM reviews r
JOIN users u ON r.user_id = u.id
WHERE r.product_id = 500
ORDER BY r.created_at DESC;
```

### 結果の見方 ― 何が変わったか

一例: `type: ref`, `key: idx_reviews_product_created`, `rows: 約18`,
`Extra: Backward index scan`（`filesort` なし）。

| | Before | After |
|---|---|---|
| `type` | `ALL` | `ref` |
| `rows` | 約198,926 | **約18** |
| 並べ替え | `Using filesort` | 消滅 |

`rows` が約20万から約18へ激減。ケースAと同じ「等値条件を先頭、ソート対象列を2番目にした
複合インデックス」で解決している。

---

## この型を覚えておく

ケースA・Bはどちらも、次の3手順で解決した。

1. **絞り込み条件を「インデックスが使える形」に書き換える**（関数を列にかけない、範囲条件にする）
2. **「等値条件の列 → 範囲/ソート対象の列」の順で複合インデックスを作る**
3. **`SELECT *` をやめ、必要な列だけ取得する**

特に「**等値条件を先頭、ソート対象を2番目にした複合インデックス**」は、
「一覧画面 ＋ 絞り込み ＋ 新着順ソート」という実務で頻出のパターンへの定石。
覚えておくと応用が利く。

## まとめ

- チューニングは個別テクニックの**組み合わせ**。一気に直そうとせず、1つずつ
- 手順は「EXPLAINで事実確認 → 仮説 → 1つ修正 → 再EXPLAIN」の繰り返し
- 「等値条件を先頭、ソート/範囲条件を後ろ」の複合インデックスは一覧系クエリの定石

## さらに詳しく

`orders` について、「特定ユーザーの、特定ステータスの注文を新しい順に一覧表示する」
（`WHERE user_id = ? AND status = ? ORDER BY created_at DESC`）を高速化するには、
どんな複合インデックスが最適か。

```sql
CREATE INDEX idx_orders_user_status_created ON orders(user_id, status, created_at);
EXPLAIN SELECT id, total_amount, created_at FROM orders
WHERE user_id = 100 AND status = 'completed'
ORDER BY created_at DESC;
DROP INDEX idx_orders_user_status_created ON orders;
```

`(user_id, status, created_at)` の順。等値条件が2つ（`user_id`, `status`）あるので
それを先頭2列に、ソート対象の `created_at` を3列目に置く。
すると `user_id = 100 AND status = 'completed'` の塊の中が `created_at` 順に並ぶので、
`Using filesort` なしで新着順を返せる（`Backward index scan`）。
これも「等値 → ソート対象」という同じ型の応用。

## 次のステージへ

[Stage 10: SQL効率化のためのtips](../10_query_tips/README.md) に進む。

# Stage 4: 複合インデックスとカバリングインデックス

## このステージでわかること

実務の検索は「複数の条件のAND」が多い。このステージでは複数の列にまたがる
**複合インデックス**の設計（特に**列の順序**が結果を左右すること＝左端一致の原則）と、
テーブル本体へのアクセスすら不要にする**カバリングインデックス**を理解する。
基礎編の締めくくりとして、ここまでの知識を組み合わせる。

## 前提

[Stage 2](../02_index_fundamentals/README.md)、[Stage 3](../03_antipatterns_n1/README.md) が終わっていること。
`orders` に `idx_orders_user_id`、`idx_orders_created_at` がある状態。

```sql
SHOW INDEX FROM orders;
```

## どんな問題？ ― 身近な例えで

紙の電話帳を思い出してほしい。エントリは「姓 → 名」の順で並んでいる。

- 「田中さん」を探す → 姓で並んでいるので、すぐたどり着ける
- 「田中 一郎さん」を探す → まず「田中」の塊へ行き、その中は名の順なので「一郎」もすぐ
- 「一郎さん」を（姓を問わず）探す → **無理**。名は「田中の中」「佐藤の中」…とバラバラに散っていて、
  電話帳の並びが一切使えない

複合インデックス `(A, B)` はこの電話帳とまったく同じ構造で、
「まずAで並べ、Aが同じものの中をBで並べる」。だから **先頭の列Aを条件に含まないと使えない**。
これを **左端一致の原則（Leftmost Prefix）** と呼ぶ。

## まず現状を見てみる

`orders` を「特定ユーザーの、特定ステータスの注文」で検索する場面を考える。

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'completed';
EXPLAIN SELECT * FROM orders WHERE status = 'completed';
```

1つ目は `idx_orders_user_id`（Stage 2で作成）が使われるが、
索引で絞れるのは `user_id = 100` の部分だけ。ヒットした十数件を1件ずつ見て
`status` をチェックすることになる。1ユーザー分なら大した量ではないが、
「2つの条件をどちらも索引で絞れたら、もっと効率的では？」というのがこのステージの出発点。

2つ目（`status` 単独）は、`status` にまだ索引がないので `type: ALL`。

## こう直す（指示）

`user_id` と `status` の複合インデックスを、**この列順で**作る。

```sql
CREATE INDEX idx_orders_user_status ON orders(user_id, status);
```

**【目的】**
`user_id = ? AND status = ?` という2条件を、1本の索引で一度に絞り込めるようにする。
列順を `(user_id, status)` にしたのは、`user_id` は単独でもよく検索する列であり、かつ
値の種類が多く（5万人分）絞り込み効果が高いから。電話帳でいう「姓」の位置に置く。

## 結果の見方 ― 何が変わったか

### 1. 2条件のAND検索

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'completed';
EXPLAIN SELECT * FROM orders WHERE status = 'completed' AND user_id = 100;  -- 条件の順を入れ替え
```

| クエリ | `type` | `key` | `key_len` | `rows` |
|---|---|---|---|---|
| `user_id = ? AND status = ?` | `ref` | `idx_orders_user_status` | 86（2列とも使用） | 約7 |
| 条件の順を入れ替えたもの | `ref` | `idx_orders_user_status` | 86 | 約7（**まったく同じ計画**） |

**【変わった点】** `user_id` だけでなく `status` も索引で絞れるようになり、`rows` がさらに減った。
`key_len` が「2列分」の長さになっているのが、両方の列が使われた証拠。

**【重要】** SQLに条件を書く順序（`WHERE user_id = ? AND status = ?` か
`WHERE status = ? AND user_id = ?` か）は**結果に影響しない**。
オプティマイザがインデックスの列順に合わせて内部的に処理する。
効くのは **インデックス定義時の列順** だけ。

### 2. 先頭列を含まない検索（左端一致の原則）

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'completed';
```

| `type` | `key` | 説明 |
|---|---|---|
| `ALL` | `NULL` | `(user_id, status)` の**先頭列 `user_id` を条件に含まない**ため、この索引は使えない |

電話帳で「名だけ」を引けないのと同じ。`status` 単独で速くしたいなら、`status` を先頭にした
別の索引が必要になる（ただし `status` は値が5種類しかない低カーディナリティ列なので、
それが有効かどうかはStage 5で検討する）。

### 3. カバリングインデックス

```sql
EXPLAIN SELECT user_id, status FROM orders WHERE user_id = 100;   -- 索引に含まれる列だけ
EXPLAIN SELECT * FROM orders WHERE user_id = 100;                 -- 索引にない列も要る
```

| クエリ | `type` | `key` | `Extra` |
|---|---|---|---|
| `SELECT user_id, status ...` | `ref` | `idx_orders_user_status` | **`Using index`** |
| `SELECT * ...` | `ref` | `idx_orders_user_status` | （`Using index` が付かない） |

**【変わった点】** `SELECT` する列（`user_id`, `status`）がすべて索引に含まれている1つ目は、
`Extra` に `Using index` が出た。これが **カバリングインデックス** の状態。

**【なぜ速いか】** 索引の中に、欲しい情報がすべて載っている。だからMySQLは
**テーブル本体（実データの行）を読みに行かない**。索引だけで結果を返せる。

一方 `SELECT *` は `created_at` や `total_amount` など索引にない列が必要なので、
索引で行の位置を特定したあと、**テーブル本体にもう一度アクセスする**（このランダムアクセスの分だけ遅い）。
Stage 3の「`SELECT *` の問題」がここに繋がる——不要な列まで取ると、カバリングの恩恵を失う。

### 4. 列の順序を逆にすると

```sql
CREATE INDEX idx_orders_status_user ON orders(status, user_id);
EXPLAIN SELECT * FROM orders WHERE user_id = 100;   -- 先頭が status の索引で、user_id 単独検索
DROP INDEX idx_orders_status_user ON orders;
```

`(status, user_id)` の先頭列は `status`。`user_id` だけの検索は「先頭列を使わない」ので
`type: ALL`。**同じ2列でも、順番を変えると使えるクエリが変わる**ことが確認できる。
（確認したら索引は消しておく。）

## 列の順序をどう決めるか

- 単独条件でもよく検索される列を先頭に置く
- 一般に「値の種類が多い（カーディナリティが高い）列」を先頭にすると絞り込みが効きやすい
- 範囲条件（`>` `<` `BETWEEN`）やソート対象の列は、等値条件の列より**後ろ**に置く
  （この型はStage 9の総合演習で使う）

この考え方の根拠（カーディナリティと統計情報）はStage 5で掘り下げる。

## まとめ

- 複合インデックス `(A, B)` は「Aで並べ、その中をBで並べる」電話帳と同じ構造
- **先頭列Aを含む条件でしか使えない**（左端一致の原則）。SQLの条件記述順は無関係
- `SELECT` 列がすべて索引に含まれると `Extra: Using index`＝カバリングインデックスで、
  テーブル本体を読まずに済む
- 同じ列でも、インデックスの列順で使えるクエリが変わる

## さらに詳しく

`(user_id, status, created_at)` という3列の複合インデックスを作ると、
`WHERE user_id = 100 ORDER BY created_at DESC` はソート処理（`Using filesort`）なしで実行できるか。

```sql
CREATE INDEX idx_orders_user_status_created ON orders(user_id, status, created_at);
EXPLAIN SELECT * FROM orders WHERE user_id = 100 ORDER BY created_at DESC;
DROP INDEX idx_orders_user_status_created ON orders;
```

答えは「できる」。索引は `user_id` ごとに、その中で `status`、さらにその中で `created_at` の順に
並んでいる。`user_id = 100` の塊の中は `created_at` 順（正確には `status`→`created_at` 順だが
`user_id` 固定なら `created_at` で並んでいるとみなせる区間がある）なので、
それを**逆からたどるだけ**で `ORDER BY created_at DESC` を満たせる。
EXPLAIN の `Extra` から `Using filesort` が消え、代わりに `Backward index scan` が出る。
「絞り込み条件の列 → ソート対象の列」の順で索引を作ると、絞り込みと並べ替えを1本でまかなえる。

## 次のステージへ

基礎編はここで終了。応用編 [Stage 5: 統計情報とカーディナリティ](../../advanced/05_statistics_cardinality/README.md) に進む。

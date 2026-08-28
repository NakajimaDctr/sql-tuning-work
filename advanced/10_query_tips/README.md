# Stage 10: SQL効率化のためのtips

## このステージでわかること

これまでの各ステージで断片的に触れた「実践的なSQLの書き方の指針」を、
辞書のように引ける形でまとめる。どれも「知っていれば避けられる」種類のもので、
1つずつは小さいが、積み重なると体感速度に効いてくる。

各tipは「困りごと → 身近な例え → Before / After → 何が変わるか」の順で読める。
数値が既存の題材で確認できるものは実測値を、そうでないものは
「`type` が `ALL` から `range` に変わる」といった定性的な表現で示す。

## 前提

Stage 1〜9 まで。特に [Stage 3（アンチパターン）](../../basics/03_antipatterns_n1/README.md)、
[Stage 4（複合・カバリング）](../../basics/04_composite_covering_index/README.md)、
[Stage 6（結合）](../06_execution_plan_internals/README.md) の内容を前提にする。

MySQLに接続しておく。

```bash
docker compose exec mysql mysql -uroot -prootpass sqltuning
```

---

## Tip 1: 不要な LEFT JOIN を避ける

### 困りごと

「とりあえず LEFT JOIN で書いておけば安全」と考えて、
本当は対応がある行しか要らないのに LEFT JOIN を使ってしまう。

### 身近な例えで

「全員必ずリストに載せる」というルールを課すと、名簿を作る側は
「まず名簿の全員を並べてから、対応する提出物を探す」しかできない。
「提出済みの人だけでいい」なら、少ない方（提出物）から並べる、という近道が選べる。

### Before / After

```sql
-- Before: 対応がある行しか使わないのに LEFT JOIN
SELECT o.id, u.name
FROM orders o
LEFT JOIN users u ON u.id = o.user_id
WHERE o.id BETWEEN 1 AND 1000;

-- After: 対応がない行は不要なので INNER JOIN
SELECT o.id, u.name
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.id BETWEEN 1 AND 1000;
```

### 何が変わるか

`orders.user_id` は必ず実在ユーザーを指すので、この2つは**同じ結果**を返す。
だが LEFT JOIN だとMySQLは「`orders` を先に読む」順序に縛られる。
INNER JOIN なら、統計情報を見てより有利な側から結合できる。
`EXPLAIN` の結合順（テーブルの並び）や `rows` の差で確認できることがある。

さらに、**LEFT JOIN のつもりで右表の条件を `WHERE` に書くと、実質 INNER JOIN に戻る**
（Stage 6の落とし穴）。対応なしの行を残したいなら、右表の絞り込みは `ON` 句へ。

```sql
-- 「completedの注文数（0件のユーザーも表示）」を出したいとき
-- OK: 条件を ON に置く
SELECT u.id, COUNT(o.id) AS cnt
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
GROUP BY u.id;

-- NG: WHERE に置くと 0件のユーザーが消える（実質 INNER JOIN）
SELECT u.id, COUNT(o.id) AS cnt
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.status = 'completed'
GROUP BY u.id;
```

**指針**: 「対応がない行も本当に必要か？」を毎回考える。不要なら INNER JOIN。

---

## Tip 2: `IN (サブクエリ)` より `EXISTS` や `JOIN`

### 困りごと

「◯◯した人の一覧」を、サブクエリで書いたら遅い。

### 身近な例えで

`EXISTS` は「1件でも見つかったら、そこで探すのをやめる」。
名簿から「1回でも注文した人」を探すとき、最初の1件が見つかった時点で
その人は確定なので、残りは見なくていい。

### Before / After

```sql
-- Before: IN (サブクエリ)。サブクエリ結果が大きいと不利なことがある
SELECT u.id, u.name
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.status = 'cancelled');

-- After 1: EXISTS（相関サブクエリだが「1件見つけたら打ち切り」）
SELECT u.id, u.name
FROM users u
WHERE EXISTS (
  SELECT 1 FROM orders o
  WHERE o.user_id = u.id AND o.status = 'cancelled'
);

-- After 2: JOIN + DISTINCT（重複を除くのを忘れずに）
SELECT DISTINCT u.id, u.name
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE o.status = 'cancelled';
```

### 何が変わるか

MySQL 8.0のオプティマイザは賢くなっていて、`IN (サブクエリ)` を内部的に
`EXISTS` 相当や semi-join に変換してくれることも多い。だが変換に失敗すると、
サブクエリが外側の行ごとに評価され、Stage 3のN+1に近いコストになる。
`EXPLAIN` で `select_type` に `DEPENDENT SUBQUERY` が出ていたら、
行ごとに再評価されているサイン。`EXISTS` や `JOIN` に書き換えると
`type` が改善したり、サブクエリのステップ自体が消えたりする。

**注意**: `NOT IN (サブクエリ)` は、サブクエリ側に1つでも `NULL` があると
結果が空になる罠がある。「◯◯していない人」は `NOT EXISTS` で書くのが安全。

---

## Tip 3: `SELECT *` をやめて必要な列だけにする

### 困りごと

デバッグ時のクセで、本番のクエリにも `SELECT *` を残してしまう。

### 身近な例えで

資料が1枚だけ欲しいのに、ファイル一式をまるごとコピーして持ち歩くようなもの。

### Before / After

```sql
-- Before
SELECT * FROM orders WHERE user_id = 100;

-- After
SELECT id, status, created_at FROM orders WHERE user_id = 100;
```

### 何が変わるか

- 転送するデータ量が減る（`TEXT` 型など大きい列を含むテーブルほど効く）
- **カバリングインデックスの可能性が開ける**。取得列がすべて索引に含まれていれば
  `Extra: Using index` になり、テーブル本体を読まずに済む（Stage 4）。
  `SELECT *` だとこの恩恵は絶対に得られない
- 列が追加されてもアプリ側の受け取りが壊れにくい

```sql
-- (user_id, status) の索引があるとき、取得列を絞るとカバリングになる
EXPLAIN SELECT user_id, status FROM orders WHERE user_id = 100;  -- Extra: Using index
```

---

## Tip 4: 大きな `OFFSET` のページネーションは遅い → キーセット方式

### 困りごと

一覧画面の「100ページ目」を開くと急に遅い。

### 身近な例えで

`LIMIT 20 OFFSET 2000` は、「2020件目から20件」を取るために
**先頭から2020件を毎回数え直して、最初の2000件を捨てている**。
ページが後ろになるほど、捨てる作業が増える。

### Before / After

```sql
-- Before: OFFSET 方式。ページが深いほど遅くなる
SELECT id, created_at FROM orders
ORDER BY id DESC
LIMIT 20 OFFSET 2000;

-- After: キーセット方式（seek method）。「前ページの最後のid」を条件にする
SELECT id, created_at FROM orders
WHERE id < :last_id_of_previous_page   -- 例: 前ページ最後の id
ORDER BY id DESC
LIMIT 20;
```

### 何が変わるか

キーセット方式は、主キー（またはソート用の索引）を使って
「`id < 前ページ最後の値` の場所」へ一発でジャンプし、そこから20件読むだけ。
**ページの深さに関係なく一定の速さ**になる。
「前へ／次へ」で十分な画面（無限スクロール、タイムラインなど）ではこちらが向く。
「任意のNページ目へジャンプ」が必須の場合は OFFSET を使わざるを得ないが、
その場合も「絞り込み条件を足してOFFSET対象そのものを小さくする」といった工夫をする。

---

## Tip 5: 暗黙の型変換でインデックスが無効化される

### 困りごと

`WHERE` で普通に等値比較しているのに、なぜか索引が使われず全件スキャン。

### 身近な例えで

索引は「数値は数値の並び」で作られている。そこへ文字列を渡すと、
MySQLは全行について「数値へ変換してから比べる」ことになり、
Stage 3の「列に関数をかける」のと同じ状態になる。

### Before / After

```sql
-- 数値列 user_id に、文字列リテラルを渡している
-- Before: '100' は文字列。MySQLが変換をはさみ、idx_orders_user_id が使いにくくなる場合がある
EXPLAIN SELECT * FROM orders WHERE user_id = '100';

-- After: 列の型に合わせて数値リテラルで比較する
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
```

### 何が変わるか

数値列 vs 文字列リテラルの場合、MySQLはリテラル側を数値化するため
比較的うまく索引を使えることが多い。だが逆——**文字列列に数値を渡す**と、
「列の側」を数値化することになり、索引が使えず `type: ALL` に落ちる。

- 文字列で保存されている列（電話番号、郵便番号、"0"始まりの商品コードなど）には
  必ず**文字列リテラル**（クオートつき）で比較する
- そもそも「先頭ゼロが意味を持つコード類」を数値型で保存しない（`0123` が `123` になる）
- アプリからバインドするときは、パラメータの型を列の型に合わせる

---

## Tip 6: `OR` を `IN` / `UNION ALL` に書き換える

### 困りごと

`WHERE a = 1 OR a = 5 OR a = 9` や、複数列にまたがる `OR` を書くと索引が効きにくい。

### Before / After

```sql
-- 同じ列の OR は IN にまとめる
-- Before
SELECT * FROM orders WHERE status = 'paid' OR status = 'shipped' OR status = 'completed';
-- After
SELECT * FROM orders WHERE status IN ('paid', 'shipped', 'completed');

-- 別々の列にまたがる OR は、それぞれ索引が効く形に分けて UNION ALL
-- Before: user_id と created_at の OR。片方ずつしか索引を活かせない
SELECT id FROM orders
WHERE user_id = 100 OR created_at >= '2025-12-01';
-- After: それぞれ索引の効くクエリにして足し合わせる（重複しうるなら UNION で除去）
SELECT id FROM orders WHERE user_id = 100
UNION
SELECT id FROM orders WHERE created_at >= '2025-12-01';
```

### 何が変わるか

同じ列の `OR` を `IN` にすると、MySQLは1本の索引で複数の値の範囲をまとめてたどれる
（`type: range`）。
別々の列にまたがる `OR` は、1本の索引では両方をカバーできないため
`type: ALL` になりがち。クエリを分けて `UNION (ALL)` すると、
各サブクエリがそれぞれ最適な索引を使える。
（`UNION` は重複除去のソートが入る。重複がありえない、または重複してよいなら
`UNION ALL` の方が速い。）

---

## Tip 7: `COUNT(*)` と `COUNT(col)` と `COUNT(DISTINCT col)` は別物

### 困りごと

「件数を数えるだけ」なのに、書き方で速さも結果も変わることを知らない。

### 違い

```sql
SELECT COUNT(*)            FROM reviews;              -- 全行数
SELECT COUNT(comment)      FROM reviews;              -- comment が NULL でない行数
SELECT COUNT(DISTINCT user_id) FROM reviews;          -- user_id の種類数（重複を除いた数）
```

- `COUNT(*)` … 行を数えるだけ。**NULLも数える**。InnoDBでは小さい索引を数え上げるので、
  `COUNT(1)` や `COUNT(col)` より不利になることはない（`COUNT(*)` でよい）
- `COUNT(列)` … その列が `NULL` の行を**除いて**数える。用途が違うので使い分ける
- `COUNT(DISTINCT 列)` … 重複排除のための一時的な集約が必要で、最も重い。
  乱発しない。必要なら対象を先に絞る

### 何が変わるか

「NULLを含めた全行が欲しい」のに `COUNT(some_nullable_col)` と書くと、
NULL行が数から漏れて**結果が間違う**。速さ以前に正しさの問題。
「件数」は基本 `COUNT(*)`、と覚えておく。

---

## Tip 8: `ORDER BY` + `LIMIT` は索引の並び順に合わせる

### 困りごと

「新着20件」を出すクエリで `Using filesort` が出て、データが増えるほど遅くなる。

### 身近な例えで

棚がすでに日付順に並んでいるなら、端から20個取るだけ。
バラバラの棚から集めてきて並べ直す（`filesort`）と、量が増えるほど大変になる。

### Before / After

```sql
-- Before: created_at に索引がない、または並び順が噛み合わない
EXPLAIN SELECT id, total_amount FROM orders
WHERE status = 'completed'
ORDER BY created_at DESC
LIMIT 20;
-- → Extra: Using filesort（絞り込んだ大量の行を毎回並べ替えている）

-- After: (status, created_at) の複合インデックスを用意する（Stage 9で作成済みなら不要）
-- CREATE INDEX idx_orders_status_created ON orders(status, created_at);
EXPLAIN SELECT id, total_amount FROM orders
WHERE status = 'completed'
ORDER BY created_at DESC
LIMIT 20;
-- → Extra から Using filesort が消え、Backward index scan になる
```

### 何が変わるか

「等値で絞る列 → 並べ替える列」の順で複合インデックスを作ると、
絞り込んだ結果がすでに `created_at` 順に並んでいる状態になる。
MySQLはそれを（DESCなら逆から）**20件読んだ時点で終われる**。
`filesort` は「候補を全部並べてから上位20件」なので、`LIMIT` があっても
候補が多いほど遅い。この差はデータ量が増えるほど開く。Stage 4・9で扱った定石そのもの。

---

## まとめ

| Tip | ひとことで |
|---|---|
| 1 | 対応なしの行が要らないなら INNER JOIN。右表の条件は `ON` に |
| 2 | `IN (サブクエリ)` が遅ければ `EXISTS` / `JOIN` へ。「〜でない」は `NOT EXISTS` |
| 3 | `SELECT *` をやめると転送量が減り、カバリングインデックスが狙える |
| 4 | 深いページは `OFFSET` でなくキーセット方式（前ページ最後の値で seek） |
| 5 | 列の型に合ったリテラルで比較する。コード類を数値型で持たない |
| 6 | 同じ列の `OR` は `IN`、別列の `OR` は `UNION (ALL)` に分ける |
| 7 | 件数は基本 `COUNT(*)`。`COUNT(列)` はNULLを除く別物。`DISTINCT` は重い |
| 8 | 「等値で絞る列 → 並べ替える列」の複合インデックスで `filesort` を消す |

共通する考え方は、Stage 3で出てきた一言に尽きる。

> インデックスは「並べ替え済みの値」を前提に速さを稼ぐ。
> 検索・結合・並べ替えを「索引に入っている値そのもの」を使う形に寄せると、速くなる。

## おわりに

お疲れ様でした。ここまでで、

- EXPLAIN を読み解いて「遅い理由」を言葉にする力
- インデックスを設計する力（単一・複合・カバリング・列順）
- 典型的なアンチパターンを避ける力
- オプティマイザの判断根拠（統計情報・結合方式）を推測する力
- 同時実行（ロック）の観点
- 実践的なクエリの書き方の引き出し

が身についているはずです。実務のデータベースはこの教材よりずっと複雑ですが、
**「まず EXPLAIN で事実を確認し、仮説を立てて一つずつ検証する」**という進め方は
どんな環境でも変わりません。

[トップページ](../../README.md) / [ロードマップ](../../roadmap.md) に戻る。

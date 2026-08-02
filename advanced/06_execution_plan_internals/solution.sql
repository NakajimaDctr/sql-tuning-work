-- ============================================================
-- Stage 6: 実行計画の内部を読む - 解答例
-- ============================================================

-- ---- 課題1, 2 ----
EXPLAIN ANALYZE
SELECT o.id, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.id BETWEEN 1 AND 1000;

-- 実行結果の例（ツリー形式、内側ほどインデントが深い）:
--
-- -> Nested loop inner join
--      (cost=551 rows=1000) (actual time=0.17..4.03 rows=1000 loops=1)
--    -> Filter: (o.id between 1 and 1000)
--         (cost=201 rows=1000) (actual time=0.155..0.538 rows=1000 loops=1)
--        -> Index range scan on o using PRIMARY over (1 <= id <= 1000)
--             (cost=201 rows=1000) (actual time=0.154..0.429 rows=1000 loops=1)
--    -> Single-row index lookup on u using PRIMARY (id=o.user_id)
--         (cost=0.25 rows=1) (actual time=0.00326..0.00329 rows=1 loops=1000)
--
-- 読み方:
--   - 一番外側(Nested loop inner join)が最終結果。1000行返している。
--   - 内側の "Single-row index lookup on u" に loops=1000 とある。
--     これは「外側(orders)の1000行それぞれについて、内側(users)への
--     インデックスルックアップを1回ずつ、合計1000回行った」ことを意味する。
--   - Nested Loop Joinは「外側のループ回数 × 内側1回あたりのコスト」で
--     総コストが決まる。内側にインデックスがあれば1回あたりが軽いので、
--     外側の行数が多くても現実的な速度で処理できる。


-- ---- 課題3: Hash Join ----
EXPLAIN FORMAT=TREE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;

-- => "Inner hash join (r.product_id = oi.product_id)" が出力される。
-- どちらのproduct_idにもインデックスがないため、Nested Loopで
-- 「外側の1行ごとに内側を検索」という戦略はコストが高くなりすぎる。
-- 代わりにMySQLは以下の戦略を取る:
--   1. 片方のテーブル(小さい方、ここではWHEREで絞り込んだorder_items側)
--      からハッシュテーブルをメモリ上に構築する (Hash)
--   2. もう片方のテーブル(reviews)を1回だけスキャンしながら、
--      ハッシュテーブルと突き合わせる (Table scan on r)
-- 結果として、どちらのテーブルも「全件見る」必要があるのは1回だけになる
-- (Nested Loopのように内側テーブルを外側の行数分だけ繰り返しアクセスしない)。

EXPLAIN ANALYZE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;

-- 実行結果の例:
--   Inner hash join ... (cost=184e+6 rows=184e+6) (actual time=7.2..125 rows=99467 loops=1)
--
-- cost の見積もり値(184,000,000)は非常に大きく見えるが、
-- 実際の actual time は 125ms 程度しかかかっていない。
-- Hash Joinのコスト見積もりは実際の処理コストと乖離することがあるため、
-- 「costの数字の大きさ」だけで判断せず、実測(EXPLAIN ANALYZE)で
-- 裏を取ることが重要。

-- ------------------------------------------------------------
-- 解説まとめ
-- ------------------------------------------------------------
-- - EXPLAIN は「実行前の見積もり」、EXPLAIN ANALYZE は「実際に実行した実測値」
-- - Nested Loop Join: 外側の行数 × 内側1回あたりのコストで決まる。
--   内側にインデックスがあれば効率的
-- - Hash Join (MySQL 8.0.18+): 結合キーにインデックスがない場合に選ばれやすい。
--   片方をハッシュ化し、もう片方を1回スキャンして突き合わせる
-- - cost見積もりを妄信せず、実測値と併せて判断する

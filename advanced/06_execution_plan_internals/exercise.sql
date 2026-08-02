-- ============================================================
-- Stage 6: 実行計画の内部を読む - 課題
-- ============================================================

-- ---- 課題1: EXPLAIN ANALYZE で実測値を見る ----
-- EXPLAIN が「見積もり」なのに対し、EXPLAIN ANALYZE は実際にクエリを
-- 実行した上で「実測値」も一緒に表示する。
EXPLAIN ANALYZE
SELECT o.id, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.id BETWEEN 1 AND 1000;

-- actual time=... rows=... loops=... の意味を読み解け。
-- 特に loops の値がなぜそうなるか（内側のテーブルへのアクセス回数）に注目せよ。


-- ---- 課題2: Nested Loop Join のコスト構造を理解する ----
-- 上のクエリは Nested Loop Join になっているはず。
-- 「外側1000行 × 内側1回ずつのインデックスアクセス」という構造を
-- EXPLAIN ANALYZE の出力から確認せよ。


-- ---- 課題3: Hash Join を発生させてみる ----
-- 結合キーにインデックスがない場合、MySQLはNested Loopの代わりに
-- Hash Joinを選択することがある。
EXPLAIN FORMAT=TREE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;

-- "Inner hash join" という表記を確認せよ。
-- oi.product_id にも r.product_id にもインデックスがないため、
-- MySQLはどちらのテーブルからも効率よく絞り込めない。
-- この場合、片方のテーブルからハッシュテーブルを作り、
-- もう片方を1回スキャンしながら突き合わせる方が効率的になる。

EXPLAIN ANALYZE
SELECT oi.product_id, COUNT(*)
FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id
LIMIT 10;

-- 実測の actual time を確認し、見積もりコスト(cost=...)の桁と比較せよ。
-- 見積もりコストが大きく見えても、実際の実行時間は短いことがある点に注目。

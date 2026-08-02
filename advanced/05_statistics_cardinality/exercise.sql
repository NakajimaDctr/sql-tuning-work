-- ============================================================
-- Stage 5: 統計情報とカーディナリティ - 課題
-- ============================================================

-- ---- 課題1: 低カーディナリティ列にインデックスを張ってみる ----
CREATE INDEX idx_orders_status ON orders(status);

-- 実際の値の分布を確認する
SELECT status, COUNT(*) AS actual_count
FROM orders
GROUP BY status
ORDER BY actual_count;

-- インデックスのカーディナリティ（MySQLが推定した「値の種類数」）を確認する
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';


-- ---- 課題2: 出現頻度の違う値でEXPLAINのrowsを比較する ----
-- 少数派の値 (cancelled) と多数派の値 (completed) で見積もり行数を比較せよ。
EXPLAIN SELECT * FROM orders WHERE status = 'cancelled';
EXPLAIN SELECT * FROM orders WHERE status = 'completed';

-- rows の見積もりと、課題1で調べた actual_count を比較してみよ。
-- ぴったり一致するだろうか？


-- ---- 課題3: 統計情報を更新する ----
ANALYZE TABLE orders;

SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
-- ANALYZE TABLE の前後でカーディナリティの値は変化しただろうか？


-- ---- 課題4: 統計情報の中身を直接覗いてみる ----
-- InnoDBは実は「ある程度サンプリングした結果」から統計情報を作っている。
SELECT * FROM mysql.innodb_table_stats WHERE table_name = 'orders';
SELECT * FROM mysql.innodb_index_stats
WHERE table_name = 'orders' AND index_name IN ('PRIMARY', 'idx_orders_status');

-- sample_size 列（サンプリングしたページ数）に注目せよ。
-- 全ページ数（n_leaf_pages）に対してどのくらいの割合をサンプルしているだろうか。

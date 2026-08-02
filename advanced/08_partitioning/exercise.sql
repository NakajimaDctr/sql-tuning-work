-- ============================================================
-- Stage 8: パーティショニング - 課題
--
-- 注意: このステージでは共有の orders テーブルは変更せず、
-- 演習専用のコピーテーブル orders_partitioned を新しく作って使う。
-- ============================================================

-- ---- 課題1: パーティション化テーブルを作成する ----
-- created_at の「年」でRANGEパーティショニングされたテーブルを作成せよ。
-- (ヒント: PARTITION BY RANGE (YEAR(created_at)) (...))
-- パーティションはp2024, p2025, pmax(それ以外)の3つに分けること。
-- パーティションキーに使う列は主キーに含める必要がある点に注意
-- (MySQLの制約: パーティションキーはテーブルの全てのユニークキーに含まれる必要がある)。

-- 以下のCREATE TABLE文を完成させて実行すること
-- (PARTITION BY句を自分で書き足す必要がある)
--
-- DROP TABLE IF EXISTS orders_partitioned;
-- CREATE TABLE orders_partitioned (
--   id INT UNSIGNED NOT NULL AUTO_INCREMENT,
--   user_id INT UNSIGNED NOT NULL,
--   status VARCHAR(20) NOT NULL,
--   total_amount INT UNSIGNED NOT NULL,
--   created_at DATETIME NOT NULL,
--   PRIMARY KEY (id, created_at)
-- ) ENGINE=InnoDB
-- PARTITION BY RANGE ( /* ここを埋める */ ) (
--   PARTITION p2024 VALUES LESS THAN ( /* ここを埋める */ ),
--   PARTITION p2025 VALUES LESS THAN ( /* ここを埋める */ ),
--   PARTITION pmax  VALUES LESS THAN MAXVALUE
-- );


-- ---- 課題2: 既存のordersデータをコピーする ----
-- (課題1のテーブルを作成してから実行すること)
INSERT INTO orders_partitioned SELECT * FROM orders;
ANALYZE TABLE orders_partitioned;

-- 各パーティションに何件ずつ入ったか確認する
SELECT PARTITION_NAME, TABLE_ROWS
FROM information_schema.PARTITIONS
WHERE TABLE_NAME = 'orders_partitioned';


-- ---- 課題3: パーティションプルーニングを確認する ----
-- created_at で範囲を絞ったクエリのEXPLAINを見て、
-- "partitions" 列が全パーティションではなく一部だけになっていることを確認せよ。
EXPLAIN SELECT * FROM orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2025-02-01';

-- 一方、パーティションキーに関係ない条件で検索した場合はどうなるか？
EXPLAIN SELECT * FROM orders_partitioned WHERE user_id = 100;
-- "partitions" 列を比較せよ。


-- ---- 後片付け ----
-- 演習が終わったら、他のステージに影響しないようテーブルを削除しておく。
DROP TABLE IF EXISTS orders_partitioned;

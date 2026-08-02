-- ============================================================
-- Stage 8: パーティショニング - 解答例
-- ============================================================

DROP TABLE IF EXISTS orders_partitioned;
CREATE TABLE orders_partitioned (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  status VARCHAR(20) NOT NULL,
  total_amount INT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id, created_at)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(created_at)) (
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

INSERT INTO orders_partitioned SELECT * FROM orders;
ANALYZE TABLE orders_partitioned;

-- ---- 課題2 ----
SELECT PARTITION_NAME, TABLE_ROWS
FROM information_schema.PARTITIONS
WHERE TABLE_NAME = 'orders_partitioned';
-- 実行結果の例:
--   p2024: 250,816件
--   p2025: 248,560件
--   pmax : 0件
-- データ生成時の日付範囲(2024-01-01〜2025-12-31)がほぼ半分ずつ2パーティションに分かれている。


-- ---- 課題3 ----
EXPLAIN SELECT * FROM orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2025-02-01';
-- => partitions: p2025 のみ
-- rows: 約248,560 (p2025パーティション全体の行数と一致。パーティション内は
-- まだセカンダリインデックスがないためパーティション内はフルスキャンだが、
-- 少なくとも p2024, pmax の2パーティションはそもそも見に行っていない)

EXPLAIN SELECT * FROM orders_partitioned WHERE user_id = 100;
-- => partitions: p2024,p2025,pmax (全パーティション)
-- rows: 約499,376 (全パーティション合計 ≒ 全行)
-- user_id はパーティションキー(created_at由来)と無関係な列なので、
-- MySQLはどのパーティションに該当データがあるか判断できず、
-- 結局すべてのパーティションを見にいく（プルーニングが効かない）。

DROP TABLE IF EXISTS orders_partitioned;

-- ------------------------------------------------------------
-- 解説まとめ
-- ------------------------------------------------------------
-- パーティショニングは「テーブルを物理的に複数の塊(パーティション)に
-- 分割して格納する」機能。パーティションキーに関わる条件で絞り込めるクエリは、
-- 関係ないパーティションを丸ごとスキップできる（パーティションプルーニング）。
--
-- 効果的なケース:
--   - 日付など、範囲で絞り込む検索が多い（例: 「直近1ヶ月分だけ集計する」）
--   - 古いパーティションを DROP PARTITION で一括削除できる
--     (大量のDELETEより高速。ログ・履歴データのアーカイブでよく使われる)
--
-- 注意点:
--   - パーティションキーに関係しない検索には効果がない（今回のuser_id検索の通り）
--   - パーティションキーはテーブルの全ユニークキーに含める必要がある
--     (今回 PRIMARY KEY を (id, created_at) の複合にしたのはこのため)
--   - パーティション数を増やしすぎると管理コストやメタデータのオーバーヘッドが増える
--   - 「インデックスの代わり」ではない。パーティション内の絞り込みには
--     従来通りインデックスが必要（このステージでは意図的にインデックスなしで
--     プルーニング単体の効果を確認した）

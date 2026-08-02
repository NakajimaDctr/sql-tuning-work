-- ============================================================
-- Stage 1: EXPLAINの読み方 - 課題
--
-- 以下の4つのクエリをそれぞれ EXPLAIN で実行し、
-- type / possible_keys / key / rows / Extra の値を確認せよ。
-- README.md の「課題」セクションの表を埋めながら進めること。
-- (この段階ではインデックスを追加しない。まずは「読む」練習)
-- ============================================================

-- Q1. 主キーでの検索
EXPLAIN SELECT * FROM users WHERE id = 100;

-- Q2. 主キー以外の列での検索（インデックスなし）
EXPLAIN SELECT * FROM orders WHERE user_id = 100;

-- Q3. インデックスのない列への文字列検索
EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';

-- Q4. 複数条件のAND検索（どちらの列にもインデックスなし）
EXPLAIN SELECT * FROM products WHERE category_id = 5 AND price > 1000;

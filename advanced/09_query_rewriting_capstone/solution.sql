-- ============================================================
-- Stage 9: クエリ書き換え実践（総合演習） - 解答例
-- ============================================================

-- ============================================================
-- 課題A: 「2024年6月に完了した注文」レポート
-- ============================================================

-- ---- Before ----
EXPLAIN SELECT * FROM orders o, users u
WHERE o.user_id = u.id
  AND YEAR(o.created_at) = 2024 AND MONTH(o.created_at) = 6
  AND o.status = 'completed'
ORDER BY o.created_at DESC;
-- => key: idx_orders_status, rows: 約249,518, Extra: Using where; Using filesort
--
-- 含まれている問題点（Stage 3, 4で学んだ内容の組み合わせ）:
--   1. YEAR()/MONTH() を created_at にかけているため、日付の範囲としての
--      絞り込みができず、「completed全体(約35万件のうち約25万件相当と見積もり)」
--      をまず対象にしてしまっている
--   2. status単体のインデックスはあるが、ORDER BY created_at のためのソートが
--      別途必要になり "Using filesort" が発生している
--   3. SELECT * で不要な列(email, address等)まで取得している

-- ---- After ----
-- status と created_at の複合インデックスを作る。
-- 理由: status(等値条件)を先頭、created_at(範囲条件 かつ ORDER BY対象)を
-- 2番目にすることで、絞り込みとソートの両方をこのインデックス1本でまかなえる。
CREATE INDEX idx_orders_status_created ON orders(status, created_at);

SELECT o.id, o.total_amount, o.created_at, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'completed'
  AND o.created_at >= '2024-06-01' AND o.created_at < '2024-07-01'
ORDER BY o.created_at DESC;

EXPLAIN SELECT o.id, o.total_amount, o.created_at, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'completed'
  AND o.created_at >= '2024-06-01' AND o.created_at < '2024-07-01'
ORDER BY o.created_at DESC;
-- => key: idx_orders_status_created, rows: 約27,552
--    Extra: Using index condition; Backward index scan
--
-- 変更点まとめ:
--   - YEAR()/MONTH() → created_at の範囲条件に書き換え（Stage 3）
--   - (status, created_at) の複合インデックスを追加（Stage 4）
--   - インデックスの並び順とORDER BYの並び順が一致しているため、
--     追加のソート処理なしで結果を返せる（"Backward index scan"は
--     インデックスを逆順に読むだけで済んでいることを示し、
--     "Using filesort"のような別テーブルでのソート処理より軽い）
--   - SELECT * をやめ、必要な列だけを取得（Stage 3）
--
-- rows が約249,518 → 約27,552 に減少（約9分の1）。


-- ============================================================
-- 課題B: 「商品レビュー一覧」機能
-- ============================================================

-- ---- Before ----
EXPLAIN SELECT * FROM reviews r, users u
WHERE r.user_id = u.id AND r.product_id = 500
ORDER BY r.created_at DESC;
-- => type: ALL, key: NULL, rows: 約198,926, Extra: Using where; Using filesort
-- reviews.product_id にインデックスがなく、全件スキャン＋ソートが発生している。

-- ---- After ----
CREATE INDEX idx_reviews_product_created ON reviews(product_id, created_at);

SELECT r.id, r.rating, r.comment, r.created_at, u.name
FROM reviews r
JOIN users u ON r.user_id = u.id
WHERE r.product_id = 500
ORDER BY r.created_at DESC;

EXPLAIN SELECT r.id, r.rating, r.comment, r.created_at, u.name
FROM reviews r
JOIN users u ON r.user_id = u.id
WHERE r.product_id = 500
ORDER BY r.created_at DESC;
-- => type: ref, key: idx_reviews_product_created, rows: 約18
--    Extra: Backward index scan (filesortなし)
--
-- rows が約198,926 → 約18 に激減。課題Aと同じパターン
-- （等値条件を先頭、ソート対象列を2番目にした複合インデックス）で解決している。

-- ------------------------------------------------------------
-- 総合演習のまとめ
-- ------------------------------------------------------------
-- 実務のチューニングは「1つの魔法のテクニック」ではなく、これまでのステージで
-- 学んだ個別の知識（EXPLAINを読む、インデックスを設計する、アンチパターンを
-- 避ける、複合インデックスの列順序を考える）を**組み合わせて**適用する作業。
-- 焦って全部を一気に直そうとせず、
--   1. EXPLAINで問題箇所を特定する
--   2. 一つずつ仮説を立てて修正する
--   3. 再度EXPLAINで効果を確認する
-- というサイクルを回すことが、このリポジトリ全体を通しての実践的な結論となる。

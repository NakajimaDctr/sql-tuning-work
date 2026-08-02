-- ============================================================
-- Stage 3: N+1問題とアンチパターン - 課題
-- ============================================================

-- ---- 課題1: N+1問題 ----
-- 「注文一覧を取得し、それぞれの注文の明細をアプリ側でループして取得する」
-- という典型的なN+1実装を、まずシェルで疑似的に再現する。
-- (このSQLファイルではなく、ターミナルで以下を実行すること)
--
--   time (for i in $(seq 1 100); do
--     docker compose exec -T mysql mysql -uroot -prootpass sqltuning \
--       -e "SELECT * FROM order_items WHERE order_id = $i;" > /dev/null
--   done)
--
-- 実行時間を記録しておく。

-- ---- 課題1の改善版 ----
-- 100回のクエリを1回にまとめて実行し、実行時間を比較せよ。
SELECT * FROM order_items WHERE order_id BETWEEN 1 AND 100;

-- 上と同じ結果を IN句で取得する場合 (アプリ側で取得したIDリストを渡す想定)
-- SELECT * FROM order_items WHERE order_id IN (1,2,3,...,100);


-- ---- 課題2: 先頭ワイルドカードLIKE ----
-- Stage 2で users.email にインデックスを追加済みの前提。
-- 以下2つのクエリのEXPLAINを比較し、type/keyの違いを確認せよ。

EXPLAIN SELECT * FROM users WHERE email LIKE 'user012345%';        -- 前方一致
EXPLAIN SELECT * FROM users WHERE email LIKE '%johndoe@example.com'; -- 先頭に%（中間一致/後方一致）


-- ---- 課題3: インデックス列に関数をかけてしまう ----
-- orders.created_at にインデックスを追加してから確認する。
CREATE INDEX idx_orders_created_at ON orders(created_at);

-- 同じ「2024年6月」を条件にした2通りの書き方を比較せよ。
EXPLAIN SELECT * FROM orders
WHERE YEAR(created_at) = 2024 AND MONTH(created_at) = 6;

EXPLAIN SELECT * FROM orders
WHERE created_at >= '2024-06-01' AND created_at < '2024-07-01';


-- ---- 課題4: SELECT * の問題 ----
-- 必要な列だけを取得する場合と何が違うか、EXPLAINのExtraと
-- 転送されるデータ量の観点で考えてみよ（Stage 4のカバリングインデックスにも繋がる）。
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
EXPLAIN SELECT id, status FROM orders WHERE user_id = 100;

-- ============================================================
-- Stage 5: 統計情報とカーディナリティ - 解答例
-- ============================================================

-- (idx_orders_status は exercise.sql の課題1で既に作成済みの前提)

-- ---- 課題1 ----
-- 実測値の例:
--   cancelled : 24,712
--   pending   : 24,794
--   shipped   : 49,997
--   paid      : 50,239
--   completed : 350,258   <- 全体の約70%
--
-- SHOW INDEX の Cardinality 列は「3」程度と表示されることが多い
-- （実際の値の種類は5つなのに、である点に注目）。


-- ---- 課題2 ----
EXPLAIN SELECT * FROM orders WHERE status = 'cancelled';
-- => rows: 約49,750 (実際は24,712 → 約2倍の過大見積もり)

EXPLAIN SELECT * FROM orders WHERE status = 'completed';
-- => rows: 約249,000 (実際は350,258 → 過小見積もり)
--
-- どちらも実際の件数とはズレている。MySQLのオプティマイザは
-- テーブル全体をスキャンして正確な件数を数えているわけではなく、
-- 「統計情報（サンプリングした推定値）」を使って見積もりを立てている。


-- ---- 課題3 ----
ANALYZE TABLE orders;
SHOW INDEX FROM orders WHERE Key_name = 'idx_orders_status';
-- Cardinalityの値はANALYZE TABLE後もほぼ変わらないことが多い。
-- サンプリング方式が変わらない限り、同じような推定値になるため。


-- ---- 課題4 ----
SELECT * FROM mysql.innodb_table_stats WHERE table_name = 'orders';
SELECT * FROM mysql.innodb_index_stats
WHERE table_name = 'orders' AND index_name IN ('PRIMARY', 'idx_orders_status');
--
-- 実行例:
--   idx_orders_status: n_leaf_pages=576, sample_size=6
--
-- つまり576ページ中わずか6ページ（約1%）だけをサンプリングして
-- 「値の種類数は3」と推定している。これが実測値(5種類)とズレる理由。
--
-- サンプルページ数は innodb_stats_persistent_sample_pages
-- (デフォルト20)で調整可能だが、増やすほどANALYZE TABLEのコストも増える。

-- ------------------------------------------------------------
-- 解説まとめ
-- ------------------------------------------------------------
-- MySQLのオプティマイザは「テーブルの一部をサンプリングして作った統計情報」を
-- もとに実行計画を決めている。そのため:
--   - rows の見積もりは常に「近似値」であり、実測値とズレることがある
--   - カーディナリティが低い（値の種類が少ない）列は、インデックスを張っても
--     絞り込み効果が薄い場合がある（'completed'のように7割を占める値では、
--     インデックス経由でも結局大半の行を読むことになる）
--   - 統計情報が古い/不正確だと、オプティマイザが誤った実行計画
--     （非効率なインデックスの選択や、逆にインデックスを使わない判断）を
--     下すことがある。データ量が大きく変わった後は ANALYZE TABLE を検討する

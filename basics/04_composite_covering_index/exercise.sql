-- ============================================================
-- Stage 4: 複合インデックスとカバリングインデックス - 課題
-- ============================================================

-- ---- Before ----
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'completed';
EXPLAIN SELECT * FROM orders WHERE status = 'completed';

-- ---- 課題1: 複合インデックスを作成する ----
-- user_id と status の両方を条件にする検索が速くなるインデックスを作成せよ。
-- 列の順序（どちらを先にするか）も考えること。

-- ここに自分の CREATE INDEX 文を書く
-- CREATE INDEX ... ON orders(...);


-- ---- 課題1のAfter確認 ----
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'completed';
-- 条件の順序を入れ替えても結果が同じか確認
EXPLAIN SELECT * FROM orders WHERE status = 'completed' AND user_id = 100;

-- 一方の列（status）だけで検索した場合はどうなるか？
EXPLAIN SELECT * FROM orders WHERE status = 'completed';


-- ---- 課題2: カバリングインデックスを体験する ----
-- 作成した複合インデックスの列だけをSELECTした場合のExtraを確認せよ。
EXPLAIN SELECT user_id, status FROM orders WHERE user_id = 100;
-- Extra に "Using index" が出ればカバリングインデックスが効いている。

EXPLAIN SELECT * FROM orders WHERE user_id = 100;
-- SELECT * の場合と比較する（インデックスに無い列(created_at等)が必要なため
-- テーブル本体へのアクセスが発生する）。


-- ---- 課題3: 列の順序を逆にすると何が起きるか ----
-- (status, user_id) の順で複合インデックスを作った場合、
-- user_id 単独の検索は速くなるか？予想してから確認してみよ。

-- CREATE INDEX idx_orders_status_user ON orders(status, user_id);
-- EXPLAIN SELECT * FROM orders WHERE user_id = 100;
-- DROP INDEX idx_orders_status_user ON orders;

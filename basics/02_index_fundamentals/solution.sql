-- ============================================================
-- Stage 2: インデックスの基礎 - 解答例
-- ============================================================

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- ---- After: インデックス追加後のEXPLAIN ----

EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';
-- => type: ref, key: idx_users_email, rows: 1
-- フルスキャン(rows≒48,000)から、インデックスを使った検索(rows=1)に変化する。

EXPLAIN SELECT * FROM orders WHERE user_id = 100;
-- => type: ref, key: idx_orders_user_id, rows: 約9〜10
-- 1ユーザーあたりの平均注文数(500,000件 / 50,000人 = 10件)程度まで絞り込めている。

-- ------------------------------------------------------------
-- 解説
-- ------------------------------------------------------------
-- インデックスはB-Tree（平衡木）構造で「列の値 → 行の位置」を
-- あらかじめソートして持っておくデータ構造。
-- これにより、目的の値を探すのに全行を読む必要がなくなり、
-- 二分探索的にO(log n)に近い計算量でアクセスできるようになる。
--
-- ただしインデックスはタダではない。
--   - ストレージを追加で消費する（インデックス自体もデータ構造として保存される）
--   - INSERT/UPDATE/DELETE のたびにインデックスも更新する必要があるため、
--     書き込み性能はやや低下する
-- 「読み取りが多く、書き込みが少ない列」から優先的にインデックスを検討するのが基本。
--
-- 元に戻す場合（他のステージへの影響を避けたい場合）:
-- DROP INDEX idx_users_email ON users;
-- DROP INDEX idx_orders_user_id ON orders;

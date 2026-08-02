-- ============================================================
-- Stage 2: インデックスの基礎 - 課題
-- ============================================================

-- ---- Before: インデックスを追加する前のEXPLAINを確認 ----

EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';

EXPLAIN SELECT * FROM orders WHERE user_id = 100;

-- ---- 課題1 ----
-- 上記2つのクエリが「インデックスを使う」ようになるインデックスを
-- 自分で CREATE INDEX して作成してみよ。
-- (ヒント: CREATE INDEX <インデックス名> ON <テーブル名>(<列名>);)

-- ここに自分の CREATE INDEX 文を書いて実行する
-- CREATE INDEX ... ON users(...);
-- CREATE INDEX ... ON orders(...);


-- ---- After: インデックス追加後に再度EXPLAINを確認 ----

EXPLAIN SELECT * FROM users WHERE email = 'user012345.johndoe@example.com';

EXPLAIN SELECT * FROM orders WHERE user_id = 100;

-- typeが変わったか、rowsが減ったかを確認すること。


-- ---- 課題2: 既存のインデックスを確認する ----
SHOW INDEX FROM users;
SHOW INDEX FROM orders;

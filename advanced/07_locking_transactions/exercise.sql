-- ============================================================
-- Stage 7: ロックとトランザクション - 課題
--
-- このステージは複数のクエリを"同時に"実行して挙動を観察する必要があるため、
-- 通常のexercise.sqlのように1つのファイルを実行するのではなく、
-- ターミナルを2つ開いて、それぞれで docker compose exec を起動して進める。
--
--   ターミナルA: docker compose exec mysql mysql -uroot -prootpass sqltuning
--   ターミナルB: docker compose exec mysql mysql -uroot -prootpass sqltuning
--
-- 以下は「どちらのターミナルで」「どの順番で」実行するかのシナリオ。
-- README.md の指示と合わせて進めること。
-- ============================================================

-- ============================================================
-- シナリオ1: 行ロック (Row Lock)
-- ============================================================
-- [ターミナルA]
BEGIN;
UPDATE orders SET status = 'paid' WHERE id = 1;
-- ここでコミットせずに待機する

-- [ターミナルB] (Aがコミットする前に実行する)
UPDATE orders SET status = 'cancelled' WHERE id = 1;
-- => 応答が返ってこない(ブロックされる)はずである。しばらく待って様子を見る。

-- [ターミナルA] (Bがブロックされているのを確認したら)
ROLLBACK;
-- => これでターミナルBの UPDATE がようやく完了するはずである。


-- ============================================================
-- シナリオ2: ギャップロック (Gap Lock)
-- ============================================================
-- [ターミナルA]
BEGIN;
SELECT COUNT(*) FROM orders
WHERE created_at BETWEEN '2030-01-01' AND '2030-01-02'
FOR UPDATE;
-- 対象期間には実際には1件もデータがない(空のギャップ)

-- [ターミナルB] (Aがコミットする前に実行する)
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (1, 'pending', 1000, '2030-01-01 12:00:00');
-- => 該当データが1件もないのに、なぜかブロックされるはずである。

-- [ターミナルA]
ROLLBACK;
-- => ターミナルBのINSERTが完了する。
-- (このINSERTで作られたテストデータは、確認後に自分で削除しておくこと)
-- DELETE FROM orders WHERE created_at = '2030-01-01 12:00:00';


-- ============================================================
-- シナリオ3: デッドロック (Deadlock)
-- ============================================================
-- [ターミナルA]
BEGIN;
UPDATE orders SET status = 'paid' WHERE id = 1;

-- [ターミナルB]
BEGIN;
UPDATE orders SET status = 'paid' WHERE id = 2;

-- [ターミナルA] (id=2 は B がロック中 → ブロックされる)
UPDATE orders SET status = 'paid' WHERE id = 2;

-- [ターミナルB] (id=1 は A がロック中 かつ Aはid=2待ちで止まっている → 循環待ち)
UPDATE orders SET status = 'paid' WHERE id = 1;
-- => 数秒後、どちらか一方が
--    "ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction"
--    というエラーで強制的にロールバックされ、もう片方は処理を続行できるようになる。

-- 最後に両方のターミナルで ROLLBACK; しておく（エラーになった側は既にロールバック済み）。
ROLLBACK;

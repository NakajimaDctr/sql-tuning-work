-- ============================================================
-- Stage 4: 複合インデックスとカバリングインデックス - 解答例
-- ============================================================

-- 「user_id = ? のみ」「user_id = ? AND status = ?」の両方でよく検索される
-- 想定なので、より選択性の高い user_id を先頭にする。
CREATE INDEX idx_orders_user_status ON orders(user_id, status);

-- ---- 課題1のAfter確認 ----
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'completed';
-- => type: ref, key: idx_orders_user_status, key_len: 86 (=user_idとstatus両方使用), rows: 約7
EXPLAIN SELECT * FROM orders WHERE status = 'completed' AND user_id = 100;
-- => 上と全く同じ実行計画になる。SQLの条件を書く順序は関係なく、
--    オプティマイザがインデックスの列順序に合わせて内部的に処理する。

EXPLAIN SELECT * FROM orders WHERE status = 'completed';
-- => type: ALL, key: NULL, rows: 全行
-- (user_id, status) の複合インデックスは「先頭列(user_id)を条件に含まない」
-- 検索には使えない。これを「左端一致の原則(leftmost prefix)」と呼ぶ。


-- ---- 課題2: カバリングインデックス ----
EXPLAIN SELECT user_id, status FROM orders WHERE user_id = 100;
-- => type: ref, key: idx_orders_user_status, Extra: Using index
-- SELECTする列(user_id, status)がすべてインデックスに含まれているため、
-- テーブル本体(データ行)を読みに行かずインデックスだけで結果を返せる。
-- これが「カバリングインデックス」。テーブル本体へのI/Oが発生しない分、高速。

EXPLAIN SELECT * FROM orders WHERE user_id = 100;
-- => type: ref, key: idx_orders_user_status, Extra: (Using indexが付かない)
-- created_at や total_amount 等インデックスに含まれない列が必要なため、
-- インデックスで行の位置を特定した後、テーブル本体にもアクセスする
-- （この追加アクセスを「ランダムI/O」と呼び、カバリングインデックスはこれを避けられる）。


-- ---- 課題3: 列の順序を逆にした場合 ----
CREATE INDEX idx_orders_status_user ON orders(status, user_id);
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
-- => type: ALL, key: NULL
-- (status, user_id) の先頭列は status。user_id だけを条件にした検索では
-- 「先頭列を使わない」ことになるため、このインデックスは使われない。
DROP INDEX idx_orders_status_user ON orders;

-- ------------------------------------------------------------
-- 解説まとめ
-- ------------------------------------------------------------
-- 複合インデックス (A, B) は「Aで絞り込み、その中でBでさらに絞り込む」
-- という辞書式順序で値を保持している（電話帳が姓→名の順で並んでいるのと同じ）。
-- そのため、
--   - A単独の検索       : 使える
--   - A AND B の検索      : 使える（最も効果的）
--   - B単独の検索        : 使えない（先頭列を飛ばせない）
--
-- インデックスの列順序は「単独でもよく検索される列」「選択性(カーディナリティ)が
-- 高い列」を先頭に置くのが基本方針（詳細はStage 5で扱う）。

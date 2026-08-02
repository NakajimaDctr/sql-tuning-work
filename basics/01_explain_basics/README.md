# Stage 1: EXPLAINの読み方

## 概要/ゴール

SQLチューニングの第一歩は「今のクエリが遅い理由をEXPLAINで説明できる」こと。
このステージでは `EXPLAIN` の主要なカラムの意味を理解し、
「速いクエリ」と「遅いクエリ」をEXPLAINの出力から見分けられるようになることを目指す。
このステージではインデックスの追加は行わず、まず「読む」ことに集中する。

## 前提知識

[Stage 0: 環境構築](../00_setup/README.md) が完了していること。

## 事前準備

```bash
docker compose exec mysql mysql -uroot -prootpass sqltuning
```

でMySQLに接続しておく。

## 悪いクエリを実行してEXPLAINを見る

まず、次のクエリを実行してみる。

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
```

結果はおおよそ次のようになる。

```
+----+-------------+--------+------+---------------+------+------+------+--------+-------------+
| id | select_type | table  | type | possible_keys | key  | rows | ...  | Extra       |
+----+-------------+--------+------+---------------+------+------+------+--------+-------------+
| 1  | SIMPLE      | orders | ALL  | NULL          | NULL | 498521 | ... | Using where |
```

`type: ALL` は「フルテーブルスキャン」を意味する。`rows: 498521` は
「このクエリのために約49万行を1件ずつ確認する見積もり」ということ。
`orders` テーブル全体がだいたいそのくらいの行数なので、実質「全部見ている」。
`user_id = 100` にヒットする行は実際には数件〜十数件しかないにもかかわらず、
インデックスがないためMySQLは全行を確認するしかない。これが「遅いクエリ」の典型例。

## 課題

`exercise.sql` の4つのクエリをそれぞれ実行し、以下の表を埋めよ（実際に手を動かして確認すること）。

| # | クエリ | type | key | rows(概算) | Extra |
|---|---|---|---|---|---|
| Q1 | `users WHERE id = 100` | ? | ? | ? | ? |
| Q2 | `orders WHERE user_id = 100` | ? | ? | ? | ? |
| Q3 | `users WHERE email = '...'` | ? | ? | ? | ? |
| Q4 | `products WHERE category_id = 5 AND price > 1000` | ? | ? | ? | ? |

**達成基準**: 4つのクエリについて、「なぜそのtypeになるのか」「keyがNULLなのはなぜか」を
自分の言葉で説明できること。

## 解答例

[`solution.sql`](./solution.sql) に各クエリの想定結果と解説を記載している。
自分で表を埋めてから答え合わせすること。

## 解説

### EXPLAINの主要カラム

| カラム | 意味 |
|---|---|
| `type` | アクセス方法。`const` `eq_ref` `ref` `range` `index` `ALL` の順に効率が落ちる |
| `possible_keys` | 使える可能性があったインデックス。`NULL`なら候補自体が存在しない |
| `key` | 実際に使われたインデックス。`NULL`なら何も使われていない |
| `rows` | このステップで読むとオプティマイザが見積もった行数（概算値。Stage 5で詳しく扱う） |
| `Extra` | 補足情報。`Using where` `Using index` `Using filesort` `Using temporary` など |

### typeの目安

- `const` / `system`: 主キーやユニークキーで1行に確定する最速のアクセス
- `eq_ref`: JOINで相手側が1行に確定するユニークキー参照
- `ref`: 非ユニークインデックスでの等値検索
- `range`: インデックスを使った範囲検索（`BETWEEN`, `<`, `>`, `IN`など）
- `index`: インデックス自体は全部読むが、テーブル本体は読まない
- `ALL`: フルテーブルスキャン。これが出たら要注意

### rowsとフィルタ後の結果件数は別物

Q3（`email`検索）は実際には1件しかヒットしないクエリだが、`rows`は約48,000だった。
これは「実際に返る行数」ではなく「調べるためにアクセスする行数」を表しているため。
インデックスがないと、結果が1件でも全件確認が必要になる。これがインデックスの本質的な効果
（Stage 2で扱う）。

## 発展問題（任意）

次のクエリのtypeとExtraを予想してから実行し、当たっているか確認してみよう。

```sql
EXPLAIN SELECT COUNT(*) FROM orders;
EXPLAIN SELECT * FROM orders ORDER BY id DESC LIMIT 10;
```

## 次のステージへ

[Stage 2: インデックスの基礎](../02_index_fundamentals/README.md) に進む。

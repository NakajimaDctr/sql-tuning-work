# Stage 0: 環境構築

## 概要/ゴール

このリポジトリの学習環境（MySQL 8.0 ＋ ECサイト風のサンプルデータ）を手元で起動し、
接続できる状態にする。これ以降の全ステージは、この環境が起動していることが前提。

## 事前準備

- Docker / Docker Compose が使えること（`docker --version`, `docker compose version`）
- ポート `3306` が空いていること（他のMySQLが起動していないか確認）

## 手順

### 1. 環境を起動する

リポジトリのルートで以下を実行する。

```bash
docker compose up -d --build
```

初回は以下が自動的に行われる。

1. MySQLコンテナが起動し、`docker/mysql/init/` 配下のSQL（テーブル定義・マスタデータ）が自動投入される
2. MySQLが起動完了 (healthcheckがHealthyになる) すると `seeder` コンテナが動き出し、
   ユーザー5万件・商品1万件・注文50万件・注文明細約150万件・レビュー20万件のサンプルデータを生成する

データ生成には数分かかる。進捗はログで確認できる。

```bash
docker compose logs -f seeder
```

`データ生成が完了しました。` と表示され、コンテナが終了 (exit code 0) すれば完了。

### 2. 接続確認

```bash
docker compose exec mysql mysql -uroot -prootpass sqltuning
```

MySQLのプロンプトに入ったら、件数を確認する。

```sql
SELECT
  (SELECT COUNT(*) FROM categories)  AS categories,
  (SELECT COUNT(*) FROM users)       AS users,
  (SELECT COUNT(*) FROM products)    AS products,
  (SELECT COUNT(*) FROM orders)      AS orders,
  (SELECT COUNT(*) FROM order_items) AS order_items,
  (SELECT COUNT(*) FROM reviews)     AS reviews;
```

`users` が50000件などになっていればOK。

### 3. GUIクライアントを使いたい場合（任意）

MySQL Workbench や DBeaver、TablePlus等からも接続できる。

- Host: `127.0.0.1`
- Port: `3306`
- User: `root`
- Password: `rootpass`
- Database: `sqltuning`

## サンプルスキーマ

このリポジトリ全体を通して使う、ECサイトの注文管理を模したスキーマ。

| テーブル | 概要 | 件数目安 |
|---|---|---|
| `categories` | 商品カテゴリ（マスタ、低カーディナリティ） | 40 |
| `users` | 会員 | 50,000 |
| `products` | 商品（`category_id`でカテゴリに紐づく） | 10,000 |
| `orders` | 注文（`user_id`で会員に紐づく、`status`は低カーディナリティ） | 500,000 |
| `order_items` | 注文明細（`order_id`, `product_id`に紐づく） | 約1,260,000 |
| `reviews` | 商品レビュー（`product_id`, `user_id`に紐づく） | 200,000 |

**重要**: このスキーマは意図的に主キー以外のインデックスを持たない状態で始まる。
外部キー制約もあえて付けていない（MySQLは外部キー制約を付けると自動でインデックスを
作ってしまうため）。Stage 2以降、学習者自身の手でインデックスを設計・追加していく。

## 環境をリセットしたいとき

演習でテーブル構造やインデックスを変更した後、初期状態に戻したい場合は次を実行する。

```bash
./tools/reset_db.sh
```

スキーマの再作成とサンプルデータの再生成（数分）が行われる。
乱数シードが固定されているため、生成されるデータは毎回ほぼ同じ内容になる。

## 次のステージへ

環境が起動できたら [Stage 1: EXPLAINの読み方](../01_explain_basics/README.md) に進む。

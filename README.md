# sql-tuning-work

SQL初学者向けの「読みながら手を動かして学ぶSQLチューニング」教材リポジトリ。

MySQL 8.0 ＋ ECサイト風のサンプルデータ（会員・商品・注文など数十万〜100万行規模）を
Dockerで一発起動し、EXPLAINの読み方からインデックス設計、実行計画の内部動作、
ロック、パーティショニング、実践的なSQLの書き方までを、
実際にクエリを実行して結果を確認しながら学ぶ。

## 特徴

- **すべてローカルのDockerで完結**。`docker compose up`だけで環境が揃う
- **実データで学ぶ**。数十万行規模のデータを使うため、インデックスの有無による
  速度差やEXPLAINの変化を実感できる
- **答えを隠さないガイド形式**。各ステージは「身近な例えで問題を説明 →
  実行するSQLを提示 → その結果の読み方（何が目的で、何が変わって、何が良くなったか）を
  丁寧に解説」という読み物になっている。クイズ形式ではないので、詰まっても先に進める

## クイックスタート

```bash
git clone <このリポジトリ>
cd sql-tuning-work
docker compose up -d --build
docker compose logs -f seeder   # データ生成完了(数分)を待つ
```

完了したら接続して確認する。

```bash
docker compose exec mysql mysql -uroot -prootpass sqltuning
```

詳細な手順は [`basics/00_setup/README.md`](./basics/00_setup/README.md) を参照。

## 進め方

[`roadmap.md`](./roadmap.md) に沿って、`basics/` → `advanced/` の順にステージを進める。
各ステージのディレクトリには `README.md` が1枚だけ入っている。
README を上から読み進め、コードブロックのSQLを手元のMySQLで実行し、
その下に書かれている「結果の見方」と照らし合わせていく、という流れで学ぶ。

## ロードマップ概要

**基礎編**: [Stage 0 環境構築](./basics/00_setup/) → [Stage 1 EXPLAINの読み方](./basics/01_explain_basics/) →
[Stage 2 インデックスの基礎](./basics/02_index_fundamentals/) →
[Stage 3 N+1問題とアンチパターン](./basics/03_antipatterns_n1/) →
[Stage 4 複合インデックスとカバリングインデックス](./basics/04_composite_covering_index/)

**応用編**: [Stage 5 統計情報とカーディナリティ](./advanced/05_statistics_cardinality/) →
[Stage 6 実行計画の内部を読む](./advanced/06_execution_plan_internals/) →
[Stage 7 ロックとトランザクション](./advanced/07_locking_transactions/) →
[Stage 8 パーティショニング](./advanced/08_partitioning/) →
[Stage 9 クエリ書き換え実践（総合演習）](./advanced/09_query_rewriting_capstone/) →
[Stage 10 SQL効率化のためのtips](./advanced/10_query_tips/)

詳細は [`roadmap.md`](./roadmap.md) を参照。

## 環境のリセット

読み進める中でテーブル構造やインデックスを変更した後、初期状態に戻したい場合:

```bash
./tools/reset_db.sh
```

## 用語集

EXPLAIN・オプティマイザ関連の用語は [`docs/glossary.md`](./docs/glossary.md) にまとめている。

## サンプルスキーマ

ECサイトの注文管理を模したスキーマ（`categories`, `users`, `products`, `orders`,
`order_items`, `reviews`）を全ステージ共通で使用する。詳細は
[`basics/00_setup/README.md`](./basics/00_setup/README.md) を参照。

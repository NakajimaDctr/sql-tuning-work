#!/usr/bin/env bash
# 演習でテーブル構造やインデックスを変更した後、環境を初期状態に戻すスクリプト。
# 各ステージのREADMEで「このステージの前に実行してください」と指示された場合に使う。
set -euo pipefail

cd "$(dirname "$0")/.."

DB_USER="root"
DB_PASSWORD="rootpass"
DB_NAME="sqltuning"

echo "==> データベースをリセットしています..."
docker compose exec -T mysql mysql -u"${DB_USER}" -p"${DB_PASSWORD}" \
  -e "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4;"

echo "==> スキーマを再投入しています..."
docker compose exec -T mysql mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
  < docker/mysql/init/00_schema.sql
docker compose exec -T mysql mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
  < docker/mysql/init/01_seed_lookup.sql

echo "==> サンプルデータを再生成しています (数分かかります)..."
docker compose run --rm seeder

echo "==> リセットが完了しました。"

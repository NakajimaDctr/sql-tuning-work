"""
SQLチューニング学習用のサンプルデータ生成スクリプト。

- 乱数シードを固定しているため、何度生成しても学習者間でほぼ同じ
  データ分布 (EXPLAINのrows推定値など) が再現される。
- users テーブルに既にデータが存在する場合は「投入済み」とみなし、
  何もせず終了する (docker compose 再起動時の重複投入を防ぐ)。
  再投入したい場合は tools/reset_db.sh を使う。
"""

import os
import random
import sys
import time

import mysql.connector
from faker import Faker

SEED = 42
random.seed(SEED)
fake = Faker("ja_JP")
Faker.seed(SEED)

DB_HOST = os.environ.get("DB_HOST", "mysql")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "root")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "rootpass")
DB_NAME = os.environ.get("DB_NAME", "sqltuning")

NUM_USERS = 50_000
NUM_PRODUCTS = 10_000
NUM_ORDERS = 500_000
AVG_ITEMS_PER_ORDER = 3
NUM_REVIEWS = 200_000

BATCH_SIZE = 5_000

ORDER_STATUSES = ["pending", "paid", "shipped", "completed", "cancelled"]
# completed が大半を占めるように偏らせる (低カーディナリティ列の分布を現実的にする)
ORDER_STATUS_WEIGHTS = [5, 10, 10, 70, 5]


def connect_with_retry(max_wait_seconds=120):
    start = time.time()
    last_err = None
    while time.time() - start < max_wait_seconds:
        try:
            return mysql.connector.connect(
                host=DB_HOST, port=DB_PORT, user=DB_USER,
                password=DB_PASSWORD, database=DB_NAME,
            )
        except mysql.connector.Error as err:
            last_err = err
            print(f"DB接続待機中... ({err})", flush=True)
            time.sleep(3)
    raise RuntimeError(f"DBに接続できませんでした: {last_err}")


def already_seeded(cursor) -> bool:
    cursor.execute("SELECT COUNT(*) FROM users")
    (count,) = cursor.fetchone()
    return count > 0


def insert_batches(cursor, conn, sql, rows_iter, total, label):
    batch = []
    inserted = 0
    for row in rows_iter:
        batch.append(row)
        if len(batch) >= BATCH_SIZE:
            cursor.executemany(sql, batch)
            conn.commit()
            inserted += len(batch)
            batch.clear()
            print(f"  {label}: {inserted:,}/{total:,}", flush=True)
    if batch:
        cursor.executemany(sql, batch)
        conn.commit()
        inserted += len(batch)
        print(f"  {label}: {inserted:,}/{total:,}", flush=True)


def gen_users(n):
    # fake.unique.email() は内部の重複チェックがO(生成済み件数)で
    # 増大し、数万件規模で極端に遅くなる/枯渇するため使わない。
    # 連番を含めることで一意性を保証しつつ高速に生成する。
    for i in range(1, n + 1):
        name = fake.name()
        email = f"user{i:06d}.{fake.user_name()}@example.com"
        address = fake.address()
        yield (name, email, address)


def gen_products(n, num_categories):
    adjectives = ["定番", "新作", "限定", "お得な", "プレミアム", "エコ", "軽量", "コンパクト", "高級", "業務用"]
    nouns = ["セット", "スターターキット", "バリューパック", "エディション", "モデル", "コレクション"]
    for i in range(n):
        category_id = random.randint(1, num_categories)
        name = f"{random.choice(adjectives)}{fake.word()}{random.choice(nouns)}"
        price = random.randint(300, 50_000)
        stock = random.randint(0, 500)
        yield (category_id, name, price, stock)


def gen_orders(n, num_users):
    start_ts = int(time.mktime(time.strptime("2024-01-01", "%Y-%m-%d")))
    end_ts = int(time.mktime(time.strptime("2025-12-31", "%Y-%m-%d")))
    for _ in range(n):
        user_id = random.randint(1, num_users)
        status = random.choices(ORDER_STATUSES, weights=ORDER_STATUS_WEIGHTS, k=1)[0]
        total_amount = random.randint(500, 100_000)
        created_ts = random.randint(start_ts, end_ts)
        created_at = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(created_ts))
        yield (user_id, status, total_amount, created_at)


def gen_order_items(num_orders, num_products, avg_items):
    for order_id in range(1, num_orders + 1):
        item_count = max(1, int(random.gauss(avg_items, 1)))
        for _ in range(item_count):
            product_id = random.randint(1, num_products)
            quantity = random.randint(1, 5)
            price = random.randint(300, 50_000)
            yield (order_id, product_id, quantity, price)


def gen_reviews(n, num_products, num_users):
    for _ in range(n):
        product_id = random.randint(1, num_products)
        user_id = random.randint(1, num_users)
        rating = random.randint(1, 5)
        comment = fake.sentence(nb_words=12)
        yield (product_id, user_id, rating, comment)


def main():
    conn = connect_with_retry()
    cursor = conn.cursor()

    if already_seeded(cursor):
        print("既にデータが投入済みのため、何もせず終了します。", flush=True)
        cursor.close()
        conn.close()
        return

    cursor.execute("SELECT COUNT(*) FROM categories")
    (num_categories,) = cursor.fetchone()
    if num_categories == 0:
        raise RuntimeError("categories テーブルが空です。01_seed_lookup.sql が投入されているか確認してください。")

    print(f"== users ({NUM_USERS:,}件) を生成中 ==", flush=True)
    insert_batches(
        cursor, conn,
        "INSERT INTO users (name, email, address) VALUES (%s, %s, %s)",
        gen_users(NUM_USERS), NUM_USERS, "users",
    )

    print(f"== products ({NUM_PRODUCTS:,}件) を生成中 ==", flush=True)
    insert_batches(
        cursor, conn,
        "INSERT INTO products (category_id, name, price, stock) VALUES (%s, %s, %s, %s)",
        gen_products(NUM_PRODUCTS, num_categories), NUM_PRODUCTS, "products",
    )

    print(f"== orders ({NUM_ORDERS:,}件) を生成中 ==", flush=True)
    insert_batches(
        cursor, conn,
        "INSERT INTO orders (user_id, status, total_amount, created_at) VALUES (%s, %s, %s, %s)",
        gen_orders(NUM_ORDERS, NUM_USERS), NUM_ORDERS, "orders",
    )

    approx_items = NUM_ORDERS * AVG_ITEMS_PER_ORDER
    print(f"== order_items (約{approx_items:,}件) を生成中 ==", flush=True)
    insert_batches(
        cursor, conn,
        "INSERT INTO order_items (order_id, product_id, quantity, price) VALUES (%s, %s, %s, %s)",
        gen_order_items(NUM_ORDERS, NUM_PRODUCTS, AVG_ITEMS_PER_ORDER), approx_items, "order_items",
    )

    print(f"== reviews ({NUM_REVIEWS:,}件) を生成中 ==", flush=True)
    insert_batches(
        cursor, conn,
        "INSERT INTO reviews (product_id, user_id, rating, comment) VALUES (%s, %s, %s, %s)",
        gen_reviews(NUM_REVIEWS, NUM_PRODUCTS, NUM_USERS), NUM_REVIEWS, "reviews",
    )

    print("== 統計情報を更新 (ANALYZE TABLE) ==", flush=True)
    for table in ["users", "products", "orders", "order_items", "reviews"]:
        cursor.execute(f"ANALYZE TABLE {table}")
        cursor.fetchall()  # ANALYZE TABLE は結果セットを返すため読み捨てる

    cursor.close()
    conn.close()
    print("データ生成が完了しました。", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"エラーが発生しました: {e}", file=sys.stderr)
        sys.exit(1)

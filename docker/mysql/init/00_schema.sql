-- ============================================================
-- SQLチューニング学習用スキーマ (ECサイトの注文管理)
--
-- 意図的に主キーのみを定義し、外部キー制約は付与していない。
-- これは学習者自身が Stage 2 以降で必要なインデックスを
-- 自分で設計・追加していく体験をしてもらうための設計。
-- (外部キー制約を付けると MySQL/InnoDB は自動的に子テーブル側の
--  参照列にインデックスを作成してしまい、演習が成立しなくなる)
-- ============================================================

-- 初期化スクリプトを流すクライアントの接続文字コードを明示する。
-- (docker-entrypoint 経由の mysql クライアントは環境によって
--  character_set_client が latin1 になり、日本語リテラルが
--  二重エンコードされて保存される事故を防ぐ)
SET NAMES utf8mb4;

CREATE TABLE categories (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name       VARCHAR(100) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE users (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name       VARCHAR(100) NOT NULL,
  -- email はあえて未インデックス。Stage 1/3 で検索の遅さを体験し、
  -- Stage 2 で自分でインデックスを追加する題材として使う。
  email      VARCHAR(255) NOT NULL,
  address    VARCHAR(255) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE products (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id INT UNSIGNED NOT NULL,
  name        VARCHAR(150) NOT NULL,
  price       INT UNSIGNED NOT NULL,
  stock       INT UNSIGNED NOT NULL DEFAULT 0,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE orders (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      INT UNSIGNED NOT NULL,
  -- 低カーディナリティ列 (Stage 5 統計情報/カーディナリティの題材)
  status       VARCHAR(20) NOT NULL,
  total_amount INT UNSIGNED NOT NULL,
  created_at   DATETIME NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id   INT UNSIGNED NOT NULL,
  product_id INT UNSIGNED NOT NULL,
  quantity   INT UNSIGNED NOT NULL,
  price      INT UNSIGNED NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE reviews (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id INT UNSIGNED NOT NULL,
  user_id    INT UNSIGNED NOT NULL,
  rating     TINYINT UNSIGNED NOT NULL,
  comment    TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# ロードマップ

SQL初学者が「読む」だけでなく「手を動かして」SQLチューニングを学べるように、
基礎編5ステージ・応用編5ステージの合計10ステージで構成している。
上から順番に進めることを推奨する（各ステージは前のステージの内容・
環境状態を前提にしている）。

進捗管理として、自分でチェックボックスにチェックを入れながら進めるとよい。

## 基礎編

- [ ] **Stage 0: 環境構築** — [`basics/00_setup/`](./basics/00_setup/)
      `docker compose up`で学習環境（MySQL＋サンプルデータ）を起動する。
- [ ] **Stage 1: EXPLAINの読み方** — [`basics/01_explain_basics/`](./basics/01_explain_basics/)
      `type` `key` `rows` `Extra`等の意味を理解し、遅いクエリを見分けられるようになる。
- [ ] **Stage 2: インデックスの基礎** — [`basics/02_index_fundamentals/`](./basics/02_index_fundamentals/)
      `CREATE INDEX`前後でEXPLAINがどう変わるかを自分の手で確認する。
- [ ] **Stage 3: N+1問題とアンチパターン** — [`basics/03_antipatterns_n1/`](./basics/03_antipatterns_n1/)
      N+1、先頭ワイルドカードLIKE、インデックス列への関数適用、SELECT \*を体験・修正する。
- [ ] **Stage 4: 複合インデックスとカバリングインデックス** — [`basics/04_composite_covering_index/`](./basics/04_composite_covering_index/)
      列順序（左端一致の原則）とカバリングインデックスを理解する。

## 応用編

- [ ] **Stage 5: 統計情報とカーディナリティ** — [`advanced/05_statistics_cardinality/`](./advanced/05_statistics_cardinality/)
      `ANALYZE TABLE`とカーディナリティ、オプティマイザの判断根拠を理解する。
- [ ] **Stage 6: 実行計画の内部を読む** — [`advanced/06_execution_plan_internals/`](./advanced/06_execution_plan_internals/)
      `EXPLAIN ANALYZE`、Nested Loop Join / Hash Joinの動作を理解する。
- [ ] **Stage 7: ロックとトランザクション** — [`advanced/07_locking_transactions/`](./advanced/07_locking_transactions/)
      行ロック・ギャップロック・デッドロックを2つのセッションで実際に体験する。
- [ ] **Stage 8: パーティショニング** — [`advanced/08_partitioning/`](./advanced/08_partitioning/)
      RANGEパーティションとパーティションプルーニングを体験する。
- [ ] **Stage 9: クエリ書き換え実践（総合演習）** — [`advanced/09_query_rewriting_capstone/`](./advanced/09_query_rewriting_capstone/)
      複数の問題を抱えた「悪いクエリ」を、これまでの知識を総動員してチューニングする。

## 各ステージの位置づけ

```
基礎編: 読む(1) → 直す基本(2) → 典型的な悪手を知る(3) → 設計力(4)
             ↓
応用編: オプティマイザの判断根拠(5, 6) → 並行処理の観点(7) → 物理設計の選択肢(8) → 総合演習(9)
```

基礎編は「1つのクエリを速くする」ための基本武器を揃えるフェーズ。
応用編は「なぜオプティマイザはそう判断するのか」「複数リクエストが同時に来たら
どうなるか」「テーブル自体の物理設計をどうするか」という、より実務的な
視点を広げるフェーズになっている。

## 学習の進め方

各ステージは以下の流れで統一されている。

1. **概要/ゴール** を読み、何を学ぶかを把握する
2. **悪いクエリを実行してEXPLAINを見る**（そのステージのテーマとなる問題を体感する）
3. **課題**（`exercise.sql`）に自分で取り組む
4. **解答例**（`solution.sql`）で答え合わせをする
5. **解説** を読み、なぜそうなるのかを理解する
6. 余裕があれば **発展問題** にも挑戦する

わからなくなったら、環境を [`tools/reset_db.sh`](./tools/reset_db.sh) で
初期状態に戻してからやり直すこともできる。

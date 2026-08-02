# Stage 6: 実行計画の内部を読む

## 概要/ゴール

これまではEXPLAINの「見積もり」を読んできた。このステージでは
`EXPLAIN ANALYZE`で実際の実行時間・実行回数を確認し、MySQLが結合(JOIN)を
どう処理しているか（Nested Loop Join / Hash Join）の内部動作を理解する。

## 前提知識

[Stage 5: 統計情報とカーディナリティ](../05_statistics_cardinality/README.md)

## 事前準備

特別な準備は不要（既存のテーブルとインデックスをそのまま使う）。

## 悪いクエリを実行してEXPLAINを見る

まず、単純なJOINを`EXPLAIN ANALYZE`で見てみる。

```sql
EXPLAIN ANALYZE
SELECT o.id, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.id BETWEEN 1 AND 1000;
```

通常のEXPLAINと違い、`actual time=...`や`rows=...`(実測値)、
`loops=...`(そのステップが何回繰り返されたか)が表示される。
これは実際にクエリを実行するため、更新系クエリ(`UPDATE`/`DELETE`)を
`EXPLAIN ANALYZE`する際は実際にデータが変更される点に注意
（このステージでは `SELECT` のみを扱う）。

## 課題

`exercise.sql` に沿って進める。

1. `EXPLAIN ANALYZE`の出力から`loops`の意味を読み解く（Nested Loop Joinの動作確認）
2. `Hash Join`が発生するクエリを実行し、なぜその戦略が選ばれるかを考える
3. Hash Joinの見積もりコストと実測時間を比較する

**達成基準**: Nested Loop JoinとHash Joinの動作の違いを、
「外側/内側のテーブルへのアクセス回数」という観点で説明できること。

## 解答例

[`solution.sql`](./solution.sql)

## 解説

### Nested Loop Join

MySQLの結合方式の基本形。「外側のテーブルを1行ずつ読み、その都度、
内側のテーブルから該当行を探す」という動作をする。

```
for 外側の各行:
    for 内側の該当行を探す (インデックスがあれば高速):
        結果を返す
```

内側テーブルの検索にインデックスが使えれば、外側の行数が多くても
「行数 × インデックス1回分のコスト」で済むため現実的な速度になる。
逆に内側にインデックスがないと、外側の行数分だけ内側の全件スキャンを
繰り返すことになり、非常に高コストになる。

### Hash Join (MySQL 8.0.18以降)

結合キーにインデックスがなく、Nested Loopでは効率が悪いと判断された場合に
選ばれる方式。片方のテーブル（通常は小さい方）からハッシュテーブルを
メモリ上に構築し、もう片方のテーブルを1回スキャンしながら突き合わせる。
双方とも「全件を1回ずつ見る」だけで済むため、インデックスがない
大規模テーブル同士の結合ではNested Loopより有利になることが多い。

### costの見積もりを鵜呑みにしない

EXPLAIN(ANALYZE)のcost値は内部のコストモデルによる見積もりであり、
実際の処理時間と必ずしも比例しない（特にHash Joinで顕著）。
最終的な判断は`actual time`などの実測値、あるいは実際のアプリケーションでの
レスポンスタイム計測で行うべき。

## 発展問題（任意）

`optimizer_switch`の`hash_join`フラグを操作すると、Hash Joinの有効/無効を
制御できる場合がある。試してみよう。

```sql
SET SESSION optimizer_switch = 'hash_join=off';
EXPLAIN ANALYZE
SELECT oi.product_id, COUNT(*) FROM order_items oi
JOIN reviews r ON oi.product_id = r.product_id
WHERE oi.id BETWEEN 1 AND 5000
GROUP BY oi.product_id LIMIT 10;
SET SESSION optimizer_switch = 'hash_join=on'; -- 元に戻す
```

実は、このクエリでは`hash_join=off`にしても実行計画は変わらない
（Hash Joinのまま）。MySQL 8.0.20以降、それまであった
「インデックスなし結合をNested Loopで力技処理する」方式
（Block Nested-Loop）が廃止されたため、インデックスが使えない結合では
Hash Joinが唯一の選択肢になっている。`hash_join`スイッチは
「インデックスが使える場合にHash Joinとどちらを優先するか」を
制御するものであり、インデックスが存在しない今回のケースには効かない。
これも「実際に試して、公式ドキュメントの説明と現実の挙動を照合する」
という実践的な学び方の一例。

## 次のステージへ

[Stage 7: ロックとトランザクション](../07_locking_transactions/README.md) に進む。

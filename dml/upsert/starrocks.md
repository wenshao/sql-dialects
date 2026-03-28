# StarRocks: UPSERT

> 参考资料:
> - [1] StarRocks Documentation - Primary Key Model
>   https://docs.starrocks.io/docs/table_design/table_types/


## 1. Primary Key 模型天然 UPSERT

 与 Doris 相同: INSERT 相同 Key 的行自动替换旧行。

## 2. INSERT = UPSERT

```sql
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'new@e.com', 26);

INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice_new@e.com', 26),
    (2, 'bob', 'bob_new@e.com', 31);

INSERT INTO users SELECT * FROM staging_users;

```

## 3. Partial Update

 Stream Load: curl -H "partial_update:true" -H "columns:id,email" ...

## 4. 不支持 MERGE / ON CONFLICT

 与 Doris 相同，使用 Primary Key 模型的 INSERT 替代 MERGE。

## 5. StarRocks vs Doris UPSERT 差异

- **核心相同**: 模型级 UPSERT(INSERT 自动覆盖)。

Sequence Column:
- **Doris**: 支持 sequence_col(条件覆盖——按版本列判断)
- **StarRocks**: 不支持(Last Write Wins)

这意味着:
- **Doris**: 多源写入同一 Key 时，可按时间戳决定"哪条更新"
- **StarRocks**: 多源写入同一 Key 时，最后写入的为准(可能不确定)

对引擎开发者的启示:
条件 UPSERT(sequence_col)解决了多数据源冲突问题:
源 A 写入 (key=1, version=3)
源 B 写入 (key=1, version=5)
- sequence_col=version → 保留 version=5 的行
StarRocks 缺少此功能，用户需要保证写入顺序——这在分布式系统中很困难。

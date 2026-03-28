# StarRocks: 锁机制与并发控制

> 参考资料:
> - [1] StarRocks Documentation - Primary Key Model
>   https://docs.starrocks.io/docs/table_design/table_types/


## 1. 并发模型: 与 Doris 同源

 StarRocks 同样不支持行级锁、表锁、咨询锁。
 并发控制通过 MVCC + 批量导入原子性实现。

 Primary Key 模型的并发特性:
   写入时通过内存 HashIndex 定位旧行 → Delete + Insert
   多个导入并发写入同一个 Key → Last Write Wins
   不支持 Doris 的 sequence_col(无版本冲突解决)

## 2. MVCC 快照读

 查询看到导入完成时的一致性快照。
 导入未完成时，新旧数据对查询不可见(原子性)。

## 3. 表级元数据锁

```sql
ALTER TABLE orders ADD COLUMN new_col INT;  -- 获取表锁

```

 Fast Schema Evolution(3.0+): 毫秒级完成，锁持有时间极短。

## 4. 乐观锁 (应用层)

```sql
CREATE TABLE orders (
    id      BIGINT,
    status  VARCHAR(50),
    amount  DECIMAL(10,2),
    version INT
) PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO orders VALUES (100, 'shipped', 99.99, 6);

```

## 5. 监控与诊断

```sql
SHOW LOAD;
SHOW PROCESSLIST;
KILL query_id;

```

## 6. StarRocks vs Doris 并发控制差异

Primary Key 并发更新:
- **StarRocks**: Last Write Wins(按写入顺序)
- **Doris**: 可配置 sequence_col(按版本列)——更灵活

DDL 锁:
- **StarRocks 3.0+**: Fast Schema Evolution(毫秒级锁)
- **Doris 1.2+**: Light Schema Change(秒级锁)

对引擎开发者的启示:
多源并发写入同一 Key 的冲突解决是 OLAP 引擎的实际挑战。
Doris 的 sequence_col 和 StarRocks 的 Last Write Wins 是两种路径:
- **sequence_col**: 更可控(用户定义"最新")但配置复杂
- **Last Write Wins**: 更简单但依赖写入顺序(可能不确定)

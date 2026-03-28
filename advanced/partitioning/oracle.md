# Oracle: 分区

> 参考资料:
> - [Oracle VLDB and Partitioning Guide](https://docs.oracle.com/en/database/oracle/oracle-database/23/vldbg/)
> - [Oracle SQL Language Reference - CREATE TABLE (Partitioning)](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html)

## RANGE 分区

```sql
CREATE TABLE orders (
    id         NUMBER,
    user_id    NUMBER,
    amount     NUMBER(10,2),
    order_date DATE
) PARTITION BY RANGE (order_date) (
    PARTITION p2023 VALUES LESS THAN (DATE '2024-01-01'),
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);
```

INTERVAL 分区（11g+，自动创建分区，Oracle 独有创新）
```sql
CREATE TABLE logs (
    id       NUMBER,
    log_date DATE,
    message  VARCHAR2(4000)
) PARTITION BY RANGE (log_date)
  INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')) (
    PARTITION p_init VALUES LESS THAN (DATE '2024-01-01')
);
```

新数据插入时，超出已有分区范围则自动创建新分区

设计分析:
  INTERVAL 分区消除了手动 ADD PARTITION 的运维负担。
  Oracle 是唯一原生支持 INTERVAL 分区的数据库。
  PostgreSQL 11+ 的声明式分区需要手动创建每个分区或使用 pg_partman 扩展。

## LIST 分区

```sql
CREATE TABLE users_region (
    id       NUMBER,
    username VARCHAR2(100),
    region   VARCHAR2(20)
) PARTITION BY LIST (region) (
    PARTITION p_east  VALUES ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES ('Beijing', 'Tianjin'),
    PARTITION p_other VALUES (DEFAULT)          -- DEFAULT 分区
);
```

自动 LIST 分区（12.2+）
```sql
CREATE TABLE events (
    id   NUMBER,
    type VARCHAR2(50),
    data CLOB
) PARTITION BY LIST (type) AUTOMATIC (
    PARTITION p_init VALUES ('CLICK')
);
```

新的 type 值自动创建分区

## HASH 分区

```sql
CREATE TABLE sessions (
    id      NUMBER,
    user_id NUMBER,
    data    CLOB
) PARTITION BY HASH (user_id) PARTITIONS 8;
```

## 复合分区（Oracle 独有的深度支持）

RANGE-HASH
```sql
CREATE TABLE sales (
    id        NUMBER,
    sale_date DATE,
    region    VARCHAR2(20),
    amount    NUMBER(10,2)
) PARTITION BY RANGE (sale_date)
  SUBPARTITION BY HASH (region) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01')
);
```

RANGE-LIST
```sql
CREATE TABLE transactions (
    id      NUMBER,
    tx_date DATE,
    tx_type VARCHAR2(20),
    amount  NUMBER(10,2)
) PARTITION BY RANGE (tx_date)
  SUBPARTITION BY LIST (tx_type) (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01') (
        SUBPARTITION p2024_credit VALUES ('CREDIT'),
        SUBPARTITION p2024_debit  VALUES ('DEBIT'),
        SUBPARTITION p2024_other  VALUES (DEFAULT)
    ),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01') (
        SUBPARTITION p2025_credit VALUES ('CREDIT'),
        SUBPARTITION p2025_debit  VALUES ('DEBIT'),
        SUBPARTITION p2025_other  VALUES (DEFAULT)
    )
);
```

## REFERENCE 分区（11g+，Oracle 独有）

子表通过外键自动继承父表的分区策略
```sql
CREATE TABLE order_items (
    id       NUMBER,
    order_id NUMBER NOT NULL,
    product  VARCHAR2(100),
    qty      NUMBER,
    CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(id)
) PARTITION BY REFERENCE (fk_order);
```

设计分析:
  REFERENCE 分区确保父子表数据在同一分区中（partition-wise join）。
  这是 Oracle 独有的能力，其他数据库需要在子表中冗余分区键列。

## 分区管理（DDL 操作）

```sql
ALTER TABLE orders ADD PARTITION p2026 VALUES LESS THAN (DATE '2027-01-01');
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;
ALTER TABLE orders MERGE PARTITIONS p2024, p2025 INTO PARTITION p2024_2025;
ALTER TABLE orders SPLIT PARTITION pmax AT (DATE '2027-01-01')
    INTO (PARTITION p2026, PARTITION pmax);
```

EXCHANGE PARTITION（高效数据加载的关键技术）
```sql
ALTER TABLE orders EXCHANGE PARTITION p2024
    WITH TABLE orders_2024_staging;
-- 秒级操作: 只交换数据字典中的指针，不移动数据

ALTER TABLE orders MOVE PARTITION p2024 TABLESPACE archive_ts;
```

## 分区索引

本地索引（每个分区一个索引段，分区 DDL 不影响索引）
```sql
CREATE INDEX idx_orders_user ON orders(user_id) LOCAL;
```

全局索引（跨分区，全局查询更高效）
```sql
CREATE INDEX idx_orders_amount ON orders(amount) GLOBAL;
```

全局分区索引
```sql
CREATE INDEX idx_orders_global ON orders(user_id) GLOBAL
PARTITION BY RANGE (user_id) (
    PARTITION ip1 VALUES LESS THAN (10000),
    PARTITION ip2 VALUES LESS THAN (MAXVALUE)
);
```

横向对比:
  Oracle:     LOCAL + GLOBAL 索引（最灵活）
  PostgreSQL: 11+ 支持分区索引（类似 LOCAL）
  MySQL:      分区表索引必须包含分区键（强制 LOCAL）
  SQL Server: 分区对齐索引 + 非对齐索引

## 数据字典查询

```sql
SELECT partition_name, high_value, num_rows, blocks
FROM user_tab_partitions WHERE table_name = 'ORDERS'
ORDER BY partition_position;

SELECT subpartition_name, partition_name, high_value
FROM user_tab_subpartitions WHERE table_name = 'SALES';
```

## 对引擎开发者的总结

### Oracle 分区功能最丰富: RANGE/LIST/HASH/INTERVAL/REFERENCE/复合分区。

2. INTERVAL 分区（自动创建）消除了运维负担，是 Oracle 独有的创新。
3. REFERENCE 分区通过外键继承分区策略，保证 partition-wise join。
4. EXCHANGE PARTITION 是批量数据加载的秒级操作（指针交换）。
### LOCAL vs GLOBAL 索引是分区表设计中最关键的权衡

   LOCAL 维护方便但全局查询慢; GLOBAL 全局查询快但分区 DDL 需重建。
6. 分区的核心价值是 partition pruning（分区裁剪），优化器必须支持。

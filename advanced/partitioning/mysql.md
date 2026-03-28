# MySQL: 分区

> 参考资料:
> - [MySQL 8.0 Reference Manual - Partitioning](https://dev.mysql.com/doc/refman/8.0/en/partitioning.html)
> - [MySQL 8.0 Reference Manual - Partition Management](https://dev.mysql.com/doc/refman/8.0/en/partitioning-management.html)

## RANGE 分区

```sql
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

RANGE COLUMNS（多列分区，5.5+）
```sql
CREATE TABLE logs (
    id BIGINT AUTO_INCREMENT,
    log_date DATE,
    level VARCHAR(10),
    message TEXT,
    PRIMARY KEY (id, log_date)
) PARTITION BY RANGE COLUMNS(log_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION p202403 VALUES LESS THAN ('2024-04-01'),
    PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);
```

## LIST 分区

```sql
CREATE TABLE users_region (
    id BIGINT AUTO_INCREMENT,
    username VARCHAR(100),
    region VARCHAR(20),
    PRIMARY KEY (id, region)
) PARTITION BY LIST COLUMNS(region) (
    PARTITION p_east  VALUES IN ('Shanghai', 'Hangzhou', 'Nanjing'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin'),
    PARTITION p_south VALUES IN ('Guangzhou', 'Shenzhen'),
    PARTITION p_west  VALUES IN ('Chengdu', 'Chongqing')
);
```

## HASH 分区

```sql
CREATE TABLE sessions (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT,
    data TEXT,
    PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id)
  PARTITIONS 8;
```

LINEAR HASH（线性哈希，增减分区更快）
```sql
CREATE TABLE cache (
    id BIGINT, key_hash INT, value TEXT,
    PRIMARY KEY (id, key_hash)
) PARTITION BY LINEAR HASH(key_hash)
  PARTITIONS 16;
```

## KEY 分区

```sql
CREATE TABLE data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    value TEXT
) PARTITION BY KEY(id)
  PARTITIONS 4;
```

## 复合分区（子分区）

```sql
CREATE TABLE sales (
    id BIGINT AUTO_INCREMENT,
    sale_date DATE,
    region VARCHAR(20),
    amount DECIMAL(10,2),
    PRIMARY KEY (id, sale_date, region)
) PARTITION BY RANGE (YEAR(sale_date))
  SUBPARTITION BY HASH(id) SUBPARTITIONS 4 (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);
```

## 分区管理

添加分区
```sql
ALTER TABLE orders ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);
```

删除分区（数据也会删除）
```sql
ALTER TABLE orders DROP PARTITION p2022;
```

清空分区数据（保留分区结构）
```sql
ALTER TABLE orders TRUNCATE PARTITION p2023;
```

重组分区（合并）
```sql
ALTER TABLE orders REORGANIZE PARTITION p2024, p2025 INTO (
    PARTITION p2024_2025 VALUES LESS THAN (2026)
);
```

拆分分区
```sql
ALTER TABLE orders REORGANIZE PARTITION pmax INTO (
    PARTITION p2026 VALUES LESS THAN (2027),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

交换分区
```sql
ALTER TABLE orders EXCHANGE PARTITION p2023 WITH TABLE orders_2023;
```

## 查看分区信息

查看表的分区信息
```sql
SELECT PARTITION_NAME, PARTITION_METHOD, PARTITION_EXPRESSION,
       PARTITION_DESCRIPTION, TABLE_ROWS
FROM information_schema.PARTITIONS
WHERE TABLE_NAME = 'orders' AND TABLE_SCHEMA = DATABASE();
```

查看查询是否进行了分区裁剪
```sql
EXPLAIN SELECT * FROM orders WHERE order_date >= '2024-01-01';
```

partitions 列显示扫描的分区

## 分区限制

1. 分区键必须是主键/唯一键的一部分
2. 最多 8192 个分区（8.0）
3. 外键不能引用分区表
4. 全文索引不支持分区表
5. RANGE/LIST 分区需要显式定义每个分区

注意：分区键必须包含在所有唯一索引中
注意：RANGE COLUMNS / LIST COLUMNS 支持多列和非整数类型
注意：HASH 分区自动均匀分布数据
注意：EXCHANGE PARTITION 可以快速交换分区和表的数据
注意：EXPLAIN 的 partitions 列显示分区裁剪效果
注意：8.0 最多支持 8192 个分区

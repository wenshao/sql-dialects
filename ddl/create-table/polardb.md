# PolarDB: CREATE TABLE

PolarDB-X (distributed, MySQL compatible) is the focus here.
PolarDB also has PostgreSQL/Oracle compatible editions on Alibaba Cloud.

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 基本建表（MySQL 兼容语法）

```sql
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## AUTO 分区表（PolarDB-X 自动分区模式，推荐）

自动选择分区键和分区策略，简化分布式使用

```sql
CREATE TABLE orders (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    amount     DECIMAL(10,2),
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB PARTITION BY KEY(id) PARTITIONS 16;
```

## 广播表（broadcast table）：全量复制到每个 DN 节点

适合小表，JOIN 时无需跨节点

```sql
CREATE TABLE regions (
    id   INT NOT NULL AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB BROADCAST;
```

## 单表（single table）：数据只存在一个 DN 上

```sql
CREATE TABLE config (
    key_name VARCHAR(64) NOT NULL,
    value    TEXT,
    PRIMARY KEY (key_name)
) ENGINE=InnoDB SINGLE;
```

## 指定分区键的分区表

```sql
CREATE TABLE order_items (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    order_id   BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity   INT    NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB
PARTITION BY HASH(order_id) PARTITIONS 8;
```

## 全局索引（Global Secondary Index）

分布式环境下在非分区键上创建全局索引

```sql
CREATE TABLE products (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    name       VARCHAR(128) NOT NULL,
    category   VARCHAR(64),
    price      DECIMAL(10,2),
    PRIMARY KEY (id),
    GLOBAL INDEX idx_category (category) PARTITION BY HASH(category) PARTITIONS 4
) ENGINE=InnoDB PARTITION BY KEY(id) PARTITIONS 16;
```

## Range 分区

```sql
CREATE TABLE logs (
    id         BIGINT   NOT NULL AUTO_INCREMENT,
    log_date   DATE     NOT NULL,
    message    TEXT,
    PRIMARY KEY (id, log_date)
) ENGINE=InnoDB
PARTITION BY RANGE(YEAR(log_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

## 二级分区（分区 + 子分区）

```sql
CREATE TABLE sales (
    id        BIGINT NOT NULL AUTO_INCREMENT,
    region    VARCHAR(32) NOT NULL,
    sale_date DATE NOT NULL,
    amount    DECIMAL(10,2),
    PRIMARY KEY (id, sale_date, region)
) ENGINE=InnoDB
PARTITION BY RANGE(YEAR(sale_date))
SUBPARTITION BY KEY(region) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);
```

## 临时表

```sql
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INT);
```

注意事项：
ENGINE 参数接受但底层由 PolarDB-X 管理存储
支持 MySQL 8.0 大部分语法
不支持 SPATIAL 索引
外键在分布式模式下有限制（不支持跨分片外键）
AUTO_INCREMENT 在分布式环境下全局唯一但不保证连续

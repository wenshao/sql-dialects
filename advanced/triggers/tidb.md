# TiDB: 触发器

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
CREATE TABLE users (
    id         BIGINT NOT NULL AUTO_RANDOM,
    username   VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);
```

DEFAULT CURRENT_TIMESTAMP and ON UPDATE CURRENT_TIMESTAMP replace
the most common BEFORE INSERT/UPDATE trigger use cases

## Generated columns (instead of triggers that compute values)

```sql
CREATE TABLE orders (
    id       BIGINT NOT NULL AUTO_RANDOM,
    price    DECIMAL(10,2),
    qty      INT,
    total    DECIMAL(10,2) AS (price * qty) STORED,  -- computed automatically
    PRIMARY KEY (id)
);

```

## CHECK constraints (instead of validation triggers)

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

```

## TiCDC (Change Data Capture, 4.0+)

Use TiCDC to capture row changes and process them asynchronously
Can replicate to Kafka, MySQL, or other TiDB clusters
Useful for audit logging, data synchronization, and event-driven architectures

## Application-level middleware

Use database middleware or ORM hooks for trigger-like behavior
Examples: Go's GORM hooks, Java's Hibernate interceptors

## Scheduled tasks for periodic operations

Instead of triggers that aggregate or maintain summary tables,
use scheduled batch jobs

Limitations:
No BEFORE INSERT / AFTER INSERT triggers
No BEFORE UPDATE / AFTER UPDATE triggers
No BEFORE DELETE / AFTER DELETE triggers
No INSTEAD OF triggers
No statement-level triggers
All trigger-like logic must be handled externally
TiCDC provides async change capture as a partial alternative

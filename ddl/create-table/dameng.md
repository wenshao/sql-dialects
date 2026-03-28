# DamengDB (达梦): CREATE TABLE

DamengDB is a major Chinese domestic database, Oracle compatible.
Supports Oracle-style PL/SQL, sequences, packages.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


## 基本建表（Oracle 兼容语法）

```sql
CREATE TABLE users (
    id         INT          IDENTITY(1,1) PRIMARY KEY,  -- 自增列
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        CLOB,
    created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uk_username UNIQUE (username),
    CONSTRAINT uk_email UNIQUE (email)
);
```

## 达梦没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器

```sql
CREATE OR REPLACE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
BEGIN
    :NEW.updated_at := CURRENT_TIMESTAMP;
END;
/
```

## 使用序列实现自增（Oracle 兼容方式）

```sql
CREATE SEQUENCE seq_orders START WITH 1 INCREMENT BY 1;
CREATE TABLE orders (
    id         INT          DEFAULT seq_orders.NEXTVAL PRIMARY KEY,
    user_id    INT          NOT NULL,
    amount     DECIMAL(10,2),
    created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);
```

## 分区表 - Range 分区

```sql
CREATE TABLE logs (
    id         INT IDENTITY(1,1),
    log_date   DATE NOT NULL,
    message    CLOB
) PARTITION BY RANGE(log_date) (
    PARTITION p2023 VALUES LESS THAN (DATE '2024-01-01'),
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);
```

## List 分区

```sql
CREATE TABLE regional_data (
    id     INT NOT NULL,
    region VARCHAR(32) NOT NULL,
    data   CLOB
) PARTITION BY LIST(region) (
    PARTITION p_east   VALUES ('shanghai', 'hangzhou', 'nanjing'),
    PARTITION p_north  VALUES ('beijing', 'tianjin'),
    PARTITION p_south  VALUES ('guangzhou', 'shenzhen')
);
```

## Hash 分区

```sql
CREATE TABLE session_data (
    session_id VARCHAR(128) NOT NULL PRIMARY KEY,
    data       CLOB
) PARTITION BY HASH(session_id) PARTITIONS 4;
```

## 复合分区（Range + Hash）

```sql
CREATE TABLE sales (
    id        INT NOT NULL,
    region    VARCHAR(32) NOT NULL,
    sale_date DATE NOT NULL,
    amount    DECIMAL(10,2)
) PARTITION BY RANGE(sale_date)
SUBPARTITION BY HASH(region) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01')
);
```

## 全局临时表

```sql
CREATE GLOBAL TEMPORARY TABLE temp_session (
    id  INT,
    val INT
) ON COMMIT DELETE ROWS;
```

## 列存储表（HUGE 表）

```sql
CREATE HUGE TABLE analytics_data (
    id         BIGINT NOT NULL,
    event_type VARCHAR(32),
    event_data CLOB,
    created_at TIMESTAMP
);
```

达梦支持 MySQL 兼容模式
可以在初始化时指定 COMPATIBLE_MODE=4 启用 MySQL 兼容
MySQL 兼容模式下支持 AUTO_INCREMENT、ENUM 等 MySQL 特有语法
注意事项：
VARCHAR 等同于 VARCHAR2（Oracle 兼容）
支持 IDENTITY 列（类似 SQL Server）和序列（Oracle 风格）
CLOB 用于大文本（类似 Oracle）
支持 HUGE 表类型用于大数据分析
大小写敏感性可在初始化时配置（CASE_SENSITIVE）
支持表空间管理

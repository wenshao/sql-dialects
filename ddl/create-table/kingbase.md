# KingbaseES (人大金仓): CREATE TABLE

KingbaseES is a Chinese domestic database, PostgreSQL compatible.
Also supports Oracle compatibility mode (PL/SQL, packages).

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)


## 基本建表（PostgreSQL 兼容语法）

```sql
CREATE TABLE users (
    id         BIGSERIAL     PRIMARY KEY,
    username   VARCHAR(64)   NOT NULL UNIQUE,
    email      VARCHAR(255)  NOT NULL UNIQUE,
    age        INTEGER,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

## KingbaseES 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器实现

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

## IDENTITY 列（SQL 标准方式）

```sql
CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT    NOT NULL,
    amount     NUMERIC(10,2),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

## 分区表 - Range 分区

```sql
CREATE TABLE logs (
    id         BIGSERIAL,
    log_date   DATE NOT NULL,
    message    TEXT
) PARTITION BY RANGE(log_date);

CREATE TABLE logs_2023 PARTITION OF logs
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE logs_2024 PARTITION OF logs
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE logs_2025 PARTITION OF logs
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

## List 分区

```sql
CREATE TABLE regional_data (
    id     BIGINT NOT NULL,
    region VARCHAR(32) NOT NULL,
    data   TEXT
) PARTITION BY LIST(region);

CREATE TABLE regional_east PARTITION OF regional_data
    FOR VALUES IN ('shanghai', 'hangzhou', 'nanjing');
CREATE TABLE regional_north PARTITION OF regional_data
    FOR VALUES IN ('beijing', 'tianjin');
CREATE TABLE regional_south PARTITION OF regional_data
    FOR VALUES IN ('guangzhou', 'shenzhen');
```

## Hash 分区

```sql
CREATE TABLE session_data (
    session_id VARCHAR(128) NOT NULL,
    data       TEXT
) PARTITION BY HASH(session_id);

CREATE TABLE session_data_p0 PARTITION OF session_data
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE session_data_p1 PARTITION OF session_data
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE session_data_p2 PARTITION OF session_data
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE session_data_p3 PARTITION OF session_data
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

## 临时表

```sql
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INTEGER);
```

## 全局临时表

```sql
CREATE GLOBAL TEMPORARY TABLE temp_session (
    id  BIGINT,
    val INTEGER
) ON COMMIT DELETE ROWS;
```

## UNLOGGED 表（不写 WAL 日志，性能更高但崩溃后数据丢失）

```sql
CREATE UNLOGGED TABLE cache_data (
    key   VARCHAR(128) PRIMARY KEY,
    value TEXT
);
```

Oracle 兼容模式建表（需要开启 Oracle 兼容特性）
CREATE TABLE compat_table (
id     NUMBER(19) NOT NULL,
name   VARCHAR2(64),
CONSTRAINT pk_compat PRIMARY KEY (id)
);
注意事项：
基于 PostgreSQL，兼容大部分 PG 语法
支持 Oracle 兼容模式（PL/SQL、包、VARCHAR2 等）
支持安全增强功能（三权分立、强制访问控制）
支持表空间管理
支持多种字符集（GBK、UTF-8 等）
分区语法与 PostgreSQL 10+ 声明式分区一致

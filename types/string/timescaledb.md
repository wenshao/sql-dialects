# TimescaleDB: 字符串类型

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 全部字符串类型
TEXT: 变长字符串，无长度限制（推荐）
VARCHAR(n): 变长字符串，最大 n 个字符
CHAR(n): 定长字符串，自动补空格
NAME: 系统类型名（64 字符）

```sql
CREATE TABLE devices (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,                 -- 推荐使用 TEXT
    code       VARCHAR(20) NOT NULL,
    fixed_code CHAR(10),
    location   TEXT
);
```

TEXT 是 PostgreSQL 推荐类型，性能与 VARCHAR 一致
无需指定长度限制
类型转换

```sql
SELECT CAST(123 AS TEXT);
SELECT 123::TEXT;
SELECT '123'::INT;
```

## 字符串字面量

```sql
SELECT 'hello world';                          -- 单引号
SELECT 'it''s a test';                         -- 转义单引号
SELECT E'hello\nworld';                        -- 转义字符串
SELECT $$no need to escape 'quotes'$$;         -- 美元引号
SELECT $tag$nested $$dollar$$ signs$tag$;      -- 带标签的美元引号
```

## COLLATION（排序规则）

```sql
SELECT * FROM devices ORDER BY name COLLATE "C";
SELECT * FROM devices ORDER BY name COLLATE "en_US";
```

## 二进制类型

BYTEA: 变长二进制数据

```sql
CREATE TABLE files (
    id   SERIAL PRIMARY KEY,
    data BYTEA
);

INSERT INTO files (data) VALUES (E'\\xDEADBEEF');
INSERT INTO files (data) VALUES (decode('48656C6C6F', 'hex'));
```

## ENUM 类型

```sql
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');
CREATE TABLE entries (
    id    SERIAL PRIMARY KEY,
    state mood DEFAULT 'neutral'
);
```

注意：TEXT 是推荐的字符串类型
注意：TEXT 和 VARCHAR 性能完全相同
注意：支持 ENUM 自定义类型
注意：完全兼容 PostgreSQL 的字符串类型

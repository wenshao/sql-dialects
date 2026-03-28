# TDengine: CREATE TABLE

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


TDengine 使用数据库 → 超级表 → 子表的层次结构
专为时序数据（IoT）设计
创建数据库

```sql
CREATE DATABASE IF NOT EXISTS power
    KEEP 365                         -- 数据保留天数
    DAYS 10                          -- 每个文件的天数
    BLOCKS 6                         -- 内存块数
    PRECISION 'ms';                  -- 时间精度：ms, us, ns
USE power;
```

## 超级表（STable）—— 数据模型的核心


## 创建超级表（定义 schema + 标签）

```sql
CREATE STABLE meters (
    ts          TIMESTAMP,           -- 第一列必须是 TIMESTAMP
    current     FLOAT,
    voltage     INT,
    phase       FLOAT
) TAGS (
    location    NCHAR(64),           -- 标签列（元数据，不随时间变化）
    group_id    INT
);
```

## 更复杂的超级表

```sql
CREATE STABLE sensors (
    ts          TIMESTAMP,
    temperature FLOAT,
    humidity    FLOAT,
    pressure    DOUBLE,
    status      BOOL,
    info        NCHAR(200)
) TAGS (
    device_id   NCHAR(64),
    site        NCHAR(64),
    type        INT
);
```

## 子表 —— 从超级表派生


## 使用超级表创建子表（指定 TAGS 值）

```sql
CREATE TABLE d1001 USING meters TAGS ('Beijing.Chaoyang', 2);
CREATE TABLE d1002 USING meters TAGS ('Beijing.Haidian', 3);
CREATE TABLE d1003 USING meters TAGS ('Shanghai.Pudong', 1);
```

## 自动建表（插入时如果子表不存在则自动创建）

```sql
INSERT INTO d2001 USING meters TAGS ('Shenzhen.Nanshan', 4)
    VALUES (NOW, 10.3, 219, 0.31);
```

## 普通表（非超级表的独立表）


```sql
CREATE TABLE log (
    ts       TIMESTAMP,
    level    INT,
    content  NCHAR(200)
);
```

## IF NOT EXISTS

```sql
CREATE TABLE IF NOT EXISTS alerts (
    ts       TIMESTAMP,
    severity INT,
    message  NCHAR(500)
);
```

## 数据类型


```sql
CREATE STABLE all_types (
    ts          TIMESTAMP,           -- 必须为第一列
    v_bool      BOOL,                -- 布尔
    v_tinyint   TINYINT,             -- 1 字节
    v_smallint  SMALLINT,            -- 2 字节
    v_int       INT,                 -- 4 字节
    v_bigint    BIGINT,              -- 8 字节
    v_float     FLOAT,               -- 4 字节
    v_double    DOUBLE,              -- 8 字节
    v_binary    BINARY(100),         -- 定长二进制字符串
    v_nchar     NCHAR(100)           -- Unicode 字符串
) TAGS (
    t_binary    BINARY(64),
    t_nchar     NCHAR(64),
    t_int       INT
);
```

注意：第一列必须是 TIMESTAMP 类型
注意：超级表（STable）是 TDengine 的核心概念，类似"表模板"
注意：标签（TAGS）是静态元数据，不随时间变化
注意：子表自动继承超级表的 schema
注意：TDengine 不支持 ALTER TABLE ADD PRIMARY KEY
注意：不支持外键约束

# Oracle: JSON 类型

> 参考资料:
> - [Oracle JSON Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/23/adjsn/)
> - [Oracle SQL Language Reference - JSON Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/JSON-Functions.html)

## JSON 存储方式的演进

12c R1+: JSON 存储在 VARCHAR2/CLOB/BLOB 中（无原生类型）
```sql
CREATE TABLE events_12c (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data CLOB CONSTRAINT chk_json CHECK (data IS JSON)
);
```

21c+: 原生 JSON 类型（二进制存储，更高效）
```sql
CREATE TABLE events_21c (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data JSON
);
```

设计分析:
  12c: CHECK (data IS JSON) 是约束而非类型，数据仍以文本存储
  21c: 原生 JSON 类型，二进制 OSON 格式，解析一次后缓存结构

横向对比:
  Oracle 21c+: 原生 JSON 类型（OSON 二进制格式）
  PostgreSQL:  json（文本）+ jsonb（二进制，推荐）—— 最早的原生 JSON 类型
  MySQL 5.7+:  JSON 类型（二进制存储）
  SQL Server:  无原生 JSON 类型（VARCHAR + ISJSON/OPENJSON）

对引擎开发者的启示:
  JSON 二进制存储（PostgreSQL jsonb / Oracle OSON）比文本存储
  在查询时快 3-10 倍（无需重复解析）。新引擎应从一开始就用二进制格式。

## 插入 JSON

```sql
INSERT INTO events_12c (data) VALUES (
    '{"name": "alice", "age": 25, "tags": ["vip", "new"]}'
);
```

## JSON 查询函数

JSON_VALUE: 返回标量值
```sql
SELECT JSON_VALUE(data, '$.name') FROM events_12c;
SELECT JSON_VALUE(data, '$.age' RETURNING NUMBER) FROM events_12c;
```

JSON_QUERY: 返回 JSON 片段（数组或对象）
```sql
SELECT JSON_QUERY(data, '$.tags') FROM events_12c;
```

点表示法（12c+，最简洁，需要 IS JSON 约束或 JSON 类型）
```sql
SELECT e.data.name FROM events_12c e;
SELECT e.data.tags[0] FROM events_12c e;
```

JSON_EXISTS: 条件过滤
```sql
SELECT * FROM events_12c WHERE JSON_EXISTS(data, '$.tags[*]?(@ == "vip")');
SELECT * FROM events_12c WHERE JSON_VALUE(data, '$.name') = 'alice';
```

IS JSON 检查
```sql
SELECT * FROM events_12c WHERE data IS JSON;
SELECT * FROM events_12c WHERE data IS NOT JSON;
```

## JSON_TABLE: 将 JSON 展开为关系表（Oracle 12c+ 的杀手级特性）

```sql
SELECT jt.*
FROM events_12c e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR2(64) PATH '$.name',
    age  NUMBER       PATH '$.age'
)) jt;
```

嵌套 JSON_TABLE（展开数组）
```sql
SELECT jt.*
FROM events_12c e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR2(64) PATH '$.name',
    NESTED PATH '$.tags[*]' COLUMNS (
        tag VARCHAR2(50) PATH '$'
    )
)) jt;
```

设计分析:
  JSON_TABLE 是 SQL:2016 标准的一部分，Oracle 12c 是最早实现的数据库之一。
  它将 JSON 文档转换为虚拟关系表，可以与其他表 JOIN。

横向对比:
  Oracle 12c+: JSON_TABLE（最早且最完整的实现）
  PostgreSQL:  jsonb_to_recordset / jsonb_array_elements（函数式，不如 JSON_TABLE 统一）
  MySQL 8.0+:  JSON_TABLE（受 Oracle 启发）
  SQL Server:  OPENJSON（功能类似但语法不同）

## JSON 修改

19c+: JSON_MERGEPATCH（RFC 7396）
```sql
SELECT JSON_MERGEPATCH(data, '{"age": 26}') FROM events_12c;
```

21c+: JSON_TRANSFORM（更精细的修改操作）
```sql
SELECT JSON_TRANSFORM(data, SET '$.age' = 26, REMOVE '$.tags') FROM events_12c;
```

## JSON 聚合（12c R2+）

```sql
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
SELECT JSON_OBJECTAGG(username VALUE age) FROM users;
```

## JSON 索引

函数索引（12c+）
```sql
CREATE INDEX idx_name ON events_12c (JSON_VALUE(data, '$.name'));
```

21c+: 多值索引（Multi-Value Index，用于数组）
```sql
CREATE MULTIVALUE INDEX idx_tags ON events e (e.data.tags.string());
```

JSON 搜索索引（全文搜索 JSON 内容）
```sql
CREATE SEARCH INDEX idx_search ON events_12c (data) FOR JSON;
```

## '' = NULL 对 JSON 的影响

JSON 中的空字符串在 Oracle 中可能有意外行为:
JSON_VALUE 返回 VARCHAR2，如果 JSON 值是 ""（空字符串），
返回结果是 NULL（因为 '' = NULL）
这导致无法区分 JSON 中的 null 和 ""

对比:
  Oracle:     JSON_VALUE('"": ""') 中的 "" 返回 NULL
  PostgreSQL: '"": ""' 中的 "" 返回 ''（空字符串，不是 NULL）
  MySQL:      '"": ""' 中的 "" 返回 ''

## 对引擎开发者的总结

1. JSON 二进制存储（OSON/jsonb）比文本存储性能好 3-10 倍。
2. JSON_TABLE 是 JSON 与关系模型的桥梁，Oracle 12c 是最早实现的。
3. 点表示法（e.data.name）是用户体验最佳的 JSON 访问方式。
4. '' = NULL 影响 JSON 中空字符串值的提取，这是 Oracle 独有的问题。
5. JSON 搜索索引和多值索引是高级 JSON 查询优化的关键。

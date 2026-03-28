# DamengDB (达梦): JSON 类型

DamengDB supports JSON data via SQL/JSON standard with Oracle-compatible functions.

> 参考资料:
> - [DamengDB SQL Reference - JSON Functions](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - SQL/JSON Standard (ISO/IEC 9075-2:2016)
> - ============================================================
> - 1. JSON 存储: 使用 CLOB / VARCHAR 而非原生 JSON 类型
> - ============================================================
> - 达梦没有独立的 JSON 列类型，使用 CLOB 或 VARCHAR 存储 JSON 文档
> - 建议使用 CLOB 存储较大的 JSON（超过 VARCHAR 最大长度）
> - 建议使用 VARCHAR 存储较小的 JSON（性能更好）

```sql
CREATE TABLE events (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    data CLOB,                               -- JSON 文档存储为 CLOB
    info VARCHAR(4000)                       -- 小 JSON 可用 VARCHAR
);
```

## 插入 JSON

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES ('{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');
```

## JSON_VALUE: 提取标量值


## JSON_VALUE 返回标量值（字符串、数字、布尔值、null）

```sql
SELECT JSON_VALUE(data, '$.name') FROM events;       -- 'alice'
SELECT JSON_VALUE(data, '$.age') FROM events;        -- '25'
```

## 返回类型指定

```sql
SELECT JSON_VALUE(data, '$.age' RETURNING INT) FROM events;  -- 25（整数）
```

## 嵌套路径

```sql
SELECT JSON_VALUE(data, '$.address.city') FROM events;       -- 'Beijing'
```

错误处理
NULL ON ERROR: 出错时返回 NULL（默认）
ERROR ON ERROR: 出错时抛出异常
DEFAULT 'N/A' ON ERROR: 出错时返回默认值

```sql
SELECT JSON_VALUE(data, '$.phone' DEFAULT 'N/A' ON ERROR) FROM events;
```

## JSON_QUERY: 提取对象或数组


## JSON_QUERY 返回 JSON 片段（对象或数组），结果仍然是 JSON 字符串

```sql
SELECT JSON_QUERY(data, '$.tags') FROM events;        -- '["vip", "new"]'
SELECT JSON_QUERY(data, '$.address') FROM events;     -- '{"city": "Beijing"}'
```

## WITH WRAPPER: 将结果包装为数组

```sql
SELECT JSON_QUERY(data, '$.tags' WITH WRAPPER) FROM events;
```

## JSON_EXISTS: 检查路径是否存在


## 返回 1（存在）或 0（不存在）

```sql
SELECT * FROM events WHERE JSON_EXISTS(data, '$.name');
SELECT * FROM events WHERE JSON_EXISTS(data, '$.address.city');
```

## 否定判断

```sql
SELECT * FROM events WHERE NOT JSON_EXISTS(data, '$.phone');
```

## JSON_TABLE: 将 JSON 展开为关系表


## JSON_TABLE 是最强大的 JSON 查询功能，将 JSON 文档转为虚拟关系表

```sql
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR(64)  PATH '$.name',
    age  INT          PATH '$.age'
)) jt;
```

## 嵌套列（NESTED PATH）

```sql
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name  VARCHAR(64) PATH '$.name',
    NESTED PATH '$.address' COLUMNS (
        city VARCHAR(64) PATH '$.city'
    )
)) jt;
```

## JSON 数组展开

```sql
SELECT jt.tag
FROM events e,
JSON_TABLE(e.data, '$.tags[*]' COLUMNS (
    tag VARCHAR(64) PATH '$'
)) jt;
```

## ORDINALITY 列（生成行号）

```sql
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$.tags[*]' COLUMNS (
    ordinality FOR ORDINALITY,
    tag VARCHAR(64) PATH '$'
)) jt;
```

## JSON 修改与构造


达梦的 JSON 修改能力有限，通常需要应用层处理
或使用字符串函数拼接
JSON 构造
通过字符串拼接构造 JSON

```sql
INSERT INTO events (data) VALUES (
    '{"name": "charlie", "age": ' || CAST(28 AS VARCHAR) || '}'
);
```

## Oracle 兼容的 JSON 操作


达梦的 JSON 函数设计对齐 Oracle 12c+ 的 SQL/JSON 支持:
Oracle 函数       达梦支持     说明
JSON_VALUE        支持         提取标量
JSON_QUERY        支持         提取对象/数组
JSON_TABLE        支持         JSON 转关系表
JSON_EXISTS       支持         路径存在检查
JSON_OBJECT       部分支持     构造 JSON 对象
JSON_ARRAY        部分支持     构造 JSON 数组
IS JSON           部分支持     JSON 格式验证
IS JSON 条件: 验证字符串是否为合法 JSON

```sql
SELECT * FROM events WHERE data IS JSON;
```

## JSON 路径表达式


达梦使用 SQL/JSON 路径表达式（类似 Oracle）:
'$'              根节点
'$.name'         对象成员访问
'$.tags[0]'      数组索引（从 0 开始）
'$.tags[*]'      数组所有元素
'$.address.city' 嵌套路径
'$.age?(@ > 20)' 过滤器表达式
路径表达式与 MySQL/PostgreSQL 的差异:
达梦/Oracle: 使用 SQL/JSON 标准路径 '$.name'
MySQL:       使用 JavaScript 风格 '$.name'（类似但函数不同）
PostgreSQL:  使用 'name' 或 '{name}'（无 $ 前缀）

## 性能考虑


达梦 JSON 的性能限制:
1. 无原生 JSON 类型: 每次查询需解析 JSON 字符串
2. 无 JSON 专用索引: 需使用函数索引模拟
3. JSON_TABLE 是最有效的 JSON 查询方式（批量解析）
4. 大 JSON 文档（> 4KB）存储在 CLOB 中，查询较慢
函数索引示例（加速 JSON_VALUE 查询）
CREATE INDEX idx_json_name ON events (JSON_VALUE(data, '$.name'));

## 注意事项与最佳实践


## 达梦使用 SQL/JSON 标准函数（JSON_VALUE、JSON_QUERY、JSON_TABLE）

## 没有原生 JSON 列类型，使用 CLOB 或 VARCHAR 存储

## 不支持 MySQL 风格的 -> 和 ->> 运算符

## JSON_TABLE 功能强大，推荐用于 JSON 数据的关系化查询

## JSON 路径表达式对齐 Oracle 的 SQL/JSON 标准

## 高频查询的 JSON 字段建议创建函数索引

## Oracle 迁移场景下 JSON 函数基本兼容

## 大 JSON 文档使用 CLOB，小 JSON 使用 VARCHAR（性能更优）

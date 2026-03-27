# JSON_TABLE 标准化

将 JSON 文档展开为关系型行列——SQL:2016 标准化的桥梁函数，让 JSON 数据融入 SQL 的 SELECT/JOIN/WHERE 体系。

## 支持矩阵

| 引擎 | 支持 | 版本 | 函数名/语法 | 备注 |
|------|------|------|-----------|------|
| Oracle | 完整支持 | 12c (2013) | `JSON_TABLE(...)` | **最早实现**，SQL:2016 主要推动者 |
| MySQL | 完整支持 | 8.0 (2018) | `JSON_TABLE(...)` | 接近标准语法 |
| PostgreSQL | 完整支持 | 17 (2024) | `JSON_TABLE(...)` | 长期缺失，17 终于补齐 |
| SQL Server | 部分支持 | 2016+ | `OPENJSON(...)` | 非标准语法，功能等价 |
| MariaDB | 完整支持 | 10.6+ | `JSON_TABLE(...)` | 与 MySQL 语法兼容 |
| Snowflake | 不支持 | - | `FLATTEN(...)` + `LATERAL` | 私有语法 |
| BigQuery | 不支持 | - | `UNNEST(JSON_QUERY_ARRAY(...))` | 需组合函数 |
| ClickHouse | 不支持 | - | `JSONExtract` 系列函数 | 无行展开原语 |
| DuckDB | 部分支持 | 0.10+ | `json_each` / `unnest` | 非标准但功能相近 |
| Trino | 完整支持 | 419+ | `JSON_TABLE(...)` | SQL:2016 标准语法 |
| Db2 | 完整支持 | 11.1+ | `JSON_TABLE(...)` | 标准语法 |

## 设计动机: JSON 与关系模型的鸿沟

### 问题场景

API 返回嵌套 JSON，需要将其转换为关系型结果集用于分析：

```json
{
  "order_id": 1001,
  "customer": "张三",
  "items": [
    {"product": "键盘", "qty": 2, "price": 299.00},
    {"product": "鼠标", "qty": 1, "price": 99.00},
    {"product": "显示器", "qty": 1, "price": 2499.00}
  ]
}
```

期望结果：

```
| order_id | customer | product | qty | price  |
|----------|----------|---------|-----|--------|
| 1001     | 张三     | 键盘    | 2   | 299.00 |
| 1001     | 张三     | 鼠标    | 1   | 99.00  |
| 1001     | 张三     | 显示器  | 1   | 2499.00|
```

在没有 JSON_TABLE 之前，每个引擎用不同的函数组合来实现这个转换，语法差异巨大。

## SQL:2016 标准语法

```sql
-- 标准 JSON_TABLE 语法（Oracle, MySQL, PostgreSQL 17+）
SELECT jt.*
FROM orders o,
JSON_TABLE(
    o.order_data,                    -- JSON 源
    '$.items[*]'                     -- 行路径表达式
    COLUMNS (
        product VARCHAR(100) PATH '$.product',      -- 列映射
        qty     INT          PATH '$.qty',
        price   DECIMAL(10,2) PATH '$.price',
        -- 元数据列
        item_idx FOR ORDINALITY                     -- 行序号（从 1 开始）
    )
) AS jt;
```

### 关键组件

```
JSON_TABLE(
    <JSON 源表达式>,
    <行路径表达式>
    COLUMNS (
        <列名> <类型> PATH <值路径>
            [DEFAULT <默认值> ON EMPTY]
            [DEFAULT <默认值> ON ERROR]
            [ERROR ON ERROR | NULL ON ERROR],
        <列名> FOR ORDINALITY,
        NESTED PATH <嵌套路径> COLUMNS (...)
    )
)
```

| 组件 | 说明 |
|------|------|
| 行路径 | `'$.items[*]'` —— 定义哪些 JSON 元素展开为行 |
| PATH | `'$.product'` —— 从每个元素中提取值的路径 |
| FOR ORDINALITY | 自动生成行号列（从 1 开始） |
| NESTED PATH | 处理嵌套数组——展开为额外的行 |
| ON EMPTY | 路径不存在时的行为（NULL/DEFAULT/ERROR） |
| ON ERROR | 类型转换失败时的行为 |

## 语法对比

### Oracle 12c+

```sql
-- Oracle JSON_TABLE（SQL:2016 最早实现）
SELECT o.order_id, jt.*
FROM orders o,
JSON_TABLE(o.order_json, '$.items[*]'
    COLUMNS (
        product VARCHAR2(100) PATH '$.product',
        qty     NUMBER        PATH '$.qty',
        price   NUMBER(10,2)  PATH '$.price',
        -- Oracle 特色: EXISTS 检查路径是否存在
        has_discount VARCHAR2(5) EXISTS PATH '$.discount'
    )
) jt;

-- Oracle 嵌套展开
SELECT o.order_id, jt.*
FROM orders o,
JSON_TABLE(o.order_json, '$'
    COLUMNS (
        customer VARCHAR2(100) PATH '$.customer',
        NESTED PATH '$.items[*]' COLUMNS (
            product VARCHAR2(100) PATH '$.product',
            qty     NUMBER        PATH '$.qty',
            NESTED PATH '$.tags[*]' COLUMNS (
                tag VARCHAR2(50) PATH '$'
            )
        )
    )
) jt;
```

### MySQL 8.0+

```sql
-- MySQL JSON_TABLE（语法与 Oracle 几乎相同）
SELECT o.order_id, jt.*
FROM orders o,
JSON_TABLE(o.order_json, '$.items[*]'
    COLUMNS (
        row_num FOR ORDINALITY,
        product VARCHAR(100) PATH '$.product',
        qty     INT          PATH '$.qty',
        price   DECIMAL(10,2) PATH '$.price'
            DEFAULT 0 ON EMPTY
            NULL ON ERROR,
        -- 嵌套路径
        NESTED PATH '$.tags[*]' COLUMNS (
            tag VARCHAR(50) PATH '$'
        )
    )
) AS jt;

-- MySQL 限制: JSON_TABLE 必须出现在 FROM 子句中
-- 且 JSON 源必须是列引用或变量（不能是子查询结果）
```

### PostgreSQL 17+

```sql
-- PostgreSQL 17 终于支持标准 JSON_TABLE
SELECT jt.*
FROM orders o,
JSON_TABLE(o.order_json, '$.items[*]'
    COLUMNS (
        product TEXT PATH '$.product',
        qty     INT  PATH '$.qty',
        price   NUMERIC(10,2) PATH '$.price'
    )
) AS jt;

-- PostgreSQL 17 之前的替代方案
-- 方案 1: json_array_elements + 手动提取
SELECT
    o.order_id,
    item ->> 'product' AS product,
    (item ->> 'qty')::int AS qty,
    (item ->> 'price')::numeric AS price
FROM orders o,
    json_array_elements(o.order_json -> 'items') AS item;

-- 方案 2: jsonb_to_recordset（已知 schema 时最简洁）
SELECT o.order_id, items.*
FROM orders o,
    jsonb_to_recordset(o.order_json -> 'items')
    AS items(product text, qty int, price numeric);
```

### SQL Server（OPENJSON —— 非标准但等价）

```sql
-- SQL Server 使用 OPENJSON（非标准语法）
SELECT o.order_id, items.*
FROM orders o
CROSS APPLY OPENJSON(o.order_json, '$.items')
WITH (
    product NVARCHAR(100) '$.product',
    qty     INT           '$.qty',
    price   DECIMAL(10,2) '$.price'
) AS items;

-- OPENJSON 默认模式（返回 key/value/type 三列）
SELECT *
FROM OPENJSON('{"a":1,"b":"hello","c":[1,2,3]}');
-- key | value   | type
-- a   | 1       | 2
-- b   | hello   | 1
-- c   | [1,2,3] | 4

-- OPENJSON 处理嵌套
SELECT o.order_id, items.product, tags.value AS tag
FROM orders o
CROSS APPLY OPENJSON(o.order_json, '$.items') WITH (
    product NVARCHAR(100) '$.product',
    tags NVARCHAR(MAX) '$.tags' AS JSON  -- AS JSON 保持子文档为 JSON
) AS items
CROSS APPLY OPENJSON(items.tags) AS tags;
```

### Snowflake（FLATTEN）

```sql
-- Snowflake 使用 FLATTEN 函数
SELECT
    o.order_id,
    f.value:product::VARCHAR AS product,
    f.value:qty::INT AS qty,
    f.value:price::DECIMAL(10,2) AS price
FROM orders o,
    LATERAL FLATTEN(input => o.order_json:items) f;

-- 嵌套 FLATTEN
SELECT
    o.order_id,
    items.value:product::VARCHAR AS product,
    tags.value::VARCHAR AS tag
FROM orders o,
    LATERAL FLATTEN(input => o.order_json:items) items,
    LATERAL FLATTEN(input => items.value:tags) tags;
```

### BigQuery

```sql
-- BigQuery 使用 UNNEST + JSON_QUERY_ARRAY
SELECT
    o.order_id,
    JSON_VALUE(item, '$.product') AS product,
    CAST(JSON_VALUE(item, '$.qty') AS INT64) AS qty,
    CAST(JSON_VALUE(item, '$.price') AS FLOAT64) AS price
FROM orders o,
    UNNEST(JSON_QUERY_ARRAY(o.order_json, '$.items')) AS item;
```

### ClickHouse

```sql
-- ClickHouse 无 JSON_TABLE，需要 JSONExtract 系列
-- 方案 1: arrayJoin + JSONExtract
SELECT
    order_id,
    JSONExtractString(item, 'product') AS product,
    JSONExtractInt(item, 'qty') AS qty,
    JSONExtractFloat(item, 'price') AS price
FROM orders
ARRAY JOIN JSONExtractArrayRaw(order_json, 'items') AS item;

-- 方案 2: 如果已经用 JSON 列类型存储
SELECT
    order_id,
    items.product,
    items.qty,
    items.price
FROM orders
ARRAY JOIN order_json.items AS items;
```

## 嵌套展开对比

处理多层嵌套是 JSON_TABLE 最体现价值的场景：

```json
{
  "departments": [
    {
      "name": "工程部",
      "teams": [
        {"name": "前端", "members": ["张三", "李四"]},
        {"name": "后端", "members": ["王五", "赵六"]}
      ]
    }
  ]
}
```

```sql
-- 标准 JSON_TABLE: 一次声明，三层展开
SELECT jt.*
FROM org_data d,
JSON_TABLE(d.json_doc, '$.departments[*]'
    COLUMNS (
        dept_name VARCHAR(100) PATH '$.name',
        NESTED PATH '$.teams[*]' COLUMNS (
            team_name VARCHAR(100) PATH '$.name',
            NESTED PATH '$.members[*]' COLUMNS (
                member VARCHAR(100) PATH '$'
            )
        )
    )
) jt;
-- 结果:
-- dept_name | team_name | member
-- 工程部    | 前端      | 张三
-- 工程部    | 前端      | 李四
-- 工程部    | 后端      | 王五
-- 工程部    | 后端      | 赵六

-- Snowflake: 需要多次 FLATTEN
SELECT
    dept.value:name::VARCHAR AS dept_name,
    team.value:name::VARCHAR AS team_name,
    member.value::VARCHAR AS member
FROM org_data d,
    LATERAL FLATTEN(d.json_doc:departments) dept,
    LATERAL FLATTEN(dept.value:teams) team,
    LATERAL FLATTEN(team.value:members) member;
```

## 对引擎开发者的实现分析

### 1. JSON 路径表达式解析

JSON_TABLE 依赖 JSON 路径表达式（SQL/JSON Path），需要实现路径解析器：

```
路径语法:
$              — 根节点
$.key          — 对象成员访问
$[0]           — 数组索引
$[*]           — 数组展开（生成多行）
$.key1.key2    — 嵌套访问
$[0 to 3]     — 数组切片（部分引擎支持）
$.key?(...)    — 过滤表达式（SQL:2016 定义但很少引擎支持）
```

### 2. 行生成器

JSON_TABLE 本质上是一个**表值函数（Table-Valued Function）**，需要在执行器中实现行生成器逻辑：

```
输入: 一个 JSON 值 + 行路径
输出: 零到多行

算法:
1. 解析行路径，定位到 JSON 数组
2. 遍历数组元素
3. 对每个元素，按 COLUMNS 定义提取值
4. 类型转换（JSON 值 → SQL 类型）
5. 处理嵌套 NESTED PATH（递归展开 → 笛卡尔积）
6. 生成 FOR ORDINALITY 序号
```

### 3. NESTED PATH 的语义

NESTED PATH 的行为类似 LEFT JOIN：

```
外层行: [{product: "键盘", tags: ["电脑", "外设"]}, {product: "鼠标", tags: []}]

展开结果（NESTED PATH '$.tags[*]'）:
键盘 | 电脑    ← tags 数组的第一个元素
键盘 | 外设    ← tags 数组的第二个元素
鼠标 | NULL    ← tags 数组为空，保留外层行，嵌套列为 NULL
```

如果有多个同级 NESTED PATH，它们之间是 UNION（而非笛卡尔积）。这个语义很容易实现错误。

### 4. 类型转换与错误处理

```sql
COLUMNS (
    price DECIMAL(10,2) PATH '$.price'
        DEFAULT 0 ON EMPTY       -- 路径不存在 → 返回 0
        ERROR ON ERROR           -- 类型转换失败 → 报错（而非返回 NULL）
)
```

引擎需要在每个值提取步骤处理两种异常:
- **EMPTY**: 路径在 JSON 中不存在
- **ERROR**: 路径存在但值无法转换为目标类型

### 5. 执行计划

```
TableScan(orders) → JsonTable(行路径, COLUMNS定义) → Project → Filter
                      ↑
                    类似 LATERAL JOIN: 对每一行执行 JSON 展开
```

在优化器中，JSON_TABLE 应被视为一种 LATERAL 子查询。谓词下推机会有限——只有当 WHERE 条件可以在路径解析前评估时才能下推。

### 6. 性能考量

JSON_TABLE 的性能瓶颈通常在 JSON 解析：
- 每行都要解析一次 JSON（如果存储为文本）
- 建议: 对频繁查询的 JSON 字段，使用二进制 JSON 格式（如 PostgreSQL 的 JSONB）
- 路径表达式可以编译为字节码，避免重复解析

## 各引擎语法差异速查

| 操作 | Oracle/MySQL | SQL Server | PostgreSQL <17 | Snowflake | BigQuery |
|------|-------------|------------|---------------|-----------|----------|
| 展开数组 | `JSON_TABLE(...[*])` | `OPENJSON(...)` | `json_array_elements()` | `FLATTEN()` | `UNNEST(JSON_QUERY_ARRAY())` |
| 提取字段 | `PATH '$.key'` | `'$.key'` in WITH | `->> 'key'` | `value:key` | `JSON_VALUE(x,'$.key')` |
| 行号 | `FOR ORDINALITY` | `WITH` 无 | `WITH ORDINALITY` | `f.index` | 无直接支持 |
| 嵌套展开 | `NESTED PATH` | 多层 CROSS APPLY | 多层 json_array_elements | 多层 FLATTEN | 多层 UNNEST |
| 空数组保留 | `DEFAULT ON EMPTY` | LEFT APPLY | LEFT JOIN LATERAL | OUTER=TRUE | LEFT JOIN UNNEST |

## 参考资料

- ISO/IEC 9075-2:2016 Section 7.11 (JSON_TABLE)
- Oracle: [JSON_TABLE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/JSON_TABLE.html)
- MySQL: [JSON_TABLE](https://dev.mysql.com/doc/refman/8.0/en/json-table-functions.html)
- PostgreSQL 17: [JSON_TABLE](https://www.postgresql.org/docs/17/functions-json.html#FUNCTIONS-SQLJSON-TABLE)
- SQL Server: [OPENJSON](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql)
- Snowflake: [FLATTEN](https://docs.snowflake.com/en/sql-reference/functions/flatten)

# JSON 聚合函数 (JSON Aggregate Functions)

把多行数据聚合成一个 JSON 对象或数组，是连接关系世界与文档世界的关键桥梁。SQL:2016 标准化了 `JSON_OBJECTAGG` / `JSON_ARRAYAGG`，但在它之前 PostgreSQL 已经凭借 `json_agg` / `jsonb_agg` 引领了八年事实标准——这种"标准化滞后"造成了今天主流引擎之间令人困惑的语法分裂。

## 为什么需要 JSON 聚合？

```sql
-- 关系模型：每个订单一行
order_id  | item_id | qty | price
----------+---------+-----+------
1001      | A       |  2  | 10.00
1001      | B       |  1  | 25.00
1002      | A       |  3  | 10.00

-- 应用层期望的形态：每个订单一个 JSON 文档
{
  "order_id": 1001,
  "items": [
    {"item_id": "A", "qty": 2, "price": 10.00},
    {"item_id": "B", "qty": 1, "price": 25.00}
  ]
}
```

JSON 聚合函数解决三类典型问题：

1. **API 层数据组装**: 后端直接 `SELECT ... FOR JSON` 输出给前端，省去 ORM 序列化
2. **数据集市预聚合**: 嵌套维度表展开成 JSON 列存储，避免运行时多表 JOIN
3. **半结构化中间状态**: ETL 中将 N:1 关系压缩到一行（如 user → activities[]）

如果没有 JSON 聚合函数，应用层需要执行多次查询（N+1 问题）或自己解析 GROUP_CONCAT 的字符串结果——前者性能差，后者格式脆弱（嵌套引号、Unicode 转义都是地雷）。

## SQL:2016 标准定义

ISO/IEC 9075-2:2016 第 10.9 节正式将 JSON 聚合函数纳入标准：

```sql
<JSON object aggregate function> ::=
    JSON_OBJECTAGG (
        <JSON name> : <JSON value expression>
        [ { NULL | ABSENT } ON NULL ]
        [ WITH UNIQUE [ KEYS ] | WITHOUT UNIQUE [ KEYS ] ]
    )

<JSON array aggregate function> ::=
    JSON_ARRAYAGG (
        <JSON value expression>
        [ ORDER BY <sort specification list> ]
        [ { NULL | ABSENT } ON NULL ]
    )
```

标准的关键语义：

1. **聚合输入**：分组内多行的列值
2. **输出**：单个 JSON 对象（OBJECTAGG）或数组（ARRAYAGG）
3. **NULL 处理**：`NULL ON NULL`（默认）保留 null；`ABSENT ON NULL` 跳过
4. **唯一性约束**（仅 OBJECTAGG）：`WITH UNIQUE KEYS` 检测重复键并抛错
5. **顺序**（仅 ARRAYAGG）：`ORDER BY` 决定元素出现顺序

```sql
-- 标准示例
SELECT JSON_ARRAYAGG(item_name ORDER BY item_id) FROM items;
SELECT JSON_OBJECTAGG(item_id : item_name ABSENT ON NULL) FROM items;
```

## 支持矩阵：JSON_OBJECTAGG（构建对象）

| 引擎 | 支持 | 语法 | 版本 | NULL/ABSENT | 备注 |
|------|------|------|------|-------------|------|
| PostgreSQL | 是 | `json_object_agg(k, v)` / `jsonb_object_agg(k, v)` | 9.4 (2014) | 通过包装函数 | 非标准函数名，标准 `JSON_OBJECTAGG` 17+ |
| PostgreSQL 17+ | 是 | `JSON_OBJECTAGG(k VALUE v)` | 17 (2024) | `ABSENT/NULL ON NULL` | SQL:2016 标准语法 |
| MySQL | 是 | `JSON_OBJECTAGG(k, v)` | 5.7.22 (2018-04) | 始终保留 NULL | 不支持 ABSENT/UNIQUE 子句 |
| MariaDB | 是 | `JSON_OBJECTAGG(k, v)` | 10.5 (2020) | 始终保留 NULL | 不支持 ORDER BY/UNIQUE |
| Oracle | 是 | `JSON_OBJECTAGG(k VALUE v)` | 12c R2 (2017) | `ABSENT/NULL ON NULL` | 标准语法 + `WITH UNIQUE KEYS` |
| SQL Server | 是 | `JSON_OBJECTAGG(k VALUE v)` | 2025 preview | `ABSENT/NULL ON NULL` | 此前需 `FOR JSON PATH` 拼装 |
| Azure SQL DB | 是 | `JSON_OBJECTAGG(k VALUE v)` | 2024 | `ABSENT/NULL ON NULL` | 早于本地 SQL Server |
| Db2 | 是 | `JSON_OBJECTAGG(KEY k VALUE v)` | 11.5+ | `ABSENT/NULL ON NULL` | 标准语法，含 KEY 关键字 |
| SQLite | 否 | -- | -- | -- | 但有 `json_group_object(k, v)` |
| ClickHouse | 否 | -- | -- | -- | 用 `groupArray(map(k, v))` 模拟 |
| DuckDB | 是 | `json_group_object(k, v)` | 0.6+ | 始终保留 NULL | 非标准命名，对标 SQLite |
| DuckDB | 是 | `JSON_OBJECTAGG(k VALUE v)` | 1.1+ | -- | 1.1 起支持标准语法别名 |
| Snowflake | 是 | `OBJECT_AGG(k, v)` | GA | NULL 自动跳过 | 非标准命名 |
| BigQuery | 否 | -- | -- | -- | 用 `TO_JSON(STRUCT(...))` 或 ARRAY_AGG 模拟 |
| Redshift | 否 | -- | -- | -- | 用 `LISTAGG` + 字符串拼接模拟 |
| Trino / Presto | 是 | `map_agg(k, v)` + `CAST` | 早期 | NULL 跳过 | 非标准；`json_format` 完成转换 |
| Spark SQL | 否 | -- | -- | -- | 用 `to_json(map_from_entries(collect_list(...)))` 模拟 |
| Databricks | 否 | -- | -- | -- | 同 Spark |
| Hive | 否 | -- | -- | -- | 用 brickhouse UDF |
| Impala | 否 | -- | -- | -- | 不支持 |
| Teradata | 是 | `JSON_AGG` (扩展) | 16.20+ | -- | 非标准 |
| Vertica | 否 | -- | -- | -- | 用 `MAPAGGREGATE` + 转换 |
| SAP HANA | 是 | `JSON_OBJECTAGG` (FOR JSON) | 2.0 SPS 04+ | -- | 标准语法部分支持 |
| H2 | 是 | `JSON_OBJECTAGG(k : v)` | 2.0+ | `ABSENT/NULL ON NULL` | 严格遵循标准 |
| HSQLDB | 否 | -- | -- | -- | 不支持 |
| Firebird | 否 | -- | -- | -- | 5.0 仅支持 JSON 函数，不含聚合 |
| Derby | 否 | -- | -- | -- | 不支持 JSON |
| Informix | 否 | -- | -- | -- | 不支持 |
| Greenplum | 是 | `json_object_agg(k, v)` | 6.0+ | -- | 继承 PostgreSQL |
| CockroachDB | 是 | `json_object_agg(k, v)` | 21.2+ | -- | 继承 PostgreSQL 命名 |
| TiDB | 是 | `JSON_OBJECTAGG(k, v)` | 5.0+ | 始终保留 NULL | 兼容 MySQL |
| OceanBase | 是 | `JSON_OBJECTAGG(k VALUE v)` | 4.x | `ABSENT/NULL ON NULL` | Oracle / MySQL 双兼容 |
| YugabyteDB | 是 | `json_object_agg(k, v)` | 2.x+ | -- | 继承 PostgreSQL |
| SingleStore | 否 | -- | -- | -- | 用 `GROUP_CONCAT` + `JSON_AGG_PRESERVE_ORDER` |
| StarRocks | 否 | -- | -- | -- | 不支持 |
| Doris | 否 | -- | -- | -- | 不支持 |
| MonetDB | 否 | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | `json_object_agg(k, v)` | 继承 | -- | 继承 PostgreSQL |
| QuestDB | 否 | -- | -- | -- | 不支持 |
| Exasol | 否 | -- | -- | -- | 7.x 不支持 |
| CrateDB | 否 | -- | -- | -- | 用 `object_agg` 实验性 |
| Materialize | 是 | `jsonb_object_agg(k, v)` | GA | -- | 兼容 PostgreSQL |
| RisingWave | 是 | `jsonb_object_agg(k, v)` | 1.0+ | -- | 兼容 PostgreSQL |
| Athena | 是 | `map_agg(k, v)` + cast | 继承 Trino | -- | -- |
| Synapse | 否 | -- | -- | -- | 用 `STRING_AGG` + 拼接 |
| Spanner | 否 | -- | -- | -- | 不支持 |
| Firebolt | 否 | -- | -- | -- | 不支持 |
| Yellowbrick | 否 | -- | -- | -- | 不支持 |
| ParadeDB | 是 | `json_object_agg(k, v)` | 继承 | -- | 继承 PostgreSQL |

> 统计：约 23 个引擎原生支持 `JSON_OBJECTAGG`（含 PostgreSQL 风格命名），其余引擎需通过 `MAP_AGG` + 转换、`FOR JSON` 拼装或字符串聚合模拟。

## 支持矩阵：JSON_ARRAYAGG（构建数组）

| 引擎 | 支持 | 语法 | 版本 | ORDER BY | NULL/ABSENT |
|------|------|------|------|----------|-------------|
| PostgreSQL | 是 | `json_agg(v)` / `jsonb_agg(v)` | 9.3 (2013) / 9.5 (2016) | 是（聚合内） | 始终保留 NULL |
| PostgreSQL 17+ | 是 | `JSON_ARRAYAGG(v)` | 17 (2024) | 是 | `ABSENT/NULL ON NULL` |
| MySQL | 是 | `JSON_ARRAYAGG(v)` | 5.7.22 (2018-04) | 否（语法层） | 始终保留 NULL |
| MariaDB | 是 | `JSON_ARRAYAGG(v)` | 10.5 (2020) | 否 | 始终保留 NULL |
| Oracle | 是 | `JSON_ARRAYAGG(v)` | 12c R2 (2017) | 是 | `ABSENT/NULL ON NULL` |
| SQL Server 2025 | 是 | `JSON_ARRAYAGG(v)` | 2025 preview | 是 | `ABSENT/NULL ON NULL` |
| SQL Server <2025 | 否 | `(SELECT ... FOR JSON PATH)` 子查询 | -- | 是 | -- |
| Azure SQL DB | 是 | `JSON_ARRAYAGG(v)` | 2024 | 是 | `ABSENT/NULL ON NULL` |
| Db2 | 是 | `JSON_ARRAYAGG(v ORDER BY ...)` | 11.5+ | 是 | `ABSENT/NULL ON NULL` |
| SQLite | 是 | `json_group_array(v)` | 3.38+ | 否 | 始终保留 NULL |
| ClickHouse | 否 | -- | -- | -- | -- |
| ClickHouse | 间接 | `groupArray(toJSONString(v))` | 早期 | 是 (`groupArrayArray`) | -- |
| DuckDB | 是 | `json_group_array(v)` / `JSON_ARRAYAGG(v)` | 0.6+ / 1.1+ | 是 | -- |
| Snowflake | 是 | `ARRAY_AGG(v)` (返回 ARRAY) | GA | 是 | NULL 自动跳过 |
| BigQuery | 否 | `TO_JSON(ARRAY_AGG(v))` 或 `TO_JSON_STRING(ARRAY_AGG(v))` | 2020 | 是 | NULL 跳过参数 |
| Redshift | 是 | `JSON_PARSE(LISTAGG(...))` 拼接 | -- | 是（LISTAGG 内） | -- |
| Trino / Presto | 是 | `cast(array_agg(v) as JSON)` | 早期 | 是 | -- |
| Spark SQL | 否 | `to_json(collect_list(v))` | -- | 否（无法保证有序） | -- |
| Databricks | 否 | 同上 | -- | -- | -- |
| Hive | 否 | `collect_list(v)` + brickhouse UDF | -- | -- | -- |
| Impala | 否 | -- | -- | -- | -- |
| Teradata | 是 | `JSON_AGG` (扩展) | 16.20+ | -- | -- |
| Vertica | 否 | `array_agg + TO_JSON` 模拟 | -- | -- | -- |
| SAP HANA | 是 | `JSON_ARRAYAGG` | 2.0 SPS 04+ | -- | -- |
| H2 | 是 | `JSON_ARRAYAGG(v)` | 2.0+ | 是 | `ABSENT/NULL ON NULL` |
| HSQLDB | 否 | -- | -- | -- | -- |
| Firebird | 否 | -- | -- | -- | -- |
| Derby | 否 | -- | -- | -- | -- |
| Informix | 否 | -- | -- | -- | -- |
| Greenplum | 是 | `json_agg(v)` | 6.0+ | 是 | -- |
| CockroachDB | 是 | `json_agg(v)` / `jsonb_agg(v)` | 21.2+ | 是 | -- |
| TiDB | 是 | `JSON_ARRAYAGG(v)` | 5.0+ | 否 | 始终保留 NULL |
| OceanBase | 是 | `JSON_ARRAYAGG(v)` | 4.x | 是 (Oracle 模式) | `ABSENT/NULL ON NULL` |
| YugabyteDB | 是 | `json_agg(v)` | 2.x+ | 是 | -- |
| SingleStore | 否 | `JSON_AGG` (聚合 String) | -- | -- | -- |
| StarRocks | 否 | -- | -- | -- | -- |
| Doris | 否 | -- | -- | -- | -- |
| MonetDB | 否 | -- | -- | -- | -- |
| TimescaleDB | 是 | `json_agg(v)` | 继承 | 是 | -- |
| QuestDB | 否 | -- | -- | -- | -- |
| Exasol | 否 | -- | -- | -- | -- |
| CrateDB | 否 | -- | -- | -- | -- |
| Materialize | 是 | `jsonb_agg(v)` | GA | 是 | -- |
| RisingWave | 是 | `jsonb_agg(v)` | 1.0+ | 是 | -- |
| Athena | 是 | `cast(array_agg(v) as JSON)` | 继承 Trino | 是 | -- |
| Synapse | 否 | `FOR JSON PATH` 子查询 | -- | -- | -- |
| Spanner | 否 | `ARRAY_AGG` 不返回 JSON | -- | -- | -- |
| Firebolt | 否 | -- | -- | -- | -- |
| Yellowbrick | 否 | -- | -- | -- | -- |
| ParadeDB | 是 | `json_agg(v)` | 继承 | 是 | -- |

> 统计：约 27 个引擎原生支持 `JSON_ARRAYAGG`（含 `json_agg` / `json_group_array` 命名变体），其余引擎需借道 `ARRAY_AGG` + 转换或字符串拼接。

## PostgreSQL 风格的 build_object 函数族

PostgreSQL 在标准化前自创了一组"按位置构建 JSON"的函数，至今在 PG 生态中比标准 `JSON_OBJECTAGG` 更常用：

| 函数 | 输入 | 输出 | 版本 | 用途 |
|------|------|------|------|------|
| `json_build_object` | 交替 key, value, ... | JSON object | 9.4 (2014) | 单行构建对象 |
| `jsonb_build_object` | 同上 | JSONB object | 9.5 (2016) | -- |
| `json_build_array` | 任意值列表 | JSON array | 9.4 (2014) | 单行构建数组 |
| `jsonb_build_array` | 同上 | JSONB array | 9.5 (2016) | -- |
| `json_object` | 单数组或两数组（key/value） | JSON object | 9.4 (2014) | 从 text[] 构建对象 |
| `json_agg` | 聚合输入 | JSON array | 9.3 (2013) | **聚合**多行成数组 |
| `jsonb_agg` | 同上 | JSONB array | 9.5 (2016) | -- |
| `json_object_agg` | 聚合 key, value | JSON object | 9.4 (2014) | **聚合**多行成对象 |
| `jsonb_object_agg` | 同上 | JSONB object | 9.5 (2016) | -- |
| `to_json` | 任意行 / 复合类型 | JSON | 9.2 (2012) | 类型转 JSON |
| `to_jsonb` | 同上 | JSONB | 9.4 (2014) | -- |
| `row_to_json` | 行类型 | JSON object | 9.2 (2012) | 行转对象 |
| `array_to_json` | 数组类型 | JSON array | 9.2 (2012) | 数组转 JSON |

```sql
-- 单行：构建嵌套对象
SELECT json_build_object(
    'order_id', o.id,
    'customer', json_build_object(
        'name', c.name,
        'email', c.email
    ),
    'total', o.total
) FROM orders o JOIN customers c ON o.customer_id = c.id;

-- 多行聚合：每个客户的订单数组
SELECT c.id,
       json_agg(
           json_build_object(
               'order_id', o.id,
               'total', o.total
           )
           ORDER BY o.created_at
       ) AS orders
FROM customers c
JOIN orders o ON o.customer_id = c.id
GROUP BY c.id;
```

`json_build_object` 是 PG 生态最常用的 JSON 构造手段，因为它：
- 不要求列名匹配（`row_to_json` 要求）
- 嵌套结构清晰（vs 字符串拼接）
- 优化器可以下推（vs 字符串函数无法）

## 支持矩阵：核心配套函数与语义

### NULL 处理

| 引擎 | 默认行为 | NULL ON NULL | ABSENT ON NULL | 备注 |
|------|---------|--------------|----------------|------|
| PostgreSQL `json_agg` | 保留 NULL | (默认) | 用 `FILTER (WHERE v IS NOT NULL)` | 9.4+ FILTER 子句 |
| PostgreSQL 17 `JSON_ARRAYAGG` | NULL ON NULL | 是 | 是 | 标准语法 |
| MySQL | 保留 NULL | (隐式) | 不支持 | 行为与标准一致但无开关 |
| MariaDB | 保留 NULL | (隐式) | 不支持 | -- |
| Oracle | ABSENT ON NULL | 是 | 是（默认） | 默认与标准相反 |
| SQL Server 2025 | ABSENT ON NULL | 是 | 是（默认） | 与 `FOR JSON` 行为一致 |
| Db2 | NULL ON NULL | 是 | 是 | 标准默认 |
| SQLite | 保留 NULL | (隐式) | 不支持 | 行为类似 MySQL |
| DuckDB | NULL ON NULL | 是 | 是 (1.1+) | -- |
| Snowflake `OBJECT_AGG` | 自动跳过 NULL | 不支持 | (隐式) | 行为类似 ABSENT ON NULL |
| Trino `map_agg` | 跳过 NULL key | -- | -- | NULL value 保留 |
| H2 | NULL ON NULL | 是 | 是 | 标准默认 |
| OceanBase Oracle 模式 | ABSENT ON NULL | 是 | 是 | -- |
| OceanBase MySQL 模式 | 保留 NULL | -- | -- | -- |

### ORDER BY 子句

| 引擎 | 支持位置 | 示例 |
|------|---------|------|
| PostgreSQL | 聚合参数内 | `json_agg(v ORDER BY id)` |
| Oracle | 聚合参数内 | `JSON_ARRAYAGG(v ORDER BY id)` |
| Db2 | 聚合参数内 | `JSON_ARRAYAGG(v ORDER BY id)` |
| SQL Server 2025 | 聚合参数内 | `JSON_ARRAYAGG(v ORDER BY id)` |
| H2 | 聚合参数内 | `JSON_ARRAYAGG(v ORDER BY id)` |
| MySQL | 不支持 | 需子查询 + ORDER BY |
| MariaDB | 不支持 | -- |
| TiDB | 不支持 | 兼容 MySQL |
| SQLite | 不支持 | 需子查询 |
| DuckDB | 聚合参数内 | `json_group_array(v ORDER BY id)` |
| Snowflake `ARRAY_AGG` | WITHIN GROUP | `ARRAY_AGG(v) WITHIN GROUP (ORDER BY id)` |
| Trino | 聚合参数内 | `array_agg(v ORDER BY id)` |
| BigQuery | 聚合参数内 | `ARRAY_AGG(v ORDER BY id)` |
| Redshift `LISTAGG` | WITHIN GROUP | `LISTAGG(...) WITHIN GROUP (ORDER BY id)` |
| Spark SQL | 不支持 | `collect_list` 不保证顺序 |

> MySQL 不支持 `JSON_ARRAYAGG(... ORDER BY ...)` 是其最大短板之一——大量场景必须靠子查询包装来保证顺序。

### UNIQUE KEYS 检测

| 引擎 | 支持 | 语法 | 行为 |
|------|------|------|------|
| Oracle | 是 | `WITH UNIQUE KEYS` | 重复键抛 ORA-40647 |
| Db2 | 是 | `WITH UNIQUE KEYS` | 重复键抛 SQLSTATE 23522 |
| SQL Server 2025 | 是 | `WITH UNIQUE KEYS` | 重复键抛错 |
| H2 | 是 | `WITH UNIQUE KEYS` | -- |
| PostgreSQL 17 | 是 | `WITH UNIQUE` | -- |
| 其他引擎 | 否 | -- | 后写覆盖前写（PG 老 API） / 保留所有重复 |

## 各引擎语法详解

### PostgreSQL（事实标准制定者）

PostgreSQL 9.3 (2013) 引入 `json_agg` 时，SQL 标准还没动笔。它的命名规范成了多个分支引擎（CockroachDB、Greenplum、YugabyteDB、Materialize、RisingWave、ParadeDB、TimescaleDB）的事实标准。

```sql
-- 9.3+: json_agg 数组聚合
SELECT json_agg(name) FROM products WHERE category = 'books';
-- ["War and Peace", "Anna Karenina", "Crime and Punishment"]

-- 9.4+: jsonb_agg 二进制版本
SELECT jsonb_agg(name) FROM products;

-- 9.4+: ORDER BY 在聚合内
SELECT json_agg(row_to_json(p) ORDER BY p.price DESC)
FROM products p;

-- 9.4+: FILTER 子句过滤 NULL（实现 ABSENT ON NULL 语义）
SELECT json_agg(email) FILTER (WHERE email IS NOT NULL)
FROM users;

-- 9.4+: json_object_agg 对象聚合
SELECT json_object_agg(category, count(*))
FROM products GROUP BY category;
-- {"books": 1234, "music": 567, "video": 890}

-- 9.4+: json_build_object 单行构建（最常用）
SELECT json_build_object(
    'id', id,
    'name', name,
    'tags', (SELECT json_agg(t.name) FROM tags t WHERE t.product_id = p.id)
) FROM products p;

-- 17+: SQL:2016 标准语法
SELECT JSON_ARRAYAGG(name ORDER BY price ABSENT ON NULL)
FROM products;

SELECT JSON_OBJECTAGG(category VALUE total_revenue WITH UNIQUE KEYS)
FROM (
    SELECT category, SUM(price * qty) AS total_revenue
    FROM order_items GROUP BY category
) t;
```

#### `json_agg` vs `jsonb_agg` 深度对比

| 维度 | json_agg | jsonb_agg |
|------|----------|-----------|
| 输出类型 | `json` | `jsonb` |
| 内部表示 | 文本（保留输入格式） | 二进制（解析后存储） |
| 键顺序 | 保留输入顺序 | 不保证（key 排序 / 哈希） |
| 重复键 | 保留所有 | 后写覆盖前写 |
| 空白字符 | 保留 | 规范化 |
| 性能（聚合时） | 略快（少一次解析） | 略慢（构建二进制） |
| 性能（后续 -> 访问） | 慢（每次解析） | 快（哈希查找） |
| 索引 | 不能直接 GIN | 可 GIN 索引 |
| 比较 | 文本比较（结构相同但格式不同会不等） | 语义比较 |

```sql
-- 关键差异：键顺序
SELECT json_object_agg('z', 1)::text || ' / ' || jsonb_object_agg('z', 1)::text;
-- json: {"z": 1}    jsonb: {"z": 1}    (单键时一样)

WITH t(k, v) AS (VALUES ('z', 1), ('a', 2), ('m', 3))
SELECT json_object_agg(k, v), jsonb_object_agg(k, v) FROM t;
-- json:  {"z":1, "a":2, "m":3}   保留 INSERT 顺序
-- jsonb: {"a":2, "m":3, "z":1}   规范化排序

-- 关键差异：重复键
WITH t(k, v) AS (VALUES ('a', 1), ('a', 2))
SELECT json_object_agg(k, v) FROM t;
-- {"a":1, "a":2}    json 保留两次

WITH t(k, v) AS (VALUES ('a', 1), ('a', 2))
SELECT jsonb_object_agg(k, v) FROM t;
-- {"a":2}    jsonb 只保留最后一次
```

**选择建议**：
- 输出后立即被消费（HTTP API 返回） → `json_agg`（少一次序列化）
- 需要进一步查询、索引或修改 → `jsonb_agg`
- 需要严格保留键顺序 → `json_agg`
- 需要去重键 → `jsonb_agg`

### MySQL / MariaDB（5.7.22 起的最小标准实现）

```sql
-- 5.7.22 (2018-04): JSON_ARRAYAGG / JSON_OBJECTAGG
SELECT JSON_ARRAYAGG(name) FROM products WHERE category = 'books';
-- ["War and Peace", "Anna Karenina"]

-- JSON_OBJECTAGG: 对象聚合
SELECT JSON_OBJECTAGG(category, total) FROM (
    SELECT category, COUNT(*) AS total FROM products GROUP BY category
) t;
-- {"books": 1234, "music": 567}

-- 限制 1: 不支持聚合内 ORDER BY
-- 错误: SELECT JSON_ARRAYAGG(name ORDER BY price) FROM products;
-- 必须用子查询：
SELECT JSON_ARRAYAGG(name)
FROM (SELECT name FROM products ORDER BY price) t;
-- 注意：MySQL 5.x 子查询的 ORDER BY 可能被优化器丢弃
-- 8.0 之后 ORDER BY 在派生表中通常会保留

-- 限制 2: 不支持 ABSENT/NULL ON NULL 子句
-- NULL 总是被保留
SELECT JSON_ARRAYAGG(email) FROM users;  -- 含 NULL

-- 模拟 ABSENT ON NULL: WHERE 过滤
SELECT JSON_ARRAYAGG(email) FROM users WHERE email IS NOT NULL;

-- 限制 3: 不支持 WITH UNIQUE KEYS
-- 重复 key 时行为：保留所有（与 json_agg 一致，和 jsonb_object_agg 不同）
SELECT JSON_OBJECTAGG(k, v) FROM (
    SELECT 'a' AS k, 1 AS v UNION ALL SELECT 'a', 2
) t;
-- {"a": 1, "a": 2}    重复保留

-- 实战：嵌套对象组装
SELECT JSON_OBJECT(
    'order_id', o.id,
    'items', (
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'item_id', oi.item_id,
            'qty', oi.qty
        ))
        FROM order_items oi WHERE oi.order_id = o.id
    )
) FROM orders o;
```

MariaDB 10.5+ 跟进了 MySQL 5.7.22 的 `JSON_ARRAYAGG` / `JSON_OBJECTAGG`，限制基本相同。TiDB 5.0+ 同样兼容这个最小子集。

### Oracle（最完整的标准实现）

Oracle 12c R2 (2017) 同期紧跟 SQL:2016，并率先实现了 `WITH UNIQUE KEYS`。

```sql
-- JSON_ARRAYAGG 完整语法
SELECT JSON_ARRAYAGG(name ORDER BY price)
       AS top_products
FROM products
WHERE rownum <= 10;

-- ABSENT ON NULL（Oracle 默认）
SELECT JSON_ARRAYAGG(email ABSENT ON NULL) FROM users;

-- NULL ON NULL（强制保留）
SELECT JSON_ARRAYAGG(email NULL ON NULL) FROM users;

-- RETURNING 子句指定输出类型
SELECT JSON_ARRAYAGG(name RETURNING CLOB) FROM products;
SELECT JSON_ARRAYAGG(name RETURNING VARCHAR2(4000)) FROM products;
SELECT JSON_ARRAYAGG(name RETURNING JSON) FROM products;  -- 21c+ 原生 JSON

-- JSON_OBJECTAGG 完整语法
SELECT JSON_OBJECTAGG(
    KEY category VALUE total
    ABSENT ON NULL
    WITH UNIQUE KEYS
    RETURNING JSON
)
FROM (
    SELECT category, SUM(amount) AS total
    FROM sales GROUP BY category
);

-- 嵌套 JSON_OBJECT/JSON_ARRAY 和聚合
SELECT JSON_OBJECT(
    'order_id' VALUE o.id,
    'items' VALUE (
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'item_id' VALUE oi.item_id,
                'qty' VALUE oi.qty
            )
            ORDER BY oi.line_no
            RETURNING JSON
        )
        FROM order_items oi WHERE oi.order_id = o.id
    )
    RETURNING JSON
) FROM orders o;

-- 唯一键检测（重复时抛错）
SELECT JSON_OBJECTAGG(KEY name VALUE id WITH UNIQUE KEYS)
FROM users;
-- ORA-40647: JSON_OBJECTAGG evaluation resulted in duplicate keys
```

OceanBase 4.x 在 Oracle 模式下完整支持上述语法，在 MySQL 模式下退化为 MySQL 5.7 子集。

### SQL Server（FOR JSON 时代到 SQL 2025 的迁移）

SQL Server 2016 引入 JSON 函数时**没有** `JSON_OBJECTAGG` / `JSON_ARRAYAGG`，要靠 `FOR JSON` 子句拼接：

```sql
-- 2016~2022: FOR JSON PATH 子查询模式
SELECT
    c.id,
    (SELECT o.id, o.total
     FROM orders o
     WHERE o.customer_id = c.id
     FOR JSON PATH) AS orders
FROM customers c;

-- 整张表转 JSON
SELECT id, name, email FROM users FOR JSON PATH;
-- [{"id":1, "name":"Alice", "email":"..."}, ...]

-- 单根对象（仅有一行时）
SELECT * FROM users WHERE id = 1
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

-- INCLUDE_NULL_VALUES 控制 NULL 处理
SELECT id, email FROM users
FOR JSON PATH, INCLUDE_NULL_VALUES;  -- 保留 NULL
SELECT id, email FROM users FOR JSON PATH;  -- 默认跳过 NULL（即 ABSENT ON NULL）

-- ROOT 子句包装根名
SELECT * FROM users FOR JSON PATH, ROOT('users');
-- {"users": [...]}

-- 关联子查询拼装：
SELECT
    c.id,
    c.name,
    (SELECT o.id AS order_id, o.total
     FROM orders o
     WHERE o.customer_id = c.id
     ORDER BY o.created_at
     FOR JSON PATH) AS orders_json
FROM customers c;

-- STRING_AGG 字符串拼接的 hack
SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(name, 'json') + '"', ',') + ']'
FROM products;
-- 危险：手动拼接极易出 BUG（嵌套引号、控制字符）

-- 2025 preview: 真正的 JSON_ARRAYAGG / JSON_OBJECTAGG
SELECT JSON_ARRAYAGG(name ORDER BY price) FROM products;
SELECT JSON_OBJECTAGG(category VALUE total) FROM categorized_sales;

-- 配套 2025 新增的 JSON 类型
DECLARE @json JSON;
SET @json = (SELECT JSON_ARRAYAGG(name) FROM products);
```

Azure SQL Database 在 2024 年中先行获得 `JSON_OBJECTAGG` / `JSON_ARRAYAGG`，本地 SQL Server 2025 GA 之后保持一致。

### ClickHouse（不直接支持 JSON 聚合）

ClickHouse 不实现 JSON 聚合的标准 API，但有等价的功能组合：

```sql
-- 1. 数组聚合 + JSON 序列化
SELECT toJSONString(groupArray(name)) FROM products;
-- '["War and Peace","Anna Karenina"]'

-- 2. groupArray 返回 ClickHouse Array，不是 JSON
SELECT groupArray(name) FROM products;
-- ['War and Peace', 'Anna Karenina']    -- ClickHouse Array 类型

-- 3. groupArrayArray 用于嵌套数组聚合
SELECT groupArrayArray([name, category]) FROM products;

-- 4. 元组聚合后转 JSON
SELECT toJSONString(groupArray((id, name, price)))
FROM products;
-- '[{"1":1,"2":"book","3":10.0},{"1":2,"2":"pen","3":1.0}]'  -- 注意：tuple 序列化键是位置

-- 5. 用 Map 类型 + 序列化模拟 JSON_OBJECTAGG
SELECT toJSONString(mapFromArrays(
    groupArray(category),
    groupArray(total)
)) FROM categorized_sales;
-- '{"books":1234,"music":567}'

-- 6. 利用 JSONExtract 函数族（输入端）
-- ClickHouse 24.x 起的实验性 JSON 类型支持更原生的操作
```

ClickHouse 的设计哲学是**列式优先 + 数组原生**，而不是 JSON。当输出格式确实需要 JSON 时，靠最后一步 `toJSONString` 或 `JSONFormat` 转换。

### DuckDB（双轨命名）

```sql
-- DuckDB 风格（早期）
SELECT json_group_array(name) FROM products;
SELECT json_group_object(category, total) FROM categorized_sales;

-- 1.1+: 标准语法别名
SELECT JSON_ARRAYAGG(name) FROM products;
SELECT JSON_OBJECTAGG(category VALUE total) FROM categorized_sales;

-- ORDER BY 在聚合内
SELECT json_group_array(name ORDER BY price DESC) FROM products;

-- 嵌套结构组装
SELECT {
    'order_id': o.id,
    'items': (
        SELECT json_group_array({
            'item_id': oi.item_id,
            'qty': oi.qty
        })
        FROM order_items oi WHERE oi.order_id = o.id
    )
} FROM orders o;

-- DuckDB 的 STRUCT 字面量自动转 JSON
SELECT to_json(LIST({'k': k, 'v': v})) FROM (
    SELECT 'a' AS k, 1 AS v UNION ALL SELECT 'b', 2
);
```

DuckDB 同时提供 `json_group_array` 和 `JSON_ARRAYAGG` 两种命名，前者沿袭 SQLite 习惯，后者拥抱 SQL 标准。

### Snowflake（独有的 OBJECT_AGG / ARRAY_AGG）

Snowflake 的 JSON 是 `VARIANT` 类型，没有专门的 JSON 聚合，而是用通用的 `ARRAY_AGG` / `OBJECT_AGG` + `VARIANT`：

```sql
-- ARRAY_AGG 聚合成 ARRAY 类型（ARRAY 在 Snowflake 中即 VARIANT 数组）
SELECT ARRAY_AGG(name) FROM products WHERE category = 'books';
-- ["War and Peace", "Anna Karenina"]   -- 类型为 ARRAY

-- WITHIN GROUP 指定顺序
SELECT ARRAY_AGG(name) WITHIN GROUP (ORDER BY price DESC)
FROM products;

-- DISTINCT 子句
SELECT ARRAY_AGG(DISTINCT category) FROM products;

-- OBJECT_AGG 聚合成 OBJECT 类型
SELECT OBJECT_AGG(category, total)
FROM (SELECT category, SUM(amount) AS total
      FROM sales GROUP BY category);
-- {"books": 1234, "music": 567}

-- OBJECT_CONSTRUCT 单行构造对象
SELECT OBJECT_CONSTRUCT(
    'order_id', o.id,
    'customer', OBJECT_CONSTRUCT(
        'name', c.name,
        'email', c.email
    ),
    'items', (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
            'item_id', oi.item_id,
            'qty', oi.qty
        )) WITHIN GROUP (ORDER BY oi.line_no)
        FROM order_items oi WHERE oi.order_id = o.id
    )
) FROM orders o JOIN customers c ON o.customer_id = c.id;

-- OBJECT_CONSTRUCT_KEEP_NULL 保留 NULL（默认跳过）
SELECT OBJECT_CONSTRUCT_KEEP_NULL('a', 1, 'b', NULL);
-- {"a": 1, "b": null}

-- VARIANT 类型自由转换
SELECT TO_JSON(ARRAY_AGG(name)) FROM products;  -- 转字符串
SELECT PARSE_JSON('[1,2,3]')::ARRAY;  -- 字符串转 ARRAY
```

Snowflake 没有 `JSON_OBJECTAGG` / `JSON_ARRAYAGG` 关键字，但 `OBJECT_AGG` / `ARRAY_AGG` + `VARIANT` 提供等价能力。语义上 Snowflake 的 `OBJECT_AGG` 默认跳过 NULL value（类似 ABSENT ON NULL），需 `OBJECT_CONSTRUCT_KEEP_NULL` 才保留。

### BigQuery（依靠 TO_JSON 转换）

BigQuery 没有 `JSON_OBJECTAGG`/`JSON_ARRAYAGG`，但有 STRUCT/ARRAY 原生类型 + `TO_JSON_STRING` / `TO_JSON`：

```sql
-- ARRAY_AGG 返回 ARRAY 类型
SELECT ARRAY_AGG(name ORDER BY price) FROM products;

-- ARRAY_AGG STRUCT 嵌套
SELECT ARRAY_AGG(STRUCT(item_id, qty) ORDER BY line_no)
FROM order_items;

-- TO_JSON_STRING：序列化为 STRING（最常用）
SELECT TO_JSON_STRING(ARRAY_AGG(name)) FROM products;
-- '["War and Peace","Anna Karenina"]'

SELECT TO_JSON_STRING(ARRAY_AGG(STRUCT(id, name, price)))
FROM products;
-- '[{"id":1,"name":"book","price":10.0}, ...]'

-- TO_JSON：返回 JSON 类型（2020 GA）
SELECT TO_JSON(ARRAY_AGG(STRUCT(id, name, price)))
FROM products;
-- 类型为 JSON，可继续做 JSON 操作

-- IGNORE NULLS 跳过 NULL
SELECT TO_JSON(ARRAY_AGG(email IGNORE NULLS))
FROM users;

-- 模拟 JSON_OBJECTAGG: STRUCT + TO_JSON
SELECT TO_JSON(ARRAY_AGG(STRUCT(category AS k, total AS v)))
FROM categorized_sales;
-- '[{"k":"books","v":1234}, {"k":"music","v":567}]'
-- 注意：这是数组形式，不是真正的 {"books":1234, ...} 对象

-- 真正的对象需要先构造 STRUCT
WITH agg AS (
    SELECT ARRAY_AGG(STRUCT(category, total)) AS rows
    FROM categorized_sales
)
SELECT TO_JSON(STRUCT(
    (SELECT rows[OFFSET(0)].category FROM agg) AS books,
    -- ... 静态字段，无法动态对象化
)) FROM agg;

-- BigQuery 真正模拟 JSON_OBJECTAGG 的现实方案：
-- 用 ARRAY<STRUCT<k STRING, v ANY>> 然后客户端转
SELECT ARRAY_AGG(STRUCT(category AS key, total AS value))
FROM categorized_sales;
```

BigQuery 真正缺乏的是"动态键名"对象聚合——因为它的 STRUCT 类型在 SQL 编译期类型已知，不允许运行时动态键。这与 PG/Oracle 的 JSON_OBJECTAGG 在表达力上有本质差距。

### Trino / Presto / Athena

```sql
-- array_agg 返回 ARRAY 类型
SELECT array_agg(name) FROM products;

-- ORDER BY 在聚合内
SELECT array_agg(name ORDER BY price DESC) FROM products;

-- CAST 到 JSON
SELECT cast(array_agg(name) AS JSON) FROM products;
-- 等价于 JSON_ARRAYAGG

-- map_agg 聚合成 MAP
SELECT map_agg(category, total)
FROM (SELECT category, SUM(amount) AS total
      FROM sales GROUP BY category);

-- 模拟 JSON_OBJECTAGG
SELECT cast(map_agg(category, total) AS JSON)
FROM (SELECT category, SUM(amount) AS total
      FROM sales GROUP BY category);
-- {"books": 1234, "music": 567}

-- 嵌套结构
SELECT cast(
    array_agg(
        cast(row(item_id, qty, price) AS row(item_id varchar, qty integer, price double))
        ORDER BY line_no
    ) AS JSON
)
FROM order_items;

-- json_format 显式序列化
SELECT json_format(cast(array_agg(name) AS JSON))
FROM products;
```

Trino 的关键是把"聚合到 ARRAY/MAP"和"序列化到 JSON"明确分两步——这与 BigQuery 和 Snowflake 思路一致。

### Spark SQL / Databricks

```sql
-- collect_list 返回 ARRAY（不保证顺序）
SELECT collect_list(name) FROM products;

-- collect_set 去重
SELECT collect_set(name) FROM products;

-- to_json 序列化
SELECT to_json(collect_list(name)) FROM products;
-- '["a","b","c"]'

-- 模拟 JSON_OBJECTAGG: map_from_entries + to_json
SELECT to_json(map_from_entries(
    collect_list(struct(category, total))
))
FROM categorized_sales;

-- 关键限制：collect_list 不保证顺序
-- 解决方案：先排序再聚合（在 ARRAY_SORT 或子查询中）
SELECT to_json(array_sort(collect_list(struct(price, name))))
FROM products;
-- 按 price 升序排序后输出（按第一个字段排序）

-- Databricks SQL 同上
```

Spark SQL 长期没有 `JSON_ARRAYAGG`，到 3.5 也未直接提供，必须组合 `collect_list` + `to_json`。

### 其他引擎概览

```sql
-- SQLite (3.38+): json_group_array / json_group_object
SELECT json_group_array(name) FROM products;
SELECT json_group_object(category, total) FROM categorized_sales;

-- Db2 11.5+
SELECT JSON_ARRAYAGG(name ORDER BY price RETURNING CLOB) FROM products;
SELECT JSON_OBJECTAGG(KEY category VALUE total
                      ABSENT ON NULL
                      WITH UNIQUE KEYS
                      RETURNING CLOB)
FROM categorized_sales;

-- H2 2.0+: 严格遵循 SQL:2016 标准
SELECT JSON_ARRAYAGG(name ORDER BY price ABSENT ON NULL) FROM products;
SELECT JSON_OBJECTAGG(category : total) FROM categorized_sales;

-- SAP HANA 2.0 SPS 04+
SELECT JSON_OBJECTAGG(KEY category VALUE total) FROM categorized_sales;

-- Teradata 16.20+
SELECT JSON_AGG(name) FROM products;

-- CockroachDB
SELECT json_agg(name) FROM products;
SELECT jsonb_agg(name) FROM products;

-- Greenplum 6.0+ (基于 PostgreSQL 9.4 fork)
SELECT json_agg(name) FROM products;

-- YugabyteDB (PG 兼容)
SELECT json_agg(name) FROM products;

-- TiDB (MySQL 兼容)
SELECT JSON_ARRAYAGG(name) FROM products;

-- Materialize / RisingWave (PG 兼容)
SELECT jsonb_agg(name) FROM products;

-- Redshift (无 JSON 聚合，靠 LISTAGG)
SELECT '[' || LISTAGG('"' || REPLACE(name, '"', '\"') || '"', ',')
              WITHIN GROUP (ORDER BY price) || ']'
FROM products;
-- 或：JSON_PARSE 解析后变 SUPER 类型
SELECT JSON_PARSE('[' || LISTAGG('"' || name || '"', ',') || ']')
FROM products;
```

## SQL Server FOR JSON 的工作原理

在 SQL Server 2025 之前，要从多行生成 JSON 数组只能用 `FOR JSON`，理解它的语义对维护老代码很关键：

```sql
-- FOR JSON AUTO: 按 SELECT 列表自动推断结构
SELECT
    c.id,
    c.name,
    o.id AS [orders.id],
    o.total AS [orders.total]
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
FOR JSON AUTO;
-- AUTO 模式自动按 JOIN 嵌套
-- [{"id":1,"name":"A","orders":[{"id":11,"total":100},...]}]

-- FOR JSON PATH: 显式控制嵌套（推荐）
SELECT
    c.id,
    c.name,
    (SELECT o.id, o.total
     FROM orders o
     WHERE o.customer_id = c.id
     FOR JSON PATH) AS orders
FROM customers c
FOR JSON PATH;

-- WITHOUT_ARRAY_WRAPPER: 单根对象（仅一行时）
SELECT TOP 1 * FROM users WHERE id = @id
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
-- {"id":1, "name":"..."}    没有外层 []

-- INCLUDE_NULL_VALUES: 默认跳过 NULL 列
SELECT id, email FROM users FOR JSON PATH;  -- {"id":1}    email NULL 被跳过
SELECT id, email FROM users FOR JSON PATH, INCLUDE_NULL_VALUES;  -- {"id":1,"email":null}

-- ROOT: 添加根名
SELECT * FROM users FOR JSON PATH, ROOT('users');
-- {"users":[...]}

-- 字符串拼接陷阱（不要用！）
DECLARE @json NVARCHAR(MAX);
SET @json = '[' +
    (SELECT STRING_AGG('"' + STRING_ESCAPE(name, 'json') + '"', ',')
     FROM products) +
    ']';
-- 风险：忘记转义会注入；NULL 处理；集合空时变成 '[]' or NULL
```

迁移到 SQL Server 2025 时，`FOR JSON` 子查询可逐步替换为 `JSON_ARRAYAGG`：

```sql
-- 旧（2016~2022）
SELECT
    c.id,
    (SELECT name, email FROM customers WHERE id = c.id
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS info,
    (SELECT id, total FROM orders WHERE customer_id = c.id
     FOR JSON PATH) AS orders
FROM customers c;

-- 新（2025+）
SELECT
    c.id,
    JSON_OBJECT('name' VALUE c.name, 'email' VALUE c.email) AS info,
    (SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE id, 'total' VALUE total))
     FROM orders WHERE customer_id = c.id) AS orders
FROM customers c;
```

## Snowflake / BigQuery 的对照实现

两大云数仓都没有 `JSON_OBJECTAGG`，但它们的设计哲学不同：

### Snowflake：用 VARIANT 抹平

```sql
-- Snowflake 把 JSON / OBJECT / ARRAY 都看作 VARIANT 子类型
-- 因此 OBJECT_AGG 直接返回 OBJECT，不需要 cast 到 JSON
SELECT OBJECT_AGG(category, total) FROM categorized_sales;
-- 返回 OBJECT 类型 (VARIANT)

-- 显式转 JSON 字符串
SELECT TO_JSON(OBJECT_AGG(category, total)) FROM categorized_sales;
-- 返回 STRING

-- 反向：JSON 字符串 → OBJECT
SELECT PARSE_JSON('{"a":1}'):a;  -- 1 (VARIANT)
```

Snowflake 的 `OBJECT_CONSTRUCT_KEEP_NULL` vs `OBJECT_CONSTRUCT` 控制 NULL 行为，对应标准的 NULL ON NULL vs ABSENT ON NULL。

### BigQuery：用 STRUCT/ARRAY + TO_JSON

```sql
-- BigQuery 主张：在编译期已知结构 → 用 STRUCT/ARRAY；运行时动态 → 用 JSON 类型

-- 静态结构（推荐）：
SELECT ARRAY_AGG(STRUCT(id, name, price)) AS products
FROM products;
-- 类型: ARRAY<STRUCT<id INT64, name STRING, price FLOAT64>>

-- 转 JSON 类型（2020 GA）
SELECT TO_JSON(ARRAY_AGG(STRUCT(id, name, price))) FROM products;
-- 类型: JSON

-- 转 JSON 字符串（任何时候都可以）
SELECT TO_JSON_STRING(ARRAY_AGG(STRUCT(id, name, price))) FROM products;
-- 类型: STRING

-- BigQuery 也有 PARSE_JSON 反向操作
SELECT PARSE_JSON('{"a":1}') AS j;
-- 类型: JSON

-- 动态键名的"对象聚合"在 BigQuery 中不直接支持，常见 workaround：
-- ARRAY<STRUCT<key, value>>，由消费方自行转 dict
SELECT ARRAY_AGG(STRUCT(category AS key, total AS value)) AS pairs
FROM categorized_sales;
-- 然后客户端 / dbt 把 pairs 转成 {"books":1234,"music":567}
```

BigQuery 的"动态键聚合"短板源自其编译期类型系统：JSON 类型出现后情况有所改善，但仍不如 Snowflake VARIANT 灵活。

## ABSENT ON NULL vs NULL ON NULL：语义陷阱

```sql
-- 测试数据
+----+----------+
| id | email    |
+----+----------+
|  1 | a@x.com  |
|  2 | NULL     |
|  3 | c@x.com  |
+----+----------+

-- NULL ON NULL（标准默认）
SELECT JSON_ARRAYAGG(email NULL ON NULL) FROM users;
-- ["a@x.com", null, "c@x.com"]    保留 NULL

-- ABSENT ON NULL
SELECT JSON_ARRAYAGG(email ABSENT ON NULL) FROM users;
-- ["a@x.com", "c@x.com"]    跳过 NULL

-- 各引擎默认值
| 引擎 | 默认 |
|------|------|
| 标准 SQL:2016 | NULL ON NULL |
| Oracle | ABSENT ON NULL（违反标准！） |
| SQL Server 2025 | ABSENT ON NULL（与 FOR JSON 一致） |
| PostgreSQL 17 | NULL ON NULL |
| Db2 | NULL ON NULL |
| H2 | NULL ON NULL |
| MySQL | 始终 NULL ON NULL（无法切换） |
| Snowflake OBJECT_AGG | 跳过 NULL value |
```

迁移陷阱：从 Oracle / SQL Server 迁移到 PostgreSQL / MySQL 时，包含 NULL 的行计数会变化（保留还是跳过结果差很多）。生产代码建议**显式写出** `ABSENT ON NULL` 或 `NULL ON NULL`。

## ORDER BY 在 JSON 聚合中的关键作用

```sql
-- 没有 ORDER BY：结果顺序由执行计划决定（哈希聚合通常不保序）
SELECT JSON_ARRAYAGG(name) FROM products;
-- 顺序不可预测：可能 [c,a,b]、[b,a,c]，每次执行不同

-- 加 ORDER BY 强制顺序
SELECT JSON_ARRAYAGG(name ORDER BY id) FROM products;
-- 严格按 id 升序

-- 多列排序
SELECT JSON_ARRAYAGG(name ORDER BY category ASC, price DESC) FROM products;

-- 关联子查询里的 ORDER BY
SELECT
    c.id,
    (SELECT JSON_ARRAYAGG(o.id ORDER BY o.created_at DESC)
     FROM orders o WHERE o.customer_id = c.id) AS recent_orders
FROM customers c;
```

各引擎细节：
- PostgreSQL/Oracle/Db2/SQL Server 2025/H2/DuckDB：`ORDER BY` 在聚合参数内
- Snowflake：`ARRAY_AGG(...) WITHIN GROUP (ORDER BY ...)` (Oracle 老语法)
- MySQL/MariaDB/TiDB/SQLite：不支持，必须用 ORDER BY 子查询包装
- Spark SQL：`collect_list` 不保证顺序，需 `array_sort` 或子查询

```sql
-- MySQL 子查询模式
SELECT JSON_ARRAYAGG(name)
FROM (SELECT name FROM products ORDER BY price) t;
-- MySQL 5.7 派生表的 ORDER BY 可能被优化器丢弃，8.0 之后较稳定
-- 严格保证顺序的写法（MySQL 8.0+）：
SELECT JSON_ARRAYAGG(name)
FROM (SELECT name FROM products ORDER BY price LIMIT 18446744073709551615) t;
-- LIMIT 大数 trick：强制保留 ORDER BY
```

## 嵌套 JSON 文档构建：实战模式

```sql
-- 模式 1: 单表多列 → 单层对象数组
-- PostgreSQL
SELECT json_agg(row_to_json(p))
FROM products p;
-- [{"id":1,"name":"book","price":10}, ...]

-- 模式 2: 主从表 → 嵌套对象（关联子查询）
-- PostgreSQL
SELECT json_agg(json_build_object(
    'order_id', o.id,
    'customer', (SELECT row_to_json(c) FROM customers c WHERE c.id = o.customer_id),
    'items', (SELECT json_agg(row_to_json(oi))
              FROM order_items oi WHERE oi.order_id = o.id)
))
FROM orders o;

-- 模式 3: 主从表 → 嵌套对象（LATERAL JOIN）
-- PostgreSQL（性能更好）
SELECT json_agg(json_build_object(
    'order_id', o.id,
    'customer', c_json,
    'items', items_json
))
FROM orders o
JOIN LATERAL (SELECT row_to_json(c) AS c_json
              FROM customers c WHERE c.id = o.customer_id) c ON true
JOIN LATERAL (SELECT json_agg(row_to_json(oi)) AS items_json
              FROM order_items oi WHERE oi.order_id = o.id) items ON true;

-- 模式 4: 全部展平到一个文档
-- BigQuery
SELECT TO_JSON(STRUCT(
    o.id AS order_id,
    (SELECT AS STRUCT c.name, c.email
     FROM customers c WHERE c.id = o.customer_id) AS customer,
    ARRAY(SELECT AS STRUCT oi.item_id, oi.qty, oi.price
          FROM order_items oi WHERE oi.order_id = o.id) AS items
))
FROM orders o;

-- 模式 5: 字段动态键名
-- PostgreSQL: jsonb_object_agg + GROUP BY
SELECT jsonb_object_agg(
    user_id::text,
    jsonb_build_object('name', name, 'email', email)
)
FROM users;
-- {"1":{"name":"A","email":"a@x"}, "2":{"name":"B","email":"b@x"}}

-- BigQuery: STRUCT 不能动态键，只能 ARRAY<STRUCT<key,value>>
SELECT ARRAY_AGG(STRUCT(
    CAST(user_id AS STRING) AS key,
    STRUCT(name, email) AS value
))
FROM users;
```

## 性能对比：JSON 聚合的成本

```
1000 万行表 (产品维度)，PostgreSQL 16，单线程：

json_agg(name)                           ~  600 ms
json_agg(name ORDER BY price)            ~  900 ms  (+50% 排序开销)
jsonb_agg(name)                          ~  720 ms  (二进制构建额外 20%)
json_agg(row_to_json(t))                 ~ 1500 ms  (每行先转对象再聚合)
json_object_agg(id, name)                ~  680 ms

100 万分组每组 10 行：
GROUP BY + json_agg                       ~ 2000 ms
GROUP BY + jsonb_agg                      ~ 2500 ms
```

引擎差异（粗略基准，10M 行 + json_agg）：
- DuckDB：~ 200ms（向量化 + 列式扫描）
- ClickHouse：~ 150ms（groupArray + toJSONString）
- PostgreSQL：~ 600ms
- MySQL：~ 1200ms（行存 + 文本 JSON）
- SQL Server：~ 1100ms（FOR JSON PATH）
- BigQuery：~ 800ms（云端，因网络与 slot 数量波动）

性能要点：
1. 二进制 JSON（jsonb）写入慢于文本 JSON（json）
2. 排序聚合 ≈ 普通聚合 + 排序成本
3. 行转对象（`row_to_json`）开销显著，能用 `json_build_object` 显式列就尽量显式
4. 列式引擎（DuckDB/ClickHouse/Snowflake）天然占便宜（向量化批量序列化）

## 设计争议

### 命名分裂：json_agg vs JSON_ARRAYAGG

PostgreSQL 选择 `json_agg`（小写 + 短名）有历史原因——9.3 (2013) 时还没有 SQL:2016 标准。等到 SQL:2016 标准化后，PG 维护团队没有破坏向后兼容性，直到 17 才补充标准名 `JSON_ARRAYAGG`。

这种"事实标准 vs 后期标准"的撕裂在 SQL 历史上反复出现：
- `STRING_AGG`（标准） vs `LISTAGG`（Oracle） vs `GROUP_CONCAT`（MySQL）
- `BOOLEAN`（标准） vs `BIT`（SQL Server）
- `LIMIT/OFFSET`（PG/MySQL） vs `FETCH FIRST`（标准） vs `TOP`（SQL Server）

引擎开发者建议：**两套都实现**，标准名作为推荐，老名字作为兼容别名。

### 输出类型：STRING vs JSON 类型

各引擎对"JSON 聚合返回什么类型"分两派：
- 派 A：返回 JSON 类型（PostgreSQL `json_agg → json`、Oracle `JSON_ARRAYAGG → JSON/CLOB`、Db2 `→ CLOB`、SQL Server 2025 `→ JSON`）
- 派 B：返回 ARRAY/OBJECT/MAP/STRUCT 等"原生集合类型"（Snowflake `ARRAY_AGG → ARRAY`、BigQuery `ARRAY_AGG → ARRAY<...>`、Trino `array_agg → ARRAY`）

派 A 的优势：直接传给客户端就是 JSON 字符串，HTTP API 友好。
派 B 的优势：仍是结构化类型，可以继续在 SQL 内部操作（取下标、过滤、JOIN UNNEST），最后才序列化。

引擎开发者建议：OLTP 业务（直接拼前端响应）派 A 更方便；OLAP/管道（仍要二次处理）派 B 更优雅。最佳实践是**两套都提供**，让用户选择。

### 自动 NULL 跳过 vs 标准的 NULL ON NULL

Snowflake / Trino 默认跳过 NULL（无显式 `ABSENT ON NULL` 子句）违反 SQL:2016 标准默认。Oracle 则在 `JSON_ARRAYAGG` / `JSON_OBJECTAGG` 上默认 ABSENT ON NULL，理由是"输出 JSON 通常不希望有显式 null"。

这种"语义不一致"的代价是迁移时的隐藏 BUG——同一个聚合查询在不同引擎结果集大小不同。

引擎开发者建议：尊重 SQL:2016 默认值（NULL ON NULL），同时在文档第一行就强调可用 `ABSENT ON NULL` 切换。

### MySQL 的"无 ORDER BY"短板

MySQL 5.7.22 引入 `JSON_ARRAYAGG` 时，团队为简化实现没有支持聚合内 `ORDER BY`。这导致大量场景必须借助子查询 ORDER BY，而 MySQL 的优化器在派生表 ORDER BY 上行为不稳定。

10 年过去了，MySQL 9.x 仍未补齐这个能力——这是 MySQL 在文档型应用场景下输给 PostgreSQL 的关键之一。

### 重复键的处理

```sql
-- 测试：两行 key 相同
INSERT INTO t VALUES ('a', 1), ('a', 2);
SELECT json_object_agg(k, v) FROM t;
```

行为对比：
- PostgreSQL `json_object_agg`：保留两个键 `{"a":1, "a":2}`（违反 JSON 规范）
- PostgreSQL `jsonb_object_agg`：后写覆盖前写 `{"a":2}`
- MySQL `JSON_OBJECTAGG`：保留两个键 `{"a":1, "a":2}`
- Oracle `JSON_OBJECTAGG`（默认）：保留两个键
- Oracle `JSON_OBJECTAGG WITH UNIQUE KEYS`：抛错
- Snowflake `OBJECT_AGG`：后写覆盖前写

JSON RFC 7159 说"重复键的行为未定义"，所以严格说所有引擎都没"违反"标准——但 PostgreSQL `json` 类型的"双键文本"被许多解析器拒绝。生产建议：**始终显式 GROUP BY 或 DISTINCT 避免依赖引擎默认**。

## 对引擎开发者的实现建议

### 1. 数据结构选择

```
JSON 聚合的累加器选择直接决定性能：

文本累加器（PG json_agg、MySQL JSON_ARRAYAGG）：
  - 状态：StringBuilder
  - 输入：每行序列化成文本，append 到 buffer
  - 输出：string → cast to JSON
  - 优点：实现简单，零额外内存
  - 缺点：无法去重 key、无法保序键

二进制累加器（PG jsonb_agg）：
  - 状态：未排序键值对列表（聚合时） → 排序合并（finalize 时）
  - 输入：解析每行为 JSONB，加入列表
  - 输出：build BinaryHeader + sorted KV
  - 优点：可处理重复键，可索引
  - 缺点：finalize 慢（排序）

向量化累加器（DuckDB / ClickHouse）：
  - 状态：列式 batch（如 ARRAY<JSON> chunked vector）
  - 输入：批量 append 整个向量
  - 输出：finalize 时拼接所有 chunk
  - 优点：cache friendly，SIMD 优化空间大
  - 缺点：实现复杂
```

### 2. 排序的代价控制

```
ORDER BY 在聚合内的实现：

方案 A：先 sort 再 aggregate
  - SortNode → AggregateNode
  - 适合：单分组或低基数 GROUP BY
  - 缺点：排序 N log N，不能并行 finalize

方案 B：每个分组单独排序
  - HashAggregate → 每分组 buffer → 各组排序 → 拼接
  - 适合：高基数 GROUP BY
  - 缺点：内存占用大，每组都要排

方案 C：流式排序合并
  - SortMergeJoin 风格：先按 GROUP BY 排序，再按 ORDER BY 排序
  - 适合：需要稳定输出顺序
  - 实现复杂度高
```

### 3. NULL 处理的代码路径

```
NULL ON NULL（默认）:
  for row in input:
      buffer.append(serialize(row))   // 即使 NULL 也 append 'null'

ABSENT ON NULL:
  for row in input:
      if row is not NULL:
          buffer.append(serialize(row))
```

实现要点：
- 在 build phase 就处理 NULL，不要在 finalize 阶段过滤（避免 buffer 反复扩容）
- 向量化场景：用 NULL bitmap + selection vector 跳过 NULL 输入
- 推断 ABSENT ON NULL 时，count_non_null 估计输出基数

### 4. 唯一键检测（WITH UNIQUE KEYS）

```
方案 A：哈希集合检测
  state.keys = HashSet<String>
  for (k, v) in input:
      if !state.keys.insert(k):
          throw DuplicateKey(k)
      state.kv.append((k, v))
  - 内存：O(N)
  - 时间：O(N) 平均

方案 B：排序后线性扫描（finalize 时）
  state.kv: Vec<(k, v)>
  finalize:
      sort by k
      for i in 1..len:
          if kv[i].k == kv[i-1].k:
              throw DuplicateKey
  - 内存：O(N)
  - 时间：O(N log N) sort 阶段
  - 优点：单线程聚合可省掉哈希构建
```

并行聚合：每个 partial state 各自检测，merge 时再做一遍跨 partial 检测。

### 5. 嵌套 JSON 的递归构建

JSON 聚合常嵌套使用：`json_agg(json_build_object('items', json_agg(...)))`。
关键实现细节：

```
1. JSON 类型必须支持类型递归：JSON 元素可以是 JSON
2. 序列化优化：内层 JSON 不要重复解析
   - PG: jsonb 直接 binary copy，json 直接 text copy
   - 不应：parse → re-serialize（性能损失）
3. 内存复用：内层聚合 finalize 后，外层只引用 buffer 不拷贝
```

### 6. 优化器交互

```
1. 行数估计：JSON_ARRAYAGG 输出 1 行（每分组 1 行）
2. 输出大小：sum(input row size) + JSON 框架开销 (~5%)
   - 用于规划是否需要 spill to disk
3. 谓词下推：FILTER (WHERE ...) 可在聚合前下推
4. 并行聚合：state 可分区合并（merge 函数）
   - 数组聚合：concat
   - 对象聚合：merge KV（注意 UNIQUE KEYS 检测）
5. 失败模式：JSON 输出超大（如 GB 级）应触发 spill 而非 OOM
```

### 7. 序列化输出格式

```
JSON 字符串生成规则：
  - 整数：直接 itoa
  - 浮点：尽量短的可逆字符串（dragon4 / grisu）
  - 字符串：UTF-8 + escape (\\, \", \n, \r, \t, \uXXXX)
  - NULL：字面量 null
  - Boolean：true/false
  - 嵌套：递归调用

性能优化：
  - 预估 buffer 大小（避免反复 realloc）
  - 字符串转义用 SIMD（AVX2 _mm_cmpeq + _mm_or 一次扫描）
  - 数字转字符串用 ryu / dragon4
  - 整体输出用 IOVec 零拷贝（如果直接送网络）
```

### 8. 测试要点

```
正确性测试：
- 空集：JSON_ARRAYAGG(...) FROM empty_table → []
- 全 NULL：NULL ON NULL → [null,null]，ABSENT ON NULL → []
- 嵌套：JSON_ARRAYAGG(JSON_OBJECT(...)) 多层嵌套
- 重复键：WITH UNIQUE KEYS 抛错；默认行为
- 排序：ORDER BY 多列稳定性
- Unicode：emoji、控制字符、surrogate pair 转义
- 大对象：单行 100KB JSON 不破坏聚合

性能测试：
- 10M 行小 JSON 聚合到 100K 分组
- 1M 行大 JSON（10KB/行）聚合
- 排序聚合 vs 无序聚合对比
- 二进制 JSON vs 文本 JSON 性能差异

兼容性测试：
- ABSENT ON NULL 与 FILTER 等价性
- 跨引擎语法迁移（PG → MySQL → Oracle 同一查询）
```

## 关键发现

1. **历史滞后造成 PG 命名垄断**：PostgreSQL 9.3 (2013) 早 SQL:2016 三年发布 `json_agg`，使 `json_agg` / `jsonb_agg` 成为 PostgreSQL 派生引擎（CockroachDB, Greenplum, YugabyteDB, TimescaleDB, Materialize, RisingWave, ParadeDB）的事实标准；而后来居上的 MySQL/Oracle/Db2/SQL Server 用了 SQL:2016 标准的 `JSON_ARRAYAGG` / `JSON_OBJECTAGG`。

2. **MySQL 5.7.22 (2018-04) 是分水岭**：在此之前 MySQL JSON 生态严重不全；之后才开始流行 JSON 列 + 聚合的工程实践。但 MySQL 至今不支持聚合内 ORDER BY 是其重大短板。

3. **SQL Server 2025 是迟到 9 年的 catch-up**：从 2016 至 2024 都靠 `FOR JSON PATH` 子查询拼接，2025 preview 才提供原生 `JSON_OBJECTAGG` / `JSON_ARRAYAGG`。Azure SQL DB 在 2024 年就抢先发布。

4. **Oracle / SQL Server 2025 的默认 ABSENT ON NULL 违反标准**：标准默认是 NULL ON NULL，但这两家选择 ABSENT ON NULL，理由是"工程上更常用"。跨引擎迁移时这是最常见的隐藏 BUG。

5. **ClickHouse / BigQuery / Snowflake 不直接提供 JSON 聚合**，但通过 `groupArray` / `ARRAY_AGG` + `to_json` 等价：
   - ClickHouse: `toJSONString(groupArray(...))`
   - BigQuery: `TO_JSON(ARRAY_AGG(STRUCT(...)))`
   - Snowflake: `ARRAY_AGG(...)` 直接是 ARRAY (VARIANT)

6. **`json_build_object` vs `JSON_OBJECTAGG` 是两类不同的功能**：前者按位置构建单行对象（PostgreSQL 9.4+），后者从多行聚合成对象（标准 SQL:2016）。两者经常组合使用：`json_object_agg(id, json_build_object(...))`。

7. **`json_agg` vs `jsonb_agg` 在 PostgreSQL 中的选择**：取决于"输出后立即被消费 vs 需要二次处理"——前者快但不能索引/去重键，后者支持完整 JSONB 操作但写入慢 20%。

8. **ORDER BY 是一条难以跨越的鸿沟**：MySQL/MariaDB/TiDB/SQLite 不支持聚合内 ORDER BY，必须借子查询；MySQL 5.7 派生表 ORDER BY 还会被优化器丢弃，工程师常被迫用 `LIMIT 大数` 之类的奇技淫巧。

9. **WITH UNIQUE KEYS 的支持率很低**：仅 Oracle/Db2/SQL Server 2025/H2/PostgreSQL 17 支持，多数引擎对重复键采取"保留全部"或"后写覆盖"，导致输出可能不是合法 JSON。

10. **二进制 JSON 是性能与索引的关键**：PostgreSQL 9.4 (2014) 的 JSONB、MySQL 5.7 (2015) 的 JSON、Oracle 21c (2021) 的原生 JSON 类型都选择了二进制路线；ClickHouse 24.x 实验性 JSON 类型也是二进制。

11. **云数仓与传统数据库的输出类型分裂**：传统派（PG/Oracle/Db2/SQL Server）输出 JSON/CLOB；云数仓派（Snowflake/BigQuery/Trino/Spark）输出 ARRAY<STRUCT> / MAP / VARIANT，需要显式 `TO_JSON` 转换才得到字符串。这反映了 OLAP 场景下"数据再加工"的需求。

## 参考资料

- ISO/IEC 9075-2:2016 第 10.9 节 JSON aggregate functions
- PostgreSQL: [JSON Functions and Operators](https://www.postgresql.org/docs/current/functions-json.html)
- PostgreSQL 17: [SQL/JSON Aggregate Functions](https://www.postgresql.org/docs/17/functions-aggregate.html#FUNCTIONS-AGGREGATE-SQLJSON)
- MySQL: [JSON_ARRAYAGG / JSON_OBJECTAGG](https://dev.mysql.com/doc/refman/8.4/en/aggregate-functions.html#function_json-arrayagg)
- Oracle: [JSON_OBJECTAGG / JSON_ARRAYAGG](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/JSON_OBJECTAGG.html)
- SQL Server 2025: [JSON_OBJECTAGG / JSON_ARRAYAGG](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-objectagg-transact-sql)
- Db2: [JSON_OBJECTAGG / JSON_ARRAYAGG](https://www.ibm.com/docs/en/db2/11.5)
- Snowflake: [OBJECT_AGG / ARRAY_AGG](https://docs.snowflake.com/en/sql-reference/functions/object_agg)
- BigQuery: [TO_JSON / ARRAY_AGG](https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions#to_json)
- DuckDB: [JSON Aggregate Functions](https://duckdb.org/docs/data/json/overview.html)
- Trino: [Aggregate Functions](https://trino.io/docs/current/functions/aggregate.html)
- SQLite: [json_group_array / json_group_object](https://www.sqlite.org/json1.html)
- H2: [JSON_ARRAYAGG / JSON_OBJECTAGG](http://www.h2database.com/html/functions-aggregate.html)
- Markus Winand: ["SQL/JSON in PostgreSQL 17"](https://modern-sql.com/blog/2024-09/postgresql-17)
- Lukas Eder: ["Standard SQL/JSON in jOOQ"](https://blog.jooq.org/standard-sql-json-the-sobering-parts/)

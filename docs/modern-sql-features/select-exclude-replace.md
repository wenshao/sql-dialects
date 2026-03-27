# SELECT * EXCLUDE / REPLACE / RENAME

从宽表中选取"除了某几列之外的所有列"——现代分析引擎对 SELECT * 的实用扩展。

## 支持矩阵

| 引擎 | EXCLUDE | REPLACE | RENAME | 语法 | 版本 | 备注 |
|------|---------|---------|--------|------|------|------|
| DuckDB | 支持 | 支持 | 支持 | EXCLUDE / REPLACE | 0.3.0+ | **最完整** |
| BigQuery | 支持 | 支持 | 不支持 | EXCEPT / REPLACE | GA | 用 EXCEPT 不是 EXCLUDE |
| Databricks | 支持 | 不支持 | 不支持 | EXCEPT | Runtime 7.0+ | 仅 EXCEPT |
| Snowflake | 支持 | 支持 | 支持 | EXCLUDE / RENAME / REPLACE | GA | 完整支持 |
| Spark SQL | 支持 | 不支持 | 不支持 | EXCEPT | 3.0+ | - |
| ClickHouse | 支持 | 支持 | 不支持 | EXCEPT / REPLACE | 21.8+ | 也支持正则 EXCEPT |
| Trino | 不支持 | 不支持 | 不支持 | - | - | - |
| PostgreSQL | 不支持 | 不支持 | 不支持 | - | - | - |
| MySQL | 不支持 | 不支持 | 不支持 | - | - | - |
| Oracle | 不支持 | 不支持 | 不支持 | - | - | - |
| SQL Server | 不支持 | 不支持 | 不支持 | - | - | - |
| SQLite | 不支持 | 不支持 | 不支持 | - | - | - |

## 设计动机: 宽表的痛点

### 问题场景

```sql
-- 现代数据仓库中，宽表（100+ 列）非常常见
-- 例如: 用户行为宽表有 150 列

-- 需求: 查询所有列，但排除敏感信息（身份证号、手机号）
-- 传统方式: 列出所有 147 列（不含 3 个敏感列）
SELECT
    user_id, name, age, gender, city, province, country,
    signup_date, last_login, login_count, device_type,
    -- ... 省略 130+ 列 ...
    total_orders, total_amount, avg_order_value
FROM user_profile;
-- 问题: 列名写到手抽筋，漏一列都不知道

-- 需求: 把金额列从分转换为元，其他列不变
-- 传统方式: 列出所有列，只改一列的表达式
SELECT
    user_id, name, age,
    -- ... 省略 145 列 ...
    amount_cents / 100.0 AS amount,     -- 只有这一列变了
    -- ... 省略剩余列 ...
FROM orders;
```

### EXCLUDE / REPLACE 的解决方案

```sql
-- EXCLUDE: 排除几列
SELECT * EXCLUDE (id_card, phone, password) FROM user_profile;

-- REPLACE: 替换某列的表达式
SELECT * REPLACE (amount_cents / 100.0 AS amount) FROM orders;

-- 简洁、不遗漏、维护方便
```

## 各引擎语法对比

### DuckDB（最完整的支持）

```sql
-- EXCLUDE: 排除指定列
SELECT * EXCLUDE (column1, column2) FROM table_name;

-- 示例
SELECT * EXCLUDE (password, ssn, phone) FROM users;

-- REPLACE: 替换列的表达式（列名保持不变）
SELECT * REPLACE (upper(name) AS name, salary * 1.1 AS salary) FROM employees;

-- EXCLUDE + REPLACE 组合使用
SELECT * EXCLUDE (internal_id) REPLACE (amount / 100.0 AS amount)
FROM transactions;

-- COLUMNS 表达式: 基于正则选择列（DuckDB 独有扩展）
SELECT COLUMNS('revenue_.*') FROM financial_report;  -- 选择所有 revenue_ 开头的列
SELECT COLUMNS('.*_amount') FROM orders;              -- 选择所有 _amount 结尾的列

-- COLUMNS + 函数应用
SELECT MIN(COLUMNS(*)) FROM data;      -- 每列的最小值
SELECT COLUMNS('.*') + 1 FROM data;    -- 所有列加 1

-- COLUMNS + EXCLUDE 组合
SELECT COLUMNS(* EXCLUDE (id, created_at)) FROM events;

-- 表前缀限定
SELECT t1.* EXCLUDE (id), t2.* EXCLUDE (id)
FROM table1 t1 JOIN table2 t2 ON t1.key = t2.key;

-- RENAME（DuckDB 特色）
-- DuckDB 通过 COLUMNS 表达式间接实现重命名
```

### BigQuery（EXCEPT 和 REPLACE）

```sql
-- BigQuery 使用 EXCEPT 而不是 EXCLUDE
SELECT * EXCEPT (column1, column2) FROM table_name;

-- 示例
SELECT * EXCEPT (raw_json, internal_flags)
FROM events
WHERE event_date = '2024-03-01';

-- REPLACE: 替换列表达式
SELECT * REPLACE (
    UPPER(name) AS name,
    ROUND(score, 2) AS score
)
FROM students;

-- EXCEPT + REPLACE 组合
SELECT * EXCEPT (debug_info) REPLACE (
    FORMAT_TIMESTAMP('%Y-%m-%d', created_at) AS created_at
)
FROM logs;

-- 在子查询中使用
SELECT * EXCEPT (rn) FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts DESC) AS rn
    FROM events
) WHERE rn = 1;
-- 这个模式非常实用: 用 ROW_NUMBER 去重后排除辅助列

-- 在 STRUCT 类型中使用（BigQuery 扩展）
SELECT event.* EXCEPT (internal_id)
FROM events;
```

### Snowflake（EXCLUDE / RENAME / REPLACE）

```sql
-- EXCLUDE: 排除列
SELECT * EXCLUDE (column1, column2) FROM table_name;

-- RENAME: 重命名列（Snowflake 独有）
SELECT * RENAME (old_name AS new_name) FROM table_name;

-- 多列重命名
SELECT * RENAME (
    first_name AS fname,
    last_name AS lname,
    date_of_birth AS dob
)
FROM customers;

-- REPLACE: 替换列表达式
SELECT * REPLACE (amount * exchange_rate AS amount) FROM transactions;

-- 三者组合使用
SELECT *
    EXCLUDE (internal_id, debug_flags)
    RENAME (created_timestamp AS created_at)
    REPLACE (ROUND(score, 2) AS score)
FROM assessments;

-- 使用顺序: EXCLUDE → RENAME → REPLACE
-- 先排除列，再重命名，最后替换表达式

-- 表前缀限定
SELECT t1.* EXCLUDE (join_key), t2.* EXCLUDE (join_key, redundant_col)
FROM table1 t1 JOIN table2 t2 ON t1.join_key = t2.join_key;
```

### Databricks / Spark SQL（仅 EXCEPT）

```sql
-- Databricks 使用 EXCEPT
SELECT * EXCEPT (column1, column2) FROM table_name;

-- 示例
SELECT * EXCEPT (raw_data, _rescued_data) FROM bronze_events;

-- 在 CTE 中使用
WITH cleaned AS (
    SELECT *, UPPER(name) AS name_upper FROM raw_data
)
SELECT * EXCEPT (name) FROM cleaned;    -- 排除原始 name，保留 name_upper

-- 注意: Spark SQL 原生不支持 REPLACE
-- 需要手动列出要替换的列
```

### ClickHouse（EXCEPT + REPLACE + 正则）

```sql
-- EXCEPT: 排除列（支持正则表达式）
SELECT * EXCEPT (column1, column2) FROM table_name;

-- 正则排除（ClickHouse 独有）
SELECT * EXCEPT ('.*_internal') FROM events;         -- 排除所有 _internal 结尾的列
SELECT * EXCEPT ('debug_.*') FROM logs;              -- 排除所有 debug_ 开头的列

-- REPLACE: 替换列
SELECT * REPLACE (toUInt32(id) AS id, upper(name) AS name) FROM users;

-- EXCEPT + REPLACE
SELECT * EXCEPT (raw_data) REPLACE (
    formatDateTime(event_time, '%Y-%m-%d') AS event_time
)
FROM events;

-- APPLY: 对所有列应用函数（ClickHouse 独有）
SELECT * APPLY (toString) FROM numbers(3);   -- 所有列转字符串
SELECT * APPLY (x -> x * 2) FROM data;       -- 所有列乘以 2
```

## 不支持引擎的替代方案

### PostgreSQL / MySQL / Oracle / SQL Server

```sql
-- 这些引擎不支持 EXCLUDE/REPLACE，只能:

-- 方案 1: 显式列出所有需要的列（最常见但最痛苦）
SELECT col1, col2, col3, /* ... */ col98, col100
FROM wide_table;  -- 跳过 col99

-- 方案 2: 使用视图预先定义常用列集合
CREATE VIEW wide_table_safe AS
SELECT col1, col2, col3, /* ... */ col98, col100
FROM wide_table;  -- 排除了敏感列
SELECT * FROM wide_table_safe;

-- 方案 3: 动态 SQL（不推荐，但有时是唯一选择）
-- PostgreSQL:
SELECT string_agg(column_name, ', ')
FROM information_schema.columns
WHERE table_name = 'wide_table'
  AND column_name NOT IN ('password', 'ssn');
-- 生成列名列表后拼接 SQL

-- 方案 4: ORM 层面排除
-- Django: Model.objects.defer('password', 'ssn')
-- Rails: Model.select(Model.column_names - ['password', 'ssn'])
```

## 实际场景

### 1. 去重后排除辅助列

```sql
-- 最常见的用法: ROW_NUMBER 去重后排除 rn 列
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM events
) WHERE rn = 1;

-- 没有 EXCLUDE 时需要列出原表的所有列
-- 有 EXCLUDE 时一行搞定
```

### 2. 宽表 JOIN 排除重复列

```sql
-- JOIN 时两个表有同名的 key 列
SELECT
    a.* EXCLUDE (customer_id),
    b.* EXCLUDE (customer_id),
    a.customer_id
FROM orders a
JOIN customers b ON a.customer_id = b.customer_id;
-- 避免结果中出现两个 customer_id 列
```

### 3. 单位转换

```sql
-- 金额从分转为元，其他 100+ 列不变
SELECT * REPLACE (
    amount_cents / 100.0 AS amount,
    tax_cents / 100.0 AS tax,
    discount_cents / 100.0 AS discount
)
FROM order_details;
```

### 4. 数据脱敏

```sql
-- 排除敏感列，对部分列做脱敏
SELECT *
    EXCLUDE (raw_phone, raw_email)
    REPLACE (
        CONCAT(LEFT(name, 1), '***') AS name,
        CONCAT('****', RIGHT(phone, 4)) AS phone_masked
    )
FROM customer_data;
```

## 对引擎开发者的实现建议

### 1. 语义分析阶段展开

EXCLUDE/REPLACE 本质是语法糖，在语义分析阶段展开为显式列列表：

```
输入 AST:
  SelectStar {
    exclude: [col3, col5],
    replace: [(upper(col2), col2)]
  }

展开后 AST:
  SelectList [col1, upper(col2) AS col2, col4, col6, ...]

实现步骤:
1. 解析 SELECT * 得到表的所有列: [col1, col2, col3, col4, col5, col6]
2. 过滤 EXCLUDE 列: [col1, col2, col4, col6]
3. 应用 REPLACE: [col1, upper(col2) AS col2, col4, col6]
4. 替换 AST 中的 SelectStar 为 SelectList
```

### 2. 语法关键字选择

```
EXCLUDE vs EXCEPT:
- EXCLUDE: DuckDB, Snowflake 使用
- EXCEPT: BigQuery, Databricks, ClickHouse 使用
- 冲突: EXCEPT 也是集合操作关键字（UNION / INTERSECT / EXCEPT）
- 建议: 使用 EXCLUDE，避免与集合操作 EXCEPT 混淆
  但如果兼容 BigQuery 生态，用 EXCEPT 并通过上下文消歧
```

### 3. 错误处理

```sql
-- 1. EXCLUDE 的列不存在
SELECT * EXCLUDE (nonexistent_col) FROM users;
-- 应该报错: column "nonexistent_col" does not exist in table "users"

-- 2. EXCLUDE 所有列
SELECT * EXCLUDE (col1, col2, col3) FROM small_table;  -- small_table 只有这 3 列
-- 应该报错: SELECT * EXCLUDE would result in zero columns

-- 3. REPLACE 的列不在 * 中
SELECT * REPLACE (upper(nonexistent) AS nonexistent) FROM users;
-- 应该报错: column "nonexistent" does not exist

-- 4. EXCLUDE + REPLACE 引用同一列
SELECT * EXCLUDE (name) REPLACE (upper(name) AS name) FROM users;
-- 应该报错: column "name" appears in both EXCLUDE and REPLACE
```

### 4. 与其他特性的交互

```sql
-- 与 table.* 的交互
SELECT t1.* EXCLUDE (id), t2.* EXCLUDE (id)
FROM t1 JOIN t2 ON t1.id = t2.id;
-- 每个 table.* 独立处理 EXCLUDE

-- 与 STRUCT 的交互（BigQuery 风格）
SELECT event.* EXCEPT (internal_id) FROM events;
-- 需要知道 event STRUCT 的所有字段

-- 与 SELECT DISTINCT 的交互
SELECT DISTINCT * EXCLUDE (id) FROM events;
-- 先展开 EXCLUDE，再应用 DISTINCT

-- 与 GROUP BY * 的交互（DuckDB 支持 GROUP BY ALL）
SELECT * EXCLUDE (amount), SUM(amount) FROM orders GROUP BY ALL;
-- GROUP BY ALL 自动识别非聚合列
```

## 设计争议: 便利性 vs 可读性

### 支持者观点

1. **宽表场景的必要性**: 100+ 列的表，手写列名不现实
2. **维护成本低**: 上游新增列时，EXCLUDE 查询自动包含新列
3. **减少错误**: 不会遗漏列
4. **现代分析工作流**: 数据探索、ETL 管道中大量使用 SELECT *

### 反对者观点

1. **可读性差**: 不看表结构就不知道结果包含哪些列
2. **脆弱性**: 上游新增列时，下游查询自动包含——可能不是预期行为
3. **SELECT * 本身的问题**: 生产代码不应该用 SELECT *
4. **标准化**: 不在 SQL 标准中，各引擎语法不一致

### 务实的建议

```
适用场景:
- 数据探索和 ad-hoc 查询（交互式分析）
- ETL 管道中的中间步骤
- 数据脱敏视图
- 测试和调试

不适用场景:
- 生产应用的 SQL（应显式列出列名）
- API 接口返回的查询（列集合应稳定）
- 长期维护的报表查询
```

## 参考资料

- DuckDB: [SELECT * EXCLUDE/REPLACE](https://duckdb.org/docs/sql/expressions/star)
- BigQuery: [SELECT * EXCEPT/REPLACE](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_except)
- Snowflake: [EXCLUDE/RENAME/REPLACE](https://docs.snowflake.com/en/sql-reference/sql/select#usage-notes-for-exclude-rename-replace)
- Databricks: [SELECT * EXCEPT](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select.html)
- ClickHouse: [EXCEPT/REPLACE](https://clickhouse.com/docs/en/sql-reference/statements/select#except)

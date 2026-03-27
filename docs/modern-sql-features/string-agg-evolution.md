# 字符串聚合的演进

将多行的值拼接成一个字符串——从 MySQL 的 GROUP_CONCAT 到 SQL:2016 标准的 LISTAGG，各引擎走了完全不同的路。

## 支持矩阵

| 引擎 | 函数 | 版本 | 标准 | 备注 |
|------|------|------|------|------|
| MySQL | `GROUP_CONCAT` | 4.1+ | 非标准 | **默认 1024 字节截断** |
| PostgreSQL | `STRING_AGG` | 9.0+ | 类似 SQL:2016 | 也可用 `ARRAY_AGG` + `ARRAY_TO_STRING` |
| SQL Server | `STRING_AGG` | 2017+ | 类似 SQL:2016 | 旧版用 `FOR XML PATH` |
| Oracle | `LISTAGG` | 11gR2+ | SQL:2016 | 12cR2+ 支持 `ON OVERFLOW` |
| SQLite | `GROUP_CONCAT` | 3.5.4+ | 非标准 | 与 MySQL 同名但行为有别 |
| BigQuery | `STRING_AGG` | GA | 类似 SQL:2016 | - |
| Snowflake | `LISTAGG` | GA | SQL:2016 | 也支持 `ARRAY_AGG` |
| ClickHouse | `groupArray` + `arrayStringConcat` | 早期版本 | 非标准 | 函数组合式 |
| DuckDB | `STRING_AGG` / `GROUP_CONCAT` / `LISTAGG` | 0.3.0+ | 多别名 | 三种语法均支持 |
| Trino | `LISTAGG` / `ARRAY_JOIN(ARRAY_AGG())` | 357+ | SQL:2016 | - |
| Hive | `CONCAT_WS` + `COLLECT_LIST` | 0.13+ | 非标准 | 两步实现 |
| Spark SQL | `CONCAT_WS` + `COLLECT_LIST` | 2.0+ | 非标准 | 同 Hive |

## 核心需求

```sql
-- 需求: 每个部门的员工名字拼接成逗号分隔的字符串
-- 输入:
-- dept_id | name
-- 1       | Alice
-- 1       | Bob
-- 1       | Charlie
-- 2       | Dave
-- 2       | Eve

-- 期望输出:
-- dept_id | names
-- 1       | Alice, Bob, Charlie
-- 2       | Dave, Eve
```

看似简单的需求，但涉及分隔符、排序、去重、溢出处理等多个维度的差异。

## 各引擎语法对比

### MySQL GROUP_CONCAT（最早但有陷阱）

```sql
-- 基本用法
SELECT dept_id, GROUP_CONCAT(name) AS names
FROM employees GROUP BY dept_id;
-- 输出: "Alice,Bob,Charlie"（默认逗号分隔，顺序不确定）

-- 指定分隔符
SELECT dept_id, GROUP_CONCAT(name SEPARATOR ' | ') AS names
FROM employees GROUP BY dept_id;
-- 输出: "Alice | Bob | Charlie"

-- 排序
SELECT dept_id, GROUP_CONCAT(name ORDER BY name ASC SEPARATOR ', ') AS names
FROM employees GROUP BY dept_id;
-- 输出: "Alice, Bob, Charlie"

-- 去重
SELECT dept_id, GROUP_CONCAT(DISTINCT skill ORDER BY skill SEPARATOR ', ') AS skills
FROM employee_skills GROUP BY dept_id;

-- ⚠️ 致命陷阱: 默认最大长度 1024 字节！
-- 超过 1024 字节时静默截断，不报错！
SHOW VARIABLES LIKE 'group_concat_max_len';
-- 默认值: 1024

-- 修改限制（会话级或全局级）
SET SESSION group_concat_max_len = 1000000;
SET GLOBAL group_concat_max_len = 1000000;

-- 这是 MySQL 中最常见的数据丢失 bug 之一
-- 很多开发者不知道结果被截断了
```

### PostgreSQL STRING_AGG

```sql
-- 基本用法（注意: 分隔符是必需参数）
SELECT dept_id, STRING_AGG(name, ', ') AS names
FROM employees GROUP BY dept_id;

-- 排序（在函数内部指定）
SELECT dept_id, STRING_AGG(name, ', ' ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- 去重
SELECT dept_id, STRING_AGG(DISTINCT name, ', ' ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- FILTER 子句（PostgreSQL 9.4+ 通用聚合过滤）
SELECT dept_id,
    STRING_AGG(name, ', ') FILTER (WHERE salary > 50000) AS high_earners
FROM employees GROUP BY dept_id;

-- 替代方案: ARRAY_AGG + ARRAY_TO_STRING（更灵活）
SELECT dept_id, ARRAY_TO_STRING(ARRAY_AGG(name ORDER BY name), ', ') AS names
FROM employees GROUP BY dept_id;

-- ARRAY_AGG 可以做更多操作（去重、切片后再拼接）
SELECT dept_id,
    ARRAY_TO_STRING(
        (ARRAY_AGG(DISTINCT name ORDER BY name))[1:5],  -- 只取前 5 个
        ', '
    ) AS top_5_names
FROM employees GROUP BY dept_id;

-- PostgreSQL 的 STRING_AGG 没有长度限制
-- 但超大结果可能导致 OOM
```

### SQL Server STRING_AGG (2017+)

```sql
-- 基本用法
SELECT dept_id, STRING_AGG(name, ', ') AS names
FROM employees GROUP BY dept_id;

-- 排序: 使用 WITHIN GROUP
SELECT dept_id, STRING_AGG(name, ', ') WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- 注意: SQL Server 的 STRING_AGG 默认返回类型与输入类型相同
-- 对于 VARCHAR(50) 的列，结果也是 VARCHAR(MAX 取决于具体情况)
-- 超过 8000 字节时需要显式转换:
SELECT dept_id,
    STRING_AGG(CAST(name AS NVARCHAR(MAX)), ', ') AS names
FROM employees GROUP BY dept_id;

-- 旧版 SQL Server (2016-) 替代方案: FOR XML PATH
SELECT dept_id,
    STUFF((
        SELECT ', ' + name
        FROM employees e2
        WHERE e2.dept_id = e1.dept_id
        ORDER BY name
        FOR XML PATH('')
    ), 1, 2, '') AS names
FROM employees e1
GROUP BY dept_id;
-- FOR XML PATH 是一种 hack，利用了 XML 拼接的副作用
-- 缺点: 会对特殊字符做 XML 转义（& → &amp;）
```

### Oracle LISTAGG（SQL:2016 标准）

```sql
-- 基本用法
SELECT dept_id, LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- WITHIN GROUP (ORDER BY ...) 是必需的

-- ⚠️ Oracle 11gR2 ~ 12cR1 的问题: 结果超过 4000 字节时报错
-- ORA-01489: result of string concatenation is too long

-- Oracle 12cR2+ 解决方案: ON OVERFLOW TRUNCATE
SELECT dept_id,
    LISTAGG(name, ', ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
    WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;
-- 超长时输出: "Alice, Bob, Charlie, ...(47)"

-- ON OVERFLOW ERROR（默认行为，显式声明）
SELECT dept_id,
    LISTAGG(name, ', ' ON OVERFLOW ERROR)
    WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- 去重（Oracle 19c+）
SELECT dept_id,
    LISTAGG(DISTINCT name, ', ') WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;
-- 19c 之前需要子查询去重

-- 窗口函数版本
SELECT dept_id, name,
    LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name)
        OVER (PARTITION BY dept_id) AS all_names
FROM employees;
```

### ClickHouse

```sql
-- ClickHouse 使用函数组合而非专用聚合函数

-- groupArray: 聚合为数组
-- arrayStringConcat: 数组拼接为字符串
SELECT dept_id,
    arrayStringConcat(groupArray(name), ', ') AS names
FROM employees GROUP BY dept_id;

-- 排序: 结合 arraySort
SELECT dept_id,
    arrayStringConcat(arraySort(groupArray(name)), ', ') AS names
FROM employees GROUP BY dept_id;

-- 去重: arrayDistinct
SELECT dept_id,
    arrayStringConcat(arraySort(arrayDistinct(groupArray(name))), ', ') AS names
FROM employees GROUP BY dept_id;

-- 限制数量: groupArray(N)(col)
SELECT dept_id,
    arrayStringConcat(groupArray(5)(name), ', ') AS top_5_names
FROM employees GROUP BY dept_id;
-- 只取每组前 5 个

-- groupUniqArray: 自动去重的数组聚合
SELECT dept_id,
    arrayStringConcat(arraySort(groupUniqArray(name)), ', ') AS names
FROM employees GROUP BY dept_id;
```

### Hive / Spark SQL

```sql
-- 两步实现: COLLECT_LIST + CONCAT_WS
SELECT dept_id,
    CONCAT_WS(', ', COLLECT_LIST(name)) AS names
FROM employees GROUP BY dept_id;

-- COLLECT_SET 自动去重
SELECT dept_id,
    CONCAT_WS(', ', COLLECT_SET(name)) AS unique_names
FROM employees GROUP BY dept_id;

-- 排序: 需要先排序再聚合（Spark 3.4+）
SELECT dept_id,
    CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(name))) AS sorted_names
FROM employees GROUP BY dept_id;
```

## 关键差异对比

| 维度 | MySQL | PostgreSQL | SQL Server | Oracle | ClickHouse |
|------|-------|-----------|------------|--------|-----------|
| 函数名 | GROUP_CONCAT | STRING_AGG | STRING_AGG | LISTAGG | groupArray+join |
| 分隔符 | SEPARATOR | 第二参数 | 第二参数 | WITHIN GROUP 前 | arrayStringConcat |
| 排序 | ORDER BY 在内 | ORDER BY 在内 | WITHIN GROUP | WITHIN GROUP | arraySort |
| 去重 | DISTINCT | DISTINCT | 需子查询 | DISTINCT (19c+) | arrayDistinct |
| 溢出处理 | 静默截断 | 无限制 | 无限制 | ON OVERFLOW | 无限制 |
| 默认限制 | 1024 字节 | 无 | 8000 字节* | 4000 字节* | 无 |
| NULL 处理 | 跳过 NULL | 跳过 NULL | 跳过 NULL | 跳过 NULL | 跳过 NULL |

\* 可通过类型转换绕过

## SQL:2016 标准 LISTAGG

```sql
-- SQL:2016 标准化了字符串聚合，命名为 LISTAGG
-- 语法:
LISTAGG([ALL | DISTINCT] expression [, separator]
    [ON OVERFLOW {ERROR | TRUNCATE [filler] [WITH | WITHOUT COUNT}])
WITHIN GROUP (ORDER BY ...)

-- 目前完全符合标准的引擎: Oracle (12cR2+), Trino, DuckDB
-- 部分符合: Snowflake（无 ON OVERFLOW）
```

## 对引擎开发者的实现建议

### 1. 内存管理

字符串聚合的最大挑战是内存：当某个 GROUP 有大量行时，拼接结果可能占用巨大内存。

```
StringAggAccumulator {
    buffer: StringBuilder       // 动态增长的字符串缓冲区
    separator: String
    has_value: bool
    total_bytes: usize          // 跟踪总大小

    fn update(value: String):
        if has_value:
            buffer.append(separator)
        buffer.append(value)
        total_bytes += value.len() + separator.len()

        // 可选: 内存保护
        if total_bytes > MAX_ALLOWED:
            if overflow_policy == ERROR: raise Error
            if overflow_policy == TRUNCATE: mark_truncated()

    fn merge(other: StringAggAccumulator):
        // 分布式聚合时合并两个 buffer
        // 注意: 需要保持 ORDER BY 的全局有序性
        // 如果有 ORDER BY，简单拼接是错的！
}
```

### 2. ORDER BY 的实现

带 ORDER BY 的字符串聚合在分布式环境中很有挑战：

```
方案 A: 先全局排序，再聚合（准确但性能差）
  局部排序 → Shuffle → 全局排序 → 聚合

方案 B: 局部聚合存储 (value, sort_key) 对，合并时排序（内存大）
  局部: 收集所有 (value, sort_key) 对
  合并: 按 sort_key 排序，再拼接

方案 C: 不保证排序（某些引擎的默认行为）
```

### 3. 溢出策略设计

建议实现三种策略：

1. **ERROR**: 超过限制时报错（最安全，Oracle 默认）
2. **TRUNCATE**: 超过限制时截断并附加省略信息
3. **UNLIMITED**: 无限制（PostgreSQL 方式，风险由用户承担）

默认策略的选择很重要：MySQL 选了静默截断（最差的设计），Oracle 选了报错（安全但不便），PostgreSQL 选了无限制（便利但有 OOM 风险）。

建议默认策略为 ERROR，同时支持 ON OVERFLOW TRUNCATE。

### 4. 兼容性考量

如果引擎需要兼容 MySQL，同时支持现代标准：

```sql
-- MySQL 兼容: GROUP_CONCAT(col SEPARATOR ',')
-- 标准方式:  LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)

-- 建议: 两种语法都支持，内部映射到同一个执行算子
-- GROUP_CONCAT 的默认截断行为可以通过变量控制
```

## 参考资料

- MySQL: [GROUP_CONCAT](https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html#function_group-concat)
- PostgreSQL: [STRING_AGG](https://www.postgresql.org/docs/current/functions-aggregate.html)
- SQL Server: [STRING_AGG](https://learn.microsoft.com/en-us/sql/t-sql/functions/string-agg-transact-sql)
- Oracle: [LISTAGG](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/LISTAGG.html)
- SQL:2016 标准: ISO/IEC 9075-2:2016, Section 10.9 (aggregate function - LISTAGG)

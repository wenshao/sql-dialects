# FETCH FIRST WITH TIES

Top-N 查询的并列值处理——SQL:2008 标准的贴心补充，解决了 LIMIT 截断同分记录的尴尬。

## 支持矩阵

| 引擎 | FETCH FIRST N ROWS | WITH TIES | PERCENT | 版本 |
|------|-------------------|-----------|---------|------|
| Oracle | 支持 | 支持 | 支持 | 12c+ (2013) |
| PostgreSQL | 支持 | 支持 | 不支持 | 13+ (2020) |
| SQL Server | 支持（TOP 语法） | 支持 | 支持 | 2012+ |
| DuckDB | 支持 | 支持 | 不支持 | 0.3.0+ |
| MariaDB | 支持 | 支持 | 不支持 | 10.6+ |
| Db2 | 支持 | 支持 | 支持 | 9.7+ |
| H2 | 支持 | 支持 | 不支持 | 2.0+ |
| CockroachDB | 支持 | 支持 | 不支持 | 22.1+ |
| MySQL | 不支持 | 不支持 | 不支持 | 仅有 LIMIT（无 FETCH 语法） |
| ClickHouse | 不支持 | 不支持 | 不支持 | 仅有 LIMIT |
| Snowflake | 不支持 | 不支持 | 不支持 | 仅有 LIMIT（TOP N 无 WITH TIES） |
| BigQuery | 不支持 | 不支持 | 不支持 | 仅有 LIMIT |
| Trino | 支持 | 支持 | 不支持 | 早期版本 |
| Spark SQL | 不支持 | 不支持 | 不支持 | 仅有 LIMIT |
| SQLite | 不支持 | 不支持 | 不支持 | 仅有 LIMIT |

## 设计动机: LIMIT 的并列截断问题

### 经典问题

考试成绩排名，需要取前 3 名：

```
| student | score |
|---------|-------|
| 张三    | 95    |
| 李四    | 90    |
| 王五    | 88    |
| 赵六    | 88    |  ← 与王五同分！
| 钱七    | 85    |
```

```sql
-- LIMIT 3: 任意截断
SELECT student, score FROM exam_scores ORDER BY score DESC LIMIT 3;
-- 结果可能是:
-- 张三 95, 李四 90, 王五 88    ← 赵六被截掉了（不公平！）
-- 或者:
-- 张三 95, 李四 90, 赵六 88    ← 王五被截掉了（也不公平！）
-- 具体返回谁取决于内部排序的稳定性——不确定行为
```

这在业务中是严重的正确性问题——同分的考生不应该被随机排除。

### WITH TIES 的解决方案

```sql
-- WITH TIES: 包含所有并列记录
SELECT student, score FROM exam_scores
ORDER BY score DESC
FETCH FIRST 3 ROWS WITH TIES;
-- 结果（确定性的）:
-- 张三 95
-- 李四 90
-- 王五 88
-- 赵六 88    ← 并列第 3，一并返回
-- 共 4 行（不是严格的 3 行）
```

关键语义：WITH TIES 保证**不遗漏与最后一行 ORDER BY 值相同的行**，即使实际返回行数超过 N。

## SQL:2008 标准语法

```sql
-- 完整 FETCH 语法
SELECT ...
FROM ...
ORDER BY ...
OFFSET n { ROW | ROWS }
FETCH { FIRST | NEXT } n { ROW | ROWS } { ONLY | WITH TIES }
```

关键组件：

| 子句 | 说明 | 示例 |
|------|------|------|
| `OFFSET n ROWS` | 跳过前 n 行 | `OFFSET 10 ROWS` |
| `FETCH FIRST n ROWS ONLY` | 取前 n 行（等价于 LIMIT n） | `FETCH FIRST 10 ROWS ONLY` |
| `FETCH FIRST n ROWS WITH TIES` | 取前 n 行，包含并列 | `FETCH FIRST 3 ROWS WITH TIES` |
| `FETCH FIRST n PERCENT ROWS ONLY` | 取前 n% 的行 | `FETCH FIRST 10 PERCENT ROWS ONLY` |
| `FIRST` vs `NEXT` | 语义相同，纯粹语法糖 | `FETCH NEXT 5 ROWS ONLY` |
| `ROW` vs `ROWS` | 语义相同，单复数语法糖 | `FETCH FIRST 1 ROW ONLY` |

### 重要约束

```sql
-- WITH TIES 必须搭配 ORDER BY
-- 原因: 没有排序就没有"并列"的概念
SELECT * FROM t FETCH FIRST 3 ROWS WITH TIES;  -- 错误或未定义行为

-- 正确写法
SELECT * FROM t ORDER BY score DESC FETCH FIRST 3 ROWS WITH TIES;
```

## 语法对比

### Oracle 12c+

```sql
-- Oracle 12c 引入 FETCH FIRST（之前只有 ROWNUM）
SELECT student, score
FROM exam_scores
ORDER BY score DESC
FETCH FIRST 3 ROWS WITH TIES;

-- PERCENT 选项
SELECT student, score
FROM exam_scores
ORDER BY score DESC
FETCH FIRST 10 PERCENT ROWS ONLY;

-- 与 OFFSET 组合
SELECT student, score
FROM exam_scores
ORDER BY score DESC
OFFSET 5 ROWS
FETCH NEXT 3 ROWS WITH TIES;
```

### PostgreSQL 13+

```sql
-- PostgreSQL 13 增加 WITH TIES 支持
SELECT student, score
FROM exam_scores
ORDER BY score DESC
FETCH FIRST 3 ROWS WITH TIES;

-- PostgreSQL 不支持 PERCENT
-- FETCH FIRST 10 PERCENT ROWS ONLY;  ← 语法错误

-- LIMIT 语法不支持 WITH TIES（只有 FETCH 语法支持）
-- LIMIT 3 WITH TIES;  ← 语法错误
```

### SQL Server（TOP WITH TIES —— 最早的实现）

```sql
-- SQL Server 使用 TOP ... WITH TIES（早于 SQL:2008 标准）
SELECT TOP 3 WITH TIES student, score
FROM exam_scores
ORDER BY score DESC;

-- TOP PERCENT
SELECT TOP 10 PERCENT student, score
FROM exam_scores
ORDER BY score DESC;

-- TOP PERCENT WITH TIES
SELECT TOP 10 PERCENT WITH TIES student, score
FROM exam_scores
ORDER BY score DESC;

-- SQL Server 2012+ 也支持 FETCH 语法
SELECT student, score
FROM exam_scores
ORDER BY score DESC
OFFSET 0 ROWS
FETCH NEXT 3 ROWS WITH TIES;
-- 注意: SQL Server 的 FETCH 必须搭配 OFFSET（即使 OFFSET 0）
```

### DuckDB

```sql
-- DuckDB 支持标准 FETCH 语法
SELECT student, score
FROM exam_scores
ORDER BY score DESC
FETCH FIRST 3 ROWS WITH TIES;

-- 也支持 LIMIT（但 LIMIT 不支持 WITH TIES）
SELECT student, score
FROM exam_scores
ORDER BY score DESC
LIMIT 3;  -- 无 WITH TIES
```

### MariaDB 10.6+

```sql
-- MariaDB 支持标准 FETCH 语法
SELECT student, score
FROM exam_scores
ORDER BY score DESC
FETCH FIRST 3 ROWS WITH TIES;

-- MySQL 不支持（需要窗口函数替代）
```

### 等价改写: 不支持 WITH TIES 的引擎

#### MySQL / ClickHouse / BigQuery / Snowflake / Spark SQL

```sql
-- 方案 1: DENSE_RANK 窗口函数（最精确的等价）
SELECT student, score
FROM (
    SELECT student, score,
           DENSE_RANK() OVER (ORDER BY score DESC) AS dr
    FROM exam_scores
) t
WHERE dr <= 3;

-- 方案 2: 自连接（仅适用于简单场景）
SELECT e.student, e.score
FROM exam_scores e
WHERE e.score >= (
    SELECT MIN(sub.score) FROM (
        SELECT DISTINCT score FROM exam_scores ORDER BY score DESC LIMIT 3
    ) sub
)
ORDER BY e.score DESC;
```

注意 DENSE_RANK vs RANK 的区别：

```sql
-- 数据: 95, 90, 88, 88, 85
-- DENSE_RANK: 1, 2, 3, 3, 4  ← "取前 3 名" 的正确语义
-- RANK:       1, 2, 3, 3, 5  ← "取前 3 位" 的正确语义
-- ROW_NUMBER: 1, 2, 3, 4, 5  ← "取前 3 行" 的语义（等价于 LIMIT）

-- WITH TIES 的语义与 DENSE_RANK 一致:
-- "取 ORDER BY 值排在前 3 的所有行"
```

## 实际用例

### 用例 1: 成绩排名（包含并列）

```sql
-- 奖学金发放: 前 10 名都有奖学金，同分都算
SELECT student_name, total_score
FROM final_grades
ORDER BY total_score DESC
FETCH FIRST 10 ROWS WITH TIES;
```

### 用例 2: 销售排行榜

```sql
-- 每个区域销量前 5 的产品（含并列）
SELECT region, product, sales_amount
FROM (
    SELECT region, product, sales_amount,
           DENSE_RANK() OVER (PARTITION BY region ORDER BY sales_amount DESC) AS dr
    FROM monthly_sales
) t
WHERE dr <= 5;
-- WITH TIES 不支持 PARTITION BY，需要窗口函数方案
```

### 用例 3: 取前 10% 的样本

```sql
-- Oracle / SQL Server: 取收入最高的 10% 客户
SELECT customer_id, revenue
FROM customers
ORDER BY revenue DESC
FETCH FIRST 10 PERCENT ROWS ONLY;
```

### 用例 4: 分页中的并列安全

```sql
-- 第 2 页，每页 20 条，保留并列
SELECT *
FROM products
ORDER BY price ASC
OFFSET 20 ROWS
FETCH NEXT 20 ROWS WITH TIES;
-- 注意: WITH TIES 在分页中需要谨慎使用
-- 可能导致页面行数不固定，前端需要处理
```

## 对引擎开发者的实现分析

1. 排序后的 Peek-Ahead 逻辑

WITH TIES 的核心实现是在达到 N 行限制后，继续"偷看"后续行是否与第 N 行的 ORDER BY 值相同：

```
算法: FETCH FIRST N ROWS WITH TIES

输入: 已排序的行流
状态: count = 0, last_order_values = null

while (row = next_row()):
    if count < N:
        emit(row)
        count++
        last_order_values = extract_order_values(row)
    else:
        current_values = extract_order_values(row)
        if current_values == last_order_values:
            emit(row)  // 并列行，继续输出
            // count 不增加（或不检查 count）
        else:
            break  // 不再并列，停止
```

关键点：
- 比较的是 ORDER BY 子句中指定的列的值，不是整行
- 如果 ORDER BY 有多个列，所有列都必须相同才算并列
- NULL 的比较行为遵循 ORDER BY 的 NULLS FIRST/LAST 规则

2. 执行计划

```
TableScan → Sort(ORDER BY score DESC) → LimitWithTies(N=3) → Project

LimitWithTies 算子:
- 与普通 Limit 的区别: 不是固定输出 N 行，而是至少 N 行
- 需要持有排序列的值进行比较
- 下游算子（如 OFFSET）需要在 LimitWithTies 之后
```

3. OFFSET + WITH TIES 的语义

```sql
OFFSET 5 ROWS FETCH NEXT 3 ROWS WITH TIES
```

执行顺序：
1. 排序
2. 跳过前 5 行
3. 从第 6 行开始，取 3 行 + 并列行

注意：OFFSET 跳过时**不考虑并列**——如果第 5 行和第 6 行同分，第 5 行仍被跳过。

4. PERCENT 的实现

```sql
FETCH FIRST 10 PERCENT ROWS ONLY
```

实现挑战：需要知道总行数才能计算 10% 是多少行。

```
方案 1: 两遍扫描
  第一遍: COUNT(*) → total
  第二遍: FETCH FIRST (total * 0.1) ROWS

方案 2: 物化排序结果
  排序后全部物化到内存/磁盘
  计算 N = total * percent
  输出前 N 行

方案 3: 估算优化
  使用统计信息估算 total
  计算 N = estimated_total * percent
  流式输出前 N 行（可能不精确）
```

多数引擎使用方案 2，因为排序本身就需要物化。

5. WITH TIES + PERCENT 组合

```sql
FETCH FIRST 10 PERCENT ROWS WITH TIES
```

SQL Server 支持这种组合。语义是：
1. 计算 10% 对应的行数 N
2. 取前 N 行
3. 如果第 N 行有并列，继续输出

6. 优化机会

```
普通 LIMIT N: 排序算法可以使用 Top-N 排序（堆排序），O(N) 空间
WITH TIES:   无法使用 Top-N 优化——不知道最终会输出多少行

但可以做部分优化:
1. 先执行 Top-(N+buffer) 排序（多取一些行）
2. 检查第 N 行的值
3. 如果后续有并列行超出 buffer，回退到完整排序

实践中，并列行通常不多，Top-(N+100) 的 buffer 足够应对大多数情况。
```

## FETCH vs LIMIT: 标准与实践

```sql
-- SQL:2008 标准语法（推荐跨引擎使用）
SELECT * FROM t ORDER BY id OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY;

-- MySQL / PostgreSQL / ClickHouse / SQLite 通用语法（事实标准）
SELECT * FROM t ORDER BY id LIMIT 5 OFFSET 10;

-- SQL Server 独有语法
SELECT TOP 5 * FROM t ORDER BY id;
```

| 特性 | FETCH (标准) | LIMIT (事实标准) | TOP (SQL Server) |
|------|-------------|-----------------|-----------------|
| ONLY (普通截断) | 支持 | 支持 | 支持 |
| WITH TIES | 支持 | 不支持 | 支持 |
| PERCENT | 支持 | 不支持 | 支持 |
| OFFSET | 支持 | 支持 | 不支持（用 OFFSET FETCH） |

LIMIT 虽然更流行，但 FETCH 提供了更完整的功能集。建议在需要 WITH TIES 或 PERCENT 时使用 FETCH 语法。

## 设计讨论

### WITH TIES 在分页中的问题

WITH TIES 在分页场景中需要特别注意：

```sql
-- 第 1 页: FETCH FIRST 10 ROWS WITH TIES → 可能返回 12 行
-- 第 2 页: OFFSET 10 FETCH NEXT 10 WITH TIES → 可能遗漏行！
-- 因为第 1 页多返回的 2 行已经在 OFFSET 10 的范围之外
```

解决方案：分页时使用 ONLY（不用 WITH TIES），仅在需要完整排名结果时使用 WITH TIES。

### 为什么 MySQL 不实现？

MySQL 的 LIMIT 语法深入人心，社区没有强烈需求切换到 FETCH 语法。WITH TIES 可以用窗口函数 `DENSE_RANK` 替代（MySQL 8.0+ 支持窗口函数）。优先级排在其他特性之后。

## 参考资料

- ISO/IEC 9075-2:2008 Section 7.17 (query expression - FETCH clause)
- Oracle: [Row Limiting Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- PostgreSQL 13: [FETCH WITH TIES](https://www.postgresql.org/docs/13/sql-select.html#SQL-LIMIT)
- SQL Server: [TOP WITH TIES](https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql)
- DuckDB: [FETCH clause](https://duckdb.org/docs/sql/query_syntax/limit)

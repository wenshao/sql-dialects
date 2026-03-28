# Azure Synapse Analytics: 分页 (Pagination)

T-SQL 语法（SQL Server 兼容）。

参考资料:
[1] Synapse SQL 开发概述 - T-SQL 功能
https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
[2] Synapse Dedicated SQL Pool - Performance Guidance
https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/best-practices-dedicated-sql-pool
[3] T-SQL Reference - OFFSET FETCH
https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql
[4] T-SQL Reference - TOP
https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql

## 1. OFFSET / FETCH（T-SQL 2012+ 标准语法，推荐）


基本分页: 跳过前 20 行，取 10 行
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```


注意: OFFSET / FETCH 必须与 ORDER BY 一起使用（强制排序）

仅取前 N 行（无跳过）
```sql
SELECT * FROM users ORDER BY id OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```


FETCH FIRST（等价于 FETCH NEXT）
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```


## 2. TOP 语法（所有版本，不支持跳过）


TOP N（取前 N 行，不支持 OFFSET）
```sql
SELECT TOP 10 * FROM users ORDER BY id;
```


TOP WITH TIES（包含并列行）
```sql
SELECT TOP 10 WITH TIES * FROM users ORDER BY age;
-- 如果第 10 名和第 11 名 age 相同，第 11 名也包含在结果中
```


TOP PERCENT（取前 N% 的行）
```sql
SELECT TOP 10 PERCENT * FROM users ORDER BY age;
```


注意: TOP 不需要 ORDER BY（但结果不确定，不推荐）

## 3. OFFSET 的性能问题（MPP 架构特殊考量）


Synapse Dedicated SQL Pool (MPP 架构):
数据分布在 60 个分布 (Distribution) 中
OFFSET 100000 需要:
每个 Distribution 返回 100010 行到 Compute 节点
Compute 节点全局排序后跳过 100000 行
数据移动 (Data Movement) 开销: 60 * (offset + limit) 行

Synapse Serverless SQL Pool:
按需查询，无预分配资源
OFFSET 性能取决于数据存储格式（Parquet、CSV 等）
支持结果缓存（对重复分页查询有帮助）

## 4. 键集分页（Keyset Pagination）: 高性能替代方案


第一页（使用 TOP）
```sql
SELECT TOP 10 * FROM users ORDER BY id;
```


后续页（已知上一页最后一条 id = 100）
```sql
SELECT TOP 10 * FROM users WHERE id > 100 ORDER BY id;
-- 时间复杂度: O(log n + limit)，与页码无关
```


多列排序的键集分页
```sql
SELECT TOP 10 * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id;
```


## 5. 窗口函数辅助分页


ROW_NUMBER 分页（推荐在 Synapse 中使用）
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE t.rn BETWEEN 21 AND 30;
```


CTE + ROW_NUMBER（更易读）
```sql
WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;
```


分组后 Top-N
```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```


## 6. Synapse 特有说明


Synapse 的分页特性:
OFFSET / FETCH:  支持（需要 ORDER BY）
TOP:             支持（不需要 ORDER BY，但不推荐无 ORDER BY）
TOP WITH TIES:   支持
LIMIT:           不支持（非 T-SQL 语法）
FETCH FIRST:     不支持（仅支持 FETCH NEXT）

Dedicated SQL Pool 的分布策略对分页的影响:
Hash 分布:  如果排序键是分布键，查询只在目标 Distribution 上执行
Round-Robin: 所有 Distribution 都参与查询
Replicated:  每个 Compute 节点有完整数据，本地排序
推荐: 将常用的分页排序键设为 Hash 分布键

性能优化建议:
使用 Columnstore Index 提升扫描性能
利用 Result Cache（重复查询自动缓存）
避免在大结果集上使用 OFFSET（改用键集分页）

## 7. 版本演进

SQL Server 2008:  TOP + ROWNUM（传统分页方式）
SQL Server 2012:  OFFSET / FETCH 语法
Synapse (初始):   TOP + OFFSET / FETCH（兼容 T-SQL）
Synapse Serverless: 结果缓存 + Parquet 优化

## 8. 横向对比: 分页语法差异


语法对比:
Synapse:     OFFSET-FETCH + TOP（T-SQL 兼容）
SQL Server:  OFFSET-FETCH + TOP（Synapse 的上游）
Oracle:      FETCH FIRST (12c+) / ROWNUM
PostgreSQL:  LIMIT / OFFSET + FETCH FIRST

MPP 引擎分页对比:
Synapse Dedicated:  60 个 Distribution，数据移动开销大
Redshift:           类似 MPP，支持 LIMIT OFFSET（非标准）
BigQuery:           无缓存，全量扫描计费，分页成本高
Snowflake:          微分区裁剪 + 弹性 Warehouse

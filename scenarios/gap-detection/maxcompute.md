# MaxCompute (ODPS): 间隙检测与岛屿问题

> 参考资料:
> - [1] MaxCompute Documentation - Window Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/window-functions


## 1. 数值间隙检测（LAG/LEAD 方法）


```sql
CREATE TABLE IF NOT EXISTS orders (id BIGINT, info STRING);

SELECT id AS gap_start_after,
       next_id AS gap_end_before,
       next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id, 1) OVER (ORDER BY id) AS next_id
    FROM orders
) t
WHERE next_id - id > 1;

```

## 2. 日期间隙检测


```sql
SELECT sale_date, next_date,
       DATEDIFF(TO_DATE(next_date, 'yyyy-MM-dd'),
                TO_DATE(sale_date, 'yyyy-MM-dd'), 'dd') - 1 AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date, 1) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t
WHERE DATEDIFF(TO_DATE(next_date, 'yyyy-MM-dd'),
               TO_DATE(sale_date, 'yyyy-MM-dd'), 'dd') > 1;

```

## 3. 岛屿问题（连续序列识别）


核心技巧: id - ROW_NUMBER() = 常量（对于连续值）

```sql
SELECT MIN(id) AS island_start,
       MAX(id) AS island_end,
       COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
) t
GROUP BY grp
ORDER BY island_start;

```

 原理:
   id: 1, 2, 3, 5, 6, 10, 11, 12
   rn: 1, 2, 3, 4, 5,  6,  7,  8
   差: 0, 0, 0, 1, 1,  4,  4,  4
   连续值的差相同 → 分组后 MIN/MAX = 岛屿边界

## 4. 综合: 岛屿 + 间隙


```sql
WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id, 1) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id IS NOT NULL AND next_id - id > 1
ORDER BY range_start;

```

## 5. 使用 posexplode 生成缺失值序列


```sql
SELECT pos + (SELECT MIN(id) FROM orders) AS missing_id
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(
    CAST((SELECT MAX(id) - MIN(id) FROM orders) AS BIGINT)
), ' ')) t AS pos, val
WHERE pos + (SELECT MIN(id) FROM orders) NOT IN (SELECT id FROM orders);

```

## 6. 横向对比与引擎开发者启示


 对比:
   MaxCompute: LAG/LEAD + ROW_NUMBER（标准窗口函数方案）
   PostgreSQL: 相同方案 + generate_series 辅助
   BigQuery:   相同方案
   MySQL 8.0+: 相同方案（窗口函数支持后）

 对引擎开发者:
1. 窗口函数是间隙/岛屿问题的最佳工具 — 必须完整支持

2. generate_series 辅助函数简化了缺失值列举 — 值得内置

3. id - ROW_NUMBER() 分组技巧依赖窗口函数的确定性排序

4. 日期间隙检测在数据质量监控中使用频率极高


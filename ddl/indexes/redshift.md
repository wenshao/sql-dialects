# Redshift: 索引

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


Redshift 不支持传统索引（没有 B-tree、Hash、GIN 等）
查询优化通过区域映射（Zone Maps）和排序键实现

## 区域映射（Zone Maps）—— 自动维护，不可手动创建

Redshift 自动为每个列的每个 1MB 数据块记录 min/max 值
查询时自动跳过不包含目标数据的块（块剪裁）
Zone Maps 对排序键列效果最好

## 排序键（SORTKEY）—— 最重要的查询优化手段


复合排序键（Compound，默认）
按声明顺序排列，最左前缀匹配
```sql
CREATE TABLE orders (
    id         BIGINT IDENTITY(1, 1),
    user_id    BIGINT,
    amount     DECIMAL(10, 2),
    order_date DATE
)
SORTKEY (order_date, user_id);
```

对 WHERE order_date = ... 和 WHERE order_date = ... AND user_id = ... 有效
对 WHERE user_id = ... 无效（不是最左前缀）

交错排序键（Interleaved）
多列等权排列，适合多个列都做过滤
```sql
CREATE TABLE search_log (
    id         BIGINT IDENTITY(1, 1),
    category   VARCHAR(50),
    region     VARCHAR(50),
    created_at DATE
)
INTERLEAVED SORTKEY (category, region, created_at);
```

对任意列的过滤都有效
- **缺点：VACUUM 成本更高，不适合经常加载数据的表**

AUTO SORTKEY（Redshift 自动选择排序键）
```sql
CREATE TABLE auto_table (
    id BIGINT IDENTITY(1, 1),
    data VARCHAR(256)
)
SORTKEY AUTO;
```


修改排序键
```sql
ALTER TABLE orders ALTER SORTKEY (order_date);
ALTER TABLE orders ALTER SORTKEY AUTO;
ALTER TABLE orders ALTER SORTKEY NONE;
```


## 分布键（DISTKEY）—— 优化 JOIN 性能

相同 DISTKEY 值的行在同一切片，JOIN 时避免数据重分布

```sql
CREATE TABLE users (
    id BIGINT IDENTITY(1, 1),
    username VARCHAR(64)
)
DISTSTYLE KEY DISTKEY (id);

CREATE TABLE orders (
    id BIGINT IDENTITY(1, 1),
    user_id BIGINT
)
DISTSTYLE KEY DISTKEY (user_id);
```


users.id 和 orders.user_id 在同一切片 → JOIN 无需数据移动

修改分布键
```sql
ALTER TABLE orders ALTER DISTKEY user_id;
ALTER TABLE orders ALTER DISTSTYLE EVEN;
ALTER TABLE orders ALTER DISTSTYLE ALL;
ALTER TABLE orders ALTER DISTSTYLE AUTO;
```


## 物化视图（Materialized View）

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
GROUP BY order_date;
```


刷新物化视图
```sql
REFRESH MATERIALIZED VIEW mv_daily_sales;
```


自动刷新
```sql
CREATE MATERIALIZED VIEW mv_auto_refresh
AUTO REFRESH YES AS
SELECT order_date, SUM(amount) AS total
FROM orders
GROUP BY order_date;
```


## VACUUM（排序键维护）

新加载的数据不是排序的，需要 VACUUM 重排

```sql
VACUUM orders;                              -- 完整 VACUUM
VACUUM SORT ONLY orders;                    -- 只重排序
VACUUM DELETE ONLY orders;                  -- 只回收删除空间
VACUUM REINDEX orders;                      -- 重建交错排序键
```


## ANALYZE（统计信息更新）

```sql
ANALYZE orders;
ANALYZE orders PREDICATE COLUMNS;           -- 只分析最近查询用到的列
```


## 查看排序和分布信息

```sql
SELECT "table", diststyle, sortkey1, sortkey_num
FROM svv_table_info
WHERE "table" = 'orders';
```


查看表的设计建议
```sql
SELECT * FROM svv_alter_table_recommendations;
```


注意：Redshift 没有任何传统索引
注意：排序键 + 区域映射是主要的查询优化机制
注意：DISTKEY 优化 JOIN，SORTKEY 优化过滤和范围查询
注意：交错排序键 VACUUM 成本高，建议大表慎用
注意：AUTO SORTKEY / AUTO DISTKEY 让 Redshift 自动选择（推荐）

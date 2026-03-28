# Materialize: 条件函数 (Conditional Functions)

> 参考资料:
> - [Materialize Documentation - Scalar Functions](https://materialize.com/docs/sql/functions/)
> - [Materialize Documentation - Types and Casting](https://materialize.com/docs/sql/types/)
> - [Materialize Documentation - SELECT Statement](https://materialize.com/docs/sql/select/)
> - 说明: Materialize 基于 PostgreSQL 语法，条件函数与 PostgreSQL 高度兼容。
> - 部分高级条件表达式在流式计算场景中有特殊语义。
> - ============================================================
> - 1. CASE WHEN: 标准条件表达式
> - ============================================================
> - 搜索式 CASE WHEN

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_category
FROM users;
```

## 简单 CASE 表达式

```sql
SELECT username,
    CASE status
        WHEN 'active' THEN 1
        WHEN 'inactive' THEN 0
        ELSE -1
    END AS status_code
FROM users;
```

## CASE 在聚合中的应用

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE CASE WHEN age >= 18 THEN 1 END IS NOT NULL) AS adults
FROM users;
```

## COALESCE: NULL 处理


## 返回第一个非 NULL 参数

```sql
SELECT COALESCE(phone, email, 'no-contact') AS contact FROM users;
```

## COALESCE 与计算列配合

```sql
SELECT COALESCE(discount, 0) * price AS final_price FROM products;
```

## COALESCE 类型推断: 所有参数必须是兼容类型

COALESCE(1, 'hello') → 类型错误! 需要统一类型:

```sql
SELECT COALESCE(CAST(1 AS TEXT), 'hello');
```

## NULLIF: 条件 NULL 化


## 两个参数相等则返回 NULL，否则返回第一个参数

```sql
SELECT NULLIF(age, 0) AS safe_age FROM users;        -- age=0 → NULL
SELECT NULLIF(status, '') AS non_empty_status FROM orders;
```

## 防止除零错误

```sql
SELECT total / NULLIF(count, 0) AS avg_value FROM metrics;
```

## GREATEST / LEAST: 多值比较


## 返回参数列表中的最大/最小值

```sql
SELECT GREATEST(score1, score2, score3) AS best_score FROM results;
SELECT LEAST(score1, score2, score3) AS worst_score FROM results;
```

## 用于边界约束

```sql
SELECT GREATEST(0, LEAST(100, score)) AS clamped_score FROM exams;
```

## NULL 语义: 任一参数为 NULL → 结果为 NULL

```sql
SELECT GREATEST(10, NULL, 20);                        -- NULL
```

## 类型转换: CAST 与 ::


## 标准 CAST

```sql
SELECT CAST('123' AS INTEGER);                        -- 123
SELECT CAST('3.14' AS DOUBLE PRECISION);              -- 3.14
SELECT CAST(age AS TEXT) FROM users;
```

## PostgreSQL 风格 :: 简写

```sql
SELECT '123'::INTEGER;                                -- 123
SELECT '2024-01-15'::DATE;                            -- 2024-01-15
SELECT 'true'::BOOLEAN;                               -- true
```

## 安全转换: TRY_CAST (Materialize 特有)

```sql
SELECT CASE
    WHEN CAST(x AS TEXT) ~ '^\d+$' THEN CAST(x AS INTEGER)
    ELSE NULL
END AS safe_int FROM raw_data;
```

## FILTER 子句: 条件聚合


## FILTER 是 PostgreSQL 风格的条件聚合（SQL:2003 标准）

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age > 30) AS over_30,
    COUNT(*) FILTER (WHERE age <= 30) AS under_30,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_total
FROM orders;
```

FILTER 与 CASE WHEN 的等价关系:
COUNT(*) FILTER (WHERE age > 30)
等价于: SUM(CASE WHEN age > 30 THEN 1 ELSE 0 END)

## 布尔表达式与逻辑函数


## Materialize 支持 BOOLEAN 类型

```sql
SELECT username, age > 18 AS is_adult FROM users;
SELECT username, active AND verified AS is_valid FROM users;
```

## IS DISTINCT FROM: NULL 安全的比较

```sql
SELECT a IS DISTINCT FROM b FROM pairs;               -- NULL ≠ NULL 时返回 FALSE
```

## 物化视图中的条件表达式


## 条件函数在物化视图中可增量维护

```sql
CREATE MATERIALIZED VIEW user_categories AS
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category,
    COALESCE(phone, 'N/A') AS contact
FROM users;
```

## 注意: CASE/COALESCE/NULLIF 的变更可在增量更新中高效计算

## 横向对比: Materialize vs PostgreSQL


功能对比:
CASE WHEN:         Materialize ✓    PostgreSQL ✓
COALESCE:          Materialize ✓    PostgreSQL ✓
NULLIF:            Materialize ✓    PostgreSQL ✓
GREATEST/LEAST:    Materialize ✓    PostgreSQL ✓
FILTER 子句:       Materialize ✓    PostgreSQL ✓
:: 类型转换:       Materialize ✓    PostgreSQL ✓
DECODE (Oracle):   Materialize ✗    PostgreSQL ✗
IIF (SQL Server):  Materialize ✗    PostgreSQL ✗
NVL (Oracle):      Materialize ✗    PostgreSQL ✗
IFNULL (MySQL):    Materialize ✗    PostgreSQL ✗
Materialize 独有特性:
物化视图中条件表达式的增量维护
实时流处理中的条件求值（NOT NULL 约束在 source 层）
mz_now() 函数可在条件中使用（基于系统时钟）

## 版本演进与注意事项

Materialize 0.x: 基础条件函数（CASE/COALESCE/NULLIF）
Materialize 0.7+: FILTER 子句支持
Materialize 0.9+: 完整类型转换支持（:: 和 CAST）
注意事项:
1. 条件函数与 PostgreSQL 语法完全兼容
2. FILTER 子句在聚合中非常高效（增量维护）
3. COALESCE 的所有参数必须类型兼容
4. 不支持 Oracle/MySQL 专有条件函数（DECODE/IF/IFNULL/NVL）
5. 在物化视图中使用条件函数，数据变更会触发增量更新

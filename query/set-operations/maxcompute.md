# MaxCompute (ODPS): 集合操作

> 参考资料:
> - [1] MaxCompute Documentation - UNION
>   https://help.aliyun.com/zh/maxcompute/user-guide/union
> - [2] MaxCompute Documentation - SELECT
>   https://help.aliyun.com/zh/maxcompute/user-guide/select-syntax


## 1. UNION ALL（所有版本支持）


```sql
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

```

 UNION ALL 不去重，保留所有行
 性能最好: 简单地合并两个结果集，无需排序或哈希去重

 设计分析: UNION ALL 在 MaxCompute 中的执行
   伏羲调度: 两个子查询并行执行，结果直接拼接
   无 Shuffle: 不需要数据重分布（与 JOIN 不同）
   最常用场景: 多路输出的逆操作 — 合并多个分区/表的数据

## 2. UNION / UNION DISTINCT（2.0+）


```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

```

 UNION = UNION DISTINCT（去重）
 实现: 合并后做全局去重（Hash 或 Sort 去重）
 性能开销: 需要对全部数据做去重 — 大数据量下开销很大

 设计分析: 1.0 为什么只支持 UNION ALL?
   UNION ALL 是纯追加操作，不需要额外计算
   UNION DISTINCT 需要去重 = 额外的 Shuffle + Hash/Sort 阶段
### 1.0 的极简设计: 只提供最基本的操作，让用户自行去重

### 2.0 补充: 为标准 SQL 兼容性加入 UNION DISTINCT


## 3. INTERSECT（2.0+）


```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

```

INTERSECT ALL（保留重复）

```sql
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

```

 INTERSECT 的实现: 类似 INNER JOIN + DISTINCT
 伏羲执行: 两个结果集按所有列做 Hash Shuffle → 在 Reducer 中找交集

## 4. EXCEPT / MINUS（2.0+）


```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

```

MINUS 是 EXCEPT 的别名（Oracle 兼容）

```sql
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

```

EXCEPT ALL

```sql
SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

```

 设计分析: MINUS vs EXCEPT
   SQL 标准: EXCEPT（SQL:1992）
   Oracle:   MINUS（Oracle 特有关键字）
   MaxCompute 同时支持两者 — 这是对 Oracle 生态迁移的友好设计
   对比:
     PostgreSQL: EXCEPT（遵循标准）
     MySQL 8.0.31+: EXCEPT（遵循标准，不支持 MINUS）
     BigQuery:   EXCEPT DISTINCT（默认去重）

## 5. 组合与嵌套


使用括号控制优先级

```sql
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

```

ORDER BY 应用于整个结果

```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

```

LIMIT 应用于整个结果

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

```

## 6. 集合操作在 ETL 中的应用


增量合并: UNION ALL + ROW_NUMBER 去重

```sql
INSERT OVERWRITE TABLE users
SELECT id, username, email, age FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM (
        SELECT *, updated_at FROM new_users
        UNION ALL
        SELECT *, updated_at FROM users
    ) combined
) ranked WHERE rn = 1;

```

数据对比: EXCEPT 找出差异

```sql
SELECT id FROM table_a
EXCEPT
SELECT id FROM table_b;
```

 返回在 table_a 中但不在 table_b 中的 id

## 7. 版本演进


 MaxCompute 1.0: 仅 UNION ALL
 MaxCompute 2.0: UNION DISTINCT, INTERSECT, EXCEPT/MINUS, ALL 变体
 对比:
   MySQL:  8.0.31+ 才支持 INTERSECT/EXCEPT（长期只有 UNION）
   PostgreSQL: 从最早期就支持所有集合操作
   Hive: 2.0+ 支持 INTERSECT/EXCEPT

## 8. 横向对比: 集合操作


 UNION ALL:       所有引擎均支持
 UNION DISTINCT:  所有现代引擎均支持
INTERSECT:       MaxCompute 2.0+ | MySQL 8.0.31+ | PostgreSQL: 支持
EXCEPT:          MaxCompute 2.0+ | MySQL 8.0.31+ | PostgreSQL: 支持
MINUS:           MaxCompute 支持  | Oracle: 支持   | PostgreSQL: 不支持
INTERSECT ALL:   MaxCompute 2.0+ | PostgreSQL: 支持 | MySQL: 不支持
EXCEPT ALL:      MaxCompute 2.0+ | PostgreSQL: 支持 | MySQL: 不支持

 性能对比:
   UNION ALL: O(N+M) 无去重     — 最快
   UNION DISTINCT: O(N+M) 去重  — 需要 Hash/Sort
   INTERSECT: O(N+M) Hash Join  — 类似 INNER JOIN
   EXCEPT: O(N+M) Hash Anti     — 类似 LEFT ANTI JOIN

## 9. 对引擎开发者的启示


1. UNION ALL 应该是最基本的操作 — 零开销追加

2. 集合操作可以复用 JOIN 的基础设施（Hash/Sort）

3. MINUS/EXCEPT 双关键字支持有利于 Oracle 用户迁移

4. INTERSECT/EXCEPT ALL 使用频率低但标准兼容性要求支持

5. 大数据量下建议 UNION ALL + 手动去重 代替 UNION DISTINCT（更可控）

6. 集合操作的列数和类型匹配检查应在编译期完成


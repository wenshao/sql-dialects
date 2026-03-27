# SQL 中的 Lambda 表达式

在 SQL 中内联定义匿名函数——当数组/列表成为一等类型后，Lambda 是操作它们的必然需求，正在弥合 SQL 与函数式编程的鸿沟。

## 支持矩阵

| 引擎 | 支持 | 语法 | 备注 |
|------|------|------|------|
| ClickHouse | 完整支持 | `x -> x * 2` | 最早推广的引擎之一 |
| Trino | 完整支持 | `x -> x + 1` | 丰富的高阶函数库 |
| Spark SQL | 完整支持 | `x -> x + 1` | Databricks 同步支持 |
| DuckDB | 完整支持 | `x -> x * 2` | list_transform, list_filter 等 |
| Databricks | 完整支持 | `x -> x + 1` | 基于 Spark 引擎 |
| Flink SQL | 不支持 | - | 无 Lambda，用 UDF 替代 |
| BigQuery | 不支持 | - | 需 UNNEST + 子查询替代 |
| PostgreSQL | 不支持 | - | 需 UNNEST + 子查询替代 |
| MySQL | 不支持 | - | 无数组类型，不适用 |
| Oracle | 不支持 | - | 无 Lambda（有集合类型但用 PL/SQL 处理） |
| SQL Server | 不支持 | - | 无原生数组类型 |
| Snowflake | 不支持 | - | 需 FLATTEN + 子查询 |

## 设计动机: 数组操作的困境

### 问题场景

数据仓库中经常存储数组类型的列。对数组元素做变换、过滤、聚合是基本需求：

```
用户标签表:
| user_id | tags                           |
|---------|--------------------------------|
| 1       | ['python', 'sql', 'java']      |
| 2       | ['javascript', 'sql', 'react'] |
| 3       | ['python', 'ml', 'sql']        |

需求: 将所有标签转为大写 → ['PYTHON', 'SQL', 'JAVA']
需求: 只保留以 's' 开头的标签 → ['sql']
需求: 计算每个标签的长度 → [6, 3, 4]
```

### 传统 SQL 的处理方式

```sql
-- PostgreSQL: 需要 UNNEST → 处理 → ARRAY_AGG 三步
SELECT user_id,
    ARRAY_AGG(UPPER(tag))
FROM users, UNNEST(tags) AS tag
GROUP BY user_id;

-- BigQuery: 同样需要展开再聚合
SELECT user_id,
    ARRAY_AGG(UPPER(tag))
FROM users, UNNEST(tags) AS tag
GROUP BY user_id;

-- 问题:
-- 1. 需要 GROUP BY（打破了当前行的上下文）
-- 2. 如果 SELECT 中有其他列，GROUP BY 必须包含它们
-- 3. 多个数组列需要分别处理，无法在一个 SELECT 中同时变换
-- 4. 嵌套数组的处理极其复杂
```

### Lambda 的解决方案

```sql
-- ClickHouse / DuckDB / Trino: 一行搞定
SELECT user_id,
    arrayMap(x -> upper(x), tags) AS upper_tags,
    arrayFilter(x -> startsWith(x, 's'), tags) AS s_tags,
    arrayMap(x -> length(x), tags) AS tag_lengths
FROM users;

-- 无需 UNNEST，无需 GROUP BY，可以同时操作多个数组列
```

## 语法对比

### ClickHouse

```sql
-- 箭头函数语法: parameter -> expression
-- arrayMap: 对每个元素应用变换
SELECT arrayMap(x -> x * 2, [1, 2, 3, 4, 5]);
-- 结果: [2, 4, 6, 8, 10]

-- arrayFilter: 保留满足条件的元素
SELECT arrayFilter(x -> x > 3, [1, 2, 3, 4, 5]);
-- 结果: [4, 5]

-- arrayExists: 是否存在满足条件的元素
SELECT arrayExists(x -> x > 100, prices) FROM products;

-- arrayAll: 是否所有元素都满足条件
SELECT arrayAll(x -> x > 0, scores) AS all_positive FROM students;

-- arrayCount: 满足条件的元素个数
SELECT arrayCount(x -> x % 2 = 0, [1, 2, 3, 4, 5]);
-- 结果: 2

-- arraySort with Lambda: 自定义排序
SELECT arraySort((x, y) -> y - x, names, scores) AS sorted_by_score_desc;

-- 多参数 Lambda
SELECT arrayMap((x, y) -> x + y, [1, 2, 3], [10, 20, 30]);
-- 结果: [11, 22, 33]

-- 嵌套 Lambda
SELECT arrayMap(arr -> arrayMap(x -> x * 10, arr), [[1, 2], [3, 4]]);
-- 结果: [[10, 20], [30, 40]]
```

### Trino

```sql
-- transform: 等价于 map（避免与 MAP 类型冲突）
SELECT transform(ARRAY[1, 2, 3, 4, 5], x -> x * 2);
-- 结果: [2, 4, 6, 8, 10]

-- filter: 保留满足条件的元素
SELECT filter(ARRAY['apple', 'banana', 'avocado'], x -> x LIKE 'a%');
-- 结果: ['apple', 'avocado']

-- reduce: 折叠（最强大的操作）
SELECT reduce(ARRAY[1, 2, 3, 4, 5], 0, (acc, x) -> acc + x, acc -> acc);
-- 结果: 15（求和）

-- reduce 计算阶乘
SELECT reduce(ARRAY[1, 2, 3, 4, 5], 1, (acc, x) -> acc * x, acc -> acc);
-- 结果: 120

-- any_match / all_match / none_match
SELECT any_match(ARRAY[1, -2, 3], x -> x < 0);
-- 结果: true

-- zip_with: 两个数组元素配对处理
SELECT zip_with(ARRAY[1, 2, 3], ARRAY['a', 'b', 'c'], (x, y) -> CAST(x AS VARCHAR) || y);
-- 结果: ['1a', '2b', '3c']

-- transform_keys / transform_values: MAP 操作
SELECT transform_values(MAP(ARRAY['a','b'], ARRAY[1,2]), (k, v) -> v * 10);
-- 结果: {a=10, b=20}

-- 链式调用
SELECT
    reduce(
        filter(
            transform(scores, x -> x * 1.1),  -- 每分加 10%
            x -> x >= 60                        -- 过滤及格的
        ),
        0, (acc, x) -> acc + x, acc -> acc      -- 求和
    ) AS adjusted_passing_total
FROM students;
```

### DuckDB

```sql
-- list_transform: 对列表每个元素做变换
SELECT list_transform([1, 2, 3, 4], x -> x * x);
-- 结果: [1, 4, 9, 16]

-- list_filter: 过滤列表
SELECT list_filter(['hello', 'world', 'hi'], x -> len(x) > 3);
-- 结果: ['hello', 'world']

-- list_reduce: 折叠
SELECT list_reduce([1, 2, 3, 4], (acc, x) -> acc + x);
-- 结果: 10

-- list_apply: list_transform 的别名
SELECT list_apply([1, 2, 3], x -> x + 100);

-- 在列上使用
SELECT user_id,
    list_transform(tags, t -> upper(t)) AS upper_tags,
    list_filter(scores, s -> s >= 60) AS passing_scores,
    list_reduce(amounts, (a, b) -> a + b) AS total_amount
FROM users;
```

### Spark SQL / Databricks

```sql
-- transform: 数组元素变换
SELECT transform(array(1, 2, 3), x -> x + 1);
-- 结果: [2, 3, 4]

-- filter: 过滤
SELECT filter(array(1, 2, 3, 4, 5), x -> x % 2 = 0);
-- 结果: [2, 4]

-- aggregate: 折叠（比 Trino 的 reduce 功能更丰富）
SELECT aggregate(array(1, 2, 3), 0, (acc, x) -> acc + x);
-- 结果: 6

-- aggregate 带 finish 函数
SELECT aggregate(array(1, 2, 3), 0, (acc, x) -> acc + x, acc -> acc / 3);
-- 结果: 2（平均值）

-- exists: 是否存在
SELECT exists(array(1, 2, 3), x -> x > 2);
-- 结果: true

-- forall: 是否全部满足
SELECT forall(array(1, 2, 3), x -> x > 0);
-- 结果: true

-- zip_with
SELECT zip_with(array(1, 2), array(3, 4), (x, y) -> x + y);
-- 结果: [4, 6]

-- transform_keys / transform_values (MAP)
SELECT transform_values(map(1, 'a', 2, 'b'), (k, v) -> upper(v));
-- 结果: {1: 'A', 2: 'B'}
```

### 不支持 Lambda 的引擎: 替代方案

```sql
-- PostgreSQL: UNNEST + 子查询（最通用的替代方案）
SELECT user_id, (
    SELECT ARRAY_AGG(UPPER(t))
    FROM UNNEST(tags) AS t
) AS upper_tags
FROM users;

-- PostgreSQL: 多个数组同时处理需要多个子查询
SELECT user_id,
    (SELECT ARRAY_AGG(UPPER(t)) FROM UNNEST(tags) AS t) AS upper_tags,
    (SELECT ARRAY_AGG(t) FROM UNNEST(tags) AS t WHERE t LIKE 's%') AS s_tags
FROM users;

-- BigQuery: UNNEST + ARRAY 子查询
SELECT user_id,
    ARRAY(SELECT UPPER(t) FROM UNNEST(tags) AS t) AS upper_tags,
    ARRAY(SELECT t FROM UNNEST(tags) AS t WHERE t LIKE 's%') AS s_tags
FROM users;

-- Snowflake: FLATTEN + ARRAY_AGG
SELECT user_id,
    ARRAY_AGG(UPPER(f.value::STRING)) WITHIN GROUP (ORDER BY f.index) AS upper_tags
FROM users, LATERAL FLATTEN(tags) f
GROUP BY user_id;
```

## 实际用例

### 用例 1: 电商——价格批量折扣计算

```sql
-- ClickHouse / DuckDB
SELECT product_id, original_prices,
    arrayMap(p -> round(p * 0.8, 2), original_prices) AS discounted_20pct,
    arrayFilter(p -> p > 100, original_prices) AS expensive_items,
    arraySum(arrayMap(p -> p * 0.8, original_prices)) AS total_after_discount
FROM product_variants;
```

### 用例 2: 日志分析——提取错误码

```sql
-- Trino
SELECT log_id,
    filter(error_codes, e -> e BETWEEN 500 AND 599) AS server_errors,
    any_match(error_codes, e -> e = 503) AS has_service_unavailable,
    cardinality(filter(error_codes, e -> e >= 400)) AS total_error_count
FROM request_logs;
```

### 用例 3: 特征工程——数值标准化

```sql
-- Spark SQL
SELECT user_id,
    transform(feature_vector,
        x -> (x - array_min(feature_vector)) /
             (array_max(feature_vector) - array_min(feature_vector))
    ) AS normalized_features
FROM ml_features;
```

### 用例 4: 嵌套数组扁平化

```sql
-- DuckDB: 二维数组展平
SELECT list_reduce(
    list_transform([[1,2],[3,4],[5,6]], inner -> inner),
    (acc, x) -> list_concat(acc, x)
) AS flattened;
-- 结果: [1, 2, 3, 4, 5, 6]

-- Trino: flatten 直接支持
SELECT flatten(ARRAY[ARRAY[1,2], ARRAY[3,4]]);
```

## 对引擎开发者的实现分析

### 1. Parser 扩展: 箭头函数语法

需要在 SQL parser 中识别 Lambda 表达式：

```
Lambda 语法:
  identifier -> expression                  -- 单参数
  (id1, id2) -> expression                  -- 多参数
  (id1, id2, ...) -> expression             -- N 参数

在 parser 中，关键挑战是区分:
  x -> x + 1        (Lambda)
  x - > x + 1       (减法 + 大于比较)

需要 lookahead: 遇到 identifier 后检查下一个 token 是否是 ->
```

### 2. 类型推断

Lambda 表达式的参数类型来自调用上下文：

```sql
arrayMap(x -> x * 2, [1, 2, 3])
-- 推断: x 的类型 = 数组元素类型 = INT
-- 推断: 返回类型 = INT（x * 2 的结果类型）
-- 推断: arrayMap 返回类型 = ARRAY<INT>

arrayFilter(x -> length(x) > 3, ['hello', 'hi'])
-- 推断: x 的类型 = VARCHAR
-- 推断: length(x) > 3 的类型 = BOOLEAN
-- 推断: arrayFilter 返回类型 = ARRAY<VARCHAR>
```

实现要点：
- Lambda 参数类型必须从外层函数签名推断（不能要求用户声明类型）
- 支持泛型高阶函数签名: `transform(ARRAY<T>, T -> U) -> ARRAY<U>`
- 错误消息要友好: "Lambda 参数 x 的类型无法推断"

### 3. 闭包作用域

Lambda 表达式可以引用外部作用域的变量：

```sql
SELECT arrayMap(x -> x * factor, values) FROM config;
-- factor 是表的列，x 是 Lambda 参数
-- Lambda 形成闭包，捕获外部的 factor 值
```

实现要求：
- Lambda 体中的标识符解析优先级: Lambda 参数 > 外部列引用 > 函数名
- 禁止 Lambda 参数遮蔽（shadowing）外部列名（或至少给出警告）

### 4. 执行模型

```
高阶函数执行流程（以 arrayMap 为例）:
1. 评估数组表达式 → 得到数组值 [1, 2, 3]
2. 编译 Lambda 体 x -> x * 2 → 得到可执行的表达式节点
3. 遍历数组:
   a. 绑定 x = 1, 执行 Lambda 体 → 2
   b. 绑定 x = 2, 执行 Lambda 体 → 4
   c. 绑定 x = 3, 执行 Lambda 体 → 6
4. 收集结果 → [2, 4, 6]
```

优化技巧：
- Lambda 体编译一次，绑定变量后重复执行
- 对于简单 Lambda（如 `x -> x * 2`），可以编译为向量化操作
- 避免每次调用创建新的表达式求值上下文

### 5. reduce/aggregate 的特殊性

`reduce` 是最强大也最复杂的高阶函数：

```sql
reduce(array, initial_state, (state, element) -> new_state, state -> result)
```

- 需要两个 Lambda（累加函数 + 终结函数）
- 累加函数的类型推断: state 的类型 = initial_state 的类型
- 终结函数可选（有些引擎不支持）
- 不能并行化（有数据依赖）

### 6. 与 SQL 标准的关系

SQL 标准（截至 SQL:2023）没有定义 Lambda 表达式。各引擎的实现是事实标准。标准化的障碍在于：

- SQL 语法中从未有过 `->` 操作符
- 标识符作用域规则与现有 SQL 不同
- 高阶函数的类型系统超出传统 SQL 类型系统的能力

## 设计争议

### Lambda vs UNNEST 子查询

```sql
-- Lambda 方式 (DuckDB)
SELECT list_transform([1,2,3], x -> x * 2);

-- UNNEST 方式 (PostgreSQL)
SELECT ARRAY(SELECT x * 2 FROM UNNEST(ARRAY[1,2,3]) AS x);
```

两种方式的对比:
- **Lambda**: 语法简洁，无需理解相关子查询语义，但需要 parser 支持新语法
- **UNNEST 子查询**: 基于现有 SQL 原语，无需新语法，但冗长且 GROUP BY 问题多

从语言设计角度看，Lambda 是更优雅的方案。但 UNNEST 子查询的优势是不需要修改 SQL 语法。

### 为什么 PostgreSQL 不支持 Lambda？

PostgreSQL 有完善的数组类型和丰富的数组函数，但选择不引入 Lambda 语法。原因：
1. PostgreSQL 社区对 SQL 标准之外的语法扩展持保守态度
2. UNNEST + 相关子查询已经能表达同等语义
3. 引入 Lambda 需要对类型推断系统做大改
4. PL/pgSQL 函数可以作为 Lambda 的替代

## 参考资料

- ClickHouse: [Higher-Order Functions](https://clickhouse.com/docs/en/sql-reference/functions/array-functions#higher-order-functions)
- Trino: [Lambda Expressions](https://trino.io/docs/current/functions/lambda.html)
- DuckDB: [List Functions](https://duckdb.org/docs/sql/functions/list)
- Spark SQL: [Higher-Order Functions](https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#array-functions)

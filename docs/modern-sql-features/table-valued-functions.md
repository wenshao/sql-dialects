# 表值函数 (Table-Valued Functions)

返回表的函数——从 SQL Server 内联 TVF 到 SQL:2016 多态表函数 (PTF)，从 Oracle 流水线函数到 ClickHouse 表函数，是现代分析数据库扩展能力的核心机制。

## SQL 标准的演进

### SQL:2003 - PROCEDURE 返回 TABLE

SQL:2003（ISO/IEC 9075-4 SQL/PSM）首次允许过程返回表结构数据：

```sql
-- 抽象语法
CREATE PROCEDURE proc_name (params)
    RETURNS TABLE (col1 type1, col2 type2, ...)
    LANGUAGE SQL
BEGIN
    -- 过程体
    RETURN TABLE (query);
END;
```

但 SQL:2003 的"过程返回表"在主流引擎中实际表现为函数（function）形式：DB2 的 `CREATE FUNCTION ... RETURNS TABLE`、PostgreSQL 的 `CREATE FUNCTION ... RETURNS TABLE / SETOF`、SQL Server 的 `CREATE FUNCTION ... RETURNS TABLE`。

### SQL:2016 - 多态表函数 (PTF)

SQL:2016（ISO/IEC 9075-2 第 18 部分）引入了真正的多态表函数（Polymorphic Table Function, PTF），核心特征：

1. **输入参数可以是表**：函数接受表作为参数（不只是标量）
2. **输出 schema 动态决定**：返回表的列结构在调用时确定，而非定义时固定
3. **PARTITION BY / ORDER BY 子句**：调用时可指定输入表的分区和排序
4. **PASS THROUGH / KEEP WHEN**：控制输入列是否传递到输出

```sql
-- SQL:2016 PTF 抽象语法
SELECT *
FROM TABLE(my_ptf(
    input_table => TABLE(orders) PARTITION BY region ORDER BY ts,
    threshold => 100
));
```

PTF 是 SQL 标准向"通用扩展机制"迈出的一大步，但实际实现进展缓慢——只有 Oracle、DB2、ClickHouse、Trino 等少数引擎部分支持。

## 表值函数的分类

```
表值函数 (TVF)
├── 内联 TVF (Inline TVF)
│   └── 单一 SELECT 表达式，类似参数化视图
├── 多语句 TVF (Multi-Statement TVF)
│   └── 显式声明返回表，过程体填充返回表
├── 标量 UDF 返回表 (Set-Returning Function, SRF)
│   └── PostgreSQL RETURNS TABLE / SETOF 风格
├── 流水线表函数 (Pipelined Table Function)
│   └── Oracle 9i 引入，PIPE ROW 流式输出
├── 系统/内置 TVF
│   └── 引擎提供的 STRING_SPLIT/numbers/range 等
└── 多态表函数 (PTF, SQL:2016)
    └── 输入可为表，输出 schema 动态决定
```

## 支持矩阵 (45+ 数据库)

### 基本 TVF 支持总览

| 引擎 | 内联 TVF | 多语句 TVF | PTF (多态) | LATERAL 调用 | 内置 TVF | 版本 |
|------|---------|-----------|-----------|-------------|---------|------|
| SQL Server | 是 | 是 | 否 | `CROSS APPLY` | `STRING_SPLIT`, `OPENJSON` | 2000+ |
| Oracle | 通过视图 | PL/SQL 函数 | 部分 (PTF 19c+) | `LATERAL` / `APPLY` | `XMLTABLE`, `JSON_TABLE` | 9i+ |
| PostgreSQL | `RETURNS TABLE` | PL/pgSQL 函数 | 否 | `LATERAL` | `generate_series`, `unnest` | 8.0+ |
| MySQL | -- | 通过存储过程模拟 | 否 | `LATERAL` 8.0.14+ | `JSON_TABLE` 8.0+ | -- |
| MariaDB | -- | -- | 否 | `LATERAL` 10.6+ | `JSON_TABLE` 10.6+ | -- |
| SQLite | -- | -- | 否 | -- | `json_each`, `generate_series` | 3.9+ |
| DB2 | 是 | 是 | 是 (11.5+) | `LATERAL` | `XMLTABLE`, `JSON_TABLE` | v8+ |
| Snowflake | 是 (SQL UDF) | 是 (JavaScript/Python UDTF) | 否 | `LATERAL FLATTEN` | `FLATTEN`, `GENERATOR` | GA |
| BigQuery | 是 (SQL TVF) | 否 | 否 | `UNNEST` (隐式) | `UNNEST`, `GENERATE_*_ARRAY` | 2020+ |
| Redshift | 是 (Stored Procedure) | 部分 | 否 | -- | `pg_*` 系统函数 | GA |
| Amazon Athena | 通过视图 | -- | 否 | `UNNEST` | 继承 Trino | GA |
| Azure Synapse | 是 | 是 | 否 | `CROSS APPLY` | 继承 SQL Server | GA |
| ClickHouse | 否 (UDF 受限) | 否 | 是 (表函数) | `ARRAY JOIN` | `file`, `url`, `mysql`, `numbers` | 早期 |
| Trino | 否 | 否 | 是 (SQL:2016 PTF) | `UNNEST` / `LATERAL` | `unnest`, `sequence` | 414+ (2023) |
| Presto | 否 | 否 | 否 | `UNNEST` | `unnest`, `sequence` | -- |
| Spark SQL | 是 (SQL UDF) | 是 (UDTF Python/Scala) | 否 | `LATERAL VIEW` | `explode`, `posexplode` | 1.0+ |
| Hive | 是 | 是 (UDTF) | 否 | `LATERAL VIEW` | `explode`, `stack`, `posexplode` | 早期 |
| Flink SQL | 是 | 是 (Table Function) | 否 | `LATERAL TABLE` | `UNNEST` | 1.0+ |
| Vertica | 是 | 是 (UDx) | 否 | `LATERAL` | `EXPLODE`, `MAPLOOKUP` | 早期 |
| Greenplum | 是 (继承 PG) | 是 (继承 PG) | 否 | `LATERAL` | 继承 PG | 6.0+ |
| TimescaleDB | 是 (继承 PG) | 是 | 否 | `LATERAL` | `time_bucket`, 继承 PG | 继承 PG |
| CockroachDB | 否 | 否 | 否 | `LATERAL` | `generate_series`, `crdb_internal.*` | -- |
| TiDB | 否 (用视图) | 否 | 否 | `LATERAL` 6.5+ | `JSON_TABLE` 7.5+ | -- |
| OceanBase | 部分 (Oracle 模式) | 部分 | 否 | `LATERAL` | `XMLTABLE`, `JSON_TABLE` (Oracle 模式) | 4.0+ |
| YugabyteDB | 是 (继承 PG) | 是 | 否 | `LATERAL` | 继承 PG | GA |
| SingleStore (MemSQL) | 是 (UDF) | 否 | 否 | -- | `JSON_AGG`, `JSON_TO_ARRAY` | 7.0+ |
| Impala | 否 | 否 | 否 | -- | `EXPLODE`, `array_to_string` | -- |
| StarRocks | 部分 | 否 | 否 | `LATERAL VIEW` | `unnest`, `generate_series` | 2.5+ |
| Doris | 部分 | 否 | 否 | `LATERAL VIEW` | `explode_*` 系列 | 1.2+ |
| MonetDB | 是 | 是 (Python/R UDF) | 否 | -- | `generate_series`, `sys.*` | 早期 |
| SAP HANA | 是 (SQL/PSM) | 是 | 否 | `LATERAL` | `SERIES_GENERATE_*` | 1.0+ |
| Informix | 是 | 是 (SPL) | 否 | -- | `LIST/SET` 表函数 | 早期 |
| Firebird | 是 (Stored Procedure with SUSPEND) | 是 | 否 | -- | -- | 1.0+ |
| H2 | 是 (Java 函数) | 部分 | 否 | -- | `system_range` | 早期 |
| HSQLDB | 否 | 部分 | 否 | -- | -- | -- |
| Derby | 是 (Java VTI) | 是 | 否 | -- | -- | 早期 |
| Teradata | 是 | 是 (SP) | 否 | -- | `XMLAGG`, `TD_UNPIVOT` | 早期 |
| Yellowbrick | 是 (继承 PG) | 是 | 否 | `LATERAL` | 继承 PG | GA |
| Firebolt | 否 | 否 | 否 | `UNNEST` | `UNNEST`, `GENERATE_SERIES` | GA |
| DatabendDB | 否 | 否 | 否 | -- | `numbers`, `unnest` | GA |
| Crate DB | 否 | 否 | 否 | -- | `unnest`, `generate_series` | -- |
| QuestDB | 否 | 否 | 否 | -- | -- | -- |
| Exasol | 是 (UDF Python/Lua) | 是 | 否 | -- | -- | 早期 |
| Materialize | 否 | 否 | 否 | `LATERAL` | `generate_series`, `unnest` | -- |
| RisingWave | 否 | 否 | 否 | `LATERAL` | `generate_series`, `unnest` | -- |
| Google Spanner | 是 (SQL TVF, GoogleSQL) | 否 | 否 | `UNNEST` | `UNNEST`, `GENERATE_*_ARRAY` | GA |
| Dremio | 否 | 否 | 否 | -- | 继承 Apache Arrow / Calcite | -- |
| Apache Drill | 否 | 否 | 否 | -- | `FLATTEN`, `KVGEN` | -- |
| Apache Pinot | 否 | 否 | 否 | -- | -- | -- |

> 统计：约 30+ 引擎支持某种形式的 TVF；约 12+ 引擎只能依赖内置 TVF 或视图替代。
>
> 真正实现 SQL:2016 PTF 的极少：**Oracle 19c+、DB2 11.5+、ClickHouse 表函数、Trino 414+（2023）**。

### 内置 TVF / 表函数对比

| 引擎 | 字符串拆分 | JSON 展开 | 数组展开 | 序列生成 | 远程数据 |
|------|-----------|----------|---------|---------|---------|
| SQL Server | `STRING_SPLIT` (2016+) | `OPENJSON` | -- | 递归 CTE | `OPENROWSET` |
| Oracle | `APEX_STRING.SPLIT` / 自定义 | `JSON_TABLE` | `TABLE(varray)` | `CONNECT BY LEVEL` | -- |
| PostgreSQL | `string_to_table` (14+) | `jsonb_array_elements` | `unnest` | `generate_series` | `dblink`, FDW |
| MySQL | `JSON_TABLE` 间接 | `JSON_TABLE` (8.0+) | `JSON_TABLE` | 递归 CTE | -- |
| DB2 | `SYSTOOLS.UDFs` | `JSON_TABLE` (11.5+) | `XMLTABLE` | `SYSPROC.MON_*` | -- |
| BigQuery | `SPLIT` + `UNNEST` | `JSON_EXTRACT_ARRAY` + `UNNEST` | `UNNEST` | `GENERATE_ARRAY` | `EXTERNAL_QUERY` |
| Snowflake | `STRTOK_SPLIT_TO_TABLE` | `LATERAL FLATTEN` | `LATERAL FLATTEN` | `GENERATOR` | `EXTERNAL_TABLE` |
| ClickHouse | `splitByChar` + `arrayJoin` | `JSONExtractKeysAndValues` | `arrayJoin` | `numbers`, `range` | `file`, `url`, `mysql`, `s3`, `kafka` |
| Trino | `split_to_rows` (PTF) | `json_extract` + `unnest` | `unnest` | `sequence` | `system.*`, 连接器 |
| Spark SQL | `split` + `explode` | `from_json` + `explode` | `explode` | `range` | -- |
| Hive | `split` + `explode` | `json_tuple` | `explode` | -- | -- |
| Flink SQL | `STRING_SPLIT` | `JSON_QUERY` | `UNNEST` | -- | 表 source |

## 各引擎深入解析

### SQL Server: 内联 TVF 与多语句 TVF（自 2000 起）

SQL Server 是 TVF 概念的最早大规模实现者，自 SQL Server 2000 即支持两种 TVF 形式。

#### 内联 TVF (Inline TVF)

内联 TVF 类似"参数化视图"：函数体只是单一的 `SELECT` 表达式。

```sql
-- 内联 TVF 定义
CREATE FUNCTION dbo.GetOrdersByCustomer (@CustomerId INT)
RETURNS TABLE
AS
RETURN
(
    SELECT order_id, order_date, total_amount
    FROM dbo.orders
    WHERE customer_id = @CustomerId
);

-- 调用
SELECT * FROM dbo.GetOrdersByCustomer(123);

-- 与其他表 JOIN：CROSS APPLY 是惯用写法
SELECT c.name, o.order_id, o.total_amount
FROM dbo.customers c
CROSS APPLY dbo.GetOrdersByCustomer(c.customer_id) o;
```

关键特征：
- 函数体为单一 SELECT 语句
- 优化器在调用时**内联展开**（类似宏替换），与外部查询合并优化
- 行数估算：与同等的 SELECT 子查询完全相同，准确

#### 多语句 TVF (Multi-Statement TVF)

多语句 TVF 在函数体中显式构造一个返回表变量，可包含复杂逻辑。

```sql
-- 多语句 TVF 定义
CREATE FUNCTION dbo.GetActiveOrdersWithStats (@CustomerId INT)
RETURNS @Result TABLE (
    order_id INT,
    order_date DATE,
    total_amount DECIMAL(18, 2),
    rank_in_customer INT
)
AS
BEGIN
    -- 多语句体：可包含变量、循环、条件
    DECLARE @TotalCount INT;
    SELECT @TotalCount = COUNT(*) FROM dbo.orders WHERE customer_id = @CustomerId;

    INSERT INTO @Result (order_id, order_date, total_amount, rank_in_customer)
    SELECT order_id, order_date, total_amount,
           ROW_NUMBER() OVER (ORDER BY total_amount DESC)
    FROM dbo.orders
    WHERE customer_id = @CustomerId AND status = 'active';

    RETURN;
END;

-- 调用方式与内联 TVF 相同
SELECT * FROM dbo.GetActiveOrdersWithStats(123);
```

#### 内联 vs 多语句：基数估算的关键差异

这是 SQL Server TVF 最重要的性能议题：

| 特性 | 内联 TVF | 多语句 TVF (传统) |
|------|---------|------------------|
| 优化方式 | 内联展开，与查询合并优化 | 黑盒，独立编译 |
| 基数估算 (传统) | 准确（基于 SELECT 表达式） | 固定 1 行 (SQL Server 2014 前) |
| 基数估算 (新) | 同左 | 100 行 (SQL Server 2014-2016) / 区间反馈 (2017+) |
| 并行执行 | 是 | 大部分情况否 |
| 重用机会 | 与外部 JOIN/聚合协同优化 | 无法跨 TVF 边界优化 |

```sql
-- 性能陷阱示例
-- 多语句 TVF：返回 100 万行
CREATE FUNCTION dbo.GetMillionRows() RETURNS @t TABLE (id INT, value INT)
AS BEGIN
    INSERT INTO @t SELECT id, value FROM dbo.million_row_table;
    RETURN;
END;

-- 调用并 JOIN：优化器以为返回 1 行（旧版）或 100 行（新版）
-- 选择 nested loop，性能灾难性
SELECT * FROM dbo.GetMillionRows() t
JOIN dbo.large_table x ON t.id = x.id;
```

SQL Server 2017 引入"间隔执行反馈"（Interleaved Execution）改善多语句 TVF 估算：第一次执行后用真实行数重新优化后续查询。但仍建议**优先使用内联 TVF**。

#### SQL Server 内置 TVF

```sql
-- STRING_SPLIT (2016+): 字符串拆分
SELECT value FROM STRING_SPLIT('a,b,c,d', ',');

-- 带序号 (2022+)
SELECT value, ordinal FROM STRING_SPLIT('a,b,c,d', ',', 1);

-- OPENJSON: JSON 展开
SELECT * FROM OPENJSON('[{"id":1,"name":"a"},{"id":2,"name":"b"}]')
WITH (id INT, name NVARCHAR(50));

-- OPENROWSET: 远程/外部数据
SELECT * FROM OPENROWSET(BULK 'C:\data.csv', FORMATFILE = 'C:\fmt.xml') AS r;
```

### Oracle: 流水线表函数（自 9i, 2001 起）

Oracle 9i (2001) 引入 **Pipelined Table Function**，是 Oracle 表值函数的标志性特性，行为类似生成器（流式输出）。

```sql
-- 步骤 1: 定义对象类型 (行类型)
CREATE OR REPLACE TYPE order_row AS OBJECT (
    order_id    NUMBER,
    customer_id NUMBER,
    amount      NUMBER(18, 2)
);
/

-- 步骤 2: 定义集合类型 (表类型)
CREATE OR REPLACE TYPE order_tab AS TABLE OF order_row;
/

-- 步骤 3: 定义流水线函数
CREATE OR REPLACE FUNCTION get_large_orders (p_threshold NUMBER)
    RETURN order_tab PIPELINED
AS
BEGIN
    FOR rec IN (SELECT order_id, customer_id, amount FROM orders
                WHERE amount > p_threshold) LOOP
        PIPE ROW (order_row(rec.order_id, rec.customer_id, rec.amount));
    END LOOP;
    RETURN;
END;
/

-- 调用：在 FROM 中用 TABLE() 子句包裹
SELECT * FROM TABLE(get_large_orders(1000));

-- 与基表 JOIN
SELECT c.name, o.order_id, o.amount
FROM customers c, TABLE(get_large_orders(1000)) o
WHERE o.customer_id = c.id;
```

#### 流水线 vs 非流水线对比

```sql
-- 非流水线（传统）：构造完整集合后一次返回
CREATE FUNCTION non_pipelined RETURN order_tab AS
    v_result order_tab := order_tab();
BEGIN
    FOR rec IN (SELECT * FROM orders) LOOP
        v_result.EXTEND;
        v_result(v_result.LAST) := order_row(rec.order_id, rec.customer_id, rec.amount);
    END LOOP;
    RETURN v_result;          -- 必须先填满集合，再整体返回
END;

-- 流水线：边生成边输出
-- 优势：1. 调用方第一行立即可见  2. 内存 O(1)  3. 可与 SELECT 流水线并行
```

#### 并行流水线函数

```sql
-- PARALLEL_ENABLE 子句允许函数被分布到多个 PQ 从属进程
CREATE OR REPLACE FUNCTION parallel_proc (
    p_cur SYS_REFCURSOR
) RETURN order_tab PIPELINED
PARALLEL_ENABLE (PARTITION p_cur BY HASH (order_id))
AS
    v_rec orders%ROWTYPE;
BEGIN
    LOOP
        FETCH p_cur INTO v_rec;
        EXIT WHEN p_cur%NOTFOUND;
        PIPE ROW (order_row(v_rec.order_id, v_rec.customer_id, v_rec.amount));
    END LOOP;
END;
```

#### Oracle 19c+ 多态表函数 (PTF)

Oracle 19c 部分实现了 SQL:2016 PTF。

```sql
-- 定义 PTF 实现包
CREATE PACKAGE my_ptf_pkg AS
    FUNCTION describe (
        tab IN OUT DBMS_TF.TABLE_T
    ) RETURN DBMS_TF.DESCRIBE_T;

    PROCEDURE fetch_rows;
END;
/

-- 包体省略...

-- 注册 PTF
CREATE FUNCTION my_polymorphic_fn (tab TABLE)
    RETURN TABLE PIPELINED ROW POLYMORPHIC USING my_ptf_pkg;
/

-- 调用
SELECT * FROM my_polymorphic_fn(orders);
```

### PostgreSQL: 集合返回函数 / RETURNS TABLE

PostgreSQL 不区分"内联 TVF"和"多语句 TVF"，所有返回多行的函数统称为 **Set-Returning Function (SRF)**。

#### 三种返回多行的语法

```sql
-- 1. RETURNS SETOF: 返回单值列的集合
CREATE FUNCTION get_active_user_ids() RETURNS SETOF INT AS $$
    SELECT id FROM users WHERE active = true;
$$ LANGUAGE SQL;

-- 2. RETURNS SETOF record: 返回任意结构的记录集
CREATE FUNCTION get_user_pairs() RETURNS SETOF RECORD AS $$
    SELECT id, name FROM users;
$$ LANGUAGE SQL;
-- 调用时必须用 AS 子句声明列结构
SELECT * FROM get_user_pairs() AS t(id INT, name TEXT);

-- 3. RETURNS TABLE (推荐): 显式声明列结构
CREATE FUNCTION get_orders_by_customer (p_customer_id INT)
RETURNS TABLE (order_id INT, order_date DATE, total NUMERIC) AS $$
    SELECT order_id, order_date, total_amount
    FROM orders
    WHERE customer_id = p_customer_id;
$$ LANGUAGE SQL;

-- 调用
SELECT * FROM get_orders_by_customer(123);
```

#### SQL 函数 vs PL/pgSQL 函数

```sql
-- SQL 函数（类似内联 TVF）：单 SELECT 表达式，可被内联
CREATE FUNCTION sql_tvf (p_id INT) RETURNS TABLE (...) AS $$
    SELECT ... FROM ... WHERE id = p_id;
$$ LANGUAGE SQL;

-- PL/pgSQL 函数（类似多语句 TVF）：可包含控制流
CREATE FUNCTION plpgsql_tvf (p_id INT) RETURNS TABLE (...) AS $$
BEGIN
    RETURN QUERY
    SELECT ... FROM ... WHERE id = p_id;
    -- 可继续 RETURN QUERY ... 多次累加结果
END;
$$ LANGUAGE plpgsql;
```

PostgreSQL 12 起，简单 SQL 函数会被**内联展开**到查询树中，性能与子查询持平。PL/pgSQL 函数是黑盒，行数估算默认为 1000 行（可用 `ROWS` 子句覆盖）：

```sql
CREATE FUNCTION big_function() RETURNS SETOF orders AS $$
BEGIN ... END;
$$ LANGUAGE plpgsql ROWS 100000;   -- 提示优化器预估 10 万行
```

#### LATERAL 调用 SRF

```sql
-- 函数引用前面表的列时，需用 LATERAL（也可省略，PG 9.3+ 自动推断）
SELECT t.id, s.value
FROM my_table t
CROSS JOIN LATERAL get_orders_by_customer(t.customer_id) AS s;
```

### MySQL: 无原生 TVF，靠存储过程模拟

MySQL 一直没有真正的 TVF。可用以下三种方式逼近：

```sql
-- 方案 1: 存储过程返回结果集
DELIMITER //
CREATE PROCEDURE get_orders_by_customer(IN p_customer_id INT)
BEGIN
    SELECT order_id, order_date, total_amount
    FROM orders WHERE customer_id = p_customer_id;
END //
DELIMITER ;

-- 调用：CALL，但结果不能直接 JOIN
CALL get_orders_by_customer(123);

-- 方案 2: 视图（无参数）
CREATE VIEW v_active_orders AS
SELECT * FROM orders WHERE status = 'active';

-- 方案 3: JSON_TABLE (8.0+) 间接实现
SELECT t.* FROM JSON_TABLE(
    '[{"id":1,"name":"a"},{"id":2,"name":"b"}]',
    '$[*]' COLUMNS (id INT PATH '$.id', name VARCHAR(50) PATH '$.name')
) AS t;
```

MySQL 8.0.14 引入 LATERAL，可与 JSON_TABLE 协同模拟简单 TVF 场景。

### DB2: 表函数 (自 v8 起，最早实现 SQL 标准)

DB2 自 v8（2002）起支持 `CREATE FUNCTION ... RETURNS TABLE`，是 SQL 标准最完整的早期实现之一。

```sql
-- 标量返回表函数
CREATE FUNCTION get_orders_by_customer (p_customer_id INTEGER)
RETURNS TABLE (
    order_id INTEGER,
    order_date DATE,
    total DECIMAL(18, 2)
)
LANGUAGE SQL
RETURN
    SELECT order_id, order_date, total_amount
    FROM orders
    WHERE customer_id = p_customer_id;

-- 调用：FROM TABLE() 子句
SELECT * FROM TABLE(get_orders_by_customer(123)) AS t;

-- 与基表 JOIN
SELECT c.name, t.*
FROM customers c, TABLE(get_orders_by_customer(c.customer_id)) AS t;
```

#### DB2 多语句 TVF (LANGUAGE SQL PSM)

```sql
CREATE FUNCTION complex_tvf (p_threshold INTEGER)
RETURNS TABLE (id INTEGER, name VARCHAR(100))
LANGUAGE SQL
BEGIN
    DECLARE v_count INTEGER;
    -- 复杂逻辑...
    RETURN
        SELECT id, name FROM big_table WHERE value > p_threshold;
END;
```

#### DB2 11.5 PTF 支持

DB2 11.5 部分支持 SQL:2016 PTF（特别是面向 Db2 Warehouse on Cloud 的分析场景）：

```sql
-- 简化的 PTF 调用示例
SELECT * FROM TABLE(my_ptf(
    INPUT TABLE => orders,
    PARAMETER => 100
));
```

### Snowflake: JavaScript / Python TVF (UDTF)

Snowflake 通过 **User-Defined Table Function (UDTF)** 支持 TVF，特色是 JavaScript 与 Python 实现。

#### SQL TVF（最简单）

```sql
CREATE OR REPLACE FUNCTION get_orders_by_customer (CUSTOMER_ID NUMBER)
RETURNS TABLE (ORDER_ID NUMBER, ORDER_DATE DATE, TOTAL NUMBER(18, 2))
AS
$$
    SELECT order_id, order_date, total_amount
    FROM orders
    WHERE customer_id = CUSTOMER_ID
$$;

SELECT * FROM TABLE(get_orders_by_customer(123));
```

#### JavaScript UDTF（带状态）

```sql
CREATE OR REPLACE FUNCTION js_split_words (S STRING)
RETURNS TABLE (WORD STRING)
LANGUAGE JAVASCRIPT
AS
$$
{
    processRow: function (row, rowWriter, context) {
        var words = row.S.split(' ');
        for (var i = 0; i < words.length; i++) {
            rowWriter.writeRow({ WORD: words[i] });
        }
    }
}
$$;

SELECT * FROM TABLE(js_split_words('hello world foo bar'));
```

#### Python UDTF（自 2022 起）

```sql
CREATE OR REPLACE FUNCTION py_top_n_per_group (N INTEGER)
RETURNS TABLE (GROUP_KEY STRING, VALUE NUMBER, RANK INTEGER)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'TopN'
AS $$
class TopN:
    def __init__(self):
        self._buffer = []

    def process(self, group_key, value):
        self._buffer.append((group_key, value))

    def end_partition(self):
        # 排序、取 top N、输出
        self._buffer.sort(key=lambda x: -x[1])
        for rank, (g, v) in enumerate(self._buffer[:CONTEXT_N], 1):
            yield (g, v, rank)
$$;

-- 配合 PARTITION BY 使用
SELECT * FROM events,
LATERAL py_top_n_per_group(5)
    OVER (PARTITION BY user_id ORDER BY ts);
```

### BigQuery: TVF (自 2020 起)

Google BigQuery 在 2020 年正式支持 SQL TVF，定义类似视图，但接受参数。

```sql
-- 定义 TVF
CREATE OR REPLACE TABLE FUNCTION dataset.get_orders (customer_id INT64)
AS
SELECT order_id, order_date, total_amount
FROM `project.dataset.orders`
WHERE orders.customer_id = customer_id;

-- 调用
SELECT * FROM dataset.get_orders(123);

-- 与基表 JOIN
SELECT c.name, o.*
FROM customers c,
UNNEST([STRUCT(c.customer_id AS cid)]) p
JOIN dataset.get_orders(p.cid) o ON true;
```

BigQuery TVF 限制：
- 只支持 SQL 表达式（无 JavaScript / Python 多语句）
- 接受标量参数，不支持表参数
- 配合 `UNNEST` 实现集合展开是惯用模式

### ClickHouse: 表函数 (Table Functions)

ClickHouse 的 **Table Function** 是其 PTF 风格的代表实现，通过 `file()` / `url()` / `mysql()` 等系统函数把外部数据接入查询。

```sql
-- 1. file(): 直接查询本地文件
SELECT * FROM file('data.csv', 'CSV', 'id UInt32, name String');

-- 2. url(): HTTP 远程数据
SELECT * FROM url(
    'https://example.com/data.json',
    'JSONEachRow',
    'id UInt32, name String'
);

-- 3. mysql(): MySQL 远程查询
SELECT * FROM mysql(
    'host:port', 'database', 'table',
    'user', 'password'
) WHERE id < 1000;

-- 4. s3(): S3 对象存储
SELECT * FROM s3(
    'https://bucket.s3.amazonaws.com/path/data.parquet',
    'access_key', 'secret',
    'Parquet'
);

-- 5. cluster(): 跨节点查询
SELECT count() FROM cluster('my_cluster', 'database', 'table');

-- 6. numbers(): 序列生成
SELECT number FROM numbers(10);  -- 0..9

-- 7. generateRandom(): 测试数据生成
SELECT * FROM generateRandom('id UInt32, name String', 1) LIMIT 100;
```

#### ClickHouse 表函数的 PTF 特性

ClickHouse 表函数本质上是多态的：返回的列结构可以由参数（如 schema 字符串或外部数据本身）动态决定。这与 SQL:2016 PTF 的精神一致，虽然语法和标准不同。

#### 用户自定义表函数

ClickHouse 不支持用户自定义 TVF（仅支持标量 UDF）。需要扩展时通常需要修改 ClickHouse 源码并实现 `ITableFunction` 接口。

### Trino / Presto: SQL:2016 PTF

Trino 414（2023 年发布）正式实现了 SQL:2016 PTF，是少数几个原生支持的引擎之一。

```sql
-- Trino PTF 调用语法（接近 SQL:2016 标准）
SELECT *
FROM TABLE(my_catalog.system.split_to_rows(
    input => TABLE(orders) PARTITION BY region,
    delimiter => ',',
    column => 'tags'
));

-- 内置 PTF: exclude_columns
SELECT *
FROM TABLE(exclude_columns(
    input => TABLE(orders),
    columns => DESCRIPTOR(internal_id, deprecated_field)
));

-- 内置 PTF: sequence
SELECT * FROM TABLE(sequence(start => 1, stop => 10, step => 1));
```

Trino 还支持插件机制：连接器可以注册自定义 PTF（如 `system.query()` 用于直接传递 SQL 给底层数据源）。

```sql
-- PostgreSQL 连接器的 query() PTF: 把 SQL 透传给 PG
SELECT *
FROM TABLE(postgresql.system.query(
    query => 'SELECT id, name FROM users WHERE active = true'
));
```

### Spark SQL / Hive: UDTF + LATERAL VIEW

Spark SQL 与 Hive 共享 **UDTF**（User-Defined Table-Generating Function）+ `LATERAL VIEW` 模式。

```sql
-- 内置 UDTF: explode
SELECT id, tag FROM articles LATERAL VIEW explode(tags) t AS tag;

-- 内置 UDTF: posexplode (带位置)
SELECT id, pos, tag FROM articles
LATERAL VIEW posexplode(tags) t AS pos, tag;

-- 内置 UDTF: stack (列转行)
SELECT id, col, val FROM measurements
LATERAL VIEW stack(3, 'temp', temp, 'humidity', humidity, 'pressure', pressure) t AS col, val;

-- LATERAL VIEW OUTER: 数组为空/NULL 时保留外部行
SELECT id, tag FROM articles LATERAL VIEW OUTER explode(tags) t AS tag;
```

#### Spark SQL Python UDTF（Spark 3.5+, 2024）

```python
from pyspark.sql.functions import udtf

@udtf(returnType="word: string, length: int")
class SplitWords:
    def eval(self, text: str):
        for word in text.split():
            yield (word, len(word))

# 注册并使用
spark.udtf.register("split_words", SplitWords)
spark.sql("SELECT * FROM split_words('hello world foo')").show()
```

### Vertica: 表函数 (UDx)

Vertica 通过 C++ / Java / R / Python 的 UDx 机制支持 TVF。

```sql
-- 内置表函数：EXPLODE
SELECT id, val FROM employees, EXPLODE(skills) WITH ORDINALITY AS t(idx, val);

-- 内置：MAPLOOKUP - 返回 KV 对
SELECT id, key, value FROM kv_table, MAPLOOKUP(metadata) AS t(key, value);

-- 用户自定义 UDTF（C++ 实现，分布式执行）
CREATE TRANSFORM FUNCTION my_udtf AS LANGUAGE 'C++'
NAME 'MyUDTFFactory' LIBRARY my_lib;
```

### Flink SQL: Table Function

Flink 用 `LATERAL TABLE` 调用表函数，特别用于流处理中的"展开"和"分裂"操作。

```sql
-- 内置 UNNEST
SELECT id, tag FROM articles, UNNEST(tags) AS t(tag);

-- 用户定义表函数 (Java/Scala)
-- public class SplitFunction extends TableFunction<Row> {
--     public void eval(String s, String sep) {
--         for (String w : s.split(sep)) collect(Row.of(w));
--     }
-- }

CREATE FUNCTION split_words AS 'com.example.SplitFunction';

SELECT id, w
FROM events,
LATERAL TABLE(split_words(text, ' ')) AS t(w);
```

### CockroachDB / TiDB: 主要靠内置 TVF

CockroachDB 不支持用户定义 TVF，但保留了 PostgreSQL 兼容的 SRF：

```sql
-- CockroachDB
SELECT * FROM generate_series(1, 10);
SELECT crdb_internal.cluster_id();
SELECT * FROM crdb_internal.ranges;  -- 系统视图风格 TVF
```

TiDB 类似，主要依赖 `JSON_TABLE`（7.5+）和递归 CTE。

## SQL Server 内联 vs 多语句 TVF：基数估算深度

### 旧版基数估算 (SQL Server 2008-2014)

```
内联 TVF:
  优化阶段被展开为子查询 → 与外部查询合并优化
  基数估算与同等子查询完全相同 (基于统计信息)

多语句 TVF (SQL Server 2014 之前):
  黑盒处理，固定估算为 1 行
  灾难性后果: 优化器选 nested loop, 用 1 行 NL 100 万行
```

### 改进路径

| 版本 | 多语句 TVF 估算 | 备注 |
|------|----------------|------|
| 2008-2012 | 固定 1 行 | 灾难性默认 |
| 2014 (CE 120) | 100 行 | 修补但仍粗糙 |
| 2017 (CE 140) | 间隔执行反馈 | 第一次执行后用真实行数重新优化后续 |
| 2019 (CE 150) | 同上 + 自适应 JOIN | nested loop / hash join 运行时切换 |
| 2022 | 同上 + 内存赠款反馈 | 进一步缓解坏估算后果 |

### 性能对比示例

```sql
-- 场景：返回 100 万行的 TVF 与大表 JOIN
-- 多语句 TVF（旧版）：估 1 行 → nested loop → 全表扫描 100 万次 → 数小时
-- 多语句 TVF（新版）：估 100 行 → 仍偏小，但好得多
-- 内联 TVF：精确估算 → 选 hash join → 数秒

-- 推荐：尽可能使用内联 TVF
-- 如必须多语句逻辑，考虑：
--   1. 临时表 + 显式 INSERT，让优化器看到真实统计信息
--   2. 在调用处用 OPTION (RECOMPILE) 强制重编译
--   3. SQL Server 2017+ 启用间隔执行
```

## 多态表函数 (PTF) 深入

### SQL:2016 PTF 完整模型

PTF 在标准中定义了三种"语义"角色：

1. **Row Semantics PTF**：逐行处理，输出可能比输入多/少行
2. **Set Semantics PTF**：按 PARTITION 整批处理，每批独立
3. **Pruning PTF**：可消除不需要的列（投影下推友好）

```sql
-- SQL:2016 抽象语法
SELECT *
FROM TABLE(my_ptf(
    -- 表参数：可带分区和排序
    input => TABLE(orders) PARTITION BY region ORDER BY ts,

    -- 标量参数
    threshold => 100,

    -- COPARTITION：指定多个表参数同分区
    -- (假设有 input2 同样分区 by region)

    -- 列描述符（PTF 自身可决定要哪些列）
    columns => DESCRIPTOR(amount, status)
));
```

### Oracle PTF（19c）

Oracle 19c 实现了 PTF，使用 PL/SQL 包描述函数语义：

```sql
-- 包规范：DESCRIBE 返回输出 schema
CREATE PACKAGE rank_ptf_pkg AS
    FUNCTION describe (
        tab IN OUT DBMS_TF.TABLE_T,
        order_col IN VARCHAR2
    ) RETURN DBMS_TF.DESCRIBE_T;

    PROCEDURE fetch_rows;
END;
/

-- PTF 注册
CREATE FUNCTION rank_within (tab TABLE, order_col VARCHAR2 DEFAULT 'ID')
    RETURN TABLE PIPELINED ROW POLYMORPHIC USING rank_ptf_pkg;
/

-- 调用：传入表 + 列名
SELECT * FROM rank_within(orders, 'amount');
```

Oracle PTF 主要用例：行级 transform（添加计算列、过滤、重命名），不太适合复杂分析。

### DB2 PTF（11.5+）

DB2 11.5（特别是 Db2 Warehouse on Cloud）支持简化的 PTF，主要用于内置分析函数（如 `MCSTABLE`, `IDA_*` 系列机器学习函数）。

```sql
-- 简化语法
SELECT *
FROM TABLE(IDAX.PREDICT_REGRESSION(
    'INTABLE=test_data, MODEL=my_model, TARGET=PREDICTED'
));
```

### ClickHouse 表函数：实质上的 PTF

ClickHouse 表函数虽不遵循 SQL:2016 语法，但实质满足 PTF 三大特征：
1. **输入可以是表** (file/url/mysql 等返回表)
2. **输出 schema 动态决定** (由 schema 字符串或推断生成)
3. **多态** (同一函数可返回不同结构)

```sql
-- file() PTF: schema 由参数显式指定
SELECT * FROM file('a.csv', 'CSV', 'id UInt32, name String');
SELECT * FROM file('b.csv', 'CSV', 'ts DateTime, value Float64');

-- mysql() PTF: schema 由远程表推断
SELECT * FROM mysql('host', 'db', 'table_a', 'u', 'p');  -- 一种 schema
SELECT * FROM mysql('host', 'db', 'table_b', 'u', 'p');  -- 不同 schema
```

### Trino PTF：最贴近标准

Trino 是少数严格按 SQL:2016 PTF 语法实现的引擎：

```sql
-- 标准 PTF 调用
SELECT *
FROM TABLE(my_catalog.schema.my_ptf(
    input => TABLE(t) PARTITION BY k ORDER BY ts,
    param => 'value'
));

-- 连接器 PTF: 透传查询
SELECT *
FROM TABLE(mysql.system.query(
    query => 'SELECT id, count(*) FROM t GROUP BY id'
));
```

Trino 414 还引入了 **descriptor argument**：

```sql
-- DESCRIPTOR 类型参数：传递列名列表
SELECT *
FROM TABLE(exclude_columns(
    input => TABLE(orders),
    columns => DESCRIPTOR(internal_id, debug_field)
));
```

## PostgreSQL: SETOF vs RETURNS TABLE 对比

PostgreSQL 三种返回多行的语法在功能上有差异：

### 三种语法的对比

| 特性 | RETURNS SETOF type | RETURNS SETOF RECORD | RETURNS TABLE |
|------|-------------------|---------------------|---------------|
| 列结构 | 返回 type 的所有列 | 调用时指定 | 函数定义时指定 |
| 调用语法 | `SELECT * FROM f()` | `SELECT * FROM f() AS t(...)` | `SELECT * FROM f()` |
| 类型重用 | 是 (基于已有类型) | 灵活 | 显式 |
| 优化器友好 | 是 | 一般 | 是 |

```sql
-- RETURNS SETOF type
CREATE FUNCTION get_user_records() RETURNS SETOF users AS $$
    SELECT * FROM users WHERE active = true;
$$ LANGUAGE SQL;

SELECT * FROM get_user_records();  -- 直接调用，结构来自 users 表

-- RETURNS SETOF RECORD (匿名)
CREATE FUNCTION get_pairs() RETURNS SETOF RECORD AS $$
    SELECT id, name FROM users;
$$ LANGUAGE SQL;

-- 调用必须指定结构
SELECT * FROM get_pairs() AS t(id INT, name TEXT);

-- RETURNS TABLE (推荐)
CREATE FUNCTION get_orders (p_id INT)
RETURNS TABLE (order_id INT, total NUMERIC) AS $$
    SELECT order_id, total_amount FROM orders WHERE customer_id = p_id;
$$ LANGUAGE SQL;

SELECT * FROM get_orders(123);
```

### PL/pgSQL 中 RETURN QUERY / RETURN NEXT

```sql
-- RETURN QUERY: 一次返回整批
CREATE FUNCTION batch_return (p_id INT)
RETURNS TABLE (id INT, val INT) AS $$
BEGIN
    RETURN QUERY
    SELECT id, val FROM source WHERE customer_id = p_id;
END;
$$ LANGUAGE plpgsql;

-- RETURN NEXT: 逐行追加（类似 PIPE ROW）
CREATE FUNCTION row_by_row (p_n INT)
RETURNS TABLE (i INT) AS $$
BEGIN
    FOR i IN 1..p_n LOOP
        RETURN NEXT;  -- 把 i 加到结果集
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

`RETURN NEXT` 不是真正的流水线（结果会先收集到内存），但在循环中累加结果时语法更清晰。

### LANGUAGE SQL 的内联展开

PostgreSQL 12+ 对简单的 LANGUAGE SQL 函数（无 SECURITY DEFINER、稳定函数体）会**自动内联**到查询计划中：

```sql
-- 内联前：函数调用作为黑盒
SELECT * FROM get_orders(123) WHERE total > 100;

-- 内联后（执行计划等价于）：
SELECT order_id, total_amount AS total
FROM orders
WHERE customer_id = 123 AND total_amount > 100;
```

效果：可以利用索引、与外部 WHERE 合并优化，性能等同于直接写子查询。

## 与 LATERAL JOIN 的协同

TVF 与 LATERAL 是天作之合：LATERAL 让 TVF 的参数引用外部表的列。

```sql
-- 标准语法 (PostgreSQL/MySQL/Oracle/DB2)
SELECT c.name, o.order_id, o.total
FROM customers c
CROSS JOIN LATERAL get_orders(c.customer_id) AS o;

-- SQL Server (CROSS APPLY 等价于 LATERAL)
SELECT c.name, o.order_id, o.total
FROM customers c
CROSS APPLY dbo.GetOrders(c.customer_id) AS o;

-- BigQuery (隐式 LATERAL)
SELECT c.name, o.order_id, o.total
FROM customers c, dataset.get_orders(c.customer_id) AS o;

-- Snowflake (LATERAL FLATTEN 类似)
SELECT c.name, f.value
FROM customers c, LATERAL FLATTEN(input => c.tags) f;

-- Spark SQL / Hive (LATERAL VIEW)
SELECT c.id, t.tag
FROM customers c LATERAL VIEW explode(c.tags) t AS tag;

-- Trino (CROSS JOIN UNNEST 隐式)
SELECT c.id, t.tag
FROM customers c CROSS JOIN UNNEST(c.tags) AS t(tag);
```

不带 LATERAL 调用 TVF 时，函数参数必须是常量或外部参数：

```sql
-- 合法：常量参数
SELECT * FROM get_orders(123);

-- 非法：引用其他表的列（在没有 LATERAL/APPLY 时）
SELECT * FROM customers c, get_orders(c.customer_id);  -- PostgreSQL 9.3+ 自动加 LATERAL
```

## 内置 TVF 实战示例

### 字符串拆分对比

```sql
-- SQL Server 2016+
SELECT value FROM STRING_SPLIT('a,b,c,d', ',');

-- SQL Server 2022+ (带序号)
SELECT value, ordinal FROM STRING_SPLIT('a,b,c,d', ',', 1);

-- PostgreSQL
SELECT regexp_split_to_table('a,b,c,d', ',');
SELECT string_to_table('a,b,c,d', ',');  -- 14+

-- Snowflake
SELECT value FROM TABLE(STRTOK_SPLIT_TO_TABLE(1, 'a,b,c,d', ','));

-- BigQuery
SELECT value FROM UNNEST(SPLIT('a,b,c,d', ',')) AS value;

-- ClickHouse
SELECT arrayJoin(splitByChar(',', 'a,b,c,d'));

-- DuckDB
SELECT unnest(string_split('a,b,c,d', ','));

-- Trino
SELECT * FROM UNNEST(split('a,b,c,d', ',')) AS t(value);
SELECT * FROM TABLE(split_to_rows(input => 'a,b,c,d', delimiter => ','));
```

### JSON 数组展开对比

```sql
-- SQL Server (OPENJSON)
SELECT id, name FROM OPENJSON('[{"id":1,"name":"a"}]')
WITH (id INT, name VARCHAR(50));

-- MySQL 8.0+ / MariaDB 10.6+ (JSON_TABLE)
SELECT id, name FROM JSON_TABLE(
    '[{"id":1,"name":"a"}]',
    '$[*]' COLUMNS (id INT PATH '$.id', name VARCHAR(50) PATH '$.name')
) AS jt;

-- PostgreSQL (jsonb_to_recordset)
SELECT id, name FROM jsonb_to_recordset('[{"id":1,"name":"a"}]'::jsonb)
AS x(id INT, name TEXT);

-- Oracle 12c+ (JSON_TABLE, SQL:2016)
SELECT * FROM JSON_TABLE(
    '[{"id":1,"name":"a"}]',
    '$[*]' COLUMNS (id NUMBER PATH '$.id', name VARCHAR2(50) PATH '$.name')
);

-- Snowflake (LATERAL FLATTEN)
SELECT f.value:id::INT, f.value:name::STRING
FROM TABLE(GENERATOR(ROWCOUNT => 1)) g,
LATERAL FLATTEN(input => PARSE_JSON('[{"id":1,"name":"a"}]')) f;

-- BigQuery (JSON_EXTRACT_ARRAY + UNNEST)
SELECT JSON_EXTRACT_SCALAR(item, '$.id') AS id,
       JSON_EXTRACT_SCALAR(item, '$.name') AS name
FROM UNNEST(JSON_EXTRACT_ARRAY('[{"id":1,"name":"a"}]')) AS item;
```

### 序列生成对比

```sql
-- PostgreSQL / DuckDB / Greenplum
SELECT * FROM generate_series(1, 10);

-- ClickHouse
SELECT number FROM numbers(10);

-- Trino / Presto
SELECT * FROM UNNEST(sequence(1, 10)) AS t(n);
SELECT * FROM TABLE(sequence(start => 1, stop => 10));  -- Trino 414+

-- BigQuery
SELECT n FROM UNNEST(GENERATE_ARRAY(1, 10)) AS n;

-- Snowflake
SELECT SEQ4() FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- Oracle (递归)
SELECT LEVEL FROM DUAL CONNECT BY LEVEL <= 10;

-- SQL Server (递归 CTE)
WITH n (i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10)
SELECT i FROM n OPTION (MAXRECURSION 0);

-- H2
SELECT * FROM SYSTEM_RANGE(1, 10);
```

## 对引擎开发者的实现建议

### 1. 内联 TVF 的展开优化

最重要的设计决策：**简单 TVF 应可被优化器内联展开为子查询**。

```
内联展开流程:
  CREATE FUNCTION fn(p) RETURNS TABLE AS $$ SELECT ... FROM t WHERE k = p $$;
  SELECT * FROM fn(42) WHERE c > 0;
  ↓ 内联
  SELECT * FROM (SELECT ... FROM t WHERE k = 42) sub WHERE c > 0;
  ↓ 谓词下推
  SELECT ... FROM t WHERE k = 42 AND c > 0;  -- 用索引
```

实现要点：
- 函数体必须是单一 SELECT（无控制流）
- 函数稳定性 (`IMMUTABLE` / `STABLE`) 要满足
- 替换函数参数为实参，递归替换嵌套调用
- PostgreSQL 自 12 起对 LANGUAGE SQL 函数自动内联

### 2. 多语句 TVF 的执行模型

多语句 TVF 不能内联，必须实例化中间表：

```
执行流程:
  1. 进入函数边界，创建临时表 / 内存集合 (返回表变量)
  2. 执行函数体语句，每个 INSERT 追加到返回表
  3. 函数 RETURN 后，返回表作为虚拟表参与外部查询
```

性能关键：
- **基数估算**：传统多语句 TVF 估算困难，导致优化器选错 JOIN 算法
- 解决方案：
  - 间隔执行（SQL Server 2017+）：第一次执行后用真实行数重新优化
  - 行数提示：PostgreSQL 的 `ROWS` 子句让用户给优化器提示
  - 自适应 JOIN：运行时根据真实行数切换 nested loop / hash join

### 3. 流水线表函数的实现

Oracle 风格的 PIPE ROW 流式实现可以避免中间集合的内存开销：

```rust
// 伪代码：流水线 TVF 的迭代器接口
struct PipelinedTVF {
    state: TVFExecutionState,
    coroutine: Coroutine,  // 函数体作为协程
}

impl Iterator for PipelinedTVF {
    fn next(&mut self) -> Option<Row> {
        // 协程驱动到下一个 PIPE ROW
        match self.coroutine.resume() {
            Yielded(row) => Some(row),     // PIPE ROW 产生一行
            Completed => None,              // 函数 RETURN
        }
    }
}
```

实现关键：
- 函数体作为协程 / 生成器执行
- `PIPE ROW` 等价于协程的 `yield`
- 内存复杂度 O(1)（独立于结果总行数）
- 调用方第一行立即可见（低延迟）

### 4. PTF 的 schema 推断

SQL:2016 PTF 最大的实现挑战：**输出 schema 在调用时动态决定**。

```
两阶段调用模型:
  阶段 1 (DESCRIBE/分析期):
    - 收集表参数的 schema、标量参数值、PARTITION BY/ORDER BY 列
    - PTF 实现返回输出 schema 描述 (列名、类型)
    - 优化器据此校验外部查询并生成执行计划

  阶段 2 (FETCH/执行期):
    - PTF 接收输入数据流 (按 PARTITION 分组)
    - 实现 process(row) 处理逐行 / process_partition(rows) 处理批
    - 输出符合阶段 1 声明 schema 的行
```

设计要点：
- 输入参数的"语义角色"区分：表参数有 PARTITION/ORDER 选项，标量参数没有
- 列描述符（DESCRIPTOR）允许 PTF 接收"列名列表"作为参数
- COPARTITION 子句要求多个表参数按相同列分区（用于关联分析）

### 5. UDTF 与执行引擎集成

Snowflake / Spark 风格 UDTF 的运行时 API：

```python
# 类似 Spark UDTF 的接口
class MyUDTF:
    def __init__(self):
        # 初始化 (每个分区一次)
        pass

    def process(self, *args):
        # 处理一行输入
        for output_row in compute(args):
            yield output_row    # 输出一行

    def end_partition(self):
        # 分区结束时调用 (聚合输出)
        for final_row in flush():
            yield final_row
```

实现要点：
- **进程隔离**：UDTF 在沙箱进程中执行（Python: PySpark 的 worker 进程；JavaScript: V8 隔离）
- **数据序列化**：跨进程传输用 Arrow / Protobuf 等高效格式
- **失败处理**：UDTF 异常应可被 SQL 层捕获并附加诊断信息
- **资源限制**：CPU 时间、内存、临时文件大小都需限制

### 6. 与查询优化器的交互

TVF 给优化器带来三类挑战：

```
1. 行数估计:
   - 内联 TVF: 与子查询完全相同处理
   - 多语句 TVF: 需要 ROWS 提示或运行时反馈
   - PTF: 通常无法估计，依赖经验值

2. 谓词下推:
   - 内联 TVF: 可下推到函数体内的 WHERE
   - 多语句 TVF: 不可（函数边界保护）
   - PTF: 取决于 PTF 是否声明"过滤友好"

3. 投影下推 (列裁剪):
   - 内联 TVF: 自动支持
   - 多语句 TVF: 需要输出完整 schema (浪费)
   - SQL:2016 PTF: 通过 KEEP WHEN 子句和 prune semantics 支持
```

### 7. 函数缓存与稳定性

```sql
-- 函数稳定性影响优化器是否可以缓存调用
-- IMMUTABLE: 同输入永远同输出 (可缓存, 可常量折叠)
-- STABLE:    同输入在单查询内同输出 (可缓存)
-- VOLATILE:  每次调用可能不同 (不可缓存)

CREATE FUNCTION pure_tvf(p INT) RETURNS TABLE (...) AS $$
    SELECT ... WHERE k = p
$$ LANGUAGE SQL IMMUTABLE;   -- 优化器可缓存结果

CREATE FUNCTION read_tvf() RETURNS TABLE (...) AS $$
    SELECT * FROM users WHERE last_login > now() - INTERVAL '1 hour'
$$ LANGUAGE SQL STABLE;       -- 单查询内缓存
```

引擎实现需正确传播稳定性：包含 VOLATILE 子调用的函数自身必须 VOLATILE。

### 8. 错误处理与诊断

TVF 错误信息应包含：
- 函数名、参数值、调用位置
- 函数体内出错的行号（如可能）
- 嵌套调用栈（TVF 调用 TVF）

```
ERROR: division by zero
  in function get_ratio (called at orders_view.sql:42)
    -> at function compute_pct (line 5)
       SELECT a / b FROM ...    -- b 为 0
```

### 9. 与列存 / 向量化的协作

向量化引擎中 TVF 的实现：

```
1. UDTF 接受批 (Vector / RecordBatch) 而非逐行
   - 提高吞吐：减少函数调用开销
   - SIMD 友好：批内可向量化处理

2. 流水线: TVF 也应支持产出批，下游算子按批消费

3. 列裁剪: PTF 应能在 DESCRIBE 阶段知道"哪些列被消费"，跳过未用列的传输
```

### 10. 安全与权限

```
1. 函数调用权限: USAGE on schema + EXECUTE on function
2. 函数所有者权限: SECURITY DEFINER vs SECURITY INVOKER
3. 资源限制: TVF 不应能消耗无限内存 / CPU
4. 注入攻击防御: 动态 SQL 在 TVF 中要参数化
```

## 关键发现

1. **SQL Server 是 TVF 概念的开拓者**：自 2000 年同时支持内联 TVF 和多语句 TVF，至今仍是该模式最完整的实现。

2. **Oracle 流水线函数是流式 TVF 的范本**：自 2001 年的 9i 引入 `PIPE ROW`，定义了"边生成边输出"的语义，影响了后续所有引擎的 SRF 设计。

3. **PostgreSQL 用 SRF 概念统一了所有返回多行的函数**：`RETURNS TABLE` / `RETURNS SETOF` / `RETURN QUERY` / `RETURN NEXT` 提供多种语法，覆盖从内联到流式的所有场景。

4. **MySQL 至今没有真正的 TVF**：是主流关系数据库中唯一的"洼地"，需要靠存储过程、视图、JSON_TABLE 模拟。

5. **DB2 是 SQL 标准 TVF 最忠实的实现者**：自 v8 起严格遵循 `CREATE FUNCTION ... RETURNS TABLE`，11.5 起部分支持 SQL:2016 PTF。

6. **BigQuery 直到 2020 年才有 TVF**：作为现代分析数据库的重要短板，新增 SQL TVF 后大幅增强了 reusability。

7. **ClickHouse 表函数是 PTF 的"事实实现"**：虽不遵循 SQL:2016 语法，但 `file()`/`url()`/`mysql()`/`s3()` 体系实质满足 PTF 的多态性、表参数、动态 schema 三大特征。

8. **Snowflake 的 JavaScript/Python UDTF 让 TVF 成为通用扩展机制**：用户可以用熟悉语言实现复杂逻辑，而不局限于 SQL 表达式。

9. **Trino 414（2023）是少数严格按 SQL:2016 PTF 实现的引擎**：包括 DESCRIPTOR 类型参数、PARTITION BY、COPARTITION 等完整语义，为分析引擎树立标准。

10. **Spark SQL / Hive 的 LATERAL VIEW + UDTF 是大数据生态的事实标准**：`explode`、`posexplode`、`stack` 配合 LATERAL VIEW 已成大数据 SQL 的"原生模式"。

11. **基数估算是多语句 TVF 的最大痛点**：SQL Server 2014 前默认 1 行，2014 改 100 行，2017 引入间隔执行才根本缓解。所有支持多语句 TVF 的引擎都要面对这个问题。

12. **内联 TVF 与子查询本质等价**：现代优化器（PostgreSQL 12+, SQL Server, Oracle）都能把内联 TVF 展开为查询树的一部分，让其与外部查询合并优化。

13. **TVF + LATERAL 是分析查询的核心组合**：从 Top-N per group 到 JSON 展开，从字符串拆分到时间序列填充，TVF + LATERAL 把过程逻辑融入声明式查询。

14. **PTF 落地缓慢的原因**：SQL:2016 PTF 需要引擎深度改造（schema 动态推断、表参数语义、PARTITION/COPARTITION），实现成本高于其他扩展。Oracle 19c、DB2 11.5、Trino 414 是为数不多的实现者。

15. **CockroachDB / TiDB 等"PG 兼容"分布式 NewSQL 都缺少 TVF**：因为分布式执行下函数体执行位置（leader/follower/coordinator）和事务语义复杂。

16. **流式数据库（Materialize / RisingWave）也缺少用户定义 TVF**：因为流上的 TVF 需要处理迟到数据、回撤等复杂语义，目前主要靠内置 TVF (UNNEST, generate_series)。

17. **嵌入式数据库的差异**：SQLite 通过虚拟表 (Virtual Table) API 支持自定义 TVF（`json_each`, `generate_series`）；H2 通过 Java 函数支持；DuckDB 通过 C++ 扩展支持。

## 总结对比矩阵

### 完整能力总览

| 引擎 | 内联 TVF | 多语句 TVF | 流式 (PIPE/yield) | PTF | 用户定义 | LATERAL 协同 |
|------|---------|-----------|------------------|-----|---------|-------------|
| SQL Server | 是 (2000+) | 是 (2000+) | 否 | 否 | 是 | `CROSS APPLY` |
| Oracle | 通过视图 | PL/SQL | `PIPELINED` (9i+) | 19c+ | 是 | `LATERAL`/`APPLY` |
| PostgreSQL | LANGUAGE SQL | PL/pgSQL | `RETURN NEXT` | 否 | 是 | `LATERAL` |
| DB2 | 是 (v8+) | LANGUAGE SQL | 否 | 11.5+ | 是 | `LATERAL` |
| MySQL | -- | 存储过程 | 否 | 否 | -- | `LATERAL` 8.0.14+ |
| Snowflake | SQL UDF | JS/Python UDTF | 是 (生成器) | 否 | 是 | `LATERAL FLATTEN` |
| BigQuery | 2020+ | 否 | 否 | 否 | SQL only | `UNNEST` |
| ClickHouse | 否 | 否 | 否 | 表函数 | 否 (源码) | `ARRAY JOIN` |
| Trino | 否 | 否 | 否 | 414+ (2023) | 插件 | `UNNEST` |
| Spark SQL | UDF | UDTF | UDTF (yield) | 否 | 是 | `LATERAL VIEW` |
| Hive | 是 | UDTF | UDTF | 否 | 是 | `LATERAL VIEW` |
| Vertica | 是 | UDx | UDx | 否 | 是 | `LATERAL` |
| Flink SQL | 是 | TableFunction | TableFunction | 否 | 是 | `LATERAL TABLE` |
| Greenplum | 继承 PG | 继承 PG | 继承 PG | 否 | 是 | `LATERAL` |
| CockroachDB | 否 | 否 | 否 | 否 | 否 | `LATERAL` |
| TiDB | 否 | 否 | 否 | 否 | 否 | `LATERAL` 6.5+ |

### 引擎选型建议

| 场景 | 推荐引擎/方法 | 原因 |
|------|-------------|------|
| 高性能内联 TVF | SQL Server 内联 TVF / PG LANGUAGE SQL | 内联展开，与查询合并优化 |
| 复杂业务逻辑 TVF | Snowflake Python UDTF / Spark UDTF | 完整编程语言，沙箱执行 |
| 流式逐行输出 | Oracle 流水线函数 | 低延迟、内存 O(1) |
| 跨数据源接入 | ClickHouse 表函数 / Trino PTF | 内置远程查询能力 |
| 大批量数据展开 | Spark `explode` / Hive `LATERAL VIEW` | 分布式向量化执行 |
| 标准兼容性 | DB2 / Oracle / Trino 414 | 严格遵循 SQL 标准 |
| PostgreSQL 生态 | PG / Greenplum / TimescaleDB / YugabyteDB | 统一 SRF 模型 |

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-4 (SQL/PSM, Procedure Returning Table)
- SQL:2016 标准: ISO/IEC 9075-2 Section 18 (Polymorphic Table Functions)
- SQL Server: [Create User-defined Functions](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/create-user-defined-functions-database-engine)
- SQL Server: [STRING_SPLIT](https://learn.microsoft.com/en-us/sql/t-sql/functions/string-split-transact-sql)
- Oracle: [Pipelined Table Functions](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-optimization-and-tuning.html#GUID-3B47E1AB-29CC-4E33-A95B-B1A7AD6DD2A2)
- Oracle: [Polymorphic Table Functions](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-optimization-and-tuning.html#GUID-4DF1AF9B-C22A-4CCB-A1FF-AE2B91FB4B7C)
- PostgreSQL: [Set Returning Functions](https://www.postgresql.org/docs/current/functions-srf.html)
- PostgreSQL: [Inlining of SQL Functions](https://wiki.postgresql.org/wiki/Inlining_of_SQL_functions)
- DB2: [CREATE FUNCTION (SQL table)](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-function-sql-scalar-table-row)
- Snowflake: [User-Defined Table Functions](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-tabular-functions)
- BigQuery: [Table-valued functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/table-functions)
- ClickHouse: [Table Functions](https://clickhouse.com/docs/en/sql-reference/table-functions)
- Trino: [Table Functions](https://trino.io/docs/current/functions/table.html)
- Spark SQL: [Python UDTFs](https://spark.apache.org/docs/latest/api/python/user_guide/sql/python_udtf.html)
- Hive: [LanguageManual UDF](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-Built-inTable-GeneratingFunctions(UDTF))
- Flink SQL: [Table Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/udfs/#table-functions)
- Vertica: [User-Defined Transform Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/ExtendingHPVertica/UDx/TransformFunctions/TransformFunctions.htm)
- 相关文章: [集合返回函数 (SRF)](set-returning-functions.md), [LATERAL JOIN](lateral-join.md), [采样查询](sampling-query.md)

# ClickHouse: 存储过程和函数

> 参考资料:
> - [1] ClickHouse - User-Defined Functions
>   https://clickhouse.com/docs/en/sql-reference/statements/create/function
> - [2] ClickHouse SQL Reference - Functions
>   https://clickhouse.com/docs/en/sql-reference/functions


 ClickHouse 不支持存储过程
 使用用户定义函数（UDF）和查询管道替代

## SQL 用户定义函数（Create Function，21.10+）


Lambda 风格的 UDF

```sql
CREATE FUNCTION full_name AS (first, last) -> concat(first, ' ', last);
SELECT full_name('Alice', 'Smith');

CREATE FUNCTION add_tax AS (price) -> price * 1.1;
SELECT add_tax(100);

```

带条件的 UDF

```sql
CREATE FUNCTION safe_divide AS (a, b) -> if(b = 0, NULL, a / b);
SELECT safe_divide(10, 3);

```

多参数

```sql
CREATE FUNCTION clamp AS (val, min_val, max_val) ->
    greatest(min_val, least(max_val, val));
SELECT clamp(150, 0, 100);

```

删除

```sql
DROP FUNCTION IF EXISTS full_name;

```

## 可执行 UDF（Executable UDF，21.11+）


 通过配置文件定义，调用外部可执行程序
 在 /etc/clickhouse-server/config.d/ 创建 XML 配置

 <function>
     <type>executable</type>
     <name>my_python_func</name>
     <return_type>String</return_type>
     <argument><type>String</type></argument>
     <format>TabSeparated</format>
     <command>python3 /opt/scripts/process.py</command>
 </function>

 使用
 SELECT my_python_func(username) FROM users;

## 字典（Dictionary，UDF 替代方案）


字典可以用于维度查找，替代 UDF 中的查表逻辑

```sql
CREATE DICTIONARY country_codes (
    code String,
    name String
)
PRIMARY KEY code
SOURCE(HTTP(URL 'http://example.com/countries.csv' FORMAT 'CSVWithNames'))
LAYOUT(FLAT())
LIFETIME(3600);

```

使用字典查找

```sql
SELECT dictGet('country_codes', 'name', 'US');

```

## 物化视图（替代存储过程的 ETL 逻辑）


物化视图在数据插入时自动触发计算

```sql
CREATE MATERIALIZED VIEW daily_summary
ENGINE = SummingMergeTree()
ORDER BY (date, user_id) AS
SELECT
    toDate(order_date) AS date,
    user_id,
    sum(amount) AS total,
    count() AS cnt
FROM orders
GROUP BY date, user_id;

```

 插入到 orders 时，daily_summary 自动更新

## 参数化视图（Parameterized View，不是真正的视图）


通过 CREATE VIEW + 替换参数模拟

```sql
CREATE VIEW user_orders AS
SELECT * FROM orders WHERE user_id = {user_id:UInt64};

```

使用时传参

```sql
SELECT * FROM user_orders(user_id = 123);

```

## 查询管道（替代复杂存储过程）


使用 INSERT INTO ... SELECT 串联处理步骤
使用 WITH (CTE) 组织复杂查询逻辑


```sql
WITH filtered AS (
    SELECT * FROM orders WHERE order_date >= '2024-01-01'
),
aggregated AS (
    SELECT user_id, sum(amount) AS total FROM filtered GROUP BY user_id
)
INSERT INTO user_totals
SELECT * FROM aggregated;

```

注意：ClickHouse 没有存储过程
注意：SQL UDF 只支持 lambda 表达式，不支持过程式逻辑
注意：复杂逻辑通过物化视图、字典和外部编排实现
注意：可执行 UDF 可以调用 Python/Shell 等外部程序
注意：ClickHouse 设计理念是快速分析查询，不是事务处理


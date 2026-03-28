# StarRocks: JOIN

> 参考资料:
> - [1] StarRocks Documentation - JOIN
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 标准 JOIN (与 Doris 完全兼容)

```sql
SELECT u.username, o.amount FROM users u INNER JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
SELECT u.* FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id;
SELECT u.* FROM users u LEFT ANTI JOIN orders o ON u.id = o.user_id;

```

## 2. 分布式 JOIN 策略

 与 Doris 相同: Broadcast / Shuffle / Bucket Shuffle / Colocate

## 3. Global Runtime Filter (StarRocks 优势)

 StarRocks 的 Runtime Filter 是全局的(跨 Fragment 广播)。
 Doris 的 Runtime Filter 早期只在本地 Fragment 内。
 SET enable_global_runtime_filter = true;

## 4. ASOF JOIN (4.0+，StarRocks 独有)

 按时间最近匹配 JOIN——时序数据的杀手级功能:
 SELECT t.*, q.price
 FROM trades t ASOF JOIN quotes q
 ON t.symbol = q.symbol AND t.trade_time >= q.quote_time;

 ASOF JOIN 匹配每条 trade 对应的"最近之前"的 quote。
 对比: ClickHouse 也支持 ASOF JOIN(更早实现)。
 Doris: 不支持(需要用窗口函数 + 子查询模拟)。

## 5. QUALIFY (3.2+，StarRocks 独有)

 窗口函数的过滤子句(不需要子查询):
 SELECT username, city, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
 FROM users
 QUALIFY rn <= 3;

 对比: Doris 不支持(需要子查询包装)。
 对比: BigQuery/Snowflake 都支持 QUALIFY。

## 6. StarRocks vs Doris JOIN 差异

Global Runtime Filter: StarRocks 更成熟
ASOF JOIN:            StarRocks 4.0+(独有)
QUALIFY:              StarRocks 3.2+(独有)
Colocate JOIN:        两者都支持(同源)
SEMI/ANTI JOIN:       两者都支持(同源)


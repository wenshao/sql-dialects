# MySQL 兼容引擎开发指南

如果你在开发一个 MySQL 兼容引擎（如 TiDB、OceanBase、PolarDB、StarRocks、Doris），本文档帮助你了解 MySQL 语法中最关键的设计决策和最容易踩的坑。

## 兼容性分级

不是所有 MySQL 特性都值得兼容。按优先级分三级：

### P0: 必须兼容（用户最常用、不兼容会报错）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| CREATE TABLE + 数据类型 | [ddl/create-table/mysql.sql](../ddl/create-table/mysql.sql) | utf8 vs utf8mb4、UNSIGNED 废弃趋势 |
| INSERT/UPDATE/DELETE | [dml/insert/mysql.sql](../dml/insert/mysql.sql) | INSERT ... SET 是 MySQL 独有语法 |
| SELECT + JOIN + WHERE | [query/joins/mysql.sql](../query/joins/mysql.sql) | 不支持 FULL OUTER JOIN |
| AUTO_INCREMENT | [ddl/sequences/mysql.sql](../ddl/sequences/mysql.sql) | lock_mode、重启回退(5.7)、id 跳跃 |
| ON DUPLICATE KEY UPDATE | [dml/upsert/mysql.sql](../dml/upsert/mysql.sql) | 死锁风险、VALUES() 废弃 |
| 事务 + 隔离级别 | [advanced/transactions/mysql.sql](../advanced/transactions/mysql.sql) | 默认 RR（不是 RC）、间隙锁 |

### P1: 应该兼容（常用但有替代方案）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| 窗口函数 (8.0+) | [query/window-functions/mysql.sql](../query/window-functions/mysql.sql) | 默认帧 RANGE 不是 ROWS |
| CTE (8.0+) | [query/cte/mysql.sql](../query/cte/mysql.sql) | MySQL 总是物化 CTE |
| JSON 类型 (5.7+) | [types/json/mysql.sql](../types/json/mysql.sql) | 二进制存储、->>/-> 运算符 |
| 存储过程 | [advanced/stored-procedures/mysql.sql](../advanced/stored-procedures/mysql.sql) | DELIMITER 是客户端概念 |
| EXPLAIN | [advanced/explain/mysql.sql](../advanced/explain/mysql.sql) | 格式差异大 |

### P2: 可以不兼容（低频或有更好的替代）

| 特性 | 关键文件 | 说明 |
|------|---------|------|
| 触发器 | [advanced/triggers/mysql.sql](../advanced/triggers/mysql.sql) | 分布式引擎通常不支持 |
| 存储引擎选择 | [ddl/create-table/mysql.sql](../ddl/create-table/mysql.sql) | ENGINE=InnoDB 忽略即可 |
| REPLACE INTO | [dml/upsert/mysql.sql](../dml/upsert/mysql.sql) | 推荐用 ON DUPLICATE KEY 代替 |
| 全文索引 | [query/full-text-search/mysql.sql](../query/full-text-search/mysql.sql) | 通常由外部搜索引擎处理 |

## MySQL 最大的 10 个坑

按"兼容引擎最容易忽略"排序：

### 1. AUTO_INCREMENT 语义复杂度

详见 [ddl/sequences/mysql.sql](../ddl/sequences/mysql.sql)

- `innodb_autoinc_lock_mode` 有三种模式，行为不同
- INSERT ... ON DUPLICATE KEY UPDATE 即使执行 UPDATE 也消耗自增值（id 跳跃）
- 批量 INSERT 的 id 分配在 mode=2 下不连续
- 5.7 重启后自增值可能回退（8.0 修复）
- **分布式引擎的选择**: AUTO_RANDOM（TiDB）或段分配

### 2. ONLY_FULL_GROUP_BY 行为差异

详见 [functions/aggregate/mysql.sql](../functions/aggregate/mysql.sql)

- 5.7.5+ 默认启用，之前默认关闭
- 大量存量 SQL 依赖非严格 GROUP BY
- 需要实现 functional dependency 检测
- ANY_VALUE() 函数作为逃生阀

### 3. utf8 不是 UTF-8

详见 [types/string/mysql.sql](../types/string/mysql.sql)

- MySQL 的 `utf8` 只支持 3 字节（BMP），不支持 emoji
- 真正的 UTF-8 需要用 `utf8mb4`
- 兼容引擎可以让 utf8 = utf8mb4，但要注意索引长度计算的差异

### 4. || 是逻辑 OR

详见 [functions/string-functions/mysql.sql](../functions/string-functions/mysql.sql)

- MySQL 中 `||` 是逻辑 OR，不是字符串拼接
- PostgreSQL/Oracle 中 `||` 是拼接
- `PIPES_AS_CONCAT` 模式可以改变这个行为
- Parser 需要根据 sql_mode 切换

### 5. DATETIME vs TIMESTAMP 时区行为

详见 [types/datetime/mysql.sql](../types/datetime/mysql.sql)

- DATETIME 不转换时区，TIMESTAMP 自动转换
- TIMESTAMP 有 2038 年问题（4 字节有符号整数）
- ON UPDATE CURRENT_TIMESTAMP 是 MySQL 独有

### 6. CHECK 约束历史

详见 [ddl/constraints/mysql.sql](../ddl/constraints/mysql.sql)

- 5.7 及之前：解析 CHECK 语法但不执行（最差的设计选择）
- 8.0.16+：真正执行
- 兼容引擎的选择：要么执行，要么报语法错误，不要静默忽略

### 7. 隐式类型转换

详见 [types/numeric/mysql.sql](../types/numeric/mysql.sql)

- MySQL 的隐式转换极其宽松（`'123abc' + 0 = 123`）
- 字符串和数字比较时，字符串转为数字（可能导致索引失效）
- PostgreSQL 完全不允许隐式转换，Oracle/SQL Server 有限允许

### 8. DDL 隐式提交

详见 [advanced/transactions/mysql.sql](../advanced/transactions/mysql.sql)

- CREATE TABLE/ALTER TABLE 等 DDL 会隐式提交当前事务
- PostgreSQL/SQL Server 的 DDL 是事务性的（可回滚）
- 分布式引擎的 DDL 通常也是非事务性的

### 9. LIMIT 语法位置

详见 [query/pagination/mysql.sql](../query/pagination/mysql.sql)

- MySQL 的 LIMIT 在 UPDATE/DELETE 中也可用（MySQL 独有）
- 深分页 LIMIT 100000, 10 性能极差（O(offset)）
- 不支持 SQL 标准的 OFFSET ... FETCH

### 10. GROUP_CONCAT 默认截断

详见 [functions/aggregate/mysql.sql](../functions/aggregate/mysql.sql)

- 默认 `group_concat_max_len = 1024`，超过静默截断
- 不报错不警告，生产中非常容易出问题
- 其他引擎（STRING_AGG/LISTAGG）通常没有这个限制

## 兼容族中其他引擎的差异点

| 引擎 | 关键差异 | 参考文件 |
|------|---------|---------|
| TiDB | AUTO_RANDOM、无触发器(全版本)、乐观/悲观事务 | [dialects/tidb.md](../dialects/tidb.md) |
| OceanBase | 双模(MySQL+Oracle)、tablegroup、locality | [dialects/oceanbase.md](../dialects/oceanbase.md) |
| PolarDB | 全局索引、广播表、AUTO 分区 | [dialects/polardb.md](../dialects/polardb.md) |
| TDSQL | shardkey 分片、两级分区 | [dialects/tdsql.md](../dialects/tdsql.md) |
| StarRocks | 4 种数据模型、DISTRIBUTED BY | [dialects/starrocks.md](../dialects/starrocks.md) |
| Doris | 同 StarRocks 同源 | [dialects/doris.md](../dialects/doris.md) |
| MariaDB | SEQUENCE(10.3+)、系统版本表、RETURNING | [dialects/mariadb.md](../dialects/mariadb.md) |

# Apache Impala: 动态 SQL (Dynamic SQL)

> 参考资料:
> - [Apache Impala SQL Language Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Apache Impala Shell Guide](https://impala.apache.org/docs/build/html/topics/impala_impala_shell.html)
> - [Apache Impala JDBC Driver](https://impala.apache.org/docs/build/html/topics/impala_jdbc.html)
> - [impyla Python Client](https://github.com/cloudera/impyla)


## 1. Impala 的动态 SQL 模型


Impala 不支持服务端动态 SQL:
无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
无存储过程 / 用户自定义函数（UDAF/UDF 是 Java/C++ 实现）
无会话级变量或控制流

Impala 的设计定位:
面向 Hadoop 生态的交互式 OLAP 引擎。
查询由 Impalad 协调节点接收，分发到工作节点执行。
动态 SQL 需要在应用层或客户端工具中实现。

## 2. impala-shell: 变量替换


impala-shell 支持 --var 参数实现简单的变量替换

命令行传参:
impala-shell --var=table_name=users --var=min_age=25 \
-q "SELECT * FROM \${var:table_name} WHERE age > \${var:min_age}"

在脚本中使用变量:
impala-shell --var=db=analytics --var=year=2026 \
-f query_template.sql

query_template.sql 内容:
SELECT * FROM ${var:db}.orders_${var:year}
WHERE order_date >= '${var:year}-01-01'
AND order_date < '${var:year}-12-31';

impala-shell 变量的限制:
仅支持简单字符串替换（无类型检查）。
变量在 SQL 发送到 Impala 之前被替换（预处理阶段）。
不支持条件逻辑或循环。
适合批量脚本，不适合复杂动态逻辑。

## 3. Python 替代方案: impyla


from impala.dbapi import connect
from impala.util import as_pandas

conn = connect(host='localhost', port=21050)
cursor = conn.cursor()

-- 参数化查询（impyla 的参数替换是客户端的字符串替换）
cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- 动态表名（需要手动验证）
table = 'users'
cursor.execute(f'SELECT COUNT(*) FROM {table}')

-- 动态 SQL 构建函数
def build_query(table, columns, where_clause, limit=100):
"""安全的动态查询构建器"""
valid_tables = {'users', 'orders', 'products'}
if table not in valid_tables:
raise ValueError(f'Invalid table: {table}')
col_str = ', '.join(columns) if columns else '*'
sql = f'SELECT {col_str} FROM {table}'
if where_clause:
sql += f' WHERE {where_clause}'
if limit:
sql += f' LIMIT {int(limit)}'
return sql

-- 使用构建器
sql = build_query('users', ['id', 'name', 'age'], 'age > 18', 50)
cursor.execute(sql)
df = as_pandas(cursor)

impyla 参数化机制说明:
cursor.execute(sql, params) 中 %s 占位符在客户端被替换为字面量。
这不是真正的服务端预处理，仅提供基本便利。
安全性仍需在应用层保证。

## 4. JDBC 替代方案: Java


import java.sql.*;

String url = "jdbc:impala://localhost:21050;AuthMech=0";
try (Connection conn = DriverManager.getConnection(url)) {
// PreparedStatement（Impala 驱动内部实现参数化）
String sql = "SELECT * FROM users WHERE age > ? AND status = ?";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
ps.setInt(1, 18);
ps.setString(2, "active");
try (ResultSet rs = ps.executeQuery()) {
while (rs.next()) {
// 处理结果
}
}
}
}

Impala JDBC PreparedStatement 行为:
驱动在客户端将 ? 替换为参数值，发送完整 SQL 到 Impala。
这不是服务端预处理，但对开发者来说接口一致。
安全性由驱动处理基本的类型转换和转义。

## 5. SQL 注入防护


由于 Impala 缺少服务端预处理，注入防护需要额外注意:

策略 1: 白名单验证（推荐，适用于标识符）
valid_tables = {'users', 'orders', 'products'}
valid_columns = {'id', 'name', 'age', 'status'}
if table_name not in valid_tables:
raise ValueError(f'Invalid table: {table_name}')

策略 2: 类型强制转换（适用于值参数）
age = int(user_input)  # 非 int 会抛异常
cursor.execute(f'SELECT * FROM users WHERE age > {age}')

策略 3: 字符串转义（适用于字符串参数）
import re
def safe_string(s):
if re.match(r"^[a-zA-Z0-9_]+$", s):
return s
raise ValueError(f'Invalid input: {s}')

策略 4: 使用 JDBC PreparedStatement（让驱动处理转义）

错误（危险）: 直接拼接
cursor.execute(f"SELECT * FROM {user_table} WHERE name = '{user_input}'")

正确: 白名单 + 类型检查 + 参数化
assert table_name in valid_tables
cursor.execute('SELECT * FROM %s WHERE name = ?' % table_name, (user_input,))

## 6. 动态 DDL: 分区管理场景


Impala 常见场景: 动态管理 HDFS/Hive 分区

动态添加分区
for month in range(1, 13):
sql = f"""ALTER TABLE orders ADD IF NOT EXISTS PARTITION (year=2026, month={month:02d})
LOCATION '/data/orders/2026/{month:02d}'"""
cursor.execute(sql)

刷新分区元数据
cursor.execute('REFRESH orders')
cursor.execute('INVALIDATE METADATA')

动态创建表（根据模式推断）
cursor.execute('CREATE TABLE IF NOT EXISTS new_table LIKE existing_table')
cursor.execute('CREATE TABLE IF NOT EXISTS new_table STORED AS PARQUET AS SELECT * FROM existing_table LIMIT 0')

Impala DDL 特性:
ALTER TABLE ADD/DROP PARTITION 是最常见的动态 DDL。
REFRESH / INVALIDATE METADATA 用于同步元数据变更。
COMPUTE STATS 用于更新统计信息以优化查询计划。

## 7. 横向对比: Hadoop 生态 OLAP 引擎


1. 服务端动态 SQL 支持:
Impala:      无（应用层实现）
Hive:        有限（HiveServer2 支持 SET 变量）
Trino:       无（应用层实现）
Spark SQL:   无（DataFrame API 代替）

2. 客户端变量替换:
Impala:   impala-shell --var（简单替换）
Hive:     hive --hivevar（简单替换）
Trino:    trino CLI --variable（简单替换）
Beeline:  --hivevar（与 Hive 相同）

3. 驱动生态:
Impala:   impyla (Python) + JDBC (Java) + ODBC
Hive:     PyHive (Python) + JDBC (Java) + ODBC
Trino:    trino-python-client + JDBC + ODBC

## 8. 对引擎开发者的启示


(1) OLAP 引擎不需要完整的动态 SQL:
Impala/Hive/Trino 均不支持服务端动态 SQL。
这是因为 OLAP 查询通常由调度系统（Airflow/DolphinScheduler）发起。
动态 SQL 逻辑在 ETL 脚本（Python/Java）中实现。

(2) 变量替换是最小可行的"动态 SQL":
impala-shell --var 满足脚本化批量查询需求。
实现简单，但缺乏安全性和类型检查。
适合内部运维场景，不适合面向用户的查询服务。

(3) 驱动层 PreparedStatement 是重要的安全保障:
即使服务端不支持预处理，驱动层的参数化接口仍能防止注入。
JDBC PreparedStatement 在驱动层替换参数，对应用层透明。
这是"安全易用的 API"优于"强大的服务端功能"的例子。

## 9. 版本与限制

Impala 2.x:  impala-shell 变量替换（--var）
Impala 3.x:  JDBC PreparedStatement 支持（驱动层）
Impala 4.x:  增强的元数据管理（REFRESH 优化）
注意:        impyla 的 %s 参数化是客户端字符串替换，非服务端预处理
注意:        JDBC PreparedStatement 由驱动实现，非 Impala 服务端特性
限制:        无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
限制:        无存储过程
限制:        impala-shell 变量替换无类型检查
限制:        面向交互式 OLAP，不适合高并发动态查询服务

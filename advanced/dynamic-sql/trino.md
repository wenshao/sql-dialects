# Trino: 动态 SQL

> 参考资料:
> - [Trino Documentation - SQL Statement Syntax](https://trino.io/docs/current/sql.html)
> - [Trino Documentation - PREPARE](https://trino.io/docs/current/sql/prepare.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## PREPARE / EXECUTE / DEALLOCATE PREPARE

```sql
PREPARE user_query FROM SELECT * FROM users WHERE age > ?;
EXECUTE user_query USING 25;
DEALLOCATE PREPARE user_query;

```

多个参数
```sql
PREPARE search FROM SELECT * FROM users WHERE status = ? AND age > ?;
EXECUTE search USING 'active', 18;
DEALLOCATE PREPARE search;

```

## 应用层替代方案: Python (trino-python-client)

import trino
conn = trino.dbapi.connect(host='localhost', port=8080, catalog='hive')
cursor = conn.cursor()
cursor.execute('SELECT * FROM users WHERE age > ?', (18,))

## JDBC 替代方案

PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
ps.setInt(1, 42);
ResultSet rs = ps.executeQuery();

**注意:** Trino 支持 PREPARE / EXECUTE / DEALLOCATE PREPARE
**注意:** PREPARE 使用 ? 作为占位符
**注意:** Trino 不支持存储过程
**限制:** 无 EXECUTE IMMEDIATE
**限制:** 无存储过程或过程语言
**限制:** PREPARE 仅限当前会话

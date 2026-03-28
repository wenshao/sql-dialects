# Spanner: 动态 SQL

> 参考资料:
> - [Cloud Spanner SQL Reference](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Cloud Spanner Client Libraries](https://cloud.google.com/spanner/docs/reference/libraries)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Spanner 不支持服务端动态 SQL

Spanner 没有存储过程或 PREPARE/EXECUTE

## 应用层替代方案: 参数化查询

Spanner 所有客户端库都支持参数化查询
Python:
from google.cloud import spanner
client = spanner.Client()
instance = client.instance('my-instance')
database = instance.database('my-database')

with database.snapshot() as snapshot:
    results = snapshot.execute_sql(
        'SELECT * FROM users WHERE age > @min_age AND status = @status',
        params={'min_age': 18, 'status': 'active'},
        param_types={'min_age': spanner.param_types.INT64, 'status': spanner.param_types.STRING}
    )

## 参数化查询语法 (SQL 层面)

Spanner 使用 @param 语法
```sql
SELECT * FROM users WHERE age > @min_age AND status = @status;

```

## gcloud CLI

gcloud spanner databases execute-sql my-database \
  --instance=my-instance \
  --sql="SELECT * FROM users WHERE id = @id" \
  --params='{"id": 42}'

**注意:** Spanner 使用 @param 命名参数
**注意:** 所有动态 SQL 在应用层通过客户端库实现
**注意:** 始终使用参数化查询
**限制:** 无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
**限制:** 无存储过程

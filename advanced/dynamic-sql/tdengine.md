# TDengine: Dynamic SQL

> 参考资料:
> - [TDengine Documentation - SQL Reference](https://docs.tdengine.com/reference/sql/)
> - ============================================================
> - TDengine 不支持服务端动态 SQL
> - ============================================================
> - TDengine 是时序数据库，不支持存储过程或动态 SQL
> - ============================================================
> - 应用层替代方案: Python (taospy)
> - ============================================================
> - import taos
> - conn = taos.connect()
> - cursor = conn.cursor()
> - # 动态 SQL
> - table = 'meters'
> - cursor.execute(f'SELECT * FROM {table} WHERE ts > now - 1h')
> - # 参数化（使用 REST API）
> - import requests
> - url = 'http://localhost:6041/rest/sql'
> - requests.post(url, data='SELECT * FROM meters LIMIT 10',
> - auth=('root', 'taosdata'))
> - ============================================================
> - taos CLI
> - ============================================================
> - taos -s "SELECT COUNT(*) FROM meters"
> - taos -s "SELECT * FROM meters WHERE ts > '2024-01-01'"
> - 注意：TDengine 面向时序数据场景
> - 注意：通过应用层 SDK 或 REST API 实现动态 SQL
> - 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
> - 限制：无存储过程

# TDengine: 全文搜索

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 不支持全文搜索
> - 仅提供基本的字符串匹配功能
> - ============================================================
> - LIKE 模糊搜索
> - ============================================================
> - 基本 LIKE

```sql
SELECT * FROM log WHERE content LIKE '%error%';
```

## 前缀匹配

```sql
SELECT * FROM log WHERE content LIKE 'ERROR%';
```

## 单字符匹配

```sql
SELECT * FROM log WHERE content LIKE 'ERR_R';
```

## MATCH（正则匹配，3.0+）


## 正则表达式匹配

```sql
SELECT * FROM log WHERE content MATCH 'error|warning';
```

## 大小写不敏感（TDengine 的 MATCH 默认大小写敏感）

```sql
SELECT * FROM log WHERE content MATCH '[Ee]rror';
```

## 标签过滤（非全文搜索但高效）


## 按标签精确匹配

```sql
SELECT * FROM meters WHERE location = 'Beijing.Chaoyang';
```

## 标签 LIKE 匹配

```sql
SELECT * FROM meters WHERE location LIKE 'Beijing%';
```

## 字符串函数辅助搜索


## CONCAT + LIKE

```sql
SELECT * FROM log WHERE CONCAT(level, ':', content) LIKE '%error%database%';
```

## LENGTH 过滤

```sql
SELECT * FROM log WHERE LENGTH(content) > 100;
```

## 不支持的全文搜索功能


不支持全文索引
不支持分词
不支持相关度排序
不支持高亮显示
不支持近似搜索
不支持布尔搜索表达式

## 替代方案


方案 1：将数据同步到 Elasticsearch 进行全文搜索
方案 2：在应用层实现全文搜索逻辑
方案 3：使用标签系统代替全文搜索（推荐）
使用标签系统示例

```sql
CREATE STABLE logs (
    ts       TIMESTAMP,
    message  NCHAR(500)
) TAGS (
    level    NCHAR(10),           -- 'ERROR', 'WARN', 'INFO'
    module   NCHAR(64),           -- 'auth', 'db', 'api'
    keyword  NCHAR(100)           -- 应用层提取的关键词
);
```

## 按标签快速过滤

```sql
SELECT * FROM logs WHERE level = 'ERROR' AND module = 'db';
```

注意：TDengine 不支持全文搜索
注意：仅支持 LIKE 和 MATCH（正则）
注意：建议使用标签系统替代全文搜索
注意：高级搜索需求建议使用 Elasticsearch 等专用搜索引擎

# ksqlDB: 集合操作（有限支持）

> 参考资料:
> - [ksqlDB Documentation - Queries](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/select-pull-query/)
> - [ksqlDB Documentation - CREATE STREAM](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-stream/)
> - ============================================================
> - 注意：ksqlDB 不直接支持标准的 UNION 语法
> - 需要通过创建多个流并合并来实现类似效果
> - ============================================================
> - 模拟 UNION ALL：使用 INSERT INTO 合并多个流到一个流

```sql
CREATE STREAM all_events (
    event_id VARCHAR KEY,
    event_type VARCHAR,
    payload VARCHAR,
    event_time TIMESTAMP
) WITH (
    KAFKA_TOPIC = 'all_events',
    VALUE_FORMAT = 'JSON'
);
```

## 将多个源流写入同一目标流（等价于 UNION ALL）

```sql
INSERT INTO all_events
SELECT event_id, event_type, payload, event_time
FROM click_events;

INSERT INTO all_events
SELECT event_id, event_type, payload, event_time
FROM page_view_events;
```

## 模拟 EXCEPT：使用 LEFT JOIN + IS NULL

```sql
SELECT e.id FROM employees_stream e
LEFT JOIN terminated_stream t
    WITHIN 1 HOUR
    ON e.id = t.id
WHERE t.id IS NULL
EMIT CHANGES;
```

## 模拟 INTERSECT：使用 INNER JOIN

```sql
SELECT e.id FROM employees_stream e
INNER JOIN project_members_table p
    ON e.id = p.id
EMIT CHANGES;
```

## 注意事项

ksqlDB 是流处理引擎，不支持传统的 UNION / INTERSECT / EXCEPT
UNION ALL 可通过多个 INSERT INTO 同一目标流实现
INTERSECT 可通过 INNER JOIN 实现
EXCEPT 可通过 LEFT JOIN + IS NULL 实现
所有操作都是持续查询（Continuous Query）
不支持 ORDER BY 和 LIMIT（流数据无界）

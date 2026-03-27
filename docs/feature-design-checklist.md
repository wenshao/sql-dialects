# SQL 特性设计清单

当你要为引擎添加一个新的 SQL 特性时，需要回答以下问题。

## 通用清单

### 1. 标准合规性
- [ ] SQL 标准（SQL:2003/2016/2023）怎么定义的？→ 看 `sql-standard.sql`
- [ ] 哪些引擎完全遵循标准？哪些有偏离？→ 看 `_comparison.md`
- [ ] 偏离标准的引擎为什么偏离？是历史原因还是设计选择？

### 2. 兼容性路线
- [ ] 你的引擎走哪条兼容路线？MySQL 族 / PostgreSQL 族 / 标准 SQL？
- [ ] 你的兼容目标引擎怎么做的？→ 看对应方言文件
- [ ] 兼容目标中有没有已知的坑？→ 看文件中的"陷阱"和"横向对比"部分

### 3. 语法设计
- [ ] 语法是否无歧义？Parser 能否明确解析？
- [ ] 是否与现有语法冲突？（如 MySQL 的 `||` 既是 OR 又可以是拼接）
- [ ] 是否需要新的保留字？保留字冲突风险？
- [ ] 错误处理：语法错误的报错信息是否清晰？

### 4. 语义设计
- [ ] NULL 处理：在所有边界情况下行为是否明确？
- [ ] 类型转换：需要隐式转换吗？规则是什么？
- [ ] 空结果集：空输入时行为是什么？
- [ ] 并发：多个会话同时操作时行为是否正确？

### 5. 实现考量
- [ ] 优化器：这个特性对查询计划有什么影响？
- [ ] 索引：能利用现有索引吗？需要新的索引类型吗？
- [ ] 内存：最坏情况下的内存占用？
- [ ] 分布式：多节点环境下的语义是否一致？

---

## 按特性的设计清单

### UPSERT / MERGE

参考: [`dml/upsert/`](../dml/upsert/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 语法 | MERGE (标准) / ON CONFLICT (PG) / ON DUPLICATE KEY (MySQL) | MERGE + ON CONFLICT 双支持 |
| 冲突检测 | 基于唯一约束自动检测 / 显式指定冲突列 | 显式指定（PG 方案，语义更清晰） |
| 返回值 | 无 / RETURNING / OUTPUT | 支持 RETURNING |
| 并发安全 | 行锁 / CAS / 引擎级去重 | OLTP 用行锁，OLAP 可引擎级 |

### 窗口函数

参考: [`query/window-functions/`](../query/window-functions/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 最小实现 | 只排名 / 排名+偏移 / 排名+偏移+聚合 | 排名+偏移+聚合（ROW_NUMBER, RANK, LAG/LEAD, SUM/AVG OVER） |
| 帧类型 | ROWS only / ROWS+RANGE / ROWS+RANGE+GROUPS | ROWS+RANGE（GROUPS 可后期加） |
| QUALIFY | 不支持 / 支持 | 支持（实现简单，用户价值大） |
| FILTER | 不支持 / 支持 | 支持（优化器友好，比 CASE WHEN 更好优化） |

### 事务

参考: [`advanced/transactions/`](../advanced/transactions/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 并发控制 | 锁 / MVCC / OCC | MVCC（现代引擎标配） |
| 默认隔离 | READ COMMITTED / REPEATABLE READ / SERIALIZABLE | RC（PG/Oracle 方案）或 SI |
| DDL 事务性 | 可回滚 / 隐式提交 | 可回滚更好，但实现复杂度高 |
| 分布式 | 2PC / TSO / Percolator / Calvin | 取决于一致性要求 |

### 数据类型

参考: [`types/`](../types/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 类型严格度 | 严格(PG) / 宽松(MySQL) / 动态(SQLite) | 严格（减少 bug，优化器更高效） |
| 字符串 | VARCHAR(n) / TEXT / STRING | 统一 STRING/TEXT（避免 MySQL 的 TEXT 限制问题） |
| 时间 | 带时区/不带时区/两种都有 | 两种都有，推荐带时区 |
| JSON | 文本存储 / 二进制(JSONB) / 原生类型 | 二进制（查询性能好） |
| 复合类型 | ARRAY+MAP+STRUCT / JSON 替代 / 不支持 | OLAP 引擎推荐原生支持 |

### 分区

参考: [`advanced/partitioning/`](../advanced/partitioning/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 分区类型 | RANGE / LIST / HASH / INTERVAL | 至少 RANGE + HASH |
| 分区键约束 | 必须在主键中(MySQL) / 无此限制(Oracle) | 无限制更好但实现更难 |
| 分区管理 | 手动 / 自动 | INTERVAL 自动创建（Oracle 方案）用户体验最好 |
| 与分布的关系 | 分区=分布(Hive) / 分区≠分布(传统RDBMS) | 分析引擎推荐分区+分桶两级 |

### 索引

参考: [`ddl/indexes/`](../ddl/indexes/)

| 决策 | 选项 | 推荐 |
|------|------|------|
| 聚集索引 | 有(MySQL/SQL Server) / 无(PG/Oracle heap) | OLTP 有聚集索引性能更好 |
| 函数索引 | 支持 / 不支持 | 支持（实现成本低，用户价值大） |
| 部分索引 | 支持(PG) / 不支持(MySQL) | 支持（节省存储和写入开销） |
| Online DDL | 支持 / 不支持 | 必须支持（生产环境刚需） |

---

## 实现优先级建议

如果你在从零构建 SQL 引擎，建议按以下顺序实现特性：

### MVP（最小可行产品）
1. CREATE TABLE + 基本类型 (INT, VARCHAR, TIMESTAMP, DECIMAL)
2. INSERT + SELECT + WHERE + ORDER BY + LIMIT
3. 基本 JOIN (INNER, LEFT)
4. GROUP BY + 基本聚合 (COUNT, SUM, AVG, MIN, MAX)

### V1（基本可用）
5. UPDATE + DELETE
6. UPSERT (ON CONFLICT 或 MERGE)
7. 子查询 (IN, EXISTS, 标量子查询)
8. CTE (非递归)
9. 窗口函数 (ROW_NUMBER, RANK, LAG/LEAD, SUM OVER)

### V2（生产就绪）
10. 事务 (BEGIN/COMMIT/ROLLBACK, MVCC)
11. 索引 (B-tree, 函数索引)
12. 约束 (PRIMARY KEY, UNIQUE, NOT NULL, CHECK)
13. 分区 (RANGE, HASH)
14. EXPLAIN (执行计划输出)
15. 权限 (GRANT/REVOKE)

### V3（功能完善）
16. 递归 CTE
17. JSON 类型
18. 物化视图
19. 存储过程/UDF
20. 全文搜索

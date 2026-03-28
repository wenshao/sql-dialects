# Apache Derby: 累计/滚动合计（Running Total）

> 参考资料:
> - [Apache Derby Documentation](https://db.apache.org/derby/docs/10.15/ref/)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构:
> - transactions(txn_id INT, account_id INT, amount DECIMAL(10,2), txn_date DATE)
> - 注意：Derby 仅支持 ROW_NUMBER()
> - Derby 不支持 SUM() OVER / AVG() OVER 等窗口聚合函数
> - ============================================================
> - 替代方案：关联子查询
> - ============================================================

```sql
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;

SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT AVG(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_avg
FROM transactions t1
ORDER BY t1.txn_date;

SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT COUNT(*)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_count
FROM transactions t1
ORDER BY t1.txn_date;
```

## 性能考量


Derby 仅支持 ROW_NUMBER()，不支持 SUM/AVG/COUNT OVER
必须使用关联子查询实现累计
Derby 是嵌入式数据库，适合小数据集

```sql
CREATE INDEX idx_transactions_date ON transactions (txn_date);
```

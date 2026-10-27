SELECT
    r.session_id,
    r.blocking_session_id,          -- CINE te blocheaza
    r.status,
    r.wait_type,
    r.command,
    t.text                          -- ce ruleaza acea sesiune
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID; 

-- fara sesiunea curenta
DBCC OPENTRAN('Olist');
go

CREATE OR ALTER VIEW vw_clients AS
WITH comenzi AS (                                    -- toate comenzile livrate, cu luna (TOATA istoria)
    SELECT c.customer_unique_id,
           DATETRUNC(MONTH, o.order_purchase_timestamp) AS luna
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
prima AS (                                           -- luna primei comenzi a fiecarui client
    SELECT customer_unique_id, MIN(luna) AS prima_luna
    FROM comenzi
    GROUP BY customer_unique_id
),
activ AS (                                           -- UN rand per client per luna (fara dubluri)
    SELECT DISTINCT customer_unique_id, luna
    FROM comenzi
)
SELECT
    a.luna,
    COUNT(*)                                                    AS clienti_activi,
    SUM(CASE WHEN a.luna = p.prima_luna THEN 1 ELSE 0 END)      AS clienti_noi,
    SUM(CASE WHEN a.luna > p.prima_luna THEN 1 ELSE 0 END)      AS clienti_care_revin,
    CAST(100.0 * SUM(CASE WHEN a.luna > p.prima_luna THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                                       AS pct_care_revin
FROM activ a
JOIN prima p ON p.customer_unique_id = a.customer_unique_id
WHERE a.luna >= '2017-01-01' AND a.luna < '2018-09-01'       -- filtrul DOAR la final
GROUP BY a.luna;
GO

SELECT * FROM vw_clients ORDER BY luna;

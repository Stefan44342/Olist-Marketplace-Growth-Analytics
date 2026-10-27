/* =====================================================================
   Olist Marketplace Growth Analytics | SQL Server
   Jan 2017 - Aug 2018 | delivered orders | customer = customer_unique_id
   ===================================================================== */
USE Olist;
GO


-- 0. Indexes on join columns (run after loading the tables)
CREATE INDEX IX_orders_customer    ON orders (customer_id);
CREATE INDEX IX_customers_customer ON customers (customer_id);
CREATE INDEX IX_customers_unique   ON customers (customer_unique_id);
CREATE INDEX IX_items_order        ON order_items (order_id);
CREATE INDEX IX_reviews_order      ON order_reviews (order_id);
GO


-- 2.3 Reliable period: orders per month
SELECT
    DATETRUNC(MONTH, order_purchase_timestamp)                  AS luna,
    COUNT(*)                                                    AS comenzi,
    SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END) AS livrate,
    MIN(order_purchase_timestamp)                               AS prima_comanda,
    MAX(order_purchase_timestamp)                               AS ultima_comanda
FROM orders
GROUP BY DATETRUNC(MONTH, order_purchase_timestamp)
ORDER BY luna;
GO


-- 2.4 Headline KPIs
CREATE OR ALTER VIEW vw_kpi AS
WITH items AS (
    SELECT order_id, SUM(price) AS gmv_comanda, SUM(freight_value) AS transport_comanda
    FROM order_items
    GROUP BY order_id
)
SELECT
    CAST(SUM(i.gmv_comanda) AS DECIMAL(14,2))                                             AS gmv,
    COUNT(o.order_id)                                                                     AS comenzi,
    COUNT(DISTINCT c.customer_unique_id)                                                  AS clienti,
    CAST(SUM(i.gmv_comanda) / COUNT(o.order_id) AS DECIMAL(10,2))                         AS aov,
    CAST(1.0 * COUNT(o.order_id) / COUNT(DISTINCT c.customer_unique_id) AS DECIMAL(10,2)) AS comenzi_per_client,
    CAST(SUM(i.transport_comanda) AS DECIMAL(14,2))                                       AS transport_total,
    CAST(100.0 * SUM(i.transport_comanda) / SUM(i.gmv_comanda) AS DECIMAL(5,2))          AS transport_pct_gmv
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN items i     ON i.order_id    = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';
GO


-- 2.5 Monthly trend and metric tree
CREATE OR ALTER VIEW vw_month_trend AS
WITH ord AS (
    SELECT
        DATETRUNC(MONTH, o.order_purchase_timestamp)                                     AS luna,
        CAST(SUM(oi.price) AS DECIMAL(14,2))                                             AS gmv,
        COUNT(DISTINCT o.order_id)                                                       AS comenzi,
        COUNT(DISTINCT c.customer_unique_id)                                             AS clienti,
        CAST(SUM(oi.price) / COUNT(DISTINCT o.order_id) AS DECIMAL(10,2))                AS aov,
        CAST(1.0 * COUNT(DISTINCT o.order_id) / COUNT(DISTINCT c.customer_unique_id)
             AS DECIMAL(10,2))                                                           AS comenzi_per_client,
        LAG(CAST(SUM(oi.price) AS DECIMAL(14,2)))
            OVER (ORDER BY DATETRUNC(MONTH, o.order_purchase_timestamp))                 AS gmv_luna_trecuta
    FROM orders o
    JOIN customers c    ON c.customer_id = o.customer_id
    JOIN order_items oi ON oi.order_id   = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY DATETRUNC(MONTH, o.order_purchase_timestamp)
)
SELECT
    luna, gmv, comenzi, clienti, aov, comenzi_per_client, gmv_luna_trecuta,
    CAST(gmv - gmv_luna_trecuta AS DECIMAL(14,2))                                         AS crestere_gmv_abs,
    CAST((gmv - gmv_luna_trecuta) * 100.0 / NULLIF(gmv_luna_trecuta, 0) AS DECIMAL(10,2)) AS crestere_gmv_pct
FROM ord;
GO


-- 2.6 New vs returning customers
CREATE OR ALTER VIEW vw_clients AS
WITH comenzi AS (
    SELECT c.customer_unique_id,
           DATETRUNC(MONTH, o.order_purchase_timestamp) AS luna
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
prima AS (
    SELECT customer_unique_id, MIN(luna) AS prima_luna
    FROM comenzi
    GROUP BY customer_unique_id
),
activ AS (
    SELECT DISTINCT customer_unique_id, luna
    FROM comenzi
)
SELECT
    a.luna,
    COUNT(*)                                               AS clienti_activi,
    SUM(CASE WHEN a.luna = p.prima_luna THEN 1 ELSE 0 END) AS clienti_noi,
    SUM(CASE WHEN a.luna > p.prima_luna THEN 1 ELSE 0 END) AS clienti_care_revin,
    CAST(100.0 * SUM(CASE WHEN a.luna > p.prima_luna THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                                  AS pct_care_revin
FROM activ a
JOIN prima p ON p.customer_unique_id = a.customer_unique_id
WHERE a.luna >= '2017-01-01' AND a.luna < '2018-09-01'
GROUP BY a.luna;
GO


-- 3.1 Cohort retention
CREATE OR ALTER VIEW vw_cohort_retention AS
WITH comenzi AS (
    SELECT c.customer_unique_id,
           DATETRUNC(MONTH, o.order_purchase_timestamp) AS luna
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
cohorta AS (
    SELECT customer_unique_id, MIN(luna) AS cohorta
    FROM comenzi
    GROUP BY customer_unique_id
),
activitate AS (
    SELECT DISTINCT customer_unique_id, luna
    FROM comenzi
),
cu_luna_nr AS (
    SELECT co.cohorta,
           DATEDIFF(MONTH, co.cohorta, a.luna) AS luna_nr,
           a.customer_unique_id
    FROM activitate a
    JOIN cohorta co ON co.customer_unique_id = a.customer_unique_id
    WHERE co.cohorta >= '2017-01-01' AND co.cohorta < '2018-09-01'
      AND a.luna    <  '2018-09-01'
),
numarat AS (
    SELECT cohorta, luna_nr, COUNT(*) AS clienti_activi
    FROM cu_luna_nr
    GROUP BY cohorta, luna_nr
)
SELECT
    cohorta,
    luna_nr,
    clienti_activi,
    MAX(CASE WHEN luna_nr = 0 THEN clienti_activi END) OVER (PARTITION BY cohorta) AS marime_cohorta,
    CAST(100.0 * clienti_activi
         / MAX(CASE WHEN luna_nr = 0 THEN clienti_activi END) OVER (PARTITION BY cohorta)
         AS DECIMAL(5,2))                                                          AS retentie_pct
FROM numarat;
GO


-- 3.2 Cohort retention matrix
SELECT
    cohorta,
    marime_cohorta,
    MAX(CASE WHEN luna_nr = 1  THEN retentie_pct END) AS M1,
    MAX(CASE WHEN luna_nr = 2  THEN retentie_pct END) AS M2,
    MAX(CASE WHEN luna_nr = 3  THEN retentie_pct END) AS M3,
    MAX(CASE WHEN luna_nr = 6  THEN retentie_pct END) AS M6,
    MAX(CASE WHEN luna_nr = 12 THEN retentie_pct END) AS M12
FROM vw_cohort_retention
GROUP BY cohorta, marime_cohorta
ORDER BY cohorta;
GO


-- 3.3 Cumulative LTV by cohort
CREATE OR ALTER VIEW vw_cohort_ltv AS
WITH gmv_comanda AS (
    SELECT order_id, SUM(price) AS gmv
    FROM order_items
    GROUP BY order_id
),
comenzi AS (
    SELECT c.customer_unique_id,
           DATETRUNC(MONTH, o.order_purchase_timestamp) AS luna,
           g.gmv
    FROM orders o
    JOIN customers c   ON c.customer_id = o.customer_id
    JOIN gmv_comanda g ON g.order_id    = o.order_id
    WHERE o.order_status = 'delivered'
),
cohorta AS (
    SELECT customer_unique_id, MIN(luna) AS cohorta
    FROM comenzi
    GROUP BY customer_unique_id
),
cu_luna_nr AS (
    SELECT co.cohorta,
           DATEDIFF(MONTH, co.cohorta, cm.luna) AS luna_nr,
           cm.customer_unique_id,
           cm.gmv
    FROM comenzi cm
    JOIN cohorta co ON co.customer_unique_id = cm.customer_unique_id
    WHERE co.cohorta >= '2017-01-01' AND co.cohorta < '2018-09-01'
      AND cm.luna    <  '2018-09-01'
),
pe_luna AS (
    SELECT cohorta, luna_nr,
           SUM(gmv)                           AS gmv_luna,
           COUNT(DISTINCT customer_unique_id) AS clienti_activi
    FROM cu_luna_nr
    GROUP BY cohorta, luna_nr
)
SELECT
    cohorta,
    luna_nr,
    gmv_luna,
    SUM(gmv_luna) OVER (PARTITION BY cohorta ORDER BY luna_nr)                      AS gmv_cumulat,
    MAX(CASE WHEN luna_nr = 0 THEN clienti_activi END) OVER (PARTITION BY cohorta)  AS marime_cohorta,
    CAST( SUM(gmv_luna) OVER (PARTITION BY cohorta ORDER BY luna_nr)
        / MAX(CASE WHEN luna_nr = 0 THEN clienti_activi END) OVER (PARTITION BY cohorta)
        AS DECIMAL(10,2))                                                           AS ltv_per_client
FROM pe_luna;
GO


-- 3.4 LTV matrix
SELECT
    cohorta,
    marime_cohorta,
    MAX(CASE WHEN luna_nr = 0  THEN ltv_per_client END) AS LTV_M0,
    MAX(CASE WHEN luna_nr = 1  THEN ltv_per_client END) AS LTV_M1,
    MAX(CASE WHEN luna_nr = 3  THEN ltv_per_client END) AS LTV_M3,
    MAX(CASE WHEN luna_nr = 6  THEN ltv_per_client END) AS LTV_M6,
    MAX(CASE WHEN luna_nr = 12 THEN ltv_per_client END) AS LTV_M12
FROM vw_cohort_ltv
GROUP BY cohorta, marime_cohorta
ORDER BY cohorta;
GO


-- 4.1 Delivery KPIs
CREATE OR ALTER VIEW vw_delivery_kpi AS
WITH rev AS (
    SELECT order_id, AVG(1.0 * review_score) AS review_comanda
    FROM order_reviews
    GROUP BY order_id
),
baza AS (
    SELECT
        order_id,
        DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date)  AS zile_livrare,
        DATEDIFF(DAY, order_purchase_timestamp, order_estimated_delivery_date)  AS zile_estimate,
        CASE WHEN CAST(order_delivered_customer_date AS DATE)
                > CAST(order_estimated_delivery_date AS DATE) THEN 1 ELSE 0 END AS intarziata
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp <  '2018-09-01'
)
SELECT
    CAST(AVG(1.0 * b.zile_livrare)  AS DECIMAL(5,1))                                AS zile_livrare_medie,
    CAST(AVG(1.0 * b.zile_estimate) AS DECIMAL(5,1))                                AS zile_estimate_medie,
    CAST(100.0 * SUM(b.intarziata) / COUNT(*) AS DECIMAL(5,2))                      AS pct_intarziate,
    CAST(AVG(CASE WHEN b.intarziata = 0 THEN r.review_comanda END) AS DECIMAL(3,2)) AS nota_la_timp,
    CAST(AVG(CASE WHEN b.intarziata = 1 THEN r.review_comanda END) AS DECIMAL(3,2)) AS nota_intarziate
FROM baza b
LEFT JOIN rev r ON r.order_id = b.order_id;
GO


-- 4.2 Review score: on time vs late
WITH rev AS (
    SELECT order_id, AVG(1.0 * review_score) AS review_comanda
    FROM order_reviews
    GROUP BY order_id
),
cu_status AS (
    SELECT
        order_id,
        CASE WHEN CAST(order_delivered_customer_date AS DATE)
               <= CAST(order_estimated_delivery_date AS DATE)
             THEN 'la timp' ELSE 'intarziata' END AS status_livrare
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp <  '2018-09-01'
)
SELECT
    s.status_livrare,
    COUNT(*)                                                                                        AS comenzi,
    CAST(AVG(r.review_comanda) AS DECIMAL(3,2))                                                     AS nota_medie,
    CAST(100.0 * SUM(CASE WHEN r.review_comanda <= 2 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_note_proaste,
    CAST(100.0 * SUM(CASE WHEN r.review_comanda = 5  THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_note_5
FROM cu_status s
JOIN rev r ON r.order_id = s.order_id
GROUP BY s.status_livrare;
GO


-- 4.3 Review score by delay bucket
CREATE OR ALTER VIEW vw_delivery_buckets AS
WITH rev AS (
    SELECT order_id, AVG(1.0 * review_score) AS review_comanda
    FROM order_reviews
    GROUP BY order_id
),
cu_zile AS (
    SELECT order_id,
           DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS zile
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp <  '2018-09-01'
),
cu_bucket AS (
    SELECT order_id,
           CASE
               WHEN zile < -14 THEN '1. >14 zile mai devreme'
               WHEN zile <= -8 THEN '2. 8-14 zile mai devreme'
               WHEN zile <= -1 THEN '3. 1-7 zile mai devreme'
               WHEN zile =   0 THEN '4. in ziua estimata'
               WHEN zile <=  3 THEN '5. 1-3 zile intarziere'
               WHEN zile <=  7 THEN '6. 4-7 zile intarziere'
               ELSE                 '7. >7 zile intarziere'
           END AS bucket,
           CASE WHEN zile <= 0 THEN 'la timp' ELSE 'intarziata' END AS status_livrare
    FROM cu_zile
)
SELECT
    b.bucket,
    b.status_livrare,
    CASE WHEN b.status_livrare = 'intarziata' THEN '#DC2626' ELSE '#2563EB' END                     AS culoare,
    COUNT(*)                                                                                        AS comenzi,
    CAST(AVG(r.review_comanda) AS DECIMAL(3,2))                                                     AS nota_medie,
    CAST(100.0 * SUM(CASE WHEN r.review_comanda <= 2 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_note_proaste
FROM cu_bucket b
JOIN rev r ON r.order_id = b.order_id
GROUP BY b.bucket, b.status_livrare;
GO


-- 4.4 Late first order vs return within 180 days
WITH order_rnk AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        ROW_NUMBER()                 OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS ord_rnk,
        LEAD(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS data_urm
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
prima AS (
    SELECT
        CASE WHEN CAST(order_delivered_customer_date AS DATE)
               <= CAST(order_estimated_delivery_date AS DATE)
             THEN 'la timp' ELSE 'intarziata' END                                                   AS prima_comanda,
        CASE WHEN DATEDIFF(DAY, order_purchase_timestamp, data_urm) <= 180 THEN 1 ELSE 0 END        AS a_revenit
    FROM order_rnk
    WHERE ord_rnk = 1
      AND order_purchase_timestamp < '2018-03-01'
)
SELECT
    prima_comanda,
    COUNT(*)                                                  AS clienti,
    SUM(a_revenit)                                            AS au_revenit_180z,
    CAST(100.0 * SUM(a_revenit) / COUNT(*) AS DECIMAL(5,2))   AS pct_revenit
FROM prima
GROUP BY prima_comanda;
GO


-- 5.1 Is it real? Days with orders and orders per day (2018)
SELECT
    DATETRUNC(MONTH, order_purchase_timestamp)                       AS luna,
    COUNT(DISTINCT CAST(order_purchase_timestamp AS DATE))           AS zile_cu_comenzi,
    DAY(EOMONTH(DATETRUNC(MONTH, order_purchase_timestamp)))         AS zile_in_luna,
    COUNT(*)                                                         AS comenzi,
    CAST(1.0 * COUNT(*) / COUNT(DISTINCT CAST(order_purchase_timestamp AS DATE))
         AS DECIMAL(6,1))                                            AS comenzi_pe_zi
FROM orders
WHERE order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp <  '2018-09-01'
GROUP BY DATETRUNC(MONTH, order_purchase_timestamp)
ORDER BY luna;
GO


-- 5.2 Only here? Change March -> June 2018 by region
CREATE OR ALTER VIEW vw_region_drop AS
WITH pe_stat AS (
    SELECT
        CASE WHEN c.customer_state IN ('SP', 'RJ', 'MG') THEN c.customer_state
             ELSE 'Rest of Brazil' END                                                    AS regiune,
        SUM(CASE WHEN o.order_purchase_timestamp <  '2018-04-01' THEN 1 ELSE 0 END) / 31.0 AS pe_zi_martie,
        SUM(CASE WHEN o.order_purchase_timestamp >= '2018-06-01' THEN 1 ELSE 0 END) / 30.0 AS pe_zi_iunie
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE (o.order_purchase_timestamp >= '2018-03-01' AND o.order_purchase_timestamp < '2018-04-01')
       OR (o.order_purchase_timestamp >= '2018-06-01' AND o.order_purchase_timestamp < '2018-07-01')
    GROUP BY CASE WHEN c.customer_state IN ('SP', 'RJ', 'MG') THEN c.customer_state ELSE 'Rest of Brazil' END
)
SELECT
    regiune,
    CAST(pe_zi_martie AS DECIMAL(6,1))                                         AS pe_zi_martie,
    CAST(pe_zi_iunie  AS DECIMAL(6,1))                                         AS pe_zi_iunie,
    CAST(pe_zi_iunie - pe_zi_martie AS DECIMAL(6,1))                           AS comenzi_pierdute_pe_zi,
    CAST(100.0 * (pe_zi_iunie - pe_zi_martie) / pe_zi_martie AS DECIMAL(5,1))  AS schimbare_pct
FROM pe_stat;
GO


-- 5.3 When? Weekly orders, São Paulo vs rest of Brazil
CREATE OR ALTER VIEW vw_weekly_region AS
SELECT
    DATETRUNC(WEEK, o.order_purchase_timestamp)               AS saptamana,
    SUM(CASE WHEN c.customer_state =  'SP' THEN 1 ELSE 0 END)  AS comenzi_SP,
    SUM(CASE WHEN c.customer_state <> 'SP' THEN 1 ELSE 0 END)  AS comenzi_in_afara_SP
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_purchase_timestamp >= '2018-01-07'
  AND o.order_purchase_timestamp <  '2018-08-19'
GROUP BY DATETRUNC(WEEK, o.order_purchase_timestamp);
GO


-- 5.4 Which component? Orders, AOV, new and returning customers (2018)
SELECT
    t.luna,
    t.comenzi,
    t.aov,
    c.clienti_noi,
    c.clienti_care_revin,
    c.pct_care_revin
FROM vw_month_trend t
JOIN vw_clients c ON c.luna = t.luna
WHERE t.luna >= '2018-01-01'
ORDER BY t.luna;
GO


-- 5.5 Where? Orders per day by category, before vs during the strike
WITH comenzi_categorie AS (
    SELECT DISTINCT
        o.order_id,
        o.order_purchase_timestamp,
        p.product_category_name_english AS categorie
    FROM orders o
    JOIN order_items oi ON oi.order_id  = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE (o.order_purchase_timestamp >= '2018-04-01' AND o.order_purchase_timestamp < '2018-05-20')
       OR (o.order_purchase_timestamp >= '2018-05-20' AND o.order_purchase_timestamp < '2018-06-03')
),
pe_categorie AS (
    SELECT
        categorie,
        SUM(CASE WHEN order_purchase_timestamp <  '2018-05-20' THEN 1 ELSE 0 END) / 49.0 AS pe_zi_inainte,
        SUM(CASE WHEN order_purchase_timestamp >= '2018-05-20' THEN 1 ELSE 0 END) / 14.0 AS pe_zi_greva
    FROM comenzi_categorie
    GROUP BY categorie
)
SELECT TOP 12
    categorie,
    CAST(pe_zi_inainte AS DECIMAL(6,1))                                         AS pe_zi_inainte,
    CAST(pe_zi_greva   AS DECIMAL(6,1))                                         AS pe_zi_greva,
    CAST(100.0 * (pe_zi_greva - pe_zi_inainte) / pe_zi_inainte AS DECIMAL(5,1)) AS schimbare_pct
FROM pe_categorie
ORDER BY pe_zi_inainte DESC;
GO

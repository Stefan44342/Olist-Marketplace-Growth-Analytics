create database Olist
use Olist
select * from [dbo].[order_items]
select * from [dbo].[orders]
select * from [dbo].[customers]

select 
DATEFROMPARTS(YEAR(ORDER_PURCHASE_TIMESTAMP),MONTH(ORDER_PURCHASE_TIMESTAMP),1) AS LUNA,
COUNT(*) AS COMENZI,
SUM(CASE WHEN ORDER_STATUS='delivered' then 1 else 0 end) as livrate,
MIN(ORDER_PURCHASE_TIMESTAMP) as prima_comanda,
max(ORDER_PURCHASE_TIMESTAMP) as ultima_comanda
FROM orders
group by DATEFROMPARTS(YEAR(ORDER_PURCHASE_TIMESTAMP),MONTH(ORDER_PURCHASE_TIMESTAMP),1)
order by LUNA
go

create or alter view vw_orders as 
SELECT
    CAST(SUM(oi.price) AS DECIMAL(14,2))                                       AS gmv,
    COUNT(DISTINCT o.order_id)                                                 AS comenzi,     
    COUNT(DISTINCT c.customer_unique_id)                                       AS clienti,
    CAST(SUM(oi.price) / COUNT(DISTINCT o.order_id) AS DECIMAL(10,2))          AS aov,
    CAST(1.0 * COUNT(DISTINCT o.order_id) / COUNT(DISTINCT c.customer_unique_id)
         AS DECIMAL(10,2))                                                     AS comenzi_per_client,
    CAST(SUM(oi.freight_value) AS DECIMAL(14,2))                               AS transport_total,
    CAST(100.0 * SUM(oi.freight_value) / SUM(oi.price) AS DECIMAL(5,2))        AS transport_pct_gmv
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id          
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';
go

create or alter view vw_month_trend as 
with ord as (
SELECT
    datetrunc(month,o.order_purchase_timestamp) as luna,
    CAST(SUM(oi.price) AS DECIMAL(14,2))                                       AS gmv,
    COUNT(DISTINCT o.order_id)                                                 AS comenzi,     
    COUNT(DISTINCT c.customer_unique_id)                                       AS clienti,
    CAST(SUM(oi.price) / COUNT(DISTINCT o.order_id) AS DECIMAL(10,2))          AS aov,
    CAST(1.0 * COUNT(DISTINCT o.order_id) / COUNT(DISTINCT c.customer_unique_id)
         AS DECIMAL(10,2))                                                     AS comenzi_per_client,
    lag(CAST(SUM(oi.price) AS DECIMAL(14,2))) over (order by datetrunc(month,o.order_purchase_timestamp)) as gmv_luna_trecuta
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id          
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
group by datetrunc(month,o.order_purchase_timestamp)
)
select 
luna,gmv,comenzi,clienti,aov,comenzi_per_client,gmv_luna_trecuta,
cast((gmv-gmv_luna_trecuta)/nullif(gmv_luna_trecuta,0)*100 as decimal(10,2)) as crestere_gmv_pct,
gmv-gmv_luna_trecuta as crestere_gmv_abs
from ord
go

create or alter view vw_clients as 
with first_order as(
select 
c.customer_unique_id,
o.order_purchase_timestamp,
datepart(MONTH,o.order_purchase_timestamp) as luna,
row_number() over ( partition by c.customer_unique_id order by o.order_purchase_timestamp) as rnk,
o.order_id
from customers c join orders o on c.customer_id=o.customer_id
where order_status='delivered' 
),clients_r as (
select 
luna,
count(distinct customer_unique_id) as clienti_activi,
sum(case when rnk=1 then 1 else 0 end) as clienti_noi,
sum(case when rnk=2 then 1 else 0 end) as clienti_care_revin
from first_order
where order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp <  '2018-09-01'
group by luna
)
select
luna,
clienti_activi,
clienti_noi,
clienti_care_revin,
cast(100*clienti_care_revin/clienti_activi as decimal(10,2)) as pct_care_revin
from clients_r





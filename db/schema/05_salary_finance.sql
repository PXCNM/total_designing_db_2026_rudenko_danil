CREATE OR REPLACE PROCEDURE courier_salary()
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    month_start timestamp := date_trunc('month', localtimestamp);
    pay_year integer := extract(year FROM month_start)::integer;
    pay_month integer := extract(month FROM month_start)::integer;
BEGIN
    WITH monthly AS MATERIALIZED (
        SELECT c.courier_id, count(o.order_id) AS deliveries,
            coalesce(sum(o.commission), 0) AS commission_sum,
            coalesce(cp.coefficient_used, c.coefficient) AS coefficient_used
        FROM courier c
        LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
            AND o.order_timestamp >= month_start AND o.order_timestamp < month_start + interval '1 month'
        LEFT JOIN courier_pay cp ON cp.courier_id = c.courier_id  AND cp.year = pay_year AND cp.month = pay_month
        GROUP BY c.courier_id, cp.coefficient_used
    ), payouts AS (
        INSERT INTO courier_pay(year, month, courier_id, amount, coefficient_used)
        SELECT pay_year, pay_month, m.courier_id,
            round(m.commission_sum * m.coefficient_used, 2), m.coefficient_used
        FROM monthly m
        ON CONFLICT (year, month, courier_id) DO UPDATE SET amount = EXCLUDED.amount
        RETURNING courier_id
    )
    UPDATE courier c SET coefficient = CASE
			WHEN m.deliveries <= 150 THEN 0.1
			WHEN m.deliveries <= 250 THEN 0.2
			WHEN m.deliveries <= 500 THEN 0.3
			ELSE 0.5
		END
    FROM monthly m JOIN payouts p USING (courier_id)
    WHERE c.courier_id = m.courier_id AND c.status <> 'уволен';
END;
$$;

CREATE OR REPLACE VIEW how_much_money AS
WITH RECURSIVE delivered_monthly AS MATERIALIZED (
    SELECT date_trunc('month', o.order_timestamp)::date AS month_start,
        sum(o.order_amount) AS sum_no_commission,
        sum(o.total_amount) AS sum_with_commission
    FROM "order" o WHERE o.status = 'доставлен'
    GROUP BY date_trunc('month', o.order_timestamp)::date
), bounds AS (
    SELECT min(month_start) AS first_month, max(month_start) AS last_month
    FROM delivered_monthly
), months(month_start) AS (
    SELECT first_month FROM bounds WHERE first_month IS NOT NULL
    UNION ALL
    SELECT (m.month_start + interval '1 month')::date
    FROM months m CROSS JOIN bounds b WHERE m.month_start < b.last_month
), payouts AS (
    SELECT make_date(cp.year, cp.month, 1) AS month_start, sum(cp.amount) AS amount
    FROM courier_pay cp GROUP BY cp.year, cp.month
), amounts AS (
    SELECT m.month_start,
        coalesce(d.sum_no_commission, 0::numeric) AS sum_no_commission,
        coalesce(d.sum_with_commission, 0::numeric) AS sum_with_commission,
        coalesce(d.sum_with_commission - d.sum_no_commission, 0::numeric) AS commission,
        coalesce(p.amount, 0::numeric) AS courier_pay
    FROM months m LEFT JOIN delivered_monthly d USING (month_start)
    LEFT JOIN payouts p USING (month_start)
), compared AS (
    SELECT a.*, lag(a.commission) OVER (ORDER BY a.month_start) AS prev_commission
    FROM amounts a
)
SELECT to_char(month_start, 'YYYY-MM') AS year_month, sum_no_commission, sum_with_commission,
	commission, prev_commission, commission - prev_commission AS commission_diff,
    courier_pay, commission - courier_pay AS net_profit
FROM compared;

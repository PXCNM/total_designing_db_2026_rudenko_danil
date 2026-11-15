CREATE OR REPLACE PROCEDURE add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    INSERT INTO product(
        restaurant_id, product_category_id, product_name,
        price, rating, status, description, photo_url
    )
    VALUES (
        p_restaurant_id, p_product_category_id, p_name,
        p_price, p_rating, p_status, p_description, p_photo_url
    );
END;
$$;

CREATE OR REPLACE FUNCTION get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
SET search_path FROM CURRENT
AS $$
    WITH delivered AS MATERIALIZED (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM "order" o WHERE o.status = 'доставлен'
    ), amounts AS (
        SELECT d.restaurant_id, sum(d.total_amount) AS total_amount, avg(d.total_amount) AS avg_amount
        FROM delivered d GROUP BY d.restaurant_id
    ), product_quantities AS (
        SELECT d.restaurant_id, s.product_id, sum(s.quantity) AS quantity
        FROM delivered d JOIN order_structure s USING (order_id) GROUP BY d.restaurant_id, s.product_id
    ), best_products AS (
        SELECT DISTINCT ON (q.restaurant_id) q.restaurant_id, q.product_id
        FROM product_quantities q ORDER BY q.restaurant_id, q.quantity DESC, random()
    ), client_counts AS (
        SELECT d.restaurant_id, d.client_id, count(*) AS order_count
        FROM delivered d GROUP BY d.restaurant_id, d.client_id
    ), best_clients AS (
        SELECT DISTINCT ON (c.restaurant_id) c.restaurant_id, c.client_id
        FROM client_counts c ORDER BY c.restaurant_id, c.order_count DESC, random()
    )
    SELECT r.restaurant_name, p.product_name, coalesce(a.total_amount, 0::numeric), a.avg_amount, c.login
    FROM restaurant r
    LEFT JOIN amounts a USING (restaurant_id)
    LEFT JOIN best_products bp USING (restaurant_id)
    LEFT JOIN product p ON p.product_id = bp.product_id
    LEFT JOIN best_clients bc ON bc.restaurant_id = r.restaurant_id
    LEFT JOIN client c ON c.client_id = bc.client_id;
$$;

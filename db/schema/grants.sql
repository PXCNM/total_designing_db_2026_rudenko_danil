BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END;
$$;

GRANT ALL PRIVILEGES ON SCHEMA rudenko_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA rudenko_food TO inspector;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA rudenko_food TO inspector;

GRANT USAGE ON TYPE rudenko_food.restaurant_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.product_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.courier_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.order_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.order_pay_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.payment_status TO inspector;
GRANT USAGE ON TYPE rudenko_food.payment_type TO inspector;
GRANT USAGE ON TYPE rudenko_food.review_entity_type TO inspector;

GRANT USAGE ON SCHEMA exts, information_schema, pg_catalog TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;
GRANT SELECT ON information_schema.tables, pg_catalog.pg_tables TO inspector;

ALTER DEFAULT PRIVILEGES IN SCHEMA rudenko_food GRANT ALL ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA rudenko_food GRANT EXECUTE ON FUNCTIONS TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA rudenko_food GRANT USAGE ON TYPES TO inspector;

DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO inspector', current_database());
    EXECUTE format(
        'ALTER ROLE inspector IN DATABASE %I SET search_path TO rudenko_food, exts, pg_catalog',
        current_database()
    );
END;
$$;

COMMIT;

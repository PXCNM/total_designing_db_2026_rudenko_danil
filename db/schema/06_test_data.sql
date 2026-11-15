CREATE OR REPLACE PROCEDURE erase_test_data()
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    DELETE FROM review;
    DELETE FROM payment;
    DELETE FROM order_structure;
    DELETE FROM "order";
    DELETE FROM courier_pay;
    DELETE FROM client_address;
    DELETE FROM product;
    DELETE FROM restaurant;
    DELETE FROM product_category;
    DELETE FROM courier;
    DELETE FROM client;
    DELETE FROM address;
END;
$$;

CREATE OR REPLACE PROCEDURE insert_test_data(value integer)
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    clients uuid[] := '{}'; couriers uuid[] := '{}'; restaurants uuid[] := '{}';
    categories uuid[] := '{}'; addresses uuid[] := '{}'; products uuid[] := '{}';
    prices numeric[] := '{}';
    restaurant_states restaurant_status[] := enum_range(NULL::restaurant_status);
    product_states product_status[] := enum_range(NULL::product_status);
    courier_states courier_status[] := enum_range(NULL::courier_status);
    order_states order_status[] := enum_range(NULL::order_status);
    payment_kinds payment_type[] := enum_range(NULL::payment_type);
    payment_states payment_status[] := enum_range(NULL::payment_status);
    review_kinds review_entity_type[] := enum_range(NULL::review_entity_type);
    first_month date := (date_trunc('month', current_date) - interval '5 months')::date;
	generation_start timestamp := greatest(first_month::timestamp, localtimestamp - interval '180 days');
    month_start date; month_end date;
    generated_id uuid; order_id_value uuid; payment_id_value uuid;
    phone_base bigint; i integer; j integer; k integer; owner_index integer;
    restaurant_index integer; product_index integer; courier_index integer;
    line_count integer; line_start integer; line_products uuid[];
    line_prices numeric[]; line_quantities numeric[]; quantity_value numeric;
    amount_value numeric; commission_value numeric; price_value numeric;
    created_at timestamp; delivered_at timestamp;
    state order_status; courier_state courier_status; review_kind review_entity_type;
    target uuid;
BEGIN
    IF value IS NULL OR value <= 0 OR value > 2147483647 / 5 THEN
        RAISE EXCEPTION 'value должен быть положительным целым числом, не превышающим 429496729' USING ERRCODE = '22023';
    END IF;
    LOCK TABLE client IN SHARE ROW EXCLUSIVE MODE;
    SELECT greatest(79000000000::bigint, coalesce(max(substring(phone_number FROM 2)::bigint), 0))
      INTO phone_base FROM client WHERE phone_number ~ '^\+7[0-9]{10}$';
    IF phone_base + value > 79999999999 THEN
        RAISE EXCEPTION 'Закончились номера телефонов' USING ERRCODE = '22023';
    END IF;

    FOR i IN 1..value LOOP
        generated_id := exts.uuid_generate_v4();
        INSERT INTO client(client_id, login, password, phone_number)
        VALUES (generated_id, 'test_' || generated_id, md5(random()::text), '+' || (phone_base + i)::text);
        clients := array_append(clients, generated_id);

        INSERT INTO product_category(product_category_name)
        VALUES ('Категория ' || exts.uuid_generate_v4()) RETURNING product_category_id INTO generated_id;
        categories := array_append(categories, generated_id);

        courier_state := courier_states[1 + floor(random() * cardinality(courier_states))::integer];
        IF i = 1 THEN courier_state := courier_states[1]; END IF;
        INSERT INTO courier(fio, phone_number, status, hire_date, dismissal_date)
        VALUES ('Курьер ' || exts.uuid_generate_v4(), '+' || (phone_base + i)::text,
            courier_state, generation_start::date,
            CASE WHEN courier_state = courier_states[4] THEN current_date END)
        RETURNING courier_id INTO generated_id;
        couriers := array_append(couriers, generated_id);

        INSERT INTO address(street, house_number)
        VALUES ('Ресторанная ' || exts.uuid_generate_v4(), '1') RETURNING address_id INTO generated_id;
        INSERT INTO restaurant(restaurant_name, address_id, description, work_start, work_end, company_details, status)
        VALUES ('Ресторан ' || exts.uuid_generate_v4(), generated_id, 'Тестовый ресторан',
            '09:00', '23:00', 'Тестовые реквизиты',
            restaurant_states[1 + floor(random() * cardinality(restaurant_states))::integer])
        RETURNING restaurant_id INTO generated_id;
        restaurants := array_append(restaurants, generated_id);

        FOR j IN 1..4 LOOP
            INSERT INTO address(street, house_number, apartment_office)
            VALUES ('Клиентская ' || clients[i], j::text, CASE WHEN j % 2 = 0 THEN j::text END)
            RETURNING address_id INTO generated_id;
            addresses := array_append(addresses, generated_id);
            INSERT INTO client_address(client_id, address_id) VALUES (clients[i], generated_id);
        END LOOP;

        FOR j IN 1..5 LOOP
            price_value := 1000 + floor(random() * 400001)::numeric / 100;
            INSERT INTO product(product_name, product_category_id, price, restaurant_id, photo_url, status, description)
            VALUES ('Блюдо ' || exts.uuid_generate_v4(), categories[i], price_value, restaurants[i],
                CASE WHEN j % 2 = 0 THEN 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
                product_states[1 + floor(random() * cardinality(product_states))::integer], 'Тестовое блюдо')
            RETURNING product_id INTO generated_id;
            products := array_append(products, generated_id);
            prices := array_append(prices, price_value);
        END LOOP;
    END LOOP;

    FOR i IN 1..(value * 5) LOOP
        owner_index := 1 + (i - 1) % value;
        restaurant_index := owner_index;
        courier_index := 1 + floor(random() * value)::integer;
        line_count := 1 + floor(random() * 3)::integer;
        line_start := floor(random() * 5)::integer;
        line_products := '{}'; line_prices := '{}'; line_quantities := '{}'; amount_value := 0;
        FOR k IN 0..(line_count - 1) LOOP
            product_index := (restaurant_index - 1) * 5 + 1 + (line_start + k) % 5;
            quantity_value := 1 + floor(random() * 4)::numeric / 2;
            line_products := array_append(line_products, products[product_index]);
            line_prices := array_append(line_prices, prices[product_index]);
            line_quantities := array_append(line_quantities, quantity_value);
            amount_value := amount_value + prices[product_index] * quantity_value;
        END LOOP;
		created_at := generation_start +
			(localtimestamp - generation_start) * ((i - 1 + random()) / (value * 5));
        state := order_states[1 + floor(random() * cardinality(order_states))::integer];
        IF i = 1 THEN state := order_states[4]; END IF;
        delivered_at := CASE WHEN state = order_states[4]
            THEN least(localtimestamp, created_at + interval '30 minutes') END;
        amount_value := round(amount_value, 2);
        commission_value := round(amount_value * 0.10, 2);
        INSERT INTO "order"(courier_id, client_id, address_id, restaurant_id, order_timestamp,
            delivery_timestamp, order_amount, status, description)
        VALUES (couriers[courier_index], clients[owner_index],
            addresses[(owner_index - 1) * 4 + 1 + ((i - 1) / value) % 4],
            restaurants[restaurant_index], created_at, delivered_at, amount_value,
            state, 'Тестовый заказ')
        RETURNING order_id INTO order_id_value;

        INSERT INTO order_structure(order_id, product_id, quantity, unit_price)
        SELECT order_id_value, x.product_id, x.quantity, x.price
        FROM unnest(line_products, line_quantities, line_prices) AS x(product_id, quantity, price);
        payment_id_value := exts.uuid_generate_v4();
        INSERT INTO payment(payment_id, order_id, payment_type, amount, transaction_id, transaction_timestamp, status)
        VALUES (payment_id_value, order_id_value,
            payment_kinds[1 + floor(random() * cardinality(payment_kinds))::integer],
            amount_value + commission_value, 'test_' || payment_id_value,
            least(localtimestamp, created_at + interval '5 minutes'), payment_states[1]);

        review_kind := review_kinds[1 + floor(random() * cardinality(review_kinds))::integer];
        target := CASE review_kind WHEN review_kinds[1] THEN line_products[1]
            WHEN review_kinds[2] THEN restaurants[restaurant_index] ELSE order_id_value END;
        INSERT INTO review(client_id, review_timestamp, entity_id, entity_type, order_id, description, photo_url, rating)
        VALUES (clients[owner_index], least(localtimestamp, created_at + interval '1 hour'),
            target, review_kind, order_id_value, 'Тестовый отзыв',
            CASE WHEN i % 2 = 0 THEN 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
            1 + floor(random() * 5)::integer);
    END LOOP;

    FOR j IN 0..5 LOOP
        month_start := (first_month + make_interval(months => j))::date;
        month_end := (month_start + interval '1 month')::date;
        WITH monthly AS (
            SELECT c.courier_id, count(o.order_id) AS deliveries,
                coalesce(sum(o.commission), 0) AS commission_sum
            FROM courier c LEFT JOIN "order" o ON o.courier_id = c.courier_id
                AND o.status = order_states[4]
                AND o.order_timestamp >= month_start AND o.order_timestamp < month_end
            WHERE c.courier_id = ANY(couriers) GROUP BY c.courier_id
        ), payouts AS (
            INSERT INTO courier_pay(year, month, courier_id, amount, coefficient_used)
            SELECT extract(year FROM month_start)::integer, extract(month FROM month_start)::integer,
                c.courier_id, round(m.commission_sum * c.coefficient, 2), c.coefficient
            FROM monthly m JOIN courier c USING (courier_id)
            RETURNING courier_id
        )
        UPDATE courier c SET coefficient = CASE
            WHEN m.deliveries <= 150 THEN 0.1 WHEN m.deliveries <= 250 THEN 0.2
            WHEN m.deliveries <= 500 THEN 0.3 ELSE 0.5 END
        FROM monthly m JOIN payouts p USING (courier_id)
        WHERE c.courier_id = m.courier_id
          AND (c.dismissal_date IS NULL OR c.dismissal_date >= month_end);
    END LOOP;
END;
$$;

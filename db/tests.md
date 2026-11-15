# Протокол для самопроверки

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | 17.0 |
| Дата проверки | 15.11.2026 |
| Схема | rudenko_food |
| Роль-аудитор | inspector |

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: архив восстанавливается без ошибок. После восстановления выполнен `db/schema/grants.sql`.

Факт: архив восстановлен без ошибок; скрипт выдачи прав выполнен успешно.

Вердикт: OK.

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO rudenko_food, exts, pg_catalog;
SELECT current_user;
```

Ожидается: `inspector`.

Факт: `inspector`.

Вердикт: OK.

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `rudenko_food`.

Факт: Получено: `rudenko_food`.

Вердикт: OK.

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.

Факт: Получено: `uuid-ossp|exts`.

Вердикт: OK.

### B.3. Все 12 таблиц модели

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'rudenko_food' AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 штук).

Факт: Получены все 12 перечисленных таблиц.

Вердикт: OK.

### B.4. UUID идентификаторы сущностей и связей

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'rudenko_food'
  AND column_name LIKE '%_id' AND column_name <> 'transaction_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

Внешний transaction_id — строка платёжного провайдера, а не UUID сущности (BR-8.3).

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'rudenko_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.

Факт: Получены 8 ENUM с указанными в constraints.md значениями.

Вердикт: OK.

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'rudenko_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: 17 FK, включая составные FK адреса клиента и автора отзыва.

Факт: Получены 17 внешних ключей, включая два составных.

Вердикт: OK.

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.

Факт: Все пять выбранных паролей имеют длину 32 и состоят из hex-символов.

Вердикт: OK.

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.

Факт: Вызов выполнен без ошибок.

Вердикт: OK.

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.

Факт: Вызов выполнен без ошибок.

Вердикт: OK.

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: client/courier/product_category/restaurant по 10; address/product/order/review/payment по 50.

Факт: Получено по 10 клиентов, курьеров, категорий и ресторанов; по 50 адресов, блюд, заказов, отзывов и платежей.

Вердикт: OK.

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего -> 40 клиентских.

Факт: Получено: `restaurant addresses|10`; `total addresses|50`.

Вердикт: OK.

### C.5. Нет пустых строк (BR-11.3)

```sql
DO $$
DECLARE col record; n bigint;
BEGIN
  FOR col IN SELECT table_name,column_name FROM information_schema.columns
    WHERE table_schema='rudenko_food' AND is_nullable='NO'
      AND data_type IN ('text','character varying','character') LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE btrim(%I) = %L',
      col.table_name,col.column_name,'') INTO n;
    RAISE NOTICE '%.%: пустых строк %', col.table_name,col.column_name,n;
  END LOOP;
END $$;
```

Ожидается: 0.

Факт: Для каждого обязательного текстового поля получено сообщение «пустых строк 0».

Вердикт: OK.

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
DO $$
DECLARE col record; n bigint;
BEGIN
  FOR col IN SELECT table_name,column_name FROM information_schema.columns
    WHERE table_schema='rudenko_food' AND is_nullable='NO' LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE %I IS NULL',
      col.table_name,col.column_name) INTO n;
    RAISE NOTICE '%.%: NULL %', col.table_name,col.column_name,n;
  END LOOP;
END $$;
SELECT count(*) AS missing_generated FROM "order"
WHERE commission IS NULL OR total_amount IS NULL;
```

Ожидается: 0.

Факт: Для каждого NOT NULL поля получено NULL 0; missing_generated = 0.

Вердикт: OK.

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.

Факт: активные курьеры присутствуют; количество не менее 1.

Вердикт: OK.

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
WITH checked AS (
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp


) SELECT * FROM checked WHERE amount IS DISTINCT FROM expected_amount;
```

Ожидается: пусто; проверены все выплаты, amount = expected_amount.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

### C.8a. Исторические коэффициенты

```sql
SELECT cp.courier_id,cp.year,cp.month,cp.coefficient_used
FROM courier_pay cp LEFT JOIN "order" o ON o.courier_id=cp.courier_id AND o.status='доставлен'
 AND o.order_timestamp >= make_date(cp.year,cp.month,1)-interval '1 month'
 AND o.order_timestamp < make_date(cp.year,cp.month,1)
GROUP BY cp.courier_id,cp.year,cp.month
HAVING cp.coefficient_used <> CASE WHEN count(o.order_id)<=150 THEN .1
 WHEN count(o.order_id)<=250 THEN .2 WHEN count(o.order_id)<=500 THEN .3 ELSE .5 END;
```

Ожидается: пусто: коэффициент выплаты соответствует доставкам предыдущего месяца; до начала истории доставок нет, применяется .1.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
SELECT (SELECT count(*) FROM client) AS clients,
       (SELECT count(*) FROM "order") AS orders,
       (SELECT count(*) FROM courier_pay) AS payouts;
```

Ожидается: без ошибок; данные добавляются. После 11 вызовов всего 110 клиентов, 550 заказов и 660 выплат.

Факт: После десяти дополнительных вызовов: clients=110, orders=550, payouts=660.

Вердикт: OK.

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'client_address -> client' AS fk, count(*) AS orphans FROM "client_address" s LEFT JOIN "client" t ON s.client_id=t.client_id WHERE t.client_id IS NULL
UNION ALL
SELECT 'client_address -> address' AS fk, count(*) AS orphans FROM "client_address" s LEFT JOIN "address" t ON s.address_id=t.address_id WHERE t.address_id IS NULL
UNION ALL
SELECT 'restaurant -> address' AS fk, count(*) AS orphans FROM "restaurant" s LEFT JOIN "address" t ON s.address_id=t.address_id WHERE t.address_id IS NULL
UNION ALL
SELECT 'courier_pay -> courier' AS fk, count(*) AS orphans FROM "courier_pay" s LEFT JOIN "courier" t ON s.courier_id=t.courier_id WHERE t.courier_id IS NULL
UNION ALL
SELECT 'product -> product_category' AS fk, count(*) AS orphans FROM "product" s LEFT JOIN "product_category" t ON s.product_category_id=t.product_category_id WHERE t.product_category_id IS NULL
UNION ALL
SELECT 'product -> restaurant' AS fk, count(*) AS orphans FROM "product" s LEFT JOIN "restaurant" t ON s.restaurant_id=t.restaurant_id WHERE t.restaurant_id IS NULL
UNION ALL
SELECT 'order -> courier' AS fk, count(*) AS orphans FROM "order" s LEFT JOIN "courier" t ON s.courier_id=t.courier_id WHERE t.courier_id IS NULL
UNION ALL
SELECT 'order -> client' AS fk, count(*) AS orphans FROM "order" s LEFT JOIN "client" t ON s.client_id=t.client_id WHERE t.client_id IS NULL
UNION ALL
SELECT 'order -> address' AS fk, count(*) AS orphans FROM "order" s LEFT JOIN "address" t ON s.address_id=t.address_id WHERE t.address_id IS NULL
UNION ALL
SELECT 'order -> restaurant' AS fk, count(*) AS orphans FROM "order" s LEFT JOIN "restaurant" t ON s.restaurant_id=t.restaurant_id WHERE t.restaurant_id IS NULL
UNION ALL
SELECT 'order_structure -> order' AS fk, count(*) AS orphans FROM "order_structure" s LEFT JOIN "order" t ON s.order_id=t.order_id WHERE t.order_id IS NULL
UNION ALL
SELECT 'order_structure -> product' AS fk, count(*) AS orphans FROM "order_structure" s LEFT JOIN "product" t ON s.product_id=t.product_id WHERE t.product_id IS NULL
UNION ALL
SELECT 'payment -> order' AS fk, count(*) AS orphans FROM "payment" s LEFT JOIN "order" t ON s.order_id=t.order_id WHERE t.order_id IS NULL
UNION ALL
SELECT 'review -> client' AS fk, count(*) AS orphans FROM "review" s LEFT JOIN "client" t ON s.client_id=t.client_id WHERE t.client_id IS NULL
UNION ALL
SELECT 'review -> order' AS fk, count(*) AS orphans FROM "review" s LEFT JOIN "order" t ON s.order_id=t.order_id WHERE t.order_id IS NULL
UNION ALL
SELECT 'order -> client_address',count(*) FROM "order" s LEFT JOIN client_address t ON (s.client_id,s.address_id)=(t.client_id,t.address_id) WHERE t.client_id IS NULL
UNION ALL
SELECT 'review -> order/client',count(*) FROM review s LEFT JOIN "order" t ON (s.order_id,s.client_id)=(t.order_id,t.client_id) WHERE t.order_id IS NULL;
```

Ожидается: все 0.

Факт: По каждой из 17 проверенных FK-связей orphans=0.

Вердикт: OK.

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT o.order_id, count(p.payment_id) AS successes
FROM "order" o LEFT JOIN payment p ON p.order_id=o.order_id AND p.status='успех'
GROUP BY o.order_id HAVING count(p.payment_id) <> 1;
```

Ожидается: пусто.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.

Факт: Получено: `0`.

Вердикт: OK.

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
SELECT 'product' AS entity, p.product_id AS id, p.rating, round(avg(r.rating),2) AS expected
FROM product p LEFT JOIN review r ON r.entity_type='блюдо' AND r.entity_id=p.product_id
GROUP BY p.product_id HAVING p.rating IS DISTINCT FROM round(avg(r.rating),2)
UNION ALL
SELECT 'restaurant', p.restaurant_id, p.rating, round(avg(r.rating),2)
FROM restaurant p LEFT JOIN review r ON r.entity_type='ресторан' AND r.entity_id=p.restaurant_id
GROUP BY p.restaurant_id HAVING p.rating IS DISTINCT FROM round(avg(r.rating),2);
```

Ожидается: пусто; проверяются оба вида агрегата, включая NULL без отзывов.

Факт: Запрос вернул 0 строк.

Вердикт: OK.

---

### D.15. Состав, суммы и даты генератора

```sql
SELECT count(*) AS bad_orders FROM "order" o
WHERE NOT EXISTS (SELECT FROM order_structure s WHERE s.order_id=o.order_id)
   OR o.order_amount IS DISTINCT FROM (SELECT round(sum(s.quantity*s.unit_price),2) FROM order_structure s WHERE s.order_id=o.order_id);
SELECT count(*) AS bad_dates FROM "order"
WHERE order_timestamp < date_trunc('month',current_date)-interval '5 months'
   OR order_timestamp > localtimestamp OR delivery_timestamp > localtimestamp;
SELECT count(*) AS bad_reviews FROM review r JOIN "order" o USING(order_id)
WHERE r.client_id<>o.client_id
 OR (r.entity_type='ресторан' AND r.entity_id<>o.restaurant_id)
 OR (r.entity_type='заказ' AND r.entity_id<>o.order_id)
 OR (r.entity_type='блюдо' AND NOT EXISTS(SELECT FROM order_structure s WHERE s.order_id=r.order_id AND s.product_id=r.entity_id));
SELECT count(*) AS months, min(make_date(year,month,1)), max(make_date(year,month,1)) FROM
 (SELECT DISTINCT year,month FROM courier_pay) m;
```

Ожидается: первые три запроса возвращают 0. Последний запрос возвращает 6 месяцев: от первого дня месяца пять месяцев назад до первого дня текущего месяца.

Факт: пустых или несогласованных заказов, недопустимых дат и неверных целей отзывов не найдено. История выплат охватывает шесть календарных месяцев, включая текущий.

Вердикт: OK.

### D.15a. Даты оплат, отзывов и найма

```sql
SELECT 'payment' AS entity,count(*) AS invalid_dates FROM payment
WHERE transaction_timestamp < date_trunc('month',current_date)-interval '5 months' OR transaction_timestamp>localtimestamp
UNION ALL SELECT 'review',count(*) FROM review
WHERE review_timestamp < date_trunc('month',current_date)-interval '5 months' OR review_timestamp>localtimestamp
UNION ALL SELECT 'courier',count(*) FROM courier
WHERE hire_date>current_date OR dismissal_date>current_date OR dismissal_date<hire_date;
```

Ожидается: три нуля: история не выходит в будущее и даты увольнения согласованы с наймом.

Факт: Получено: `payment|0`; `review|0`; `courier|0`.

Вердикт: OK.

### D.16. Неверный аргумент генератора

```sql
BEGIN;
SAVEPOINT bad_input;
CALL insert_test_data(0);
ROLLBACK TO SAVEPOINT bad_input;
CALL insert_test_data(-1);
ROLLBACK TO SAVEPOINT bad_input;
CALL insert_test_data(NULL);
ROLLBACK TO SAVEPOINT bad_input;
CALL insert_test_data(429496730);
ROLLBACK TO SAVEPOINT bad_input;
ROLLBACK;
```

Ожидается: четыре ошибки 22023, без добавления данных.

Факт: Получены четыре ошибки 22023; все операции откатились к savepoint.

Вердикт: OK.

## E. Функции и процедуры

### E.1. Контрольный набор и add_product

Набор создаёт клиентов ivan/petr, рестораны Основной/Без заказов/В приготовлении/Равные лидеры, доставленные и недоставленные заказы; заказ-1…заказ-8 — метки заказов. UUID генерируются на сервере. Транзакция остаётся открытой до конца E.5i; E.6–E.7 используют отдельную транзакцию.

```sql
BEGIN;
CALL erase_test_data();
DO $$
DECLARE
    ca uuid; cb uuid; addr uuid; restaurant_address uuid; co uuid; cat uuid;
    restaurants uuid[] := '{}'; products uuid[] := '{}'; orders uuid[] := '{}';
    id uuid; i integer; amount numeric;
    ridx integer; cidx uuid;
BEGIN
    INSERT INTO address(street,house_number) VALUES ('Тестовая улица','1') RETURNING address_id INTO addr;
    INSERT INTO client(login,password,phone_number) VALUES ('ivan',md5('пароль'),'+79990000001') RETURNING client_id INTO ca;
    INSERT INTO client(login,password,phone_number) VALUES ('petr',md5('пароль'),'+79990000002') RETURNING client_id INTO cb;
    INSERT INTO client_address VALUES (ca,addr),(cb,addr);
    INSERT INTO courier(fio,phone_number) VALUES ('Иванов Иван Иванович','+79990000003') RETURNING courier_id INTO co;
    INSERT INTO product_category(product_category_name) VALUES ('Тестовые данные') RETURNING product_category_id INTO cat;
    FOR i IN 1..4 LOOP
        INSERT INTO address(street,house_number) VALUES ('Ресторанная улица',i::text) RETURNING address_id INTO restaurant_address;
        INSERT INTO restaurant(restaurant_name,address_id,description,work_start,work_end,company_details)
        VALUES ((ARRAY['Основной','Без заказов','В приготовлении','Равные лидеры'])[i],restaurant_address,'Тестовые данные','09:00','22:00','Тестовые данные')
        RETURNING restaurant_id INTO id;
        restaurants := array_append(restaurants,id);
    END LOOP;
    CALL add_product(p_restaurant_id=>restaurants[1],p_product_category_id=>cat,p_name=>'Пицца',
        p_price=>1000,p_rating=>NULL,p_status=>'доступно',p_description=>'Тестовые данные',p_photo_url=>'https://example.com/a.jpg');
    SELECT product_id INTO id FROM product WHERE product_name='Пицца';
    products := array_append(products,id);
    CALL add_product(restaurants[1],cat,'Паста',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO id FROM product WHERE product_name='Паста'; products := array_append(products,id);
    CALL add_product(restaurants[4],cat,'Суп',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO id FROM product WHERE product_name='Суп'; products := array_append(products,id);
    CALL add_product(restaurants[4],cat,'Салат',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO id FROM product WHERE product_name='Салат'; products := array_append(products,id);
    CALL add_product(restaurants[3],cat,'Роллы',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO id FROM product WHERE product_name='Роллы'; products := array_append(products,id);
    CALL add_product(restaurants[1],cat,'Подарок',0,NULL,'нет_в_наличии','Блюдо с нулевой ценой');

    FOR i IN 1..8 LOOP
        ridx := CASE WHEN i<=5 THEN 1 WHEN i<=7 THEN 4 ELSE 3 END;
        cidx := CASE WHEN i IN (3,7) THEN cb ELSE ca END;
        amount := (ARRAY[1000,2000,4500,100000,100000,1000,1000,1000])[i];
        INSERT INTO "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
            order_amount,status,description)
        VALUES (co,cidx,addr,restaurants[ridx],localtimestamp-interval '1 hour',
            CASE WHEN i IN (1,2,3,6,7) THEN localtimestamp END,amount,
            CASE WHEN i IN (1,2,3,6,7) THEN 'доставлен'::order_status
                 WHEN i=4 THEN 'отменён'::order_status ELSE 'готовится'::order_status END,'заказ-'||i)
        RETURNING order_id INTO id;
        orders := array_append(orders,id);
        IF i<=5 THEN
            INSERT INTO order_structure VALUES (id,products[1],CASE WHEN i=3 THEN .5 WHEN i>=4 THEN 100 ELSE 1 END,1000);
            IF i IN (2,3) THEN INSERT INTO order_structure VALUES (id,products[2],CASE WHEN i=2 THEN 1 ELSE 4 END,1000); END IF;
        ELSE
            INSERT INTO order_structure VALUES (id,products[i-3],1,1000);
        END IF;
    END LOOP;
    INSERT INTO payment(order_id,payment_type,amount,transaction_id,status)
    SELECT order_id,'карта',total_amount,order_id::text,'успех' FROM "order";
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;

END;
$$;
SELECT product_name,price,rating,photo_url FROM product ORDER BY product_name;
SELECT count(*) AS orders FROM "order";
```

Ожидается: 6 блюд: «Пицца», «Паста», «Суп», «Салат», «Роллы», «Подарок»; цена «Подарка» 0, остальные по 1000; рейтинги NULL; у блюда «Пицца» задан URL, у блюда «Паста» фото NULL. Восемь заказов.

Факт: созданы 6 блюд и 8 заказов. Цены всех блюд, кроме «Подарка», равны 1000; цена «Подарка» 0; рейтинги NULL. У блюда «Пицца» сохранён URL, у блюда «Паста» photo_url=NULL.

Вердикт: OK.

### E.2. Несуществующий ресторан

```sql
SAVEPOINT invalid_case;
DO $$ DECLARE r uuid; c uuid; BEGIN SELECT restaurant_id INTO r FROM restaurant WHERE restaurant_name='Основной'; SELECT product_category_id INTO c FROM product_category LIMIT 1; CALL add_product('00000000-0000-0000-0000-000000000000',c,'Некорректные данные',1000,NULL,'доступно','Тестовые данные'); END $$;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.2a. Несуществующая категория

```sql
SAVEPOINT invalid_case;
DO $$ DECLARE r uuid; c uuid; BEGIN SELECT restaurant_id INTO r FROM restaurant WHERE restaurant_name='Основной'; SELECT product_category_id INTO c FROM product_category LIMIT 1; CALL add_product(r,'00000000-0000-0000-0000-000000000000','Некорректные данные',1000,NULL,'доступно','Тестовые данные'); END $$;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.2b. Отрицательная цена

```sql
SAVEPOINT invalid_case;
DO $$ DECLARE r uuid; c uuid; BEGIN SELECT restaurant_id INTO r FROM restaurant WHERE restaurant_name='Основной'; SELECT product_category_id INTO c FROM product_category LIMIT 1; CALL add_product(r,c,'Некорректные данные',-1,NULL,'доступно','Тестовые данные'); END $$;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.2c. NULL цена

```sql
SAVEPOINT invalid_case;
DO $$ DECLARE r uuid; c uuid; BEGIN SELECT restaurant_id INTO r FROM restaurant WHERE restaurant_name='Основной'; SELECT product_category_id INTO c FROM product_category LIMIT 1; CALL add_product(r,c,'Некорректные данные',NULL,NULL,'доступно','Тестовые данные'); END $$;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23502; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23502; откат к savepoint выполнен.

Вердикт: OK.

### E.2d. Начальный рейтинг

```sql
DO $$ DECLARE r uuid; c uuid; BEGIN
SELECT restaurant_id INTO r FROM restaurant WHERE restaurant_name='Основной';
SELECT product_category_id INTO c FROM product_category LIMIT 1;
CALL add_product(r,c,'Блюдо с начальным рейтингом',1000,4.5,'доступно','Тестовые данные'); END $$;
SELECT rating FROM product WHERE product_name='Блюдо с начальным рейтингом';
DELETE FROM product WHERE product_name='Блюдо с начальным рейтингом';
```

Ожидается: 4.50.

Факт: Получено: `4.50`; `DELETE 1`.

Вердикт: OK.

### E.3. Вставка и изменение отзывов

```sql
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT o.client_id,p.product_id,'блюдо',o.order_id,'Отзыв о блюде',
 CASE o.description WHEN 'заказ-1' THEN 3 WHEN 'заказ-2' THEN 4 ELSE 5 END
FROM "order" o CROSS JOIN product p
WHERE o.description IN ('заказ-1','заказ-2','заказ-3') AND p.product_name='Пицца';
SELECT rating FROM product WHERE product_name='Пицца';
UPDATE review SET rating=1 WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1');
SELECT rating FROM product WHERE product_name='Пицца';
UPDATE review SET entity_type='ресторан',entity_id=(SELECT restaurant_id FROM restaurant WHERE restaurant_name='Основной')
WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1');
SELECT product_name,rating FROM product WHERE product_name='Пицца';
SELECT restaurant_name,rating FROM restaurant WHERE restaurant_name='Основной';
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT client_id,restaurant_id,'ресторан',order_id,'Отзыв о ресторане',5 FROM "order" WHERE description='заказ-2';
SELECT rating FROM restaurant WHERE restaurant_name='Основной';
```

Ожидается: рейтинг Пицца: 4.00 -> 3.33 -> 4.50; Основной: 1.00 -> 3.00. При переносе отзыва пересчитаны старая и новая цели.

Факт: Получены рейтинги Пицца: 4.00 -> 3.33 -> 4.50; Основной: 1.00 -> 3.00.

Вердикт: OK.

### E.3a. Чужой автор

```sql
SAVEPOINT invalid_case;
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT c.client_id,o.order_id,'заказ',o.order_id,'Некорректные данные',5
FROM "order" o CROSS JOIN client c WHERE o.description='заказ-1' AND c.login='petr' ;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.3b. Блюдо не из заказа

```sql
SAVEPOINT invalid_case;
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT o.client_id,p.product_id,'блюдо',o.order_id,'Некорректные данные',5
FROM "order" o CROSS JOIN product p WHERE o.description='заказ-1' AND p.product_name='Суп' ;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.3c. Повторный отзыв на объект

```sql
SAVEPOINT invalid_case;
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT client_id,entity_id,entity_type,order_id,'Повторный отзыв',rating FROM review LIMIT 1;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23505; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23505; откат к savepoint выполнен.

Вердикт: OK.

### E.3d. Отзыв на сам заказ

```sql
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT client_id,order_id,'заказ',order_id,'Отзыв о заказе',5 FROM "order" WHERE description='заказ-1';
SELECT rating FROM restaurant WHERE restaurant_name='Основной';
SAVEPOINT invalid_case;
UPDATE review SET entity_id=exts.uuid_generate_v4() WHERE entity_type='заказ';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: вставка успешна, Основной остаётся 3.00; несовпадающий entity_id отклонён с SQLSTATE 23514.

Факт: Отзыв на заказ вставлен; Основной остался 3.00. Несовпадающая цель отклонена с 23514; откат к savepoint успешен.

Вердикт: OK.

### E.3e. Ресторан вне заказа

```sql
SAVEPOINT invalid_case;
INSERT INTO review(client_id,entity_id,entity_type,order_id,description,rating)
SELECT o.client_id,r.restaurant_id,'ресторан',o.order_id,'Некорректные данные',5
FROM "order" o CROSS JOIN restaurant r WHERE o.description='заказ-1' AND r.restaurant_name='Без заказов';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.4. Удаление отзывов

```sql
DELETE FROM review WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-2') AND entity_type='ресторан';
SELECT rating FROM restaurant WHERE restaurant_name='Основной';
DELETE FROM review;
SELECT count(*) AS nonnull_ratings FROM product WHERE rating IS NOT NULL;
SELECT count(*) AS nonnull_ratings FROM restaurant WHERE rating IS NOT NULL;
```

Ожидается: после частичного удаления Основной=1.00; после удаления всех отзывов оба счётчика 0.

Факт: После частичного удаления Основной=1.00; после полного удаления оба счётчика nonnull_ratings=0.

Вердикт: OK.

### E.5. Точные результаты статистики

```sql
SELECT * FROM get_statistic() ORDER BY restaurant_name;
CREATE TEMP TABLE tie_samples(product_name varchar,user_login varchar) ON COMMIT DROP;
DO $$ BEGIN FOR i IN 1..20 LOOP
  INSERT INTO tie_samples SELECT best_product_name,best_user FROM get_statistic() WHERE restaurant_name='Равные лидеры';
END LOOP; END $$;
SELECT array_agg(DISTINCT product_name),array_agg(DISTINCT user_login) FROM tie_samples;
```

Ожидается: Основной: Паста, 8250, 2750, ivan. Без заказов/В приготовлении: лидеры NULL, сумма 0, среднее NULL. Равные лидеры: Суп или Салат, 2200, 1100, ivan или petr. Повторные выборы допускают только этих лидеров; появления всех вариантов за 20 вызовов не требуется.

Факт: Основной: Паста/8250/2750/ivan. Без заказов и В приготовлении: 0, среднее и лидеры NULL. Равные лидеры: 2200/1100; за 20 отдельных вызовов выбраны только Суп/Салат и ivan/petr.

Вердикт: OK.

### E.5a. UNIQUE логина

```sql
SAVEPOINT invalid_case;
INSERT INTO client(login,password,phone_number) VALUES('ivan',md5('x'),'+79998887766');
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23505; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23505; откат к savepoint выполнен.

Вердикт: OK.

### E.5b. CHECK количества

```sql
SAVEPOINT invalid_case;
UPDATE order_structure SET quantity=0 WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1');
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.5c. Чужой адрес

```sql
SAVEPOINT invalid_case;
INSERT INTO address(street,house_number) VALUES('Чужая улица','1'); UPDATE "order" SET address_id=(SELECT address_id FROM address WHERE street='Чужая улица') WHERE description='заказ-1';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23503; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23503; откат к savepoint выполнен.

Вердикт: OK.

### E.5d. Смешанные рестораны

```sql
SAVEPOINT invalid_case;
INSERT INTO order_structure SELECT o.order_id,p.product_id,1,1000 FROM "order" o CROSS JOIN product p WHERE o.description='заказ-1' AND p.product_name='Суп';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.5e. Вторая успешная оплата

```sql
SAVEPOINT invalid_case;
INSERT INTO payment(order_id,payment_type,amount,transaction_id,status) SELECT order_id,'карта',total_amount,'повторная-оплата','успех' FROM "order" WHERE description='заказ-1';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23505; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23505; откат к savepoint выполнен.

Вердикт: OK.

### E.5f. Неверная сумма оплаты

```sql
SAVEPOINT invalid_case;
UPDATE payment SET amount=1 WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1');
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.5g. Нет успешной оплаты

```sql
SAVEPOINT invalid_case;
DELETE FROM payment WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1'); SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.5h. Нет позиций заказа

```sql
SAVEPOINT invalid_case;
DELETE FROM order_structure WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1'); SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 23514; после отката к savepoint можно продолжать E.

Факт: Получена ожидаемая ошибка 23514; откат к savepoint выполнен.

Вердикт: OK.

### E.5h1. Ручная запись generated-комиссии

```sql
SAVEPOINT invalid_case;
UPDATE "order" SET commission=0 WHERE description='заказ-1';
ROLLBACK TO SAVEPOINT invalid_case;
```

Ожидается: ошибка SQLSTATE 428C9.

Факт: Получена ожидаемая ошибка 428C9; откат к savepoint выполнен.

Вердикт: OK.

### E.5i. Агрегированный статус оплаты

```sql
DELETE FROM payment WHERE order_id=(SELECT order_id FROM "order" WHERE description='заказ-1');
INSERT INTO payment(order_id,payment_type,amount,transaction_id,status)
SELECT order_id,'карта',total_amount,'пробная-оплата','ошибка' FROM "order" WHERE description='заказ-1';
SELECT pay_status FROM "order" WHERE description='заказ-1';
UPDATE payment SET status='в_обработке' WHERE transaction_id='пробная-оплата';
SELECT pay_status FROM "order" WHERE description='заказ-1';
UPDATE payment SET status='успех' WHERE transaction_id='пробная-оплата';
SELECT pay_status FROM "order" WHERE description='заказ-1';
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
```

Ожидается: ошибка -> ожидает -> оплачен; проверка ограничений успешна. Промежуточные неоплаченные состояния не фиксируются.

Факт: Получены ошибка -> ожидает -> оплачен. SET CONSTRAINTS ALL IMMEDIATE выполнен без ошибок, затем ROLLBACK.

Вердикт: OK.

### E.6. Зарплата: пороги, месяц и уволенный курьер

```sql
BEGIN;
CALL erase_test_data();
CREATE TEMP TABLE salary_cases(courier_id uuid, deliveries integer, initial_rate numeric, next_rate numeric) ON COMMIT DROP;
DO $$
DECLARE
    c uuid; a uuid; ra uuid; r uuid; cat uuid; p uuid; co uuid; i integer;
    start_at timestamp := date_trunc('month',localtimestamp);
    deliveries integer[] := ARRAY[0,150,151,250,251,500,501,2];
    next_rates numeric[] := ARRAY[.1,.1,.2,.2,.3,.3,.5,.4];
BEGIN
    INSERT INTO client(login,password,phone_number) VALUES ('kurier_test',md5('пароль'),'+79990000001') RETURNING client_id INTO c;
    INSERT INTO address(street,house_number) VALUES ('Клиентская улица','1') RETURNING address_id INTO a;
    INSERT INTO client_address VALUES (c,a);
    INSERT INTO address(street,house_number) VALUES ('Ресторанная улица','1') RETURNING address_id INTO ra;
    INSERT INTO restaurant(restaurant_name,address_id,description,work_start,work_end,company_details)
        VALUES ('Тестовые данные',ra,'Тестовые данные','09:00','22:00','Тестовые данные') RETURNING restaurant_id INTO r;
    INSERT INTO product_category(product_category_name) VALUES ('Тестовые данные') RETURNING product_category_id INTO cat;
    CALL add_product(r,cat,'Тестовые данные',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO p FROM product LIMIT 1;
    FOR i IN 1..8 LOOP
        INSERT INTO courier(fio,phone_number,status,hire_date,dismissal_date,coefficient)
        VALUES ('Курьер '||i,'+79990000002',CASE WHEN i=8 THEN 'уволен'::courier_status ELSE 'свободен'::courier_status END,
            (start_at-interval '2 months')::date,CASE WHEN i=8 THEN current_date END,CASE WHEN i=8 THEN .4 ELSE .3 END)
        RETURNING courier_id INTO co;
        INSERT INTO salary_cases VALUES (co,deliveries[i],CASE WHEN i=8 THEN .4 ELSE .3 END,next_rates[i]);
        WITH added AS (
            INSERT INTO "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
                order_amount,status,description)
            SELECT co,c,a,r,start_at,localtimestamp,1000,'доставлен','Тестовые данные'
            FROM generate_series(1,deliveries[i]) RETURNING order_id
        ) INSERT INTO order_structure(order_id,product_id,quantity,unit_price)
          SELECT order_id,p,1,1000 FROM added;
    END LOOP;
    -- Недоставленные заказы текущего месяца и доставки за обеими границами месяца.
    SELECT s.courier_id INTO co FROM salary_cases s WHERE s.deliveries=0;
    WITH added AS (
        INSERT INTO "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
            order_amount,status,description)
        SELECT co,c,a,r,start_at,NULL,1000,s,'Не участвует в расчёте'
        FROM unnest(ARRAY['создан','готовится','в_доставке','отменён']::order_status[]) s
        UNION ALL
        SELECT co,c,a,r,t,t+interval '1 hour',1000,'доставлен','За пределами месяца'
        FROM unnest(ARRAY[start_at-interval '1 microsecond',start_at+interval '1 month']) t
        RETURNING order_id
    ) INSERT INTO order_structure SELECT order_id,p,1,1000 FROM added;
END;
$$;
INSERT INTO payment(order_id,payment_type,amount,transaction_id,status)
SELECT o.order_id,'карта',o.total_amount,o.order_id::text,'успех' FROM "order" o
WHERE NOT EXISTS(SELECT FROM payment p WHERE p.order_id=o.order_id);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
CALL courier_salary();
SELECT s.deliveries,s.initial_rate,cp.coefficient_used,cp.amount,
 round(s.deliveries*100*s.initial_rate,2) AS expected_amount,
 c.coefficient,s.next_rate AS expected_next_rate
FROM salary_cases s JOIN courier c USING(courier_id) JOIN courier_pay cp USING(courier_id)
ORDER BY s.deliveries;
```

Ожидается: для 0/150/151/250/251/500/501 доставок следующий коэффициент .1/.1/.2/.2/.3/.3/.5; сумма deliveries×100×.3. Уволенный с 2 доставками получает 80, коэффициент остаётся .4. Недоставленные и заказы вне месяца исключены.

Факт: Получены 8 выплат. Все amount совпали с expected_amount, коэффициенты — с expected_next_rate. Уволенному начислено 80.00 с сохранением .4; для 501 доставки начислено 15030.00 с исходным .3 и новым .5.

Вердикт: OK.

### E.7. Повторный расчёт

```sql
CREATE TEMP TABLE first_payouts ON COMMIT DROP AS SELECT * FROM courier_pay;
CALL courier_salary();
SELECT * FROM courier_pay EXCEPT SELECT * FROM first_payouts;
SELECT * FROM first_payouts EXCEPT SELECT * FROM courier_pay;
SELECT count(*) FROM courier_pay;
ROLLBACK;
```

Ожидается: обе разности пусты; выплат 8, суммы и coefficient_used не изменились.

Факт: Обе разности пусты; число выплат 8. Суммы и исходные коэффициенты сохранены.

Вердикт: OK.

## F. Представление `how_much_money`

### F.1. Контрольные месяцы и колонки

```sql
BEGIN;
CALL erase_test_data();
DO $$
DECLARE c uuid; a uuid; ra uuid; r uuid; cat uuid; p uuid; co uuid; id uuid; i integer;
BEGIN
    INSERT INTO client(login,password,phone_number) VALUES ('finansy_test',md5('пароль'),'+79990000001') RETURNING client_id INTO c;
    INSERT INTO address(street,house_number) VALUES ('Клиентская улица','1') RETURNING address_id INTO a;
    INSERT INTO client_address VALUES(c,a);
    INSERT INTO address(street,house_number) VALUES ('Ресторанная улица','1') RETURNING address_id INTO ra;
    INSERT INTO restaurant(restaurant_name,address_id,description,work_start,work_end,company_details)
        VALUES ('Тестовые данные',ra,'Тестовые данные','09:00','22:00','Тестовые данные') RETURNING restaurant_id INTO r;
    INSERT INTO product_category(product_category_name) VALUES ('Тестовые данные') RETURNING product_category_id INTO cat;
    CALL add_product(r,cat,'Тестовые данные',1000,NULL,'доступно','Тестовые данные');
    SELECT product_id INTO p FROM product LIMIT 1;
    INSERT INTO courier(fio,phone_number) VALUES ('Тестовые данные','+79990000002') RETURNING courier_id INTO co;
    INSERT INTO courier_pay VALUES (2025,12,co,10,.1),(2026,1,co,0,.1),(2026,2,co,20,.1);
    FOR i IN 1..3 LOOP
        INSERT INTO "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
            order_amount,status,description)
        VALUES (co,c,a,r,CASE WHEN i=1 THEN timestamp '2025-12-31 23:59:59' ELSE timestamp '2026-02-01' END,
            CASE WHEN i<=2 THEN timestamp '2026-02-01 01:00' END,
            i*1000,CASE WHEN i<=2 THEN 'доставлен'::order_status ELSE 'отменён'::order_status END,'Тестовые данные')
        RETURNING order_id INTO id;
        INSERT INTO order_structure VALUES(id,p,i,1000);
    END LOOP;
END;
$$;
INSERT INTO payment(order_id,payment_type,amount,transaction_id,status)
SELECT o.order_id,'карта',o.total_amount,o.order_id::text,'успех' FROM "order" o
WHERE NOT EXISTS(SELECT FROM payment p WHERE p.order_id=o.order_id);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT column_name,data_type FROM information_schema.columns
WHERE table_schema='rudenko_food' AND table_name='how_much_money' ORDER BY ordinal_position;
```

Ожидается: year_month text; остальные семь колонок numeric: sum_no_commission, sum_with_commission, commission, prev_commission, commission_diff, courier_pay, net_profit.

Факт: Получены все 8 колонок: year_month имеет тип text, остальные numeric. Отложенные ограничения контрольных заказов проверены без ошибок.

Вердикт: OK.

### F.2. Непрерывный календарь и переход года

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: три строки: 2025-12, 2026-01, 2026-02; отменённый заказ исключён. Суммы без/с комиссией: 1000/1100, 0/0, 2000/2200.

Факт: Получены 2025-12, 2026-01, 2026-02; суммы 1000/1100, 0/0, 2000/2200.

Вердикт: OK.

### F.3. Месяц без заказов и предыдущая комиссия

```sql
SELECT year_month,commission,prev_commission,commission_diff FROM how_much_money ORDER BY year_month;
```

Ожидается: комиссии 100/0/200, предыдущие NULL/100/0, разности NULL/-100/200.

Факт: Комиссии 100/0/200; prev_commission NULL/100/0; commission_diff NULL/-100/200.

Вердикт: OK.

### F.4. Фактические выплаты и прибыль

```sql
SELECT year_month,courier_pay,net_profit FROM how_much_money ORDER BY year_month;
UPDATE courier_pay SET amount=5 WHERE year=2026 AND month=1;
SELECT net_profit FROM how_much_money WHERE year_month='2026-01';
ROLLBACK;
```

Ожидается: выплаты 10/0/20, прибыль 90/0/180. После добавления выплаты в пустом месяце прибыль января -5.

Факт: Выплаты 10/0/20; прибыль 90/0/180. После UPDATE прибыль января -5.00; изменения откатились.

Вердикт: OK.

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'rudenko_food';
```

Ожидается: `rudenko_food`, `true`, `true` (полный доступ).

Факт: Получено: `rudenko_food|t|t`.

Вердикт: OK.

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'rudenko_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).

Факт: Для 12 таблиц получены SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES и TRIGGER; представление также доступно для чтения.

Вердикт: OK.

### G.3. `information_schema` читается под `inspector`

```sql
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'rudenko_food' AND table_type='BASE TABLE';
```

Ожидается: 12 (количество таблиц).

Факт: Получено: `12`.

Вердикт: OK.

### G.4. `pg_catalog` читается под `inspector`

```sql
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'rudenko_food';
```

Ожидается: 12.

Факт: Получено: `12`.

Вердикт: OK.

### G.5. Все процедуры/функции работают под `inspector`

```sql
BEGIN;
SET LOCAL search_path TO rudenko_food, exts;
CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;
ROLLBACK;

```

Ожидается: без `permission denied`.

Факт: Генерация, очистка, расчёт зарплаты, статистика и финансовый отчёт выполнены без permission denied. add_product и работа с отзывами отдельно выполнены под этой же ролью в E.

Вердикт: OK.

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. План реального запроса

Проверяется тело функции: EXPLAIN вызова get_statistic() может показывать только Function Scan.

```sql
EXPLAIN (ANALYZE, BUFFERS)
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
```

Ожидается: однократное чтение базовой таблицы order для delivered; повторно используется CTE. В теле нет оконных функций или коррелированных подзапросов на каждый ресторан. Время зависит от среды; порога в миллисекундах нет.

Факт: в плане одно чтение базовой таблицы order и повторное использование результата через CTE Scan on delivered.

Вердикт: OK.

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.

Факт: Все 12 счётчиков равны 0.

Вердикт: OK.

### I.2. Повторный `erase_test_data` не падает

```sql
CREATE TEMP TABLE saved_relations AS
SELECT oid FROM pg_class WHERE relnamespace='rudenko_food'::regnamespace;
CALL erase_test_data();
SELECT count(*) AS missing_objects FROM saved_relations s LEFT JOIN pg_class c USING(oid) WHERE c.oid IS NULL;
```

Ожидается: без ошибок; missing_objects = 0, OID отношений сохранены.

Факт: Повторная очистка успешна; missing_objects=0, OID отношений сохранены.

Вердикт: OK.

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.

Факт: Повторная генерация успешна; заказов 50.

Вердикт: OK.

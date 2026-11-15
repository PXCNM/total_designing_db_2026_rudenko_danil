CREATE OR REPLACE FUNCTION prevent_restaurant_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id THEN
        RAISE EXCEPTION 'Изменение restaurant_id запрещено' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER product_restaurant_change_check
BEFORE UPDATE OF restaurant_id ON product
FOR EACH ROW EXECUTE FUNCTION prevent_restaurant_change();
CREATE TRIGGER order_restaurant_change_check
BEFORE UPDATE OF restaurant_id ON "order"
FOR EACH ROW EXECUTE FUNCTION prevent_restaurant_change();

CREATE OR REPLACE FUNCTION check_order_products()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    order_restaurant uuid;
    product_restaurant uuid;
BEGIN
    SELECT restaurant_id INTO order_restaurant FROM "order" WHERE order_id = NEW.order_id;
    SELECT restaurant_id INTO product_restaurant FROM product WHERE product_id = NEW.product_id;
    IF order_restaurant IS DISTINCT FROM product_restaurant THEN
        RAISE EXCEPTION 'Блюдо и заказ должны пренадлежать одному ресторану' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_products_check
BEFORE INSERT OR UPDATE OF order_id, product_id ON order_structure
FOR EACH ROW EXECUTE FUNCTION check_order_products();

CREATE OR REPLACE FUNCTION check_order_amount_of(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    expected numeric(12,2);
    actual numeric(12,2);
    n bigint;
BEGIN
    SELECT order_amount INTO actual FROM "order" WHERE order_id = p_order_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    SELECT count(*), round(coalesce(sum(quantity * unit_price), 0), 2)
	INTO n, expected
    FROM order_structure WHERE order_id = p_order_id;
    IF n = 0 OR expected <> actual THEN
        RAISE EXCEPTION 'Сумма товаров заказа (%) должна совпадать с order_amount (%)', expected, actual USING ERRCODE = '23514';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION check_order_amount()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    affected_order_id uuid;
BEGIN
    affected_order_id := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.order_id
        ELSE NEW.order_id
    END;
    PERFORM check_order_amount_of(affected_order_id);
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_amount_check_order
AFTER INSERT OR UPDATE ON "order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_amount();
CREATE CONSTRAINT TRIGGER order_amount_check_lines
AFTER INSERT OR UPDATE OR DELETE ON order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_amount();

CREATE OR REPLACE FUNCTION prevent_order_item_move()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.order_id IS DISTINCT FROM OLD.order_id THEN
        RAISE EXCEPTION 'Нельзя переносить позицию в другой заказ' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_item_move_check
BEFORE UPDATE OF order_id ON order_structure
FOR EACH ROW EXECUTE FUNCTION prevent_order_item_move();

CREATE OR REPLACE FUNCTION check_order_payment_amounts()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM payment p
        JOIN "order" o USING (order_id)
        WHERE o.order_id = NEW.order_id AND p.amount <> o.total_amount
    ) THEN
        RAISE EXCEPTION 'Сумма оплаты должна совпадать с итоговой суммой заказа' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_payment_amount_check
AFTER UPDATE ON "order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_payment_amounts();

CREATE OR REPLACE FUNCTION check_new_payment_amount()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    total numeric(13,2);
BEGIN
    SELECT total_amount INTO total FROM "order" WHERE order_id = NEW.order_id;
    IF total IS NULL OR NEW.amount <> total THEN
        RAISE EXCEPTION 'Сумма платежа должна совпадать с итоговой суммой заказа' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_amount_check
BEFORE INSERT OR UPDATE OF order_id, amount ON payment
FOR EACH ROW EXECUTE FUNCTION check_new_payment_amount();

CREATE OR REPLACE FUNCTION check_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    expected order_pay_status;
BEGIN
	SELECT CASE
		WHEN bool_or(status = 'успех') THEN 'оплачен'::order_pay_status
		WHEN bool_and(status = 'ошибка') THEN 'ошибка'::order_pay_status
		ELSE 'ожидает'::order_pay_status
	END INTO expected
	FROM payment WHERE order_id = NEW.order_id;
    IF NEW.pay_status IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'Статус оплаты заказа должен быть %, получено %', expected, NEW.pay_status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_pay_status_check
BEFORE UPDATE OF pay_status ON "order"
FOR EACH ROW EXECUTE FUNCTION check_order_pay_status();

CREATE OR REPLACE FUNCTION update_order_pay_status_of(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    calculated_status order_pay_status;
BEGIN
    SELECT CASE
        WHEN bool_or(status = 'успех') THEN 'оплачен'::order_pay_status
        WHEN bool_and(status = 'ошибка') THEN 'ошибка'::order_pay_status
        ELSE 'ожидает'::order_pay_status
    END INTO calculated_status
    FROM payment WHERE order_id = p_order_id;
    UPDATE "order" SET pay_status = calculated_status WHERE order_id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION update_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM update_order_pay_status_of(OLD.order_id);
    ELSE
        PERFORM update_order_pay_status_of(NEW.order_id);
        IF TG_OP = 'UPDATE' AND OLD.order_id IS DISTINCT FROM NEW.order_id THEN
            PERFORM update_order_pay_status_of(OLD.order_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_order_status
AFTER INSERT OR UPDATE OR DELETE ON payment
FOR EACH ROW EXECUTE FUNCTION update_order_pay_status();

CREATE OR REPLACE FUNCTION check_successful_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    affected_order_id uuid;
    successful_count bigint;
BEGIN
    affected_order_id := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.order_id
        ELSE NEW.order_id
    END;
    IF NOT EXISTS (
        SELECT 1 FROM "order" WHERE order_id = affected_order_id
    ) THEN
        RETURN NULL;
    END IF;
    SELECT count(*) INTO successful_count
    FROM payment WHERE order_id = affected_order_id AND status = 'успех';
    IF successful_count <> 1 THEN
        RAISE EXCEPTION 'У заказа должна быть ровно одна успешная попытка оплаты' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_payment_success_check
AFTER INSERT OR UPDATE ON "order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_successful_payment();
CREATE CONSTRAINT TRIGGER payment_success_check
AFTER INSERT OR UPDATE OR DELETE ON payment
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_successful_payment();

CREATE OR REPLACE FUNCTION check_review_target()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    order_restaurant_id uuid;
BEGIN
    SELECT restaurant_id INTO order_restaurant_id
    FROM "order" WHERE order_id = NEW.order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Заказ отзыва не существует' USING ERRCODE = '23503';
    END IF;
    IF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM order_structure
            WHERE order_id = NEW.order_id AND product_id = NEW.entity_id
        ) THEN
            RAISE EXCEPTION 'Блюдо отзыва должно входить в заказ клиента' USING ERRCODE = '23503';
        END IF;
    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NEW.entity_id <> order_restaurant_id THEN
            RAISE EXCEPTION 'Ресторан отзыва должен совпадать с рестораном заказа' USING ERRCODE = '23503';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER review_target_check
BEFORE INSERT OR UPDATE OF order_id, entity_id, entity_type ON review
FOR EACH ROW EXECUTE FUNCTION check_review_target();

CREATE OR REPLACE FUNCTION protect_reviewed_order_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM review
        WHERE entity_type = 'блюдо' AND order_id = OLD.order_id AND entity_id = OLD.product_id
    ) THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'Нельзя удалить позицию заказа с отзывом' USING ERRCODE = '23514';
        ELSIF (OLD.order_id, OLD.product_id) IS DISTINCT FROM (NEW.order_id, NEW.product_id) THEN
            RAISE EXCEPTION 'Нельзя заменить блюдо или заказ у позиции с отзывом' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER reviewed_order_item_check
BEFORE UPDATE OF order_id, product_id OR DELETE ON order_structure
FOR EACH ROW EXECUTE FUNCTION protect_reviewed_order_item();

CREATE OR REPLACE FUNCTION update_entity_rating(p_entity_type review_entity_type, p_entity_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    calculated_rating numeric(3,2);
BEGIN
    IF p_entity_type = 'заказ' THEN
        RETURN;
    END IF;
    SELECT round(avg(rating), 2) INTO calculated_rating
    FROM review WHERE entity_type = p_entity_type AND entity_id = p_entity_id;
    IF p_entity_type = 'блюдо' THEN
        UPDATE product SET rating = calculated_rating WHERE product_id = p_entity_id;
    ELSIF p_entity_type = 'ресторан' THEN
        UPDATE restaurant SET rating = calculated_rating WHERE restaurant_id = p_entity_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM update_entity_rating(OLD.entity_type, OLD.entity_id);
    ELSE
        PERFORM update_entity_rating(NEW.entity_type, NEW.entity_id);
        IF TG_OP = 'UPDATE' AND (OLD.entity_type, OLD.entity_id) IS DISTINCT FROM (NEW.entity_type, NEW.entity_id) THEN
            PERFORM update_entity_rating(OLD.entity_type, OLD.entity_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER review_rating_change
AFTER INSERT OR UPDATE OR DELETE ON review
FOR EACH ROW EXECUTE FUNCTION rating_change();

CREATE TABLE client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(64) NOT NULL CHECK (btrim(login) <> '') UNIQUE,
    password char(32) NOT NULL CHECK (password ~ '^[0-9a-fA-F]{32}$'),
    phone_number varchar(16) NOT NULL CHECK (btrim(phone_number) <> '') UNIQUE
);

CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(100) NOT NULL CHECK (btrim(street) <> ''),
    house_number varchar(10) NOT NULL CHECK (btrim(house_number) <> ''),
    apartment_office varchar(10)
);

CREATE TABLE client_address (
    client_id uuid NOT NULL REFERENCES client(client_id),
    address_id uuid NOT NULL REFERENCES address(address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL CHECK (btrim(restaurant_name) <> ''),
    address_id uuid NOT NULL UNIQUE REFERENCES address(address_id),
    description text NOT NULL CHECK (btrim(description) <> ''),
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL CHECK (btrim(company_details) <> ''),
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status restaurant_status NOT NULL DEFAULT 'активен',
    CONSTRAINT restaurant_work_hours_ck CHECK (work_end > work_start)
);

CREATE TABLE courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(100) NOT NULL CHECK (btrim(fio) <> ''),
    phone_number varchar(16) NOT NULL CHECK (btrim(phone_number) <> ''),
    status courier_status NOT NULL DEFAULT 'свободен',
    hire_date date NOT NULL DEFAULT current_date,
    dismissal_date date,
    coefficient numeric(2,1) NOT NULL DEFAULT 0.1 CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT courier_dismissal_required_ck CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT courier_employment_dates_ck CHECK (dismissal_date >= hire_date)
);

CREATE TABLE courier_pay (
    year integer NOT NULL CHECK (year BETWEEN 2000 AND 9999),
    month integer NOT NULL CHECK (month BETWEEN 1 AND 12),
    courier_id uuid NOT NULL REFERENCES courier(courier_id),
    amount numeric(12,2) NOT NULL CHECK (amount >= 0),
    coefficient_used numeric(2,1) NOT NULL CHECK (coefficient_used BETWEEN 0.1 AND 0.5),
    PRIMARY KEY (year, month, courier_id)
);

CREATE TABLE product_category (
    product_category_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    product_category_name varchar(100) NOT NULL CHECK (btrim(product_category_name) <> '')
);

CREATE TABLE product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_id uuid NOT NULL REFERENCES product_category(product_category_id),
	restaurant_id uuid NOT NULL REFERENCES restaurant(restaurant_id),
	product_name varchar(100) NOT NULL CHECK (btrim(product_name) <> ''),
    price numeric(12,2) NOT NULL CHECK (price >= 0),
    photo_url text,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status product_status NOT NULL DEFAULT 'доступно',
    description text NOT NULL CHECK (btrim(description) <> '')
);

CREATE TABLE "order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES courier(courier_id),
    client_id uuid NOT NULL REFERENCES client(client_id),
    address_id uuid NOT NULL REFERENCES address(address_id),
    restaurant_id uuid NOT NULL REFERENCES restaurant(restaurant_id),
    order_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(12,2) NOT NULL CHECK (order_amount >= 0),
    commission numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(13,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,
    status order_status NOT NULL DEFAULT 'создан',
    pay_status order_pay_status NOT NULL DEFAULT 'ожидает',
    description text NOT NULL CHECK (btrim(description) <> ''),
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id) REFERENCES client_address(client_id, address_id),
	CONSTRAINT order_total_amount_minimum_ck CHECK (total_amount >= 1000),
    CONSTRAINT order_delivery_required_ck CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL),
    CONSTRAINT order_delivery_time_ck CHECK (delivery_timestamp >= order_timestamp),
    UNIQUE (order_id, client_id)
);

CREATE TABLE order_structure (
    order_id uuid NOT NULL REFERENCES "order"(order_id),
    product_id uuid NOT NULL REFERENCES product(product_id),
    quantity numeric(9,3) NOT NULL CHECK (quantity > 0),
    unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES "order"(order_id),
    payment_type payment_type NOT NULL,
    amount numeric(13,2) NOT NULL CHECK(amount >= 0),
    transaction_id varchar(100) NOT NULL CHECK (btrim(transaction_id) <> '') UNIQUE,
    transaction_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    status payment_status NOT NULL DEFAULT 'в_обработке'
);
CREATE UNIQUE INDEX payment_one_success_uq ON payment(order_id) WHERE status = 'успех';

CREATE TABLE review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL REFERENCES client(client_id),
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type review_entity_type NOT NULL,
    order_id uuid NOT NULL REFERENCES "order"(order_id),
    description text NOT NULL CHECK (btrim(description) <> ''),
    photo_url text,
    rating numeric(2,1) NOT NULL CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT review_order_client_fk FOREIGN KEY (order_id, client_id)
        REFERENCES "order" (order_id, client_id),
    CONSTRAINT review_target_order_ck CHECK (entity_type <> 'заказ' OR entity_id = order_id),
    UNIQUE (order_id, entity_type, entity_id)
);

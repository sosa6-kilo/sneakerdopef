DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS product_sizes CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS brands CASCADE;
DROP TYPE IF EXISTS order_status CASCADE;

CREATE TABLE brands (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE products (
    id             SERIAL PRIMARY KEY,
    name           VARCHAR(200) NOT NULL,
    brand_id       INTEGER NOT NULL REFERENCES brands(id),
    price          INTEGER NOT NULL,
    stock          INTEGER NOT NULL DEFAULT 0,
    description    TEXT NOT NULL DEFAULT '',
    image          VARCHAR(255) NOT NULL DEFAULT '',
    gender         VARCHAR(10) NOT NULL DEFAULT 'unisex'
                   CHECK (gender IN ('male', 'female', 'kids', 'unisex')),
    material_upper VARCHAR(100) NOT NULL DEFAULT '',
    material_sole  VARCHAR(100) NOT NULL DEFAULT '',
    color          VARCHAR(100) NOT NULL DEFAULT '',
    season         VARCHAR(20)  NOT NULL DEFAULT 'демисезон',
    country        VARCHAR(100) NOT NULL DEFAULT '',
    created_at     TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_brand_id ON products(brand_id);

CREATE TABLE product_sizes (
    id         SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    size       VARCHAR(10) NOT NULL,
    UNIQUE (product_id, size)
);

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    surname       VARCHAR(100) NOT NULL,
    name          VARCHAR(100) NOT NULL,
    patronymic    VARCHAR(100),
    login         VARCHAR(50) NOT NULL UNIQUE,
    email         VARCHAR(150) NOT NULL UNIQUE,
    phone         VARCHAR(30) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(10) NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    created_at    TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE cart_items (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id VARCHAR(36),
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    size       VARCHAR(10) NOT NULL,
    qty        INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT cart_item_owner CHECK (
        (user_id IS NOT NULL AND session_id IS NULL) OR
        (user_id IS NULL AND session_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX idx_cart_user_product_size
    ON cart_items(user_id, product_id, size) WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX idx_cart_session_product_size
    ON cart_items(session_id, product_id, size) WHERE session_id IS NOT NULL;

CREATE TYPE order_status AS ENUM ('new', 'confirmed', 'cancelled');

CREATE TABLE orders (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(id),
    user_fio         VARCHAR(255) NOT NULL,
    delivery_address VARCHAR(500) NOT NULL,
    delivery_date    DATE NOT NULL,
    delivery_slot    VARCHAR(20) NOT NULL,
    status           order_status NOT NULL DEFAULT 'new',
    cancel_reason    TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_user_id ON orders(user_id);

CREATE TABLE order_items (
    id           SERIAL PRIMARY KEY,
    order_id     INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id   INTEGER REFERENCES products(id) ON DELETE SET NULL,
    product_name VARCHAR(200) NOT NULL,
    size         VARCHAR(10),
    qty          INTEGER NOT NULL,
    price        INTEGER NOT NULL
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);

INSERT INTO brands (name) VALUES
    ('Nike'),
    ('Air Jordan'),
    ('Adidas'),
    ('New Balance'),
    ('Converse'),
    ('Vans'),
    ('Rick Owens'),
    ('Asics'),
    ('Maison Margiela'),
    ('Raf Simons'),
    ('Y-3'),
    ('Reebok'),
    ('Puma')
ON CONFLICT (name) DO NOTHING;

-- Демо-пользователь с правами администратора (логин: admin, пароль: admin123)
INSERT INTO users (surname, name, patronymic, login, email, phone, password_hash, role) VALUES
    ('Админов', 'Админ', NULL, 'admin', 'admin@sneakerdope.ru', '+70000000000',
     '$argon2id$v=19$m=65536,t=3,p=4$SiR7u+sevPdCQ8iky1NovA$MZySXjGSI5yN4NpBA2QmShLC1X4XAviqLs4jHunu3dY',
     'admin')
ON CONFLICT (login) DO NOTHING;

-- Исходные демо-товары
INSERT INTO products (name, brand_id, price, stock, description, image, gender) VALUES
('Air Jordan 1 Retro High OG',
     (SELECT id FROM brands WHERE name = 'Air Jordan'),
     23990, 12,
     'Air Jordan 1 Retro High OG — культовая модель 1985 года.',
     'Air Jordan 1 Retro High OG.jpg', 'male'),

    ('Yeezy Boost 350 V2 Bone',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     19990, 5,
     'Yeezy Boost 350 V2 в расцветке Bone.',
     'Yeezy Boost 350 V2 Bone.jpg', 'unisex'),

    ('New Balance 2002R Protection Pack',
     (SELECT id FROM brands WHERE name = 'New Balance'),
     17990, 8,
     'New Balance 2002R из линейки Protection Pack.',
     'New Balance 2002R Protection Pack.jpg', 'female'),

    ('Converse Chuck 70 Canvas Black',
     (SELECT id FROM brands WHERE name = 'Converse'),
     9990, 15,
     'Converse Chuck 70 — классика на каждый день.',
     'Converse Chuck 70 Canvas Black.jpg', 'unisex'),

    ('Vans Old Skool Pro Black',
     (SELECT id FROM brands WHERE name = 'Vans'),
     9490, 0,
     'Vans Old Skool Pro для скейтборда и города.',
     'Vans Old Skool Pro Black.jpg', 'male'),

    ('Air Jordan 4 Retro Fear',
     (SELECT id FROM brands WHERE name = 'Air Jordan'),
     23990, 6,
     'Air Jordan 4 Retro в колорвее Fear.',
     'Air Jordan 4 Retro Fear.jpg', 'male');

-- Дополнительные товары (дизайнерские бренды, женские/детские модели)
INSERT INTO products (name, brand_id, price, stock, description, image, gender) VALUES
('Rick Owens x Veja Geobasket White',
     (SELECT id FROM brands WHERE name = 'Rick Owens'),
     64990, 3,
     'Rick Owens x Veja Geobasket — культовая дизайнерская модель на массивной подошве, созданная в коллаборации с французским брендом Veja.',
     'Rick Owens x Veja Geobasket White.jpg', 'unisex'),

    ('Rick Owens x Veja Geobasket Low Black',
     (SELECT id FROM brands WHERE name = 'Rick Owens'),
     59990, 2,
     'Низкий силуэт Geobasket от Rick Owens и Veja — минималистичный дизайн с фирменной массивной подошвой.',
     'Rick Owens x Veja Geobasket Low Black.jpg', 'unisex'),

    ('Rick Owens Ramones High-Top Leather',
     (SELECT id FROM brands WHERE name = 'Rick Owens'),
     89990, 2,
     'Rick Owens Ramones — высокие кожаные кроссовки-ботинки с асимметричной шнуровкой, одна из самых узнаваемых моделей бренда.',
     'Rick Owens Ramones High-Top Leather.jpg', 'male'),

    ('Asics Gel-Kayano 14 Cream Black',
     (SELECT id FROM brands WHERE name = 'Asics'),
     16990, 10,
     'Asics Gel-Kayano 14 — переиздание беговой модели начала 2000-х, ставшее одним из главных трендов sneaker-моды.',
     'Asics Gel-Kayano 14 Cream Black.jpg', 'unisex'),

    ('Asics Gel-NYC Oatmeal',
     (SELECT id FROM brands WHERE name = 'Asics'),
     15990, 9,
     'Asics Gel-NYC — городская версия гелевых кроссовок Asics с акцентом на комфорт и ретро-силуэт.',
     'Asics Gel-NYC Oatmeal.jpg', 'unisex'),

    ('Asics Gel-1130 White Pink',
     (SELECT id FROM brands WHERE name = 'Asics'),
     13990, 11,
     'Asics Gel-1130 — женская модель на основе беговых кроссовок 2000-х с амортизирующей гелевой вставкой.',
     'Asics Gel-1130 White Pink.jpg', 'female'),

    ('Asics GT-2160 Grey Navy',
     (SELECT id FROM brands WHERE name = 'Asics'),
     14990, 7,
     'Asics GT-2160 — мужская беговая модель с системой стабилизации GEL, популярная в уличном стиле.',
     'Asics GT-2160 Grey Navy.jpg', 'male'),

    ('Asics Contend 8 Kids',
     (SELECT id FROM brands WHERE name = 'Asics'),
     4990, 14,
     'Asics Contend 8 — лёгкие детские беговые кроссовки с амортизацией и прочной подошвой для активных игр.',
     'Asics Contend 8 Kids.jpg', 'kids'),

    ('Maison Margiela x Reebok Classic Leather Tabi',
     (SELECT id FROM brands WHERE name = 'Maison Margiela'),
     49990, 3,
     'Коллаборация Maison Margiela и Reebok — культовая модель Classic Leather с фирменным раздельным носком Tabi.',
     'Maison Margiela x Reebok Classic Leather Tabi.jpg', 'unisex'),

    ('Maison Margiela Replica Sneaker Low White',
     (SELECT id FROM brands WHERE name = 'Maison Margiela'),
     54990, 2,
     'Maison Margiela Replica — минималистичные низкие кроссовки с характерной красной строчкой на пятке.',
     'Maison Margiela Replica Sneaker Low White.jpg', 'unisex'),

    ('Maison Margiela Replica High-Top',
     (SELECT id FROM brands WHERE name = 'Maison Margiela'),
     59990, 2,
     'Высокая версия Replica от Maison Margiela — лаконичный дизайн в фирменной эстетике бренда.',
     'Maison Margiela Replica High-Top.jpg', 'male'),

    ('Raf Simons x Adidas Ozweego Grey',
     (SELECT id FROM brands WHERE name = 'Raf Simons'),
     34990, 4,
     'Raf Simons x Adidas Ozweego — переосмысление беговой модели 90-х с увеличенной подошвой и футуристичным дизайном.',
     'Raf Simons x Adidas Ozweego Grey.jpg', 'unisex'),

    ('Raf Simons Orion White',
     (SELECT id FROM brands WHERE name = 'Raf Simons'),
     38990, 3,
     'Raf Simons Orion — фирменная модель бренда с массивной подошвой и асимметричными деталями.',
     'Raf Simons Orion White.jpg', 'male'),

    ('Raf Simons x Adidas Replicant Ozweego',
     (SELECT id FROM brands WHERE name = 'Raf Simons'),
     36990, 2,
     'Replicant Ozweego — ещё одна версия коллаборации Raf Simons и Adidas с прозрачными вставками на подошве.',
     'Raf Simons x Adidas Replicant Ozweego.jpg', 'unisex'),

    ('Y-3 Qasa High Black',
     (SELECT id FROM brands WHERE name = 'Y-3'),
     42990, 4,
     'Y-3 Qasa High — флагманская модель линии Yohji Yamamoto и Adidas с округлой подошвой-обмоткой.',
     'Y-3 Qasa High Black.jpg', 'unisex'),

    ('Y-3 Kaiwa Black White',
     (SELECT id FROM brands WHERE name = 'Y-3'),
     29990, 5,
     'Y-3 Kaiwa — современная беговая модель от Yohji Yamamoto и Adidas с минималистичным дизайном.',
     'Y-3 Kaiwa Black White.jpg', 'unisex'),

    ('Y-3 Superstar Black',
     (SELECT id FROM brands WHERE name = 'Y-3'),
     27990, 4,
     'Y-3 Superstar — переосмысление культовой Adidas Superstar в эстетике Yohji Yamamoto.',
     'Y-3 Superstar Black.jpg', 'female'),

    ('Y-3 Rivalry White',
     (SELECT id FROM brands WHERE name = 'Y-3'),
     31990, 3,
     'Y-3 Rivalry — баскетбольный силуэт Adidas, переработанный Yohji Yamamoto в фирменном минималистичном стиле.',
     'Y-3 Rivalry White.jpg', 'male'),

    ('Reebok Classic Leather White',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     8990, 18,
     'Reebok Classic Leather — легендарная модель 1983 года, один из самых узнаваемых силуэтов в истории бренда.',
     'Reebok Classic Leather White.jpg', 'unisex'),

    ('Reebok Club C 85 White Green',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     8490, 14,
     'Reebok Club C 85 — теннисная модель середины 80-х с лаконичным дизайном, ставшая стритвир-классикой.',
     'Reebok Club C 85 White Green.jpg', 'female'),

    ('Reebok Question Mid Black Red',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     12990, 6,
     'Reebok Question Mid — именная баскетбольная модель Аллена Айверсона, выпущенная в 1996 году.',
     'Reebok Question Mid Black Red.jpg', 'male'),

    ('Reebok Zig Kinetica Grey',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     11990, 8,
     'Reebok Zig Kinetica — современная беговая модель с зигзагообразной подошвой ZigTech.',
     'Reebok Zig Kinetica Grey.jpg', 'male'),

    ('Reebok Classic Leather Kids',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     5490, 16,
     'Детская версия легендарной Reebok Classic Leather — та же конструкция в уменьшенном размере.',
     'Reebok Classic Leather Kids.jpg', 'kids'),

    ('Puma Suede Classic Black',
     (SELECT id FROM brands WHERE name = 'Puma'),
     7990, 15,
     'Puma Suede Classic — модель 1968 года из замши, одна из первых сигнатур в баскетбольной истории бренда.',
     'Puma Suede Classic Black.jpg', 'male'),

    ('Puma RS-X Toys',
     (SELECT id FROM brands WHERE name = 'Puma'),
     10990, 9,
     'Puma RS-X — современная массивная модель в стиле dad-shoes с яркими цветовыми блоками.',
     'Puma RS-X Toys.jpg', 'unisex'),

    ('Puma Cali Wedge White',
     (SELECT id FROM brands WHERE name = 'Puma'),
     8990, 10,
     'Puma Cali — женская модель на скрытой танкетке с калифорнийской ретро-эстетикой.',
     'Puma Cali Wedge White.jpg', 'female'),

    ('Puma Smash Kids',
     (SELECT id FROM brands WHERE name = 'Puma'),
     4490, 13,
     'Puma Smash — детская версия классической теннисной модели Puma, простая и износостойкая.',
     'Puma Smash Kids.jpg', 'kids'),

    ('Nike Air Force 1 ''07 White Women',
     (SELECT id FROM brands WHERE name = 'Nike'),
     12990, 16,
     'Nike Air Force 1 ''07 — женская версия культовой баскетбольной модели 1982 года с воздушной подушкой Air.',
     'Nike Air Force 1 ''07 White Women.jpg', 'female'),

    ('Nike Air Max 90 Women Pink',
     (SELECT id FROM brands WHERE name = 'Nike'),
     15990, 10,
     'Nike Air Max 90 — женская версия легендарной модели 1990 года с видимой подушкой Air в пятке.',
     'Nike Air Max 90 Women Pink.jpg', 'female'),

    ('Nike Dunk Low Women Panda',
     (SELECT id FROM brands WHERE name = 'Nike'),
     13990, 12,
     'Nike Dunk Low в чёрно-белой расцветке Panda — одна из самых популярных женских моделей последних лет.',
     'Nike Dunk Low Women Panda.jpg', 'female'),

    ('Nike Air Max 90 Kids',
     (SELECT id FROM brands WHERE name = 'Nike'),
     9990, 11,
     'Детская версия Nike Air Max 90 с уменьшенной колодкой и видимой амортизирующей подушкой Air.',
     'Nike Air Max 90 Kids.jpg', 'kids'),

    ('Nike Court Borough Low Kids',
     (SELECT id FROM brands WHERE name = 'Nike'),
     4990, 17,
     'Nike Court Borough Low — простая и доступная детская модель в стиле классических кедов.',
     'Nike Court Borough Low Kids.jpg', 'kids'),

    ('Adidas Samba OG Women',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     10990, 14,
     'Adidas Samba OG — футбольная модель 1950 года, ставшая одним из главных трендов женской уличной моды.',
     'Adidas Samba OG Women.jpg', 'female'),

    ('Adidas Gazelle Women Burgundy',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     9990, 12,
     'Adidas Gazelle — замшевая модель 1968 года, любимая женская модель в винтажном стиле.',
     'Adidas Gazelle Women Burgundy.jpg', 'female'),

    ('Adidas Superstar Kids',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     6990, 15,
     'Детская версия Adidas Superstar с фирменным носком Shell Toe — та же легендарная конструкция в уменьшенном размере.',
     'Adidas Superstar Kids.jpg', 'kids'),

    ('Adidas Stan Smith Kids',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     6490, 14,
     'Adidas Stan Smith — детская версия теннисной модели 1971 года в минималистичном белом дизайне.',
     'Adidas Stan Smith Kids.jpg', 'kids'),

    ('New Balance 530 White Silver',
     (SELECT id FROM brands WHERE name = 'New Balance'),
     12990, 9,
     'New Balance 530 — беговая модель конца 90-х, переизданная как одна из самых популярных женских моделей бренда.',
     'New Balance 530 White Silver.jpg', 'female'),

    ('New Balance 9060 Grey',
     (SELECT id FROM brands WHERE name = 'New Balance'),
     16990, 7,
     'New Balance 9060 — массивная модель из линейки прото-ран, сочетающая ретро-дизайн с современными технологиями.',
     'New Balance 9060 Grey.jpg', 'unisex'),

    ('New Balance 574 Kids',
     (SELECT id FROM brands WHERE name = 'New Balance'),
     6990, 13,
     'New Balance 574 — детская версия одной из самых узнаваемых моделей бренда с замшево-сетчатым верхом.',
     'New Balance 574 Kids.jpg', 'kids'),

    ('Vans Authentic Women Black',
     (SELECT id FROM brands WHERE name = 'Vans'),
     6990, 16,
     'Vans Authentic — первая модель бренда 1966 года, простой парусиновый кед на вулканизированной подошве.',
     'Vans Authentic Women Black.jpg', 'female'),

    ('Vans Old Skool Kids',
     (SELECT id FROM brands WHERE name = 'Vans'),
     5990, 15,
     'Детская версия Vans Old Skool с фирменной боковой полосой Jazz Stripe.',
     'Vans Old Skool Kids.jpg', 'kids'),

    ('Converse Chuck Taylor All Star Lift Women',
     (SELECT id FROM brands WHERE name = 'Converse'),
     11990, 10,
     'Converse Chuck Taylor All Star Lift — женская версия классических кед на массивной платформе.',
     'Converse Chuck Taylor All Star Lift Women.jpg', 'female'),

    ('Converse Chuck Taylor All Star Kids',
     (SELECT id FROM brands WHERE name = 'Converse'),
     5490, 18,
     'Детская версия легендарных кед Converse Chuck Taylor All Star 1917 года.',
     'Converse Chuck Taylor All Star Kids.jpg', 'kids'),

    ('Air Jordan 1 Mid Kids',
     (SELECT id FROM brands WHERE name = 'Air Jordan'),
     10990, 9,
     'Детская версия Air Jordan 1 Mid — облегчённый вариант культового баскетбольного силуэта.',
     'Air Jordan 1 Mid Kids.jpg', 'kids'),

    ('Air Jordan 11 Retro Women Bred',
     (SELECT id FROM brands WHERE name = 'Air Jordan'),
     25990, 4,
     'Air Jordan 11 Retro — модель 1996 года с лаковой накладкой на носке, в женском размерном ряду.',
     'Air Jordan 11 Retro Women Bred.jpg', 'female'),

    ('Asics Gel-Sonoma 15-50',
     (SELECT id FROM brands WHERE name = 'Asics'),
     13490, 8,
     'Asics Gel-Sonoma 15-50 — туристическая модель на основе трекинговых кроссовок 2015 года, популярная в gorpcore-эстетике.',
     'Asics Gel-Sonoma 15-50.jpg', 'male'),

    ('Y-3 Boston Sandal',
     (SELECT id FROM brands WHERE name = 'Y-3'),
     18990, 5,
     'Y-3 Boston — сандалии-кроксы от Yohji Yamamoto и Adidas, выполненные в минималистичной чёрной палитре.',
     'Y-3 Boston Sandal.jpg', 'unisex'),

    ('Maison Margiela Fusion Sneaker',
     (SELECT id FROM brands WHERE name = 'Maison Margiela'),
     64990, 1,
     'Maison Margiela Fusion — экспериментальная модель, визуально совмещающая два разных кроссовка в одной паре.',
     'Maison Margiela Fusion Sneaker.jpg', 'male'),

    ('Rick Owens x Veja Geobasket Mid Beige',
     (SELECT id FROM brands WHERE name = 'Rick Owens'),
     62990, 2,
     'Geobasket Mid — промежуточный по высоте силуэт коллаборации Rick Owens и Veja с массивной подошвой.',
     'Rick Owens x Veja Geobasket Mid Beige.jpg', 'female'),

    ('Reebok Club C Double Women',
     (SELECT id FROM brands WHERE name = 'Reebok'),
     9490, 9,
     'Reebok Club C Double — женская модель с двойным языком, переосмысление классической теннисной Club C.',
     'Reebok Club C Double Women.jpg', 'female'),

    ('Raf Simons x Adidas Detroit Runner',
     (SELECT id FROM brands WHERE name = 'Raf Simons'),
     33990, 3,
     'Raf Simons Detroit Runner — беговая модель с фирменной массивной подошвой и сетчатым верхом.',
     'Raf Simons x Adidas Detroit Runner.jpg', 'unisex'),

    ('Adidas Campus 00s Women',
     (SELECT id FROM brands WHERE name = 'Adidas'),
     10990, 11,
     'Adidas Campus 00s — переиздание баскетбольной модели 80-х в женском размерном ряду, замшевый верх.',
     'Adidas Campus 00s Women.jpg', 'female'),

    ('Air Jordan 4 Kids Black Cat',
     (SELECT id FROM brands WHERE name = 'Air Jordan'),
     13990, 6,
     'Детская версия Air Jordan 4 в тёмной расцветке Black Cat — облегчённый вариант культовой модели.',
     'Air Jordan 4 Kids Black Cat.jpg', 'kids'),

    ('New Balance 550 White Green',
     (SELECT id FROM brands WHERE name = 'New Balance'),
     13990, 7,
     'New Balance 550 — баскетбольная модель 1989 года, переизданная как одна из самых популярных моделей бренда.',
     'New Balance 550 White Green.jpg', 'unisex'),

    ('Converse Run Star Hike Women',
     (SELECT id FROM brands WHERE name = 'Converse'),
     13990, 8,
     'Converse Run Star Hike — женская модель на массивной зубчатой подошве, основанная на силуэте Chuck Taylor.',
     'Converse Run Star Hike Women.jpg', 'female');

-- Реальные характеристики товаров (материалы, цвет, сезон, страна) -
-- раньше эти поля на странице товара брались из вёрстки
-- (одни и те же захардкоженные значения у всех товаров)
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Air Jordan 1 Retro High OG';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Пена Boost', color = 'Бежевый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Yeezy Boost 350 V2 Bone';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'США' WHERE name = 'New Balance 2002R Protection Pack';
UPDATE products SET material_upper = 'Текстиль (канвас)', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Converse Chuck 70 Canvas Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Китай' WHERE name = 'Vans Old Skool Pro Black';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / красный', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Air Jordan 4 Retro Fear';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Италия' WHERE name = 'Rick Owens x Veja Geobasket White';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Италия' WHERE name = 'Rick Owens x Veja Geobasket Low Black';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Rick Owens Ramones High-Top Leather';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина с гелевой вставкой', color = 'Чёрный / Кремовый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics Gel-Kayano 14 Cream Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина с гелевой вставкой', color = 'Бежевый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics Gel-NYC Oatmeal';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина с гелевой вставкой', color = 'Белый / Розовый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics Gel-1130 White Pink';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Серый / Тёмно-синий', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics GT-2160 Grey Navy';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics Contend 8 Kids';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Италия' WHERE name = 'Maison Margiela Replica Sneaker Low White';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Maison Margiela Replica High-Top';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Серый', season = 'демисезон', country = 'Италия' WHERE name = 'Raf Simons x Adidas Ozweego Grey';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Италия' WHERE name = 'Raf Simons Orion White';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Raf Simons x Adidas Replicant Ozweego';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Y-3 Qasa High Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый / Чёрный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Y-3 Kaiwa Black White';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Y-3 Superstar Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Y-3 Rivalry White';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Classic Leather White';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Белый / Зелёный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Club C 85 White Green';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / Красный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Question Mid Black Red';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'EVA ZigTech', color = 'Серый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Zig Kinetica Grey';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Classic Leather Kids';
UPDATE products SET material_upper = 'Замша', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Индонезия' WHERE name = 'Puma Suede Classic Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Индонезия' WHERE name = 'Puma RS-X Toys';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Puma Cali Wedge White';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Индонезия' WHERE name = 'Puma Smash Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Nike Air Force 1 ''07 White Women';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Розовый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Nike Air Max 90 Women Pink';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Nike Dunk Low Women Panda';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Nike Air Max 90 Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Nike Court Borough Low Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Adidas Samba OG Women';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Adidas Gazelle Women Burgundy';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Индонезия' WHERE name = 'Adidas Superstar Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Индонезия' WHERE name = 'Adidas Stan Smith Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый', season = 'демисезон', country = 'США' WHERE name = 'New Balance 530 White Silver';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Серый', season = 'демисезон', country = 'США' WHERE name = 'New Balance 9060 Grey';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'США' WHERE name = 'New Balance 574 Kids';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный', season = 'демисезон', country = 'Китай' WHERE name = 'Vans Authentic Women Black';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Китай' WHERE name = 'Vans Old Skool Kids';
UPDATE products SET material_upper = 'Текстиль (канвас)', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Converse Chuck Taylor All Star Lift Women';
UPDATE products SET material_upper = 'Текстиль (канвас)', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Converse Chuck Taylor All Star Kids';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Air Jordan 1 Mid Kids';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Красный', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Air Jordan 11 Retro Women Bred';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина с гелевой вставкой', color = 'Чёрный / белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Asics Gel-Sonoma 15-50';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Y-3 Boston Sandal';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Maison Margiela Fusion Sneaker';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Rick Owens x Veja Geobasket Mid Beige';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Reebok Club C Double Women';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Италия' WHERE name = 'Raf Simons x Adidas Detroit Runner';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Индонезия' WHERE name = 'Adidas Campus 00s Women';
UPDATE products SET material_upper = 'Натуральная кожа', material_sole = 'Резина', color = 'Чёрный / Мультиколор', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Air Jordan 4 Kids Black Cat';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Белый / Зелёный', season = 'демисезон', country = 'США' WHERE name = 'New Balance 550 White Green';
UPDATE products SET material_upper = 'Текстиль / синтетика', material_sole = 'Резина', color = 'Чёрный / белый', season = 'демисезон', country = 'Вьетнам' WHERE name = 'Converse Run Star Hike Women';

-- Размеры исходных демо-товаров
INSERT INTO product_sizes (product_id, size) VALUES
((SELECT id FROM products WHERE name = 'Air Jordan 1 Retro High OG'), '38'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Retro High OG'), '39'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Retro High OG'), '40'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Retro High OG'), '41'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Retro High OG'), '43'),

    ((SELECT id FROM products WHERE name = 'Yeezy Boost 350 V2 Bone'), '39'),
    ((SELECT id FROM products WHERE name = 'Yeezy Boost 350 V2 Bone'), '40'),
    ((SELECT id FROM products WHERE name = 'Yeezy Boost 350 V2 Bone'), '41'),
    ((SELECT id FROM products WHERE name = 'Yeezy Boost 350 V2 Bone'), '42'),

    ((SELECT id FROM products WHERE name = 'New Balance 2002R Protection Pack'), '40'),
    ((SELECT id FROM products WHERE name = 'New Balance 2002R Protection Pack'), '41'),
    ((SELECT id FROM products WHERE name = 'New Balance 2002R Protection Pack'), '42'),
    ((SELECT id FROM products WHERE name = 'New Balance 2002R Protection Pack'), '43'),
    ((SELECT id FROM products WHERE name = 'New Balance 2002R Protection Pack'), '44'),

    ((SELECT id FROM products WHERE name = 'Converse Chuck 70 Canvas Black'), '38'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck 70 Canvas Black'), '39'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck 70 Canvas Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck 70 Canvas Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck 70 Canvas Black'), '42'),

    ((SELECT id FROM products WHERE name = 'Vans Old Skool Pro Black'), '39'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Pro Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Pro Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Pro Black'), '42'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Pro Black'), '43'),

    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Retro Fear'), '40'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Retro Fear'), '41'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Retro Fear'), '42'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Retro Fear'), '43');

-- Размеры дополнительных товаров
INSERT INTO product_sizes (product_id, size) VALUES
((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket White'), '40'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket White'), '41'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket White'), '42'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket White'), '43'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket White'), '44'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Low Black'), '39'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Low Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Low Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Low Black'), '42'),
    ((SELECT id FROM products WHERE name = 'Rick Owens Ramones High-Top Leather'), '41'),
    ((SELECT id FROM products WHERE name = 'Rick Owens Ramones High-Top Leather'), '42'),
    ((SELECT id FROM products WHERE name = 'Rick Owens Ramones High-Top Leather'), '43'),
    ((SELECT id FROM products WHERE name = 'Rick Owens Ramones High-Top Leather'), '44'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Kayano 14 Cream Black'), '38'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Kayano 14 Cream Black'), '39'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Kayano 14 Cream Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Kayano 14 Cream Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Kayano 14 Cream Black'), '42'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-NYC Oatmeal'), '39'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-NYC Oatmeal'), '40'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-NYC Oatmeal'), '41'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-NYC Oatmeal'), '42'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-NYC Oatmeal'), '43'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-1130 White Pink'), '36'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-1130 White Pink'), '37'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-1130 White Pink'), '38'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-1130 White Pink'), '39'),
    ((SELECT id FROM products WHERE name = 'Asics GT-2160 Grey Navy'), '40'),
    ((SELECT id FROM products WHERE name = 'Asics GT-2160 Grey Navy'), '41'),
    ((SELECT id FROM products WHERE name = 'Asics GT-2160 Grey Navy'), '42'),
    ((SELECT id FROM products WHERE name = 'Asics GT-2160 Grey Navy'), '43'),
    ((SELECT id FROM products WHERE name = 'Asics GT-2160 Grey Navy'), '44'),
    ((SELECT id FROM products WHERE name = 'Asics Contend 8 Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Asics Contend 8 Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Asics Contend 8 Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Asics Contend 8 Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Asics Contend 8 Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi'), '39'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi'), '40'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi'), '41'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi'), '42'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela x Reebok Classic Leather Tabi'), '43'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica Sneaker Low White'), '40'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica Sneaker Low White'), '41'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica Sneaker Low White'), '42'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica Sneaker Low White'), '43'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica High-Top'), '41'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica High-Top'), '42'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica High-Top'), '43'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Replica High-Top'), '44'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Ozweego Grey'), '39'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Ozweego Grey'), '40'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Ozweego Grey'), '41'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Ozweego Grey'), '42'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Ozweego Grey'), '43'),
    ((SELECT id FROM products WHERE name = 'Raf Simons Orion White'), '41'),
    ((SELECT id FROM products WHERE name = 'Raf Simons Orion White'), '42'),
    ((SELECT id FROM products WHERE name = 'Raf Simons Orion White'), '43'),
    ((SELECT id FROM products WHERE name = 'Raf Simons Orion White'), '44'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Replicant Ozweego'), '38'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Replicant Ozweego'), '39'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Replicant Ozweego'), '40'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Replicant Ozweego'), '41'),
    ((SELECT id FROM products WHERE name = 'Y-3 Qasa High Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Y-3 Qasa High Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Y-3 Qasa High Black'), '42'),
    ((SELECT id FROM products WHERE name = 'Y-3 Qasa High Black'), '43'),
    ((SELECT id FROM products WHERE name = 'Y-3 Qasa High Black'), '44'),
    ((SELECT id FROM products WHERE name = 'Y-3 Kaiwa Black White'), '39'),
    ((SELECT id FROM products WHERE name = 'Y-3 Kaiwa Black White'), '40'),
    ((SELECT id FROM products WHERE name = 'Y-3 Kaiwa Black White'), '41'),
    ((SELECT id FROM products WHERE name = 'Y-3 Kaiwa Black White'), '42'),
    ((SELECT id FROM products WHERE name = 'Y-3 Superstar Black'), '36'),
    ((SELECT id FROM products WHERE name = 'Y-3 Superstar Black'), '37'),
    ((SELECT id FROM products WHERE name = 'Y-3 Superstar Black'), '38'),
    ((SELECT id FROM products WHERE name = 'Y-3 Superstar Black'), '39'),
    ((SELECT id FROM products WHERE name = 'Y-3 Rivalry White'), '41'),
    ((SELECT id FROM products WHERE name = 'Y-3 Rivalry White'), '42'),
    ((SELECT id FROM products WHERE name = 'Y-3 Rivalry White'), '43'),
    ((SELECT id FROM products WHERE name = 'Y-3 Rivalry White'), '44'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '38'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '39'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '40'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '41'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '42'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather White'), '43'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C 85 White Green'), '36'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C 85 White Green'), '37'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C 85 White Green'), '38'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C 85 White Green'), '39'),
    ((SELECT id FROM products WHERE name = 'Reebok Question Mid Black Red'), '41'),
    ((SELECT id FROM products WHERE name = 'Reebok Question Mid Black Red'), '42'),
    ((SELECT id FROM products WHERE name = 'Reebok Question Mid Black Red'), '43'),
    ((SELECT id FROM products WHERE name = 'Reebok Question Mid Black Red'), '44'),
    ((SELECT id FROM products WHERE name = 'Reebok Question Mid Black Red'), '45'),
    ((SELECT id FROM products WHERE name = 'Reebok Zig Kinetica Grey'), '40'),
    ((SELECT id FROM products WHERE name = 'Reebok Zig Kinetica Grey'), '41'),
    ((SELECT id FROM products WHERE name = 'Reebok Zig Kinetica Grey'), '42'),
    ((SELECT id FROM products WHERE name = 'Reebok Zig Kinetica Grey'), '43'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Reebok Classic Leather Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Puma Suede Classic Black'), '40'),
    ((SELECT id FROM products WHERE name = 'Puma Suede Classic Black'), '41'),
    ((SELECT id FROM products WHERE name = 'Puma Suede Classic Black'), '42'),
    ((SELECT id FROM products WHERE name = 'Puma Suede Classic Black'), '43'),
    ((SELECT id FROM products WHERE name = 'Puma Suede Classic Black'), '44'),
    ((SELECT id FROM products WHERE name = 'Puma RS-X Toys'), '38'),
    ((SELECT id FROM products WHERE name = 'Puma RS-X Toys'), '39'),
    ((SELECT id FROM products WHERE name = 'Puma RS-X Toys'), '40'),
    ((SELECT id FROM products WHERE name = 'Puma RS-X Toys'), '41'),
    ((SELECT id FROM products WHERE name = 'Puma RS-X Toys'), '42'),
    ((SELECT id FROM products WHERE name = 'Puma Cali Wedge White'), '36'),
    ((SELECT id FROM products WHERE name = 'Puma Cali Wedge White'), '37'),
    ((SELECT id FROM products WHERE name = 'Puma Cali Wedge White'), '38'),
    ((SELECT id FROM products WHERE name = 'Puma Cali Wedge White'), '39'),
    ((SELECT id FROM products WHERE name = 'Puma Smash Kids'), '27'),
    ((SELECT id FROM products WHERE name = 'Puma Smash Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Puma Smash Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Puma Smash Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Puma Smash Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Nike Air Force 1 ''07 White Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Nike Air Force 1 ''07 White Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Nike Air Force 1 ''07 White Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Nike Air Force 1 ''07 White Women'), '39'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Women Pink'), '36'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Women Pink'), '37'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Women Pink'), '38'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Women Pink'), '39'),
    ((SELECT id FROM products WHERE name = 'Nike Dunk Low Women Panda'), '36'),
    ((SELECT id FROM products WHERE name = 'Nike Dunk Low Women Panda'), '37'),
    ((SELECT id FROM products WHERE name = 'Nike Dunk Low Women Panda'), '38'),
    ((SELECT id FROM products WHERE name = 'Nike Dunk Low Women Panda'), '39'),
    ((SELECT id FROM products WHERE name = 'Nike Dunk Low Women Panda'), '40'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Nike Air Max 90 Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Nike Court Borough Low Kids'), '27'),
    ((SELECT id FROM products WHERE name = 'Nike Court Borough Low Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Nike Court Borough Low Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Nike Court Borough Low Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Nike Court Borough Low Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Adidas Samba OG Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Adidas Samba OG Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Adidas Samba OG Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Adidas Samba OG Women'), '39'),
    ((SELECT id FROM products WHERE name = 'Adidas Gazelle Women Burgundy'), '36'),
    ((SELECT id FROM products WHERE name = 'Adidas Gazelle Women Burgundy'), '37'),
    ((SELECT id FROM products WHERE name = 'Adidas Gazelle Women Burgundy'), '38'),
    ((SELECT id FROM products WHERE name = 'Adidas Gazelle Women Burgundy'), '39'),
    ((SELECT id FROM products WHERE name = 'Adidas Superstar Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Adidas Superstar Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Adidas Superstar Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Adidas Superstar Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Adidas Superstar Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Adidas Stan Smith Kids'), '27'),
    ((SELECT id FROM products WHERE name = 'Adidas Stan Smith Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Adidas Stan Smith Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Adidas Stan Smith Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Adidas Stan Smith Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'New Balance 530 White Silver'), '36'),
    ((SELECT id FROM products WHERE name = 'New Balance 530 White Silver'), '37'),
    ((SELECT id FROM products WHERE name = 'New Balance 530 White Silver'), '38'),
    ((SELECT id FROM products WHERE name = 'New Balance 530 White Silver'), '39'),
    ((SELECT id FROM products WHERE name = 'New Balance 9060 Grey'), '39'),
    ((SELECT id FROM products WHERE name = 'New Balance 9060 Grey'), '40'),
    ((SELECT id FROM products WHERE name = 'New Balance 9060 Grey'), '41'),
    ((SELECT id FROM products WHERE name = 'New Balance 9060 Grey'), '42'),
    ((SELECT id FROM products WHERE name = 'New Balance 9060 Grey'), '43'),
    ((SELECT id FROM products WHERE name = 'New Balance 574 Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'New Balance 574 Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'New Balance 574 Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'New Balance 574 Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'New Balance 574 Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Vans Authentic Women Black'), '35'),
    ((SELECT id FROM products WHERE name = 'Vans Authentic Women Black'), '36'),
    ((SELECT id FROM products WHERE name = 'Vans Authentic Women Black'), '37'),
    ((SELECT id FROM products WHERE name = 'Vans Authentic Women Black'), '38'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Kids'), '27'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Vans Old Skool Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Lift Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Lift Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Lift Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Lift Women'), '39'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Kids'), '27'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Converse Chuck Taylor All Star Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Mid Kids'), '28'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Mid Kids'), '29'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Mid Kids'), '30'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Mid Kids'), '31'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 1 Mid Kids'), '32'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 11 Retro Women Bred'), '36'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 11 Retro Women Bred'), '37'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 11 Retro Women Bred'), '38'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 11 Retro Women Bred'), '39'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Sonoma 15-50'), '40'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Sonoma 15-50'), '41'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Sonoma 15-50'), '42'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Sonoma 15-50'), '43'),
    ((SELECT id FROM products WHERE name = 'Asics Gel-Sonoma 15-50'), '44'),
    ((SELECT id FROM products WHERE name = 'Y-3 Boston Sandal'), '39'),
    ((SELECT id FROM products WHERE name = 'Y-3 Boston Sandal'), '40'),
    ((SELECT id FROM products WHERE name = 'Y-3 Boston Sandal'), '41'),
    ((SELECT id FROM products WHERE name = 'Y-3 Boston Sandal'), '42'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Fusion Sneaker'), '42'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Fusion Sneaker'), '43'),
    ((SELECT id FROM products WHERE name = 'Maison Margiela Fusion Sneaker'), '44'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Mid Beige'), '37'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Mid Beige'), '38'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Mid Beige'), '39'),
    ((SELECT id FROM products WHERE name = 'Rick Owens x Veja Geobasket Mid Beige'), '40'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C Double Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C Double Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C Double Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Reebok Club C Double Women'), '39'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Detroit Runner'), '40'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Detroit Runner'), '41'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Detroit Runner'), '42'),
    ((SELECT id FROM products WHERE name = 'Raf Simons x Adidas Detroit Runner'), '43'),
    ((SELECT id FROM products WHERE name = 'Adidas Campus 00s Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Adidas Campus 00s Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Adidas Campus 00s Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Adidas Campus 00s Women'), '39'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Kids Black Cat'), '28'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Kids Black Cat'), '29'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Kids Black Cat'), '30'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Kids Black Cat'), '31'),
    ((SELECT id FROM products WHERE name = 'Air Jordan 4 Kids Black Cat'), '32'),
    ((SELECT id FROM products WHERE name = 'New Balance 550 White Green'), '39'),
    ((SELECT id FROM products WHERE name = 'New Balance 550 White Green'), '40'),
    ((SELECT id FROM products WHERE name = 'New Balance 550 White Green'), '41'),
    ((SELECT id FROM products WHERE name = 'New Balance 550 White Green'), '42'),
    ((SELECT id FROM products WHERE name = 'New Balance 550 White Green'), '43'),
    ((SELECT id FROM products WHERE name = 'Converse Run Star Hike Women'), '36'),
    ((SELECT id FROM products WHERE name = 'Converse Run Star Hike Women'), '37'),
    ((SELECT id FROM products WHERE name = 'Converse Run Star Hike Women'), '38'),
    ((SELECT id FROM products WHERE name = 'Converse Run Star Hike Women'), '39');
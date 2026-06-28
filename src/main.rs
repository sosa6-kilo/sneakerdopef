use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{
    extract::{DefaultBodyLimit, Multipart, Path, Query, State},
    http::{HeaderMap, HeaderName, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post, put},
    Json, Router,
};
use chrono::{Datelike, NaiveDateTime};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{postgres::PgPoolOptions, FromRow, PgPool};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::services::ServeDir;
use uuid::Uuid;

#[derive(Debug, Clone)]
struct Session {
    user_id: i32,
    role: String,
    name: String,
}

struct AppState {
    pool: PgPool,
    sessions: Mutex<HashMap<String, Session>>,
}

type SharedState = Arc<AppState>;

#[derive(Debug, Clone, FromRow)]
struct ProductRow {
    id: i32,
    name: String,
    brand: String,
    price: i32,
    stock: i32,
    description: String,
    image: String,
    gender: String,
    material_upper: String,
    material_sole: String,
    color: String,
    season: String,
    country: String,
    created_at: NaiveDateTime,
}

#[derive(Debug, Clone, Serialize)]
struct Product {
    id: i32,
    name: String,
    brand: String,
    price: i32,
    size_options: Vec<String>,
    stock: i32,
    description: String,
    image: String,
    gender: String,
    material_upper: String,
    material_sole: String,
    color: String,
    season: String,
    country: String,
    created_at: NaiveDateTime,
}

#[derive(Debug, Clone, Serialize, FromRow)]
struct Brand {
    id: i32,
    name: String,
}

#[derive(Debug, Clone, FromRow)]
struct UserRow {
    id: i32,
    surname: String,
    name: String,
    patronymic: Option<String>,
    login: String,
    email: String,
    phone: String,
    password_hash: String,
    role: String,
}

#[derive(Debug, Clone, Serialize, FromRow)]
struct MeResponse {
    id: i32,
    surname: String,
    name: String,
    patronymic: Option<String>,
    login: String,
    email: String,
    phone: String,
    role: String,
}

#[derive(Debug, Clone, Serialize)]
struct OrderItem {
    product_id: Option<i32>,
    product_name: String,
    size: Option<String>,
    qty: i32,
    price: i32,
}

#[derive(Debug, Clone, Serialize)]
struct Order {
    id: i32,
    user_id: i32,
    user_fio: String,
    items: Vec<OrderItem>,
    delivery_address: String,
    delivery_date: chrono::NaiveDate,
    delivery_slot: String,
    status: String,
    cancel_reason: Option<String>,
    created_at: NaiveDateTime,
}

#[derive(Debug, Deserialize)]
struct RegisterRequest {
    surname: String,
    name: String,
    patronymic: Option<String>,
    login: String,
    email: String,
    phone: String,
    password: String,
    password_repeat: String,
    rules: bool,
}

#[derive(Debug, Deserialize)]
struct LoginRequest {
    login: String,
    password: String,
}

#[derive(Debug, Deserialize)]
struct CartAddRequest {
    product_id: i32,
    size: String,
    qty: Option<i32>,
}

#[derive(Debug, Deserialize)]
struct CartUpdateRequest {
    product_id: i32,
    size: String,
    qty: i32,
}

#[derive(Debug, Deserialize)]
struct CartRemoveRequest {
    product_id: i32,
    size: String,
}

#[derive(Debug, Deserialize)]
struct CreateOrderRequest {
    password: String,
    delivery_address: String,
    delivery_date: chrono::NaiveDate,
    delivery_slot: String,
}

#[derive(Debug, Deserialize)]
struct ProductInput {
    name: String,
    brand: String,
    price: i32,
    size_options: Vec<String>,
    stock: i32,
    description: String,
    image: String,
    gender: String,
    #[serde(default)]
    material_upper: String,
    #[serde(default)]
    material_sole: String,
    #[serde(default)]
    color: String,
    #[serde(default)]
    season: String,
    #[serde(default)]
    country: String,
}

#[derive(Debug, Deserialize)]
struct BrandInput {
    name: String,
}

#[derive(Debug, Deserialize)]
struct OrderActionRequest {
    confirm: bool,
    reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CatalogQuery {
    brand: Option<String>,
    gender: Option<String>,
    sort: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DeliverySlotsQuery {
    date: chrono::NaiveDate,
}

fn hash_password(password: &str) -> Result<String, String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| e.to_string())
}

fn verify_password(password: &str, password_hash: &str) -> bool {
    match PasswordHash::new(password_hash) {
        Ok(parsed) => Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok(),
        Err(_) => false,
    }
}

fn is_valid_fio_part(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }

    for c in s.chars() {
        let lower = c.to_lowercase().next().unwrap_or(c);
        let is_russian_letter = ('а'..='я').contains(&lower) || lower == 'ё';
        let is_space_or_dash = c == ' ' || c == '-';

        if !is_russian_letter && !is_space_or_dash {
            return false;
        }
    }

    true
}

fn is_valid_login(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }

    for c in s.chars() {
        if !c.is_ascii_alphanumeric() && c != '-' {
            return false;
        }
    }

    true
}

fn is_valid_email(s: &str) -> bool {
    s.contains('@') && s.contains('.') && !s.starts_with('@') && !s.ends_with('@')
}

fn is_valid_phone(s: &str) -> bool {
    if s.len() < 5 {
        return false;
    }

    for c in s.chars() {
        let is_allowed = c.is_ascii_digit() || c == '+' || c == '-' || c == ' ' || c == '(' || c == ')';
        if !is_allowed {
            return false;
        }
    }

    true
}

fn shop_hours_for(weekday: chrono::Weekday) -> (i32, i32) {
    use chrono::Weekday::*;
    match weekday {
        Sat | Sun => (11 * 60, 20 * 60),
        _ => (10 * 60, 21 * 60),
    }
}

fn time_to_minutes(time_text: &str) -> Option<i32> {
    let (hours_text, minutes_text) = time_text.split_once(':')?;
    let hours: i32 = hours_text.parse().ok()?;
    let minutes: i32 = minutes_text.parse().ok()?;
    Some(hours * 60 + minutes)
}

fn parse_slot(slot: &str) -> Option<(i32, i32)> {
    let (start_text, end_text) = slot.split_once('-')?;

    let start = time_to_minutes(start_text)?;
    let end = time_to_minutes(end_text)?;

    Some((start, end))
}

fn is_valid_delivery_slot(date: chrono::NaiveDate, slot: &str) -> bool {
    let today = chrono::Local::now().date_naive();
    if date < today {
        return false;
    }

    let (start, end) = match parse_slot(slot) {
        Some(v) => v,
        None => return false,
    };

    if end - start != 30 {
        return false;
    }

    let (open, close) = shop_hours_for(date.weekday());
    start >= open && end <= close
}

fn minutes_to_hm(m: i32) -> String {
    format!("{:02}:{:02}", m / 60, m % 60)
}

fn generate_delivery_slots(date: chrono::NaiveDate) -> Vec<String> {
    let (open, close) = shop_hours_for(date.weekday());
    let mut slots = vec![];
    let mut t = open;
    while t + 30 <= close {
        slots.push(format!("{}-{}", minutes_to_hm(t), minutes_to_hm(t + 30)));
        t += 30;
    }
    slots
}

async fn get_delivery_slots(Query(query): Query<DeliverySlotsQuery>) -> (StatusCode, Json<Value>) {
    let today = chrono::Local::now().date_naive();
    if query.date < today {
        return (StatusCode::OK, Json(json!({ "slots": [] })));
    }
    (StatusCode::OK, Json(json!({ "slots": generate_delivery_slots(query.date) })))
}

fn bearer_token(headers: &HeaderMap) -> Option<String> {
    let value = headers.get(axum::http::header::AUTHORIZATION)?.to_str().ok()?;
    value.strip_prefix("Bearer ").map(|s| s.trim().to_string())
}

fn get_session_id(headers: &HeaderMap) -> String {
    headers
        .get("x-session-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string()
}

fn get_session(state: &SharedState, headers: &HeaderMap) -> Option<Session> {
    let token = bearer_token(headers)?;
    state.sessions.lock().unwrap().get(&token).cloned()
}

fn current_user_id(state: &SharedState, headers: &HeaderMap) -> Option<i32> {
    get_session(state, headers).map(|s| s.user_id)
}

fn create_session_token(state: &SharedState, user_id: i32, role: &str, name: &str) -> String {
    let token = Uuid::new_v4().to_string();
    state.sessions.lock().unwrap().insert(
        token.clone(),
        Session {
            user_id,
            role: role.to_string(),
            name: name.to_string(),
        },
    );
    token
}

async fn merge_guest_cart_into_user(pool: &PgPool, session_id: &str, user_id: i32) {
    if session_id.is_empty() {
        return;
    }

    let guest_items: Vec<(i32, String, i32)> = sqlx::query_as(
        "SELECT product_id, size, qty FROM cart_items WHERE session_id = $1",
    )
    .bind(session_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    for (product_id, size, qty) in guest_items {
        let _ = sqlx::query(
            "INSERT INTO cart_items (user_id, product_id, size, qty) VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, product_id, size) WHERE user_id IS NOT NULL
             DO UPDATE SET qty = cart_items.qty + EXCLUDED.qty",
        )
        .bind(user_id)
        .bind(product_id)
        .bind(size)
        .bind(qty)
        .execute(pool)
        .await;
    }

    let _ = sqlx::query("DELETE FROM cart_items WHERE session_id = $1")
        .bind(session_id)
        .execute(pool)
        .await;
}

async fn fetch_sizes_map(pool: &PgPool, product_ids: &[i32]) -> HashMap<i32, Vec<String>> {
    if product_ids.is_empty() {
        return HashMap::new();
    }

    let rows: Vec<(i32, String)> = sqlx::query_as(
        "SELECT product_id, size FROM product_sizes WHERE product_id = ANY($1) ORDER BY size",
    )
    .bind(product_ids)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let mut map: HashMap<i32, Vec<String>> = HashMap::new();
    for (product_id, size) in rows {
        if map.contains_key(&product_id) {
            map.get_mut(&product_id).unwrap().push(size);
        } else {
            map.insert(product_id, vec![size]);
        }
    }
    map
}

async fn rows_to_products(pool: &PgPool, rows: Vec<ProductRow>) -> Vec<Product> {
    let mut ids: Vec<i32> = vec![];
    for row in &rows {
        ids.push(row.id);
    }

    let mut sizes_map = fetch_sizes_map(pool, &ids).await;

    let mut products: Vec<Product> = vec![];
    for row in rows {
        let size_options = sizes_map.remove(&row.id).unwrap_or_default();

        let product = Product {
            id: row.id,
            name: row.name,
            brand: row.brand,
            price: row.price,
            size_options,
            stock: row.stock,
            description: row.description,
            image: row.image,
            gender: row.gender,
            material_upper: row.material_upper,
            material_sole: row.material_sole,
            color: row.color,
            season: row.season,
            country: row.country,
            created_at: row.created_at,
        };

        products.push(product);
    }

    products
}

const PRODUCT_SELECT: &str = "SELECT p.id, p.name, b.name AS brand, p.price,
    p.stock, p.description, p.image, p.gender,
    p.material_upper, p.material_sole, p.color, p.season, p.country, p.created_at
    FROM products p JOIN brands b ON b.id = p.brand_id";

async fn list_products(State(state): State<SharedState>, Query(query): Query<CatalogQuery>) -> Json<Vec<Product>> {
    let brand_filter = query.brand.filter(|b| !b.is_empty());
    let gender_filter = query.gender.filter(|g| !g.is_empty());

    let order_clause = match query.sort.as_deref() {
        Some("price_asc") => "ORDER BY p.price ASC",
        Some("price_desc") => "ORDER BY p.price DESC",
        _ => "ORDER BY p.created_at DESC",
    };

    let sql = format!(
        "{PRODUCT_SELECT} WHERE p.stock > 0 AND ($1::text IS NULL OR b.name ILIKE $1)
         AND ($2::text IS NULL OR p.gender = $2) {order_clause}"
    );

    let rows: Vec<ProductRow> = sqlx::query_as(&sql)
        .bind(brand_filter)
        .bind(gender_filter)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();

    Json(rows_to_products(&state.pool, rows).await)
}

async fn get_product(State(state): State<SharedState>, Path(id): Path<i32>) -> Response {
    let sql = format!("{PRODUCT_SELECT} WHERE p.id = $1");

    let row: Option<ProductRow> = sqlx::query_as(&sql)
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None);

    match row {
        Some(r) => {
            let products = rows_to_products(&state.pool, vec![r]).await;
            Json(products.into_iter().next().unwrap()).into_response()
        }
        None => (StatusCode::NOT_FOUND, Json(json!({"error": "Товар не найден"}))).into_response(),
    }
}

async fn latest_products(State(state): State<SharedState>) -> Json<Vec<Product>> {
    let sql = format!("{PRODUCT_SELECT} WHERE p.stock > 0 ORDER BY p.created_at DESC LIMIT 15");

    let rows: Vec<ProductRow> = sqlx::query_as(&sql).fetch_all(&state.pool).await.unwrap_or_default();

    Json(rows_to_products(&state.pool, rows).await)
}

async fn bestseller_products(State(state): State<SharedState>) -> Json<Vec<Product>> {
    // Считаем суммарное количество проданных штук по товару, учитывая только
    // заказы, которые не были отменены. Сортируем по этой сумме по убыванию,
    // показываем только товары, которые ещё есть в наличии.
    let sql = format!(
        "{PRODUCT_SELECT}
         JOIN (
             SELECT oi.product_id, SUM(oi.qty) AS sold_qty
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             WHERE oi.product_id IS NOT NULL AND o.status != 'cancelled'
             GROUP BY oi.product_id
         ) sales ON sales.product_id = p.id
         WHERE p.stock > 0
         ORDER BY sales.sold_qty DESC, p.created_at DESC
         LIMIT 3"
    );

    let rows: Vec<ProductRow> = sqlx::query_as(&sql).fetch_all(&state.pool).await.unwrap_or_default();

    Json(rows_to_products(&state.pool, rows).await)
}

async fn list_brands(State(state): State<SharedState>) -> Json<Vec<Brand>> {
    let brands: Vec<Brand> = sqlx::query_as("SELECT id, name FROM brands ORDER BY name")
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();

    Json(brands)
}

async fn register(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<RegisterRequest>,
) -> (StatusCode, Json<Value>) {
    let mut errors: HashMap<String, String> = HashMap::new();

    if !is_valid_fio_part(&body.surname) {
        errors.insert("surname".to_string(), "Некорректная фамилия".to_string());
    }
    if !is_valid_fio_part(&body.name) {
        errors.insert("name".to_string(), "Некорректное имя".to_string());
    }
    if let Some(p) = &body.patronymic {
        if !p.is_empty() && !is_valid_fio_part(p) {
            errors.insert("patronymic".to_string(), "Некорректное отчество".to_string());
        }
    }
    if !is_valid_login(&body.login) {
        errors.insert("login".to_string(), "Логин может содержать только латиницу, цифры и тире".to_string());
    }
    if !is_valid_email(&body.email) {
        errors.insert("email".to_string(), "Некорректный email".to_string());
    }
    if !is_valid_phone(&body.phone) {
        errors.insert("phone".to_string(), "Некорректный телефон".to_string());
    }
    if body.password.len() < 6 {
        errors.insert("password".to_string(), "Пароль должен быть не менее 6 символов".to_string());
    }
    if body.password != body.password_repeat {
        errors.insert("password_repeat".to_string(), "Пароли не совпадают".to_string());
    }
    if !body.rules {
        errors.insert("rules".to_string(), "Нужно согласиться с правилами".to_string());
    }

    let login_taken: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM users WHERE login ILIKE $1)")
        .bind(&body.login)
        .fetch_one(&state.pool)
        .await
        .unwrap_or(false);
    if login_taken {
        errors.insert("login".to_string(), "Логин уже занят".to_string());
    }

    let email_taken: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM users WHERE email ILIKE $1)")
        .bind(&body.email)
        .fetch_one(&state.pool)
        .await
        .unwrap_or(false);
    if email_taken {
        errors.insert("email".to_string(), "Такой email уже зарегистрирован".to_string());
    }

    let phone_taken: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM users WHERE phone = $1)")
        .bind(&body.phone)
        .fetch_one(&state.pool)
        .await
        .unwrap_or(false);
    if phone_taken {
        errors.insert("phone".to_string(), "Такой номер уже зарегистрирован".to_string());
    }

    if !errors.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "errors": errors })));
    }

    let password_hash = match hash_password(&body.password) {
        Ok(h) => h,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "error": "Не удалось обработать пароль" })),
            )
        }
    };

    let new_id: i32 = match sqlx::query_scalar(
        "INSERT INTO users (surname, name, patronymic, login, email, phone, password_hash)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
    )
    .bind(&body.surname)
    .bind(&body.name)
    .bind(&body.patronymic)
    .bind(&body.login)
    .bind(&body.email)
    .bind(&body.phone)
    .bind(&password_hash)
    .fetch_one(&state.pool)
    .await
    {
        Ok(id) => id,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "error": "Не удалось создать пользователя" })),
            )
        }
    };

    let session_id = get_session_id(&headers);
    merge_guest_cart_into_user(&state.pool, &session_id, new_id).await;

    let token = create_session_token(&state, new_id, "user", &body.name);

    (StatusCode::OK, Json(json!({ "ok": true, "user_id": new_id, "token": token })))
}

async fn login(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<LoginRequest>,
) -> (StatusCode, Json<Value>) {
    let found: Option<UserRow> = sqlx::query_as(
        "SELECT id, surname, name, patronymic, login, email, phone, password_hash, role
         FROM users WHERE login = $1",
    )
    .bind(&body.login)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    let user = match found {
        Some(u) if verify_password(&body.password, &u.password_hash) => u,
        _ => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({ "error": "Неверный логин или пароль" })),
            )
        }
    };

    let session_id = get_session_id(&headers);
    merge_guest_cart_into_user(&state.pool, &session_id, user.id).await;

    let token = create_session_token(&state, user.id, &user.role, &user.name);

    (StatusCode::OK, Json(json!({ "ok": true, "user_id": user.id, "token": token })))
}

async fn logout(State(state): State<SharedState>, headers: HeaderMap) -> Json<Value> {
    if let Some(token) = bearer_token(&headers) {
        state.sessions.lock().unwrap().remove(&token);
    }
    Json(json!({ "ok": true }))
}

async fn get_me(State(state): State<SharedState>, headers: HeaderMap) -> (StatusCode, Json<Value>) {
    let user_id = match current_user_id(&state, &headers) {
        Some(uid) => uid,
        None => return (StatusCode::UNAUTHORIZED, Json(json!({ "error": "Не авторизован" }))),
    };

    let user: Option<MeResponse> = sqlx::query_as(
        "SELECT id, surname, name, patronymic, login, email, phone, role FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    match user {
        Some(u) => (StatusCode::OK, Json(json!(u))),
        None => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    }
}

async fn build_cart_response(pool: &PgPool, user_id: Option<i32>, session_id: &str) -> Value {
    let rows: Vec<(i32, String, String, String, i32, i32, i32, String)> = if let Some(uid) = user_id {
        sqlx::query_as(
            "SELECT p.id, p.name, b.name, c.size, p.price, c.qty, p.stock, p.image
             FROM cart_items c
             JOIN products p ON p.id = c.product_id
             JOIN brands b ON b.id = p.brand_id
             WHERE c.user_id = $1
             ORDER BY p.name, c.size",
        )
        .bind(uid)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as(
            "SELECT p.id, p.name, b.name, c.size, p.price, c.qty, p.stock, p.image
             FROM cart_items c
             JOIN products p ON p.id = c.product_id
             JOIN brands b ON b.id = p.brand_id
             WHERE c.session_id = $1
             ORDER BY p.name, c.size",
        )
        .bind(session_id)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    };

    let mut items = vec![];
    let mut total = 0;

    for (product_id, name, brand, size, price, qty, stock, image) in rows {
        let line_total = price * qty;
        total += line_total;
        items.push(json!({
            "product_id": product_id,
            "name": name,
            "brand": brand,
            "size": size,
            "price": price,
            "qty": qty,
            "stock": stock,
            "image": image,
            "line_total": line_total,
        }));
    }

    json!({ "items": items, "total": total })
}

async fn get_cart(State(state): State<SharedState>, headers: HeaderMap) -> (StatusCode, Json<Value>) {
    let session_id = get_session_id(&headers);
    let user_id = current_user_id(&state, &headers);
    let body = build_cart_response(&state.pool, user_id, &session_id).await;

    (StatusCode::OK, Json(body))
}

async fn cart_add(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<CartAddRequest>,
) -> (StatusCode, Json<Value>) {
    let qty_to_add = body.qty.unwrap_or(1);
    let session_id = get_session_id(&headers);

    let stock: Option<i32> = sqlx::query_scalar("SELECT stock FROM products WHERE id = $1")
        .bind(body.product_id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None);

    let stock = match stock {
        Some(s) => s,
        None => return (StatusCode::NOT_FOUND, Json(json!({ "error": "Товар не найден" }))),
    };

    let size_exists: Option<i32> = sqlx::query_scalar(
        "SELECT 1 FROM product_sizes WHERE product_id = $1 AND size = $2",
    )
    .bind(body.product_id)
    .bind(&body.size)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    if size_exists.is_none() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Выберите доступный размер" })));
    }

    let user_id = current_user_id(&state, &headers);

    let current_qty: i32 = if let Some(uid) = user_id {
        sqlx::query_scalar(
            "SELECT qty FROM cart_items WHERE user_id = $1 AND product_id = $2 AND size = $3",
        )
        .bind(uid)
        .bind(body.product_id)
        .bind(&body.size)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None)
        .unwrap_or(0)
    } else {
        sqlx::query_scalar(
            "SELECT qty FROM cart_items WHERE session_id = $1 AND product_id = $2 AND size = $3",
        )
        .bind(&session_id)
        .bind(body.product_id)
        .bind(&body.size)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None)
        .unwrap_or(0)
    };

    if current_qty + qty_to_add > stock {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Нельзя добавить больше товара, чем есть в наличии" })),
        );
    }

    if let Some(uid) = user_id {
        let _ = sqlx::query(
            "INSERT INTO cart_items (user_id, product_id, size, qty) VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, product_id, size) WHERE user_id IS NOT NULL
             DO UPDATE SET qty = cart_items.qty + EXCLUDED.qty",
        )
        .bind(uid)
        .bind(body.product_id)
        .bind(&body.size)
        .bind(qty_to_add)
        .execute(&state.pool)
        .await;
    } else {
        let _ = sqlx::query(
            "INSERT INTO cart_items (session_id, product_id, size, qty) VALUES ($1, $2, $3, $4)
             ON CONFLICT (session_id, product_id, size) WHERE session_id IS NOT NULL
             DO UPDATE SET qty = cart_items.qty + EXCLUDED.qty",
        )
        .bind(&session_id)
        .bind(body.product_id)
        .bind(&body.size)
        .bind(qty_to_add)
        .execute(&state.pool)
        .await;
    }

    (StatusCode::OK, Json(json!({ "ok": true })))
}

async fn cart_update(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<CartUpdateRequest>,
) -> (StatusCode, Json<Value>) {
    let session_id = get_session_id(&headers);

    let stock: Option<i32> = sqlx::query_scalar("SELECT stock FROM products WHERE id = $1")
        .bind(body.product_id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None);

    let stock = match stock {
        Some(s) => s,
        None => return (StatusCode::NOT_FOUND, Json(json!({ "error": "Товар не найден" }))),
    };

    if body.qty > stock {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Недостаточно товара в наличии" })));
    }

    let user_id = current_user_id(&state, &headers);

    if body.qty <= 0 {
        if let Some(uid) = user_id {
            let _ = sqlx::query(
                "DELETE FROM cart_items WHERE user_id = $1 AND product_id = $2 AND size = $3",
            )
            .bind(uid)
            .bind(body.product_id)
            .bind(&body.size)
            .execute(&state.pool)
            .await;
        } else {
            let _ = sqlx::query(
                "DELETE FROM cart_items WHERE session_id = $1 AND product_id = $2 AND size = $3",
            )
            .bind(&session_id)
            .bind(body.product_id)
            .bind(&body.size)
            .execute(&state.pool)
            .await;
        }
    } else if let Some(uid) = user_id {
        let _ = sqlx::query(
            "INSERT INTO cart_items (user_id, product_id, size, qty) VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, product_id, size) WHERE user_id IS NOT NULL
             DO UPDATE SET qty = EXCLUDED.qty",
        )
        .bind(uid)
        .bind(body.product_id)
        .bind(&body.size)
        .bind(body.qty)
        .execute(&state.pool)
        .await;
    } else {
        let _ = sqlx::query(
            "INSERT INTO cart_items (session_id, product_id, size, qty) VALUES ($1, $2, $3, $4)
             ON CONFLICT (session_id, product_id, size) WHERE session_id IS NOT NULL
             DO UPDATE SET qty = EXCLUDED.qty",
        )
        .bind(&session_id)
        .bind(body.product_id)
        .bind(&body.size)
        .bind(body.qty)
        .execute(&state.pool)
        .await;
    }

    (StatusCode::OK, Json(json!({ "ok": true })))
}

async fn cart_remove(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<CartRemoveRequest>,
) -> Json<Value> {
    let session_id = get_session_id(&headers);
    let user_id = current_user_id(&state, &headers);

    if let Some(uid) = user_id {
        let _ = sqlx::query("DELETE FROM cart_items WHERE user_id = $1 AND product_id = $2 AND size = $3")
            .bind(uid)
            .bind(body.product_id)
            .bind(&body.size)
            .execute(&state.pool)
            .await;
    } else {
        let _ = sqlx::query("DELETE FROM cart_items WHERE session_id = $1 AND product_id = $2 AND size = $3")
            .bind(&session_id)
            .bind(body.product_id)
            .bind(&body.size)
            .execute(&state.pool)
            .await;
    }

    Json(json!({ "ok": true }))
}

async fn create_order(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<CreateOrderRequest>,
) -> (StatusCode, Json<Value>) {
    let user_id = match current_user_id(&state, &headers) {
        Some(uid) => uid,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({ "error": "Нужно авторизоваться, чтобы оформить заказ" })),
            )
        }
    };

    let user: Option<UserRow> = sqlx::query_as(
        "SELECT id, surname, name, patronymic, login, email, phone, password_hash, role
         FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    let user = match user {
        Some(u) => u,
        None => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    };

    if !verify_password(&body.password, &user.password_hash) {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Неверный пароль" })));
    }

    let address = body.delivery_address.trim();
    if address.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Укажите адрес доставки" })),
        );
    }

    if !is_valid_delivery_slot(body.delivery_date, &body.delivery_slot) {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Выбранное время доставки недоступно - проверьте дату и часы работы магазина" })),
        );
    }

    let cart_rows: Vec<(i32, String, String, i32, i32)> = sqlx::query_as(
        "SELECT p.id, p.name, c.size, p.price, c.qty
         FROM cart_items c JOIN products p ON p.id = c.product_id
         WHERE c.user_id = $1",
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    if cart_rows.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Корзина пуста" })));
    }

    for (_id, name, _size, _price, qty) in &cart_rows {
        let stock: i32 = sqlx::query_scalar("SELECT stock FROM products WHERE id = $1")
            .bind(_id)
            .fetch_one(&state.pool)
            .await
            .unwrap_or(0);
        if *qty > stock {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "error": format!("Недостаточно товара: {}", name) })),
            );
        }
    }

    let fio = format!(
        "{} {} {}",
        user.surname,
        user.name,
        user.patronymic.clone().unwrap_or_default()
    );

    let mut tx = match state.pool.begin().await {
        Ok(tx) => tx,
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    };

    let order_id: i32 = match sqlx::query_scalar(
        "INSERT INTO orders (user_id, user_fio, delivery_address, delivery_date, delivery_slot, status)
         VALUES ($1, $2, $3, $4, $5, 'new') RETURNING id",
    )
    .bind(user_id)
    .bind(&fio)
    .bind(address)
    .bind(body.delivery_date)
    .bind(&body.delivery_slot)
    .fetch_one(&mut *tx)
    .await
    {
        Ok(id) => id,
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось создать заказ" }))),
    };

    for (product_id, name, size, price, qty) in &cart_rows {
        let _ = sqlx::query(
            "INSERT INTO order_items (order_id, product_id, product_name, size, qty, price)
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(order_id)
        .bind(product_id)
        .bind(name)
        .bind(size)
        .bind(qty)
        .bind(price)
        .execute(&mut *tx)
        .await;

        let update_result = sqlx::query(
            "UPDATE products SET stock = stock - $1 WHERE id = $2 AND stock >= $1",
        )
        .bind(qty)
        .bind(product_id)
        .execute(&mut *tx)
        .await;

        match update_result {
            Ok(res) if res.rows_affected() > 0 => {}
            _ => {
                let _ = tx.rollback().await;
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "error": format!("Недостаточно товара: {}", name) })),
                );
            }
        }
    }

    let _ = sqlx::query("DELETE FROM cart_items WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await;

    if tx.commit().await.is_err() {
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось оформить заказ" })));
    }

    (StatusCode::OK, Json(json!({ "ok": true, "order_id": order_id })))
}

async fn load_orders(pool: &PgPool, where_clause: &str, bind_user_id: Option<i32>) -> Vec<Order> {
    let sql = format!(
        "SELECT id, user_id, user_fio, delivery_address, delivery_date, delivery_slot,
                status::text AS status, cancel_reason, created_at
         FROM orders {where_clause} ORDER BY created_at DESC"
    );

    #[derive(FromRow)]
    struct OrderRow {
        id: i32,
        user_id: i32,
        user_fio: String,
        delivery_address: String,
        delivery_date: chrono::NaiveDate,
        delivery_slot: String,
        status: String,
        cancel_reason: Option<String>,
        created_at: NaiveDateTime,
    }

    let rows: Vec<OrderRow> = if let Some(uid) = bind_user_id {
        sqlx::query_as(&sql).bind(uid).fetch_all(pool).await.unwrap_or_default()
    } else {
        sqlx::query_as(&sql).fetch_all(pool).await.unwrap_or_default()
    };

    let mut orders = vec![];
    for row in rows {
        let items: Vec<OrderItem> = sqlx::query_as::<_, (Option<i32>, String, Option<String>, i32, i32)>(
            "SELECT product_id, product_name, size, qty, price FROM order_items WHERE order_id = $1",
        )
        .bind(row.id)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|(product_id, product_name, size, qty, price)| OrderItem { product_id, product_name, size, qty, price })
        .collect();

        orders.push(Order {
            id: row.id,
            user_id: row.user_id,
            user_fio: row.user_fio,
            items,
            delivery_address: row.delivery_address,
            delivery_date: row.delivery_date,
            delivery_slot: row.delivery_slot,
            status: row.status,
            cancel_reason: row.cancel_reason,
            created_at: row.created_at,
        });
    }

    orders
}

async fn my_orders(State(state): State<SharedState>, headers: HeaderMap) -> (StatusCode, Json<Value>) {
    let user_id = match current_user_id(&state, &headers) {
        Some(uid) => uid,
        None => return (StatusCode::UNAUTHORIZED, Json(json!({ "error": "Не авторизован" }))),
    };

    let orders = load_orders(&state.pool, "WHERE user_id = $1", Some(user_id)).await;

    (StatusCode::OK, Json(json!(orders)))
}

async fn delete_order(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(order_id): Path<i32>,
) -> (StatusCode, Json<Value>) {
    let user_id = match current_user_id(&state, &headers) {
        Some(uid) => uid,
        None => return (StatusCode::UNAUTHORIZED, Json(json!({ "error": "Не авторизован" }))),
    };

    let status: Option<String> = sqlx::query_scalar(
        "SELECT status::text FROM orders WHERE id = $1 AND user_id = $2",
    )
    .bind(order_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    match status {
        Some(s) if s == "new" => {
            let _ = sqlx::query(
                "UPDATE products p SET stock = p.stock + oi.qty
                 FROM order_items oi WHERE oi.order_id = $1 AND oi.product_id = p.id",
            )
            .bind(order_id)
            .execute(&state.pool)
            .await;

            let _ = sqlx::query("DELETE FROM orders WHERE id = $1").bind(order_id).execute(&state.pool).await;
            (StatusCode::OK, Json(json!({ "ok": true })))
        }
        Some(_) => (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Можно удалить только новый заказ" })),
        ),
        None => (StatusCode::NOT_FOUND, Json(json!({ "error": "Заказ не найден" }))),
    }
}

fn check_admin(state: &SharedState, headers: &HeaderMap) -> bool {
    matches!(get_session(state, headers), Some(s) if s.role == "admin")
}

async fn admin_list_orders(State(state): State<SharedState>, headers: HeaderMap) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }
    let orders = load_orders(&state.pool, "", None).await;
    (StatusCode::OK, Json(json!(orders)))
}

async fn admin_update_order(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<i32>,
    Json(body): Json<OrderActionRequest>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    let result = if body.confirm {
        sqlx::query("UPDATE orders SET status = 'confirmed', cancel_reason = NULL WHERE id = $1")
            .bind(id)
            .execute(&state.pool)
            .await
    } else {
        let update_status = sqlx::query(
            "UPDATE orders SET status = 'cancelled', cancel_reason = $1
             WHERE id = $2 AND status != 'cancelled'",
        )
        .bind(&body.reason)
        .bind(id)
        .execute(&state.pool)
        .await;

        if let Ok(res) = &update_status {
            if res.rows_affected() > 0 {
                let _ = sqlx::query(
                    "UPDATE products p SET stock = p.stock + oi.qty
                     FROM order_items oi WHERE oi.order_id = $1 AND oi.product_id = p.id",
                )
                .bind(id)
                .execute(&state.pool)
                .await;
            }
        }

        update_status
    };

    match result {
        Ok(res) if res.rows_affected() > 0 => (StatusCode::OK, Json(json!({ "ok": true }))),
        Ok(_) => (StatusCode::NOT_FOUND, Json(json!({ "error": "Заказ не найден" }))),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    }
}

async fn find_or_create_brand(pool: &PgPool, name: &str) -> Option<i32> {
    if let Ok(Some(id)) = sqlx::query_scalar::<_, i32>("SELECT id FROM brands WHERE name = $1")
        .bind(name)
        .fetch_optional(pool)
        .await
    {
        return Some(id);
    }

    sqlx::query_scalar("INSERT INTO brands (name) VALUES ($1) ON CONFLICT (name) DO NOTHING RETURNING id")
        .bind(name)
        .fetch_optional(pool)
        .await
        .unwrap_or(None)
}

async fn admin_list_products(State(state): State<SharedState>, headers: HeaderMap) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    let sql = format!("{PRODUCT_SELECT} ORDER BY p.created_at DESC");
    let rows: Vec<ProductRow> = sqlx::query_as(&sql)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();

    let products = rows_to_products(&state.pool, rows).await;
    (StatusCode::OK, Json(json!(products)))
}

async fn admin_add_product(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<ProductInput>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    if body.price <= 0 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Цена должна быть больше нуля" })));
    }
    if body.stock < 0 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Остаток не может быть отрицательным" })));
    }

    let brand_id = match find_or_create_brand(&state.pool, &body.brand).await {
        Some(id) => id,
        None => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось определить бренд" }))),
    };

    let id: i32 = match sqlx::query_scalar(
        "INSERT INTO products (name, brand_id, price, stock, description, image, gender,
         material_upper, material_sole, color, season, country)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id",
    )
    .bind(&body.name)
    .bind(brand_id)
    .bind(body.price)
    .bind(body.stock)
    .bind(&body.description)
    .bind(&body.image)
    .bind(&body.gender)
    .bind(&body.material_upper)
    .bind(&body.material_sole)
    .bind(&body.color)
    .bind(&body.season)
    .bind(&body.country)
    .fetch_one(&state.pool)
    .await
    {
        Ok(id) => id,
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось создать товар" }))),
    };

    for size in &body.size_options {
        let _ = sqlx::query("INSERT INTO product_sizes (product_id, size) VALUES ($1, $2)")
            .bind(id)
            .bind(size)
            .execute(&state.pool)
            .await;
    }

    (StatusCode::OK, Json(json!({ "ok": true, "id": id })))
}

async fn admin_edit_product(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<i32>,
    Json(body): Json<ProductInput>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    if body.price <= 0 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Цена должна быть больше нуля" })));
    }
    if body.stock < 0 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Остаток не может быть отрицательным" })));
    }

    let brand_id = match find_or_create_brand(&state.pool, &body.brand).await {
        Some(id) => id,
        None => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось определить бренд" }))),
    };

    let result = sqlx::query(
        "UPDATE products SET name = $1, brand_id = $2, price = $3,
         stock = $4, description = $5, image = $6, gender = $7,
         material_upper = $8, material_sole = $9, color = $10, season = $11, country = $12
         WHERE id = $13",
    )
    .bind(&body.name)
    .bind(brand_id)
    .bind(body.price)
    .bind(body.stock)
    .bind(&body.description)
    .bind(&body.image)
    .bind(&body.gender)
    .bind(&body.material_upper)
    .bind(&body.material_sole)
    .bind(&body.color)
    .bind(&body.season)
    .bind(&body.country)
    .bind(id)
    .execute(&state.pool)
    .await;

    match result {
        Ok(res) if res.rows_affected() > 0 => {
            let _ = sqlx::query("DELETE FROM product_sizes WHERE product_id = $1").bind(id).execute(&state.pool).await;
            for size in &body.size_options {
                let _ = sqlx::query("INSERT INTO product_sizes (product_id, size) VALUES ($1, $2)")
                    .bind(id)
                    .bind(size)
                    .execute(&state.pool)
                    .await;
            }
            (StatusCode::OK, Json(json!({ "ok": true })))
        }
        Ok(_) => (StatusCode::NOT_FOUND, Json(json!({ "error": "Товар не найден" }))),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    }
}

async fn admin_delete_product(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<i32>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    match sqlx::query("DELETE FROM products WHERE id = $1").bind(id).execute(&state.pool).await {
        Ok(res) if res.rows_affected() > 0 => (StatusCode::OK, Json(json!({ "ok": true }))),
        Ok(_) => (StatusCode::NOT_FOUND, Json(json!({ "error": "Товар не найден" }))),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Внутренняя ошибка" }))),
    }
}

const ALLOWED_IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "gif"];

fn guess_extension_from_filename(name: &str) -> Option<String> {
    let ext = name.rsplit('.').next()?.to_lowercase();
    if ALLOWED_IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        Some(ext)
    } else {
        None
    }
}

async fn admin_upload_image(
    State(state): State<SharedState>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    let field = match multipart.next_field().await {
        Ok(Some(f)) => f,
        _ => return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Файл не найден в запросе" }))),
    };

    let original_name = field.file_name().unwrap_or("").to_string();
    let extension = match guess_extension_from_filename(&original_name) {
        Some(ext) => ext,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "error": "Допустимые форматы изображения: jpg, jpeg, png, webp, gif" })),
            )
        }
    };

    let bytes = match field.bytes().await {
        Ok(b) => b,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(json!({ "error": "Не удалось прочитать файл" }))),
    };

    const MAX_UPLOAD_BYTES: usize = 5 * 1024 * 1024;
    if bytes.len() > MAX_UPLOAD_BYTES {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Файл слишком большой (максимум 5 МБ)" })),
        );
    }

    let upload_dir = "static/img/products";
    if let Err(_) = tokio::fs::create_dir_all(upload_dir).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось подготовить папку для загрузки" })));
    }

    let file_name = format!("{}.{}", Uuid::new_v4(), extension);
    let file_path = format!("{}/{}", upload_dir, file_name);

    if let Err(_) = tokio::fs::write(&file_path, &bytes).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "Не удалось сохранить файл" })));
    }

    let public_path = format!("/img/products/{}", file_name);
    (StatusCode::OK, Json(json!({ "ok": true, "path": public_path })))
}

async fn admin_add_brand(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(body): Json<BrandInput>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    let id: Option<i32> = sqlx::query_scalar(
        "INSERT INTO brands (name) VALUES ($1) ON CONFLICT (name) DO NOTHING RETURNING id",
    )
    .bind(&body.name)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    match id {
        Some(id) => (StatusCode::OK, Json(json!({ "ok": true, "id": id }))),
        None => (StatusCode::BAD_REQUEST, Json(json!({ "error": "Такой бренд уже существует" }))),
    }
}

async fn admin_delete_brand(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<i32>,
) -> (StatusCode, Json<Value>) {
    if !check_admin(&state, &headers) {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Доступ запрещён" })));
    }

    match sqlx::query("DELETE FROM brands WHERE id = $1").bind(id).execute(&state.pool).await {
        Ok(res) if res.rows_affected() > 0 => (StatusCode::OK, Json(json!({ "ok": true }))),
        Ok(_) => (StatusCode::NOT_FOUND, Json(json!({ "error": "Категория не найдена" }))),
        Err(_) => (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Нельзя удалить бренд, у которого есть товары" })),
        ),
    }
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt::init();

    let database_url = std::env::var("DATABASE_URL")
        .expect("Нужно указать DATABASE_URL (например, в .env)");

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Не удалось подключиться к базе данных");

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    println!("Сайт и API Sneakerdope доступны на http://0.0.0.0:{port} ...");

    let app_state: SharedState = Arc::new(AppState {
        pool,
        sessions: Mutex::new(HashMap::new()),
    });

    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::mirror_request())
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE, Method::OPTIONS])
        .allow_headers([
            axum::http::header::CONTENT_TYPE,
            axum::http::header::AUTHORIZATION,
            HeaderName::from_static("x-session-id"),
        ]);

    let app = Router::new()
        .route("/api/products", get(list_products))
        .route("/api/products/latest", get(latest_products))
        .route("/api/products/bestsellers", get(bestseller_products))
        .route("/api/products/{id}", get(get_product))
        .route("/api/brands", get(list_brands))
        .route("/api/register", post(register))
        .route("/api/login", post(login))
        .route("/api/logout", post(logout))
        .route("/api/me", get(get_me))
        .route("/api/cart", get(get_cart))
        .route("/api/cart/add", post(cart_add))
        .route("/api/cart/update", post(cart_update))
        .route("/api/cart/remove", post(cart_remove))
        .route("/api/orders", post(create_order).get(my_orders))
        .route("/api/orders/{id}", delete(delete_order))
        .route("/api/delivery-slots", get(get_delivery_slots))
        .route("/api/admin/orders", get(admin_list_orders))
        .route("/api/admin/orders/{id}", post(admin_update_order))
        .route("/api/admin/products", get(admin_list_products).post(admin_add_product))
        .route("/api/admin/products/{id}", put(admin_edit_product).delete(admin_delete_product))
        .route("/api/admin/upload", post(admin_upload_image).layer(DefaultBodyLimit::max(6 * 1024 * 1024)))
        .route("/api/admin/brands", post(admin_add_brand))
        .route("/api/admin/brands/{id}", delete(admin_delete_brand))
        .fallback_service(ServeDir::new("static"))
        .with_state(app_state)
        .layer(cors);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
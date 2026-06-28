const API_BASE = "";

const AUTH_TOKEN_KEY = "sneakerdope_token";
const AUTH_ROLE_KEY = "sneakerdope_role";
const GUEST_SESSION_KEY = "sneakerdope_session_id";

function getAuthToken() {
  return localStorage.getItem(AUTH_TOKEN_KEY);
}

function setAuthToken(token) {
  localStorage.setItem(AUTH_TOKEN_KEY, token);
}

function clearAuthToken() {
  localStorage.removeItem(AUTH_TOKEN_KEY);
  localStorage.removeItem(AUTH_ROLE_KEY);
}

function isLoggedIn() {
  return !!getAuthToken();
}

function getCachedRole() {
  return localStorage.getItem(AUTH_ROLE_KEY);
}

function setCachedRole(role) {
  localStorage.setItem(AUTH_ROLE_KEY, role);
}

function isAdmin() {
  return getCachedRole() === "admin";
}

function getGuestSessionId() {
  let id = localStorage.getItem(GUEST_SESSION_KEY);
  if (!id) {
    id = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));
    localStorage.setItem(GUEST_SESSION_KEY, id);
  }
  return id;
}

function capitalize(str) {
  if (!str) return str;
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// МАЛЕНЬКИЙ ПОМОЩНИК ДЛЯ ЗАПРОСОВ К API
async function api(path, method = "GET", body = null) {
  const headers = { "X-Session-Id": getGuestSessionId() };

  const token = getAuthToken();
  if (token) {
    headers["Authorization"] = "Bearer " + token;
  }

  const options = {
    method: method,
    headers: headers,
  };

  if (body !== null) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }

  try {
    const res = await fetch(API_BASE + path, options);

    if (res.status === 401 && token) {
      clearAuthToken();
    }

    let data = null;
    try {
      data = await res.json();
    } catch (parseError) {
      data = null;
    }

    return { ok: res.ok, status: res.status, data: data };
  } catch (networkError) {
    console.error("Не получилось достучаться до сервера:", networkError);
    return { ok: false, status: 0, data: null };
  }
}

function formatPrice(value) {
  return value.toLocaleString("ru-RU") + " ₽";
}

// ШАПКА САЙТА

async function refreshCartCount() {
  const result = await api("/api/cart");
  if (!result.ok || !result.data) return;

  let count = 0;
  for (const item of result.data.items) {
    count += item.qty;
  }

  document.querySelectorAll(".cart-count").forEach((el) => {
    el.textContent = String(count);
  });
}

function refreshAuthLinks() {
  const loggedIn = isLoggedIn();

  document.querySelectorAll(".auth-links").forEach((block) => {
    if (loggedIn) {
      const adminLinkHtml = isAdmin()
        ? '<a href="admin.html">Админ-панель</a><span class="divider">/</span>'
        : "";
      block.innerHTML =
        adminLinkHtml +
        '<a href="profile.html">Личный кабинет</a>' +
        '<span class="divider">/</span>' +
        '<a href="#" data-logout>Выйти</a>';
    } else {
      block.innerHTML =
        '<a href="auth.html">Войти</a>' +
        '<span class="divider">/</span>' +
        '<a href="auth.html">Регистрация</a>';
    }
  });

  document.querySelectorAll("[data-logout]").forEach((link) => {
    link.addEventListener("click", async (e) => {
      e.preventDefault();
      await api("/api/logout", "POST");
      clearAuthToken();
      window.location.href = "index.html";
    });
  });
}

async function syncRoleFromServer() {
  if (!isLoggedIn()) return;

  const result = await api("/api/me");
  if (!result.ok || !result.data) return;

  const serverRole = result.data.role || "user";
  if (serverRole !== getCachedRole()) {
    setCachedRole(serverRole);
    refreshAuthLinks();
  }
}

function initHeader() {
  refreshCartCount();
  refreshAuthLinks();
  syncRoleFromServer();
}

// ОБЩЕЕ ДЛЯ ТОВАРОВ

function productImageSrc(image) {
  if (!image) return "";
  if (image.startsWith("/") || image.startsWith("http")) return image;
  return "img/products/" + image;
}

function productBadgeHtml(p) {
  const createdAt = new Date(p.created_at);
  if (isNaN(createdAt.getTime())) return "";
  const daysAgo = (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24);
  if (daysAgo > 7) return "";
  return '<span class="tag product-card__badge">New</span>';
}

function productPriceHtml(p) {
  return formatPrice(p.price);
}

function productCardHtml(p) {
  const quickAddSize = p.size_options && p.size_options.length ? p.size_options[0] : "";
  const imageSrc = productImageSrc(p.image);
  const imageHtml = imageSrc
    ? '<img src="' + imageSrc + '" alt="' + p.name + '" loading="lazy" />'
    : "Фото товара";
  return (
    '<article class="product-card">' +
      '<div class="product-card__media">' +
        productBadgeHtml(p) +
        '<a class="product-card__media-link" href="product.html?id=' + p.id + '" aria-label="Открыть товар"></a>' +
        imageHtml +
        '<button class="product-card__add" type="button" data-add-to-cart="' + p.id + '" data-add-to-cart-size="' + quickAddSize + '" aria-label="В корзину">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M12 5v14M5 12h14"/></svg>' +
        "</button>" +
      "</div>" +
      '<p class="product-card__brand">' + p.brand + "</p>" +
      '<h3 class="product-card__name"><a href="product.html?id=' + p.id + '">' + p.name + "</a></h3>" +
      '<p class="product-card__price">' + productPriceHtml(p) + "</p>" +
    "</article>"
  );
}

function bindAddToCartButtons() {
  document.querySelectorAll("[data-add-to-cart]").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.preventDefault();
      const productId = Number(btn.getAttribute("data-add-to-cart"));
      const size = btn.getAttribute("data-add-to-cart-size");
      if (!size) {
        alert("У этого товара пока нет доступных размеров");
        return;
      }
      const result = await api("/api/cart/add", "POST", { product_id: productId, size: size, qty: 1 });
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не получилось добавить товар в корзину");
        return;
      }
      refreshCartCount();
    });
  });
}

function getSliderVisibleCount() {
  const width = window.innerWidth;
  if (width <= 720) return 2;
  if (width <= 1024) return 3;
  return 5;
}

function initSlider(products) {
  const slider = document.querySelector(".slider");
  const track = document.querySelector(".slider__track");
  if (!slider || !track || products.length === 0) return;

  track.innerHTML = products.map(productCardHtml).join("");
  bindAddToCartButtons();

  const total = products.length;
  let visible = getSliderVisibleCount();
  let index = 0;

  const prevBtn = slider.querySelector(".slider__arrow--prev");
  const nextBtn = slider.querySelector(".slider__arrow--next");
  const dotsWrap = slider.querySelector(".slider__dots");

  function updateControlsVisibility() {
    const needsSlider = total > visible;
    if (prevBtn) prevBtn.style.display = needsSlider ? "" : "none";
    if (nextBtn) nextBtn.style.display = needsSlider ? "" : "none";
    if (dotsWrap) dotsWrap.style.display = needsSlider ? "" : "none";
  }

  function renderDots() {
    if (!dotsWrap) return;
    const dotsCount = Math.max(1, total - visible + 1);
    let html = "";
    for (let i = 0; i < dotsCount; i++) {
      html += '<span class="dot' + (i === index ? " is-active" : "") + '" data-dot="' + i + '"></span>';
    }
    dotsWrap.innerHTML = html;
    dotsWrap.querySelectorAll(".dot").forEach((dot) => {
      dot.addEventListener("click", () => {
        index = Number(dot.getAttribute("data-dot"));
        goTo(index);
        restartAutoplay();
      });
    });
  }

  function goTo(newIndex) {
    const maxIndex = Math.max(0, total - visible);

    if (newIndex > maxIndex) {
      newIndex = 0;
    } else if (newIndex < 0) {
      newIndex = maxIndex;
    }

    index = newIndex;
    const cardWidth = track.children[0] ? track.children[0].getBoundingClientRect().width : 0;
    const gap = parseFloat(getComputedStyle(track).gap) || 0;
    track.style.transform = "translateX(-" + index * (cardWidth + gap) + "px)";

    if (dotsWrap) {
      dotsWrap.querySelectorAll(".dot").forEach((dot, i) => {
        dot.classList.toggle("is-active", i === index);
      });
    }
  }

  if (prevBtn) {
    prevBtn.addEventListener("click", () => {
      goTo(index - 1);
      restartAutoplay();
    });
  }
  if (nextBtn) {
    nextBtn.addEventListener("click", () => {
      goTo(index + 1);
      restartAutoplay();
    });
  }

  const AUTOPLAY_DELAY = 3000;
  let autoplayTimer = null;

  function startAutoplay() {
    stopAutoplay();
    autoplayTimer = setInterval(() => {
      goTo(index + 1);
    }, AUTOPLAY_DELAY);
  }

  function stopAutoplay() {
    if (autoplayTimer) {
      clearInterval(autoplayTimer);
      autoplayTimer = null;
    }
  }

  function restartAutoplay() {
    if (total > visible) startAutoplay();
  }

  slider.addEventListener("mouseenter", stopAutoplay);
  slider.addEventListener("mouseleave", () => restartAutoplay());

  updateControlsVisibility();
  renderDots();
  goTo(0);
  restartAutoplay();

  window.addEventListener("resize", () => {
    const newVisible = getSliderVisibleCount();
    if (newVisible !== visible) {
      visible = newVisible;
      updateControlsVisibility();
      renderDots();
    }
    goTo(Math.min(index, Math.max(0, total - visible)));
  });
}

async function renderBrandStrip() {
  const row = document.querySelector(".brand-strip__row");
  if (!row) return;

  const result = await api("/api/brands");
  if (!result.ok || !result.data) return;

  row.innerHTML = result.data
    .map((b) => '<span class="brand-strip__name">' + b.name + "</span>")
    .join("");
}


// ГЛАВНАЯ СТРАНИЦА (index.html)
async function renderBestsellers() {
  const bestsellersBlock = document.querySelector(".bestsellers");
  if (!bestsellersBlock) return;

  const head = bestsellersBlock.querySelector(".bestsellers__head");

  const result = await api("/api/products/bestsellers");
  if (!result.ok || !result.data) return;

  const top3 = result.data.slice(0, 3);

  const itemsHtml = top3
    .map((p, i) => {
      const imageSrc = productImageSrc(p.image);
      const thumbHtml = imageSrc
        ? '<img src="' + imageSrc + '" alt="' + p.name + '" loading="lazy" />'
        : "";
      return (
        '<div class="bestsellers__item">' +
          '<span class="bestsellers__rank">0' + (i + 1) + "</span>" +
          '<div class="bestsellers__thumb">' + thumbHtml + "</div>" +
          "<div>" +
            '<p class="bestsellers__name"><a href="product.html?id=' + p.id + '">' + p.name + "</a></p>" +
            '<p class="bestsellers__price">' + formatPrice(p.price) + "</p>" +
          "</div>" +
        "</div>"
      );
    })
    .join("");

  bestsellersBlock.innerHTML = "";
  if (head) bestsellersBlock.appendChild(head);
  bestsellersBlock.insertAdjacentHTML("beforeend", itemsHtml);
}

async function initIndexPage() {
  const result = await api("/api/products/latest");
  if (!result.ok || !result.data) return;

  const products = result.data;

  initSlider(products);

  renderBrandStrip();

  renderBestsellers();

  const grid4 = document.querySelector(".grid-4");
  if (grid4) {
    grid4.innerHTML = products.slice(0, 4).map(productCardHtml).join("");
  }

  bindAddToCartButtons();
}

let catalogProducts = [];
let catalogPage = 1;
const CATALOG_PAGE_SIZE = 21;

function getFilterGroup(name) {
  return document.querySelector('.filters__group[data-filter-group="' + name + '"]');
}

function getCheckedValues(groupName) {
  const group = getFilterGroup(groupName);
  const result = [];
  if (!group) return result;
  group.querySelectorAll('input[type="checkbox"][data-value]').forEach((checkbox) => {
    if (checkbox.checked) {
      result.push(checkbox.getAttribute("data-value"));
    }
  });
  return result;
}

function getCheckedGenders() {
  const group = getFilterGroup("gender");
  const result = [];
  if (!group) return result;
  group.querySelectorAll('input[type="checkbox"][data-gender]').forEach((checkbox) => {
    if (checkbox.checked) {
      result.push(checkbox.getAttribute("data-gender"));
    }
  });
  return result;
}

function renderBrandFilter() {
  const group = getFilterGroup("brand");
  const list = group ? group.querySelector("[data-options-list]") : null;
  if (!list) return;

  const previouslyChecked = new Set(getCheckedValues("brand"));

  const counts = new Map();
  catalogProducts.forEach((p) => {
    counts.set(p.brand, (counts.get(p.brand) || 0) + 1);
  });

  const brands = Array.from(counts.keys()).sort((a, b) => a.localeCompare(b, "ru"));

  list.innerHTML = brands
    .map((brand) => {
      const checked = previouslyChecked.has(brand) ? " checked" : "";
      return (
        '<label class="filters__option">' +
          '<input type="checkbox" data-value="' + brand + '"' + checked + " />" +
          brand +
          '<span class="count">' + counts.get(brand) + "</span>" +
        "</label>"
      );
    })
    .join("");
}

function renderSizeFilter() {
  const group = getFilterGroup("size");
  const list = group ? group.querySelector("[data-options-list]") : null;
  if (!list) return;

  const previouslyChecked = new Set(getCheckedValues("size"));

  const sizesSet = new Set();
  catalogProducts.forEach((p) => {
    p.size_options.forEach((s) => sizesSet.add(s));
  });

  const sizes = Array.from(sizesSet).sort((a, b) => Number(a) - Number(b));

  list.innerHTML = sizes
    .map((size) => {
      const checked = previouslyChecked.has(size) ? " checked" : "";
      return (
        '<label class="filters__option"><input type="checkbox" data-value="' + size + '"' + checked + " /> " + size + "</label>"
      );
    })
    .join("");
}

function bindFilterInputs() {
  document.querySelectorAll(".filters input").forEach((input) => {
    input.addEventListener("change", () => {
      catalogPage = 1;
      applyCatalogFilters();
    });
  });
}

function renderPagination(totalItems) {
  const nav = document.querySelector(".pagination");
  if (!nav) return;

  const totalPages = Math.ceil(totalItems / CATALOG_PAGE_SIZE);

  if (totalPages <= 1) {
    nav.style.display = "none";
    nav.innerHTML = "";
    return;
  }

  if (catalogPage > totalPages) {
    catalogPage = totalPages;
  }

  nav.style.display = "";

  let html = "";
  for (let page = 1; page <= totalPages; page++) {
    html +=
      '<a href="#" data-page="' + page + '" class="' + (page === catalogPage ? "is-active" : "") + '">' +
      page +
      "</a>";
  }
  if (catalogPage < totalPages) {
    html += '<a href="#" data-page="' + (catalogPage + 1) + '">→</a>';
  }

  nav.innerHTML = html;

  nav.querySelectorAll("a[data-page]").forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      catalogPage = Number(link.getAttribute("data-page"));
      applyCatalogFilters();
      nav.scrollIntoView({ behavior: "smooth", block: "nearest" });
    });
  });
}

function applyCatalogFilters() {
  const grid = document.querySelector(".catalog-grid");
  if (!grid) return;

  let list = catalogProducts.slice();

  const priceFrom = document.querySelector('.price-range input[placeholder="от"]');
  const priceTo = document.querySelector('.price-range input[placeholder="до"]');
  if (priceFrom && priceFrom.value !== "") {
    list = list.filter((p) => p.price >= Number(priceFrom.value));
  }
  if (priceTo && priceTo.value !== "") {
    list = list.filter((p) => p.price <= Number(priceTo.value));
  }

  const brands = getCheckedValues("brand");
  if (brands.length > 0) {
    list = list.filter((p) => brands.includes(p.brand));
  }

  const sizes = getCheckedValues("size");
  if (sizes.length > 0) {
    list = list.filter((p) => p.size_options.some((s) => sizes.includes(s)));
  }

  const genders = getCheckedGenders();
  if (genders.length > 0) {
    list = list.filter((p) => genders.includes(p.gender));
  }

  const sortSelect = document.querySelector("#sort-select");
  const sortValue = sortSelect ? sortSelect.value : "";

  if (sortValue === "По цене: сначала дешевле") {
    list.sort((a, b) => a.price - b.price);
  } else if (sortValue === "По цене: сначала дороже") {
    list.sort((a, b) => b.price - a.price);
  } else if (sortValue === "По размеру") {
    list.sort((a, b) => {
      const minA = Math.min(...a.size_options.map(Number));
      const minB = Math.min(...b.size_options.map(Number));
      return minA - minB;
    });
  }

  const countEl = document.querySelector(".catalog-toolbar__count");
  if (countEl) {
    countEl.textContent = "Найдено " + list.length + " товаров";
  }

  const totalPages = Math.max(1, Math.ceil(list.length / CATALOG_PAGE_SIZE));
  if (catalogPage > totalPages) catalogPage = totalPages;
  if (catalogPage < 1) catalogPage = 1;

  const start = (catalogPage - 1) * CATALOG_PAGE_SIZE;
  const pageItems = list.slice(start, start + CATALOG_PAGE_SIZE);

  grid.innerHTML = pageItems.map(productCardHtml).join("");

  renderPagination(list.length);

  bindAddToCartButtons();
}

function applyGenderFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const gender = params.get("gender");
  if (!gender) return;

  const group = getFilterGroup("gender");
  if (!group) return;
  const checkbox = group.querySelector('input[data-gender="' + gender + '"]');
  if (checkbox) checkbox.checked = true;
}


// КАТАЛОГ (catalog.html)
async function loadCatalog() {
  const result = await api("/api/products");
  if (!result.ok || !result.data) {
    alert("Не удалось загрузить каталог. Попробуйте обновить страницу.");
    return;
  }
  catalogProducts = result.data;
  renderBrandFilter();
  renderSizeFilter();
  applyGenderFromUrl();
  bindFilterInputs();
  applyCatalogFilters();
}

function initCatalogPage() {
  loadCatalog();

  const sortSelect = document.querySelector("#sort-select");
  if (sortSelect) {
    sortSelect.addEventListener("change", applyCatalogFilters);
  }

  const resetBtn = document.querySelector(".filters .btn--ghost");
  if (resetBtn) {
    resetBtn.addEventListener("click", () => {
      document.querySelectorAll(".filters input").forEach((input) => {
        if (input.type === "checkbox") {
          input.checked = false;
        } else {
          input.value = "";
        }
      });
      catalogPage = 1;
      applyCatalogFilters();
    });
  }
}


// СТРАНИЦА ТОВАРА (product.html)
async function initProductPage() {
  const params = new URLSearchParams(window.location.search);
  const id = Number(params.get("id")) || 1;

  const result = await api("/api/products/" + id);
  if (!result.ok || !result.data) {
    alert("Товар не найден");
    return;
  }
  const product = result.data;

  document.title = "Sneakerdope — " + product.name;

  const crumbs = document.querySelector(".page-head__crumbs");
  if (crumbs) crumbs.textContent = "Главная / Каталог / " + product.name;

  const brandEl = document.querySelector(".product-info__brand");
  if (brandEl) brandEl.textContent = product.brand;

  const nameEl = document.querySelector(".product-info h1");
  if (nameEl) nameEl.textContent = product.name;

  const galleryMain = document.querySelector(".product-gallery__main");
  if (galleryMain) {
    const imageSrc = productImageSrc(product.image);
    galleryMain.innerHTML = imageSrc
      ? '<img src="' + imageSrc + '" alt="' + product.name + '" />'
      : "Фото товара";
  }

  const priceEl = document.querySelector(".product-info__price");
  if (priceEl) priceEl.innerHTML = productPriceHtml(product);

  const stockEl = document.querySelector(".product-info__stock");
  if (stockEl) {
    if (product.stock <= 0) {
      stockEl.textContent = "Нет в наличии";
      stockEl.classList.add("product-info__stock--out");
      stockEl.classList.remove("product-info__stock--low");
    } else if (product.stock <= 3) {
      stockEl.textContent = "Осталось всего " + product.stock + " шт.";
      stockEl.classList.add("product-info__stock--low");
      stockEl.classList.remove("product-info__stock--out");
    } else {
      stockEl.textContent = "В наличии: " + product.stock + " шт.";
      stockEl.classList.remove("product-info__stock--low", "product-info__stock--out");
    }
  }

  const descEl = document.querySelector(".product-description");
  if (descEl) descEl.textContent = product.description;

  const specsValues = {
    brand: product.brand,
    material_upper: product.material_upper,
    material_sole: product.material_sole,
    color: product.color,
    season: capitalize(product.season),
    country: product.country,
  };
  document.querySelectorAll(".specs-table [data-field]").forEach((cell) => {
    const field = cell.getAttribute("data-field");
    if (field in specsValues) {
      cell.textContent = specsValues[field];
    }
  });

  const sizeGrid = document.querySelector(".size-grid");
  if (sizeGrid) {
    sizeGrid.innerHTML = product.size_options
      .map((size, i) => {
        return (
          '<input type="radio" name="size" id="size-' + size + '" ' + (i === 0 ? "checked" : "") + " />" +
          '<label for="size-' + size + '">' + size + "</label>"
        );
      })
      .join("");
  }

  const addBtn = document.querySelector(".product-actions .btn--primary");
  const qtyInput = document.querySelector(".product-info .qty-stepper input");
  const qtyButtons = document.querySelectorAll(".product-info .qty-stepper button");

  if (product.stock <= 0) {
    if (addBtn) {
      addBtn.textContent = "Нет в наличии";
      addBtn.disabled = true;
    }
  }

  if (qtyButtons.length === 2 && qtyInput) {
    qtyButtons[0].addEventListener("click", () => {
      const current = Number(qtyInput.value) || 1;
      qtyInput.value = Math.max(1, current - 1);
    });
    qtyButtons[1].addEventListener("click", () => {
      const current = Number(qtyInput.value) || 1;
      qtyInput.value = Math.min(product.stock, current + 1);
    });
  }

  if (addBtn) {
    addBtn.addEventListener("click", async () => {
      const qty = qtyInput ? Number(qtyInput.value) || 1 : 1;
      const selectedSizeInput = sizeGrid ? sizeGrid.querySelector('input[name="size"]:checked') : null;

      if (!selectedSizeInput) {
        alert("Выберите размер");
        return;
      }
      const size = selectedSizeInput.id.replace("size-", "");

      const addResult = await api("/api/cart/add", "POST", { product_id: product.id, size: size, qty: qty });
      if (!addResult.ok) {
        alert((addResult.data && addResult.data.error) || "Не получилось добавить товар в корзину");
        return;
      }
      refreshCartCount();

      const originalText = addBtn.textContent;
      addBtn.textContent = "Добавлено";
      addBtn.disabled = true;
      setTimeout(() => {
        addBtn.textContent = originalText;
        addBtn.disabled = false;
      }, 1200);
    });
  }
}

function cartItemHtml(item) {
  const imageSrc = productImageSrc(item.image);
  const mediaHtml = imageSrc ? '<img src="' + imageSrc + '" alt="' + item.name + '" loading="lazy" />' : "";
  const overStock = item.stock <= 0 || item.qty > item.stock;
  const warningHtml = overStock
    ? '<p class="cart-item__warning">' +
        (item.stock <= 0
          ? "Товара больше нет в наличии"
          : "В наличии только " + item.stock + " шт., уменьшите количество") +
      "</p>"
    : "";
  return (
    '<div class="cart-item' + (overStock ? " cart-item--warning" : "") + '" data-product-id="' + item.product_id + '" data-size="' + item.size + '" data-stock="' + item.stock + '">' +
      '<div class="cart-item__media">' + mediaHtml + "</div>" +
      "<div>" +
        '<p class="cart-item__brand">' + item.brand + "</p>" +
        '<p class="cart-item__name"><a href="product.html?id=' + item.product_id + '">' + item.name + "</a></p>" +
        '<p class="cart-item__size">Размер RU ' + item.size + "</p>" +
        warningHtml +
        '<button class="cart-item__remove" type="button" data-remove>Удалить</button>' +
      "</div>" +
      '<div class="qty-stepper">' +
        '<button type="button" data-qty-minus aria-label="Уменьшить количество">−</button>' +
        '<input type="text" value="' + item.qty + '" inputmode="numeric" aria-label="Количество" data-qty-input />' +
        '<button type="button" data-qty-plus aria-label="Увеличить количество">+</button>' +
      "</div>" +
      '<p class="cart-item__price price">' + formatPrice(item.line_total) + "</p>" +
    "</div>"
  );
}

async function loadCart() {
  const list = document.querySelector(".cart-list");
  const summary = document.querySelector(".cart-summary");
  if (!list) return;

  const result = await api("/api/cart");
  if (!result.ok || !result.data) {
    alert("Не удалось загрузить корзину");
    return;
  }
  const cart = result.data;

  if (cart.items.length === 0) {
    list.innerHTML =
      '<div class="cart-empty">' +
        "<p>В корзине пока пусто.</p>" +
        '<a href="catalog.html" class="btn btn--primary">Перейти в каталог</a>' +
      "</div>";
    if (summary) summary.style.display = "none";
    return;
  }

  if (summary) summary.style.display = "";
  list.innerHTML = cart.items.map(cartItemHtml).join("");

  let totalQty = 0;
  for (const item of cart.items) totalQty += item.qty;

  const hasStockIssue = cart.items.some((item) => item.stock <= 0 || item.qty > item.stock);
  const checkoutBtn = document.getElementById("checkout-open");
  if (checkoutBtn) {
    checkoutBtn.disabled = hasStockIssue;
    checkoutBtn.title = hasStockIssue
      ? "Скорректируйте количество товаров — кое-чего не хватает в наличии"
      : "";
  }

  const rows = document.querySelectorAll(".cart-summary__row");
  if (rows[0]) {
    rows[0].innerHTML = "<span>Товары, " + totalQty + " шт.</span><span class=\"price\">" + formatPrice(cart.total) + "</span>";
  }

  const totalRow = document.querySelector(".cart-summary__row--total");
  if (totalRow) {
    totalRow.innerHTML = "<span>К оплате</span><span class=\"price\">" + formatPrice(cart.total) + "</span>";
  }

  bindCartItemEvents();
}

async function updateCartQty(productId, size, qty) {
  const result = await api("/api/cart/update", "POST", { product_id: productId, size: size, qty: qty });
  if (!result.ok) {
    alert((result.data && result.data.error) || "Не получилось обновить количество");
  }
  loadCart();
  refreshCartCount();
}

function bindCartItemEvents() {
  document.querySelectorAll(".cart-item").forEach((row) => {
    const productId = Number(row.getAttribute("data-product-id"));
    const size = row.getAttribute("data-size");
    const stock = Number(row.getAttribute("data-stock"));
    const qtyInput = row.querySelector("[data-qty-input]");

    row.querySelector("[data-remove]").addEventListener("click", async () => {
      await api("/api/cart/remove", "POST", { product_id: productId, size: size });
      loadCart();
      refreshCartCount();
    });

    row.querySelector("[data-qty-minus]").addEventListener("click", () => {
      const newQty = Math.max(0, Number(qtyInput.value) - 1);
      updateCartQty(productId, size, newQty);
    });

    row.querySelector("[data-qty-plus]").addEventListener("click", () => {
      const newQty = Number(qtyInput.value) + 1;
      if (newQty > stock) {
        alert("В наличии только " + stock + " шт.");
        return;
      }
      updateCartQty(productId, size, newQty);
    });

    qtyInput.addEventListener("change", () => {
      const newQty = Math.max(0, Number(qtyInput.value) || 0);
      if (newQty > stock) {
        alert("В наличии только " + stock + " шт.");
        loadCart();
        return;
      }
      updateCartQty(productId, size, newQty);
    });
  });
}


// КОРЗИНА (cart.html)
function initCartPage() {
  loadCart();

// ОФОРМЛЕНИЕ ЗАКАЗА
  initCheckoutModal();
}

function showCheckoutError(form, fieldName, message) {
  const errorEl = form.querySelector('[data-error-for="' + fieldName + '"]');
  if (errorEl) {
    errorEl.textContent = message;
    errorEl.classList.add("is-visible");
  }
}

function clearCheckoutErrors(form) {
  form.querySelectorAll(".checkout-form__error").forEach((el) => {
    el.classList.remove("is-visible");
  });
}

function todayIsoDate() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return y + "-" + m + "-" + d;
}

async function loadSlotsForDate(dateValue) {
  const container = document.getElementById("checkout-slots");
  if (!container) return;

  if (!dateValue) {
    container.innerHTML = '<p class="slot-grid__empty">Сначала выберите дату</p>';
    return;
  }

  container.innerHTML = '<p class="slot-grid__empty">Загрузка...</p>';

  const result = await api("/api/delivery-slots?date=" + encodeURIComponent(dateValue));
  if (!result.ok || !result.data || !result.data.slots || result.data.slots.length === 0) {
    container.innerHTML = '<p class="slot-grid__empty">На эту дату нет доступных слотов</p>';
    return;
  }

  container.innerHTML = result.data.slots
    .map(function (slot) {
      return (
        '<label class="slot-chip">' +
          '<input type="radio" name="delivery_slot" value="' + slot + '" />' +
          slot +
        "</label>"
      );
    })
    .join("");

  container.querySelectorAll(".slot-chip input").forEach((input) => {
    input.addEventListener("change", () => {
      container.querySelectorAll(".slot-chip").forEach((chip) => chip.classList.remove("is-active"));
      input.closest(".slot-chip").classList.add("is-active");
    });
  });
}

function initCheckoutModal() {
  const overlay = document.getElementById("checkout-overlay");
  const openBtn = document.getElementById("checkout-open");
  const closeBtn = document.getElementById("checkout-close");
  const form = document.getElementById("checkout-form");
  const dateInput = document.getElementById("checkout-date");

  if (!overlay || !openBtn || !form) return;

  if (!isLoggedIn()) {
    openBtn.textContent = "Войдите или зарегистрируйтесь";
  }

  dateInput.min = todayIsoDate();

  function openModal() {
    clearCheckoutErrors(form);
    form.reset();
    loadSlotsForDate("");

    const qtyEl = document.querySelector(".cart-summary__row span:first-child");
    const totalEl = document.querySelector(".cart-summary__row--total span:last-child");
    document.getElementById("checkout-summary-qty").textContent = qtyEl ? qtyEl.textContent : "Товары";
    document.getElementById("checkout-summary-total").textContent = totalEl ? totalEl.textContent : "";

    overlay.hidden = false;
  }

  function closeModal() {
    overlay.hidden = true;
  }

  openBtn.addEventListener("click", () => {
    if (!isLoggedIn()) {
      window.location.href = "auth.html";
      return;
    }
    openModal();
  });
  closeBtn.addEventListener("click", closeModal);
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) closeModal();
  });

  dateInput.addEventListener("change", () => {
    loadSlotsForDate(dateInput.value);
  });

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    clearCheckoutErrors(form);

    const address = form.elements.delivery_address.value.trim();
    const date = form.elements.delivery_date.value;
    const slotInput = form.querySelector('input[name="delivery_slot"]:checked');
    const password = form.elements.password.value;

    let hasError = false;
    if (!address) {
      showCheckoutError(form, "delivery_address", "Укажите адрес доставки");
      hasError = true;
    }
    if (!date) {
      showCheckoutError(form, "delivery_date", "Выберите дату доставки");
      hasError = true;
    }
    if (!slotInput) {
      showCheckoutError(form, "delivery_slot", "Выберите время доставки");
      hasError = true;
    }
    if (!password) {
      showCheckoutError(form, "password", "Введите пароль");
      hasError = true;
    }
    if (hasError) return;

    const submitBtn = form.querySelector('button[type="submit"]');
    submitBtn.disabled = true;

    const result = await api("/api/orders", "POST", {
      delivery_address: address,
      delivery_date: date,
      delivery_slot: slotInput.value,
      password: password,
    });

    submitBtn.disabled = false;

    if (!result.ok) {
      if (result.status === 401) {
        alert("Сессия истекла, нужно войти заново");
        window.location.href = "auth.html";
        return;
      }

      const message = (result.data && result.data.error) || "Не удалось оформить заказ";
      if (message.toLowerCase().indexOf("пароль") !== -1) {
        showCheckoutError(form, "password", message);
      } else {
        showCheckoutError(form, "general", message);
      }
      return;
    }

    closeModal();
    window.location.href = "profile.html";
  });
}

function showFieldError(input, message) {
  const field = input.closest(".field");
  const errorEl = field ? field.querySelector(".field-error") : null;
  if (errorEl) {
    errorEl.textContent = message;
    errorEl.style.display = "block";
  }
}

function clearFieldErrors(form) {
  form.querySelectorAll(".field-error").forEach((el) => {
    el.style.display = "none";
  });
}


// ВХОД И РЕГИСТРАЦИЯ (auth.html)
function initAuthPage() {
  const loginForm = document.querySelector("#form-login");
  const registerForm = document.querySelector("#form-register");

  if (loginForm) {
    loginForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      clearFieldErrors(loginForm);

      const login = loginForm.querySelector("#login-login").value.trim();
      const password = loginForm.querySelector("#login-password").value;

      const result = await api("/api/login", "POST", { login: login, password: password });
      if (!result.ok) {
        const message = (result.data && result.data.error) || "Неверный логин или пароль";
        showFieldError(loginForm.querySelector("#login-login"), message);
        return;
      }

      if (result.data && result.data.token) {
        setAuthToken(result.data.token);
      }

      const me = await api("/api/me");
      if (me.ok && me.data) {
        setCachedRole(me.data.role || "user");
      }

      window.location.href = "index.html";
    });
  }

  if (registerForm) {
    registerForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      clearFieldErrors(registerForm);

      const formData = {
        surname: registerForm.elements.surname.value.trim(),
        name: registerForm.elements.name.value.trim(),
        patronymic: registerForm.elements.patronymic.value.trim() || null,
        login: registerForm.elements.login.value.trim(),
        email: registerForm.elements.email.value.trim(),
        phone: registerForm.elements.phone.value.trim(),
        password: registerForm.elements.password.value,
        password_repeat: registerForm.elements.password_repeat.value,
        rules: registerForm.elements.rules.checked,
      };

      const result = await api("/api/register", "POST", formData);
      if (!result.ok) {
        const errors = (result.data && result.data.errors) || {};
        const leftover = [];

        for (const fieldName in errors) {
          const input = registerForm.elements[fieldName];
          const field = input ? input.closest(".field") : null;
          const errorEl = field
            ? field.querySelector(".field-error")
            : registerForm.querySelector('[data-error-for="' + fieldName + '"]');

          if (errorEl) {
            errorEl.textContent = errors[fieldName];
            errorEl.style.display = "block";
          } else {
            leftover.push(errors[fieldName]);
          }
        }

        if (leftover.length > 0) {
          alert(leftover.join("\n"));
        }
        return;
      }

      if (result.data && result.data.token) {
        setAuthToken(result.data.token);
      }

      setCachedRole("user");

      window.location.href = "index.html";
    });
  }
}

const ORDER_STATUS_LABELS = {
  new: "Новый",
  confirmed: "Подтверждён",
  cancelled: "Отменён",
};

function formatOrderDate(isoString) {
  const d = new Date(isoString);
  if (isNaN(d.getTime())) return isoString;
  return d.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric" });
}

function formatDeliveryDate(isoDate) {
  const parts = isoDate.split("-");
  if (parts.length !== 3) return isoDate;
  return parts[2] + "." + parts[1] + "." + parts[0];
}

function orderTotal(order) {
  let total = 0;
  for (const item of order.items) total += item.price * item.qty;
  return total;
}

function orderCardHtml(order) {
  const statusKey = order.status || "new";
  const statusLabel = ORDER_STATUS_LABELS[statusKey] || statusKey;

  const itemsHtml = order.items
    .map(function (item) {
      const sizeLabel = item.size ? " · RU " + item.size : "";
      return (
        '<div class="order-card__item-row">' +
          "<span>" + item.product_name + sizeLabel + " × " + item.qty + "</span>" +
          '<span class="price">' + formatPrice(item.price * item.qty) + "</span>" +
        "</div>"
      );
    })
    .join("");

  const cancelReasonHtml =
    statusKey === "cancelled" && order.cancel_reason
      ? '<p class="order-card__cancel-reason">Причина отмены: ' + order.cancel_reason + "</p>"
      : "";

  const cancelBtnHtml =
    statusKey === "new"
      ? '<button type="button" class="btn btn--ghost btn--small" data-cancel-order="' + order.id + '">Отменить заказ</button>'
      : "";

  return (
    '<article class="order-card">' +
      '<div class="order-card__head">' +
        '<span class="order-card__number">Заказ №' + order.id + "</span>" +
        '<span class="order-status order-status--' + statusKey + '">' + statusLabel + "</span>" +
      "</div>" +
      '<div class="order-card__body">' +
        '<p class="order-card__delivery">' +
          "<b>Доставка:</b> " + order.delivery_address + "<br />" +
          "<b>Дата и время:</b> " + formatDeliveryDate(order.delivery_date) + ", " + order.delivery_slot +
        "</p>" +
        '<div class="order-card__items">' + itemsHtml + "</div>" +
        cancelReasonHtml +
        '<div class="order-card__foot">' +
          '<span class="order-card__date">от ' + formatOrderDate(order.created_at) + "</span>" +
          '<div style="display:flex; align-items:center; gap:14px;">' +
            cancelBtnHtml +
            '<span class="order-card__total price">' + formatPrice(orderTotal(order)) + "</span>" +
          "</div>" +
        "</div>" +
      "</div>" +
    "</article>"
  );
}

function bindOrderCancelButtons(container) {
  container.querySelectorAll("[data-cancel-order]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!confirm("Отменить заказ №" + btn.getAttribute("data-cancel-order") + "?")) return;
      const orderId = Number(btn.getAttribute("data-cancel-order"));
      const result = await api("/api/orders/" + orderId, "DELETE");
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не удалось отменить заказ");
        return;
      }
      loadProfileOrders();
    });
  });
}

async function loadProfileOrders() {
  const currentEl = document.getElementById("orders-current");
  const historyEl = document.getElementById("orders-history");
  if (!currentEl || !historyEl) return;

  const result = await api("/api/orders");
  if (!result.ok || !result.data) {
    currentEl.innerHTML = '<div class="orders-empty">Не удалось загрузить заказы</div>';
    historyEl.innerHTML = "";
    return;
  }

  const orders = result.data;
  const current = orders.filter((o) => o.status === "new");
  const history = orders.filter((o) => o.status !== "new");

  currentEl.innerHTML = current.length
    ? current.map(orderCardHtml).join("")
    : '<div class="orders-empty">Текущих заказов нет</div>';

  historyEl.innerHTML = history.length
    ? history.map(orderCardHtml).join("")
    : '<div class="orders-empty">История заказов пуста</div>';

  bindOrderCancelButtons(currentEl);
}

async function loadProfileInfo() {
  const card = document.getElementById("profile-card");
  if (!card) return;

  if (!isLoggedIn()) {
    window.location.href = "auth.html";
    return;
  }

  const result = await api("/api/me");
  if (!result.ok || !result.data) {
    clearAuthToken();
    window.location.href = "auth.html";
    return;
  }

  const user = result.data;
  const fio = [user.surname, user.name, user.patronymic].filter(Boolean).join(" ");

  card.querySelector(".profile-card__name").textContent = fio;
  card.querySelector(".profile-card__login").textContent = "@" + user.login;

  const rows = card.querySelectorAll(".profile-card__row");
  if (rows[0]) rows[0].innerHTML = "<span>Email</span><span>" + user.email + "</span>";
  if (rows[1]) rows[1].innerHTML = "<span>Телефон</span><span>" + user.phone + "</span>";

  const logoutBtn = card.querySelector(".profile-card__logout");
  if (logoutBtn) {
    logoutBtn.addEventListener("click", async () => {
      await api("/api/logout", "POST");
      clearAuthToken();
      window.location.href = "index.html";
    });
  }
}


// ЛИЧНЫЙ КАБИНЕТ
function initProfilePage() {
  loadProfileInfo();
  loadProfileOrders();
}


// АДМИНКА (admin.html)
function initAdminTabs() {
  const tabButtons = document.querySelectorAll("[data-admin-tab]");
  tabButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const target = btn.getAttribute("data-admin-tab");

      tabButtons.forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");

      document.querySelectorAll("[data-admin-panel]").forEach((panel) => {
        panel.hidden = panel.getAttribute("data-admin-panel") !== target;
      });
    });
  });
}


// АДМИНКА - заказы
function adminOrderRowHtml(order) {
  const statusKey = order.status || "new";
  const statusLabel = ORDER_STATUS_LABELS[statusKey] || statusKey;

  const itemsText = order.items
    .map((item) => item.product_name + (item.size ? " (RU " + item.size + ")" : "") + " × " + item.qty)
    .join(", ");

  const actionsHtml =
    statusKey === "new"
      ? '<button type="button" class="btn btn--ghost btn--small" data-order-confirm="' + order.id + '">Подтвердить</button>' +
        '<button type="button" class="btn btn--ghost btn--small" data-order-cancel="' + order.id + '">Отменить</button>'
      : "";

  return (
    '<tr>' +
      "<td>№" + order.id + "</td>" +
      "<td>" + order.user_fio + "</td>" +
      "<td>" + itemsText + "</td>" +
      "<td>" + formatDeliveryDate(order.delivery_date) + ", " + order.delivery_slot + "</td>" +
      '<td class="price">' + formatPrice(orderTotal(order)) + "</td>" +
      '<td><span class="order-status order-status--' + statusKey + '">' + statusLabel + "</span></td>" +
      '<td class="admin-table__actions">' + actionsHtml + "</td>" +
    "</tr>"
  );
}

async function loadAdminOrders() {
  const tbody = document.querySelector("#admin-orders-table tbody");
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="admin-table__empty">Загрузка...</td></tr>';

  const result = await api("/api/admin/orders");
  if (!result.ok || !result.data) {
    tbody.innerHTML = '<tr><td colspan="7" class="admin-table__empty">Не удалось загрузить заказы</td></tr>';
    return;
  }

  const orders = result.data;
  tbody.innerHTML = orders.length
    ? orders.map(adminOrderRowHtml).join("")
    : '<tr><td colspan="7" class="admin-table__empty">Заказов пока нет</td></tr>';

  tbody.querySelectorAll("[data-order-confirm]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const id = Number(btn.getAttribute("data-order-confirm"));
      const result = await api("/api/admin/orders/" + id, "POST", { confirm: true });
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не удалось подтвердить заказ");
        return;
      }
      loadAdminOrders();
    });
  });

  tbody.querySelectorAll("[data-order-cancel]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const reason = prompt("Причина отмены заказа (необязательно):", "") || null;
      const id = Number(btn.getAttribute("data-order-cancel"));
      const result = await api("/api/admin/orders/" + id, "POST", { confirm: false, reason: reason });
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не удалось отменить заказ");
        return;
      }
      loadAdminOrders();
    });
  });
}


// АДМИНКА - бренды
let adminBrandsCache = [];

function adminBrandRowHtml(brand) {
  return (
    "<tr>" +
      "<td>" + brand.name + "</td>" +
      '<td class="admin-table__actions">' +
        '<button type="button" class="btn btn--ghost btn--small" data-brand-delete="' + brand.id + '">Удалить</button>' +
      "</td>" +
    "</tr>"
  );
}

async function loadAdminBrands() {
  const tbody = document.querySelector("#admin-brands-table tbody");

  const result = await api("/api/brands");
  if (!result.ok || !result.data) {
    if (tbody) tbody.innerHTML = '<tr><td colspan="2" class="admin-table__empty">Не удалось загрузить бренды</td></tr>';
    return;
  }

  adminBrandsCache = result.data;
  fillBrandSelect();

  if (!tbody) return;

  tbody.innerHTML = adminBrandsCache.length
    ? adminBrandsCache.map(adminBrandRowHtml).join("")
    : '<tr><td colspan="2" class="admin-table__empty">Брендов пока нет</td></tr>';

  tbody.querySelectorAll("[data-brand-delete]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!confirm("Удалить этот бренд?")) return;
      const id = Number(btn.getAttribute("data-brand-delete"));
      const result = await api("/api/admin/brands/" + id, "DELETE");
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не удалось удалить бренд");
        return;
      }
      loadAdminBrands();
    });
  });
}

function fillBrandSelect() {
  const select = document.getElementById("product-brand");
  if (!select) return;

  const currentValue = select.value;
  select.innerHTML = adminBrandsCache
    .map((b) => '<option value="' + b.name + '">' + b.name + "</option>")
    .join("");

  if (currentValue && adminBrandsCache.some((b) => b.name === currentValue)) {
    select.value = currentValue;
  }
}

function initAdminBrandForm() {
  const form = document.getElementById("admin-brand-form");
  if (!form) return;

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const input = form.elements.name;
    const name = input.value.trim();
    if (!name) return;

    const result = await api("/api/admin/brands", "POST", { name: name });
    if (!result.ok) {
      alert((result.data && result.data.error) || "Не удалось добавить бренд");
      return;
    }

    input.value = "";
    loadAdminBrands();
  });
}


// АДМИНКА - товары
const GENDER_LABELS = {
  male: "Мужской",
  female: "Женский",
  kids: "Детский",
  unisex: "Унисекс",
};

function adminProductRowHtml(p) {
  return (
    "<tr>" +
      "<td>" + p.id + "</td>" +
      "<td>" + p.brand + "</td>" +
      "<td>" + p.name + "</td>" +
      '<td class="price">' + formatPrice(p.price) + "</td>" +
      "<td>" + p.stock + "</td>" +
      "<td>" + (GENDER_LABELS[p.gender] || p.gender) + "</td>" +
      '<td class="admin-table__actions">' +
        '<button type="button" class="btn btn--ghost btn--small" data-product-edit="' + p.id + '">Изменить</button>' +
        '<button type="button" class="btn btn--ghost btn--small" data-product-delete="' + p.id + '">Удалить</button>' +
      "</td>" +
    "</tr>"
  );
}

let adminProductsCache = [];

const ADMIN_PRODUCT_SORTERS = {
  created_desc: (a, b) => (a.id < b.id ? 1 : a.id > b.id ? -1 : 0),
  name_asc: (a, b) => a.name.localeCompare(b.name, "ru"),
  price_asc: (a, b) => a.price - b.price,
  price_desc: (a, b) => b.price - a.price,
  stock_asc: (a, b) => a.stock - b.stock,
  stock_desc: (a, b) => b.stock - a.stock,
};

function renderAdminProducts() {
  const tbody = document.querySelector("#admin-products-table tbody");
  if (!tbody) return;

  const sortSelect = document.getElementById("admin-product-sort");
  const sortKey = sortSelect ? sortSelect.value : "created_desc";
  const sorter = ADMIN_PRODUCT_SORTERS[sortKey] || ADMIN_PRODUCT_SORTERS.created_desc;

  const sorted = adminProductsCache.slice().sort(sorter);

  tbody.innerHTML = sorted.length
    ? sorted.map(adminProductRowHtml).join("")
    : '<tr><td colspan="7" class="admin-table__empty">Товаров пока нет</td></tr>';

  tbody.querySelectorAll("[data-product-edit]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = Number(btn.getAttribute("data-product-edit"));
      const product = adminProductsCache.find((p) => p.id === id);
      if (product) openProductModal(product);
    });
  });

  tbody.querySelectorAll("[data-product-delete]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!confirm("Удалить этот товар?")) return;
      const id = Number(btn.getAttribute("data-product-delete"));
      const result = await api("/api/admin/products/" + id, "DELETE");
      if (!result.ok) {
        alert((result.data && result.data.error) || "Не удалось удалить товар");
        return;
      }
      loadAdminProducts();
    });
  });
}

async function loadAdminProducts() {
  const tbody = document.querySelector("#admin-products-table tbody");
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="admin-table__empty">Загрузка...</td></tr>';

  const result = await api("/api/admin/products");
  if (!result.ok || !result.data) {
    tbody.innerHTML = '<tr><td colspan="7" class="admin-table__empty">Не удалось загрузить товары</td></tr>';
    return;
  }

  adminProductsCache = result.data;
  renderAdminProducts();
}

function initAdminProductSort() {
  const sortSelect = document.getElementById("admin-product-sort");
  if (sortSelect) {
    sortSelect.addEventListener("change", renderAdminProducts);
  }
}

function openProductModal(product) {
  const overlay = document.getElementById("product-overlay");
  const form = document.getElementById("product-form");
  const title = document.getElementById("product-modal-title");
  if (!overlay || !form) return;

  form.reset();
  clearProductFormErrors(form);
  fillBrandSelect();

  const fileNameHint = document.getElementById("product-image-file-name");
  if (fileNameHint) fileNameHint.textContent = "";

  if (product) {
    title.textContent = "Редактировать товар";
    form.dataset.editId = product.id;
    form.elements.name.value = product.name;
    form.elements.brand.value = product.brand;
    form.elements.price.value = product.price;
    form.elements.stock.value = product.stock;
    form.elements.gender.value = product.gender;
    form.elements.size_options.value = (product.size_options || []).join(", ");
    form.elements.description.value = product.description;
    form.elements.image.value = product.image;
    form.elements.material_upper.value = product.material_upper || "";
    form.elements.material_sole.value = product.material_sole || "";
    form.elements.color.value = product.color || "";
    form.elements.season.value = product.season || "";
    form.elements.country.value = product.country || "";
  } else {
    title.textContent = "Новый товар";
    delete form.dataset.editId;
  }

  overlay.hidden = false;
}

function closeProductModal() {
  const overlay = document.getElementById("product-overlay");
  if (overlay) overlay.hidden = true;
}

function showProductFieldError(form, fieldName, message) {
  const errorEl = form.querySelector('[data-error-for="' + fieldName + '"]');
  if (errorEl) {
    errorEl.textContent = message;
    errorEl.style.display = "block";
  } else {
    alert(message);
  }
}

function clearProductFormErrors(form) {
  form.querySelectorAll(".field-error").forEach((el) => {
    el.style.display = "none";
  });
}

function initProductModal() {
  const overlay = document.getElementById("product-overlay");
  const form = document.getElementById("product-form");
  const openBtn = document.getElementById("product-add-open");
  const closeBtn = document.getElementById("product-modal-close");
  const fileInput = document.getElementById("product-image-file");
  const fileNameHint = document.getElementById("product-image-file-name");
  if (!overlay || !form) return;

  if (openBtn) {
    openBtn.addEventListener("click", () => openProductModal(null));
  }
  if (closeBtn) {
    closeBtn.addEventListener("click", closeProductModal);
  }
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) closeProductModal();
  });

  if (fileInput) {
    fileInput.addEventListener("change", async () => {
      const file = fileInput.files && fileInput.files[0];
      if (!file) return;

      if (fileNameHint) fileNameHint.textContent = "Загрузка...";

      const formData = new FormData();
      formData.append("image_file", file);

      const headers = { "X-Session-Id": getGuestSessionId() };
      const token = getAuthToken();
      if (token) headers["Authorization"] = "Bearer " + token;

      try {
        const res = await fetch("/api/admin/upload", { method: "POST", headers: headers, body: formData });
        const data = await res.json().catch(() => null);

        if (!res.ok || !data || !data.path) {
          if (fileNameHint) fileNameHint.textContent = (data && data.error) || "Не удалось загрузить файл";
          return;
        }

        form.elements.image.value = data.path;
        if (fileNameHint) fileNameHint.textContent = "Загружено: " + file.name;
      } catch (networkError) {
        if (fileNameHint) fileNameHint.textContent = "Не получилось достучаться до сервера";
      }
    });
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    clearProductFormErrors(form);

    const sizeOptions = form.elements.size_options.value
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);

    const price = Number(form.elements.price.value);

    const body = {
      name: form.elements.name.value.trim(),
      brand: form.elements.brand.value,
      price: price,
      size_options: sizeOptions,
      stock: Number(form.elements.stock.value),
      description: form.elements.description.value.trim(),
      image: form.elements.image.value.trim(),
      gender: form.elements.gender.value,
      material_upper: form.elements.material_upper.value.trim(),
      material_sole: form.elements.material_sole.value.trim(),
      color: form.elements.color.value.trim(),
      season: form.elements.season.value.trim(),
      country: form.elements.country.value.trim(),
    };

    if (!body.name) {
      showProductFieldError(form, "name", "Укажите название товара");
      return;
    }
    if (!body.brand) {
      showProductFieldError(form, "brand", "Сначала добавьте хотя бы один бренд");
      return;
    }
    if (!Number.isFinite(price) || price <= 0) {
      alert("Цена должна быть больше нуля");
      return;
    }
    if (!Number.isInteger(body.stock) || body.stock < 0) {
      alert("Остаток не может быть отрицательным");
      return;
    }

    const editId = form.dataset.editId;
    const result = editId
      ? await api("/api/admin/products/" + editId, "PUT", body)
      : await api("/api/admin/products", "POST", body);

    if (!result.ok) {
      alert((result.data && result.data.error) || "Не удалось сохранить товар");
      return;
    }

    closeProductModal();
    loadAdminProducts();
  });
}

async function initAdminPage() {
  if (!isLoggedIn()) {
    window.location.href = "auth.html";
    return;
  }

  const me = await api("/api/me");
  if (!me.ok || !me.data || me.data.role !== "admin") {
    window.location.href = "index.html";
    return;
  }
  setCachedRole("admin");

  initAdminTabs();
  initAdminBrandForm();
  initProductModal();
  initAdminProductSort();

  loadAdminOrders();
  loadAdminBrands();
  loadAdminProducts();
}

document.addEventListener("DOMContentLoaded", () => {
  initHeader();

  if (document.querySelector(".slider__track")) initIndexPage();
  if (document.querySelector(".catalog-grid")) initCatalogPage();
  if (document.querySelector(".product-page")) initProductPage();
  if (document.querySelector(".cart-layout")) initCartPage();
  if (document.querySelector("#form-login")) initAuthPage();
  if (document.querySelector(".profile-layout")) initProfilePage();
  if (document.querySelector(".admin-layout")) initAdminPage();
});
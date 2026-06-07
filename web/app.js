(function () {
  "use strict";

  const STORAGE = {
    apiBaseUrl: "stuffTrackerMobileWeb.apiBaseUrl",
    token: "stuffTrackerMobileWeb.token",
    refreshToken: "stuffTrackerMobileWeb.refreshToken",
    user: "stuffTrackerMobileWeb.user",
    homes: "stuffTrackerMobileWeb.homes",
    deletedItems: "stuffTrackerMobileWeb.deletedItems",
    collapsed: "stuffTrackerMobileWeb.collapsed",
  };

  const DEFAULT_API_BASE_URL = defaultApiBaseUrl();
  const APP_ICON_URL = "/assets/app-icon.png?v=20260531-ios-cubby";
  const STORED_TOKEN = localStorage.getItem(STORAGE.token) || "";
  const STORED_REFRESH_TOKEN = localStorage.getItem(STORAGE.refreshToken) || "";
  const HAS_STORED_SESSION = Boolean(STORED_TOKEN || STORED_REFRESH_TOKEN);
  const INITIAL_ITEM_LINK = parseItemDeepLink(window.location);
  const app = document.getElementById("app");

  const state = {
    apiBaseUrl: localStorage.getItem(STORAGE.apiBaseUrl) || DEFAULT_API_BASE_URL,
    token: STORED_TOKEN,
    refreshToken: STORED_REFRESH_TOKEN,
    user: HAS_STORED_SESSION ? readJson(STORAGE.user, null) : null,
    accountPlan: null,
    homes: HAS_STORED_SESSION ? readJson(STORAGE.homes, []) : [],
    homesLoaded: false,
    collapsed: new Set(readJson(STORAGE.collapsed, [])),
    search: "",
    flaggedOnly: false,
    isLoading: false,
    toast: "",
    toastTimer: null,
    sheet: null,
    photoPreview: null,
    isUploadingAttachment: false,
    actionMenu: null,
    draggingItem: null,
    suppressItemClick: false,
    selectionMode: false,
    selectedHomeId: "",
    selectedItemIds: new Set(),
    adding: null,
    iconSearch: "",
    authConfigLoaded: false,
    googleClientId: "",
    appleClientId: "",
    appStoreUrl: "",
    pendingItemLink: INITIAL_ITEM_LINK,
    deepLinkHandled: false,
    highlightedItemId: "",
  };

  let activeDropZone = null;
  let activeDropChip = null;
  let activeTokenRefresh = null;

  if (!HAS_STORED_SESSION) {
    state.collapsed = new Set();
    localStorage.removeItem(STORAGE.user);
    localStorage.removeItem(STORAGE.homes);
    localStorage.removeItem(STORAGE.deletedItems);
    localStorage.removeItem(STORAGE.collapsed);
  }

  const ICON_PATHS = {
    archive: '<path d="M4 7h16v13H4z"/><path d="M3 4h18v3H3z"/><path d="M9 11h6"/>',
    house: '<path d="M3 11 12 4l9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
    building: '<path d="M4 20h16"/><path d="M6 20V5h8v15"/><path d="M14 9h4v11"/><path d="M9 8h2"/><path d="M9 12h2"/><path d="M9 16h2"/>',
    door: '<path d="M7 21V4h10v17"/><path d="M10 12h.01"/><path d="M4 21h16"/>',
    box: '<path d="m3 8 9-5 9 5-9 5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>',
    cabinet: '<path d="M5 4h14v16H5z"/><path d="M5 10h14"/><path d="M10 7h4"/><path d="M10 16h4"/>',
    books: '<path d="M5 4h4v16H5z"/><path d="M9 4h4v16H9z"/><path d="M15 5l4 14"/><path d="M6 8h2"/><path d="M10 15h2"/>',
    drawer: '<path d="M4 6h16v12H4z"/><path d="M4 10h16"/><path d="M4 14h16"/><path d="M11 8h2"/><path d="M11 12h2"/><path d="M11 16h2"/>',
    fridge: '<path d="M7 3h10v18H7z"/><path d="M7 10h10"/><path d="M10 6v2"/><path d="M10 13v3"/>',
    computer: '<path d="M4 5h16v10H4z"/><path d="M9 20h6"/><path d="M12 15v5"/>',
    bag: '<path d="M6 8h12l1 12H5z"/><path d="M9 8a3 3 0 0 1 6 0"/>',
    person: '<path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="7" r="4"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m16.5 16.5 4 4"/>',
    plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    ellipsis: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    trash: '<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M6 6l1 15h10l1-15"/><path d="M10 11v6"/><path d="M14 11v6"/>',
    pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13 7 4 4"/>',
    star: '<path d="m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6-5.4-2.9-5.4 2.9 1-6-4.4-4.3 6.1-.9z"/>',
    flag: '<path d="M5 21V4"/><path d="M5 4h11l-1.5 4L16 12H5"/>',
    sort: '<path d="M7 7h10"/><path d="M7 12h7"/><path d="M7 17h4"/>',
    cloud: '<path d="M17.5 18H8a5 5 0 1 1 1.8-9.7A6 6 0 0 1 21 11a4 4 0 0 1-3.5 7z"/>',
    refresh: '<path d="M20 12a8 8 0 0 1-13.7 5.6"/><path d="M4 12A8 8 0 0 1 17.7 6.4"/><path d="M4 18v-5h5"/><path d="M20 6v5h-5"/>',
    share: '<path d="M8 12h8"/><circle cx="5" cy="12" r="3"/><circle cx="19" cy="5" r="3"/><circle cx="19" cy="19" r="3"/><path d="m16.5 7-9 4"/><path d="m16.5 17-9-4"/>',
    doc: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/>',
    photo: '<path d="M4 5h16v14H4z"/><circle cx="9" cy="10" r="2"/><path d="m4 17 5-5 4 4 2-2 5 5"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.1 0l2-2a5 5 0 0 0-7.1-7.1l-1.2 1.2"/><path d="M14 11a5 5 0 0 0-7.1 0l-2 2A5 5 0 0 0 12 20.1l1.2-1.2"/>',
    apple: '<path d="M16.05 2.1c0 1-.39 1.96-1.08 2.68-.73.77-1.83 1.36-2.82 1.28-.12-.97.41-2.02 1.08-2.7.75-.77 2.03-1.35 2.82-1.26z"/><path d="M20.15 17.35c-.48 1.1-.72 1.6-1.35 2.57-.87 1.36-2.09 3.05-3.61 3.07-1.35.01-1.69-.88-3.52-.87-1.82.01-2.2.89-3.55.88-1.52-.02-2.68-1.54-3.55-2.9-2.43-3.82-2.68-8.34-1.08-10.68 1.14-1.65 2.94-2.63 4.62-2.63 1.71 0 2.79.9 4.2.9 1.37 0 2.21-.9 4.18-.9 1.49 0 3.07.81 4.2 2.22-3.69 2.02-3.09 7.29-.54 8.36z"/>',
    tag: '<path d="M20 13 13 20 4 11V4h7z"/><circle cx="8.5" cy="8.5" r="1"/>',
    heart: '<path d="M20.8 5.6a5.5 5.5 0 0 0-7.8 0L12 6.6l-1-1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 22l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z"/>',
    car: '<path d="M5 16h14l-1.5-5h-11z"/><path d="M7 11l2-4h6l2 4"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="17" r="2"/>',
    tool: '<path d="M14.7 6.3a4 4 0 0 0 5 5L11 20 4 13z"/><path d="M5 12l7 7"/>',
    circle: '<circle cx="12" cy="12" r="6"/>',
  };

  const ICON_SECTIONS = [
    {
      title: "Home",
      icons: [
        ["house.fill", "House"],
        ["building.2", "Building"],
        ["door.left.hand.closed", "Door"],
        ["archivebox.fill", "Archive"],
      ],
    },
    {
      title: "Storage",
      icons: [
        ["shippingbox.fill", "Box"],
        ["cabinet.fill", "Cabinet"],
        ["books.vertical.fill", "Shelf"],
        ["rectangle.split.3x1.fill", "Drawer"],
        ["refrigerator.fill", "Fridge"],
        ["bag.fill", "Bag"],
      ],
    },
    {
      title: "Items",
      icons: [
        ["desktopcomputer", "Computer"],
        ["doc.fill", "Document"],
        ["photo.fill", "Photo"],
        ["tag.fill", "Tag"],
        ["heart.fill", "Health"],
        ["car.fill", "Car"],
        ["wrench.fill", "Tool"],
        ["circle.fill", "Circle"],
      ],
    },
  ];

  function readJson(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch {
      return fallback;
    }
  }

  function defaultApiBaseUrl() {
    const { hostname, origin, port, protocol } = window.location;
    const isLocalHost = hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
    if ((protocol === "http:" || protocol === "https:") && !isLocalHost) {
      return origin;
    }
    if (isLocalHost && port === "3002") {
      return origin;
    }
    return "http://localhost:3002";
  }

  function parseItemDeepLink(location) {
    const parts = location.pathname.split("/").filter(Boolean);
    const offset = parts[0] === "web" ? 1 : 0;
    if (parts[offset] !== "items" || parts.length !== offset + 3) return null;

    const homeId = decodePathPart(parts[offset + 1]);
    const itemId = decodePathPart(parts[offset + 2]);
    if (!homeId || !itemId) return null;

    return {
      homeId,
      itemId,
    };
  }

  function decodePathPart(value) {
    try {
      return decodeURIComponent(value);
    } catch {
      return "";
    }
  }

  function writeJson(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
  }

  function persistSession() {
    if (state.token) {
      localStorage.setItem(STORAGE.token, state.token);
    } else {
      localStorage.removeItem(STORAGE.token);
    }

    if (state.refreshToken) {
      localStorage.setItem(STORAGE.refreshToken, state.refreshToken);
    } else {
      localStorage.removeItem(STORAGE.refreshToken);
    }

    if (state.user) {
      writeJson(STORAGE.user, state.user);
    } else {
      localStorage.removeItem(STORAGE.user);
    }
    localStorage.setItem(STORAGE.apiBaseUrl, state.apiBaseUrl);
  }

  function persistData() {
    writeJson(STORAGE.homes, state.homes);
  }

  function clearCachedData() {
    state.homes = [];
    state.homesLoaded = false;
    state.accountPlan = null;
    state.collapsed = new Set();
    localStorage.removeItem(STORAGE.homes);
    localStorage.removeItem(STORAGE.deletedItems);
    localStorage.removeItem(STORAGE.collapsed);
  }

  function persistCollapsed() {
    writeJson(STORAGE.collapsed, Array.from(state.collapsed));
  }

  function hasAuthSession() {
    return Boolean(state.token || state.refreshToken);
  }

  function clearSession() {
    state.token = "";
    state.refreshToken = "";
    state.user = null;
    resetSelectionMode();
    clearCachedData();
    persistSession();
  }

  function resetSelectionMode() {
    state.selectionMode = false;
    state.selectedHomeId = "";
    state.selectedItemIds.clear();
  }

  function selectedIds() {
    return Array.from(state.selectedItemIds);
  }

  function selectionCount() {
    return state.selectedItemIds.size;
  }

  function selectedHome() {
    return state.selectedHomeId ? findHome(state.selectedHomeId) : null;
  }

  function hasSelectableItems() {
    return state.homes.some((home) => (home.items || []).length > 0);
  }

  function isItemSelected(homeId, itemId) {
    return state.selectedHomeId === homeId && state.selectedItemIds.has(itemId);
  }

  function toggleItemSelection(homeId, itemId) {
    const item = findItem(homeId, itemId);
    if (!item) return false;

    if (!state.selectionMode) {
      state.selectionMode = true;
    }
    if (state.selectedHomeId && state.selectedHomeId !== homeId) {
      showToast("Select items from one home at a time");
      return false;
    }

    state.selectedHomeId = homeId;
    if (state.selectedItemIds.has(itemId)) {
      state.selectedItemIds.delete(itemId);
      if (!state.selectedItemIds.size) state.selectedHomeId = "";
    } else {
      state.selectedItemIds.add(itemId);
    }
    state.actionMenu = null;
    return true;
  }

  function pruneSelection() {
    if (!state.selectedHomeId) return;
    const home = findHome(state.selectedHomeId);
    if (!home) {
      state.selectedHomeId = "";
      state.selectedItemIds.clear();
      return;
    }
    const validIds = new Set(home.items.map((item) => item.id));
    state.selectedItemIds.forEach((itemId) => {
      if (!validIds.has(itemId)) state.selectedItemIds.delete(itemId);
    });
    if (!state.selectedItemIds.size) state.selectedHomeId = "";
  }

  function isLocalHost() {
    return ["localhost", "127.0.0.1", "::1"].includes(window.location.hostname);
  }

  function showToast(message) {
    state.toast = message;
    if (state.toastTimer) {
      clearTimeout(state.toastTimer);
    }
    state.toastTimer = setTimeout(() => {
      state.toast = "";
      render();
    }, 3200);
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function escapeAttr(value) {
    return escapeHtml(value);
  }

  function id() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return window.crypto.randomUUID();
    }
    return "10000000-1000-4000-8000-" + Math.random().toString(16).slice(2, 14).padEnd(12, "0");
  }

  function formatDollars(cents) {
    if (!Number.isInteger(cents)) return "";
    return (cents / 100).toFixed(2);
  }

  function centsFromDollars(value) {
    const trimmed = String(value || "").trim();
    if (!trimmed) return null;
    const dollars = Number(trimmed);
    if (!Number.isFinite(dollars) || dollars < 0) return null;
    return Math.round(dollars * 100);
  }

  function iconKey(symbol) {
    const value = String(symbol || "").toLowerCase();
    if (value.includes("house")) return "house";
    if (value.includes("building")) return "building";
    if (value.includes("door")) return "door";
    if (value.includes("archive") || value.includes("shipping") || value.includes("cube")) return "box";
    if (value.includes("cabinet")) return "cabinet";
    if (value.includes("books")) return "books";
    if (value.includes("rectangle.split")) return "drawer";
    if (value.includes("refrigerator")) return "fridge";
    if (value.includes("desktop") || value.includes("laptop") || value.includes("display")) return "computer";
    if (value.includes("bag") || value.includes("suitcase") || value.includes("backpack")) return "bag";
    if (value.includes("doc")) return "doc";
    if (value.includes("photo") || value.includes("camera")) return "photo";
    if (value.includes("tag")) return "tag";
    if (value.includes("heart") || value.includes("cross") || value.includes("pill")) return "heart";
    if (value.includes("car") || value.includes("truck")) return "car";
    if (value.includes("wrench") || value.includes("hammer") || value.includes("screwdriver")) return "tool";
    if (value.includes("cloud")) return "cloud";
    if (value.includes("apple")) return "apple";
    if (value.includes("person")) return "person";
    if (value.includes("trash")) return "trash";
    if (value.includes("star")) return "star";
    if (value.includes("flag")) return "flag";
    return value in ICON_PATHS ? value : "circle";
  }

  function svgIcon(symbol, className = "") {
    const key = iconKey(symbol);
    const body = ICON_PATHS[key] || ICON_PATHS.circle;
    const klass = className ? ` ${escapeAttr(className)}` : "";
    return `<svg class="svg-icon${klass}" viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
  }

  function googleMark() {
    return `
      <svg class="google-mark" viewBox="0 0 18 18" aria-hidden="true">
        <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84c-.21 1.13-.84 2.08-1.79 2.72v2.26h2.9c1.7-1.57 2.69-3.87 2.69-6.62z"/>
        <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.9-2.26c-.8.54-1.83.86-3.06.86-2.35 0-4.34-1.59-5.05-3.72H.96v2.33A9 9 0 0 0 9 18z"/>
        <path fill="#FBBC05" d="M3.95 10.7A5.41 5.41 0 0 1 3.67 9c0-.59.1-1.16.28-1.7V4.97H.96A9 9 0 0 0 0 9c0 1.45.35 2.82.96 4.03l2.99-2.33z"/>
        <path fill="#EA4335" d="M9 3.58c1.32 0 2.51.45 3.44 1.35l2.58-2.58C13.46.9 11.43 0 9 0A9 9 0 0 0 .96 4.97L3.95 7.3C4.66 5.17 6.65 3.58 9 3.58z"/>
      </svg>
    `;
  }

  function defaultLocationIcon(location) {
    if (location.type === "floor") return "building.2";
    if (location.type === "room") return "door.left.hand.closed";

    const lower = location.name.toLowerCase();
    if (lower.includes("drawer")) return "rectangle.split.3x1.fill";
    if (lower.includes("shelf") || lower.includes("bookcase")) return "books.vertical.fill";
    if (lower.includes("box") || lower.includes("bin")) return "shippingbox.fill";
    if (lower.includes("closet") || lower.includes("cabinet")) return "cabinet.fill";
    if (lower.includes("fridge") || lower.includes("freezer")) return "refrigerator.fill";
    if (lower.includes("desk")) return "desktopcomputer";
    if (lower.includes("bag") || lower.includes("backpack")) return "bag.fill";
    return "shippingbox.fill";
  }

  function allIconOptions() {
    return ICON_SECTIONS.flatMap((section) => section.icons.map(([name, label]) => ({ ...section, name, label })));
  }

  function render(options = {}) {
    const active = document.activeElement;
    const activeId = active && active.id;
    const selectionStart = active && "selectionStart" in active ? active.selectionStart : null;
    const selectionEnd = active && "selectionEnd" in active ? active.selectionEnd : null;
    const sheetBody = document.querySelector(".sheet-body");
    const sheetScrollTop = options.preserveSheetScroll === false ? null : sheetBody?.scrollTop ?? null;

    app.innerHTML = renderApp();

    if (sheetScrollTop !== null) {
      const nextSheetBody = document.querySelector(".sheet-body");
      if (nextSheetBody) nextSheetBody.scrollTop = sheetScrollTop;
    }

    if (activeId) {
      const nextActive = document.getElementById(activeId);
      if (nextActive) {
        nextActive.focus();
        if (selectionStart !== null && "setSelectionRange" in nextActive) {
          nextActive.setSelectionRange(selectionStart, selectionEnd);
        }
      }
    }

    const addInput = document.querySelector("[data-add-input]");
    if (addInput && activeId !== "search-input") {
      addInput.focus();
    }

    if (options.focusSelector) {
      const nextFocus = document.querySelector(options.focusSelector);
      if (nextFocus) nextFocus.focus({ preventScroll: true });
    }

    requestAnimationFrame(updateBreadcrumb);
    requestAnimationFrame(renderProviderSignInButtons);
  }

  function renderApp() {
    if (!hasAuthSession()) {
      if (state.pendingItemLink) {
        return renderSharedItemFallback();
      }
      return renderSignedOutApp();
    }

    const homes = filteredHomes();
    const isFiltering = state.search.trim().length > 0 || state.flaggedOnly;
    return `
      <div class="mobile-shell ${state.selectionMode ? "has-selection-bar" : ""}">
        <header class="top-bar">
          <div class="nav-row">
            <button type="button" class="nav-selection-button" data-action="${state.selectionMode ? "end-selection" : "start-selection"}" ${!state.selectionMode && !hasSelectableItems() ? "disabled" : ""}>
              ${state.selectionMode ? "Done" : "Select"}
            </button>
            <div class="nav-title">
              <img src="${APP_ICON_URL}" width="28" height="28" alt="">
              <span>CubbyLog</span>
            </div>
            <button type="button" class="icon-button avatar-button" data-action="open-account" aria-label="Account">
              ${renderAvatar()}
            </button>
          </div>
          <div class="search-controls">
            <div class="search-wrap">
              ${svgIcon("search")}
              <input id="search-input" class="search-input" type="search" autocomplete="off" placeholder="Search stuff..." value="${escapeAttr(state.search)}">
            </div>
            <button type="button" class="flag-filter ${state.flaggedOnly ? "is-active" : ""}" data-action="toggle-flag-filter" aria-pressed="${state.flaggedOnly ? "true" : "false"}" aria-label="${state.flaggedOnly ? "Showing flagged items" : "Show flagged items"}">
              ${svgIcon(state.flaggedOnly ? "flag.fill" : "flag")}
            </button>
          </div>
        </header>
        <div id="breadcrumb" class="breadcrumb is-hidden" aria-hidden="true"></div>
        <main class="content">
          ${
            state.isLoading
              ? renderLoading()
              : homes.length
                ? `<div class="home-list">${homes.map((home) => renderHome(home, isFiltering)).join("")}</div>`
                : isFiltering
                  ? renderNoResults()
                  : renderEmptyState()
          }
          ${!state.isLoading && !isFiltering ? renderAddHomeArea() : ""}
        </main>
        ${renderSheet()}
        ${renderPhotoPreviewModal()}
        ${state.selectionMode ? renderSelectionBar() : ""}
        ${state.toast ? `<div class="toast" role="status">${escapeHtml(state.toast)}</div>` : ""}
      </div>
    `;
  }

  function renderSharedItemFallback() {
    return `
      <div class="marketing-page shared-link-page">
        <header class="marketing-nav">
          <a class="marketing-brand" href="/" aria-label="CubbyLog home">
            <img src="${APP_ICON_URL}" width="34" height="34" alt="">
            <span>CubbyLog</span>
          </a>
          <button type="button" class="marketing-sign-in" data-action="open-account">Sign in</button>
        </header>
        <main class="shared-link-main">
          <section class="shared-link-panel">
            <img class="shared-link-icon" src="${APP_ICON_URL}" width="76" height="76" alt="">
            <p class="marketing-kicker">Shared item</p>
            <h1>Open this shared item in CubbyLog</h1>
            <p class="shared-link-copy">Sign in with an account that can access this home, or open the link again from the iOS app.</p>
            <div class="shared-link-actions">
              ${state.appStoreUrl ? `<a class="marketing-secondary" href="${escapeAttr(state.appStoreUrl)}" target="_blank" rel="noreferrer">Get iOS App</a>` : ""}
              <button type="button" class="marketing-primary button-reset" data-action="open-account">Sign in on Web</button>
            </div>
            <div class="shared-link-auth">
              ${state.authConfigLoaded ? renderAuthControls() : `<div class="auth-unavailable">Loading sign-in providers...</div>`}
            </div>
          </section>
        </main>
        ${renderSheet()}
        ${state.toast ? `<div class="toast" role="status">${escapeHtml(state.toast)}</div>` : ""}
      </div>
    `;
  }

  function renderSignedOutApp() {
    return `
      <div class="marketing-page">
        <header class="marketing-nav">
          <a class="marketing-brand" href="#top" aria-label="CubbyLog home">
            <img src="${APP_ICON_URL}" width="34" height="34" alt="">
            <span>CubbyLog</span>
          </a>
          <nav class="marketing-links" aria-label="Landing page">
            <a href="#features">Features</a>
            <a href="#details">Details</a>
            <a href="#access">Access</a>
          </nav>
          <button type="button" class="marketing-sign-in" data-action="open-account">Sign in</button>
        </header>
        <main id="top" class="marketing-main">
          <section class="marketing-hero">
            <div class="marketing-hero-copy">
              <p class="marketing-kicker">A gentle home for the things you keep</p>
              <h1>CubbyLog</h1>
              <p class="marketing-lede">Remember where the spare keys, school forms, warranties, and borrowed chargers live. CubbyLog turns your home into a friendly map, one shelf and cubby at a time.</p>
              <div class="marketing-actions">
                <button type="button" class="marketing-primary" data-action="open-account">Start your CubbyLog</button>
                <a class="marketing-secondary" href="#features">See how it works</a>
              </div>
              <dl class="marketing-proof">
                <div>
                  <dt>Places</dt>
                  <dd>Rooms, shelves, bins</dd>
                </div>
                <div>
                  <dt>Details</dt>
                  <dd>Photos and notes</dd>
                </div>
                <div>
                  <dt>Confidence</dt>
                  <dd>Warranties and serials</dd>
                </div>
              </dl>
            </div>
          </section>
          ${renderMarketingFeatures()}
          ${renderMarketingDetails()}
          ${renderMarketingAccess()}
        </main>
        ${renderSheet()}
        ${state.toast ? `<div class="toast" role="status">${escapeHtml(state.toast)}</div>` : ""}
      </div>
    `;
  }

  function renderMarketingFeatures() {
    const features = [
      ["cabinet.fill", "Name the places you actually use", "Kitchen drawer, blue bin, guest closet, garage shelf: your inventory can use the words you would actually say."],
      ["search", "Find it by the clue you remember", "Search notes, rooms, labels, serial numbers, model numbers, and odd details when you only have part of the answer."],
      ["heart.fill", "Keep the little context", "Photos, receipts, manuals, warranty dates, values, and notes stay tucked beside the item they describe."],
      ["share", "Give the household the same map", "Share a home so family or housemates can find things and keep the map current together."],
    ];
    return `
      <section id="features" class="marketing-section">
        <div class="marketing-section-heading">
          <p>Made for real-life storage</p>
          <h2>Your home is not a spreadsheet. CubbyLog keeps the room, shelf, bin, and item together.</h2>
        </div>
        <div class="marketing-feature-grid">
          ${features.map(([icon, title, copy]) => `
            <article class="marketing-feature-card">
              <span class="marketing-feature-icon">${svgIcon(icon)}</span>
              <h3>${escapeHtml(title)}</h3>
              <p>${escapeHtml(copy)}</p>
            </article>
          `).join("")}
        </div>
      </section>
    `;
  }

  function renderMarketingDetails() {
    return `
      <section id="details" class="marketing-section marketing-detail-band">
        <div class="marketing-section-heading">
          <p>Small details, kept kindly</p>
          <h2>The things you save should be as easy to find as the things themselves.</h2>
        </div>
        <div class="marketing-detail-list">
          <div class="marketing-detail-row">
            ${svgIcon("tag")}
            <div>
              <h3>Custom notes for the odd little details</h3>
              <p>Add whatever future you will be grateful for, from filter size to paint color to access code.</p>
            </div>
          </div>
          <div class="marketing-detail-row">
            ${svgIcon("doc")}
            <div>
              <h3>Receipts and manuals where they belong</h3>
              <p>Keep paperwork with the item it belongs to, right where everyone will look first.</p>
            </div>
          </div>
          <div class="marketing-detail-row">
            ${svgIcon("cloud")}
            <div>
              <h3>Your map follows you</h3>
              <p>Sign in once and keep the same cozy map available from the web and the app.</p>
            </div>
          </div>
        </div>
      </section>
    `;
  }

  function renderMarketingAccess() {
    return `
      <section id="access" class="marketing-section marketing-access">
        <div class="marketing-section-heading">
          <p>Start small</p>
          <h2>Add one closet today, then let the rest of the house catch up over time.</h2>
        </div>
        <div class="marketing-access-actions">
          <button type="button" class="marketing-primary" data-action="open-account">Sign in or create account</button>
        </div>
      </section>
    `;
  }

  function renderAccountRequired() {
    return `
      <section class="empty-state auth-required">
        <div class="empty-panel">
          <img src="${APP_ICON_URL}" alt="">
          <h2>Bring your CubbyLog to the web</h2>
          <p>Sign in to see the same homes, rooms, and cubbies you keep on your phone.</p>
          <div class="auth-actions">
            ${renderAuthControls()}
          </div>
        </div>
      </section>
    `;
  }

  function renderAuthControls() {
    if (!state.authConfigLoaded) {
      return `<div class="auth-unavailable">Loading sign-in options...</div>`;
    }

    const controls = [];
    if (state.googleClientId) {
      controls.push(`
        <div class="provider-button-host provider-google-host" data-google-sign-in-host>
          <div class="provider-google-facade" aria-hidden="true">
            ${googleMark()}
            <span>Sign in with Google</span>
          </div>
          <div class="provider-google-click-target" data-google-click-target></div>
        </div>
      `);
    }
    if (state.appleClientId) {
      controls.push(`<button type="button" class="row-button provider-apple" data-action="apple-sign-in">${svgIcon("apple", "provider-icon")}<span>Sign in with Apple</span></button>`);
    }
    if (isLocalHost() && !state.googleClientId && !state.appleClientId) {
      controls.push(`<button type="button" class="row-button" data-action="dev-sign-in">${svgIcon("person")} Dev Sign In</button>`);
    }
    if (!controls.length) {
      controls.push(`
        <div class="auth-unavailable">
          Google and Apple sign-in are not connected on the web yet.
          ${state.appStoreUrl ? `<a class="auth-fallback-link" href="${escapeAttr(state.appStoreUrl)}" target="_blank" rel="noreferrer">Get the iOS app</a>` : ""}
        </div>
      `);
    }
    return controls.join("");
  }

  function renderAvatar() {
    if (state.user && state.user.avatarUrl) {
      return `<img class="avatar-image" src="${escapeAttr(state.user.avatarUrl)}" alt="">`;
    }
    return svgIcon("person");
  }

  function renderSelectionBar() {
    const count = selectionCount();
    const label = count === 1 ? "1 item selected" : count ? `${count} items selected` : "Select items";
    const home = selectedHome();
    const disabled = count ? "" : "disabled";
    return `
      <div class="selection-action-bar" role="toolbar" aria-label="Selection actions">
        <div class="selection-summary">
          <strong>${escapeHtml(label)}</strong>
          <span>${escapeHtml(home?.name || "Choose items in one home")}</span>
        </div>
        <div class="selection-actions">
          <button type="button" class="selection-action" data-action="open-selection-move" ${disabled} aria-label="Move selected items">
            ${svgIcon("drawer")}<span>Move</span>
          </button>
          <button type="button" class="selection-action" data-action="set-selected-flagged" data-flagged="true" ${disabled} aria-label="Flag selected items">
            ${svgIcon("flag")}<span>Flag</span>
          </button>
          <button type="button" class="selection-action" data-action="set-selected-flagged" data-flagged="false" ${disabled} aria-label="Remove flags from selected items">
            ${svgIcon("x")}<span>Unflag</span>
          </button>
          <button type="button" class="selection-action danger" data-action="open-bulk-delete" ${disabled} aria-label="Delete selected items">
            ${svgIcon("trash")}<span>Delete</span>
          </button>
        </div>
      </div>
    `;
  }

  function renderLoading() {
    return `<div class="loading-state"><div class="spinner" aria-label="Loading"></div></div>`;
  }

  function renderNoResults() {
    const query = state.search.trim();
    const icon = state.flaggedOnly ? "flag" : "search";
    const title = state.flaggedOnly ? "No flagged items" : "No results";
    const copy = state.flaggedOnly && query
      ? "No flagged items match this search."
      : state.flaggedOnly
        ? "Flag items to keep them close at hand."
        : "Try another item, room, property, or note.";
    return `
      <div class="no-results">
        <div class="empty-panel">
          ${svgIcon(icon)}
          <h2>${escapeHtml(title)}</h2>
          <p>${escapeHtml(copy)}</p>
        </div>
      </div>
    `;
  }

  function renderEmptyState() {
    return `
      <div class="empty-state">
        <div class="empty-panel">
          <img src="${APP_ICON_URL}" alt="">
          <h2>Welcome to CubbyLog</h2>
          <p>Add one home to start building your friendly map of rooms, shelves, bins, and the things tucked inside.</p>
          <button type="button" class="primary-button" data-action="start-add" data-add-kind="home">
            ${svgIcon("plus")} Create Your First Home
          </button>
        </div>
      </div>
    `;
  }

  function renderAddHomeArea() {
    if (state.adding && state.adding.kind === "home") {
      return renderInlineAdd("Home name");
    }
    return `
      <button type="button" class="page-command" data-action="start-add" data-add-kind="home">
        ${svgIcon("plus")} <span>Add home</span>
      </button>
    `;
  }

  function renderHome(home, isSearchActive) {
    const key = nodeKey("home", home.id);
    const collapsed = !isSearchActive && state.collapsed.has(key);
    const summary = collapsed ? collapsedSummary(home.locations.length, home.items.length, "location", "locations") : "";
    const children = topLevelLocations(home).map((location) => renderLocation(home, location, isSearchActive)).join("");
    const items = renderItemFlow(home, null);
    return `
      <section class="tree-card home-card" data-path="${escapeAttr(home.name)}">
        ${renderNodeHeader({
          key,
          title: home.name,
          icon: home.icon || "house.fill",
          summary,
          kind: "home",
          homeId: home.id,
          collapsed,
        })}
        ${collapsed ? "" : `
          <div class="node-divider"></div>
          ${children}
          ${items}
          ${renderScopedAdd("location", home.id, null, "floor", "Floor name")}
          ${renderScopedAdd("location", home.id, null, "room", "Room name")}
          ${renderScopedAdd("item", home.id, null, null, "Item name")}
          <div class="card-bottom"></div>
        `}
      </section>
    `;
  }

  function renderLocation(home, location, isSearchActive) {
    const key = nodeKey("location", location.id);
    const collapsed = !isSearchActive && state.collapsed.has(key);
    const descendants = descendantCount(home, location.id);
    const noun = location.type === "floor" ? ["location", "locations"] : ["container", "containers"];
    const summary = collapsed ? collapsedSummary(descendants.locations, descendants.items, noun[0], noun[1]) : "";
    const className = location.type === "floor" ? "floor-card" : location.type === "room" ? "room-card" : "container-card";
    const children = childLocations(home, location.id).map((child) => renderLocation(home, child, isSearchActive)).join("");
    const path = locationPath(home, location).join(" / ");
    const addLocationType = location.type === "floor" ? "room" : "container";
    const addLocationLabel = location.type === "floor" ? "Room name" : "Container name";

    return `
      <section class="tree-card ${className}" data-path="${escapeAttr(path)}">
        ${renderNodeHeader({
          key,
          title: location.name,
          icon: location.icon || defaultLocationIcon(location),
          summary,
          kind: "location",
          homeId: home.id,
          locationId: location.id,
          collapsed,
        })}
        ${collapsed ? "" : `
          ${location.type !== "container" ? '<div class="node-divider"></div>' : ""}
          ${children}
          ${renderItemFlow(home, location.id)}
          ${renderScopedAdd("location", home.id, location.id, addLocationType, addLocationLabel)}
          ${renderScopedAdd("item", home.id, location.id, null, "Item name")}
          <div class="card-bottom"></div>
        `}
      </section>
    `;
  }

  function renderNodeHeader({ key, title, icon, summary, kind, homeId, locationId, collapsed }) {
    const actionMenuOpen = actionMenuMatches(kind, homeId, locationId || null);
    return `
      <div class="node-header">
        <button type="button" class="collapse-button ${collapsed ? "is-collapsed" : ""}" data-action="toggle-collapse" data-node-key="${escapeAttr(key)}" aria-label="${collapsed ? "Expand" : "Collapse"} ${escapeAttr(title)}">
          ${svgIcon("chevron")}
        </button>
        <div class="node-title">
          <span class="symbol">${svgIcon(icon)}</span>
          <span class="node-title-text">${escapeHtml(title)}</span>
        </div>
        <div class="summary">${escapeHtml(summary)}</div>
        <button type="button" class="menu-button ${actionMenuOpen ? "is-open" : ""}" data-action="open-actions" data-kind="${escapeAttr(kind)}" data-home-id="${escapeAttr(homeId)}" ${locationId ? `data-location-id="${escapeAttr(locationId)}"` : ""} aria-label="Actions for ${escapeAttr(title)}" aria-expanded="${actionMenuOpen ? "true" : "false"}">
          ${svgIcon("ellipsis")}
        </button>
      </div>
      ${actionMenuOpen ? renderInlineActionMenu() : ""}
    `;
  }

  function actionMenuMatches(kind, homeId, locationId) {
    const menu = state.actionMenu;
    if (!menu) return false;
    return menu.kind === kind && menu.homeId === homeId && (menu.locationId || null) === (locationId || null);
  }

  function renderInlineActionMenu() {
    const target = targetForActionTarget(state.actionMenu);
    if (!target) return "";
    return `
      <div class="inline-action-menu" data-action-menu role="menu" aria-label="Actions for ${escapeAttr(targetTitle(target))}">
        ${actionRowsForTarget(state.actionMenu, "inline-action").join("")}
      </div>
    `;
  }

  function renderItemFlow(home, locationId) {
    const items = itemsIn(home, locationId);
    return `
      <div class="item-flow" data-drop-zone data-home-id="${escapeAttr(home.id)}" data-location-id="${escapeAttr(locationId || "")}">
        ${items.map((item, index) => renderItemChip(home, item, index)).join("")}
        <button type="button" class="add-chip" data-action="start-add" data-add-kind="item" data-home-id="${escapeAttr(home.id)}" data-parent-id="${escapeAttr(locationId || "")}">
          ${svgIcon("plus")} <span>Add item</span>
        </button>
      </div>
    `;
  }

  function renderItemChip(home, item, index) {
    const highlighted = state.highlightedItemId === item.id;
    const selected = isItemSelected(home.id, item.id);
    const locked = state.selectionMode && state.selectedHomeId && state.selectedHomeId !== home.id;
    const photoUrl = firstPhotoUrl(item);
    const chipClasses = [
      "item-chip",
      highlighted ? "is-deep-linked" : "",
      state.selectionMode ? "is-selection-mode" : "",
      selected ? "is-selected" : "",
      locked ? "is-selection-locked" : "",
    ].filter(Boolean).join(" ");
    const action = state.selectionMode ? "toggle-item-selection" : "open-item";
    const draggable = !state.selectionMode || selected;
    const selectionLabel = selected ? "Deselect" : "Select";
    return `
      <span class="${chipClasses}" draggable="${draggable ? "true" : "false"}" data-draggable-item data-home-id="${escapeAttr(home.id)}" data-location-id="${escapeAttr(item.locationId || "")}" data-item-id="${escapeAttr(item.id)}" data-item-index="${escapeAttr(index)}">
        ${photoUrl ? renderPhotoThumbnailButton(photoUrl, `${item.name} photo`, "item-chip-photo") : ""}
        <button type="button" class="item-chip-main" data-action="${action}" data-home-id="${escapeAttr(home.id)}" data-location-id="${escapeAttr(item.locationId || "")}" data-item-id="${escapeAttr(item.id)}" ${state.selectionMode ? `aria-pressed="${selected ? "true" : "false"}"` : ""} aria-label="${state.selectionMode ? `${selectionLabel} ${escapeAttr(item.name)}` : `${escapeAttr(item.name)}. Drag to move.`}">
          ${state.selectionMode ? `<span class="selection-check" aria-hidden="true">${selected ? svgIcon("check") : ""}</span>` : ""}
          ${svgIcon(item.icon || "circle.fill")}
          <span class="item-name">${escapeHtml(item.name)}</span>
          ${item.isFlagged ? `<span class="item-flag" aria-label="Flagged">${svgIcon("flag.fill")}</span>` : ""}
          ${item.quantity > 1 ? `<span class="quantity">x${escapeHtml(item.quantity)}</span>` : ""}
        </button>
      </span>
    `;
  }

  function firstPhotoUrl(item) {
    return Array.isArray(item.photoUrls) && item.photoUrls.length ? item.photoUrls[0] : "";
  }

  function renderPhotoThumbnailButton(url, title, className = "") {
    return `
      <button type="button" class="photo-thumbnail-button ${escapeAttr(className)}" data-action="open-photo-preview" data-photo-url="${escapeAttr(url)}" data-photo-title="${escapeAttr(title)}" aria-label="Open ${escapeAttr(title)}">
        <img src="${escapeAttr(url)}" alt="${escapeAttr(title)}" loading="lazy">
      </button>
    `;
  }

  function renderScopedAdd(kind, homeId, parentId, locationType, placeholder) {
    if (!state.adding || state.adding.kind !== kind || state.adding.homeId !== homeId) return "";
    const addingParent = state.adding.parentId || null;
    if (addingParent !== (parentId || null)) return "";
    if (kind === "location" && state.adding.locationType !== locationType) return "";
    return renderInlineAdd(placeholder);
  }

  function renderInlineAdd(placeholder) {
    return `
      <form class="inline-add" data-form="commit-add">
        <input data-add-input name="name" placeholder="${escapeAttr(placeholder)}" autocomplete="off">
        <button type="submit" class="inline-icon commit" aria-label="Save">${svgIcon("check")}</button>
        <button type="button" class="inline-icon" data-action="cancel-add" aria-label="Cancel">${svgIcon("x")}</button>
      </form>
    `;
  }

  function renderSheet() {
    if (!state.sheet) return "";
    if (state.sheet.type === "account") return renderAccountSheet();
    if (state.sheet.type === "rename") return renderRenameSheet();
    if (state.sheet.type === "iconPicker") return renderIconPickerSheet();
    if (state.sheet.type === "delete") return renderDeleteSheet();
    if (state.sheet.type === "bulkDelete") return renderBulkDeleteSheet();
    if (state.sheet.type === "itemEditor") return renderItemEditorSheet();
    if (state.sheet.type === "locationPicker") return renderLocationPickerSheet();
    if (state.sheet.type === "selectionMove") return renderSelectionMoveSheet();
    return "";
  }

  function renderPhotoPreviewModal() {
    if (!state.photoPreview?.url) return "";
    const title = state.photoPreview.title || "Photo";
    return `
      <div class="photo-modal-backdrop">
        <section class="photo-modal" role="dialog" aria-modal="true" aria-label="${escapeAttr(title)}">
          <header class="photo-modal-header">
            <div class="photo-modal-title">${escapeHtml(title)}</div>
            <button type="button" class="photo-modal-close" data-action="close-photo-preview" aria-label="Close photo preview">${svgIcon("x")}</button>
          </header>
          <div class="photo-modal-image-wrap">
            <img src="${escapeAttr(state.photoPreview.url)}" alt="${escapeAttr(title)}">
          </div>
        </section>
      </div>
    `;
  }

  function sheetChrome(title, body, options = {}) {
    const save = options.saveFormId
      ? `<button type="submit" form="${escapeAttr(options.saveFormId)}" class="sheet-save" ${state.isUploadingAttachment ? "disabled" : ""}>${escapeHtml(options.saveLabel || "Save")}</button>`
      : `<span></span>`;
    const closeAction = options.closeAction || "close-sheet";
    return `
      <div class="sheet-backdrop">
        <section class="sheet${options.sheetClass ? ` ${escapeAttr(options.sheetClass)}` : ""}" role="dialog" aria-modal="true" aria-label="${escapeAttr(title)}">
          <header class="sheet-header">
            <button type="button" class="sheet-close" data-action="${escapeAttr(closeAction)}">${escapeHtml(options.closeLabel || "Done")}</button>
            <div class="sheet-title">${escapeHtml(title)}</div>
            ${save}
          </header>
          <div class="sheet-body">${body}</div>
        </section>
      </div>
    `;
  }

  function renderAccountSheet() {
    const connected = hasAuthSession();
    if (!connected) {
      const body = `
        <section class="sign-in-panel">
          <img src="${APP_ICON_URL}" width="76" height="76" alt="">
          <h2>Welcome to CubbyLog</h2>
          <p>Sign in with Google or Apple to create your account and keep your home map in sync.</p>
          <div class="auth-actions">
            ${renderAuthControls()}
          </div>
        </section>
      `;
      return sheetChrome("Sign in", body, { closeLabel: "Close", sheetClass: "sheet-auth" });
    }

    const userName = state.user ? state.user.name : "Not signed in";
    const userEmail = state.user ? state.user.email : "Not signed in";
    const body = `
      <section class="form-section">
        <div class="form-list">
          <div class="account-card">
            <div class="account-avatar">${state.user && state.user.avatarUrl ? `<img class="avatar-image" src="${escapeAttr(state.user.avatarUrl)}" alt="">` : svgIcon(connected ? "person" : "cloud")}</div>
            <div class="account-meta">
              <div class="account-name">${escapeHtml(userName)}</div>
              <div class="account-email">${escapeHtml(userEmail)}</div>
            </div>
          </div>
        </div>
      </section>
      ${connected ? renderSubscriptionSection() : ""}
      ${connected ? renderSyncSection() : ""}
      ${canManageApiSettings() ? renderApiSettingsSection() : ""}
      <section class="form-section">
        <h2 class="section-title">Account</h2>
        <div class="form-list">
          ${connected ? `<button type="button" class="row-button danger" data-action="logout-all">${svgIcon("x")} Sign Out Everywhere</button>` : ""}
          ${connected ? `<button type="button" class="row-button danger" data-action="sign-out">${svgIcon("x")} Sign Out</button>` : ""}
        </div>
      </section>
      <p class="footnote">Version web.</p>
    `;
    return sheetChrome("Account", body);
  }

  function renderSyncSection() {
    return `
      <section class="form-section">
        <h2 class="section-title">Sync</h2>
        <div class="form-list">
          <button type="button" class="row-button" data-action="reload-server">${svgIcon("refresh")} Reload Server Data</button>
        </div>
      </section>
    `;
  }

  function renderApiSettingsSection() {
    return `
      <form class="form-section" data-form="account-settings">
        <h2 class="section-title">Backend</h2>
        <div class="form-list">
          <label class="form-row">
            <span>API URL</span>
            <input name="apiBaseUrl" value="${escapeAttr(state.apiBaseUrl)}" inputmode="url" autocomplete="url">
          </label>
          <button type="submit" class="row-button">${svgIcon("check")} Save API URL</button>
        </div>
      </form>
    `;
  }

  function canManageApiSettings() {
    return Boolean(state.accountPlan?.isAdmin || state.accountPlan?.is_admin);
  }

  function renderSubscriptionSection() {
    const plan = state.accountPlan;
    if (!plan) {
      return `
        <section class="form-section">
          <h2 class="section-title">Subscription</h2>
          <div class="form-list">
            <div class="form-row"><span>Plan</span><strong>Loading...</strong></div>
          </div>
        </section>
      `;
    }

    const paid = Boolean(plan.isPaid);
    const source = plan.entitlement?.source ? plan.entitlement.source.replaceAll("_", " ") : "";
    return `
      <section class="form-section">
        <h2 class="section-title">Subscription</h2>
        <div class="form-list">
          <div class="form-row"><span>Plan</span><strong>${paid ? "Paid" : "Free"}</strong></div>
          ${paid && source ? `<div class="form-row"><span>Source</span><strong>${escapeHtml(titleCase(source))}</strong></div>` : ""}
          ${!paid ? renderQuotaRow("Containers + Items", plan.usage.totalContainersAndItems, plan.limits.totalContainersAndItems) : ""}
          ${!paid ? renderQuotaRow("Images", plan.usage.images, plan.limits.images) : ""}
          ${!paid ? renderQuotaRow("Documents", plan.usage.documents, plan.limits.documents) : ""}
        </div>
      </section>
    `;
  }

  function renderQuotaRow(label, used, limit) {
    return `<div class="form-row"><span>${escapeHtml(label)}</span><strong>${escapeHtml(used)}/${escapeHtml(limit)}</strong></div>`;
  }

  function titleCase(value) {
    return String(value || "").replace(/\b\w/g, (match) => match.toUpperCase());
  }

  function actionRowsForTarget(actionTarget, className = "sheet-action") {
    const target = targetForActionTarget(actionTarget);
    if (!target) return [];
    const locationId = actionTarget.locationId || null;
    const base = { homeId: actionTarget.homeId, parentId: locationId || "" };
    const rows = [
      actionButton("rename-target", "pencil", "Rename", {}, false, className),
      actionButton("change-icon", "star", "Change Icon", {}, false, className),
    ];
    if (actionTarget.kind === "home") {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Floor", { ...base, addKind: "location", locationType: "floor" }, false, className));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Room", { ...base, addKind: "location", locationType: "room" }, false, className));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { ...base, addKind: "item" }, false, className));
    } else if (target.location?.type === "floor") {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Room", { ...base, addKind: "location", locationType: "room" }, false, className));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { ...base, addKind: "item" }, false, className));
      rows.push(actionButton("sort-children", "sort", "Order Rooms by Name", {}, false, className));
    } else {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Container", { ...base, addKind: "location", locationType: "container" }, false, className));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { ...base, addKind: "item" }, false, className));
      rows.push(actionButton("sort-children", "sort", "Order Containers by Name", {}, false, className));
    }
    rows.push(actionButton("open-delete", "trash", "Delete", {}, true, className));
    return rows;
  }

  function actionButton(action, icon, label, extra = {}, danger = false, className = "sheet-action") {
    const data = Object.entries(extra)
      .map(([key, value]) => `data-${toKebab(key)}="${escapeAttr(value)}"`)
      .join(" ");
    return `
      <button type="button" class="${escapeAttr(className)} ${danger ? "danger" : ""}" data-action="${escapeAttr(action)}" ${data} ${className === "inline-action" ? 'role="menuitem"' : ""}>
        ${svgIcon(icon)} <span>${escapeHtml(label)}</span>
      </button>
    `;
  }

  function renderOptionalDateRow(field, label, value) {
    const dateValue = value || "";
    return `
      <div class="form-row optional-date-row">
        <span>${escapeHtml(label)}</span>
        <div class="date-control">
          ${dateValue
            ? `<input name="${escapeAttr(field)}" type="date" value="${escapeAttr(dateValue)}">
               <button type="button" class="date-action clear" data-action="clear-item-date" data-date-field="${escapeAttr(field)}">Clear</button>`
            : `<input name="${escapeAttr(field)}" type="hidden" value="">
               <button type="button" class="date-action" data-action="add-item-date" data-date-field="${escapeAttr(field)}">Add</button>`}
        </div>
      </div>
    `;
  }

  function isItemDateField(field) {
    return field === "purchaseDate" || field === "warrantyExpiresDate";
  }

  function todayDateString() {
    const date = new Date();
    date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
    return date.toISOString().slice(0, 10);
  }

  function renderRenameSheet() {
    const target = targetForSheet();
    if (!target) return "";
    const title = target.location ? target.location.name : target.home.name;
    const body = `
      <form id="rename-form" class="form-section" data-form="rename">
        <div class="form-list">
          <label class="form-row">
            <span>Name</span>
            <input id="rename-input" name="name" value="${escapeAttr(title)}" autocomplete="off">
          </label>
        </div>
      </form>
    `;
    return sheetChrome("Rename", body, { closeLabel: "Cancel", saveFormId: "rename-form" });
  }

  function renderIconPickerSheet() {
    const search = state.iconSearch.trim().toLowerCase();
    const visible = ICON_SECTIONS.map((section) => ({
      ...section,
      icons: section.icons.filter(([name, label]) => {
        const text = `${section.title} ${name} ${label}`.toLowerCase();
        return !search || text.includes(search);
      }),
    })).filter((section) => section.icons.length);

    const currentIcon = currentTargetIcon();
    const body = `
      <div class="form-section">
        <div class="search-wrap">
          ${svgIcon("search")}
          <input id="icon-search-input" class="search-input" type="search" placeholder="Search icon names" value="${escapeAttr(state.iconSearch)}">
        </div>
      </div>
      <div class="form-section">
        <button type="button" class="icon-option ${!currentIcon ? "is-selected" : ""}" data-action="choose-icon" data-icon="">
          ${svgIcon("x")} <span>No icon</span>
        </button>
      </div>
      ${visible.map((section) => `
        <section class="form-section">
          <h2 class="section-title">${escapeHtml(section.title)}</h2>
          <div class="icon-grid">
            ${section.icons.map(([name, label]) => `
              <button type="button" class="icon-option ${currentIcon === name ? "is-selected" : ""}" data-action="choose-icon" data-icon="${escapeAttr(name)}">
                ${svgIcon(name)} <span>${escapeHtml(label)}</span>
              </button>
            `).join("")}
          </div>
        </section>
      `).join("")}
    `;
    return sheetChrome("Choose Icon", body, { closeLabel: "Cancel" });
  }

  function renderDeleteSheet() {
    const target = targetForSheet();
    const item = state.sheet.itemId ? findItem(state.sheet.homeId, state.sheet.itemId) : null;
    const title = item ? item.name : target?.location ? target.location.name : target?.home?.name || "Item";
    const body = `
      <section class="form-section">
        <div class="form-list">
          <div class="full-row">
            <strong>Delete ${escapeHtml(title)}?</strong>
            <p class="footnote">This removes the selected ${escapeHtml(item ? "item" : state.sheet.kind)} from the current data set.</p>
          </div>
          <button type="button" class="row-button danger" data-action="confirm-delete">${svgIcon("trash")} Delete</button>
        </div>
      </section>
    `;
    return sheetChrome("Confirm Delete", body, { closeLabel: "Cancel" });
  }

  function renderBulkDeleteSheet() {
    const count = selectionCount();
    const label = count === 1 ? "1 item" : `${count} items`;
    const body = `
      <section class="form-section">
        <div class="form-list">
          <div class="full-row">
            <strong>Delete ${escapeHtml(label)}?</strong>
            <p class="footnote">This removes the selected items from the current data set.</p>
          </div>
          <button type="button" class="row-button danger" data-action="confirm-bulk-delete" ${count ? "" : "disabled"}>${svgIcon("trash")} Delete</button>
        </div>
      </section>
    `;
    return sheetChrome("Confirm Delete", body, { closeLabel: "Cancel" });
  }

  function renderSelectionMoveSheet() {
    const home = selectedHome();
    const count = selectionCount();
    if (!home || !count) return "";

    const path = Array.isArray(state.sheet.path) ? state.sheet.path : [];
    const parentId = path[path.length - 1] || null;
    const parentLocation = parentId ? home.locations.find((location) => location.id === parentId) : null;
    const children = childLocations(home, parentId);
    const targetTitle = parentLocation ? parentLocation.name : home.name;
    const targetIcon = parentLocation ? parentLocation.icon || defaultLocationIcon(parentLocation) : home.icon || "house.fill";
    const body = `
      <section class="form-section">
        <div class="form-list">
          ${path.length ? `<button type="button" class="row-button" data-action="selection-location-back">${svgIcon("chevron")} Back</button>` : ""}
          <button type="button" class="row-button" data-action="move-selected-to-location" data-location-id="${escapeAttr(parentId || "")}">
            ${svgIcon(targetIcon)} <span>Move to ${escapeHtml(targetTitle)}</span>
          </button>
        </div>
      </section>
      <section class="form-section">
        <h2 class="section-title">Locations</h2>
        <div class="location-choice-list">
          ${children.length ? children.map((location) => {
            const hasChildren = childLocations(home, location.id).length > 0;
            return renderLocationChoice({
              icon: location.icon || defaultLocationIcon(location),
              title: location.name,
              subtitle: formatLocationSubtitle(location.type),
              locationId: location.id,
              selected: false,
              action: hasChildren ? "drill-selection-location" : "move-selected-to-location",
              hasChildren,
            });
          }).join("") : `<div class="full-row"><p class="footnote">No deeper locations here.</p></div>`}
        </div>
      </section>
    `;
    return sheetChrome("Move Items", body, { closeLabel: "Cancel" });
  }

  function renderItemEditorSheet() {
    const item = findItem(state.sheet.homeId, state.sheet.itemId);
    const home = findHome(state.sheet.homeId);
    if (!item || !home) return "";
    const draft = state.sheet.draft || cloneItem(item);
    const iconOptions = allIconOptions().slice(0, 10);
    const body = `
      <form id="item-editor-form" data-form="item-save" data-home-id="${escapeAttr(home.id)}" data-item-id="${escapeAttr(item.id)}">
        <input type="hidden" name="icon" value="${escapeAttr(draft.icon || "")}">
        <section class="form-section">
          <h2 class="section-title">Details</h2>
          <div class="form-list">
            <label class="form-row">
              <span>Name</span>
              <input name="name" value="${escapeAttr(draft.name)}" autocomplete="off" required>
            </label>
            <div class="full-row">
              <div class="row-label">Icon</div>
              <div class="icon-strip">
                <button type="button" class="icon-option ${!draft.icon ? "is-selected" : ""}" data-action="set-item-icon" data-icon="">
                  ${svgIcon("x")} <span>None</span>
                </button>
                ${iconOptions.map((option) => `
                  <button type="button" class="icon-option ${draft.icon === option.name ? "is-selected" : ""}" data-action="set-item-icon" data-icon="${escapeAttr(option.name)}">
                    ${svgIcon(option.name)} <span>${escapeHtml(option.label)}</span>
                  </button>
                `).join("")}
              </div>
            </div>
            <label class="form-row">
              <span>Quantity</span>
              <input name="quantity" type="number" min="1" max="9999" inputmode="numeric" value="${escapeAttr(draft.quantity || 1)}">
            </label>
            <label class="form-row">
              <span>Flagged</span>
              <input name="isFlagged" type="checkbox" ${draft.isFlagged ? "checked" : ""}>
            </label>
            ${renderOptionalDateRow("purchaseDate", "Purchase Date", draft.purchaseDate)}
            ${renderOptionalDateRow("warrantyExpiresDate", "Warranty Expires", draft.warrantyExpiresDate)}
            <label class="form-row">
              <span>Serial</span>
              <input name="serialNumber" value="${escapeAttr(draft.serialNumber || "")}" autocomplete="off">
            </label>
            <label class="form-row">
              <span>Model</span>
              <input name="modelNumber" value="${escapeAttr(draft.modelNumber || "")}" autocomplete="off">
            </label>
            <label class="form-row">
              <span>Value</span>
              <input name="estimatedValue" inputmode="decimal" value="${escapeAttr(formatDollars(draft.estimatedValueCents))}">
            </label>
            <label class="form-row notes-row">
              <span>Notes</span>
              <textarea name="notes" rows="3">${escapeHtml(draft.notes || "")}</textarea>
            </label>
          </div>
        </section>
        <section class="form-section">
          <h2 class="section-title">Location</h2>
          <div class="form-list">
            <div class="form-row location-picker-row">
              <span>Stored In</span>
              <input type="hidden" name="locationId" value="${escapeAttr(draft.locationId || "")}">
              <button type="button" class="location-select-button" data-action="open-location-picker" aria-label="Choose storage location">
                <span>${escapeHtml(selectedLocationLabel(home, draft.locationId))}</span>
                ${svgIcon("chevron")}
              </button>
            </div>
          </div>
        </section>
        <section class="form-section">
          <h2 class="section-title">Properties</h2>
          <div class="form-list">
            ${draft.properties.map((property, index) => renderPropertyRow(property, index)).join("")}
            <button type="button" class="row-button" data-action="add-property">${svgIcon("plus")} Add Property</button>
          </div>
        </section>
        ${renderPhotoSection(draft.name, draft.photoUrls)}
        ${renderDocumentSection(draft.documents)}
        <section class="form-section">
          <div class="form-list">
            <button type="button" class="row-button danger" data-action="open-delete" data-kind="item" data-home-id="${escapeAttr(home.id)}" data-item-id="${escapeAttr(item.id)}">
              ${svgIcon("trash")} Delete Item
            </button>
          </div>
        </section>
      </form>
    `;
    return sheetChrome("Edit Item", body, { closeLabel: "Cancel", saveFormId: "item-editor-form" });
  }

  function renderLocationPickerSheet() {
    const home = findHome(state.sheet.homeId);
    const item = findItem(state.sheet.homeId, state.sheet.itemId);
    if (!home || !item) return "";

    const draft = state.sheet.draft || cloneItem(item);
    const path = Array.isArray(state.sheet.path) ? state.sheet.path : [];
    const parentId = path[path.length - 1] || null;
    const parent = parentId ? home.locations.find((location) => location.id === parentId) : null;
    const children = childLocations(home, parentId);
    const title = parent ? parent.name : "Select Location";
    const selectedId = draft.locationId || null;
    const body = `
      <div class="location-picker">
        <div class="location-picker-path">${escapeHtml(locationPathLabel(home, parentId))}</div>
        <div class="location-choice-list">
          ${renderLocationChoice({
            icon: parent ? "check" : home.icon || "house.fill",
            title: parent ? "Place here" : `${home.name} (top level)`,
            subtitle: parent ? `Store in ${parent.name}` : "Store directly in this home",
            locationId: parentId,
            selected: selectedId === parentId,
            action: "choose-item-location",
          })}
          ${children.map((location) => {
            const hasChildren = childLocations(home, location.id).length > 0;
            return renderLocationChoice({
              icon: location.icon || defaultLocationIcon(location),
              title: location.name,
              subtitle: location.type,
              locationId: location.id,
              selected: selectedId === location.id,
              action: hasChildren ? "drill-location" : "choose-item-location",
              hasChildren,
            });
          }).join("")}
        </div>
      </div>
    `;
    return sheetChrome(title, body, {
      closeLabel: parent ? "Back" : "Cancel",
      closeAction: parent ? "location-picker-back" : "cancel-location-picker",
      sheetClass: "sheet-location-picker",
    });
  }

  function renderLocationChoice({ icon, title, subtitle, locationId, selected, action, hasChildren = false }) {
    return `
      <button type="button" class="location-choice ${selected ? "is-selected" : ""}" data-action="${escapeAttr(action)}" data-location-id="${escapeAttr(locationId || "")}">
        <span class="location-choice-icon">${svgIcon(icon)}</span>
        <span class="location-choice-copy">
          <span class="location-choice-title">${escapeHtml(title)}</span>
          <span class="location-choice-subtitle">${escapeHtml(formatLocationSubtitle(subtitle))}</span>
        </span>
        <span class="location-choice-trailing">
          ${selected ? svgIcon("check") : ""}
          ${hasChildren ? svgIcon("chevron") : ""}
        </span>
      </button>
    `;
  }

  function renderPropertyRow(property, index) {
    return `
      <div class="property-row" data-property-row data-property-id="${escapeAttr(property.id)}">
        <div class="property-fields">
          <input data-property-key value="${escapeAttr(property.key)}" placeholder="Key" autocomplete="off">
          <input data-property-value value="${escapeAttr(property.value)}" placeholder="Value" autocomplete="off">
        </div>
        <button type="button" class="property-delete" data-action="remove-property" data-index="${escapeAttr(index)}" aria-label="Delete property">
          ${svgIcon("trash")}
        </button>
      </div>
    `;
  }

  function renderAttachmentsSection(title, urls, icon) {
    if (!urls || !urls.length) return "";
    return `
      <section class="form-section">
        <h2 class="section-title">${escapeHtml(title)}</h2>
        <div class="form-list">
          <div class="attachment-list">
            ${urls.map((url, index) => `
              <a class="attachment-link" href="${escapeAttr(url)}" target="_blank" rel="noreferrer">
                ${svgIcon(icon)} <span>${escapeHtml(title.slice(0, -1))} ${index + 1}</span>
              </a>
            `).join("")}
          </div>
        </div>
      </section>
    `;
  }

  function renderPhotoSection(itemName, urls) {
    const photoUrls = Array.isArray(urls) ? urls : [];
    const uploadLabel = state.isUploadingAttachment ? "Uploading..." : "Add Photos";
    return `
      <section class="form-section">
        <h2 class="section-title">Photos</h2>
        <div class="form-list">
          ${photoUrls.length ? `
            <div class="photo-thumbnail-grid">
              ${photoUrls.map((url, index) => `
                <div class="photo-thumb-wrap">
                  ${renderPhotoThumbnailButton(url, `${itemName || "Item"} photo ${index + 1}`, "photo-grid-thumb")}
                  <button type="button" class="attachment-remove" data-action="remove-photo" data-index="${escapeAttr(index)}" aria-label="Remove photo">
                    ${svgIcon("x")}
                  </button>
                </div>
              `).join("")}
            </div>
          ` : ""}
          <div class="attachment-upload-row">
            <label class="attachment-upload-button ${state.isUploadingAttachment ? "is-disabled" : ""}">
              ${svgIcon("photo")} <span>${escapeHtml(uploadLabel)}</span>
              <input type="file" accept="image/*" multiple data-upload-kind="photo" ${state.isUploadingAttachment ? "disabled" : ""}>
            </label>
          </div>
        </div>
      </section>
    `;
  }

  function renderDocumentSection(documents) {
    const itemDocuments = Array.isArray(documents) ? documents : [];
    const uploadLabel = state.isUploadingAttachment ? "Uploading..." : "Upload Documents";
    return `
      <section class="form-section">
        <h2 class="section-title">Documents</h2>
        <div class="form-list">
          ${itemDocuments.length ? `
            <div class="attachment-list">
              ${itemDocuments.map((document, index) => {
                const name = document.name || `Document ${index + 1}`;
                return `
                  <div class="attachment-row">
                    <a class="attachment-link" href="${escapeAttr(document.url)}" target="_blank" rel="noreferrer">
                      ${svgIcon("doc")} <span>${escapeHtml(name)}</span>
                    </a>
                    <button type="button" class="attachment-remove" data-action="remove-document" data-index="${escapeAttr(index)}" aria-label="Remove ${escapeAttr(name)}">
                      ${svgIcon("x")}
                    </button>
                  </div>
                `;
              }).join("")}
            </div>
          ` : ""}
          <div class="attachment-upload-row">
            <label class="attachment-upload-button ${state.isUploadingAttachment ? "is-disabled" : ""}">
              ${svgIcon("doc")} <span>${escapeHtml(uploadLabel)}</span>
              <input type="file" multiple data-upload-kind="document" ${state.isUploadingAttachment ? "disabled" : ""}>
            </label>
          </div>
        </div>
      </section>
    `;
  }

  function selectedLocationLabel(home, selectedId) {
    if (!home) return "No location";
    if (!selectedId) return home.name;
    return locationPathLabel(home, selectedId) || home.name;
  }

  function locationPathLabel(home, locationId) {
    if (!home || !locationId) return home?.name || "No location";
    const path = [];
    let current = home.locations.find((location) => location.id === locationId);
    while (current) {
      path.unshift(current.name);
      current = current.parentId ? home.locations.find((location) => location.id === current.parentId) : null;
    }
    return path.length ? path.join(" › ") : home.name;
  }

  function initialLocationPickerPath(home, selectedId) {
    if (!home || !selectedId) return [];
    const ancestors = [];
    let current = home.locations.find((location) => location.id === selectedId);
    while (current) {
      ancestors.unshift(current.id);
      current = current.parentId ? home.locations.find((location) => location.id === current.parentId) : null;
    }
    ancestors.pop();
    return ancestors;
  }

  function formatLocationSubtitle(value) {
    const text = String(value || "");
    if (!text) return "";
    return text.replace(/\b\w/g, (match) => match.toUpperCase());
  }

  function filteredHomes() {
    const query = state.search.trim().toLowerCase();
    const hasQuery = query.length > 0;
    if (!hasQuery && !state.flaggedOnly) return state.homes;

    return state.homes.map((home) => {
      const homeMatches = hasQuery && home.name.toLowerCase().includes(query);
      const directMatchIds = new Set(
        home.locations
          .filter((loc) => hasQuery && loc.name.toLowerCase().includes(query))
          .map((loc) => loc.id)
      );
      const matchingLocationIds = new Set(directMatchIds);
      let toExpand = new Set(directMatchIds);
      while (toExpand.size) {
        const children = home.locations.filter((loc) => loc.parentId && toExpand.has(loc.parentId)).map((loc) => loc.id);
        toExpand = new Set(children.filter((childId) => !matchingLocationIds.has(childId)));
        toExpand.forEach((childId) => matchingLocationIds.add(childId));
      }

      const matchingItems = home.items.filter((item) => {
        if (!hasQuery) return true;
        const propertyText = item.properties.map((property) => `${property.key} ${property.value}`).join(" ");
        return [
          item.name,
          item.notes || "",
          item.serialNumber || "",
          item.modelNumber || "",
          propertyText,
        ].join(" ").toLowerCase().includes(query);
      });

      const visibleItems = home.items.filter((item) => {
        if (state.flaggedOnly && !item.isFlagged) return false;
        if (!hasQuery) return true;
        if (homeMatches) return true;
        if (matchingItems.some((match) => match.id === item.id)) return true;
        return item.locationId ? matchingLocationIds.has(item.locationId) : false;
      });

      if (state.flaggedOnly && visibleItems.length === 0) {
        return null;
      }
      if (homeMatches && !state.flaggedOnly) return home;

      if (!homeMatches && directMatchIds.size === 0 && visibleItems.length === 0) {
        return null;
      }

      const neededLocationIds = state.flaggedOnly ? new Set() : new Set(matchingLocationIds);
      visibleItems.forEach((item) => {
        if (item.locationId) neededLocationIds.add(item.locationId);
      });

      let toResolve = new Set(neededLocationIds);
      while (toResolve.size) {
        const parents = home.locations
          .filter((loc) => toResolve.has(loc.id) && loc.parentId)
          .map((loc) => loc.parentId);
        toResolve = new Set(parents.filter((parentId) => !neededLocationIds.has(parentId)));
        toResolve.forEach((parentId) => neededLocationIds.add(parentId));
      }

      return {
        ...home,
        locations: home.locations.filter((loc) => neededLocationIds.has(loc.id)),
        items: visibleItems,
      };
    }).filter(Boolean);
  }

  function topLevelLocations(home) {
    return childLocations(home, null);
  }

  function childLocations(home, parentId) {
    return home.locations
      .filter((location) => (location.parentId || null) === (parentId || null))
      .sort(sortBySortOrderThenName);
  }

  function itemsIn(home, locationId) {
    return home.items
      .filter((item) => (item.locationId || null) === (locationId || null))
      .sort(sortBySortOrderThenName);
  }

  function sortBySortOrderThenName(a, b) {
    const sortA = Number.isFinite(a.sortOrder) ? a.sortOrder : 0;
    const sortB = Number.isFinite(b.sortOrder) ? b.sortOrder : 0;
    if (sortA !== sortB) return sortA - sortB;
    return a.name.localeCompare(b.name);
  }

  function descendantCount(home, locationId) {
    const children = childLocations(home, locationId);
    let locations = children.length;
    let items = itemsIn(home, locationId).length;
    children.forEach((child) => {
      const sub = descendantCount(home, child.id);
      locations += sub.locations;
      items += sub.items;
    });
    return { locations, items };
  }

  function collapsedSummary(locationCount, itemCount, locationSingular, locationPlural) {
    const locationText = locationCount === 1 ? `1 ${locationSingular}` : `${locationCount} ${locationPlural}`;
    const itemText = itemCount === 1 ? "1 item" : `${itemCount} items`;
    if (locationCount === 0 && itemCount === 0) return "Empty";
    if (locationCount === 0) return itemText;
    if (itemCount === 0) return locationText;
    return `${locationText}, ${itemText}`;
  }

  function locationPath(home, location) {
    const ancestors = [];
    let current = location;
    while (current) {
      ancestors.unshift(current.name);
      current = current.parentId ? home.locations.find((loc) => loc.id === current.parentId) : null;
    }
    return [home.name, ...ancestors];
  }

  function nodeKey(kind, value) {
    return `${kind}:${value}`;
  }

  function findHome(homeId) {
    return state.homes.find((home) => home.id === homeId);
  }

  function findLocation(homeId, locationId) {
    return findHome(homeId)?.locations.find((location) => location.id === locationId);
  }

  function findItem(homeId, itemId) {
    return findHome(homeId)?.items.find((item) => item.id === itemId);
  }

  function findItemContext(homeId, itemId) {
    const home = findHome(homeId);
    if (!home) return null;
    const item = home.items.find((candidate) => candidate.id === itemId);
    return item ? { home, item } : null;
  }

  function cloneItem(item) {
    return JSON.parse(JSON.stringify(item));
  }

  function targetForSheet() {
    return targetForActionTarget(state.sheet);
  }

  function targetForActionTarget(actionTarget) {
    if (!actionTarget) return null;
    const home = findHome(actionTarget.homeId);
    if (!home) return null;
    const location = actionTarget.locationId ? home.locations.find((loc) => loc.id === actionTarget.locationId) : null;
    return { home, location };
  }

  function targetTitle(target) {
    return target.location ? target.location.name : target.home.name;
  }

  function currentTargetIcon() {
    const target = targetForSheet();
    if (!target) return "";
    return target.location ? target.location.icon || "" : target.home.icon || "";
  }

  function toKebab(value) {
    return value.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
  }

  async function apiRequest(method, path, body) {
    let response = await sendApiRequest(method, path, body);

    if (response.status === 401 && isRefreshableRequest(path)) {
      if (state.refreshToken && await refreshAccessToken()) {
        response = await sendApiRequest(method, path, body);
      } else {
        clearSession();
        throw new Error("Session expired. Please sign in again.");
      }
    }

    return parseApiResponse(response);
  }

  function sendApiRequest(method, path, body) {
    const headers = {
      "Content-Type": "application/json",
      ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
    };

    return fetch(`${state.apiBaseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  function isRefreshableRequest(path) {
    return ![
      "/auth/config",
      "/auth/google",
      "/auth/apple",
      "/auth/dev",
      "/auth/refresh",
    ].includes(path);
  }

  async function refreshAccessToken() {
    if (!state.refreshToken) return false;

    if (!activeTokenRefresh) {
      activeTokenRefresh = (async () => {
        const response = await fetch(`${state.apiBaseUrl}/auth/refresh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refreshToken: state.refreshToken }),
        });

        if (!response.ok) {
          const message = await apiErrorMessage(response);
          clearSession();
          throw new Error(response.status === 401 ? "Session expired. Please sign in again." : message);
        }

        applyAuthResponse(await response.json());
        return true;
      })().finally(() => {
        activeTokenRefresh = null;
      });
    }

    return activeTokenRefresh;
  }

  async function parseApiResponse(response) {
    if (!response.ok) {
      throw new Error(await apiErrorMessage(response));
    }

    if (response.status === 204) return null;
    return response.json();
  }

  async function apiErrorMessage(response) {
    let message = `HTTP ${response.status}`;
    try {
      const text = await response.text();
      if (!text.trim()) return message;
      try {
        const parsed = JSON.parse(text);
        return parsed.error || parsed.message || text.trim();
      } catch {
        return text.trim();
      }
    } catch {
      return message;
    }
  }

  async function uploadItemAttachment(homeId, kind, file) {
    if (!file || file.size <= 0) {
      throw new Error(`${file?.name || "File"} is empty`);
    }

    const contentType = uploadContentTypeForFile(kind, file);
    if (kind === "photo" && !contentType.startsWith("image/")) {
      throw new Error("Photos must use an image file type");
    }

    const upload = normalizeUploadResponse(await apiRequest("POST", `/homes/${homeId}/items/uploads`, {
      kind,
      file_name: uploadFileName(kind, file),
      content_type: contentType,
      size_bytes: file.size,
    }));

    const response = await fetch(upload.uploadUrl, {
      method: "PUT",
      headers: upload.headers,
      body: file,
    });

    if (!response.ok) {
      throw new Error(await uploadErrorMessage(response));
    }

    return upload;
  }

  function normalizeUploadResponse(upload) {
    const normalized = {
      uploadUrl: upload?.uploadUrl ?? upload?.upload_url ?? "",
      fileUrl: upload?.fileUrl ?? upload?.file_url ?? "",
      key: upload?.key ?? "",
      headers: Object.fromEntries(Object.entries(upload?.headers || {}).map(([key, value]) => [key, String(value)])),
    };
    if (!normalized.uploadUrl || !normalized.fileUrl || !normalized.key) {
      throw new Error("Upload response was missing file details");
    }
    return normalized;
  }

  function uploadFileName(kind, file) {
    const name = String(file.name || "").trim();
    return name || `${kind}-attachment`;
  }

  function uploadContentTypeForFile(kind, file) {
    if (file.type) return file.type;
    const name = String(file.name || "").toLowerCase();
    if (kind === "photo") {
      if (name.endsWith(".jpg") || name.endsWith(".jpeg")) return "image/jpeg";
      if (name.endsWith(".png")) return "image/png";
      if (name.endsWith(".heic")) return "image/heic";
      if (name.endsWith(".heif")) return "image/heif";
      if (name.endsWith(".webp")) return "image/webp";
      if (name.endsWith(".gif")) return "image/gif";
    }
    if (name.endsWith(".pdf")) return "application/pdf";
    if (name.endsWith(".zip")) return "application/zip";
    if (name.endsWith(".txt")) return "text/plain";
    if (name.endsWith(".csv")) return "text/csv";
    return "application/octet-stream";
  }

  async function uploadErrorMessage(response) {
    const fallback = `Upload failed with HTTP ${response.status}`;
    try {
      const text = await response.text();
      return text.trim() || fallback;
    } catch {
      return fallback;
    }
  }

  async function loadAuthConfig() {
    try {
      const config = await apiRequest("GET", "/auth/config");
      state.googleClientId = config.googleClientId ?? config.google_client_id ?? "";
      state.appleClientId = config.appleClientId ?? config.apple_client_id ?? "";
      state.appStoreUrl = config.iosAppStoreUrl ?? config.ios_app_store_url ?? "";
    } catch {
      state.googleClientId = "";
      state.appleClientId = "";
      state.appStoreUrl = "";
    }
    state.authConfigLoaded = true;
    render();
  }

  function renderProviderSignInButtons() {
    const containers = Array.from(document.querySelectorAll("[data-google-sign-in-host]"));
    if (!state.googleClientId || !window.google?.accounts?.id || !containers.length) return;

    window.google.accounts.id.initialize({
      client_id: state.googleClientId,
      callback: handleGoogleCredentialResponse,
    });

    containers.forEach((container) => {
      if (container.dataset.clientId === state.googleClientId) return;
      const target = container.querySelector("[data-google-click-target]") || container;
      target.innerHTML = "";
      const width = Math.round(container.getBoundingClientRect().width || container.clientWidth || 320);
      window.google.accounts.id.renderButton(target, {
        theme: "outline",
        size: "large",
        type: "standard",
        shape: "rectangular",
        text: "signin_with",
        logo_alignment: "center",
        width: Math.max(width, 240),
      });
      container.dataset.clientId = state.googleClientId;
    });
  }

  function handleGoogleCredentialResponse(response) {
    if (!response?.credential) {
      showToast("Google sign-in failed");
      render();
      return;
    }
    void runMutation(async () => {
      const auth = await apiRequest("POST", "/auth/google", { idToken: response.credential });
      applyAuthResponse(auth);
      await loadServerHomes();
      state.sheet = null;
    }, "Signed in");
  }

  async function signInWithApple() {
    if (!state.appleClientId || !window.AppleID?.auth) {
      throw new Error("Apple sign-in is not configured");
    }

    window.AppleID.auth.init({
      clientId: state.appleClientId,
      scope: "name email",
      redirectURI: window.location.origin,
      usePopup: true,
    });

    const response = await window.AppleID.auth.signIn();
    const identityToken = response?.authorization?.id_token;
    if (!identityToken) {
      throw new Error("Apple sign-in did not return an identity token");
    }

    const name = response?.user?.name || {};
    const fullName = (name.firstName || name.lastName)
      ? { givenName: name.firstName || null, familyName: name.lastName || null }
      : null;
    const auth = await apiRequest("POST", "/auth/apple", { identityToken, fullName });
    applyAuthResponse(auth);
    await loadServerHomes();
    state.sheet = null;
  }

  function applyAuthResponse(auth) {
    state.token = auth.token;
    state.refreshToken = auth.refreshToken ?? auth.refresh_token ?? state.refreshToken;
    state.user = normalizeUser(auth.user);
    persistSession();
  }

  async function loadServerHomes() {
    const [plan, homes] = await Promise.all([
      apiRequest("GET", "/account/plan"),
      apiRequest("GET", "/homes"),
    ]);
    state.accountPlan = plan;
    const details = await Promise.all(homes.map((home) => apiRequest("GET", `/homes/${home.id}`)));
    state.homes = details.map(normalizeHomeDetail);
    state.homesLoaded = true;
    pruneSelection();
    persistData();
  }

  function normalizeHomeDetail(raw) {
    return {
      id: raw.id,
      name: raw.name,
      ownerId: raw.ownerId ?? raw.owner_id ?? "",
      role: raw.role || "owner",
      icon: raw.icon || null,
      locations: (raw.locations || []).map(normalizeLocation),
      items: (raw.items || []).map(normalizeItem),
    };
  }

  function normalizeLocation(raw) {
    return {
      id: raw.id,
      homeId: raw.homeId ?? raw.home_id,
      parentId: raw.parentId ?? raw.parent_id ?? null,
      name: raw.name,
      type: raw.type,
      sortOrder: raw.sortOrder ?? raw.sort_order ?? 0,
      icon: raw.icon || null,
    };
  }

  function normalizeItem(raw) {
    return {
      id: raw.id,
      homeId: raw.homeId ?? raw.home_id,
      locationId: raw.locationId ?? raw.location_id ?? null,
      name: raw.name,
      icon: raw.icon || null,
      notes: raw.notes || "",
      quantity: raw.quantity || 1,
      properties: raw.properties || [],
      photoUrls: raw.photoUrls ?? raw.photo_urls ?? [],
      documents: (raw.documents || []).map((document) => ({
        id: document.id,
        url: document.url,
        name: document.name,
        contentType: document.contentType ?? document.content_type ?? null,
      })),
      purchaseDate: raw.purchaseDate ?? raw.purchase_date ?? null,
      serialNumber: raw.serialNumber ?? raw.serial_number ?? null,
      modelNumber: raw.modelNumber ?? raw.model_number ?? null,
      warrantyExpiresDate: raw.warrantyExpiresDate ?? raw.warranty_expires_date ?? null,
      estimatedValueCents: raw.estimatedValueCents ?? raw.estimated_value_cents ?? null,
      isFlagged: raw.isFlagged ?? raw.is_flagged ?? false,
      sortOrder: raw.sortOrder ?? raw.sort_order ?? 0,
      createdBy: raw.createdBy ?? raw.created_by ?? "",
    };
  }

  function itemPayload(item) {
    return {
      name: item.name,
      location_id: item.locationId || null,
      icon: item.icon || null,
      notes: item.notes || null,
      quantity: Math.max(1, Number(item.quantity) || 1),
      properties: item.properties
        .map((property) => ({
          id: property.id || id(),
          key: property.key.trim(),
          value: property.value.trim(),
        }))
        .filter((property) => property.key),
      photo_urls: item.photoUrls || [],
      documents: (item.documents || []).map((document) => ({
        id: document.id,
        url: document.url,
        name: document.name,
        content_type: document.contentType || null,
      })),
      purchase_date: item.purchaseDate || null,
      serial_number: item.serialNumber || null,
      model_number: item.modelNumber || null,
      warranty_expires_date: item.warrantyExpiresDate || null,
      estimated_value_cents: Number.isInteger(item.estimatedValueCents) ? item.estimatedValueCents : null,
      is_flagged: Boolean(item.isFlagged),
      sort_order: Number.isFinite(item.sortOrder) ? item.sortOrder : 0,
    };
  }

  async function runMutation(work, successMessage) {
    state.isLoading = true;
    try {
      await work();
      if (successMessage) showToast(successMessage);
    } catch (error) {
      showToast(error.message || String(error));
    } finally {
      state.isLoading = false;
      render();
      openPendingItemLink();
    }
  }

  async function createHome(name) {
    await apiRequest("POST", "/homes", { name, icon: null });
    await loadServerHomes();
  }

  async function createLocation(homeId, name, parentId, type) {
    const home = findHome(homeId);
    if (!home) return;
    const sortOrder = childLocations(home, parentId).length;
    await apiRequest("POST", `/homes/${homeId}/locations`, {
      name,
      parent_id: parentId || null,
      type,
      sort_order: sortOrder,
      icon: null,
    });
    await loadServerHomes();
  }

  async function createItem(homeId, name, locationId) {
    const home = findHome(homeId);
    if (!home) return;
    const sortOrder = itemsIn(home, locationId).length;
    const item = {
      id: id(),
      homeId,
      locationId: locationId || null,
      name,
      icon: null,
      notes: "",
      quantity: 1,
      properties: [],
      photoUrls: [],
      documents: [],
      purchaseDate: null,
      serialNumber: null,
      modelNumber: null,
      warrantyExpiresDate: null,
      estimatedValueCents: null,
      isFlagged: false,
      sortOrder,
      createdBy: state.user?.id || "local",
    };
    await apiRequest("POST", `/homes/${homeId}/items`, itemPayload(item));
    await loadServerHomes();
  }

  async function moveItem(homeId, itemId, targetLocationId, insertionIndex) {
    const home = findHome(homeId);
    const item = findItem(homeId, itemId);
    if (!home || !item) return false;

    const fromLocationId = item.locationId || null;
    const toLocationId = targetLocationId || null;
    const originalHomes = JSON.parse(JSON.stringify(state.homes));
    const updates = itemMoveUpdates(home, item, toLocationId, insertionIndex);
    if (!updates.length) return false;

    updates.forEach(({ id: updateId, locationId, sortOrder }) => {
      const candidate = home.items.find((homeItem) => homeItem.id === updateId);
      if (candidate) {
        candidate.locationId = locationId;
        candidate.sortOrder = sortOrder;
      }
    });
    persistData();
    render();

    try {
      await Promise.all(updates.map((update) => apiRequest("PATCH", `/homes/${homeId}/items/${update.id}`, {
        location_id: update.locationId,
        sort_order: update.sortOrder,
      })));
      await loadServerHomes();
      return true;
    } catch (error) {
      state.homes = originalHomes;
      persistData();
      throw error;
    } finally {
      if (fromLocationId !== toLocationId) {
        state.collapsed.delete(nodeKey("home", homeId));
        if (toLocationId) expandLocationPath(homeId, toLocationId);
        persistCollapsed();
      }
    }
  }

  async function moveItems(homeId, itemIds, targetLocationId, insertionIndex) {
    const home = findHome(homeId);
    const uniqueIds = Array.from(new Set(itemIds)).filter(Boolean);
    if (!home || !uniqueIds.length) return false;

    const selectedSet = new Set(uniqueIds);
    const originalHomes = JSON.parse(JSON.stringify(state.homes));
    const updates = itemGroupMoveUpdates(home, uniqueIds, selectedSet, targetLocationId || null, insertionIndex);
    if (!updates.length) return false;

    updates.forEach(({ id: updateId, locationId, sortOrder }) => {
      const candidate = home.items.find((homeItem) => homeItem.id === updateId);
      if (candidate) {
        candidate.locationId = locationId;
        candidate.sortOrder = sortOrder;
      }
    });
    persistData();
    render();

    try {
      await Promise.all(updates.map((update) => apiRequest("PATCH", `/homes/${homeId}/items/${update.id}`, {
        location_id: update.locationId,
        sort_order: update.sortOrder,
      })));
      await loadServerHomes();
      return true;
    } catch (error) {
      state.homes = originalHomes;
      persistData();
      throw error;
    } finally {
      state.collapsed.delete(nodeKey("home", homeId));
      if (targetLocationId) expandLocationPath(homeId, targetLocationId);
      persistCollapsed();
    }
  }

  function itemMoveUpdates(home, item, toLocationId, insertionIndex) {
    const fromLocationId = item.locationId || null;
    const movingId = item.id;
    const updates = new Map();
    const queueUpdate = (candidate, locationId, sortOrder) => {
      const nextLocationId = locationId || null;
      const nextSortOrder = sortOrder;
      if ((candidate.locationId || null) !== nextLocationId || candidate.sortOrder !== nextSortOrder) {
        updates.set(candidate.id, {
          id: candidate.id,
          locationId: nextLocationId,
          sortOrder: nextSortOrder,
        });
      }
    };

    if (fromLocationId !== toLocationId) {
      itemsIn(home, fromLocationId)
        .filter((candidate) => candidate.id !== movingId)
        .forEach((candidate, index) => queueUpdate(candidate, fromLocationId, index));
    }

    const targetItems = itemsIn(home, toLocationId);
    const sourceIndex = targetItems.findIndex((candidate) => candidate.id === movingId);
    const siblings = targetItems.filter((candidate) => candidate.id !== movingId);
    let destination = Number.isFinite(insertionIndex) ? insertionIndex : siblings.length;
    if (sourceIndex >= 0 && sourceIndex < destination) destination -= 1;
    destination = Math.min(Math.max(destination, 0), siblings.length);

    siblings.splice(destination, 0, item);
    siblings.forEach((candidate, index) => queueUpdate(candidate, toLocationId, index));

    return Array.from(updates.values());
  }

  function itemGroupMoveUpdates(home, orderedItemIds, selectedSet, toLocationId, insertionIndex) {
    const selectedItems = orderedItemIds
      .map((itemId) => home.items.find((item) => item.id === itemId))
      .filter((item) => item && selectedSet.has(item.id));
    if (!selectedItems.length) return [];

    const updates = new Map();
    const sourceLocationIds = new Set(selectedItems.map((item) => item.locationId || null));
    const impactedLocationIds = new Set([...sourceLocationIds, toLocationId || null]);
    const queueUpdate = (candidate, locationId, sortOrder) => {
      const nextLocationId = locationId || null;
      if ((candidate.locationId || null) !== nextLocationId || candidate.sortOrder !== sortOrder) {
        updates.set(candidate.id, {
          id: candidate.id,
          locationId: nextLocationId,
          sortOrder,
        });
      }
    };

    impactedLocationIds.forEach((locationId) => {
      if ((locationId || null) === (toLocationId || null)) return;
      itemsIn(home, locationId)
        .filter((item) => !selectedSet.has(item.id))
        .forEach((item, index) => queueUpdate(item, locationId, index));
    });

    const targetItems = itemsIn(home, toLocationId);
    const siblings = targetItems.filter((item) => !selectedSet.has(item.id));
    const targetIndex = Number.isFinite(insertionIndex) ? insertionIndex : targetItems.length;
    const selectedBeforeTarget = targetItems.slice(0, targetIndex).filter((item) => selectedSet.has(item.id)).length;
    const destination = Math.min(Math.max(targetIndex - selectedBeforeTarget, 0), siblings.length);
    siblings.splice(destination, 0, ...selectedItems);
    siblings.forEach((item, index) => queueUpdate(item, toLocationId || null, index));

    return Array.from(updates.values());
  }

  async function renameTarget(name) {
    const target = targetForSheet();
    if (!target) return;
    if (state.sheet.kind === "home") {
      await apiRequest("PATCH", `/homes/${target.home.id}`, { name, icon: target.home.icon || null });
      await loadServerHomes();
      return;
    }

    if (target.location) {
      await apiRequest("PATCH", `/homes/${target.home.id}/locations/${target.location.id}`, { name });
      await loadServerHomes();
    }
  }

  async function updateTargetIcon(icon) {
    const target = targetForSheet();
    if (!target) return;
    const nextIcon = icon || null;
    if (state.sheet.kind === "home") {
      await apiRequest("PATCH", `/homes/${target.home.id}`, { name: target.home.name, icon: nextIcon });
      await loadServerHomes();
      return;
    }
    if (target.location) {
      await apiRequest("PATCH", `/homes/${target.home.id}/locations/${target.location.id}`, { icon: nextIcon });
      await loadServerHomes();
    }
  }

  async function deleteTarget() {
    const sheet = state.sheet;
    if (!sheet) return;
    if (sheet.itemId) {
      await deleteItem(sheet.homeId, sheet.itemId);
      return;
    }

    const target = targetForSheet();
    if (!target) return;
    if (sheet.kind === "home") {
      await apiRequest("DELETE", `/homes/${target.home.id}`);
      await loadServerHomes();
      return;
    }

    if (target.location) {
      await apiRequest("DELETE", `/homes/${target.home.id}/locations/${target.location.id}`);
      await loadServerHomes();
    }
  }

  async function deleteItem(homeId, itemId) {
    const home = findHome(homeId);
    const item = findItem(homeId, itemId);
    if (!home || !item) return;
    await apiRequest("DELETE", `/homes/${homeId}/items/${itemId}`);
    await loadServerHomes();
  }

  async function deleteItems(homeId, itemIds) {
    const home = findHome(homeId);
    const uniqueIds = Array.from(new Set(itemIds)).filter((itemId) => findItem(homeId, itemId));
    if (!home || !uniqueIds.length) return;
    await Promise.all(uniqueIds.map((itemId) => apiRequest("DELETE", `/homes/${homeId}/items/${itemId}`)));
    await loadServerHomes();
  }

  async function setItemsFlagged(homeId, itemIds, isFlagged) {
    const home = findHome(homeId);
    const items = Array.from(new Set(itemIds))
      .map((itemId) => findItem(homeId, itemId))
      .filter(Boolean);
    if (!home || !items.length) return;

    const originalHomes = JSON.parse(JSON.stringify(state.homes));
    items.forEach((item) => {
      item.isFlagged = isFlagged;
    });
    persistData();
    render();

    try {
      await Promise.all(items.map((item) => apiRequest("PATCH", `/homes/${homeId}/items/${item.id}`, {
        is_flagged: isFlagged,
      })));
      await loadServerHomes();
    } catch (error) {
      state.homes = originalHomes;
      persistData();
      throw error;
    }
  }

  async function saveItemFromForm(form) {
    const homeId = form.dataset.homeId;
    const itemId = form.dataset.itemId;
    const home = findHome(homeId);
    const item = findItem(homeId, itemId);
    if (!home || !item) return;
    const draft = readItemDraftFromForm(form);
    const saved = {
      ...item,
      ...draft,
      properties: draft.properties
        .map((property) => ({
          id: property.id || id(),
          key: property.key.trim(),
          value: property.value.trim(),
        }))
        .filter((property) => property.key),
    };
    await apiRequest("PATCH", `/homes/${home.id}/items/${item.id}`, itemPayload(saved));
    await loadServerHomes();
  }

  function readItemDraftFromForm(form) {
    const formItem = findItem(form.dataset.homeId, form.dataset.itemId);
    return {
      name: form.elements.name.value.trim(),
      icon: form.elements.icon.value || null,
      quantity: Math.max(1, Number(form.elements.quantity.value) || 1),
      notes: form.elements.notes.value.trim(),
      locationId: form.elements.locationId.value || null,
      properties: Array.from(form.querySelectorAll("[data-property-row]")).map((row) => ({
        id: row.dataset.propertyId || id(),
        key: row.querySelector("[data-property-key]").value,
        value: row.querySelector("[data-property-value]").value,
      })),
      photoUrls: state.sheet?.draft?.photoUrls || formItem?.photoUrls || [],
      documents: state.sheet?.draft?.documents || formItem?.documents || [],
      purchaseDate: form.elements.purchaseDate.value || null,
      serialNumber: form.elements.serialNumber.value.trim() || null,
      modelNumber: form.elements.modelNumber.value.trim() || null,
      warrantyExpiresDate: form.elements.warrantyExpiresDate.value || null,
      estimatedValueCents: centsFromDollars(form.elements.estimatedValue.value),
      isFlagged: Boolean(form.elements.isFlagged.checked),
      sortOrder: formItem?.sortOrder || 0,
    };
  }

  async function sortChildrenForTarget(actionTarget = state.sheet) {
    const target = targetForActionTarget(actionTarget);
    if (!target) return;
    const parentId = target.location ? target.location.id : null;
    const sorted = childLocations(target.home, parentId).sort((a, b) => a.name.localeCompare(b.name));
    await Promise.all(sorted.map((location, index) => apiRequest("PATCH", `/homes/${target.home.id}/locations/${location.id}`, { sort_order: index })));
    await loadServerHomes();
  }

  function openPendingItemLink() {
    const link = state.pendingItemLink;
    if (!link || state.deepLinkHandled || !hasAuthSession() || !state.homesLoaded) return;

    const context = findItemContext(link.homeId, link.itemId);
    state.deepLinkHandled = true;

    if (!context) {
      showToast("Could not open that item. Sign in with an account that can access it.");
      return;
    }

    prepareHierarchyForItem(context.home, context.item);
    state.highlightedItemId = context.item.id;
    state.sheet = null;
    render();

    requestAnimationFrame(() => {
      const chip = itemChipElement(context.home.id, context.item.id);
      chip?.scrollIntoView({ block: "center", behavior: "smooth" });

      window.setTimeout(() => {
        const latestItem = findItem(context.home.id, context.item.id) || context.item;
        state.highlightedItemId = "";
        state.sheet = {
          type: "itemEditor",
          homeId: context.home.id,
          itemId: context.item.id,
          draft: cloneItem(latestItem),
        };
        render();
      }, 420);
    });
  }

  function prepareHierarchyForItem(home, item) {
    state.search = "";
    state.flaggedOnly = false;
    state.adding = null;
    state.collapsed.delete(nodeKey("home", home.id));
    expandLocationPath(home.id, item.locationId);
    persistCollapsed();
  }

  function expandLocationPath(homeId, locationId) {
    const home = findHome(homeId);
    if (!home) return;

    let currentLocationId = locationId;
    while (currentLocationId) {
      state.collapsed.delete(nodeKey("location", currentLocationId));
      const location = home.locations.find((candidate) => candidate.id === currentLocationId);
      currentLocationId = location?.parentId || null;
    }
  }

  function itemChipElement(homeId, itemId) {
    return Array.from(document.querySelectorAll(".item-chip[data-item-id]"))
      .find((element) => element.dataset.homeId === homeId && element.dataset.itemId === itemId);
  }

  function closestFromEvent(event, selector) {
    const target = event.target;
    if (target instanceof Element) return target.closest(selector);
    return target?.parentElement?.closest(selector) || null;
  }

  function handleDragStart(event) {
    const chip = closestFromEvent(event, "[data-draggable-item]");
    if (!chip || !event.dataTransfer) return;

    const homeId = chip.dataset.homeId;
    const itemId = chip.dataset.itemId;
    const itemIds = state.selectionMode && isItemSelected(homeId, itemId) ? selectedIds() : [itemId];
    state.draggingItem = {
      homeId,
      itemId,
      itemIds,
      locationId: chip.dataset.locationId || null,
    };
    state.suppressItemClick = true;
    chip.classList.add("is-dragging");
    document.body.classList.add("is-dragging-item");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", JSON.stringify(state.draggingItem));
  }

  function handleDragOver(event) {
    const dropTarget = currentItemDropTarget(event);
    if (!dropTarget) {
      clearDropTarget();
      return;
    }

    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    markDropTarget(dropTarget);
  }

  async function handleDrop(event) {
    const dropTarget = currentItemDropTarget(event);
    const draggingItem = state.draggingItem;
    clearDropTarget();
    state.draggingItem = null;
    document.body.classList.remove("is-dragging-item");

    if (!dropTarget || !draggingItem) return;
    event.preventDefault();
    await runMutation(async () => {
      const itemIds = Array.isArray(draggingItem.itemIds) && draggingItem.itemIds.length ? draggingItem.itemIds : [draggingItem.itemId];
      if (itemIds.length > 1) {
        await moveItems(draggingItem.homeId, itemIds, dropTarget.locationId, dropTarget.insertionIndex);
      } else {
        await moveItem(draggingItem.homeId, draggingItem.itemId, dropTarget.locationId, dropTarget.insertionIndex);
      }
      if (state.selectionMode) resetSelectionMode();
    });
  }

  function handleDragEnd() {
    clearDropTarget();
    state.draggingItem = null;
    document.body.classList.remove("is-dragging-item");
    document.querySelectorAll(".item-chip.is-dragging").forEach((chip) => {
      chip.classList.remove("is-dragging");
    });
    window.setTimeout(() => {
      state.suppressItemClick = false;
    }, 160);
  }

  function currentItemDropTarget(event) {
    if (!state.draggingItem) return null;
    const zone = closestFromEvent(event, "[data-drop-zone]");
    if (!zone || zone.dataset.homeId !== state.draggingItem.homeId) return null;

    const home = findHome(zone.dataset.homeId);
    if (!home) return null;

    const locationId = zone.dataset.locationId || null;
    const targetItems = itemsIn(home, locationId);
    let insertionIndex = targetItems.length;
    let chip = closestFromEvent(event, "[data-draggable-item]");

    if (chip && !zone.contains(chip)) chip = null;
    if (chip) {
      const targetIndex = targetItems.findIndex((item) => item.id === chip.dataset.itemId);
      if (targetIndex >= 0) {
        const rect = chip.getBoundingClientRect();
        const after = event.clientX > rect.left + rect.width / 2;
        insertionIndex = targetIndex + (after ? 1 : 0);
        return { zone, chip, position: after ? "after" : "before", locationId, insertionIndex };
      }
    }

    return { zone, chip: null, position: "inside", locationId, insertionIndex };
  }

  function markDropTarget(dropTarget) {
    if (activeDropZone === dropTarget.zone && activeDropChip === dropTarget.chip) {
      if (!dropTarget.chip || dropTarget.chip.classList.contains(`drop-${dropTarget.position}`)) return;
    }

    clearDropTarget();
    activeDropZone = dropTarget.zone;
    activeDropChip = dropTarget.chip;
    activeDropZone.classList.add("is-drop-target");
    if (activeDropChip) activeDropChip.classList.add(`drop-${dropTarget.position}`);
  }

  function clearDropTarget() {
    if (activeDropZone) activeDropZone.classList.remove("is-drop-target");
    if (activeDropChip) activeDropChip.classList.remove("drop-before", "drop-after");
    activeDropZone = null;
    activeDropChip = null;
  }

  function updateBreadcrumb() {
    const breadcrumb = document.getElementById("breadcrumb");
    if (!breadcrumb) return;
    const cards = Array.from(document.querySelectorAll(".tree-card[data-path]"));
    const threshold = 114;
    let current = null;
    cards.forEach((card) => {
      if (card.getBoundingClientRect().top <= threshold) {
        current = card;
      }
    });
    const path = current?.dataset.path?.split(" / ") || [];
    if (path.length <= 1) {
      breadcrumb.classList.add("is-hidden");
      breadcrumb.innerHTML = "";
      return;
    }
    breadcrumb.classList.remove("is-hidden");
    breadcrumb.innerHTML = path.map((part, index) => {
      const escaped = escapeHtml(part);
      return index === path.length - 1 ? `<strong>${escaped}</strong>` : `<span>${escaped}</span><span>›</span>`;
    }).join("");
  }

  async function handleAction(element) {
    const action = element.dataset.action;
    if (action === "open-account") {
      state.sheet = { type: "account" };
      state.actionMenu = null;
      render();
      if (!hasAuthSession() && !state.authConfigLoaded) {
        void loadAuthConfig();
      }
      return;
    }
    if (action === "start-selection") {
      state.selectionMode = true;
      state.actionMenu = null;
      state.sheet = null;
      state.adding = null;
      render();
      return;
    }
    if (action === "end-selection") {
      resetSelectionMode();
      state.actionMenu = null;
      state.sheet = null;
      render();
      return;
    }
    if (action === "close-sheet") {
      state.sheet = null;
      state.photoPreview = null;
      state.actionMenu = null;
      state.iconSearch = "";
      render();
      return;
    }
    if (action === "open-photo-preview") {
      if (state.selectionMode) {
        const chip = element.closest("[data-draggable-item]");
        if (chip) {
          toggleItemSelection(chip.dataset.homeId, chip.dataset.itemId);
          render();
          return;
        }
      }
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        state.sheet.draft = readItemDraftFromForm(form);
      }
      state.photoPreview = {
        url: element.dataset.photoUrl || "",
        title: element.dataset.photoTitle || "Photo",
      };
      render();
      return;
    }
    if (action === "close-photo-preview") {
      state.photoPreview = null;
      render();
      return;
    }
    if (action === "remove-photo" || action === "remove-document") {
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        const draft = readItemDraftFromForm(form);
        const index = Number(element.dataset.index);
        if (action === "remove-photo") {
          draft.photoUrls = draft.photoUrls.filter((_, candidateIndex) => candidateIndex !== index);
        } else {
          draft.documents = draft.documents.filter((_, candidateIndex) => candidateIndex !== index);
        }
        state.sheet.draft = draft;
        render();
      }
      return;
    }
    if (action === "toggle-collapse") {
      state.actionMenu = null;
      const key = element.dataset.nodeKey;
      if (state.collapsed.has(key)) state.collapsed.delete(key);
      else state.collapsed.add(key);
      persistCollapsed();
      render();
      return;
    }
    if (action === "toggle-flag-filter") {
      state.flaggedOnly = !state.flaggedOnly;
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "toggle-item-selection") {
      toggleItemSelection(element.dataset.homeId, element.dataset.itemId);
      render();
      return;
    }
    if (action === "open-actions") {
      const nextMenu = {
        kind: element.dataset.kind,
        homeId: element.dataset.homeId,
        locationId: element.dataset.locationId || null,
      };
      state.actionMenu = actionMenuMatches(nextMenu.kind, nextMenu.homeId, nextMenu.locationId) ? null : nextMenu;
      state.sheet = null;
      render();
      return;
    }
    if (action === "start-add" || action === "start-add-from-sheet") {
      const currentSheet = state.sheet;
      const currentMenu = state.actionMenu;
      state.adding = {
        kind: element.dataset.addKind,
        homeId: element.dataset.homeId || currentSheet?.homeId || currentMenu?.homeId || "",
        parentId: element.dataset.parentId || currentSheet?.locationId || currentMenu?.locationId || null,
        locationType: element.dataset.locationType || null,
      };
      if (element.dataset.addKind === "home") {
        state.adding = { kind: "home" };
      }
      state.sheet = null;
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "cancel-add") {
      state.adding = null;
      render();
      return;
    }
    if (action === "rename-target") {
      state.sheet = { ...(state.sheet || state.actionMenu), type: "rename" };
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "change-icon") {
      state.iconSearch = "";
      state.sheet = { ...(state.sheet || state.actionMenu), type: "iconPicker" };
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "choose-icon") {
      const icon = element.dataset.icon || "";
      await runMutation(async () => {
        await updateTargetIcon(icon);
        state.sheet = null;
        state.iconSearch = "";
      }, "Icon updated");
      return;
    }
    if (action === "open-delete") {
      const current = state.sheet || state.actionMenu || {};
      state.sheet = {
        type: "delete",
        kind: element.dataset.kind || current.kind,
        homeId: element.dataset.homeId || current.homeId,
        locationId: element.dataset.locationId || current.locationId || null,
        itemId: element.dataset.itemId || null,
      };
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "confirm-delete") {
      await runMutation(async () => {
        await deleteTarget();
        state.sheet = null;
      }, "Deleted");
      return;
    }
    if (action === "open-selection-move") {
      if (!selectionCount()) return;
      state.sheet = { type: "selectionMove", path: [] };
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "selection-location-back") {
      if (state.sheet?.type === "selectionMove") {
        const path = Array.isArray(state.sheet.path) ? state.sheet.path.slice(0, -1) : [];
        state.sheet = { ...state.sheet, path };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "drill-selection-location") {
      if (state.sheet?.type === "selectionMove") {
        const locationId = element.dataset.locationId || "";
        const path = Array.isArray(state.sheet.path) ? state.sheet.path.slice() : [];
        if (locationId) path.push(locationId);
        state.sheet = { ...state.sheet, path };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "move-selected-to-location") {
      const homeId = state.selectedHomeId;
      const itemIds = selectedIds();
      const locationId = element.dataset.locationId || null;
      await runMutation(async () => {
        await moveItems(homeId, itemIds, locationId);
        resetSelectionMode();
        state.sheet = null;
      }, "Moved items");
      return;
    }
    if (action === "set-selected-flagged") {
      const homeId = state.selectedHomeId;
      const itemIds = selectedIds();
      const isFlagged = element.dataset.flagged === "true";
      await runMutation(async () => {
        await setItemsFlagged(homeId, itemIds, isFlagged);
      }, isFlagged ? "Flagged" : "Unflagged");
      return;
    }
    if (action === "open-bulk-delete") {
      if (!selectionCount()) return;
      state.sheet = { type: "bulkDelete" };
      state.actionMenu = null;
      render();
      return;
    }
    if (action === "confirm-bulk-delete") {
      const homeId = state.selectedHomeId;
      const itemIds = selectedIds();
      await runMutation(async () => {
        await deleteItems(homeId, itemIds);
        resetSelectionMode();
        state.sheet = null;
      }, "Deleted");
      return;
    }
    if (action === "open-item") {
      if (state.suppressItemClick) return;
      if (state.selectionMode) {
        toggleItemSelection(element.dataset.homeId, element.dataset.itemId);
        render();
        return;
      }
      const item = findItem(element.dataset.homeId, element.dataset.itemId);
      state.actionMenu = null;
      state.sheet = {
        type: "itemEditor",
        homeId: element.dataset.homeId,
        itemId: element.dataset.itemId,
        draft: item ? cloneItem(item) : null,
      };
      render();
      return;
    }
    if (action === "open-location-picker") {
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        const home = findHome(state.sheet.homeId);
        const draft = readItemDraftFromForm(form);
        state.sheet = {
          type: "locationPicker",
          homeId: state.sheet.homeId,
          itemId: state.sheet.itemId,
          draft,
          path: initialLocationPickerPath(home, draft.locationId),
        };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "cancel-location-picker") {
      if (state.sheet?.type === "locationPicker") {
        state.sheet = {
          type: "itemEditor",
          homeId: state.sheet.homeId,
          itemId: state.sheet.itemId,
          draft: state.sheet.draft,
        };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "location-picker-back") {
      if (state.sheet?.type === "locationPicker") {
        const path = Array.isArray(state.sheet.path) ? state.sheet.path.slice(0, -1) : [];
        state.sheet = { ...state.sheet, path };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "drill-location") {
      if (state.sheet?.type === "locationPicker") {
        const locationId = element.dataset.locationId || "";
        const path = Array.isArray(state.sheet.path) ? state.sheet.path.slice() : [];
        if (locationId) path.push(locationId);
        state.sheet = { ...state.sheet, path };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "choose-item-location") {
      if (state.sheet?.type === "locationPicker") {
        const draft = { ...state.sheet.draft, locationId: element.dataset.locationId || null };
        state.sheet = {
          type: "itemEditor",
          homeId: state.sheet.homeId,
          itemId: state.sheet.itemId,
          draft,
        };
        render({ preserveSheetScroll: false });
      }
      return;
    }
    if (action === "set-item-icon") {
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        state.sheet.draft = { ...state.sheet.draft, ...readItemDraftFromForm(form), icon: element.dataset.icon || null };
        render();
      }
      return;
    }
    if (action === "add-property") {
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        const draft = readItemDraftFromForm(form);
        const propertyId = id();
        draft.properties.push({ id: propertyId, key: "", value: "" });
        state.sheet.draft = draft;
        render({ focusSelector: `[data-property-id="${propertyId}"] [data-property-key]` });
      }
      return;
    }
    if (action === "remove-property") {
      const form = document.getElementById("item-editor-form");
      if (form && state.sheet?.type === "itemEditor") {
        const draft = readItemDraftFromForm(form);
        draft.properties.splice(Number(element.dataset.index), 1);
        state.sheet.draft = draft;
        render();
      }
      return;
    }
    if (action === "add-item-date" || action === "clear-item-date") {
      const form = document.getElementById("item-editor-form");
      const field = element.dataset.dateField || "";
      if (form && state.sheet?.type === "itemEditor" && isItemDateField(field)) {
        const draft = readItemDraftFromForm(form);
        draft[field] = action === "add-item-date" ? draft[field] || todayDateString() : null;
        state.sheet.draft = draft;
        render(action === "add-item-date" ? { focusSelector: `input[name="${field}"]` } : {});
      }
      return;
    }
    if (action === "sort-children") {
      const actionTarget = state.actionMenu || state.sheet;
      await runMutation(async () => {
        await sortChildrenForTarget(actionTarget);
        state.sheet = null;
        state.actionMenu = null;
      }, "Locations sorted");
      return;
    }
    if (action === "dev-sign-in") {
      if (!isLocalHost()) {
        showToast("Dev sign-in is only available locally");
        render();
        return;
      }
      await runMutation(async () => {
        const auth = await apiRequest("POST", "/auth/dev", { email: "dev@stufftracker.local", name: "Local Dev" });
        applyAuthResponse(auth);
        await loadServerHomes();
      }, "Signed in");
      return;
    }
    if (action === "apple-sign-in") {
      await runMutation(signInWithApple, "Signed in");
      return;
    }
    if (action === "reload-server") {
      await runMutation(loadServerHomes, "Server data reloaded");
      return;
    }
    if (action === "sign-out") {
      clearSession();
      state.sheet = null;
      render();
      return;
    }
    if (action === "logout-all") {
      await runMutation(async () => {
        await apiRequest("POST", "/auth/logout-all");
        clearSession();
        state.sheet = null;
      }, "Signed out everywhere");
      return;
    }
  }

  function normalizeUser(raw) {
    return {
      id: raw.id,
      email: raw.email,
      name: raw.name,
      avatarUrl: raw.avatarUrl ?? raw.avatar_url ?? null,
    };
  }

  async function handleSubmit(event) {
    const form = event.target.closest("form[data-form]");
    if (!form) return;
    event.preventDefault();
    const kind = form.dataset.form;

    if (kind === "commit-add") {
      const name = form.elements.name.value.trim();
      if (!name || !state.adding) return;
      const adding = state.adding;
      state.adding = null;
      await runMutation(async () => {
        if (adding.kind === "home") await createHome(name);
        else if (adding.kind === "location") await createLocation(adding.homeId, name, adding.parentId, adding.locationType);
        else if (adding.kind === "item") await createItem(adding.homeId, name, adding.parentId);
      }, "Added");
      return;
    }

    if (kind === "account-settings") {
      if (!canManageApiSettings()) {
        showToast("Admin access required");
        render();
        return;
      }
      const nextUrl = form.elements.apiBaseUrl.value.trim().replace(/\/$/, "");
      state.apiBaseUrl = nextUrl || DEFAULT_API_BASE_URL;
      state.authConfigLoaded = false;
      persistSession();
      showToast("API URL saved");
      void loadAuthConfig();
      render();
      return;
    }

    if (kind === "rename") {
      const name = form.elements.name.value.trim();
      if (!name) return;
      await runMutation(async () => {
        await renameTarget(name);
        state.sheet = null;
      }, "Renamed");
      return;
    }

    if (kind === "item-save") {
      await runMutation(async () => {
        await saveItemFromForm(form);
        state.sheet = null;
      }, "Item saved");
    }
  }

  async function handleAttachmentFileChange(event) {
    const input = event.target.closest?.("input[type='file'][data-upload-kind]");
    if (!input) return;

    const files = Array.from(input.files || []);
    input.value = "";
    if (!files.length || state.isUploadingAttachment) return;

    const kind = input.dataset.uploadKind;
    const form = document.getElementById("item-editor-form");
    if (!form || state.sheet?.type !== "itemEditor" || !["photo", "document"].includes(kind)) return;

    state.sheet.draft = readItemDraftFromForm(form);
    state.isUploadingAttachment = true;
    render();

    try {
      const uploads = [];
      for (const file of files) {
        uploads.push({ file, upload: await uploadItemAttachment(form.dataset.homeId, kind, file) });
      }

      if (state.sheet?.type !== "itemEditor") return;

      const currentForm = document.getElementById("item-editor-form");
      const draft = currentForm && state.sheet?.type === "itemEditor"
        ? readItemDraftFromForm(currentForm)
        : state.sheet?.draft || {};

      if (kind === "photo") {
        draft.photoUrls = [
          ...(draft.photoUrls || []),
          ...uploads.map(({ upload }) => upload.fileUrl),
        ];
      } else {
        draft.documents = [
          ...(draft.documents || []),
          ...uploads.map(({ file, upload }) => ({
            id: upload.key,
            url: upload.fileUrl,
            name: uploadFileName("document", file),
            contentType: uploadContentTypeForFile("document", file),
          })),
        ];
      }

      state.sheet.draft = draft;
      showToast(attachmentUploadSuccessMessage(kind, uploads.length));
    } catch (error) {
      showToast(error.message || String(error));
    } finally {
      state.isUploadingAttachment = false;
      render();
    }
  }

  function attachmentUploadSuccessMessage(kind, count) {
    if (count === 1) return kind === "photo" ? "Photo added" : "Document uploaded";
    return kind === "photo" ? `${count} photos added` : `${count} documents uploaded`;
  }

  function handleInput(event) {
    if (event.target.id === "search-input") {
      state.search = event.target.value;
      render();
      return;
    }
    if (event.target.id === "icon-search-input") {
      state.iconSearch = event.target.value;
      render();
    }
  }

  document.addEventListener("click", (event) => {
    const actionElement = event.target.closest("[data-action]");
    if (!actionElement) {
      if (state.photoPreview && event.target.classList?.contains("photo-modal-backdrop")) {
        state.photoPreview = null;
        render();
        return;
      }
      if (state.actionMenu && !event.target.closest("[data-action-menu]")) {
        state.actionMenu = null;
        render();
      }
      return;
    }
    event.preventDefault();
    void handleAction(actionElement);
  });
  document.addEventListener("submit", (event) => {
    void handleSubmit(event);
  });
  document.addEventListener("input", handleInput);
  document.addEventListener("change", (event) => {
    void handleAttachmentFileChange(event);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.photoPreview) {
      state.photoPreview = null;
      render();
    }
  });
  document.addEventListener("dragstart", handleDragStart);
  document.addEventListener("dragover", handleDragOver);
  document.addEventListener("drop", (event) => {
    void handleDrop(event);
  });
  document.addEventListener("dragend", handleDragEnd);
  window.addEventListener("scroll", updateBreadcrumb, { passive: true });
  window.addEventListener("resize", updateBreadcrumb);
  window.addEventListener("load", () => requestAnimationFrame(renderProviderSignInButtons));

  render();

  if (state.pendingItemLink && !hasAuthSession() && !state.authConfigLoaded) {
    void loadAuthConfig();
  }

  if (hasAuthSession()) {
    void runMutation(loadServerHomes);
  }
})();

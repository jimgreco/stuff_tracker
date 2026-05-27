(function () {
  "use strict";

  const STORAGE = {
    apiBaseUrl: "stuffTrackerMobileWeb.apiBaseUrl",
    token: "stuffTrackerMobileWeb.token",
    user: "stuffTrackerMobileWeb.user",
    homes: "stuffTrackerMobileWeb.homes",
    deletedItems: "stuffTrackerMobileWeb.deletedItems",
    collapsed: "stuffTrackerMobileWeb.collapsed",
  };

  const DEFAULT_API_BASE_URL = defaultApiBaseUrl();
  const STORED_TOKEN = localStorage.getItem(STORAGE.token) || "";
  const app = document.getElementById("app");

  const state = {
    apiBaseUrl: localStorage.getItem(STORAGE.apiBaseUrl) || DEFAULT_API_BASE_URL,
    token: STORED_TOKEN,
    user: STORED_TOKEN ? readJson(STORAGE.user, null) : null,
    accountPlan: null,
    homes: STORED_TOKEN ? readJson(STORAGE.homes, []) : [],
    collapsed: new Set(readJson(STORAGE.collapsed, [])),
    search: "",
    isLoading: false,
    toast: "",
    toastTimer: null,
    sheet: null,
    adding: null,
    iconSearch: "",
    authConfigLoaded: false,
    googleClientId: "",
    appleClientId: "",
  };

  if (!STORED_TOKEN) {
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
    sort: '<path d="M7 7h10"/><path d="M7 12h7"/><path d="M7 17h4"/>',
    cloud: '<path d="M17.5 18H8a5 5 0 1 1 1.8-9.7A6 6 0 0 1 21 11a4 4 0 0 1-3.5 7z"/>',
    refresh: '<path d="M20 12a8 8 0 0 1-13.7 5.6"/><path d="M4 12A8 8 0 0 1 17.7 6.4"/><path d="M4 18v-5h5"/><path d="M20 6v5h-5"/>',
    share: '<path d="M8 12h8"/><circle cx="5" cy="12" r="3"/><circle cx="19" cy="5" r="3"/><circle cx="19" cy="19" r="3"/><path d="m16.5 7-9 4"/><path d="m16.5 17-9-4"/>',
    doc: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/>',
    photo: '<path d="M4 5h16v14H4z"/><circle cx="9" cy="10" r="2"/><path d="m4 17 5-5 4 4 2-2 5 5"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.1 0l2-2a5 5 0 0 0-7.1-7.1l-1.2 1.2"/><path d="M14 11a5 5 0 0 0-7.1 0l-2 2A5 5 0 0 0 12 20.1l1.2-1.2"/>',
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
    if (isLocalHost && port && port !== "5173") {
      return origin;
    }
    return "http://localhost:3002";
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
    state.accountPlan = null;
    state.collapsed = new Set();
    localStorage.removeItem(STORAGE.homes);
    localStorage.removeItem(STORAGE.deletedItems);
    localStorage.removeItem(STORAGE.collapsed);
  }

  function persistCollapsed() {
    writeJson(STORAGE.collapsed, Array.from(state.collapsed));
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
    if (value.includes("person")) return "person";
    if (value.includes("trash")) return "trash";
    if (value.includes("star")) return "star";
    return value in ICON_PATHS ? value : "circle";
  }

  function svgIcon(symbol, className = "") {
    const key = iconKey(symbol);
    const body = ICON_PATHS[key] || ICON_PATHS.circle;
    const klass = className ? ` ${escapeAttr(className)}` : "";
    return `<svg class="svg-icon${klass}" viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
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

  function render() {
    const active = document.activeElement;
    const activeId = active && active.id;
    const selectionStart = active && "selectionStart" in active ? active.selectionStart : null;
    const selectionEnd = active && "selectionEnd" in active ? active.selectionEnd : null;

    app.innerHTML = renderApp();

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

    requestAnimationFrame(updateBreadcrumb);
    requestAnimationFrame(renderProviderSignInButtons);
  }

  function renderApp() {
    if (!state.token) {
      return renderSignedOutApp();
    }

    const homes = filteredHomes();
    const isSearching = state.search.trim().length > 0;
    return `
      <div class="mobile-shell">
        <header class="top-bar">
          <div class="nav-row">
            <div class="nav-spacer" aria-hidden="true"></div>
            <div class="nav-title">Stuff Tracker</div>
            <button type="button" class="icon-button avatar-button" data-action="open-account" aria-label="Account">
              ${renderAvatar()}
            </button>
          </div>
          <div class="search-wrap">
            ${svgIcon("search")}
            <input id="search-input" class="search-input" type="search" autocomplete="off" placeholder="Search stuff..." value="${escapeAttr(state.search)}">
          </div>
        </header>
        <div id="breadcrumb" class="breadcrumb is-hidden" aria-hidden="true"></div>
        <main class="content">
          ${renderStatus()}
          ${
            state.isLoading
              ? renderLoading()
              : homes.length
                ? `<div class="home-list">${homes.map((home) => renderHome(home, isSearching)).join("")}</div>`
                : isSearching
                  ? renderNoResults()
                  : renderEmptyState()
          }
          ${!state.isLoading && !isSearching ? renderAddHomeArea() : ""}
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
          <a class="marketing-brand" href="#top" aria-label="Stuff Tracker home">
            <img src="./assets/app-icon.png" width="34" height="34" alt="">
            <span>Stuff Tracker</span>
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
              <p class="marketing-kicker">Home inventory that follows the way you actually store things</p>
              <h1>Stuff Tracker</h1>
              <p class="marketing-lede">Map homes, rooms, containers, and loose items. Keep photos, documents, serial numbers, warranties, and values close to the things they belong to.</p>
              <div class="marketing-actions">
                <button type="button" class="marketing-primary" data-action="open-account">Start tracking</button>
                <a class="marketing-secondary" href="#features">See features</a>
              </div>
              <dl class="marketing-proof">
                <div>
                  <dt>Homes</dt>
                  <dd>Shared spaces</dd>
                </div>
                <div>
                  <dt>Items</dt>
                  <dd>Photos and docs</dd>
                </div>
                <div>
                  <dt>Search</dt>
                  <dd>Room to serial</dd>
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
      ["house.fill", "Mirror your real storage", "Build a tree of homes, floors, rooms, bins, shelves, drawers, and loose items without flattening everything into one list."],
      ["search", "Find by any clue", "Search item names, notes, rooms, serial numbers, model numbers, and custom properties when you only remember part of the answer."],
      ["photo.fill", "Attach the evidence", "Keep photos, documents, warranty dates, purchase dates, values, and notes with the item they describe."],
      ["share", "Use it with your household", "Share a home so the people who live with the stuff can keep the inventory current together."],
    ];
    return `
      <section id="features" class="marketing-section">
        <div class="marketing-section-heading">
          <p>Built around where things live</p>
          <h2>Inventory that keeps the room, container, and item together.</h2>
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
          <p>Less guessing when it matters</p>
          <h2>Useful details stay attached to the thing, not buried in a folder.</h2>
        </div>
        <div class="marketing-detail-list">
          <div class="marketing-detail-row">
            ${svgIcon("tag")}
            <div>
              <h3>Custom fields for the odd details</h3>
              <p>Add the property you need, from filter size to paint color to access code.</p>
            </div>
          </div>
          <div class="marketing-detail-row">
            ${svgIcon("doc")}
            <div>
              <h3>Documents beside the item</h3>
              <p>Store receipts, manuals, warranty paperwork, and reference files where future you will look first.</p>
            </div>
          </div>
          <div class="marketing-detail-row">
            ${svgIcon("cloud")}
            <div>
              <h3>Synced from the start</h3>
              <p>Sign in once and keep the same inventory available from the web and the app.</p>
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
          <p>Ready when you are</p>
          <h2>Start with the spaces you already know, then fill in the details over time.</h2>
        </div>
        <div class="marketing-access-actions">
          <button type="button" class="marketing-primary" data-action="open-account">Sign in or create account</button>
          <button type="button" class="marketing-secondary button-reset" data-action="open-account">${svgIcon("cloud")} API settings</button>
        </div>
      </section>
    `;
  }

  function renderAccountRequired() {
    return `
      <section class="empty-state auth-required">
        <div class="empty-panel">
          <img src="./assets/app-icon.png" alt="">
          <h2>Sign in to use Stuff Tracker on the web</h2>
          <p>Create or connect an account to sync your homes, rooms, and items.</p>
          <div class="auth-actions">
            ${renderAuthControls()}
          </div>
          <button type="button" class="secondary-button" data-action="open-account">
            ${svgIcon("cloud")} API settings
          </button>
        </div>
      </section>
    `;
  }

  function renderAuthControls() {
    const controls = [];
    if (state.googleClientId) {
      controls.push(`<div class="provider-button-host" data-google-sign-in-host></div>`);
    }
    if (state.appleClientId) {
      controls.push(`<button type="button" class="row-button provider-apple" data-action="apple-sign-in">Sign in with Apple</button>`);
    }
    if (isLocalHost()) {
      controls.push(`<button type="button" class="row-button" data-action="dev-sign-in">${svgIcon("person")} Dev Sign In</button>`);
    }
    if (!controls.length) {
      controls.push(`<div class="auth-unavailable">Sign-in providers are not configured for this API URL.</div>`);
    }
    return controls.join("");
  }

  function renderAvatar() {
    if (state.user && state.user.avatarUrl) {
      return `<img class="avatar-image" src="${escapeAttr(state.user.avatarUrl)}" alt="">`;
    }
    return svgIcon("person");
  }

  function renderStatus() {
    return `
      <div class="status-strip">
        <span class="status-dot connected"></span>
        <span>Connected to backend sync</span>
      </div>
    `;
  }

  function renderLoading() {
    return `<div class="loading-state"><div class="spinner" aria-label="Loading"></div></div>`;
  }

  function renderNoResults() {
    return `
      <div class="no-results">
        <div class="empty-panel">
          ${svgIcon("search")}
          <h2>No results</h2>
          <p>Try another item, room, property, or note.</p>
        </div>
      </div>
    `;
  }

  function renderEmptyState() {
    return `
      <div class="empty-state">
        <div class="empty-panel">
          <img src="./assets/app-icon.png" alt="">
          <h2>Welcome to Stuff Tracker</h2>
          <p>Track your stuff across homes, rooms, containers, and loose items.</p>
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
        <button type="button" class="menu-button" data-action="open-actions" data-kind="${escapeAttr(kind)}" data-home-id="${escapeAttr(homeId)}" ${locationId ? `data-location-id="${escapeAttr(locationId)}"` : ""} aria-label="Actions for ${escapeAttr(title)}">
          ${svgIcon("ellipsis")}
        </button>
      </div>
    `;
  }

  function renderItemFlow(home, locationId) {
    const items = itemsIn(home, locationId);
    return `
      <div class="item-flow">
        ${items.map((item) => renderItemChip(home, item)).join("")}
        <button type="button" class="add-chip" data-action="start-add" data-add-kind="item" data-home-id="${escapeAttr(home.id)}" data-parent-id="${escapeAttr(locationId || "")}">
          ${svgIcon("plus")} <span>Add item</span>
        </button>
      </div>
    `;
  }

  function renderItemChip(home, item) {
    return `
      <button type="button" class="item-chip" data-action="open-item" data-home-id="${escapeAttr(home.id)}" data-item-id="${escapeAttr(item.id)}">
        ${svgIcon(item.icon || "circle.fill")}
        <span class="item-name">${escapeHtml(item.name)}</span>
        ${item.quantity > 1 ? `<span class="quantity">x${escapeHtml(item.quantity)}</span>` : ""}
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
    if (state.sheet.type === "actions") return renderActionsSheet();
    if (state.sheet.type === "rename") return renderRenameSheet();
    if (state.sheet.type === "iconPicker") return renderIconPickerSheet();
    if (state.sheet.type === "delete") return renderDeleteSheet();
    if (state.sheet.type === "itemEditor") return renderItemEditorSheet();
    return "";
  }

  function sheetChrome(title, body, options = {}) {
    const save = options.saveFormId
      ? `<button type="submit" form="${escapeAttr(options.saveFormId)}" class="sheet-save">${escapeHtml(options.saveLabel || "Save")}</button>`
      : `<span></span>`;
    return `
      <div class="sheet-backdrop">
        <section class="sheet" role="dialog" aria-modal="true" aria-label="${escapeAttr(title)}">
          <header class="sheet-header">
            <button type="button" class="sheet-close" data-action="close-sheet">${escapeHtml(options.closeLabel || "Done")}</button>
            <div class="sheet-title">${escapeHtml(title)}</div>
            ${save}
          </header>
          <div class="sheet-body">${body}</div>
        </section>
      </div>
    `;
  }

  function renderAccountSheet() {
    const connected = Boolean(state.token);
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
      <form class="form-section" data-form="account-settings">
        <h2 class="section-title">Backend</h2>
        <div class="form-list">
          <label class="form-row">
            <span>API URL</span>
            <input name="apiBaseUrl" value="${escapeAttr(state.apiBaseUrl)}" inputmode="url" autocomplete="url">
          </label>
          <button type="submit" class="row-button">${svgIcon("check")} Save API URL</button>
          ${!connected ? renderAuthControls() : ""}
          ${connected ? `<button type="button" class="row-button" data-action="reload-server">${svgIcon("refresh")} Reload Server Data</button>` : ""}
        </div>
      </form>
      <section class="form-section">
        <h2 class="section-title">Account</h2>
        <div class="form-list">
          ${connected ? `<button type="button" class="row-button danger" data-action="logout-all">${svgIcon("x")} Sign Out Everywhere</button>` : ""}
          ${connected ? `<button type="button" class="row-button danger" data-action="sign-out">${svgIcon("x")} Sign Out</button>` : ""}
          ${!connected ? `<div class="auth-unavailable">Sign in to create and sync inventory data on the web.</div>` : ""}
        </div>
      </section>
      <p class="footnote">Version web.</p>
    `;
    return sheetChrome("Account", body);
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

  function renderActionsSheet() {
    const target = targetForSheet();
    if (!target) return "";
    const title = target.location ? target.location.name : target.home.name;
    const rows = [];
    rows.push(actionButton("rename-target", "pencil", "Rename"));
    rows.push(actionButton("change-icon", "star", "Change Icon"));
    if (state.sheet.kind === "home") {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Floor", { addKind: "location", locationType: "floor" }));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Room", { addKind: "location", locationType: "room" }));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { addKind: "item" }));
    } else if (target.location.type === "floor") {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Room", { addKind: "location", locationType: "room" }));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { addKind: "item" }));
      rows.push(actionButton("sort-children", "sort", "Order Rooms by Name"));
    } else {
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Container", { addKind: "location", locationType: "container" }));
      rows.push(actionButton("start-add-from-sheet", "plus", "Add Item", { addKind: "item" }));
      rows.push(actionButton("sort-children", "sort", "Order Containers by Name"));
    }
    rows.push(actionButton("open-delete", "trash", "Delete", {}, true));
    return sheetChrome(title, `<div class="action-list">${rows.join("")}</div>`);
  }

  function actionButton(action, icon, label, extra = {}, danger = false) {
    const data = Object.entries(extra)
      .map(([key, value]) => `data-${toKebab(key)}="${escapeAttr(value)}"`)
      .join(" ");
    return `
      <button type="button" class="sheet-action ${danger ? "danger" : ""}" data-action="${escapeAttr(action)}" ${data}>
        ${svgIcon(icon)} <span>${escapeHtml(label)}</span>
      </button>
    `;
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
              <span>Purchase Date</span>
              <input name="purchaseDate" type="date" value="${escapeAttr(draft.purchaseDate || "")}">
            </label>
            <label class="form-row">
              <span>Warranty</span>
              <input name="warrantyExpiresDate" type="date" value="${escapeAttr(draft.warrantyExpiresDate || "")}">
            </label>
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
            <label class="full-row">
              <div class="row-label">Notes</div>
              <textarea name="notes" rows="4">${escapeHtml(draft.notes || "")}</textarea>
            </label>
          </div>
        </section>
        <section class="form-section">
          <h2 class="section-title">Location</h2>
          <div class="form-list">
            <label class="form-row">
              <span>Stored In</span>
              <select name="locationId">
                ${locationOptions(home, draft.locationId).join("")}
              </select>
            </label>
          </div>
        </section>
        <section class="form-section">
          <h2 class="section-title">Properties</h2>
          <div class="form-list">
            ${draft.properties.map((property, index) => renderPropertyRow(property, index)).join("")}
            <button type="button" class="row-button" data-action="add-property">${svgIcon("plus")} Add Property</button>
          </div>
        </section>
        ${renderAttachmentsSection("Photos", draft.photoUrls, "photo")}
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

  function renderDocumentSection(documents) {
    if (!documents || !documents.length) return "";
    return `
      <section class="form-section">
        <h2 class="section-title">Documents</h2>
        <div class="form-list">
          <div class="attachment-list">
            ${documents.map((document) => `
              <a class="attachment-link" href="${escapeAttr(document.url)}" target="_blank" rel="noreferrer">
                ${svgIcon("doc")} <span>${escapeHtml(document.name)}</span>
              </a>
            `).join("")}
          </div>
        </div>
      </section>
    `;
  }

  function locationOptions(home, selectedId) {
    const options = [`<option value="" ${!selectedId ? "selected" : ""}>No location</option>`];
    function walk(parentId, depth) {
      childLocations(home, parentId).forEach((location) => {
        const prefix = Array(depth + 1).join("  ");
        options.push(`<option value="${escapeAttr(location.id)}" ${location.id === selectedId ? "selected" : ""}>${escapeHtml(prefix + location.name)}</option>`);
        walk(location.id, depth + 1);
      });
    }
    walk(null, 0);
    return options;
  }

  function filteredHomes() {
    const query = state.search.trim().toLowerCase();
    if (!query) return state.homes;

    return state.homes.map((home) => {
      const homeMatches = home.name.toLowerCase().includes(query);
      const directMatchIds = new Set(home.locations.filter((loc) => loc.name.toLowerCase().includes(query)).map((loc) => loc.id));
      const matchingLocationIds = new Set(directMatchIds);
      let toExpand = new Set(directMatchIds);
      while (toExpand.size) {
        const children = home.locations.filter((loc) => loc.parentId && toExpand.has(loc.parentId)).map((loc) => loc.id);
        toExpand = new Set(children.filter((childId) => !matchingLocationIds.has(childId)));
        toExpand.forEach((childId) => matchingLocationIds.add(childId));
      }

      const matchingItems = home.items.filter((item) => {
        const propertyText = item.properties.map((property) => `${property.key} ${property.value}`).join(" ");
        return [
          item.name,
          item.notes || "",
          item.serialNumber || "",
          item.modelNumber || "",
          propertyText,
        ].join(" ").toLowerCase().includes(query);
      });

      if (!homeMatches && directMatchIds.size === 0 && matchingItems.length === 0) {
        return null;
      }
      if (homeMatches) return home;

      const neededLocationIds = new Set(matchingLocationIds);
      matchingItems.forEach((item) => {
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
        items: home.items.filter((item) => {
          if (matchingItems.some((match) => match.id === item.id)) return true;
          return item.locationId ? matchingLocationIds.has(item.locationId) : false;
        }),
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

  function cloneItem(item) {
    return JSON.parse(JSON.stringify(item));
  }

  function targetForSheet() {
    const sheet = state.sheet;
    if (!sheet) return null;
    const home = findHome(sheet.homeId);
    if (!home) return null;
    const location = sheet.locationId ? home.locations.find((loc) => loc.id === sheet.locationId) : null;
    return { home, location };
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
    const response = await fetch(`${state.apiBaseUrl}${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (!response.ok) {
      let message = `HTTP ${response.status}`;
      try {
        const parsed = await response.json();
        message = parsed.error || parsed.message || message;
      } catch {
        const text = await response.text();
        if (text.trim()) message = text.trim();
      }
      throw new Error(message);
    }

    if (response.status === 204) return null;
    return response.json();
  }

  async function loadAuthConfig() {
    try {
      const config = await apiRequest("GET", "/auth/config");
      state.googleClientId = config.googleClientId ?? config.google_client_id ?? "";
      state.appleClientId = config.appleClientId ?? config.apple_client_id ?? "";
    } catch {
      state.googleClientId = "";
      state.appleClientId = "";
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
      container.innerHTML = "";
      window.google.accounts.id.renderButton(container, {
        theme: "outline",
        size: "large",
        width: Math.max(container.clientWidth || 280, 240),
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
      sortOrder,
      createdBy: state.user?.id || "local",
    };
    await apiRequest("POST", `/homes/${homeId}/items`, itemPayload(item));
    await loadServerHomes();
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
      sortOrder: formItem?.sortOrder || 0,
    };
  }

  async function sortChildrenForTarget() {
    const target = targetForSheet();
    if (!target) return;
    const parentId = target.location ? target.location.id : null;
    const sorted = childLocations(target.home, parentId).sort((a, b) => a.name.localeCompare(b.name));
    await Promise.all(sorted.map((location, index) => apiRequest("PATCH", `/homes/${target.home.id}/locations/${location.id}`, { sort_order: index })));
    await loadServerHomes();
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
      render();
      if (!state.token && !state.authConfigLoaded) {
        void loadAuthConfig();
      }
      return;
    }
    if (action === "close-sheet") {
      state.sheet = null;
      state.iconSearch = "";
      render();
      return;
    }
    if (action === "toggle-collapse") {
      const key = element.dataset.nodeKey;
      if (state.collapsed.has(key)) state.collapsed.delete(key);
      else state.collapsed.add(key);
      persistCollapsed();
      render();
      return;
    }
    if (action === "open-actions") {
      state.sheet = {
        type: "actions",
        kind: element.dataset.kind,
        homeId: element.dataset.homeId,
        locationId: element.dataset.locationId || null,
      };
      render();
      return;
    }
    if (action === "start-add" || action === "start-add-from-sheet") {
      const currentSheet = state.sheet;
      state.adding = {
        kind: element.dataset.addKind,
        homeId: element.dataset.homeId || currentSheet?.homeId || "",
        parentId: element.dataset.parentId || currentSheet?.locationId || null,
        locationType: element.dataset.locationType || null,
      };
      if (element.dataset.addKind === "home") {
        state.adding = { kind: "home" };
      }
      state.sheet = null;
      render();
      return;
    }
    if (action === "cancel-add") {
      state.adding = null;
      render();
      return;
    }
    if (action === "rename-target") {
      state.sheet = { ...state.sheet, type: "rename" };
      render();
      return;
    }
    if (action === "change-icon") {
      state.iconSearch = "";
      state.sheet = { ...state.sheet, type: "iconPicker" };
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
      const current = state.sheet || {};
      state.sheet = {
        type: "delete",
        kind: element.dataset.kind || current.kind,
        homeId: element.dataset.homeId || current.homeId,
        locationId: element.dataset.locationId || current.locationId || null,
        itemId: element.dataset.itemId || null,
      };
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
    if (action === "open-item") {
      const item = findItem(element.dataset.homeId, element.dataset.itemId);
      state.sheet = {
        type: "itemEditor",
        homeId: element.dataset.homeId,
        itemId: element.dataset.itemId,
        draft: item ? cloneItem(item) : null,
      };
      render();
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
        draft.properties.push({ id: id(), key: "", value: "" });
        state.sheet.draft = draft;
        render();
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
    if (action === "sort-children") {
      await runMutation(async () => {
        await sortChildrenForTarget();
        state.sheet = null;
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
      state.token = "";
      state.user = null;
      clearCachedData();
      persistSession();
      state.sheet = null;
      render();
      return;
    }
    if (action === "logout-all") {
      await runMutation(async () => {
        await apiRequest("POST", "/auth/logout-all");
        state.token = "";
        state.user = null;
        clearCachedData();
        persistSession();
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
    if (!actionElement) return;
    event.preventDefault();
    void handleAction(actionElement);
  });
  document.addEventListener("submit", (event) => {
    void handleSubmit(event);
  });
  document.addEventListener("input", handleInput);
  window.addEventListener("scroll", updateBreadcrumb, { passive: true });
  window.addEventListener("resize", updateBreadcrumb);
  window.addEventListener("load", () => requestAnimationFrame(renderProviderSignInButtons));

  render();

  if (state.token) {
    void runMutation(loadServerHomes);
  }
})();

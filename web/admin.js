(function () {
  "use strict";

  const STORAGE = {
    token: "stuffTrackerMobileWeb.token",
    refreshToken: "stuffTrackerMobileWeb.refreshToken",
    user: "stuffTrackerMobileWeb.user",
  };
  const app = document.getElementById("admin-app");

  const state = {
    token: localStorage.getItem(STORAGE.token) || "",
    refreshToken: localStorage.getItem(STORAGE.refreshToken) || "",
    user: readJson(STORAGE.user, null),
    authConfig: null,
    overview: null,
    loading: false,
    updatingUserId: "",
    status: "",
    error: "",
  };

  function readJson(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key) || "");
    } catch {
      return fallback;
    }
  }

  function writeJson(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
  }

  function persistAuth(auth) {
    state.token = auth.token || "";
    state.refreshToken = auth.refreshToken ?? auth.refresh_token ?? "";
    state.user = normalizeUser(auth.user);
    localStorage.setItem(STORAGE.token, state.token);
    localStorage.setItem(STORAGE.refreshToken, state.refreshToken);
    writeJson(STORAGE.user, state.user);
  }

  function clearAuth() {
    state.token = "";
    state.refreshToken = "";
    state.user = null;
    state.overview = null;
    localStorage.removeItem(STORAGE.token);
    localStorage.removeItem(STORAGE.refreshToken);
    localStorage.removeItem(STORAGE.user);
  }

  function normalizeUser(raw) {
    if (!raw) return null;
    return {
      id: raw.id,
      email: raw.email,
      name: raw.name || raw.email,
      avatarUrl: raw.avatarUrl ?? raw.avatar_url ?? null,
    };
  }

  async function apiRequest(path, options = {}) {
    const headers = {
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      ...(options.headers || {}),
    };
    const response = await fetch(path, {
      ...options,
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const payload = await readResponse(response);
    if (!response.ok) {
      const error = new Error(payload?.error || `Request failed with HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  async function readResponse(response) {
    const type = response.headers.get("content-type") || "";
    if (type.includes("application/json")) return response.json();
    return response.text();
  }

  async function loadAuthConfig() {
    try {
      state.authConfig = await apiRequest("/auth/config", { headers: {} });
    } catch {
      state.authConfig = {};
    }
    render();
  }

  async function loadOverview() {
    if (!state.token) return;
    state.loading = true;
    state.error = "";
    render();
    try {
      state.overview = await apiRequest("/admin/overview");
      state.status = `Updated ${formatDateTime(state.overview.generated_at)}`;
    } catch (error) {
      if (error.status === 401) {
        clearAuth();
        await loadAuthConfig();
      }
      state.error = error.message || String(error);
    } finally {
      state.loading = false;
      render();
    }
  }

  async function signInWithGoogle(response) {
    if (!response?.credential) {
      state.error = "Google sign-in failed";
      render();
      return;
    }
    await run(async () => {
      const auth = await apiRequest("/auth/google", { method: "POST", body: { idToken: response.credential }, headers: {} });
      persistAuth(auth);
      await loadOverview();
    });
  }

  async function signInWithApple() {
    const clientId = state.authConfig?.apple_client_id || state.authConfig?.appleClientId;
    if (!clientId || !window.AppleID?.auth) {
      state.error = "Apple sign-in is not configured";
      render();
      return;
    }
    await run(async () => {
      window.AppleID.auth.init({
        clientId,
        scope: "name email",
        redirectURI: window.location.origin,
        usePopup: true,
      });
      const response = await window.AppleID.auth.signIn();
      const identityToken = response?.authorization?.id_token;
      if (!identityToken) throw new Error("Apple sign-in did not return an identity token");
      const name = response?.user?.name || {};
      const fullName = (name.firstName || name.lastName)
        ? { givenName: name.firstName || null, familyName: name.lastName || null }
        : null;
      const auth = await apiRequest("/auth/apple", { method: "POST", body: { identityToken, fullName }, headers: {} });
      persistAuth(auth);
      await loadOverview();
    });
  }

  async function run(operation) {
    state.loading = true;
    state.error = "";
    render();
    try {
      await operation();
    } catch (error) {
      state.error = error.message || String(error);
    } finally {
      state.loading = false;
      render();
    }
  }

  async function updateManualEntitlement(userId, makePaid) {
    const user = findOverviewUser(userId);
    const email = user?.email || "this user";
    if (!makePaid && !window.confirm(`Set ${email} back to the free plan?`)) {
      return;
    }

    state.loading = true;
    state.updatingUserId = userId;
    state.error = "";
    render();
    try {
      const result = await apiRequest(`/admin/users/${encodeURIComponent(userId)}/manual-entitlement`, {
        method: makePaid ? "POST" : "DELETE",
      });
      await loadOverview();
      if (makePaid) {
        state.status = `${email} is manually paid`;
      } else if (result.plan?.isPaid) {
        const source = titleCase(result.plan.entitlement?.source || "paid");
        state.status = `Manual access removed for ${email}; account is still paid via ${source}`;
      } else {
        state.status = `${email} is back on the free plan`;
      }
    } catch (error) {
      state.error = error.message || String(error);
    } finally {
      state.loading = false;
      state.updatingUserId = "";
      render();
    }
  }

  function render() {
    app.innerHTML = state.token ? renderDashboard() : renderGate();
    requestAnimationFrame(renderGoogleButton);
  }

  function renderGate() {
    return `
      <main class="admin-gate">
        <section class="gate-panel" aria-labelledby="admin-gate-title">
          <div class="gate-brand">
            <img src="/assets/app-icon.png?v=20260705-layered-icon" alt="">
            <div>
              <p class="gate-kicker">Operations workspace</p>
              <h1 id="admin-gate-title">CubbyLog Admin</h1>
            </div>
          </div>
          <p>Sign in with an admin account to review users, storage, sessions, and entitlement status.</p>
          <div class="auth-controls">
            ${renderAuthControls()}
          </div>
          ${state.error ? `<div class="status error" role="alert">${escapeHtml(state.error)}</div>` : ""}
        </section>
      </main>
    `;
  }

  function renderAuthControls() {
    if (!state.authConfig) return `<div class="status" role="status" aria-live="polite">Loading sign-in options…</div>`;
    const controls = [];
    const googleClientId = state.authConfig.google_client_id || state.authConfig.googleClientId;
    if (googleClientId) {
      controls.push(`<div class="provider-host" data-google-sign-in-host data-client-id="${escapeAttr(googleClientId)}"></div>`);
    }
    const appleClientId = state.authConfig.apple_client_id || state.authConfig.appleClientId;
    if (appleClientId) {
      controls.push(`<button type="button" class="admin-button" data-action="apple-sign-in">Sign in with Apple</button>`);
    }
    return controls.length ? controls.join("") : `<div class="status error" role="alert">No web sign-in providers are configured.</div>`;
  }

  function renderDashboard() {
    const overview = state.overview;
    const user = overview?.current_user || state.user || {};
    return `
      <a class="skip-link" href="#admin-main">Skip to admin content</a>
      <main id="admin-main" class="admin-shell" aria-busy="${state.loading ? "true" : "false"}">
        <header class="admin-topbar">
          <div class="admin-brand">
            <img src="/assets/app-icon.png?v=20260705-layered-icon" alt="">
            <div>
              <h1>CubbyLog Admin</h1>
              <p>${escapeHtml(user.email || "Signed in")}</p>
            </div>
          </div>
          <div class="admin-actions">
            <button type="button" class="admin-button" data-action="refresh" ${state.loading ? "disabled" : ""}>${state.loading ? "Refreshing…" : "Refresh"}</button>
            <a class="admin-button" href="/">Open App</a>
            <button type="button" class="admin-button danger" data-action="sign-out">Sign Out</button>
          </div>
        </header>
        ${state.error ? `<div class="status error" role="alert">${escapeHtml(state.error)}</div>` : ""}
        ${state.status ? `<div class="status" role="status" aria-live="polite">${escapeHtml(state.status)}</div>` : ""}
        ${overview ? renderOverview(overview) : `<section class="admin-loading" role="status" aria-live="polite"><span>${state.loading ? "Loading admin data…" : "No admin data loaded"}</span></section>`}
      </main>
    `;
  }

  function renderOverview(overview) {
    const totals = overview.totals || {};
    return `
      <section class="admin-summary" aria-label="Account overview">
        ${metric("Users", totals.users)}
        ${metric("Homes", totals.homes)}
        ${metric("Locations", totals.locations)}
        ${metric("Items", totals.items)}
        ${metric("Entitlements", totals.active_entitlements)}
        ${metric("Sessions", totals.active_sessions)}
      </section>
      <section class="admin-panel">
        <header class="panel-header">
          <div>
            <h2>Users</h2>
            <p class="admin-muted">${overview.users.length} most recent accounts</p>
          </div>
        </header>
        <div class="admin-table-wrap">
          <table class="admin-table">
            <caption class="visually-hidden">Most recent CubbyLog user accounts and their usage, plan, and session status</caption>
            <thead>
              <tr>
                <th>User</th>
                <th>Homes</th>
                <th>Shared</th>
                <th>Items</th>
                <th>Plan</th>
                <th>Sessions</th>
                <th>Last Seen</th>
                <th>Joined</th>
              </tr>
            </thead>
            <tbody>
              ${overview.users.map(renderUserRow).join("")}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function metric(label, value) {
    return `<article class="metric"><span>${escapeHtml(label)}</span><strong>${number(value)}</strong></article>`;
  }

  function renderUserRow(user) {
    return `
      <tr>
        <td data-label="User">
          <div class="user-email">${escapeHtml(user.email)}</div>
          <div class="user-name">${escapeHtml(user.name || "")}</div>
        </td>
        <td data-label="Homes">${number(user.home_count)}</td>
        <td data-label="Shared">${number(user.shared_home_count)}</td>
        <td data-label="Items">${number(user.item_count)}</td>
        <td data-label="Plan">${renderPlanControl(user)}</td>
        <td data-label="Sessions">${number(user.active_session_count)}</td>
        <td class="date-cell" data-label="Last Seen">${formatDateTime(user.last_seen_at)}</td>
        <td class="date-cell" data-label="Joined">${formatDateTime(user.created_at)}</td>
      </tr>
    `;
  }

  function renderPlanControl(user) {
    const source = user.active_entitlement_source || "";
    const manualSource = source === "manual" || source === "promo" || source === "admin";
    const busy = state.updatingUserId === user.id;
    const controls = [];
    if (!source) {
      controls.push(`
        <button
          type="button"
          class="admin-button compact primary"
          data-action="make-paid"
          data-user-id="${escapeAttr(user.id)}"
          aria-label="Make ${escapeAttr(user.email || "this account")} paid"
          ${state.loading ? "disabled" : ""}
        >Make Paid</button>
      `);
    } else if (manualSource) {
      controls.push(`
        <button
          type="button"
          class="admin-button compact danger"
          data-action="make-free"
          data-user-id="${escapeAttr(user.id)}"
          aria-label="Make ${escapeAttr(user.email || "this account")} free"
          ${state.loading ? "disabled" : ""}
        >Make Free</button>
      `);
    } else {
      controls.push(`<span class="plan-note">Managed by App Store</span>`);
    }

    return `
      <div class="plan-cell">
        ${renderEntitlement(user)}
        <div class="plan-controls">
          ${busy ? `<span class="plan-note" role="status">Updating…</span>` : controls.join("")}
        </div>
      </div>
    `;
  }

  function renderEntitlement(user) {
    if (!user.active_entitlement_source) return `<span class="pill empty">Free</span>`;
    const suffix = user.active_entitlement_expires_at ? ` until ${formatDate(user.active_entitlement_expires_at)}` : "";
    return `<span class="pill">${escapeHtml(titleCase(user.active_entitlement_source))}${escapeHtml(suffix)}</span>`;
  }

  function findOverviewUser(userId) {
    return state.overview?.users?.find((user) => user.id === userId) || null;
  }

  function renderGoogleButton() {
    const host = document.querySelector("[data-google-sign-in-host]");
    if (!host || !window.google?.accounts?.id) return;
    const clientId = host.dataset.clientId;
    if (!clientId || host.dataset.rendered === "true") return;
    window.google.accounts.id.initialize({
      client_id: clientId,
      callback: signInWithGoogle,
    });
    window.google.accounts.id.renderButton(host, {
      theme: "outline",
      size: "large",
      type: "standard",
      shape: "pill",
      text: "signin_with",
      logo_alignment: "center",
      width: Math.max(Math.round(host.getBoundingClientRect().width || 320), 240),
    });
    host.dataset.rendered = "true";
  }

  function number(value) {
    const parsed = Number(value || 0);
    return Number.isFinite(parsed) ? parsed.toLocaleString() : "0";
  }

  function formatDateTime(value) {
    if (!value) return "Never";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "Never";
    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    }).format(date);
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(date);
  }

  function titleCase(value) {
    return String(value || "")
      .replaceAll("_", " ")
      .replace(/\b\w/g, (letter) => letter.toUpperCase());
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

  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-action]");
    const action = target?.dataset.action;
    if (!action) return;
    event.preventDefault();
    if (action === "refresh") {
      void loadOverview();
    }
    if (action === "sign-out") {
      clearAuth();
      render();
      void loadAuthConfig();
    }
    if (action === "apple-sign-in") {
      void signInWithApple();
    }
    if (action === "make-paid") {
      const userId = target.dataset.userId;
      if (userId) void updateManualEntitlement(userId, true);
    }
    if (action === "make-free") {
      const userId = target.dataset.userId;
      if (userId) void updateManualEntitlement(userId, false);
    }
  });

  render();
  if (state.token) {
    void loadOverview();
  } else {
    void loadAuthConfig();
  }
})();

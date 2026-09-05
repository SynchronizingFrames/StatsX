/* StatsX site -- shared client for the Accounts API. No dependencies. */
(function () {
  "use strict";

  // ===== CONFIG (cam edits these) ==========================================
  // 1) Your Cloudflare Worker URL (no trailing slash). Shown on the Worker's overview page.
  var API_URL = "https://statsx-api.YOURNAME.workers.dev";
  // 2) Your work.ink link. In the work.ink dashboard set its DESTINATION URL to:
  //      https://synchronizingframes.github.io/StatsX/account.html?token={TOKEN}
  var WORK_INK_URL = "https://work.ink/2EPc/statsx-key-12hr";
  // 3) The loader users paste into their executor (your obfuscated StatsX gist).
  var LOADER_URL = "https://gist.githubusercontent.com/SynchronizingFrames/738ff6965f638c29de79af05fb8ccd7d/raw/StatsX.obf.lua";
  // ========================================================================

  var SESSION_KEY = "sx_session";
  var PENDING_KEY = "sx_pending_token";

  function store(kind) { try { return kind === "session" ? window.sessionStorage : window.localStorage; } catch (e) { return null; } }
  function getSession() { var s = store("local"); return s ? s.getItem(SESSION_KEY) : null; }
  function setSession(v) { var s = store("local"); if (!s) return; if (v) s.setItem(SESSION_KEY, v); else s.removeItem(SESSION_KEY); }
  function getPending() { var s = store("session"); return s ? s.getItem(PENDING_KEY) : null; }
  function setPending(v) { var s = store("session"); if (!s) return; if (v) s.setItem(PENDING_KEY, v); else s.removeItem(PENDING_KEY); }

  function configured() { return !/YOURNAME/.test(API_URL); }

  function request(method, path, body, extraHeaders) {
    if (!configured()) {
      return Promise.resolve({ status: 0, data: { ok: false, error: "not_configured", message: "The site is not connected to an API yet. Set API_URL in api.js." } });
    }
    var headers = { "accept": "application/json" };
    if (body !== undefined) headers["content-type"] = "application/json";
    var sess = getSession();
    if (sess) headers["authorization"] = "Bearer " + sess;
    if (extraHeaders) for (var k in extraHeaders) if (extraHeaders.hasOwnProperty(k)) headers[k] = extraHeaders[k];
    var ctrl = ("AbortController" in window) ? new AbortController() : null;
    var timer = ctrl ? setTimeout(function () { ctrl.abort(); }, 15000) : null;
    return fetch(API_URL + path, { method: method, headers: headers, body: body !== undefined ? JSON.stringify(body) : undefined, signal: ctrl ? ctrl.signal : undefined })
      .then(function (res) {
        return res.text().then(function (txt) {
          var data = null;
          try { data = JSON.parse(txt); } catch (e) { data = { ok: false, error: "bad_response", message: "The server sent an unreadable reply (" + res.status + ")." }; }
          if (res.status === 401 && data && /session/.test(data.error || "")) setSession(null);
          return { status: res.status, data: data };
        });
      })
      .catch(function () {
        return { status: 0, data: { ok: false, error: "network", message: "Could not reach the StatsX server. Check your connection or try again in a moment." } };
      })
      .then(function (r) { if (timer) clearTimeout(timer); return r; });
  }

  var api = {
    URL: API_URL,
    WORK_INK_URL: WORK_INK_URL,
    LOADER_URL: LOADER_URL,
    configured: configured,
    session: { get: getSession, set: setSession, clear: function () { setSession(null); } },
    pending: { get: getPending, set: setPending, clear: function () { setPending(null); } },

    health: function () { return request("GET", "/v1/health"); },
    stats: function () { return request("GET", "/v1/stats"); },
    register: function (username, password) { return request("POST", "/v1/register", { username: username, password: password }); },
    login: function (username, password) { return request("POST", "/v1/login", { username: username, password: password }); },
    me: function () { return request("GET", "/v1/me"); },
    claim: function (token) { return request("POST", "/v1/claim", { token: token }); },
    resetDevice: function () { return request("POST", "/v1/key/reset-device", {}); },
    changePassword: function (current, next) { return request("POST", "/v1/password", { current: current, next: next }); },
    admin: {
      overview: function (key, q) { return request("GET", "/v1/admin/overview" + (q ? "?q=" + encodeURIComponent(q) : ""), undefined, { "x-admin-key": key }); },
      action: function (key, body) { return request("POST", "/v1/admin/action", body, { "x-admin-key": key }); }
    },

    // ---- formatting helpers ----
    pad2: function (n) { return (n < 10 ? "0" : "") + n; },
    hms: function (ms) {
      if (!ms || ms < 0) ms = 0;
      var s = Math.floor(ms / 1000);
      return api.pad2(Math.floor(s / 3600)) + ":" + api.pad2(Math.floor((s % 3600) / 60)) + ":" + api.pad2(s % 60);
    },
    ago: function (ts, now) {
      if (!ts) return "never";
      var d = Math.max(0, (now || Date.now()) - ts), s = Math.floor(d / 1000);
      if (s < 45) return "just now";
      var m = Math.floor(s / 60); if (m < 60) return m + "m ago";
      var h = Math.floor(m / 60); if (h < 48) return h + "h ago";
      var dd = Math.floor(h / 24); if (dd < 30) return dd + "d ago";
      return api.date(ts);
    },
    date: function (ts) {
      if (!ts) return "--";
      var d = new Date(ts);
      var M = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return d.getDate() + " " + M[d.getMonth()] + " " + d.getFullYear();
    },
    time: function (ts) {
      if (!ts) return "--:--";
      var d = new Date(ts);
      return api.pad2(d.getHours()) + ":" + api.pad2(d.getMinutes());
    },
    datetime: function (ts) { return ts ? api.date(ts) + " " + api.time(ts) : "--"; },
    initials: function (name) { return (name || "?").replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase() || "?"; },
    esc: function (s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); },
    copy: function (text) {
      if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(text).then(function () { return true; }, function () { return false; });
      try {
        var ta = document.createElement("textarea"); ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.appendChild(ta); ta.select(); var ok = document.execCommand("copy"); document.body.removeChild(ta);
        return Promise.resolve(!!ok);
      } catch (e) { return Promise.resolve(false); }
    },
    // Pull a work.ink token out of the address bar (destination = account.html?token={TOKEN}) and stash it.
    captureToken: function () {
      var q = location.search || "";
      if (!q) return null;
      var m = /[?&](?:token|key|t)=([^&#]+)/i.exec(q);
      var token = m ? decodeURIComponent(m[1]) : null;
      if (!token) {
        // work.ink may put the token in a param we did not predict: accept a lone unknown param that looks like a token.
        var parts = q.slice(1).split("&");
        if (parts.length === 1) { var kv = parts[0].split("="); var v = decodeURIComponent(kv[1] || kv[0] || ""); if (/^[A-Za-z0-9_\-]{8,}$/.test(v)) token = v; }
      }
      if (token) {
        setPending(token);
        try { history.replaceState(null, "", location.pathname); } catch (e) {}
      }
      return token;
    }
  };

  window.StatsXAPI = api;
})();

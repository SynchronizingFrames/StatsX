/* StatsX account page: auth, dashboard, key claim, countdown. Depends on api.js (window.StatsXAPI). */
(function () {
  "use strict";
  var API = window.StatsXAPI;
  var $ = function (id) { return document.getElementById(id); };
  var html = document.documentElement;
  html.classList.add("js");
  // reveal headline (same choreography as the home page)
  var readyDone = false;
  function ready() { if (readyDone) return; readyDone = true; html.classList.add("ready"); }
  requestAnimationFrame(function () { requestAnimationFrame(ready); });
  setTimeout(ready, 1200);

  // ---------- state ----------
  var me = null;            // last /v1/me payload
  var skew = 0;             // server_now - client_now
  var tick = null;          // countdown interval
  var mode = "login";       // auth tab
  var claiming = false;

  var views = { auth: $("viewAuth"), dash: $("viewDash"), loading: $("viewLoading") };
  function show(which) {
    for (var k in views) if (views.hasOwnProperty(k)) views[k].hidden = (k !== which);
    $("navAuth").textContent = which === "dash" ? "Account" : "Log in";
    html.classList.toggle("is-dash", which === "dash");
  }
  function serverNow() { return Date.now() + skew; }

  // ---------- clock in header ----------
  (function clock() {
    var el = $("utcClock");
    function t() { var d = new Date(); el.textContent = API.pad2(d.getUTCHours()) + ":" + API.pad2(d.getUTCMinutes()) + ":" + API.pad2(d.getUTCSeconds()); }
    t(); setInterval(t, 1000);
  })();

  // ---------- work.ink return: token in URL ----------
  var arrivedToken = API.captureToken();
  if (arrivedToken) $("pendingNote").hidden = false;
  if (API.pending.get()) $("pendingNote").hidden = false;

  // Real account count from the API. Stays hidden if the API is unreachable -- never a fake number.
  if (API.configured()) {
    API.stats().then(function (r) {
      if (r && r.data && r.data.ok && typeof r.data.users === "number") {
        $("factAccountsN").textContent = String(r.data.users);
        $("factAccounts").hidden = false;
      }
    });
  }

  // ---------- auth tabs ----------
  var tabs = document.querySelectorAll(".tab");
  function setMode(m) {
    mode = m;
    for (var i = 0; i < tabs.length; i++) tabs[i].classList.toggle("on", tabs[i].getAttribute("data-tab") === m);
    $("authSubmit").innerHTML = (m === "login" ? "Log in" : "Create account") + ' <span aria-hidden="true">&#8599;</span>';
    $("fPass").setAttribute("autocomplete", m === "login" ? "current-password" : "new-password");
    $("pwHint").textContent = m === "login" ? "for this site only" : "new, 8+ chars, never your Roblox one";
    $("authFoot").textContent = m === "login"
      ? "Your key only works in-game on this exact Roblox account. Never reuse your Roblox password."
      : "We check the username exists on Roblox. Pick a password you do not use anywhere else.";
    hideErr("authErr");
  }
  for (var i = 0; i < tabs.length; i++) tabs[i].addEventListener("click", function () { setMode(this.getAttribute("data-tab")); });

  $("pwToggle").addEventListener("click", function () {
    var f = $("fPass"); var vis = f.type === "text"; f.type = vis ? "password" : "text"; this.textContent = vis ? "show" : "hide";
  });

  function showErr(id, msg) { var e = $(id); e.textContent = msg; e.hidden = false; }
  function hideErr(id) { var e = $(id); e.hidden = true; e.textContent = ""; }
  function busy(btn, on, label) {
    btn.disabled = on; btn.classList.toggle("busy", on);
    if (label !== undefined) btn.innerHTML = label;
  }

  // ---------- auth submit ----------
  $("authForm").addEventListener("submit", function (ev) {
    ev.preventDefault();
    hideErr("authErr");
    var u = $("fUser").value.trim().replace(/^@/, "");
    var p = $("fPass").value;
    if (!/^[A-Za-z0-9_]{3,20}$/.test(u)) return showErr("authErr", "Enter your exact Roblox username (3-20 letters, numbers, one underscore).");
    if (p.length < 8) return showErr("authErr", "Password needs at least 8 characters.");
    if (!API.configured()) return showErr("authErr", "This site is not connected to its API yet (API_URL in api.js).");
    var btn = $("authSubmit"); var old = btn.innerHTML;
    busy(btn, true, mode === "login" ? "Checking&hellip;" : "Creating&hellip;");
    $("authStatus").textContent = mode === "login" ? "AUTH" : "REGISTER";
    (mode === "login" ? API.login(u, p) : API.register(u, p)).then(function (r) {
      busy(btn, false, old);
      if (!r.data.ok) { $("authStatus").textContent = "DENIED"; return showErr("authErr", r.data.message || "Something went wrong."); }
      API.session.set(r.data.session);
      $("authStatus").textContent = "OK";
      $("fPass").value = "";
      applyMe(r.data.me);
      show("dash");
      maybeClaim();
    });
  });

  // ---------- sign out / password ----------
  $("btnOut").addEventListener("click", function () {
    API.session.clear(); me = null; stopTick(); show("auth"); setMode("login"); $("fUser").value = "";
  });
  $("btnPw").addEventListener("click", function () { var p = $("pwPanel"); p.hidden = !p.hidden; if (!p.hidden) $("pwCur").focus(); });
  $("pwForm").addEventListener("submit", function (ev) {
    ev.preventDefault(); hideErr("pwErr");
    var cur = $("pwCur").value, nxt = $("pwNew").value;
    if (nxt.length < 8) return showErr("pwErr", "New password needs at least 8 characters.");
    var btn = $("pwSubmit"); busy(btn, true, "Saving&hellip;");
    API.changePassword(cur, nxt).then(function (r) {
      busy(btn, false, "Change");
      if (!r.data.ok) return showErr("pwErr", r.data.message || "Could not change password.");
      API.session.set(r.data.session);
      $("pwCur").value = ""; $("pwNew").value = ""; $("pwPanel").hidden = true;
      applyMe(r.data.me);
      toast("Password changed. Other sessions were signed out.");
    });
  });

  // ---------- key card ----------
  function stage(name) {
    var card = $("keyCard"); card.setAttribute("data-stage", name);
    var st = card.querySelectorAll(".stage");
    for (var i = 0; i < st.length; i++) st[i].hidden = !st[i].classList.contains("stage-" + name);
  }

  $("btnGet").addEventListener("click", function () {
    // Nothing to fake here: work.ink sends the user back with ?token=... which the server verifies.
    $("keyBarRight").textContent = "WAITING FOR CHECKPOINT";
  });

  $("btnCopy").addEventListener("click", function () {
    var b = this; API.copy($("keyValue").textContent).then(function (ok) { b.textContent = ok ? "Copied" : "Select + copy"; b.classList.add("did"); setTimeout(function () { b.textContent = "Copy key"; b.classList.remove("did"); }, 1600); });
  });
  $("btnCopyLoader").addEventListener("click", function () {
    var b = this; API.copy($("loaderCode").textContent).then(function (ok) { b.textContent = ok ? "copied" : "select + copy"; b.classList.add("did"); setTimeout(function () { b.textContent = "copy"; b.classList.remove("did"); }, 1600); });
  });
  $("btnReset").addEventListener("click", function () {
    if (!me || !me.key) return;
    if (!me.key.hwid_bound) return toast("Nothing to reset. The key binds to the first PC that unlocks with it.");
    if (!confirm("Unbind this key from its current PC? You have " + me.key.resets_left + " reset" + (me.key.resets_left === 1 ? "" : "s") + " left on this key.")) return;
    var b = this; b.disabled = true;
    API.resetDevice().then(function (r) {
      b.disabled = false;
      if (!r.data.ok) return toast(r.data.message || "Could not reset device.");
      applyMe(r.data.me); toast("Device unbound. The next PC that unlocks becomes the bound one.");
    });
  });
  $("btnRetry").addEventListener("click", function () { $("retryWrap").hidden = true; hideErr("keyErr"); $("keyBarRight").textContent = "NO ACTIVE KEY"; stage("none"); });

  function logLine(text, ok) {
    var li = document.createElement("li"); li.textContent = text; if (ok) li.className = "ok";
    $("claimLog").appendChild(li); return li;
  }
  var scrambleTimer = null;
  function scramble(on) {
    var el = $("scramble"), A = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    if (scrambleTimer) { clearInterval(scrambleTimer); scrambleTimer = null; }
    if (!on) return;
    scrambleTimer = setInterval(function () {
      var s = "STATSX"; for (var g = 0; g < 3; g++) { s += "-"; for (var c = 0; c < 4; c++) s += A[Math.floor(Math.random() * A.length)]; }
      el.textContent = s;
    }, 60);
  }

  function maybeClaim() {
    var token = API.pending.get();
    if (!token || !me || claiming) return;
    if (me.key) { API.pending.clear(); toast("You already have an active key. The checkpoint was not needed."); return; }
    claiming = true;
    $("keyBarRight").textContent = "VERIFYING";
    $("claimLog").innerHTML = ""; hideErr("keyErr"); $("retryWrap").hidden = true;
    stage("claim"); scramble(true);
    var l1 = logLine("checkpoint token received from work.ink");
    var l2 = null, l3 = null;
    var started = Date.now();
    setTimeout(function () { l1.className = "ok"; l2 = logLine("asking work.ink to confirm and burn the token"); }, 350);
    API.claim(token).then(function (r) {
      var wait = Math.max(0, 1400 - (Date.now() - started));
      setTimeout(function () {
        claiming = false;
        if (l2) l2.className = "ok";
        if (!r.data.ok) {
          scramble(false);
          $("scramble").textContent = "STATSX-----------------";
          logLine("rejected: " + (r.data.error || "unknown"));
          showErr("keyErr", r.data.message || "Checkpoint could not be verified.");
          $("retryWrap").hidden = false;
          $("keyBarRight").textContent = "REJECTED";
          if (r.data.error !== "workink_unavailable" && r.data.error !== "network") API.pending.clear();
          return;
        }
        API.pending.clear();
        l3 = logLine(r.data.reused ? "active key already on the account" : "random key generated and tied to @" + me.username, true);
        setTimeout(function () {
          scramble(false);
          applyMe(r.data.me);
          $("keyCard").classList.add("pop"); setTimeout(function () { $("keyCard").classList.remove("pop"); }, 900);
        }, 500);
      }, wait);
    });
  }

  // ---------- render ----------
  function applyMe(m) {
    if (!m) return;
    me = m;
    if (typeof m.now === "number") skew = m.now - Date.now();
    var dn = m.display_name || m.username;
    $("dispName").textContent = dn;
    $("handle").textContent = "@" + m.username;
    $("planBadge").textContent = (m.plan_label || "Free key").toUpperCase();
    $("planBadge").className = "badge mono" + (m.plan !== "free" ? " badge-hi" : "") + (m.banned ? " badge-bad" : "");
    if (m.banned) $("planBadge").textContent = "BANNED";
    $("rbxLine").textContent = m.roblox_id ? "roblox id " + m.roblox_id + " \u00b7 verified" : "roblox id not verified";
    $("avatarText").textContent = API.initials(m.username);
    var img = $("avatarImg");
    if (m.avatar_url) { img.src = m.avatar_url; img.hidden = false; img.onerror = function () { img.hidden = true; }; } else img.hidden = true;
    $("noneUser").textContent = "@" + m.username;
    $("useUser").textContent = "@" + m.username;
    $("keyHours").textContent = m.key_hours || 12;
    if (m.workink_url) $("btnGet").href = m.workink_url; else $("btnGet").href = API.WORK_INK_URL;
    $("loaderCode").textContent = 'loadstring(game:HttpGet("' + API.LOADER_URL + '"))()';

    $("stSince").textContent = API.date(m.created_at);
    $("stClaims").textContent = m.claim_count || 0;
    $("stLogins").textContent = m.login_count || 0;
    $("stLast").textContent = API.ago(m.last_login_at, serverNow());

    renderEvents(m.events || []);

    if (m.key) {
      var k = m.key;
      $("keyValue").textContent = k.key;
      $("kvUses").textContent = k.uses;
      $("kvIssued").textContent = API.datetime(k.created_at);
      $("kvExpires").textContent = k.never_expires ? "never" : API.datetime(k.expires_at);
      $("kvDevice").textContent = k.hwid_bound ? "bound " + API.ago(k.hwid_at, serverNow()) : "not bound yet";
      $("kvDevice").className = k.hwid_bound ? "ok" : "";
      $("resetNote").textContent = k.resets_left + " reset" + (k.resets_left === 1 ? "" : "s") + " left";
      $("btnReset").disabled = k.resets_left <= 0;
      $("keyBarRight").textContent = k.never_expires ? "ACTIVE \u00b7 NEVER EXPIRES" : "ACTIVE";
      $("keyFoot").textContent = k.source === "admin"
        ? "This key was granted by the owner."
        : k.source === "gift"
          ? "This key came from a gift code (" + (k.duration_label || "") + "). It is tied to @" + m.username + "."
          : "Keep this private. The key is tied to @" + m.username + " and locks to the first PC that unlocks with it.";
      stage("key");
      startTick();
    } else {
      stopTick();
      if (!claiming) { stage("none"); $("keyBarRight").textContent = "NO ACTIVE KEY"; }
      $("keyFoot").textContent = "A new key can be claimed the moment the current one expires.";
    }
  }

  var EV = {
    register: "account created", login: "logged in", login_failed: "failed login attempt", claim: "key claimed", claim_failed: "checkpoint rejected",
    unlock: "unlocked in game", unlock_blocked: "unlock blocked (other device)", device_reset: "device reset", password_change: "password changed",
    ban: "account banned", unban: "ban lifted", revoke: "key revoked", grant: "key granted by owner", plan: "plan changed", redeem: "gift code redeemed", redeem_failed: "gift code rejected"
  };
  function renderEvents(list) {
    var ul = $("actList"); ul.innerHTML = "";
    $("actCount").textContent = list.length ? list.length + " recent" : "";
    if (!list.length) { ul.innerHTML = '<li class="empty mono">nothing yet</li>'; return; }
    for (var i = 0; i < list.length; i++) {
      var e = list[i], li = document.createElement("li");
      var label = EV[e.type] || e.type.replace(/_/g, " ");
      if (e.type === "grant" && e.meta && (e.meta.label || e.meta.hours)) label += " (" + (e.meta.label || e.meta.hours + "h") + ")";
      if (e.type === "redeem" && e.meta && e.meta.label) label += " (" + e.meta.label + ")";
      if (e.type === "plan" && e.meta && e.meta.plan) label += " \u2192 " + e.meta.plan;
      var bad = /failed|blocked|ban$|revoke/.test(e.type), good = /^(claim|unlock|grant|unban|register|redeem)$/.test(e.type);
      li.innerHTML = '<i class="' + (bad ? "bad" : good ? "good" : "") + '"></i><span>' + API.esc(label) + '</span><time class="mono">' + API.esc(API.ago(e.at, serverNow())) + "</time>";
      ul.appendChild(li);
    }
  }

  function startTick() {
    stopTick();
    // A key with no expiry has nothing to count down.
    if (me && me.key && me.key.never_expires) {
      $("keyLeft").textContent = "never";
      $("keyBar").style.width = "100%";
      var pr = $("keyProgress"); if (pr) pr.classList.add("full");
      return;
    }
    var pr2 = $("keyProgress"); if (pr2) pr2.classList.remove("full");
    function step() {
      if (!me || !me.key) return stopTick();
      var left = me.key.expires_at - serverNow();
      var total = me.key.expires_at - me.key.created_at;
      $("keyLeft").textContent = API.hms(left);
      $("keyBar").style.width = Math.max(0, Math.min(100, (left / total) * 100)).toFixed(2) + "%";
      if (left <= 0) { stopTick(); refresh(); }
    }
    step(); tick = setInterval(step, 1000);
  }
  function stopTick() { if (tick) { clearInterval(tick); tick = null; } }

  // ---------- gift code redeem ----------
  $("redeemForm").addEventListener("submit", function (ev) {
    ev.preventDefault();
    hideErr("redeemErr");
    var input = $("redeemCode");
    var code = input.value.trim().toUpperCase().replace(/\s+/g, "");
    if (!/^STATSX-GIFT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) {
      return showErr("redeemErr", "Gift codes look like STATSX-GIFT-XXXX-XXXX-XXXX.");
    }
    var btn = $("redeemSubmit");
    busy(btn, true, "Checking\u2026");
    API.redeem(code).then(function (r) {
      busy(btn, false, "Redeem");
      if (!r.data.ok) return showErr("redeemErr", r.data.message || "That code could not be redeemed.");
      input.value = "";
      applyMe(r.data.me);
      $("keyCard").classList.add("pop");
      setTimeout(function () { $("keyCard").classList.remove("pop"); }, 900);
      toast("Gift code accepted \u00b7 " + (r.data.label || "key issued"));
    });
  });

  // ---------- toast ----------
  var toastTimer = null;
  function toast(msg) {
    var t = $("toast");
    if (!t) { t = document.createElement("div"); t.id = "toast"; t.className = "toast mono"; document.body.appendChild(t); }
    t.textContent = msg; t.classList.add("on");
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.classList.remove("on"); }, 3600);
  }

  // ---------- boot ----------
  function refresh() {
    return API.me().then(function (r) {
      if (r.data.ok) { applyMe(r.data.me); show("dash"); maybeClaim(); return true; }
      if (r.data.error === "network" || r.data.error === "not_configured") {
        show("auth"); showErr("authErr", r.data.message); return false;
      }
      API.session.clear(); show("auth"); return false;
    });
  }

  setMode("login");
  if (!API.configured()) {
    show("auth");
    showErr("authErr", "This site is not connected to its API yet. Set API_URL in api.js (see README).");
  } else if (API.session.get()) {
    show("loading");
    refresh();
  } else {
    show("auth");
  }

  // Refresh on return to tab so the countdown never drifts far from the server.
  document.addEventListener("visibilitychange", function () { if (!document.hidden && me && API.session.get()) refresh(); });
})();

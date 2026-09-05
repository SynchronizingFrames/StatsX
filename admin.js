/* StatsX owner panel. Depends on api.js. The admin key lives in sessionStorage for this tab only. */
(function () {
  "use strict";
  var API = window.StatsXAPI;
  var $ = function (id) { return document.getElementById(id); };
  var KEY = "sx_admin_key";
  var data = null, timer = null;

  document.documentElement.classList.add("js");
  requestAnimationFrame(function () { requestAnimationFrame(function () { document.documentElement.classList.add("ready"); }); });
  setTimeout(function () { document.documentElement.classList.add("ready"); }, 1200);
  try { $("apiHost").textContent = API.configured() ? new URL(API.URL).host : "api not configured"; } catch (e) {}

  (function clock() {
    var el = $("utcClock");
    function t() { var d = new Date(); el.textContent = API.pad2(d.getUTCHours()) + ":" + API.pad2(d.getUTCMinutes()) + ":" + API.pad2(d.getUTCSeconds()); }
    t(); setInterval(t, 1000);
  })();

  function adminKey() { try { return sessionStorage.getItem(KEY); } catch (e) { return null; } }
  function setAdminKey(v) { try { if (v) sessionStorage.setItem(KEY, v); else sessionStorage.removeItem(KEY); } catch (e) {} }
  function showErr(id, msg) { var e = $(id); e.textContent = msg; e.hidden = false; }
  function hideErr(id) { var e = $(id); e.hidden = true; }

  function lock() { setAdminKey(null); $("panel").hidden = true; $("gate").hidden = false; if (timer) { clearInterval(timer); timer = null; } $("gateKey").value = ""; }
  function open() { $("gate").hidden = true; $("panel").hidden = false; load(); if (!timer) timer = setInterval(load, 20000); }

  $("btnLock").addEventListener("click", lock);
  $("gateForm").addEventListener("submit", function (ev) {
    ev.preventDefault(); hideErr("gateErr");
    var k = $("gateKey").value.trim();
    if (!k) return showErr("gateErr", "Paste the ADMIN_KEY you set on the Worker.");
    if (!API.configured()) return showErr("gateErr", "Set API_URL in api.js first.");
    API.admin.overview(k, "").then(function (r) {
      if (!r.data.ok) return showErr("gateErr", r.data.message || "Rejected.");
      setAdminKey(k); render(r.data); open();
    });
  });
  $("btnRefresh").addEventListener("click", load);
  var qTimer = null;
  $("q").addEventListener("input", function () { if (qTimer) clearTimeout(qTimer); qTimer = setTimeout(load, 250); });

  function load() {
    var k = adminKey(); if (!k) return lock();
    hideErr("panelErr");
    API.admin.overview(k, $("q").value.trim()).then(function (r) {
      if (!r.data.ok) { if (r.data.error === "bad_admin_key" || r.data.error === "no_admin_key") return lock(); return showErr("panelErr", r.data.message || "Load failed."); }
      render(r.data);
    });
  }

  function fmtLeft(exp, nowTs) { var l = exp - nowTs; return l > 0 ? API.hms(l) : "--"; }

  function render(d) {
    data = d;
    var nowTs = (d.stats && d.stats.time) || Date.now();
    $("sUsers").textContent = d.stats.users; $("sActive").textContent = d.stats.active_keys;
    $("sUnlocks").textContent = d.stats.unlocks_24h; $("sKeys").textContent = d.stats.keys_total;
    $("sHours").textContent = d.config.key_hours + "h"; $("sMotd").textContent = d.config.motd || "(none)";
    $("sCodes").textContent = (d.voucher_stats && d.voucher_stats.open) || 0;
    renderVouchers(d.vouchers || [], nowTs);

    var tb = $("uBody"); tb.innerHTML = "";
    $("uCount").textContent = d.users.length + (d.users.length === 200 ? "+" : "");
    if (!d.users.length) tb.innerHTML = '<tr><td colspan="7" class="empty mono">no accounts match</td></tr>';
    for (var i = 0; i < d.users.length; i++) {
      var u = d.users[i], tr = document.createElement("tr");
      if (u.banned) tr.className = "banned";
      var keyCell = u.key_expires_at && u.key_expires_at > nowTs ? '<span class="ok mono">' + fmtLeft(u.key_expires_at, nowTs) + "</span>" : '<span class="dim mono">none</span>';
      var dev = u.key_expires_at && u.key_expires_at > nowTs ? (u.key_bound ? "bound \u00b7 " + (u.key_uses || 0) + " uses" : "unbound") : "--";
      tr.innerHTML =
        '<td><div class="u">' + (u.avatar_url ? '<img src="' + API.esc(u.avatar_url) + '" alt="">' : '<i class="mono">' + API.esc(API.initials(u.username)) + "</i>") +
        "<div><b>" + API.esc(u.display_name || u.username) + '</b><span class="mono">@' + API.esc(u.username) + (u.roblox_id ? " \u00b7 " + u.roblox_id : " \u00b7 unverified") + "</span></div></div></td>" +
        '<td><span class="badge mono' + (u.plan !== "free" ? " badge-hi" : "") + (u.banned ? " badge-bad" : "") + '">' + API.esc(u.banned ? "BANNED" : u.plan.toUpperCase()) + "</span></td>" +
        "<td>" + keyCell + "</td>" +
        '<td class="mono small">' + API.esc(dev) + "</td>" +
        '<td class="mono">' + (u.login_count || 0) + "</td>" +
        '<td class="mono small">' + API.esc(API.ago(u.last_login_at, nowTs)) + "</td>" +
        '<td class="acts">' +
          (u.banned ? btn("unban", u.username, "Unban") : btn("ban", u.username, "Ban")) +
          btn("revoke", u.username, "Revoke") + btn("reset_device", u.username, "Unbind") +
          btn("grant", u.username, "Grant") + btn("set_plan", u.username, "Plan") + btn("delete", u.username, "Delete", true) +
        "</td>";
      tb.appendChild(tr);
    }

    var ul = $("eList"); ul.innerHTML = "";
    $("eCount").textContent = d.events.length;
    if (!d.events.length) ul.innerHTML = '<li class="empty mono">nothing yet</li>';
    for (var j = 0; j < d.events.length; j++) {
      var e = d.events[j], li = document.createElement("li");
      var bad = /failed|blocked|^ban$|revoke/.test(e.type), good = /^(claim|unlock|grant|unban|register)$/.test(e.type);
      var extra = "";
      if (e.meta) {
        if (e.meta.reason) extra += " \u00b7 " + e.meta.reason;
        if (e.meta.hours && e.type === "grant") extra += " \u00b7 " + e.meta.hours + "h";
        if (e.meta.plan) extra += " \u00b7 " + e.meta.plan;
        if (e.meta.link) extra += " \u00b7 link " + e.meta.link;
        if (e.meta.ip) extra += " \u00b7 " + e.meta.ip;
        if (e.meta.by === "admin") extra += " \u00b7 by you";
      }
      li.innerHTML = '<i class="' + (bad ? "bad" : good ? "good" : "") + '"></i><span><b>@' + API.esc(e.username || "?") + "</b> " + API.esc(e.type.replace(/_/g, " ")) + '<em class="mono">' + API.esc(extra) + "</em></span><time class=\"mono\">" + API.esc(API.ago(e.at, nowTs)) + "</time>";
      ul.appendChild(li);
    }
  }
  function btn(action, user, label, danger) {
    return '<button type="button" class="mini mono' + (danger ? " danger" : "") + '" data-a="' + action + '" data-u="' + API.esc(user) + '">' + label + "</button>";
  }

  $("uBody").addEventListener("click", function (ev) {
    var b = ev.target.closest ? ev.target.closest("button[data-a]") : null;
    if (!b) return;
    var action = b.getAttribute("data-a"), user = b.getAttribute("data-u"), body = { action: action, username: user };
    if (action === "ban") { var r = prompt("Ban @" + user + "? Reason (optional):"); if (r === null) return; body.reason = r; }
    if (action === "grant") {
      var dur = prompt("Grant @" + user + " a key. Length: 12h / 1d / 7d / 1mo / 1y / 10y / 89y / inf", "1mo");
      if (dur === null) return;
      body.duration = dur.trim() || "1mo";
    }
    if (action === "set_plan") { var p = prompt("Plan for @" + user + " (free / vip / lifetime ...):", "vip"); if (p === null) return; body.plan = p.trim(); }
    if (action === "delete" && !confirm("Delete @" + user + " and all their keys? This cannot be undone.")) return;
    if (action === "revoke" && !confirm("Revoke @" + user + "'s active key?")) return;
    b.disabled = true;
    API.admin.action(adminKey(), body).then(function (r) {
      b.disabled = false;
      if (!r.data.ok) return showErr("panelErr", r.data.message || "Action failed.");
      load();
    });
  });

  // ---------- key generator ----------
  var lastCodes = [];

  function renderCodes(codes, label) {
    lastCodes = codes.slice();
    var ul = $("genList"); ul.innerHTML = "";
    $("genOutTitle").textContent = codes.length + (codes.length === 1 ? " CODE" : " CODES") + " \u00b7 " + label.toUpperCase();
    for (var i = 0; i < codes.length; i++) {
      var li = document.createElement("li");
      li.innerHTML = "<code>" + API.esc(codes[i]) + '</code><button type="button" class="mini mono" data-copy="' + API.esc(codes[i]) + '">Copy</button>';
      ul.appendChild(li);
    }
    $("genOut").hidden = false;
  }

  $("genList").addEventListener("click", function (ev) {
    var b = ev.target.closest ? ev.target.closest("button[data-copy]") : null;
    if (!b) return;
    API.copy(b.getAttribute("data-copy")).then(function (ok) {
      b.textContent = ok ? "Copied" : "Failed";
      b.classList.add("did");
      setTimeout(function () { b.textContent = "Copy"; b.classList.remove("did"); }, 1400);
    });
  });

  $("btnCopyAll").addEventListener("click", function () {
    var b = this;
    API.copy(lastCodes.join("\n")).then(function (ok) {
      b.textContent = ok ? "Copied" : "Failed";
      setTimeout(function () { b.textContent = "Copy all"; }, 1400);
    });
  });

  $("genForm").addEventListener("submit", function (ev) {
    ev.preventDefault(); hideErr("genErr");
    var k = adminKey(); if (!k) return lock();
    var btn = $("btnGen");
    var body = {
      duration: $("genDuration").value,
      count: parseInt($("genCount").value, 10) || 1,
      note: $("genNote").value.trim(),
    };
    btn.disabled = true; btn.classList.add("busy"); $("genBatch").textContent = "WORKING";
    API.admin.generate(k, body).then(function (r) {
      btn.disabled = false; btn.classList.remove("busy");
      if (!r.data.ok) { $("genBatch").textContent = "FAILED"; return showErr("genErr", r.data.message || "Could not generate codes."); }
      $("genBatch").textContent = "BATCH " + (r.data.batch || "");
      renderCodes(r.data.codes || [], r.data.label || "");
      $("genNote").value = "";
      load();
    });
  });

  function renderVouchers(list, nowTs) {
    var tb = $("vBody"); tb.innerHTML = "";
    $("vCount").textContent = list.length + (list.length === 120 ? "+" : "");
    if (!list.length) { tb.innerHTML = '<tr><td colspan="6" class="empty mono">no codes yet</td></tr>'; return; }
    for (var i = 0; i < list.length; i++) {
      var v = list[i], tr = document.createElement("tr");
      var status = v.revoked
        ? '<span class="badge mono badge-bad">CANCELLED</span>'
        : v.redeemed_at
          ? '<span class="badge mono">USED &middot; @' + API.esc(v.redeemed_username || "?") + "</span>"
          : '<span class="badge mono badge-hi">OPEN</span>';
      if (v.redeemed_at || v.revoked) tr.className = "used";
      tr.innerHTML =
        '<td><code class="mono code-cell">' + API.esc(v.code) + "</code></td>" +
        '<td class="mono">' + API.esc(v.label) + "</td>" +
        "<td>" + status + "</td>" +
        '<td class="mono small dim">' + API.esc(v.note || "--") + "</td>" +
        '<td class="mono small dim">' + API.esc(API.ago(v.created_at, nowTs)) + "</td>" +
        '<td class="acts">' +
          '<button type="button" class="mini mono" data-copy-code="' + API.esc(v.code) + '">Copy</button>' +
          (v.redeemed_at || v.revoked ? "" : '<button type="button" class="mini mono" data-c="cancel_code" data-code="' + API.esc(v.code) + '">Cancel</button>') +
          '<button type="button" class="mini mono danger" data-c="delete_code" data-code="' + API.esc(v.code) + '">Delete</button>' +
        "</td>";
      tb.appendChild(tr);
    }
  }

  $("vBody").addEventListener("click", function (ev) {
    var t = ev.target.closest ? ev.target : null;
    if (!t) return;
    var cp = t.closest("button[data-copy-code]");
    if (cp) {
      API.copy(cp.getAttribute("data-copy-code")).then(function (ok) {
        cp.textContent = ok ? "Copied" : "Failed";
        setTimeout(function () { cp.textContent = "Copy"; }, 1400);
      });
      return;
    }
    var b = t.closest("button[data-c]");
    if (!b) return;
    var action = b.getAttribute("data-c"), code = b.getAttribute("data-code");
    if (action === "delete_code" && !confirm("Delete " + code + " for good?")) return;
    if (action === "cancel_code" && !confirm("Cancel " + code + " so it can never be redeemed?")) return;
    b.disabled = true;
    API.admin.action(adminKey(), { action: action, code: code }).then(function (r) {
      b.disabled = false;
      if (!r.data.ok) return showErr("panelErr", r.data.message || "Action failed.");
      load();
    });
  });

  if (adminKey()) open(); else $("gate").hidden = false;
})();

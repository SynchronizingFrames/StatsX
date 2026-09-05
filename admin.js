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
    if (action === "grant") { var h = prompt("Grant @" + user + " a key for how many hours?", "24"); if (h === null) return; body.hours = parseInt(h, 10) || 24; }
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

  if (adminKey()) open(); else $("gate").hidden = false;
})();

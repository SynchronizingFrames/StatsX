/* StatsX owner panel: leak tracer.
   Paste a leaked copy of the TSB Hub. The server reads the hidden tags and says which key downloaded it. */
(function () {
  "use strict";
  var API_URL = (window.StatsXAPI && typeof window.StatsXAPI.URL === "string" && window.StatsXAPI.URL) || "https://statsx-api.discordflex911.workers.dev";
  API_URL = API_URL.replace(/\/+$/, "");
  var $ = function (id) { return document.getElementById(id); };
  var box = $("traceText"), btn = $("btnTrace"), out = $("traceOut"), err = $("traceErr"), state = $("traceState");
  if (!box || !btn || !out || !err) return;

  function adminKey() { try { return sessionStorage.getItem("sx_admin_key"); } catch (e) { return null; } }
  function post(body) {
    return fetch(API_URL + "/v1/admin/action", {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-key": adminKey() || "" },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.json().catch(function () { return { ok: false, message: "Bad reply from the server (" + r.status + ")." }; });
    }, function () {
      return { ok: false, message: "Could not reach the server. Check your connection." };
    });
  }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function when(ts) { if (!ts) return "--"; try { return new Date(ts).toISOString().replace("T", " ").slice(0, 16) + " UTC"; } catch (e) { return "--"; } }
  function showErr(msg) { err.textContent = msg; err.hidden = false; }
  function note(msg) { out.appendChild(el("p", "tiny mono", msg)); }

  function card(f) {
    var wrap = el("div", "mono");
    wrap.style.cssText = "border:1px solid rgba(255,255,255,.14);border-radius:8px;padding:12px;margin:12px 0 0;";
    if (f.missing) { wrap.appendChild(el("div", null, "Key #" + f.key_id + " downloaded this copy, but that key has been deleted.")); return wrap; }
    var who = el("div", null, "LEAKED BY: " + (f.username || "(deleted account)"));
    who.style.cssText = "font-weight:600;font-size:14px;margin-bottom:6px;";
    wrap.appendChild(who);
    var status = f.banned ? "account banned" : f.revoked ? "key revoked" : (f.expires_at && f.expires_at < Date.now() ? "key expired" : "key active");
    wrap.appendChild(el("div", "tiny", "Key " + f.key + "  \u00b7  " + status + "  \u00b7  key made " + when(f.created_at)));
    if (f.username && !f.banned) {
      var b = el("button", "btn btn-ghost", "Ban " + f.username);
      b.type = "button";
      b.style.marginTop = "10px";
      b.addEventListener("click", function () {
        if (!confirm("Ban " + f.username + "? This also kills their key.")) return;
        b.disabled = true; b.textContent = "Banning...";
        post({ action: "ban", username: f.username, reason: "Leaked the TSB Hub (key " + f.key + ")" }).then(function (r) {
          if (r.ok) { b.textContent = "Banned"; }
          else { b.disabled = false; b.textContent = "Ban " + f.username; showErr(r.message || "Ban failed."); }
        });
      });
      wrap.appendChild(b);
    }
    return wrap;
  }

  btn.addEventListener("click", function () {
    err.hidden = true; out.innerHTML = "";
    var text = box.value;
    if (!text.trim()) return showErr("Paste the leaked script first.");
    if (!adminKey()) return showErr("Unlock the panel with your admin key first.");
    btn.disabled = true; btn.textContent = "Tracing..."; if (state) state.textContent = "WORKING";
    post({ action: "trace", text: text }).then(function (r) {
      btn.disabled = false; btn.textContent = "Trace"; if (state) state.textContent = "READY";
      if (!r.ok) return showErr(r.message || "Trace failed.");
      if (!r.found || !r.found.length) {
        if (r.markers) note("Found " + r.markers + " tag(s), but none were made by your server. They are fake or damaged.");
        else note("No tag in this copy. Either it was downloaded before the tracer was turned on, or someone removed the tags.");
        return;
      }
      if (r.found.length > 1) note("This copy has tags from " + r.found.length + " different keys. Someone mixed copies, so check each one.");
      for (var i = 0; i < r.found.length; i++) out.appendChild(card(r.found[i]));
    });
  });
})();

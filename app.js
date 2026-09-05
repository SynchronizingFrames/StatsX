/* StatsX site -- home page motion + live numbers. Depends on api.js (window.StatsXAPI). */
(function () {
  "use strict";
  var API = window.StatsXAPI;
  var html = document.documentElement;
  html.classList.add("js");
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var $ = function (s, c) { return (c || document).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); };

  // ---- intro ------------------------------------------------------------
  function ready() { html.classList.add("ready"); }
  requestAnimationFrame(function () { requestAnimationFrame(ready); });
  setTimeout(ready, 1200); // never let the hero stay hidden if rAF is throttled

  // ---- scroll reveal (IntersectionObserver + safety net) ----------------
  var rv = $$(".rv");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.05 });
    rv.forEach(function (el, i) {
      el.style.transitionDelay = ((i % 3) * 70) + "ms";
      io.observe(el);
    });
  } else {
    rv.forEach(function (el) { el.classList.add("in"); });
  }
  setTimeout(function () { rv.forEach(function (el) { el.classList.add("in"); }); }, 1800);

  // ---- hero panel: mouse tilt + living switches --------------------------
  var tilt = $("#tilt"), panel = tilt && $(".panel", tilt), hero = $(".hero");
  if (tilt && panel && hero && !reduce && window.matchMedia && window.matchMedia("(pointer: fine)").matches) {
    hero.addEventListener("mousemove", function (e) {
      var r = tilt.getBoundingClientRect();
      var dx = (e.clientX - (r.left + r.width / 2)) / r.width;
      var dy = (e.clientY - (r.top + r.height / 2)) / r.height;
      panel.style.transform = "rotateX(" + (-dy * 7).toFixed(2) + "deg) rotateY(" + (dx * 9).toFixed(2) + "deg)";
    });
    hero.addEventListener("mouseleave", function () { panel.style.transform = ""; });
  }
  var switches = $$(".panel .sw");
  if (switches.length && !reduce) {
    setInterval(function () {
      var s = switches[Math.floor(Math.random() * switches.length)];
      s.classList.toggle("on");
    }, 2600);
  }

  // ---- macro timeline pulse ---------------------------------------------
  var steps = $$(".tl .step");
  if (steps.length && !reduce) {
    var si = 0;
    setInterval(function () {
      si = (si + 1) % steps.length;
      steps.forEach(function (s, i) { s.classList.toggle("hot", i === si); });
    }, 720);
  }

  // ---- UTC clock ---------------------------------------------------------
  var utcClock = $("#utcClock");
  function tick() {
    var now = new Date();
    if (utcClock) utcClock.textContent = API.pad2(now.getUTCHours()) + ":" + API.pad2(now.getUTCMinutes()) + ":" + API.pad2(now.getUTCSeconds());
  }
  tick();
  setInterval(tick, 1000);

  // ---- nav: reflect login state ------------------------------------------
  var navAuth = $("#navAuth");
  if (navAuth && API.session.get()) navAuth.textContent = "Account";

  // ---- live numbers from the server (only shown when the API is live) ----
  var liveLine = $("#liveLine");
  function countTo(el, n) {
    var from = parseInt(el.textContent, 10) || 0;
    if (reduce || from === n) { el.textContent = n; return; }
    var t0 = performance.now(), dur = 900;
    (function frame(t) {
      var p = Math.min(1, (t - t0) / dur); p = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(from + (n - from) * p);
      if (p < 1) requestAnimationFrame(frame);
    })(t0);
  }
  function loadStats() {
    if (!liveLine || !API.configured()) return;
    API.stats().then(function (r) {
      if (!r.data.ok) return;
      liveLine.hidden = false;
      countTo($("#liveActive"), r.data.active_keys || 0);
      countTo($("#liveUnlocks"), r.data.unlocks_24h || 0);
    });
  }
  loadStats();
  setInterval(loadStats, 60000);
})();

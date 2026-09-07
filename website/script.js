/* 一览 Yilan 官网交互 */
(function () {
  "use strict";

  /* ---- 手机样机：书签磁贴 ---- */
  var tiles = [
    { name: "知乎",     glyph: "知", c: "#0FA36B" },
    { name: "GitHub",  glyph: "G",  c: "#24292f" },
    { name: "B站",     glyph: "B",  c: "#E88FB4" },
    { name: "微博",    glyph: "微", c: "#D9435B" },
    { name: "少数派",  glyph: "派", c: "#D9432B" },
    { name: "豆瓣",    glyph: "豆", c: "#2B7AD9" },
    { name: "掘金",    glyph: "掘", c: "#1E80FF" },
    { name: "邮箱",    glyph: "邮", c: "#4353C4" }
  ];
  var grid = document.getElementById("pgrid");
  if (grid) {
    grid.innerHTML = tiles.map(function (t) {
      return '<div class="p-tile"><div class="p-tile-ico" style="--t:' + t.c + '">' + t.glyph + "</div>" +
        '<div class="p-tile-name">' + t.name + "</div></div>";
    }).join("");
  }

  /* ---- 导航滚动态 ---- */
  var nav = document.getElementById("nav");
  function onScroll() {
    nav.classList.toggle("scrolled", window.scrollY > 8);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---- 移动端抽屉 ---- */
  var burger = document.getElementById("burger");
  var drawer = document.getElementById("drawer");
  if (burger && drawer) {
    burger.addEventListener("click", function () {
      var open = drawer.classList.toggle("open");
      burger.setAttribute("aria-expanded", open ? "true" : "false");
      burger.setAttribute("aria-label", open ? "关闭菜单" : "打开菜单");
    });
    drawer.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        drawer.classList.remove("open");
        burger.setAttribute("aria-expanded", "false");
      }
    });
  }

  /* ---- 滚动显现 ---- */
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var reveals = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  }

  /* ---- 下载链接兜底：按最新 Release 的真实附件校正按钮 ---- */
  /* 静态直链 releases/latest/download/<固定名> 只在「最新正式 Release 挂了
     固定名附件」时有效；Release 断更或缺附件时按钮会 404。加载后向 GitHub
     API 求证一次：能解析到附件就改用真实地址，解析不到就退到 Release 页，
     保证按钮永不 404；API 不可用时保持静态直链不动。 */
  function pickAsset(assets, ext) {
    var fallback = null;
    for (var i = 0; i < assets.length; i++) {
      var a = assets[i] || {};
      var name = typeof a.name === "string" ? a.name.toLowerCase() : "";
      if (name.slice(-(ext.length + 1)) !== "." + ext) continue;
      if (name.indexOf("latest") === -1) return a.browser_download_url;
      if (!fallback) fallback = a.browser_download_url;
    }
    return fallback;
  }
  var dlApk = document.getElementById("dl-apk");
  var dlIpa = document.getElementById("dl-ipa");
  if (dlApk || dlIpa) {
    fetch("https://api.github.com/repos/rexleimo/yilang-browser/releases/latest", {
      headers: { Accept: "application/vnd.github+json" }
    }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rel) {
      if (!rel || !Array.isArray(rel.assets)) return;
      var page = typeof rel.html_url === "string" ? rel.html_url : null;
      if (dlApk) dlApk.href = pickAsset(rel.assets, "apk") || page || dlApk.href;
      if (dlIpa) dlIpa.href = pickAsset(rel.assets, "ipa") || page || dlIpa.href;
    }).catch(function () { /* 保持静态直链 */ });
  }
})();

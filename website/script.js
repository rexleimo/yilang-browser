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
})();

/// 广告拦截（EasyList 风格的轻量落地）。
///
/// webview_flutter 不暴露 shouldInterceptRequest，无法在网络层拦子资源，
/// 所以采取三层组合拳：
/// 1. 主框架导航拦截：onNavigationRequest 里对广告/跟踪域名直接 prevent
///    （挡弹窗广告、跳转中转页）。
/// 2. JS 元素清理：页面注入脚本，按 URL 特征移除广告 iframe/img/script，
///    按 CSS 特征隐藏常见广告容器，并用 MutationObserver 兜住懒加载节点。
/// 3. 弹窗封锁：覆写 window.open，广告域名返回 null。
///
/// 规则保持保守（低误杀）：域名用「注册域后缀」匹配，CSS 只选高置信度的
/// 广告容器类名/ID。
library;

/// 广告 / 跟踪域名后缀表（不含 scheme，匹配注册域后缀）。
const List<String> kAdHostSuffixes = <String>[
  // Google 系
  'doubleclick.net',
  'googlesyndication.com',
  'googletagservices.com',
  'googleadservices.com',
  'adservice.google.com',
  'google-analytics.com',
  'analytics.google.com',
  'scorecardresearch.com',
  // 百度系
  'hm.baidu.com',
  'pos.baidu.com',
  'cpro.baidu.com',
  'cpro.baidustatic.com',
  // 电商 / 联盟
  'alimama.com',
  'tanx.com',
  'mediav.com',
  'admaster.com.cn',
  'cnzz.com',
  'umeng.com',
  // 国际常见
  'adnxs.com',
  'adsrvr.org',
  'criteo.com',
  'outbrain.com',
  'taboola.com',
  'zedo.com',
  'pubmatic.com',
  'rubiconproject.com',
  'amazon-adsystem.com',
  'moatads.com',
  'hotjar.io',
  'appsflyer.com',
];

/// 高置信度广告容器 CSS 选择器（只藏明显广告位，避免误杀正文）。
const List<String> kAdCssSelectors = <String>[
  '.adsbygoogle',
  '#google_ads_iframe',
  'iframe[id^="google_ads_iframe"]',
  'iframe[src*="doubleclick"]',
  'iframe[src*="googlesyndication"]',
  '[id^="ad-"][id\$="-banner"]',
  '[class*="adsbygoogle"]',
  '[data-ad-slot]',
  '[data-google-query-id]',
  '.J_ad',
  '#BAIDU_SSP__wrapper',
];

/// 判断 URL 是否命中广告/跟踪域名（host 以表中后缀结尾）。
bool isAdUrl(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  for (final suffix in kAdHostSuffixes) {
    if (host == suffix || host.endsWith('.$suffix')) return true;
  }
  return false;
}

/// 生成注入页面的拦截脚本（IIFE，幂等：重复注入只生效一次）。
String adBlockerScript() {
  final hostList =
      kAdHostSuffixes.map((h) => "'$h'").join(',');
  final selectorList =
      kAdCssSelectors.map((s) => "'${s.replaceAll("'", r"\'")}'").join(',');
  return '''
(function(){
  if (window.__yilanAdBlock) return;
  window.__yilanAdBlock = true;
  var HOSTS = [$hostList];
  var SELECTORS = [$selectorList];
  function hostOf(u){
    try { return new URL(u, location.href).hostname.toLowerCase(); } catch(e){ return ''; }
  }
  function isAd(u){
    var h = hostOf(u);
    if (!h) return false;
    for (var i=0;i<HOSTS.length;i++){
      var d = HOSTS[i];
      if (h === d || h.slice(-(d.length+1)) === '.'+d) return true;
    }
    return false;
  }
  function purge(root){
    try {
      var nodes = (root || document).querySelectorAll(
        'iframe[src],img[src],script[src],source[src],[style*="url("]'
      );
      for (var i=0;i<nodes.length;i++){
        var el = nodes[i];
        var u = el.getAttribute && (el.getAttribute('src') || el.getAttribute('href') || '');
        if (u && isAd(u)) { el.remove(); continue; }
        var style = el.getAttribute && el.getAttribute('style');
        if (style && style.indexOf('url(') >= 0 && isAd(style)) { el.remove(); }
      }
      for (var j=0;j<SELECTORS.length;j++){
        var bad = (root || document).querySelectorAll(SELECTORS[j]);
        for (var k=0;k<bad.length;k++){ bad[k].style.setProperty('display','none','important'); }
      }
    } catch(e) {}
  }
  function run(){ purge(document); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else { run(); }
  try {
    var mo = new MutationObserver(function(muts){
      for (var i=0;i<muts.length;i++){
        var nodes = muts[i].addedNodes;
        for (var j=0;j<nodes.length;j++){
          var n = nodes[j];
          if (n.nodeType === 1) purge(n.parentElement || document);
        }
      }
    });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  } catch(e) {}
  try {
    var rawOpen = window.open;
    window.open = function(u){
      if (u && isAd(String(u))) return null;
      return rawOpen.apply(window, arguments);
    };
  } catch(e) {}
})();
''';
}

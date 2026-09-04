/// 广告拦截引擎（EasyList 风格的轻量落地）。
///
/// 参考架构（受 WebView 能力约束）：
/// - Brave 把 adblock-rust 焊进 Chromium 网络栈（我们做不到：webview_flutter
///   不暴露 shouldInterceptRequest，无法在网络层拦子资源）；
/// - Firefox iOS / Brave iOS 在 WebKit 限制下用「声明式规则 + JS 补丁」双通道。
///   我们等价于他们的通道 B：JS 引擎补丁 + 主框架导航拦截。
///
/// 三层组合：
/// 1. 主框架导航拦截：onNavigationRequest 对广告/追踪域名 prevent（挡弹窗、
///    中转页、popunder 整页跳转）。
/// 2. JS 引擎补丁：purge 已注入的广告元素（iframe/img/script/video…）、
///    cosmetic 隐藏常见广告容器、MutationObserver 兜懒加载、
///    patch fetch/XHR/sendBeacon/window.open/setAttribute 拦动态请求。
/// 3. 计数反馈：通过 JavaScriptChannel 上报拦截数（Brave Shields 式反馈）。
///
/// 「反追踪」和「拦广告」分开建表（Firefox ETP / 广告拦截的拆分），
/// 命中任一都算 bad，但保留分类能力（以后可分开关）。
///
/// 规则保持保守（低误杀）：域名用「注册域后缀」匹配（evil-x.com 不会命中
/// x.com），URL 关键词用带边界的高置信度片段。
library;

/// 广告 / 广告联盟域名后缀。
const List<String> kAdHostSuffixes = <String>[
  // Google 系
  'doubleclick.net',
  'googlesyndication.com',
  'googletagservices.com',
  'googleadservices.com',
  'adservice.google.com',
  // 通用联盟 / 弹窗
  'adnxs.com',
  'adsrvr.org',
  'criteo.com',
  'criteo.net',
  'outbrain.com',
  'taboola.com',
  'zedo.com',
  'pubmatic.com',
  'rubiconproject.com',
  'amazon-adsystem.com',
  'moatads.com',
  'openx.net',
  'smartadserver.com',
  'adform.net',
  'adfox.ru',
  'media.net',
  'yieldmo.com',
  'sharethrough.com',
  'sonobi.com',
  'indexww.com',
  'casalemedia.com',
  '33across.com',
  'bidswitch.net',
  'adwallet.com',
  '33across.com',
  // 成人站广告联盟（exoclick 系是弹窗/横幅重灾区）
  'exoclick.com',
  'exosrv.com',
  'exdynsrv.com',
  'exoclick.net',
  'juicyads.com',
  'juicyads.rocks',
  'popads.net',
  'popcash.net',
  'popmyads.com',
  'adsterra.com',
  'adsterratech.com',
  'propellerads.com',
  'propellerclick.com',
  'hilltopads.net',
  'hilltopads.com',
  'clickadu.com',
  'adsupply.com',
  'tsyndicate.com',
  'trafficjunky.net',
  'adspyglass.com',
  'coinzilla.com',
  'a-ads.com',
  'ero-advertising.com',
  'rtmark.net',
  'ad-maven.com',
  'onclckpro.com',
  'revcontent.com',
  'adskeeper.com',
  'adskeeper.co.uk',
  'mgid.com',
  'plugrush.com',
  'adcash.com',
  'adplexity.com',
];

/// 追踪器 / 分析域名后缀（Firefox ETP 的 Disconnect 思路：只认追踪实体）。
const List<String> kTrackerHostSuffixes = <String>[
  'google-analytics.com',
  'analytics.google.com',
  'scorecardresearch.com',
  'quantserve.com',
  'quantcount.com',
  'hotjar.io',
  'hotjar.com',
  'mouseflow.com',
  'fullstory.com',
  'crazyegg.com',
  'clicktale.net',
  'cnzz.com',
  'umeng.com',
  'hm.baidu.com',
  'admaster.com.cn',
  'appsflyer.com',
  'app-measurement.com',
  'mixpanel.com',
  'segment.io',
  'segment.com',
  'amplitude.com',
  'matomo.cloud',
  'clarity.ms',
  'bat.bing.com',
];

/// URL 关键词模式（子串匹配，带边界的高置信度片段，避免 /adventure 误杀）。
const List<String> kAdUrlPatterns = <String>[
  '/ads/',
  '/ads?',
  '.ads.',
  '/adserver',
  '/advert',
  '/pagead/',
  '/banners/',
  '/banner_',
  'banner.ad',
  'popunder',
  'popads',
  '/popad',
  '/interstitial',
  'zoneid=',
  '/delivery/js',
  '/adframe',
  '/adiframe',
  '/adjs.php',
  '/showad',
  '/getad',
  'adclick',
  'adfeed',
];

/// 高置信度广告容器 CSS 选择器（只藏明显广告位，避免误杀正文）。
const List<String> kAdCssSelectors = <String>[
  '.adsbygoogle',
  '#google_ads_iframe',
  'iframe[id^="google_ads_iframe"]',
  'iframe[src*="doubleclick"]',
  'iframe[src*="googlesyndication"]',
  'iframe[src*="exoclick"]',
  'iframe[src*="juicyads"]',
  'iframe[src*="popads"]',
  'iframe[src*="adsterra"]',
  'iframe[src*="propellerads"]',
  '[id^="ad-"][id\$="-banner"]',
  '[class*="adsbygoogle"]',
  '[data-ad-slot]',
  '[data-google-query-id]',
  '[data-ad-processed]',
  '.J_ad',
  '#BAIDU_SSP__wrapper',
];

String? _hostOf(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  return host.isEmpty ? null : host;
}

bool _matchesSuffix(String? host, List<String> suffixes) {
  if (host == null) return false;
  for (final suffix in suffixes) {
    if (host == suffix || host.endsWith('.$suffix')) return true;
  }
  return false;
}

/// 广告 URL：域名后缀或 URL 关键词模式命中。
bool isAdUrl(String url) {
  final host = _hostOf(url);
  if (_matchesSuffix(host, kAdHostSuffixes)) return true;
  final lower = url.toLowerCase();
  for (final pattern in kAdUrlPatterns) {
    if (lower.contains(pattern)) return true;
  }
  return false;
}

/// 追踪器 URL：仅域名后缀（Disconnect 风格，只认追踪实体）。
bool isTrackerUrl(String url) =>
    _matchesSuffix(_hostOf(url), kTrackerHostSuffixes);

/// 任一命中（网络/JS 层统一入口）。
bool isBadUrl(String url) => isAdUrl(url) || isTrackerUrl(url);

/// 生成注入页面的拦截脚本（IIFE，幂等：重复注入只生效一次）。
String adBlockerScript() {
  final ads = kAdHostSuffixes.map((h) => "'$h'").join(',');
  final trackers = kTrackerHostSuffixes.map((h) => "'$h'").join(',');
  final patterns =
      kAdUrlPatterns.map((p) => "'${p.replaceAll("'", r"\'")}'").join(',');
  final selectors =
      kAdCssSelectors.map((s) => "'${s.replaceAll("'", r"\'")}'").join(',');
  return '''
(function(){
  if (window.__yilanAdBlock) return;
  window.__yilanAdBlock = true;
  var ADS = [$ads];
  var TRACKERS = [$trackers];
  var PATTERNS = [$patterns];
  var SELECTORS = [$selectors];
  var blocked = 0;
  function hostOf(u){
    try { return new URL(u, location.href).hostname.toLowerCase(); } catch(e){ return ''; }
  }
  function inList(list, h){
    if (!h) return false;
    for (var i=0;i<list.length;i++){
      var d = list[i];
      if (h === d || h.slice(-(d.length+1)) === '.'+d) return true;
    }
    return false;
  }
  function isAd(u){
    var s = String(u || '');
    if (!s) return false;
    if (inList(ADS, hostOf(s))) return true;
    var low = s.toLowerCase();
    for (var i=0;i<PATTERNS.length;i++){
      if (low.indexOf(PATTERNS[i]) >= 0) return true;
    }
    return false;
  }
  function isTracker(u){ return inList(TRACKERS, hostOf(String(u||''))); }
  function isBad(u){ return isAd(u) || isTracker(u); }
  function hit(){
    blocked++;
    try {
      window.yilanAdBlock && window.yilanAdBlock.postMessage(String(blocked));
    } catch(e) {}
  }
  function purge(root){
    try {
      var nodes = (root || document).querySelectorAll(
        'iframe[src],img[src],script[src],source[src],video[src],audio[src],embed[src],object[data],[style*="url("]'
      );
      for (var i=0;i<nodes.length;i++){
        var el = nodes[i];
        var u = (el.getAttribute && (el.getAttribute('src') || el.getAttribute('data') || el.getAttribute('data-src'))) || '';
        var style = (el.getAttribute && el.getAttribute('style')) || '';
        if ((u && isBad(u)) || (style && style.indexOf('url(') >= 0 && isBad(style))) {
          el.remove();
          hit();
        }
      }
      for (var j=0;j<SELECTORS.length;j++){
        var bad = (root || document).querySelectorAll(SELECTORS[j]);
        for (var k=0;k<bad.length;k++){
          var tag = bad[k].tagName;
          if (tag === 'IFRAME' || tag === 'SCRIPT') { bad[k].remove(); } 
          else { bad[k].style.setProperty('display','none','important'); }
          hit();
        }
      }
    } catch(e) {}
  }
  function run(){
    purge(document);
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function(){ purge(document); });
    }
  }
  run();
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
  // 动态请求层：fetch / XHR / sendBeacon / window.open / setAttribute
  try {
    var rawFetch = window.fetch;
    if (rawFetch) {
      window.fetch = function(input, init){
        var u = (input && input.url) ? input.url : input;
        if (isBad(u)) { hit(); return Promise.reject(new Error('blocked')); }
        return rawFetch.apply(window, arguments);
      };
    }
  } catch(e) {}
  try {
    var rawOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, u){
      if (isBad(u)) { hit(); u = 'data:text/plain,blocked'; }
      return rawOpen.apply(this, arguments);
    };
  } catch(e) {}
  try {
    if (navigator.sendBeacon) {
      var rawBeacon = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = function(u, data){
        if (isBad(u)) { hit(); return true; }
        return rawBeacon(u, data);
      };
    }
  } catch(e) {}
  try {
    var rawOpenWin = window.open;
    window.open = function(u){
      if (u && isBad(String(u))) { hit(); return null; }
      return rawOpenWin.apply(window, arguments);
    };
  } catch(e) {}
  try {
    var rawSetAttr = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value){
      if ((name === 'src' || name === 'data-src') && isBad(value)) { hit(); return; }
      return rawSetAttr.apply(this, arguments);
    };
  } catch(e) {}
})();
''';
}

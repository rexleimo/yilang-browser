import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../logic/reader_article.dart';

/// 阅读模式页：把提取出的正文 HTML 用 WebView 本地渲染，
/// 不发任何网络请求（图片除外，仍指向原站）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.article});

  final ReaderArticle article;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFFFBFBF8))
      ..loadHtmlString(readerHtmlDocument(widget.article));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.article.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

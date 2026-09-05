import 'package:flutter_test/flutter_test.dart';
import 'package:yilan_browser/features/browser/logic/reader_article.dart';

void main() {
  group('ReaderArticle.fromJsResult', () {
    test('解析标准 JSON 字符串', () {
      final article = ReaderArticle.fromJsResult(
        '{"title":"标题","html":"<p>正文</p>"}',
      );
      expect(article, isNotNull);
      expect(article!.title, '标题');
      expect(article.html, '<p>正文</p>');
    });

    test('解析被二次编码的 JSON 字符串（部分内核会再包一层引号）', () {
      final article = ReaderArticle.fromJsResult(
        '"{\\"title\\":\\"T\\",\\"html\\":\\"<p>x</p>\\"}"',
      );
      expect(article, isNotNull);
      expect(article!.title, 'T');
      expect(article.html, '<p>x</p>');
    });

    test('非法 JSON → null', () {
      expect(ReaderArticle.fromJsResult('{not json'), isNull);
    });

    test('非字符串结果 → null', () {
      expect(ReaderArticle.fromJsResult(42), isNull);
      expect(ReaderArticle.fromJsResult(null), isNull);
    });

    test('空 html → null（页面无正文，阅读模式不可用）', () {
      expect(
        ReaderArticle.fromJsResult('{"title":"T","html":"   "}'),
        isNull,
      );
      expect(ReaderArticle.fromJsResult('{"title":"T","html":""}'), isNull);
      expect(ReaderArticle.fromJsResult('{"title":"T"}'), isNull);
    });

    test('html 超长截断（防御异常大页面撑爆 WebView）', () {
      final big = '{"title":"T","html":"${'x' * 600000}"}';
      final article = ReaderArticle.fromJsResult(big);
      expect(article, isNotNull);
      expect(article!.html.length, lessThanOrEqualTo(500000));
    });
  });

  group('readerHtmlDocument', () {
    test('包含标题、视口与样式，正文原样嵌入', () {
      final doc = readerHtmlDocument(
        const ReaderArticle(title: '文章标题', html: '<p>段落</p><img src="a.png">'),
      );
      expect(doc, contains('<title>文章标题</title>'));
      expect(doc, contains('viewport'));
      expect(doc, contains('<p>段落</p>'));
      expect(doc, contains('<img src="a.png">'));
      expect(doc, contains('max-width'));
    });

    test('标题中的 HTML 特殊字符被转义', () {
      final doc = readerHtmlDocument(
        const ReaderArticle(title: '<script>alert(1)</script>', html: '<p>x</p>'),
      );
      expect(doc, contains('&lt;script&gt;'));
      expect(doc, isNot(contains('<script>alert')));
    });
  });
}

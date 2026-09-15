import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../exceptions.dart';

/// 解析 HTML 字符串为文档树。
///
/// 空输入或纯空白输入抛出 [HtmlParseException]；其余情况一律能拿到文档——
/// `package:html` 实现了 HTML5 的错误恢复算法，畸形标签不会导致失败。
Document parseHtmlDocument(String html) {
  if (html.trim().isEmpty) {
    throw const HtmlParseException('HTML 为空或全是空白，无从解析');
  }
  return html_parser.parse(html);
}

/// 读取元素的属性值。
///
/// `package:html` 的属性 map 键类型是 `Object`：普通 HTML 属性是 `String`，
/// 只有外来内容（xmlns/xlink）才是 `AttributeName`。这里把两种情况都覆盖掉。
String? elementAttribute(Element element, String name) {
  final direct = element.attributes[name];
  if (direct != null) return direct;
  for (final entry in element.attributes.entries) {
    if (entry.key.toString() == name) return entry.value;
  }
  return null;
}

/// 读取元素上的整数属性；缺失或不可解析时返回 null。
int? elementIntAttribute(Element element, String name) {
  final raw = elementAttribute(element, name);
  if (raw == null) return null;
  return int.tryParse(raw.trim());
}

/// 定位课表 `<table>` 的策略。
abstract class TableLocator {
  /// 取文档里第一个 `<table>`。
  const factory TableLocator.first() = _FirstTable;

  /// 按 CSS 选择器定位；selector 指向的不是 `<table>` 时返回 null。
  const factory TableLocator.css(String selector) = _CssTable;

  /// 按 `id` 定位。
  const factory TableLocator.id(String id) = _IdTable;

  /// 按自定义谓词定位，取第一个满足条件的 `<table>`。
  const factory TableLocator.where(bool Function(Element table) test, {String description}) =
      _PredicateTable;

  /// 在文档中定位表格；找不到返回 null。
  Element? select(Document document);

  /// 供诊断信息使用的可读描述。
  String describe();
}

class _FirstTable implements TableLocator {
  const _FirstTable();

  @override
  Element? select(Document document) => document.querySelector('table');

  @override
  String describe() => '第一个 <table>';
}

class _CssTable implements TableLocator {
  const _CssTable(this.selector);

  final String selector;

  @override
  Element? select(Document document) {
    final found = document.querySelector(selector);
    if (found == null) return null;
    if (found.localName == 'table') return found;
    // 选择器可能命中的是外层容器，往下再找一层。
    return found.querySelector('table');
  }

  @override
  String describe() => '选择器 "$selector"';
}

class _IdTable implements TableLocator {
  const _IdTable(this.id);

  final String id;

  @override
  Element? select(Document document) {
    final found = document.getElementById(id);
    if (found == null) return null;
    return found.localName == 'table' ? found : found.querySelector('table');
  }

  @override
  String describe() => 'id="$id"';
}

class _PredicateTable implements TableLocator {
  const _PredicateTable(this.test, {this.description});

  final bool Function(Element table) test;
  final String? description;

  @override
  Element? select(Document document) {
    for (final table in document.querySelectorAll('table')) {
      if (test(table)) return table;
    }
    return null;
  }

  @override
  String describe() => description ?? '自定义谓词';
}

/// 生成一个简短的、可读的元素路径，形如 `div.course-item[3]`。
///
/// 用于诊断信息里定位出问题的元素——比报一个坐标有用得多。
String elementPath(Element element) {
  final tag = element.localName ?? '?';
  final id = element.attributes['id'];
  if (id != null && id.isNotEmpty) return '$tag#$id';
  final classes = element.attributes['class'];
  final suffix = StringBuffer(tag);
  if (classes != null && classes.trim().isNotEmpty) {
    final first = classes.trim().split(RegExp(r'\s+')).first;
    suffix.write('.$first');
  }
  final parent = element.parent;
  if (parent != null) {
    final siblings = parent.children.where((e) => e.localName == tag).toList();
    if (siblings.length > 1) {
      suffix.write('[${siblings.indexOf(element)}]');
    }
  }
  return suffix.toString();
}

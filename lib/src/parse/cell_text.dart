import 'package:html/dom.dart';

import 'text_normalize.dart';

/// 一段"宽间隔"的占位符，用于还原被空白分隔的字段。
///
/// 很多教务系统不用 `<br>` 分行，而是在一行里用多个 `&nbsp;` 把课程名、教师、
/// 教室排开。U+0001 不会出现在解码后的 HTML 文本里，且不会被 trim() 吃掉。
const String kFieldSeparator = '\u0001';

/// 默认被视为"空单元格"的占位文本。
const List<String> kDefaultBlankTokens = <String>[
  '',
  '-',
  '--',
  '—',
  '——',
  '－',
  '/',
  '无',
  '暂无',
  '没有',
  'null',
];

/// 产生换行的标签。
const Set<String> _lineBreakTags = <String>{'br', 'hr'};

/// 会产生块级边界的标签。
///
/// `<td>` 与 `<table>` 在内是刻意的：单元格里嵌套表格时，内层单元格的文本应当
/// 各成一行，而不是和外层粘在一起。
const Set<String> _blockTags = <String>{
  'div',
  'p',
  'li',
  'ul',
  'ol',
  'tr',
  'td',
  'th',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'section',
  'article',
  'header',
  'footer',
  'blockquote',
  'pre',
  'dt',
  'dd',
  'form',
  'fieldset',
  'figure',
  'address',
  'main',
  'nav',
  'aside',
  'details',
  'summary',
  'caption',
};

/// HTML 源码里的换行与制表符。
///
/// 它们在渲染时只是普通空白，不携带任何行语义，所以在走查阶段就要压成空格，
/// 免得和结构性的换行混为一谈。
final RegExp _sourceWhitespace = RegExp(r'[\r\n\t]');

/// 行内连续两个及以上空格。
final RegExp _wideGap = RegExp(' {2,}');

/// 把一个单元格的内容拆成清洗过的逻辑行。
///
/// 这是 DOM 走查而非字符串分割：按换行符切 element.text 会同时犯两个错——
/// 把源码里内联标签之间的换行当成换行（渲染时那只是一个空格），又漏掉
/// div/p 嵌套产生的真实换行（现代教务系统的主流写法，里面根本没有换行符）。
///
/// keepWideGaps 为 true 时，行内连续两个以上的空白会被替换成 kFieldSeparator，
/// 调用方可用 splitFields 还原字段边界。
List<String> extractCellLines(Element cell, {bool keepWideGaps = true}) {
  final buffer = StringBuffer();
  _walk(cell, buffer);
  final out = <String>[];
  for (final raw in buffer.toString().split('\n')) {
    final line = _cleanLine(raw, keepWideGaps);
    if (line.isNotEmpty) out.add(line);
  }
  return out;
}

/// 按 kFieldSeparator 把一行拆成字段。
///
/// 行内没有宽间隔时返回只含该行本身的单元素列表。
List<String> splitFields(String line) {
  if (!line.contains(kFieldSeparator)) return <String>[line];
  return <String>[
    for (final part in line.split(kFieldSeparator))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// 判断一组行是否等同于空单元格。
///
/// blankTokens 里的占位符（短横线、无、暂无 之类）也算空。
bool isBlankCell(Iterable<String> lines, [List<String> blankTokens = kDefaultBlankTokens]) {
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (blankTokens.contains(trimmed)) continue;
    return false;
  }
  return true;
}

void _walk(Node node, StringBuffer out) {
  if (node is Text) {
    out.write(node.text.replaceAll(_sourceWhitespace, ' '));
    return;
  }
  if (node is! Element) return; // 注释、DOCTYPE 等一律忽略。
  final tag = node.localName ?? '';
  if (tag == 'script' || tag == 'style') return;
  if (_lineBreakTags.contains(tag)) {
    out.write('\n');
    return;
  }
  final isBlock = _blockTags.contains(tag);
  if (isBlock) out.write('\n');
  for (final child in node.nodes) {
    _walk(child, out);
  }
  if (isBlock) out.write('\n');
}

String _cleanLine(String raw, bool keepWideGaps) {
  final trimmed = normalizeWhitespace(raw).trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(_wideGap, keepWideGaps ? kFieldSeparator : ' ');
}

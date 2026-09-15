import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

/// 一个合成单元格的规格。
///
/// [attributes] 里的键值会原样写进标签，用于构造 `rowspan="abc"` 这类脏数据。
class CellSpec {
  const CellSpec(
    this.text, {
    this.rowSpan,
    this.colSpan,
    this.tag = 'td',
    this.attributes = const <String, String>{},
  });

  final String text;
  final int? rowSpan;
  final int? colSpan;
  final String tag;
  final Map<String, String> attributes;

  String render() {
    final attrs = <String>[
      if (rowSpan != null) 'rowspan="$rowSpan"',
      if (colSpan != null) 'colspan="$colSpan"',
      for (final entry in attributes.entries) '${entry.key}="${entry.value}"',
    ];
    final suffix = attrs.isEmpty ? '' : ' ${attrs.join(' ')}';
    return '<$tag$suffix>${text.isEmpty ? '&nbsp;' : text}</$tag>';
  }
}

/// 渲染整张表；[tbody] 为 false 时输出裸 `<tr>`（用于验证隐式 tbody）。
String buildTableHtml(
  List<List<CellSpec>> rows, {
  String tableAttributes = '',
  bool tbody = true,
  String extraInside = '',
}) {
  final body = rows.map((r) => '<tr>${r.map((c) => c.render()).join()}</tr>').join();
  final attrs = tableAttributes.isEmpty ? '' : ' $tableAttributes';
  final inner = tbody ? '<tbody>$body</tbody>' : body;
  return '<table$attrs>$extraInside$inner</table>';
}

/// 解析出一张 `<table>` 元素。
Element buildTable(
  List<List<CellSpec>> rows, {
  String tableAttributes = '',
  bool tbody = true,
  String extraInside = '',
}) {
  final html = buildTableHtml(
    rows,
    tableAttributes: tableAttributes,
    tbody: tbody,
    extraInside: extraInside,
  );
  return parseFragment(html).querySelector('table')!;
}

/// 用 `n` 行 `m` 列的纯文本表格。
Element buildPlainTable(int n, int m) => buildTable(<List<CellSpec>>[
  for (var r = 0; r < n; r++) <CellSpec>[for (var c = 0; c < m; c++) CellSpec('r${r}c$c')],
]);

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

/// 「永不丢失导入」的保证：畸形 HTML 可以解析不出东西，但**绝不能抛异常**。
void main() {
  final registry = SchoolAdapterRegistry.standard;

  // 这些输入结构上是坏的，但仍应走完整条流水线。
  final malformed = <String, String>{
    '未闭合的 td': '<table id="kbTable"><tr><td>高等数学<td>张伟</tr></table>',
    '未闭合的 table': '<table id="kbTable"><tr><td>高等数学</td></tr>',
    '未闭合的 tr': '<table id="kbTable"><tr><td>a</td><td>b</td>',
    'td 出现在 tr 之外': '<table id="kbTable"><td>孤儿单元格</td></table>',
    '游离的结束标签': '</div></td></tr><table id="kbTable"><tr><td>a</td></tr></table>',
    '只有表头没有表体': '<table id="kbTable"><thead><tr><th>节次</th></tr></thead></table>',
    '属性没有引号': '<table id=kbTable><tr><td rowspan=2>x</td></tr><tr><td>y</td></tr></table>',
    '带 BOM': '﻿<table id="kbTable"><tr><td>a</td></tr></table>',
    '嵌套表格错乱': '<table id="kbTable"><tr><td><table><tr><td>x</table></td></tr></table>',
    '空表格': '<table id="kbTable"></table>',
  };

  malformed.forEach((name, html) {
    test('$name —— 不抛异常且有结构化的结果', () {
      late CourseImportResult result;
      expect(() => result = registry.parseAuto(html), returnsNormally);
      expect(result, isNotNull);
      expect(result.warnings, isNotNull);
    });

    test('$name —— parseAs 同样不抛', () {
      expect(() => registry.parseAs('STANDARD_GRID_01', html), returnsNormally);
    });
  });

  group('空输入', () {
    test('parseAuto 对空串返回 noAdapterMatched 而不抛', () {
      for (final input in <String>['', '   ', '\n\t ']) {
        late CourseImportResult result;
        expect(() => result = registry.parseAuto(input), returnsNormally);
        expect(result.isEmpty, isTrue);
        expect(result.hasErrors, isTrue);
      }
    });

    test('直接调用适配器解析空串会抛 HtmlParseException', () {
      const adapter = StandardGridAdapter();
      expect(() => adapter.parse(''), throwsA(isA<HtmlParseException>()));
    });
  });

  group('乱码与异常编码', () {
    test('GBK 字节被当成 latin-1 解码后不崩溃', () {
      // 模拟：GBK 的「高等数学」被按 latin-1 解出来的一串高位字符。
      final mojibake = String.fromCharCodes(<int>[0xB8, 0xDF, 0xB5, 0xC8]);
      final html =
          '<table id="kbTable" class="timetable">'
          '<tr><td>节次</td><td>星期</td></tr>'
          '<tr><td></td><td>星期一</td></tr>'
          '<tr><td>第1-2节</td><td>$mojibake<br>1-16周<br>教101</td></tr>'
          '</table>';
      late CourseImportResult result;
      expect(() => result = registry.parseAuto(html), returnsNormally);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, mojibake);
    });

    test('全乱码页面不崩溃且报出识别失败', () {
      final mojibake = String.fromCharCodes(<int>[0xB8, 0xDF, 0xB5, 0xC8]);
      final html = '<table id="kbTable"><tr><td>$mojibake</td></tr></table>';
      late CourseImportResult result;
      expect(() => result = registry.parseAuto(html), returnsNormally);
      expect(result.isEmpty, isTrue);
      expect(result.hasErrors, isTrue);
    });
  });
}

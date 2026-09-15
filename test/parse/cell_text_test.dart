import 'package:curriculum/curriculum.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:test/test.dart';

Element cell(String innerHtml) {
  final fragment = parseFragment('<table><tr><td id="t">$innerHtml</td></tr></table>');
  return fragment.querySelector('#t')!;
}

void main() {
  group('extractCellLines', () {
    test('br 断行，且不产生双换行', () {
      expect(extractCellLines(cell('a<br>b')), <String>['a', 'b']);
      expect(extractCellLines(cell('a<br/>b')), <String>['a', 'b']);
      expect(extractCellLines(cell('a<BR>b')), <String>['a', 'b']);
    });

    test('连续 br 不产生空行', () {
      expect(extractCellLines(cell('a<br><br>b')), <String>['a', 'b']);
    });

    test('div 嵌套每层一行', () {
      expect(extractCellLines(cell('<div>高等数学</div><div>张伟</div><div>1-16周</div>')), <String>[
        '高等数学',
        '张伟',
        '1-16周',
      ]);
    });

    test('p 套 div 不留空行', () {
      expect(extractCellLines(cell('<p>a<div>b</div></p>')), <String>['a', 'b']);
    });

    test('script 与 style 不贡献内容', () {
      expect(extractCellLines(cell('a<script>var x=1;</script>')), <String>['a']);
      expect(extractCellLines(cell('<style>.a{color:red}</style>b')), <String>['b']);
      expect(extractCellLines(cell('<script>var x=1;</script>')), isEmpty);
    });

    test('注释不贡献内容', () {
      expect(extractCellLines(cell('a<!-- 注释 -->b')), <String>['ab']);
    });

    test('源码里的换行只是空格，不算换行', () {
      // 最关键的一条：渲染时 foo 与 bar 在同一行。
      expect(extractCellLines(cell('foo\nbar')), <String>['foo bar']);
      expect(extractCellLines(cell('<span>foo</span>\n<span>bar</span>')), <String>['foo bar']);
    });

    test('nbsp 只算空白', () {
      expect(extractCellLines(cell('&nbsp;')), isEmpty);
      expect(extractCellLines(cell('a&nbsp;b')), <String>['a b']);
      expect(extractCellLines(cell('&nbsp;a&nbsp;')), <String>['a']);
    });

    test('全角空格与其它宽空白', () {
      expect(extractCellLines(cell('a　b')), <String>['a b']);
      expect(extractCellLines(cell('　')), isEmpty);
    });

    test('中文标点原样保留', () {
      expect(extractCellLines(cell('高等数学（A）')), <String>['高等数学（A）']);
    });

    test('嵌套表格：内层单元格各成一行', () {
      final lines = extractCellLines(cell('<table><tr><td>内1</td><td>内2</td></tr></table>'));
      expect(lines, containsAll(<String>['内1', '内2']));
    });

    test('一段连续空白成为 kFieldSeparator', () {
      final lines = extractCellLines(cell('高等数学&nbsp;&nbsp;张伟&nbsp;&nbsp;教101'));
      expect(lines, hasLength(1));
      expect(lines.single.contains(kFieldSeparator), isTrue);
      expect(splitFields(lines.single), <String>['高等数学', '张伟', '教101']);
    });

    test('单个空格不构成字段分隔', () {
      final lines = extractCellLines(cell('高等数学 张伟'));
      expect(splitFields(lines.single), <String>['高等数学 张伟']);
    });

    test('keepWideGaps=false 时宽间隔折叠为单个空格', () {
      final lines = extractCellLines(cell('a&nbsp;&nbsp;b'), keepWideGaps: false);
      expect(lines, <String>['a b']);
    });
  });

  group('isBlankCell', () {
    test('空列表与占位符都算空', () {
      expect(isBlankCell(const <String>[]), isTrue);
      expect(isBlankCell(<String>['-']), isTrue);
      expect(isBlankCell(<String>['无']), isTrue);
      expect(isBlankCell(<String>['', '—']), isTrue);
      expect(isBlankCell(<String>['高等数学']), isFalse);
      expect(isBlankCell(<String>['-', '高等数学']), isFalse);
    });

    test('可自定义占位符集合', () {
      expect(isBlankCell(<String>['N/A'], <String>['N/A']), isTrue);
      expect(isBlankCell(<String>['N/A'], <String>['无']), isFalse);
    });
  });
}

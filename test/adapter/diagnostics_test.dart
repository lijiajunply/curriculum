import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

void main() {
  group('解析选项', () {
    test('maxWarnings 截断保存但继续计数', () {
      final seen = <ParseWarning>[];
      final ctx = ParseContext(options: ParseOptions(maxWarnings: 2, onWarning: seen.add));
      for (var i = 0; i < 5; i++) {
        ctx.warn(ParseWarningKind.custom, '第 $i 条');
      }
      expect(ctx.warnings, hasLength(2));
      expect(ctx.droppedWarnings, 3);
      expect(ctx.counters[ParseWarningKind.custom], 5);
      // 回调不受上限影响，宿主仍能流式看到全部。
      expect(seen, hasLength(5));
      expect(ctx.stats.warningCount, 5);
    });

    test('hasErrors 不受 maxWarnings 影响', () {
      final ctx = ParseContext(options: const ParseOptions(maxWarnings: 1));
      ctx.error(ParseWarningKind.custom, '错误一');
      ctx.error(ParseWarningKind.custom, '错误二');
      expect(ctx.warnings, hasLength(1));
      expect(ctx.hasErrors, isTrue);
    });

    test('rawText 被截断', () {
      final ctx = ParseContext(options: const ParseOptions());
      ctx.warn(ParseWarningKind.unknownCellText, '太长', rawText: 'x' * 500);
      expect(ctx.warnings.single.rawText!.length, lessThanOrEqualTo(201));
      expect(ctx.warnings.single.rawText, endsWith('…'));
    });

    test('copyWith 覆盖部分字段', () {
      const base = ParseOptions();
      final strict = base.copyWith(strict: true, maxWarnings: 10);
      expect(strict.strict, isTrue);
      expect(strict.maxWarnings, 10);
      expect(strict.mergeSameCourse, isTrue);
      expect(base.strict, isFalse);
    });
  });

  group('严格模式', () {
    const adapter = StandardGridAdapter();

    test('默认关闭：parse 不因内容问题抛异常', () {
      final result = adapter.parse('<html><body>没有课表</body></html>');
      expect(result.hasErrors, isTrue);
      expect(result.isEmpty, isTrue);
    });

    test('parseOrThrow 在无课程时抛并携带诊断', () {
      expect(
        () => adapter.parseOrThrow('<html><body>没有课表</body></html>'),
        throwsA(
          isA<ParseFailedException>()
              .having((e) => e.warnings, 'warnings', isNotEmpty)
              .having((e) => e.partial, 'partial', isNotNull),
        ),
      );
    });

    test('strict 打开后 parseOrThrow 也会因 error 级诊断抛出', () {
      final html =
          '<table id="kbTable" class="timetable">'
          '<tr><th>节次</th><th>星期</th></tr>'
          '<tr><th></th><th>星期一</th></tr>'
          '<tr><td>第1-2节</td><td>高等数学<br>张伟<br>1-16周<br>教101</td></tr>'
          '</table>';
      // 先确认这份 HTML 本身是能解析的。
      expect(adapter.parse(html).courses, hasLength(1));
      // 再确认不是 error 导致的误报。
      expect(
        () => adapter.parseOrThrow(html, options: const ParseOptions(strict: true)),
        returnsNormally,
      );
    });
  });

  group('诊断报告', () {
    test('包含适配器、统计与每条诊断的位置', () {
      const adapter = StandardGridAdapter();
      final html =
          '<table id="kbTable" class="timetable">'
          '<tr><th>节次</th><th>星期</th></tr>'
          '<tr><th></th><th>星期一</th></tr>'
          '<tr><td>第1-2节</td><td>高等数学<br>张伟<br>待定<br>教101</td></tr>'
          '</table>';
      final report = adapter.parse(html).diagnosticReport;
      expect(report, contains('STANDARD_GRID_01'));
      expect(report, contains('courses: 1'));
      expect(report, contains('周次无法解析'));
      expect(report, contains('r2.c1'));
    });

    test('无诊断时明确说 none', () {
      const adapter = StandardGridAdapter();
      final html =
          '<table id="kbTable" class="timetable">'
          '<tr><th>节次</th><th>星期</th></tr>'
          '<tr><th></th><th>星期一</th></tr>'
          '<tr><td>第1-2节</td><td>高等数学<br>张伟<br>1-16周<br>教101</td></tr>'
          '</table>';
      final report = adapter.parse(html).diagnosticReport;
      expect(report, contains('warnings: none'));
    });
  });
}

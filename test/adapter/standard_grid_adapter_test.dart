import 'dart:convert';
import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

const adapter = StandardGridAdapter();

String fixture(String name) => File('test/fixtures/standard_grid/$name').readAsStringSync();

void main() {
  group('StandardGridAdapter 端到端', () {
    late CourseImportResult result;

    setUpAll(() {
      result = adapter.parse(fixture('basic.html'));
    });

    test('逐个字段与期望一致', () {
      final expected = jsonDecode(fixture('basic.expected.json')) as Map<String, dynamic>;
      expect(result.toJson()['courses'], equals(expected['courses']));
    });

    test('课程条数', () {
      expect(result.courses, hasLength(7));
    });

    test('没有 error 级诊断', () {
      final errors = result.warnings.where((w) => w.severity == ParseSeverity.error).toList();
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    test('rowspan 单元格跨过两行标签，得到 1-4 节', () {
      final english = result.courses.firstWhere((c) => c.name == '大学英语（视听说）');
      expect(english.day, 3);
      expect(english.startSection, 1);
      expect(english.endSection, 4);
      expect(english.weeks, <int>[1, 3, 5, 7]);
    });

    test('同一格里的两门课都拿整格跨度，不被均分', () {
      final lab = result.courses.firstWhere((c) => c.name == '程序设计基础(实验)');
      final main = result.courses.firstWhere((c) => c.name == '程序设计基础');
      expect(main.startSection, 3);
      expect(main.endSection, 4);
      expect(lab.startSection, 3);
      expect(lab.endSection, 4);
    });

    test('colspan 单元格只落在最左侧那一列（默认不跨天）', () {
      final pe = result.courses.firstWhere((c) => c.name == '体育（篮球）');
      expect(pe.day, 4);
      expect(result.courses.where((c) => c.name == '体育（篮球）'), hasLength(1));
    });

    test('空白单元格与占位符单元格被跳过', () {
      expect(result.courses.any((c) => c.name == '-' || c.name.isEmpty), isFalse);
    });

    test('div 与 br 两种分行写法都能解析', () {
      final marx = result.courses.firstWhere((c) => c.name == '马克思主义基本原理');
      expect(marx.teacher, '王强');
      expect(marx.position, '博远楼305');
      expect(marx.weeks, <int>[3, 4, 5, 7, 9]);
    });

    test('config 默认不产出', () {
      expect(result.config, isNull);
      expect(result.toJson()['config'], isNull);
    });

    test('adapterId 被带到结果里', () {
      expect(result.adapterId, 'STANDARD_GRID_01');
    });

    test('diagnosticReport 可读且不含 error', () {
      final report = result.diagnosticReport;
      expect(report, contains('STANDARD_GRID_01'));
      expect(report, contains('courses: 7'));
    });
  });

  group('探测', () {
    test('canParse 认结构标记', () {
      expect(adapter.canParse(fixture('basic.html')), isTrue);
      expect(adapter.canParse('<html><body>无关页面</body></html>'), isFalse);
      expect(adapter.canParse(''), isFalse);
    });

    test('optionalMarkers 提高置信度', () {
      final full = adapter.detectConfidence(fixture('basic.html'));
      final bare = adapter.detectConfidence('<table id="kbTable"></table>');
      expect(full, greaterThan(bare));
      expect(adapter.detectConfidence('<html></html>'), 0);
    });
  });

  group('parseOrThrow', () {
    test('有结果时不抛', () {
      expect(() => adapter.parseOrThrow(fixture('basic.html')), returnsNormally);
    });

    test('表格缺失时抛 ParseFailedException', () {
      expect(
        () => adapter.parseOrThrow('<html><body>没有课表</body></html>'),
        throwsA(isA<ParseFailedException>()),
      );
    });

    test('parse 对同样的输入不抛，只返回带 error 的空结果', () {
      final result = adapter.parse('<html><body>没有课表</body></html>');
      expect(result.isEmpty, isTrue);
      expect(result.hasErrors, isTrue);
      expect(result.warnings.single.kind, ParseWarningKind.tableNotFound);
    });
  });
}

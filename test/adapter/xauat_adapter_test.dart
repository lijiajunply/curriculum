import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

const adapter = XauatAdapter();

String fixture(String name) => File('test/fixtures/xauat/$name').readAsStringSync();

void main() {
  group('XauatAdapter 端到端', () {
    late CourseImportResult result;

    setUpAll(() => result = adapter.parse(fixture('basic.html')));

    test('卡片数量与卡片总数一致', () {
      expect(result.courses, hasLength(4));
    });

    test('星期来自所在列，而不是卡片内容', () {
      final byName = <String, Course>{for (final c in result.courses) c.name: c};
      expect(byName['高等数学A']!.day, 1);
      expect(byName['数据结构']!.day, 3);
      expect(byName['数据结构(实验)']!.day, 3);
      expect(byName['大学英语（视听说）']!.day, 5);
    });

    test('节次来自括号子句', () {
      final byName = <String, Course>{for (final c in result.courses) c.name: c};
      expect(byName['高等数学A']!.startSection, 1);
      expect(byName['高等数学A']!.endSection, 2);
      expect(byName['数据结构(实验)']!.startSection, 5);
      expect(byName['数据结构(实验)']!.endSection, 6);
    });

    test('周次的 ~ 分隔与逗号列表都被展开', () {
      final byName = <String, Course>{for (final c in result.courses) c.name: c};
      expect(byName['高等数学A']!.weeks, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      expect(byName['大学英语（视听说）']!.weeks, <int>[1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16]);
      expect(byName['数据结构(实验)']!.weeks, <int>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('课程名里的半角括号不会被当成子句吃掉', () {
      expect(result.courses.map((c) => c.name), contains('数据结构(实验)'));
    });

    test('没有 error 级诊断', () {
      expect(result.warnings.where((w) => w.severity == ParseSeverity.error), isEmpty);
    });

    test('教师为空——页面本身不提供，不是解析失败', () {
      expect(result.courses.every((c) => c.teacher.isEmpty), isTrue);
      // 空教师只记 info，不记 warning。
      expect(result.warnings.where((w) => w.kind == ParseWarningKind.missingTeacher), hasLength(4));
    });

    test('课程代码不进入输出', () {
      // `.card-content-code` 里的 MATH101 / CS201 等按设计丢弃，
      // 因为拾光课程表的 Course 没有对应字段。见适配器文档。
      expect(result.courses.any((c) => c.name.contains('MATH101')), isFalse);
      expect(result.courses.every((c) => c.remark == null), isTrue);
    });
  });

  group('比原实现多支持的写法', () {
    test('单双周子句被展开（原 CourseHtmlParser 不支持）', () {
      final result = adapter.parse(fixture('extra_clauses.html'));
      final algebra = result.courses.firstWhere((c) => c.name == '线性代数');
      expect(algebra.weeks, <int>[1, 3, 5, 7, 9, 11, 13, 15]);
      expect(algebra.startSection, 3);
      expect(algebra.endSection, 4);
    });

    test('不带括号的行政噪声行被跳过', () {
      final result = adapter.parse(fixture('extra_clauses.html'));
      final pe = result.courses.firstWhere((c) => c.name == '体育（篮球）');
      expect(pe.position, '风雨操场');
      expect(pe.day, 4);
      expect(pe.startSection, 7);
      expect(pe.endSection, 8);
    });
  });

  group('探测', () {
    test('认结构标记', () {
      expect(adapter.canParse(fixture('basic.html')), isTrue);
      expect(adapter.canParse('<html><body>无关页面</body></html>'), isFalse);
    });

    test('不会跟标准网格适配器抢页面', () {
      final standard = File('test/fixtures/standard_grid/basic.html').readAsStringSync();
      expect(adapter.canParse(standard), isFalse);

      final xauat = fixture('basic.html');
      expect(const StandardGridAdapter().canParse(xauat), isFalse);
    });

    test('parseAuto 选中西建大适配器', () {
      final result = SchoolAdapterRegistry.standard.parseAuto(fixture('basic.html'));
      expect(result.adapterId, 'XAUAT_01');
      expect(result.courses, hasLength(4));
    });
  });
}

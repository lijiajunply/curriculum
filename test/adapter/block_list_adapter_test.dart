import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:html/dom.dart';
import 'package:test/test.dart';

/// 绝对定位 div 课表的示例适配器。
class DemoBlockAdapter extends BlockListAdapter {
  const DemoBlockAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'DEMO_BLOCK_01',
    schoolId: 'DEMO',
    adapterName: '示例 div 网格课表',
    category: AdapterCategory.generalTool,
  );

  @override
  List<String> get requiredMarkers => const <String>['course-item'];

  @override
  String get blockSelector => '.course-item';

  @override
  DaySectionResolver get positionResolver => const DaySectionResolver.fromAttributes();

  @override
  CourseCellLayout get cellLayout => const OrderedLineLayout(
    order: <CourseField>[
      CourseField.name,
      CourseField.teacher,
      CourseField.weeks,
      CourseField.position,
    ],
  );
}

String fixture() => File('test/fixtures/generic/div_grid.html').readAsStringSync();

void main() {
  const adapter = DemoBlockAdapter();

  group('BlockListAdapter 端到端', () {
    late CourseImportResult result;

    setUpAll(() {
      result = adapter.parse(fixture());
    });

    test('解析出两门课，按 (星期, 节次) 排序', () {
      expect(result.courses, hasLength(2));
      expect(result.courses[0].name, '高等数学A');
      expect(result.courses[0].day, 1);
      expect(result.courses[0].startSection, 1);
      expect(result.courses[0].endSection, 2);
      expect(result.courses[0].weeks, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('data-span 决定节次跨度', () {
      final english = result.courses.firstWhere((c) => c.name == '大学英语（视听说）');
      expect(english.day, 3);
      expect(english.startSection, 3);
      expect(english.endSection, 4);
      expect(english.teacher, '李娜');
      expect(english.position, '外语楼203');
      expect(english.weeks, <int>[1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('没有 error 级诊断', () {
      expect(result.warnings.where((w) => w.severity == ParseSeverity.error), isEmpty);
    });

    test('adapterId 与统计被带上', () {
      expect(result.adapterId, 'DEMO_BLOCK_01');
      expect(result.stats.coursesEmitted, 2);
    });
  });

  group('DaySectionResolver', () {
    ParseContext ctx() => ParseContext(options: const ParseOptions());

    Element block(String attrs) {
      final html = '<div class="course-item" $attrs>高等数学</div>';
      return parseHtmlDocument(html).querySelector('.course-item')!;
    }

    test('fromAttributes 支持中文星期', () {
      final resolver = const DaySectionResolver.fromAttributes();
      final position = resolver.resolve(block('data-day="星期三" data-section="3"'), ctx());
      expect(position!.day, 3);
      expect(position.sections, const SectionRange(3, 3));
    });

    test('fromAttributes 默认跨度为 1，可配置', () {
      const resolver = DaySectionResolver.fromAttributes(defaultSpan: 2);
      final position = resolver.resolve(block('data-day="1" data-section="5"'), ctx());
      expect(position!.sections, const SectionRange(5, 6));
    });

    test('fromAttributes 缺少必要属性时返回 null', () {
      final resolver = const DaySectionResolver.fromAttributes();
      expect(resolver.resolve(block('data-section="1"'), ctx()), isNull);
      expect(resolver.resolve(block('data-day="1"'), ctx()), isNull);
      expect(resolver.resolve(block('data-day="9" data-section="1"'), ctx()), isNull);
    });

    test('fromDescendant 从子元素读「星期三第3-4节」', () {
      const resolver = DaySectionResolver.fromDescendant(selector: '.week-label');
      final html =
          '<div class="course-item">'
          '<span class="week-label">星期三第3-4节</span>高等数学</div>';
      final element = parseHtmlDocument(html).querySelector('.course-item')!;
      final position = resolver.resolve(element, ctx());
      expect(position!.day, 3);
      expect(position.sections, const SectionRange(3, 4));
    });

    test('fromStyle 从绝对定位推算', () {
      const resolver = DaySectionResolver.fromStyle(
        rowHeight: 50,
        columnWidth: 100,
        firstSection: 1,
        firstDay: 1,
      );
      final position = resolver.resolve(block('style="top:100px;left:200px;height:100px"'), ctx());
      expect(position!.day, 3);
      expect(position.sections, const SectionRange(3, 4));
    });

    test('fromStyle 缺少定位信息时返回 null', () {
      const resolver = DaySectionResolver.fromStyle();
      expect(resolver.resolve(block(''), ctx()), isNull);
    });
  });

  test('探测认结构标记', () {
    expect(adapter.canParse(fixture()), isTrue);
    expect(adapter.canParse('<html></html>'), isFalse);
  });
}

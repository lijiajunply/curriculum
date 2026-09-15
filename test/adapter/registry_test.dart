import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:html/dom.dart';
import 'package:test/test.dart';

/// 只按固定置信度命中的假适配器。
class FakeAdapter extends SchoolAdapter {
  const FakeAdapter(
    this.id, {
    this.confidence = 1,
    this.marker = '',
    this.category = AdapterCategory.bachelorAndAssociate,
    this.schoolId = 'FAKE',
  });

  final String id;
  final double confidence;
  final String marker;

  final AdapterCategory category;
  final String schoolId;

  @override
  SchoolAdapterInfo get info =>
      SchoolAdapterInfo(adapterId: id, schoolId: schoolId, adapterName: id, category: category);

  @override
  double detectConfidence(String html) => html.contains(marker) ? confidence : 0;

  @override
  CourseImportResult parseDocument(
    Document document, {
    ParseOptions options = const ParseOptions(),
  }) => CourseImportResult(
    courses: <Course>[Course(name: id, day: 1)],
    adapterId: id,
  );
}

String fixture() => File('test/fixtures/standard_grid/basic.html').readAsStringSync();

void main() {
  group('注册与查询', () {
    test('register / byId / unregister', () {
      final registry = SchoolAdapterRegistry();
      const adapter = FakeAdapter('A_01', marker: 'x');
      registry.register(adapter);
      expect(registry.byId('A_01'), same(adapter));
      expect(registry.byId('NOPE'), isNull);
      expect(registry.all(), hasLength(1));
      expect(registry.unregister('A_01'), isTrue);
      expect(registry.unregister('A_01'), isFalse);
      expect(registry.all(), isEmpty);
    });

    test('重复 id 默认抛错，override 时替换', () {
      final registry = SchoolAdapterRegistry();
      registry.register(const FakeAdapter('A_01', marker: 'x'));
      expect(() => registry.register(const FakeAdapter('A_01', marker: 'y')), throwsStateError);
      const replacement = FakeAdapter('A_01', marker: 'y');
      registry.register(replacement, override: true);
      expect(registry.all(), hasLength(1));
      expect(registry.byId('A_01'), same(replacement));
    });

    test('按类别与学校筛选', () {
      final registry = SchoolAdapterRegistry(<SchoolAdapter>[
        const FakeAdapter('A_01', category: AdapterCategory.generalTool),
        const FakeAdapter('B_01', category: AdapterCategory.postgraduate, schoolId: 'B'),
        const FakeAdapter('B_02', schoolId: 'B'),
      ]);
      expect(registry.byCategory(AdapterCategory.generalTool), hasLength(1));
      expect(registry.byCategory(AdapterCategory.postgraduate), hasLength(1));
      expect(registry.bySchoolId('B'), hasLength(2));
      expect(registry.bySchoolId('NOPE'), isEmpty);
    });

    test('all() 返回不可变列表', () {
      final registry = SchoolAdapterRegistry(<SchoolAdapter>[
        const FakeAdapter('A_01', marker: 'x'),
      ]);
      expect(
        () => registry.all().add(const FakeAdapter('Z_99', marker: 'z')),
        throwsUnsupportedError,
      );
    });
  });

  group('探测', () {
    test('按置信度降序', () {
      final registry = SchoolAdapterRegistry(<SchoolAdapter>[
        const FakeAdapter('LOW', marker: 'x', confidence: 1),
        const FakeAdapter('HIGH', marker: 'x', confidence: 1.4),
        const FakeAdapter('MID', marker: 'x', confidence: 1.2),
      ]);
      final ids = registry.detect('xx').map((c) => c.adapter.info.adapterId);
      expect(ids.toList(), <String>['HIGH', 'MID', 'LOW']);
    });

    test('置信度相同时后注册的优先，便于宿主盖过内置适配器', () {
      final registry = SchoolAdapterRegistry(<SchoolAdapter>[
        const FakeAdapter('BUILTIN', marker: 'x', confidence: 1),
        const FakeAdapter('USER', marker: 'x', confidence: 1),
      ]);
      expect(registry.detectBest('xx')!.adapter.info.adapterId, 'USER');
    });

    test('不命中的适配器不出现在候选里', () {
      final registry = SchoolAdapterRegistry(<SchoolAdapter>[
        const FakeAdapter('A', marker: 'needle'),
      ]);
      expect(registry.detect('haystack'), isEmpty);
      expect(registry.detectBest('haystack'), isNull);
    });
  });

  group('parseAuto', () {
    test('挑中标准网格适配器而不是兜底适配器', () {
      final result = SchoolAdapterRegistry.standard.parseAuto(fixture());
      expect(result.adapterId, 'STANDARD_GRID_01');
      expect(result.courses, hasLength(7));
    });

    test('无候选时返回带错误的空结果而不是抛异常', () {
      final registry = SchoolAdapterRegistry();
      final result = registry.parseAuto('<html><body>无关页面</body></html>');
      expect(result.isEmpty, isTrue);
      expect(result.hasErrors, isTrue);
      expect(result.warnings.single.kind, ParseWarningKind.noAdapterMatched);
    });

    test('只有兜底适配器可用时也能出结果', () {
      final html =
          '<html><body><table>'
          '<tr><td>节次</td><td>星期一</td><td>星期二</td></tr>'
          '<tr><td>第1-2节</td><td>高等数学<br>张伟<br>1-16周<br>教101</td>'
          '<td></td></tr>'
          '</table></body></html>';
      final result = SchoolAdapterRegistry.standard.parseAuto(html);
      expect(result.adapterId, 'GENERIC_MATRIX_01');
      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '高等数学');
    });
  });

  group('parseAs', () {
    test('指定 id 正常解析', () {
      final result = SchoolAdapterRegistry.standard.parseAs('STANDARD_GRID_01', fixture());
      expect(result.courses, hasLength(7));
    });

    test('未知 id 抛异常并列出已知 id', () {
      expect(
        () => SchoolAdapterRegistry.standard.parseAs('NOPE', fixture()),
        throwsA(
          isA<AdapterNotFoundException>()
              .having((e) => e.adapterId, 'adapterId', 'NOPE')
              .having((e) => e.knownIds, 'knownIds', isNotEmpty),
        ),
      );
    });
  });

  group('standard 注册表', () {
    test('含内置适配器', () {
      final ids = SchoolAdapterRegistry.standard.all().map((a) => a.info.adapterId).toList();
      expect(ids, contains('STANDARD_GRID_01'));
      expect(ids, contains('GENERIC_MATRIX_01'));
    });

    test('兜底适配器排在最后', () {
      final ids = SchoolAdapterRegistry.standard.all().map((a) => a.info.adapterId).toList();
      expect(ids.last, 'GENERIC_MATRIX_01');
    });

    test('多次访问是同一实例', () {
      expect(identical(SchoolAdapterRegistry.standard, SchoolAdapterRegistry.standard), isTrue);
    });

    test('兜底适配器的置信度最低', () {
      final candidates = SchoolAdapterRegistry.standard.detect(fixture());
      expect(candidates.first.adapter.info.adapterId, 'STANDARD_GRID_01');
      expect(candidates.last.adapter.info.adapterId, 'GENERIC_MATRIX_01');
      expect(candidates.last.confidence, lessThan(candidates.first.confidence));
    });
  });
}

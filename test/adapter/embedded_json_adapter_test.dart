import 'dart:convert';
import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

/// 内嵌 JSON 课表的示例适配器。
///
/// 各校的 JSON schema 是自己的，所以 `mapPayload` 天然是每校一段字段映射。
class DemoJsonAdapter extends EmbeddedJsonAdapter {
  const DemoJsonAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'DEMO_JSON_01',
    schoolId: 'DEMO',
    adapterName: '示例内嵌 JSON 课表',
    category: AdapterCategory.generalTool,
  );

  @override
  List<String> get requiredMarkers => const <String>['scheduleData'];

  @override
  JsonPayloadLocator get locator => const JsonPayloadLocator.scriptVar('scheduleData');

  @override
  List<Course> mapPayload(Object? payload, ParseContext ctx) {
    final map = payload as Map<String, dynamic>;
    final rows = map['data']! as List<dynamic>;
    final courses = <Course>[];
    for (final row in rows) {
      final item = row as Map<String, dynamic>;
      final section = item['djc']! as int;
      final weeks = parseWeeks(item['zcstr'] as String?)?.weeks ?? const <int>[];
      courses.add(
        Course(
          name: item['kcmc']! as String,
          teacher: (item['tmc'] as String?) ?? '',
          position: (item['croommc'] as String?) ?? '',
          day: item['xingqi']! as int,
          startSection: section,
          endSection: section,
          weeks: weeks,
        ),
      );
    }
    // 逐节次给出的记录并成连续区间。
    return mergeAdjacentSections(courses);
  }
}

String fixture() => File('test/fixtures/generic/script_payload.html').readAsStringSync();

void main() {
  const adapter = DemoJsonAdapter();

  group('EmbeddedJsonAdapter 端到端', () {
    late CourseImportResult result;

    setUpAll(() {
      result = adapter.parse(fixture());
    });

    test('字符串里的花括号不会打断 JSON 切片', () {
      final weird = result.courses.firstWhere((c) => c.name == '数据结构{实验}');
      expect(weird.teacher, '王强');
      expect(weird.position, '信息楼B301');
    });

    test('逐节次的记录被合并成连续区间', () {
      final math = result.courses.firstWhere((c) => c.name == '高等数学A');
      expect(math.day, 1);
      expect(math.startSection, 1);
      expect(math.endSection, 2);
      expect(math.weeks, <int>[1, 2, 3, 4]);
    });

    test('结果按 (星期, 节次) 排序', () {
      expect(result.courses.map((c) => c.name).toList(), <String>['高等数学A', '数据结构{实验}']);
      expect(result.courses[1].day, 3);
      expect(result.courses[1].startSection, 3);
      expect(result.courses[1].weeks, <int>[1, 3, 5]);
    });

    test('adapterId 被带上', () {
      expect(result.adapterId, 'DEMO_JSON_01');
    });
  });

  group('JsonPayloadLocator', () {
    ParseContext ctx() => ParseContext(options: const ParseOptions());

    test('scriptVar 找不到时返回 null', () {
      final doc = parseHtmlDocument('<html><script>var other = 1;</script></html>');
      expect(const JsonPayloadLocator.scriptVar('scheduleData').locate(doc, ctx()), isNull);
    });

    test('fromTextarea', () {
      final doc = parseHtmlDocument('<html><textarea id="payload">{"a":1}</textarea></html>');
      final payload = const JsonPayloadLocator.fromTextarea('payload').locate(doc, ctx());
      expect(payload, <String, dynamic>{'a': 1});
    });

    test('fromAttribute', () {
      final doc = parseHtmlDocument('<html><div id="app" data-schedule=\'{"a":2}\'></div></html>');
      final payload = const JsonPayloadLocator.fromAttribute('data-schedule').locate(doc, ctx());
      expect(payload, <String, dynamic>{'a': 2});
    });

    test('fromComment', () {
      final doc = parseHtmlDocument('<html><body><!--SCHEDULE_JSON {"a":3} --></body></html>');
      final payload = const JsonPayloadLocator.fromComment('SCHEDULE_JSON').locate(doc, ctx());
      expect(payload, <String, dynamic>{'a': 3});
    });

    test('载荷缺失时 parse 返回带 error 的空结果而非抛异常', () {
      final result = adapter.parse('<html><body>没有数据</body></html>');
      expect(result.isEmpty, isTrue);
      expect(result.hasErrors, isTrue);
      expect(result.warnings.single.kind, ParseWarningKind.payloadNotFound);
    });
  });

  group('sliceJsonAt 括号配对扫描', () {
    test('截出完整的对象', () {
      const text = 'var x = {"a":1,"b":{"c":2}};';
      expect(sliceJsonAt(text, 0), '{"a":1,"b":{"c":2}}');
    });

    test('字符串里的括号不影响深度', () {
      const text = 'var x = {"a":"}{","b":1};';
      final slice = sliceJsonAt(text, 0)!;
      expect(jsonDecode(slice), <String, dynamic>{'a': '}{', 'b': 1});
    });

    test('转义引号不影响判定', () {
      const text = r'var x = {"a":"say \"hi\""};';
      final slice = sliceJsonAt(text, 0)!;
      expect(jsonDecode(slice), <String, dynamic>{'a': 'say "hi"'});
    });

    test('数组载荷', () {
      expect(sliceJsonAt('var x = [1,2,3];', 0), '[1,2,3]');
    });

    test('没有载荷时返回 null', () {
      expect(sliceJsonAt('var x = 1;', 0), isNull);
      expect(sliceJsonAt('var x = {"a":1;', 0), isNull);
    });
  });
}

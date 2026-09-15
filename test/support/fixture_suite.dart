import 'dart:convert';
import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

/// 自动发现 `test/fixtures/**/<用例>.expected.json`，与同目录同名的 `.html`
/// 配对，按目录名解析出适配器，为每一对生成一个测试。
///
/// **投放两个文件 = 一个测试，零代码。** 新增真实样本的流程见
/// `test/fixtures/README.md`。
///
/// `_pending/` 下的样本还没有期望值，只做宽松断言：不抛异常，且要么产出课程、
/// 要么留下诊断。
void registerFixtureSuites({SchoolAdapterRegistry? registry, String root = 'test/fixtures'}) {
  final reg = registry ?? SchoolAdapterRegistry.standard;
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return;

  final files = rootDir.listSync(recursive: true).whereType<File>().map((f) => f.path).toList()
    ..sort();

  for (final path in files) {
    if (!path.endsWith('.expected.json')) continue;
    final htmlPath = '${path.substring(0, path.length - '.expected.json'.length)}.html';
    if (!File(htmlPath).existsSync()) {
      fail('缺少与 $path 配对的 HTML：$htmlPath');
    }
    final caseName = _stripExtension(_baseName(path));
    final groupName = _parentName(path);
    final adapter = _resolveAdapter(reg, groupName);

    group('fixture $groupName', () {
      test('$caseName 与期望 JSON 一致', () {
        final html = File(htmlPath).readAsStringSync();
        final expected = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        final result = adapter.parse(html);
        expect(result.toJson()['courses'], equals(expected['courses']));

        final errors = result.warnings.where((w) => w.severity == ParseSeverity.error).toList();
        expect(errors, isEmpty, reason: '期望值对上了但有 error 级诊断：\n${result.diagnosticReport}');
      });

      test('$caseName 解析结果可被 parseAuto 复现', () {
        final html = File(htmlPath).readAsStringSync();
        final result = reg.parseAuto(html);
        expect(result.courses, isNotEmpty, reason: '自动探测没能解析出课程：\n${result.diagnosticReport}');
      });
    });
  }

  for (final path in files) {
    if (!path.endsWith('.html')) continue;
    if (!_isPending(path)) continue;
    final caseName = _stripExtension(_baseName(path));
    final groupName = _parentName(path);
    test('pending $groupName/$caseName 不抛异常并给出结果或诊断', () {
      final html = File(path).readAsStringSync();
      late CourseImportResult result;
      expect(() => result = reg.parseAuto(html), returnsNormally);
      expect(
        result.courses.isNotEmpty || result.warnings.isNotEmpty,
        isTrue,
        reason: '既没有课程也没有诊断，说明静默吞掉了问题',
      );
    });
  }
}

/// 目录名 → 适配器。
///
/// 目录名（把 `-` 当作 `_`）大写后应当是某个适配器 id 的前缀，例如
/// `standard_grid` → `STANDARD_GRID_01`。
SchoolAdapter _resolveAdapter(SchoolAdapterRegistry registry, String groupName) {
  final key = groupName.replaceAll('-', '_').toUpperCase();
  for (final adapter in registry.all()) {
    if (adapter.info.adapterId.toUpperCase().startsWith(key)) return adapter;
  }
  for (final adapter in registry.all()) {
    if (adapter.info.schoolId.toUpperCase() == key) return adapter;
  }
  fail(
    '目录名 "$groupName" 无法对应到任何适配器。'
    '约定：目录名大写后应为某个 adapterId 的前缀。'
    '当前已注册：${registry.all().map((a) => a.info.adapterId).join(', ')}',
  );
}

bool _isPending(String path) => path.split(Platform.pathSeparator).contains('_pending');

String _baseName(String path) => path.split(Platform.pathSeparator).last;

String _parentName(String path) {
  final parts = path.split(Platform.pathSeparator);
  return parts.length >= 2 ? parts[parts.length - 2] : '';
}

String _stripExtension(String name) {
  final index = name.indexOf('.');
  return index < 0 ? name : name.substring(0, index);
}

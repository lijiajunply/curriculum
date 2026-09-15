import 'dart:io';

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

/// 文档漂移防护：README 与 CHANGELOG 必须跟上代码。
void main() {
  final readme = File('README.md').readAsStringSync();
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('每个内置适配器都在 README 的清单里', () {
    for (final adapter in buildBuiltinAdapters()) {
      expect(
        readme,
        contains(adapter.info.adapterId),
        reason: 'README 没有列出内置适配器 ${adapter.info.adapterId}',
      );
    }
  });

  test('CHANGELOG 有当前版本的条目', () {
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    expect(changelog, contains('## [$version]'), reason: 'CHANGELOG 缺少 $version 的条目');
  });

  test('LICENSE 不再是占位符', () {
    final license = File('LICENSE').readAsStringSync();
    expect(license, isNot(contains('TODO')));
    expect(license, contains('MIT License'));
  });

  test('README 不再有脚手架占位文字', () {
    expect(readme, isNot(contains('TODO: Put a short description')));
    expect(readme, isNot(contains('const like = ')));
  });

  test('示例可执行文件存在且被分析', () {
    expect(File('example/main.dart').existsSync(), isTrue);
  });

  test('样本目录有投放说明', () {
    expect(File('test/fixtures/README.md').existsSync(), isTrue);
  });
}

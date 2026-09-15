// 用法:
//   dart run example/main.dart <课表.html>
//   dart run example/main.dart <课表.html> --adapter STANDARD_GRID_01
//   dart run example/main.dart <课表.html> --json
//
// 不带 --json 时打印人类可读的课程列表与诊断报告；带 --json 时直接输出
// 拾光课程表 saveImportedCourses 接受的 JSON。
import 'dart:io';

import 'package:curriculum/curriculum.dart';

void main(List<String> args) {
  final positional = <String>[
    for (final arg in args)
      if (!arg.startsWith('--') && !_isFlagValue(args, arg)) arg,
  ];
  if (positional.isEmpty) {
    stderr.writeln(
      '用法: dart run example/main.dart <课表.html> '
      '[--adapter 适配器ID] [--json]',
    );
    exitCode = 64;
    return;
  }

  final file = File(positional.first);
  if (!file.existsSync()) {
    stderr.writeln('文件不存在: ${positional.first}');
    exitCode = 66;
    return;
  }
  final html = file.readAsStringSync();
  final registry = SchoolAdapterRegistry.standard;
  final adapterId = _flagValue(args, '--adapter');

  late final CourseImportResult result;
  try {
    result = adapterId != null ? registry.parseAs(adapterId, html) : registry.parseAuto(html);
  } on CurriculumException catch (error) {
    stderr.writeln('解析失败: $error');
    exitCode = 65;
    return;
  }

  if (args.contains('--json')) {
    stdout.writeln(result.toJsonString());
    return;
  }

  stdout.writeln('适配器: ${result.adapterId ?? '(未匹配)'}');
  if (result.courses.isEmpty) {
    stdout.writeln('没有解析出课程。');
  } else {
    for (final course in result.courses) {
      stdout.writeln(
        '  周${course.day} 第${course.startSection}-${course.endSection}节  '
        '${course.name}  ${course.teacher}  ${course.position}  '
        '周次 ${weekListToString(course.weeks)}',
      );
    }
  }
  if (result.timeSlots.isNotEmpty) {
    stdout.writeln('作息时间:');
    for (final slot in result.timeSlots) {
      stdout.writeln('  第${slot.number}节 ${slot.startTime}-${slot.endTime}');
    }
  }
  stdout.writeln();
  stdout.write(result.diagnosticReport);
}

bool _isFlagValue(List<String> args, String arg) {
  final index = args.indexOf(arg);
  return index > 0 && args[index - 1] == '--adapter';
}

String? _flagValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

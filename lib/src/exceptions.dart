import 'model/course_import_result.dart';
import 'model/parse_warning.dart';

/// 本库所有异常的基类。
sealed class CurriculumException implements Exception {
  /// 创建异常。
  const CurriculumException(this.message, {this.cause});

  /// 人类可读的说明。
  final String message;

  /// 底层原因（若有）。
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message'
      '${cause == null ? '' : ' (caused by: $cause)'}';
}

/// 输入的 HTML 为空或全是空白，无从解析。
final class HtmlParseException extends CurriculumException {
  /// 创建异常。
  const HtmlParseException(super.message, {super.cause});
}

/// 矩阵适配器在页面里没有找到可用的课表 `<table>`。
final class TableNotFoundException extends CurriculumException {
  /// 创建异常。
  const TableNotFoundException(super.message, {super.cause});
}

/// `parseAs()` 收到的适配器 id 未注册。
final class AdapterNotFoundException extends CurriculumException {
  /// 创建异常。
  AdapterNotFoundException(this.adapterId, {List<String> knownIds = const []})
    : knownIds = List<String>.unmodifiable(knownIds),
      super(
        '未注册的适配器 id: $adapterId'
        '${knownIds.isEmpty ? '' : '（已知：${knownIds.join(', ')}）'}',
      );

  /// 请求的适配器 id。
  final String adapterId;

  /// 当前注册表里已知的 id，便于排查拼写。
  final List<String> knownIds;
}

/// `parseAuto()` 在严格模式下未能匹配任何适配器。
final class NoAdapterMatchedException extends CurriculumException {
  /// 创建异常。
  const NoAdapterMatchedException(super.message, {super.cause});
}

/// 解析结果为空（或在严格模式下存在 error 级诊断）。
///
/// 只由 `parseOrThrow()` 抛出。携带完整诊断，便于调用方展示"我到底读懂了什么"。
final class ParseFailedException extends CurriculumException {
  /// 创建异常。
  ParseFailedException(super.message, {required List<ParseWarning> warnings, this.partial})
    : warnings = List<ParseWarning>.unmodifiable(warnings);

  /// 解析过程中收集到的全部诊断。
  final List<ParseWarning> warnings;

  /// 部分成功的解析结果（若有）。
  final CourseImportResult? partial;
}

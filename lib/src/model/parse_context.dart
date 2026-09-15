import 'parse_options.dart';
import 'parse_warning.dart';

/// 单条诊断里原始文本的最大保留长度。
const int kRawTextLimit = 200;

/// 解析流水线中唯一的可变状态：诊断收集器 + 计数器。
///
/// 解析全程只通过它报告问题，因此"跳过坏单元格还是整体失败"的策略只在这一处
/// 表达，各解析器不必各自决策。
class ParseContext {
  /// 创建一个解析上下文。
  ParseContext({required this.options, this.adapterId});

  /// 本次解析使用的选项。
  final ParseOptions options;

  /// 正在运行的适配器 id（若有）。
  final String? adapterId;

  /// 已收集的诊断，按产生顺序排列。
  final List<ParseWarning> warnings = <ParseWarning>[];

  /// 按分类统计的诊断条数（**不受** [ParseOptions.maxWarnings] 截断影响）。
  final Map<ParseWarningKind, int> counters = <ParseWarningKind, int>{};

  int _cellsSeen = 0;
  int _cellsParsed = 0;
  int _cellsSkipped = 0;
  int _coursesEmitted = 0;
  int _droppedWarnings = 0;
  int _errorCount = 0;

  /// 记录一条 info 级诊断。
  void info(ParseWarningKind kind, String message, {String? location, String? rawText}) =>
      _add(ParseWarning.info(kind, message, location: location, rawText: _truncate(rawText)));

  /// 记录一条 warning 级诊断。
  void warn(ParseWarningKind kind, String message, {String? location, String? rawText}) =>
      _add(ParseWarning.warn(kind, message, location: location, rawText: _truncate(rawText)));

  /// 记录一条 error 级诊断。
  void error(ParseWarningKind kind, String message, {String? location, String? rawText}) =>
      _add(ParseWarning.error(kind, message, location: location, rawText: _truncate(rawText)));

  /// 记录一个被检查的候选单元格。
  void recordCellSeen() => _cellsSeen++;

  /// 记录一个成功产出课程的单元格。
  void recordCellParsed() => _cellsParsed++;

  /// 记录一个因空白或无法理解而跳过的单元格。
  void recordCellSkipped() => _cellsSkipped++;

  /// 记录本次解析最终产出的课程条数。
  void recordCoursesEmitted(int count) => _coursesEmitted = count;

  /// 是否出现过 error 级诊断。
  ///
  /// 依据内部计数器而非 [warnings]，因此即使诊断因 [ParseOptions.maxWarnings]
  /// 触顶而未保存，也不会漏判。
  bool get hasErrors => _errorCount > 0;

  /// 汇总统计。
  ParseStats get stats => ParseStats(
    cellsSeen: _cellsSeen,
    cellsParsed: _cellsParsed,
    cellsSkipped: _cellsSkipped,
    coursesEmitted: _coursesEmitted,
    warningCount: warnings.length + _droppedWarnings,
  );

  /// 因超出上限而未保存的诊断条数。
  int get droppedWarnings => _droppedWarnings;

  void _add(ParseWarning warning) {
    counters[warning.kind] = (counters[warning.kind] ?? 0) + 1;
    if (warning.severity == ParseSeverity.error) _errorCount++;
    options.onWarning?.call(warning);
    if (warnings.length >= options.maxWarnings) {
      _droppedWarnings++;
      return;
    }
    warnings.add(warning);
  }

  static String? _truncate(String? text) {
    if (text == null) return null;
    return text.length <= kRawTextLimit ? text : '${text.substring(0, kRawTextLimit)}…';
  }
}

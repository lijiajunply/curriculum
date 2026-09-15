import 'parse_warning.dart';

/// 解析行为的开关集合。
///
/// 全部字段都有保守的默认值：默认配置下解析器**只产出页面确实提供了的信息**，
/// 不会凭空发明学期配置、不会丢弃边界情况下的课程。
class ParseOptions {
  /// 创建一组解析选项。
  const ParseOptions({
    this.emitConfig = false,
    this.keepRawCellText = false,
    this.mergeSameCourse = true,
    this.emptyWeeksMeansAllWeeks = true,
    this.expandMultiDayCells = false,
    this.emitTimeSlots = true,
    this.strict = false,
    this.maxWarnings = 500,
    this.onWarning,
  });

  /// 是否产出 [CourseConfig]。
  ///
  /// 默认 `false`，而且这个默认值很重要：上游拾光课程表的导入逻辑是
  /// `configJson?.defaultClassDuration ?: existing ?: 45`，也就是**非空 config 会
  /// 覆盖用户本地的上下课时长**。解析器无从得知某校真实的一节课多长，所以除非
  /// 页面确实写明了，否则不该产出 config。
  final bool emitConfig;

  /// 是否把单元格原文塞进 [Course.remark]，便于调用方核对解析结果。
  final bool keepRawCellText;

  /// 是否把同名同师同地点同节次的记录合并为一条（并集周次）。
  ///
  /// 默认 `true`。注意合并**不会**跨越不同的上课地点——一门课学期中换教室应当
  /// 保留为两个课程块。
  final bool mergeSameCourse;

  /// 当周次字段为空时，是否视为"全周"。
  ///
  /// 默认 `true`。置 `false` 时，周次为空的记录会被丢弃。
  final bool emptyWeeksMeansAllWeeks;

  /// 当一个单元格的 `colspan` 覆盖多个星期时，是否为每个星期各产出一门课。
  ///
  /// 默认 `false`（只认最左侧那一列）。真实课表里 `colspan` 跨列通常意味着
  /// 连堂，但也有学校用它表示"这几天都上"，按需开启。
  final bool expandMultiDayCells;

  /// 是否尝试从表头解析作息时间（[TimeSlot]）。
  final bool emitTimeSlots;

  /// 严格模式：解析结束后若存在 error 级诊断，则抛出 `ParseFailedException`。
  ///
  /// 默认 `false`。开启它等于放弃"永不丢失导入"的保证，只适合测试与调试。
  final bool strict;

  /// 收集诊断的上限；超出后仅计数不再保存，避免病态输入撑爆内存。
  final int maxWarnings;

  /// 每产生一条诊断就回调一次，便于宿主 App 做进度或日志流。
  final void Function(ParseWarning warning)? onWarning;

  /// 返回一个替换了部分字段的副本。
  ParseOptions copyWith({
    bool? emitConfig,
    bool? keepRawCellText,
    bool? mergeSameCourse,
    bool? emptyWeeksMeansAllWeeks,
    bool? expandMultiDayCells,
    bool? emitTimeSlots,
    bool? strict,
    int? maxWarnings,
    void Function(ParseWarning warning)? onWarning,
  }) => ParseOptions(
    emitConfig: emitConfig ?? this.emitConfig,
    keepRawCellText: keepRawCellText ?? this.keepRawCellText,
    mergeSameCourse: mergeSameCourse ?? this.mergeSameCourse,
    emptyWeeksMeansAllWeeks: emptyWeeksMeansAllWeeks ?? this.emptyWeeksMeansAllWeeks,
    expandMultiDayCells: expandMultiDayCells ?? this.expandMultiDayCells,
    emitTimeSlots: emitTimeSlots ?? this.emitTimeSlots,
    strict: strict ?? this.strict,
    maxWarnings: maxWarnings ?? this.maxWarnings,
    onWarning: onWarning ?? this.onWarning,
  );
}

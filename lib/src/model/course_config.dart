import 'json_utils.dart';

/// 课表学期配置，字段对齐拾光课程表的 `CourseConfigJsonModel`。
///
/// 解析器默认**不产出**这个对象，见 [ParseOptions.emitConfig]。
class CourseConfig {
  /// 创建一份学期配置。
  const CourseConfig({
    this.semesterStartDate,
    this.semesterTotalWeeks = 20,
    this.defaultClassDuration = 45,
    this.defaultBreakDuration = 10,
    this.firstDayOfWeek = 1,
  });

  /// 从 JSON 对象解码。
  factory CourseConfig.fromJson(Map<String, dynamic> json) => CourseConfig(
    semesterStartDate: json.asStringOrNull('semesterStartDate'),
    semesterTotalWeeks: json.asInt('semesterTotalWeeks', fallback: 20),
    defaultClassDuration: json.asInt('defaultClassDuration', fallback: 45),
    defaultBreakDuration: json.asInt('defaultBreakDuration', fallback: 10),
    firstDayOfWeek: json.asInt('firstDayOfWeek', fallback: 1),
  );

  /// 开学日期，`yyyy-MM-dd`。
  final String? semesterStartDate;

  /// 学期总周数。
  final int semesterTotalWeeks;

  /// 一节课的时长（分钟）。
  final int defaultClassDuration;

  /// 课间休息时长（分钟）。
  final int defaultBreakDuration;

  /// 一周的起始日，ISO 记法（周一 = 1）。
  ///
  /// 这是**展示设置**，不是解析产物。解析器恒产出 ISO 星期编号，因此这里保持
  /// 默认值 1；拿它去"修正"一张周日开头的表会导致表格被二次旋转。
  final int firstDayOfWeek;

  /// 编码为 JSON 对象。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'semesterStartDate': semesterStartDate,
    'semesterTotalWeeks': semesterTotalWeeks,
    'defaultClassDuration': defaultClassDuration,
    'defaultBreakDuration': defaultBreakDuration,
    'firstDayOfWeek': firstDayOfWeek,
  };

  /// 返回一个替换了部分字段的副本。
  CourseConfig copyWith({
    String? semesterStartDate,
    int? semesterTotalWeeks,
    int? defaultClassDuration,
    int? defaultBreakDuration,
    int? firstDayOfWeek,
  }) => CourseConfig(
    semesterStartDate: semesterStartDate ?? this.semesterStartDate,
    semesterTotalWeeks: semesterTotalWeeks ?? this.semesterTotalWeeks,
    defaultClassDuration: defaultClassDuration ?? this.defaultClassDuration,
    defaultBreakDuration: defaultBreakDuration ?? this.defaultBreakDuration,
    firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
  );

  @override
  bool operator ==(Object other) =>
      other is CourseConfig &&
      other.semesterStartDate == semesterStartDate &&
      other.semesterTotalWeeks == semesterTotalWeeks &&
      other.defaultClassDuration == defaultClassDuration &&
      other.defaultBreakDuration == defaultBreakDuration &&
      other.firstDayOfWeek == firstDayOfWeek;

  @override
  int get hashCode => Object.hash(
    semesterStartDate,
    semesterTotalWeeks,
    defaultClassDuration,
    defaultBreakDuration,
    firstDayOfWeek,
  );
}

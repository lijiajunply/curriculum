import 'section_parser.dart';

/// 课程解析的**不可约输入**：清洗过的文本行，加上已经确定的位置。
///
/// 矩阵单元格、`<div>` 课程块、内嵌 JSON 记录最终都归约成它，因此下游的
/// 字段抽取、节次解析、合并去重可以完全共用——这正是本库能同时覆盖
/// "时间网格"、"绝对定位 div"、"接口 JSON" 三类课表的原因。
class CourseSource {
  /// 创建一个课程来源。
  const CourseSource({
    required this.lines,
    required this.day,
    required this.sections,
    this.debugLabel,
    this.attributes = const <String, String>{},
  });

  /// 清洗后的文本行，见 `extractCellLines`。
  final List<String> lines;

  /// 星期，ISO 记法（周一 = 1 … 周日 = 7）。
  final int day;

  /// 由表格几何或文本标签解析出的节次跨度。
  final SectionRange sections;

  /// 形如 `r5.c3` 的位置标签，用于诊断。
  final String? debugLabel;

  /// 元素的 `data-*` 等属性，供需要读属性的布局使用。
  final Map<String, String> attributes;

  @override
  String toString() => 'CourseSource(${debugLabel ?? '?'}, 周$day, $sections, ${lines.length} 行)';
}

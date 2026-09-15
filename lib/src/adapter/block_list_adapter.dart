import 'package:html/dom.dart';

import '../grid/matrix_layout.dart' show dayNumberFromCharacter;
import '../model/course_import_result.dart';
import '../model/parse_context.dart';
import '../model/parse_options.dart';
import '../model/parse_warning.dart';
import '../parse/cell_text.dart';
import '../parse/course_cell_layout.dart';
import '../parse/course_source.dart';
import '../parse/course_source_parser.dart';
import '../parse/html_utils.dart';
import '../parse/section_parser.dart';
import 'school_adapter.dart';

/// 解析出的位置。
class DaySectionPosition {
  /// 创建位置。
  const DaySectionPosition({required this.day, required this.sections});

  /// 星期，ISO 记法。
  final int day;

  /// 节次跨度。
  final SectionRange sections;
}

/// 从课程块元素上读出它的 (星期, 节次)。
abstract class DaySectionResolver {
  /// 从 `data-*` 属性读。
  const factory DaySectionResolver.fromAttributes({
    String dayAttribute,
    String startAttribute,
    String spanAttribute,
    int defaultSpan,
    int maxSection,
  }) = _FromAttributes;

  /// 从块内的某个后代元素读位置文本，例如 `.week-label` 里的 `星期三第3-4节`。
  const factory DaySectionResolver.fromDescendant({required String selector, int maxSection}) =
      _FromDescendant;

  /// 从绝对定位的 `style` 推：`top`/`height` 定节次，`left`/`width` 定星期列。
  const factory DaySectionResolver.fromStyle({
    double rowHeight,
    double columnWidth,
    double topOffset,
    double leftOffset,
    int firstSection,
    int firstDay,
    int maxSection,
  }) = _FromStyle;

  /// 解析位置；无法确定返回 null。
  DaySectionPosition? resolve(Element block, ParseContext ctx);
}

int? _dayFromValue(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final direct = int.tryParse(trimmed);
  if (direct != null) return direct >= 1 && direct <= 7 ? direct : null;
  final match = RegExp('[一二三四五六日天]').firstMatch(trimmed);
  if (match == null) return null;
  return dayNumberFromCharacter(match.group(0)!);
}

double? _pixels(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'(-?\d+(?:\.\d+)?)\s*(?:px)?').firstMatch(raw.trim());
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

Map<String, String> _inlineStyle(Element element) {
  final raw = elementAttribute(element, 'style');
  if (raw == null) return const <String, String>{};
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final index = part.indexOf(':');
    if (index <= 0) continue;
    out[part.substring(0, index).trim().toLowerCase()] = part.substring(index + 1).trim();
  }
  return out;
}

class _FromAttributes implements DaySectionResolver {
  const _FromAttributes({
    this.dayAttribute = 'data-day',
    this.startAttribute = 'data-section',
    this.spanAttribute = 'data-span',
    this.defaultSpan = 1,
    this.maxSection = 20,
  });

  final String dayAttribute;
  final String startAttribute;
  final String spanAttribute;
  final int defaultSpan;
  final int maxSection;

  @override
  DaySectionPosition? resolve(Element block, ParseContext ctx) {
    final day = _dayFromValue(elementAttribute(block, dayAttribute));
    if (day == null) return null;
    final start = int.tryParse(elementAttribute(block, startAttribute)?.trim() ?? '');
    if (start == null || start < 1 || start > maxSection) return null;
    final span = int.tryParse(elementAttribute(block, spanAttribute)?.trim() ?? '') ?? defaultSpan;
    final end = start + (span < 1 ? 1 : span) - 1;
    return DaySectionPosition(
      day: day,
      sections: SectionRange(start, end > maxSection ? maxSection : end),
    );
  }
}

class _FromDescendant implements DaySectionResolver {
  const _FromDescendant({required this.selector, this.maxSection = 20});

  final String selector;
  final int maxSection;

  @override
  DaySectionPosition? resolve(Element block, ParseContext ctx) {
    final label = block.querySelector(selector);
    if (label == null) return null;
    final text = extractCellLines(label, keepWideGaps: false).join('');
    final dayMatch = RegExp('(?:星期|周|礼拜)\\s*([一二三四五六日天])').firstMatch(text);
    final day = dayMatch == null ? _dayFromValue(text) : dayNumberFromCharacter(dayMatch.group(1)!);
    if (day == null) return null;
    final sections = parseSections(text, maxSection: maxSection);
    if (sections == null) return null;
    return DaySectionPosition(day: day, sections: sections);
  }
}

class _FromStyle implements DaySectionResolver {
  const _FromStyle({
    this.rowHeight = 50,
    this.columnWidth = 100,
    this.topOffset = 0,
    this.leftOffset = 0,
    this.firstSection = 1,
    this.firstDay = 1,
    this.maxSection = 20,
  });

  final double rowHeight;
  final double columnWidth;
  final double topOffset;
  final double leftOffset;
  final int firstSection;
  final int firstDay;
  final int maxSection;

  @override
  DaySectionPosition? resolve(Element block, ParseContext ctx) {
    final style = _inlineStyle(block);
    final top = _pixels(style['top']);
    final left = _pixels(style['left']);
    if (top == null || left == null) return null;
    if (rowHeight <= 0 || columnWidth <= 0) return null;

    final start = firstSection + ((top - topOffset) / rowHeight).round();
    if (start < 1 || start > maxSection) return null;
    final height = _pixels(style['height']) ?? rowHeight;
    final span = (height / rowHeight).round().clamp(1, maxSection);
    final end = start + span - 1;

    final day = firstDay + ((left - leftOffset) / columnWidth).round();
    if (day < 1 || day > 7) return null;

    return DaySectionPosition(
      day: day,
      sections: SectionRange(start, end > maxSection ? maxSection : end),
    );
  }
}

/// 绝对定位 `<div>` 课表的适配器基类。
///
/// 一些较新的教务系统把课表渲染成一个个带 `data-day` / `style="top:…"` 的课程块，
/// 而不是 `<table>`。这类页面复用同一套 [CourseCellLayout] 与 `parseCourseSources`，
/// 差别只在于 `(lines, day, sections)` 的来源不同——这正是 `CourseSource` 接缝的价值。
abstract class BlockListAdapter extends SchoolAdapter {
  /// 创建适配器。
  const BlockListAdapter();

  /// 选中课程块的选择器，例如 `.course-item`。
  String get blockSelector;

  /// 块内文本到记录的布局。
  CourseCellLayout get cellLayout;

  /// 位置解析策略。
  DaySectionResolver get positionResolver;

  /// 周次缺失时的展开上界。
  int get defaultMaxWeek => 20;

  @override
  CourseImportResult parseDocument(
    Document document, {
    ParseOptions options = const ParseOptions(),
  }) {
    final ctx = ParseContext(options: options, adapterId: info.adapterId);
    final sources = <CourseSource>[];

    for (final block in document.querySelectorAll(blockSelector)) {
      ctx.recordCellSeen();
      final lines = extractCellLines(block);
      if (isBlankCell(lines)) {
        ctx.recordCellSkipped();
        continue;
      }
      final position = positionResolver.resolve(block, ctx);
      if (position == null) {
        ctx.warn(
          ParseWarningKind.unknownPosition,
          '无法从该课程块确定星期与节次',
          location: elementPath(block),
          rawText: lines.join(' / '),
        );
        ctx.recordCellSkipped();
        continue;
      }
      sources.add(
        CourseSource(
          lines: lines,
          day: position.day,
          sections: position.sections,
          debugLabel: elementPath(block),
          attributes: <String, String>{
            for (final entry in block.attributes.entries) entry.key.toString(): entry.value,
          },
        ),
      );
    }

    final courses = parseCourseSources(sources, cellLayout, ctx, defaultMaxWeek: defaultMaxWeek);
    return CourseImportResult(
      courses: courses,
      warnings: ctx.warnings,
      adapterId: info.adapterId,
      stats: ctx.stats,
    );
  }
}

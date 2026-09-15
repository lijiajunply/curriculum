import 'package:html/dom.dart';

import '../grid/cell_position.dart';
import '../grid/matrix_layout.dart';
import '../grid/table_grid.dart';
import '../model/course.dart';
import '../model/course_config.dart';
import '../model/course_import_result.dart';
import '../model/parse_context.dart';
import '../model/parse_options.dart';
import '../model/parse_warning.dart';
import '../model/time_slot.dart';
import '../parse/cell_text.dart';
import '../parse/course_source.dart';
import '../parse/course_source_parser.dart';
import '../parse/time_slot_parser.dart';
import 'school_adapter.dart';

/// 矩阵式课表的通用解析流水线。
///
/// 从归一化网格到课程列表的全部步骤都在这里，各校适配器只需要给出一份
/// [MatrixTableConfig]。
class MatrixTimetableParser {
  /// 创建解析器。
  const MatrixTimetableParser(this.config);

  /// 布局配置。
  final MatrixTableConfig config;

  /// 解析一张课表。
  CourseImportResult run(Element table, ParseContext ctx) {
    var grid = TableGrid.from(table, context: ctx);
    if (config.orientation == MatrixOrientation.daysAreRows) {
      grid = grid.transposed();
    }

    final columnToDay = config.dayColumns.resolve(grid, ctx);
    final rowSections = config.sectionMapping.build(grid, ctx);

    final sources = <CourseSource>[];
    if (columnToDay.isEmpty) {
      ctx.error(ParseWarningKind.detectionFailed, '没能确定任何星期列，无法继续');
    } else if (rowSections.isEmpty) {
      ctx.error(ParseWarningKind.noSectionForRow, '没能确定任何行的节次，无法继续');
    } else {
      _collectSources(grid, columnToDay, rowSections, sources, ctx);
    }

    final courses = parseCourseSources(
      sources,
      config.cellLayout,
      ctx,
      defaultMaxWeek: config.defaultMaxWeek,
    );

    return CourseImportResult(
      courses: courses,
      timeSlots: _timeSlots(table, ctx),
      config: ctx.options.emitConfig ? _inferConfig(courses) : null,
      warnings: ctx.warnings,
      adapterId: ctx.adapterId,
      stats: ctx.stats,
    );
  }

  void _collectSources(
    TableGrid grid,
    Map<int, int> columnToDay,
    RowSectionMap rowSections,
    List<CourseSource> sources,
    ParseContext ctx,
  ) {
    for (var r = config.headerRowCount; r < grid.rowCount; r++) {
      if (rowSections.isBannerRow(r)) {
        ctx.info(ParseWarningKind.skippedBannerRow, '第 $r 行是上午/下午之类的分隔横幅，整行跳过', location: 'r$r');
        continue;
      }

      for (final entry in columnToDay.entries) {
        final column = entry.key;
        if (column < config.headerColumnCount) continue;
        if (column >= grid.columnCount) continue;

        final cell = grid.cellAt(r, column);
        final element = cell.element;
        // 跨行/跨列填充出来的槽位不是宿主，跳过；一个 rowspan 单元格只会在它
        // 最上面那一行作为宿主出现一次，所以这里不需要任何"是否见过"的集合。
        if (cell.kind != GridCellKind.origin || element == null) continue;

        final position = config.positionResolver.resolve(
          PositionQuery(cell: cell, grid: grid, columnToDay: columnToDay, rowSections: rowSections),
          ctx,
        );
        if (position == null) {
          ctx.warn(ParseWarningKind.noSectionForRow, '无法确定该单元格属于哪一节', location: cell.debugLabel);
          continue;
        }

        final lines = extractCellLines(element);
        if (isBlankCell(lines, config.blankCellTokens)) {
          ctx.recordCellSeen();
          ctx.recordCellSkipped();
          continue;
        }

        final days = <int>[position.day];
        if (ctx.options.expandMultiDayCells) {
          for (var dc = 1; dc < cell.colSpan; dc++) {
            final next = columnToDay[column + dc];
            // 只跨**连续的**星期，`colspan=3` 跨五六日时不会溢出成星期 8。
            if (next != null && next == position.day + dc) days.add(next);
          }
          if (days.length > 1) {
            ctx.info(
              ParseWarningKind.multiDayCell,
              'colspan 跨了 ${days.length} 天，逐天各产出一条',
              location: cell.debugLabel,
            );
          }
        }

        for (final day in days) {
          sources.add(
            CourseSource(
              lines: lines,
              day: day,
              sections: position.sections,
              debugLabel: cell.debugLabel,
            ),
          );
        }
      }
    }
  }

  List<TimeSlot> _timeSlots(Element table, ParseContext ctx) {
    if (!config.extractTimeSlots || !ctx.options.emitTimeSlots) {
      return const <TimeSlot>[];
    }
    return parseTimeSlots(table, maxSection: config.maxSection);
  }

  /// 只推断得出学期总周数；其余字段是默认值，**不要**拿它去覆盖用户本地设置。
  CourseConfig? _inferConfig(List<Course> courses) {
    var maxWeek = 0;
    for (final course in courses) {
      for (final week in course.weeks) {
        if (week > maxWeek) maxWeek = week;
      }
    }
    if (maxWeek <= 0) return null;
    return CourseConfig(semesterTotalWeeks: maxWeek);
  }
}

/// 矩阵式课表适配器的基类。
///
/// 子类通常只需要覆写 [info]、[requiredMarkers] 与 [config] 三处。
abstract class MatrixTableAdapter extends SchoolAdapter {
  /// 创建适配器。
  const MatrixTableAdapter();

  /// 静态课表布局配置。
  ///
  /// 只有需要按页面内容动态决定配置时才覆写 [configFor] 而不覆写本 getter。
  MatrixTableConfig get config => throw UnsupportedError('$runtimeType 必须覆写 config 或 configFor 之一');

  /// 允许按页面内容动态给出配置，例如从页头读出学期周数、或在多张表里挑一张。
  MatrixTableConfig configFor(Document document) => config;

  @override
  CourseImportResult parseDocument(
    Document document, {
    ParseOptions options = const ParseOptions(),
  }) {
    final ctx = ParseContext(options: options, adapterId: info.adapterId);
    final effective = configFor(document);
    final table = effective.tableLocator.select(document);
    if (table == null) {
      ctx.error(ParseWarningKind.tableNotFound, '没找到匹配的课表：${effective.tableLocator.describe()}');
      return CourseImportResult(
        courses: const <Course>[],
        warnings: ctx.warnings,
        adapterId: info.adapterId,
        stats: ctx.stats,
      );
    }
    return MatrixTimetableParser(effective).run(table, ctx);
  }
}

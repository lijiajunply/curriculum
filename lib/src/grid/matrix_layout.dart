import 'dart:math' as math;

import '../model/parse_context.dart';
import '../model/parse_warning.dart';
import '../parse/cell_text.dart';
import '../parse/course_cell_layout.dart';
import '../parse/html_utils.dart';
import '../parse/section_parser.dart';
import 'cell_position.dart';
import 'table_grid.dart';

/// 匹配 `星期一`、`周三`、`礼拜天` 这类标签。
final RegExp _dayLabel = RegExp('(?:星期|周|礼拜)\\s*([$kDayCharacters天])');

/// 把汉字转换成 ISO 星期编号；无法识别返回 null。
int? dayNumberFromCharacter(String char) {
  if (char == '天') return 7;
  final index = kDayCharacters.indexOf(char);
  return index < 0 ? null : index + 1;
}

/// 网格列号到星期的映射策略。
abstract class DayColumns {
  /// 从表头文本里认星期标签。
  ///
  /// 扫描前 [maxHeaderRows] 行，取**匹配最多**的那一行——这样
  /// `<th colspan="7">星期</th>` 那一行会输给下面更具体的一行。只认到周五的表
  /// 就只产出 5 天的映射，周末自然不被扫描。
  const factory DayColumns.headerLabels({int maxHeaderRows, Map<int, int>? overrides}) =
      _HeaderLabels;

  /// 按列号顺序硬编码：第 `firstColumn` 列是 `firstDay`，依次递增。
  const factory DayColumns.byIndex({required int firstColumn, int firstDay, int dayCount}) =
      _ByIndex;

  /// 直接给出列到星期的映射。
  const factory DayColumns.explicit(Map<int, int> columnToDay) = _Explicit;

  /// 解析出「网格列号 -> ISO 星期」；识别失败时返回空映射。
  Map<int, int> resolve(TableGrid grid, ParseContext ctx);
}

class _HeaderLabels implements DayColumns {
  const _HeaderLabels({this.maxHeaderRows = 3, this.overrides});

  final int maxHeaderRows;
  final Map<int, int>? overrides;

  @override
  Map<int, int> resolve(TableGrid grid, ParseContext ctx) {
    var best = <int, int>{};
    final limit = math.min(maxHeaderRows, grid.rowCount);
    for (var r = 0; r < limit; r++) {
      final found = <int, int>{};
      for (var c = 0; c < grid.columnCount; c++) {
        final cell = grid.cellAt(r, c);
        final element = cell.element;
        if (cell.kind != GridCellKind.origin || element == null) continue;
        final text = extractCellLines(element, keepWideGaps: false).join('');
        final match = _dayLabel.firstMatch(text);
        final char = match?.group(1) ?? (text.trim().length == 1 ? text.trim() : null);
        if (char == null) continue;
        final day = dayNumberFromCharacter(char);
        if (day == null) continue;
        found[c] = day;
      }
      if (found.length > best.length) best = found;
    }

    final overridesMap = overrides;
    if (overridesMap != null) {
      for (final entry in overridesMap.entries) {
        best[entry.key] = entry.value;
      }
    }

    if (best.isEmpty) {
      ctx.warn(ParseWarningKind.detectionFailed, '表头里没找到星期标签');
    }
    return best;
  }
}

class _ByIndex implements DayColumns {
  const _ByIndex({required this.firstColumn, this.firstDay = 1, this.dayCount = 7});

  final int firstColumn;
  final int firstDay;
  final int dayCount;

  @override
  Map<int, int> resolve(TableGrid grid, ParseContext ctx) => <int, int>{
    for (var i = 0; i < dayCount; i++)
      if (firstColumn + i < grid.columnCount) firstColumn + i: firstDay + i,
  };
}

class _Explicit implements DayColumns {
  const _Explicit(this.columnToDay);

  final Map<int, int> columnToDay;

  @override
  Map<int, int> resolve(TableGrid grid, ParseContext ctx) => Map<int, int>.of(columnToDay);
}

/// 行号到节次的映射策略。
abstract class SectionMapping {
  /// 从某一列（通常是第 0 列）的 `第X节` 标签读节次。
  const factory SectionMapping.labelColumn({required int column, bool fillDown, int maxSection}) =
      _LabelColumn;

  /// 行号即节次：第 `headerRowCount` 行是第一节课。
  const factory SectionMapping.rowIndex({
    required int headerRowCount,
    int firstSection,
    int maxSection,
  }) = _RowIndex;

  /// 构建行到节次的映射。
  RowSectionMap build(TableGrid grid, ParseContext ctx);
}

class _LabelColumn implements SectionMapping {
  const _LabelColumn({required this.column, this.fillDown = true, this.maxSection = 20});

  final int column;
  final bool fillDown;
  final int maxSection;

  @override
  RowSectionMap build(TableGrid grid, ParseContext ctx) {
    final byRow = List<SectionRange?>.filled(grid.rowCount, null);
    final banner = List<bool>.filled(grid.rowCount, false);
    SectionRange? previous;

    for (var r = 0; r < grid.rowCount; r++) {
      if (isBannerRow(grid, r)) {
        banner[r] = true;
        continue;
      }
      if (column >= grid.columnCount) continue;

      final cell = grid.cellAt(r, column);
      final host = cell.isOrigin ? cell : cell.origin;
      var text = '';
      final element = host?.element;
      if (element != null) {
        text = extractCellLines(element, keepWideGaps: false).join('');
      }

      final span = host?.rowSpan ?? 1;
      final parsed = parseSections(text, maxSection: maxSection);
      if (parsed == null) {
        if (fillDown && previous != null) {
          byRow[r] = previous;
        }
        continue;
      }

      if (parsed.length == span && span > 1) {
        // 标签写 `第1-2节` 且跨两行：逐行拆开，第 r+i 行就是第 start+i 节。
        for (var i = 0; i < span && r + i < grid.rowCount; i++) {
          byRow[r + i] = SectionRange(parsed.start + i, parsed.start + i);
        }
      } else {
        for (var i = 0; i < span && r + i < grid.rowCount; i++) {
          byRow[r + i] = parsed;
        }
      }
      previous = parsed;
    }

    return RowSectionMap._(byRow, banner);
  }
}

class _RowIndex implements SectionMapping {
  const _RowIndex({required this.headerRowCount, this.firstSection = 1, this.maxSection = 20});

  final int headerRowCount;
  final int firstSection;
  final int maxSection;

  @override
  RowSectionMap build(TableGrid grid, ParseContext ctx) {
    final byRow = List<SectionRange?>.filled(grid.rowCount, null);
    final banner = List<bool>.filled(grid.rowCount, false);
    var section = firstSection;
    for (var r = 0; r < grid.rowCount; r++) {
      if (r < headerRowCount) continue;
      if (isBannerRow(grid, r)) {
        banner[r] = true;
        continue;
      }
      if (section > maxSection) break;
      byRow[r] = SectionRange(section, section);
      section++;
    }
    return RowSectionMap._(byRow, banner);
  }
}

/// 行到节次的映射结果。
class RowSectionMap {
  const RowSectionMap._(this.byRow, this._banner);

  /// 每一行对应的节次；表头行与横幅行为 null。
  final List<SectionRange?> byRow;

  final List<bool> _banner;

  /// 该行是否是横幅行。
  bool isBannerRow(int row) => row >= 0 && row < _banner.length && _banner[row];

  /// 是否一行节次都没解析出来。
  bool get isEmpty => byRow.every((r) => r == null);

  /// 一个从 [firstRow] 起、纵向跨 [rowSpan] 行的单元格覆盖的节次范围。
  ///
  /// 逐行走而不是只看首行，这样「标签列写 `第1-2节 / 第3-4节`、内容单元格
  /// `rowspan=2`」的组合能正确得到 1–4。
  SectionRange? extentFor(int firstRow, int rowSpan) {
    SectionRange? result;
    final last = math.min(firstRow + rowSpan, byRow.length);
    for (var r = firstRow; r < last; r++) {
      final range = byRow[r];
      if (range == null) continue;
      result = result == null
          ? range
          : SectionRange(math.min(result.start, range.start), math.max(result.end, range.end));
    }
    return result;
  }
}

/// 一行是否是「上午 / 下午 / 晚上」这类横幅行。
///
/// 判定依据是结构：整行只有一个 origin 单元格且它 `colSpan` 覆盖整行。这类行
/// 若不跳过，会被当成一个节次并把后面所有课程整体错位——这是仅次于 `rowspan`
/// 的真实故障源。
bool isBannerRow(TableGrid grid, int row) {
  final origins = <GridCell>[
    for (var c = 0; c < grid.columnCount; c++)
      if (grid.cellAt(row, c).isOrigin) grid.cellAt(row, c),
  ];
  if (origins.length != 1) return false;
  return origins.first.colSpan >= grid.columnCount;
}

/// 课表的方向。
enum MatrixOrientation {
  /// 列为星期、行为节次（标准时间网格）。
  daysAreColumns,

  /// 行为星期、列为节次。
  ///
  /// 解析时先对网格做转置，因此 [MatrixTableConfig] 里的所有数值都应当按
  /// **转置之后**的网格来描述。注意这对「正方列表视图」那种两列文字列表并不
  /// 适用——那不是矩阵，应当用块列表适配器。
  daysAreRows,
}

/// 一个矩阵课表的全部解析配置。
class MatrixTableConfig {
  /// 创建配置。
  const MatrixTableConfig({
    required this.headerRowCount,
    required this.dayColumns,
    required this.sectionMapping,
    required this.cellLayout,
    this.tableLocator = const TableLocator.first(),
    this.headerColumnCount = 1,
    this.orientation = MatrixOrientation.daysAreColumns,
    this.positionResolver = const CellPositionResolver.geometry(),
    this.maxSection = 20,
    this.defaultMaxWeek = 20,
    this.blankCellTokens = kDefaultBlankTokens,
    this.extractTimeSlots = true,
  });

  /// 定位课表 `<table>` 的策略。
  final TableLocator tableLocator;

  /// 表头占用的行数，从这些行之后开始扫课程。
  final int headerRowCount;

  /// 左侧标签列占用的列数（通常是「节次」那一列）。
  final int headerColumnCount;

  /// 列到星期的映射策略。
  final DayColumns dayColumns;

  /// 行到节次的映射策略。
  final SectionMapping sectionMapping;

  /// 单元格内容到记录的布局。
  final CourseCellLayout cellLayout;

  /// 课表方向。
  final MatrixOrientation orientation;

  /// 位置解析策略。
  final CellPositionResolver positionResolver;

  /// 节次的合理上界。
  final int maxSection;

  /// 周次缺失或为「全周」时的展开上界。
  final int defaultMaxWeek;

  /// 视为空单元格的占位文本。
  final List<String> blankCellTokens;

  /// 是否尝试从表头抽取作息时间。
  final bool extractTimeSlots;
}

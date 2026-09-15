import '../model/parse_context.dart';
import '../model/parse_warning.dart';
import '../parse/html_utils.dart';
import '../parse/section_parser.dart';
import 'matrix_layout.dart';
import 'table_grid.dart';

/// 一个单元格解析出的位置。
class CellPosition {
  /// 创建位置。
  const CellPosition({required this.day, required this.sections});

  /// 星期，ISO 记法（周一 = 1 … 周日 = 7）。
  final int day;

  /// 节次跨度。
  final SectionRange sections;

  @override
  String toString() => '周$day $sections';
}

/// 位置解析所需的全部上下文。
class PositionQuery {
  /// 创建查询。
  const PositionQuery({
    required this.cell,
    required this.grid,
    required this.columnToDay,
    required this.rowSections,
  });

  /// 当前单元格。
  final GridCell cell;

  /// 归一化网格。
  final TableGrid grid;

  /// 网格列号到星期的映射。
  final Map<int, int> columnToDay;

  /// 行到节次的映射。
  final RowSectionMap rowSections;
}

/// 默认的单元格 `id` 形态：正方 `3-5`、URP `3_5`，都是「星期-节次」。
///
/// 第一条捕获组是星期，第二条是节次。
final List<RegExp> kDefaultCellIdPatterns = List<RegExp>.unmodifiable(<RegExp>[
  RegExp(r'^(\d+)_(\d+)$'),
  RegExp(r'^(\d+)-(\d+)$'),
]);

/// 从一个单元格推断它属于哪一天、哪几节。
///
/// 真实课表有三类位置来源，对应用三种解析器：
/// - [CellPositionResolver.geometry]：从网格行列与 `rowSpan` 推，适用于标准矩阵表。
/// - [CellPositionResolver.byId]：从 `td` 的 `id` 属性读。这是**最常见**的一类——
///   226 个上游适配器里只有 15 个需要处理 `rowspan`，其余都把位置编码在属性里。
/// - [CellPositionResolver.byIndex]：行索引即节次、列索引即星期，适用于无表头的裸表。
abstract class CellPositionResolver {
  /// 纯几何：列→星期映射 + 行→节次映射。
  const factory CellPositionResolver.geometry() = _GeometryPosition;

  /// 从 `id` 属性读位置，失败时回退到几何。
  ///
  /// 不是 const 构造：默认正则表是运行期构造的。
  factory CellPositionResolver.byId({List<RegExp>? patterns, int maxSection}) = _IdPosition;

  /// 索引推算：列号减偏移即星期，行号由 `SectionMapping.rowIndex` 给出。
  const factory CellPositionResolver.byIndex({
    required int firstDayColumn,
    int firstDay,
    int dayCount,
  }) = _IndexPosition;

  /// 解析位置；无法确定时返回 null。
  CellPosition? resolve(PositionQuery query, ParseContext ctx);
}

class _GeometryPosition implements CellPositionResolver {
  const _GeometryPosition();

  @override
  CellPosition? resolve(PositionQuery query, ParseContext ctx) {
    final day = query.columnToDay[query.cell.column];
    if (day == null) return null;
    final sections = query.rowSections.extentFor(query.cell.row, query.cell.rowSpan);
    if (sections == null) return null;
    return CellPosition(day: day, sections: sections);
  }
}

class _IdPosition implements CellPositionResolver {
  _IdPosition({List<RegExp>? patterns, this.maxSection = 20})
    : patterns = patterns ?? kDefaultCellIdPatterns;

  final List<RegExp> patterns;
  final int maxSection;

  @override
  CellPosition? resolve(PositionQuery query, ParseContext ctx) {
    final element = query.cell.element;
    if (element != null) {
      final id = elementAttribute(element, 'id')?.trim();
      if (id != null && id.isNotEmpty) {
        for (final pattern in patterns) {
          final match = pattern.firstMatch(id);
          if (match == null) continue;
          final day = int.tryParse(match.group(1)!);
          final section = int.tryParse(match.group(2)!);
          if (day == null || section == null) continue;
          if (day < 1 || day > 7) continue;
          if (section < 1 || section > maxSection) continue;
          final end = section + query.cell.rowSpan - 1;
          if (end > maxSection) {
            ctx.warn(
              ParseWarningKind.sectionOutOfRange,
              'id="$id" 推出的节次越界，已钳制',
              location: query.cell.debugLabel,
            );
          }
          return CellPosition(
            day: day,
            sections: SectionRange(section, end > maxSection ? maxSection : end),
          );
        }
      }
    }
    // id 不可用时退回几何，而不是整格作废。
    return const _GeometryPosition().resolve(query, ctx);
  }
}

class _IndexPosition implements CellPositionResolver {
  const _IndexPosition({required this.firstDayColumn, this.firstDay = 1, this.dayCount = 7});

  final int firstDayColumn;
  final int firstDay;
  final int dayCount;

  @override
  CellPosition? resolve(PositionQuery query, ParseContext ctx) {
    final offset = query.cell.column - firstDayColumn;
    if (offset < 0 || offset >= dayCount) return null;
    final sections = query.rowSections.extentFor(query.cell.row, query.cell.rowSpan);
    if (sections == null) return null;
    return CellPosition(day: firstDay + offset, sections: sections);
  }
}

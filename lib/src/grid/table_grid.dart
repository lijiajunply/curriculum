import 'package:html/dom.dart';

import '../model/parse_context.dart';
import '../model/parse_options.dart';
import '../model/parse_warning.dart';
import '../parse/html_utils.dart';

/// `colspan` 的钳制上界。
///
/// 真实课表不会有这么多列；这个值只用来兜住 `colspan="999999"` 这类脏数据，
/// 免得一行就被撑成几十万个槽位。
const int _kMaxColumns = 1000;

/// 网格里一个槽位的性质。
enum GridCellKind {
  /// 该槽位由一个真实的 `<td>`/`<th>` 占据，`rowSpan` / `colSpan` 描述其跨度。
  origin,

  /// 该槽位被邻居的 `rowspan` / `colspan` 覆盖，[GridCell.origin] 指回宿主。
  spanned,

  /// 该槽位从未被任何元素占据——某一行的单元格比表格最大列数少，尾部补出来的。
  absent,
}

/// 归一化网格里的一个槽位。
///
/// **相等性刻意保持为引用相等**（不重写 `==`）：判断一个槽位是否由同一个元素
/// 覆盖，问的正是"是不是同一个对象"。跨行/跨列填充出来的槽位都持有同一个
/// origin 引用，用 `identical` 判断即可。
class GridCell {
  const GridCell._({
    required this.kind,
    this.element,
    required this.row,
    required this.column,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.origin,
  });

  /// 该槽位的性质。
  final GridCellKind kind;

  /// 宿主元素；仅 [GridCellKind.origin] 非空。
  final Element? element;

  /// 网格行号（0 基），单元格的**上边缘**。
  final int row;

  /// 网格列号（0 基），单元格的**左边缘**。
  final int column;

  /// 纵向跨度；仅 origin 有意义。
  final int rowSpan;

  /// 横向跨度；仅 origin 有意义。
  final int colSpan;

  /// 覆盖该槽位的宿主；仅 [GridCellKind.spanned] 非空。
  final GridCell? origin;

  /// 是否是宿主槽位。
  bool get isOrigin => kind == GridCellKind.origin;

  /// 是否是空洞槽位。
  bool get isAbsent => kind == GridCellKind.absent;

  /// 是否是跨行/跨列填充出来的槽位。
  bool get isSpanned => kind == GridCellKind.spanned;

  /// 覆盖区域的最后一行。
  int get lastRow => row + rowSpan - 1;

  /// 覆盖区域的最后一列。
  int get lastColumn => column + colSpan - 1;

  /// 形如 `r3.c5` 的位置标签，用于诊断信息。
  String get debugLabel => 'r$row.c$column';

  @override
  String toString() => switch (kind) {
    GridCellKind.origin => 'origin($debugLabel, ${rowSpan}x$colSpan)',
    GridCellKind.spanned => 'spanned($debugLabel -> ${origin!.debugLabel})',
    GridCellKind.absent => 'absent($debugLabel)',
  };
}

/// 把 `<table>` 归一化成的矩形网格。
///
/// `rowspan` / `colspan` 是课表解析里最大的正确性陷阱：一个跨行单元格会占掉
/// 后续若干行的槽位，若不做归一化，后续每一列的课程都会整体错位。本类把这件事
/// 一次做对，下游只需按 `(row, column)` 取值。
///
/// 网格**自身就是占位图**：槽位非空即"已占用"，不需要额外的布尔矩阵，这消除了
/// 一整类记账 bug。
class TableGrid {
  const TableGrid._({required this.rowCount, required this.columnCount, required this.rows});

  /// 归一化 `<table>`。
  ///
  /// [context] 用于收集结构异常（非法跨度、参差行等）。省略时这些诊断会被丢弃，
  /// 适合测试与快速调用；生产路径应当传入。
  factory TableGrid.from(Element table, {ParseContext? context}) {
    final ctx = context ?? ParseContext(options: const ParseOptions());
    final rowElements = _logicalRows(table).toList();
    final rowCount = rowElements.length;
    final grid = <List<GridCell?>>[for (var i = 0; i < rowCount; i++) <GridCell?>[]];

    for (var r = 0; r < rowCount; r++) {
      final row = grid[r];
      var cursor = 0;
      for (final element in _logicalCells(rowElements[r])) {
        // 跳过被上方 rowspan 占掉的槽位。游标只前进不回退——这正是避免
        // "落在自己 colspan 内部"或"每列都从 0 重扫"（O(n²) 且会错位）的关键。
        while (cursor < row.length && row[cursor] != null) {
          cursor++;
        }
        final rs = _span(element, 'rowspan', rowCount - r, ctx);
        final cs = _span(element, 'colspan', _kMaxColumns, ctx);

        final origin = GridCell._(
          kind: GridCellKind.origin,
          element: element,
          row: r,
          column: cursor,
          rowSpan: rs,
          colSpan: cs,
        );
        _put(row, cursor, origin);
        for (var dr = 0; dr < rs; dr++) {
          for (var dc = 0; dc < cs; dc++) {
            if (dr == 0 && dc == 0) continue;
            _put(
              grid[r + dr],
              cursor + dc,
              GridCell._(
                kind: GridCellKind.spanned,
                row: r + dr,
                column: cursor + dc,
                origin: origin,
              ),
            );
          }
        }
        cursor += cs;
      }
    }

    // 补齐成矩形。
    var columnCount = 0;
    for (final row in grid) {
      if (row.length > columnCount) columnCount = row.length;
    }
    for (var r = 0; r < rowCount; r++) {
      final row = grid[r];
      if (row.length < columnCount) {
        ctx.info(ParseWarningKind.raggedRow, '第 $r 行只有 ${row.length} 格，尾部按空洞补齐', location: 'r$r');
        while (row.length < columnCount) {
          row.add(null);
        }
      }
      for (var c = 0; c < columnCount; c++) {
        row[c] ??= GridCell._(kind: GridCellKind.absent, row: r, column: c);
      }
    }

    return TableGrid._(
      rowCount: rowCount,
      columnCount: columnCount,
      rows: <List<GridCell>>[for (final row in grid) row.cast<GridCell>()],
    );
  }

  /// 行数。
  final int rowCount;

  /// 列数。
  final int columnCount;

  /// 矩形网格，每行恰好 [columnCount] 个槽位。
  final List<List<GridCell>> rows;

  /// 取指定位置的槽位。
  GridCell cellAt(int row, int column) => rows[row][column];

  /// 按行优先顺序遍历所有宿主槽位。
  Iterable<GridCell> get originCells sync* {
    for (final row in rows) {
      for (final cell in row) {
        if (cell.kind == GridCellKind.origin) yield cell;
      }
    }
  }

  /// 是否没有任何行。
  bool get isEmpty => rowCount == 0;

  /// 转置网格：行列互换，`rowSpan` / `colSpan` 互换。
  ///
  /// 用于"行为星期、列为节次"的课表——正方教务的列表视图就是这种形态。
  /// 转置后每个槽位仍指向**转置后**的宿主对象，引用关系保持一致。
  TableGrid transposed() {
    final remapped = <GridCell, GridCell>{};
    final newRows = <List<GridCell>>[for (var c = 0; c < columnCount; c++) <GridCell>[]];

    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < columnCount; c++) {
        final cell = rows[r][c];
        switch (cell.kind) {
          case GridCellKind.origin:
            final moved = GridCell._(
              kind: GridCellKind.origin,
              element: cell.element,
              row: c,
              column: r,
              rowSpan: cell.colSpan,
              colSpan: cell.rowSpan,
            );
            remapped[cell] = moved;
            newRows[c].add(moved);
          case GridCellKind.spanned:
            // 宿主一定在行优先序里先于它出现，所以映射必然已就绪。
            newRows[c].add(
              GridCell._(
                kind: GridCellKind.spanned,
                row: c,
                column: r,
                origin: remapped[cell.origin!]!,
              ),
            );
          case GridCellKind.absent:
            newRows[c].add(GridCell._(kind: GridCellKind.absent, row: c, column: r));
        }
      }
    }

    return TableGrid._(rowCount: columnCount, columnCount: rowCount, rows: newRows);
  }

  @override
  String toString() =>
      'TableGrid(${rowCount}x$columnCount, '
      '${originCells.length} origins)';
}

/// 表格的直接子行。
///
/// **绝不递归**：`querySelectorAll('tr')` 会钻进单元格里的嵌套 `<table>`（真实
/// 存在——有些课表把图例表塞在单元格里），那样行号就全错了。
/// `package:html` 会为裸 `<table><tr>` 合成隐式 `<tbody>`，所以两个分支都要有；
/// `<caption>` / `<colgroup>` 由 default 分支跳过。
Iterable<Element> _logicalRows(Element table) sync* {
  for (final child in table.children) {
    switch (child.localName) {
      case 'tr':
        yield child;
      case 'thead':
      case 'tbody':
      case 'tfoot':
        for (final grand in child.children) {
          if (grand.localName == 'tr') yield grand;
        }
    }
  }
}

/// 一行里的单元格，只看直接子节点。
Iterable<Element> _logicalCells(Element tr) sync* {
  for (final child in tr.children) {
    final tag = child.localName;
    if (tag == 'td' || tag == 'th') yield child;
  }
}

void _put(List<GridCell?> row, int column, GridCell cell) {
  while (row.length <= column) {
    row.add(null);
  }
  row[column] = cell;
}

/// 解析并钳制跨度属性。
int _span(Element element, String name, int max, ParseContext ctx) {
  final raw = elementAttribute(element, name);
  if (raw == null) return 1;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null) {
    ctx.warn(ParseWarningKind.invalidSpan, '$name="$raw" 不是整数，按 1 处理', location: element.localName);
    return 1;
  }
  if (parsed == 0) {
    if (name == 'rowspan') {
      // 规范里 rowspan="0" 表示延伸到行组末尾；老教务系统偶尔拿它当"未设置"。
      ctx.info(ParseWarningKind.zeroRowspan, 'rowspan="0" 按规范延伸到表格末尾', location: element.localName);
      return max < 1 ? 1 : max;
    }
    ctx.warn(ParseWarningKind.invalidSpan, 'colspan="0" 非法，按 1 处理', location: element.localName);
    return 1;
  }
  if (parsed < 0) {
    ctx.warn(ParseWarningKind.invalidSpan, '$name="$raw" 为负，按 1 处理', location: element.localName);
    return 1;
  }
  if (parsed > max) {
    ctx.warn(
      ParseWarningKind.spanOverflow,
      '$name=$parsed 越界，已钳制为 $max',
      location: element.localName,
    );
    return max;
  }
  return parsed;
}

import 'package:html/dom.dart';

import '../grid/cell_position.dart';
import '../grid/matrix_layout.dart';
import '../grid/table_grid.dart';
import '../parse/course_cell_layout.dart';
import '../parse/field_extractors.dart';
import '../parse/html_utils.dart';
import 'matrix_table_adapter.dart';
import 'school_adapter.dart';

/// 匹配星期标签，用于挑选最像课表的那张表。
final RegExp _dayLabelPattern = RegExp('(?:星期|周|礼拜)\\s*[一二三四五六日天]');

/// 兜底的启发式矩阵适配器。
///
/// 当没有任何专用适配器命中时，它能从页面里挑出"最像课表"的那张表并尝试解析。
/// 置信度被刻意压到最低（0.1），因此只在没有别的候选时才生效。
///
/// 它不保证正确——字段顺序是猜的、表头是猜的——所以一旦某校有了真实样本，就应当
/// 写一个专用适配器把它盖过去。
class GeneralMatrixAdapter extends MatrixTableAdapter {
  /// 创建适配器。
  const GeneralMatrixAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'GENERIC_MATRIX_01',
    schoolId: 'GENERIC',
    adapterName: '通用矩阵课表（启发式兜底）',
    category: AdapterCategory.generalTool,
    description:
        '没有专用适配器命中时，自动挑选最像课表的表格并按'
        '「课程名/教师/周次/教室」尝试解析。结果不保证正确。',
  );

  @override
  bool canParse(String html) => html.contains('<table');

  @override
  double detectConfidence(String html) => canParse(html) ? 0.1 : 0;

  @override
  MatrixTableConfig configFor(Document document) {
    final table = _bestTable(document);
    return MatrixTableConfig(
      headerRowCount: 1,
      headerColumnCount: 1,
      tableLocator: TableLocator.where(
        (candidate) => identical(candidate, table),
        description: '启发式选出的表（星期列最多）',
      ),
      dayColumns: const DayColumns.headerLabels(),
      sectionMapping: const SectionMapping.labelColumn(column: 0),
      positionResolver: const CellPositionResolver.geometry(),
      cellLayout: const OrderedLineLayout(
        order: <CourseField>[
          CourseField.name,
          CourseField.teacher,
          CourseField.weeks,
          CourseField.position,
        ],
      ),
    );
  }

  /// 挑表头里"像星期的单元格"最多的那张表。
  Element? _bestTable(Document document) {
    Element? best;
    var bestScore = 0;
    for (final table in document.querySelectorAll('table')) {
      final score = _dayLabelCount(table);
      if (score > bestScore) {
        bestScore = score;
        best = table;
      }
    }
    return best;
  }

  int _dayLabelCount(Element table) {
    final grid = TableGrid.from(table);
    var best = 0;
    final limit = grid.rowCount < 3 ? grid.rowCount : 3;
    for (var r = 0; r < limit; r++) {
      var count = 0;
      for (final cell in grid.rows[r]) {
        final element = cell.element;
        if (cell.kind != GridCellKind.origin || element == null) continue;
        if (_dayLabelPattern.hasMatch(element.text)) count++;
      }
      if (count > best) best = count;
    }
    return best;
  }
}

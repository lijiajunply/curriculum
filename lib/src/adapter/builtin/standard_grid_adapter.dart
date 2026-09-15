import '../../grid/cell_position.dart';
import '../../grid/matrix_layout.dart';
import '../../parse/course_cell_layout.dart';
import '../../parse/field_extractors.dart';
import '../../parse/html_utils.dart';
import '../matrix_table_adapter.dart';
import '../school_adapter.dart';

/// 标准时间网格课表的通用适配器，同时也是**新增学校适配器的模板**。
///
/// 「星期 × 节次」的矩阵表是国内教务系统最常见的形态：表头一行写星期一…星期日，
/// 左侧一列写第X节，单元格里用 `<div>` 或 `<br>` 分行列出课程名 / 教师 / 周次 /
/// 教室。本适配器覆盖这种结构，字段顺序为 `课程名 / 教师 / 周次 / 教室`。
///
/// 新增一所学校通常只需要照抄本类，改三处：
/// 1. [info] 里的 id 与名称；
/// 2. [requiredMarkers] 换成本校页面的结构标记；
/// 3. [config] 里的字段顺序、表头行数、表格选择器。
///
/// 若某校只是字段顺序不同（例如教师排在课程名之前），把那行 [OrderedLineLayout.order]
/// 调换即可，**不需要写新的解析代码**。
///
/// **前提假设**：页面恰好有两行表头——第一行是「节次 + 跨列的『星期』」，
/// 第二行是「星期一…星期日」。只有一行表头的页面需要把 [MatrixTableConfig.headerRowCount]
/// 调成 1，否则第一行课程会被当成表头跳过。
class StandardGridAdapter extends MatrixTableAdapter {
  /// 创建适配器。
  const StandardGridAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'STANDARD_GRID_01',
    schoolId: 'GENERIC',
    adapterName: '标准时间网格（星期 × 节次）',
    category: AdapterCategory.generalTool,
    description:
        '覆盖「表头为星期、首列为节次」的矩阵式课表，'
        '字段顺序为 课程名/教师/周次/教室。',
  );

  @override
  List<String> get requiredMarkers => const <String>['kbTable'];

  @override
  List<String> get optionalMarkers => const <String>['timetable', '节次'];

  @override
  MatrixTableConfig get config => const MatrixTableConfig(
    headerRowCount: 2,
    headerColumnCount: 1,
    tableLocator: TableLocator.css('#kbTable, table.timetable'),
    dayColumns: DayColumns.headerLabels(),
    sectionMapping: SectionMapping.labelColumn(column: 0),
    positionResolver: CellPositionResolver.geometry(),
    cellLayout: OrderedLineLayout(
      order: <CourseField>[
        CourseField.name,
        CourseField.teacher,
        CourseField.weeks,
        CourseField.position,
      ],
    ),
  );
}

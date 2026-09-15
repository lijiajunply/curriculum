import '../../grid/cell_position.dart';
import '../../grid/matrix_layout.dart';
import '../../parse/course_cell_layout.dart';
import '../../parse/field_extractors.dart';
import '../../parse/html_utils.dart';
import '../matrix_table_adapter.dart';
import '../school_adapter.dart';

/// 「正方」风格时间网格课表的适配器。
///
/// 结构与 [StandardGridAdapter] 同为「星期 × 节次」矩阵，但有两处关键差异，正好
/// 展示了本库的扩展方式：
///
/// 1. **位置编码在 `id` 属性里**（`<td id="3-5">` = 星期三第 5 节）。这类写法在
///    真实教务系统里远比 `rowspan` 常见，所以位置解析改用
///    [CellPositionResolver.byId]——`id` 是权威，`rowspan` 只用来推跨度。
/// 2. **字段顺序不同**：单元格里是「课程名 / 周次 / 地点 / 教师」。
///
/// 两处差异各自只改了一行配置，没有新增任何解析代码。
class ZhengfangGridAdapter extends MatrixTableAdapter {
  /// 创建适配器。
  const ZhengfangGridAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'ZHENGFANG_GRID_01',
    schoolId: 'ZHENGFANG',
    adapterName: '正方教务 · 时间网格视图',
    category: AdapterCategory.bachelorAndAssociate,
    description:
        '位置由 td 的 id="星期-节次" 给出，'
        '单元格字段顺序为 课程名/周次/地点/教师。',
  );

  @override
  List<String> get requiredMarkers => const <String>['kbgrid_table_0'];

  @override
  List<String> get optionalMarkers => const <String>['timetable_con', 'td_wrap'];

  @override
  MatrixTableConfig get config => MatrixTableConfig(
    headerRowCount: 1,
    headerColumnCount: 1,
    tableLocator: TableLocator.id('kbgrid_table_0'),
    dayColumns: const DayColumns.headerLabels(maxHeaderRows: 1),
    sectionMapping: const SectionMapping.labelColumn(column: 0),
    // 与通用适配器唯一的差别之一：位置从 id 读。
    positionResolver: CellPositionResolver.byId(),
    cellLayout: const OrderedLineLayout(
      order: <CourseField>[
        CourseField.name,
        CourseField.weeks,
        CourseField.position,
        CourseField.teacher,
      ],
    ),
  );
}

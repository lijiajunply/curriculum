import '../../parse/course_cell_layout.dart';
import '../../parse/field_extractors.dart';
import '../block_list_adapter.dart';
import '../school_adapter.dart';

/// 卡片里需要在成行之前丢掉的噪声行。
///
/// 这些是教务系统附在卡片里的行政信息（分组、人数），与课程本身无关；
/// 不丢掉的话它们会挤进「课程名 / 教室」的位置。
final RegExp _cardNoise = RegExp('上课组|人数|学分|周学时|总学时|选课人数');

/// 西安建筑科技大学 · 教务系统课表的适配器。
///
/// 页面结构与常见的「星期 × 节次」表格完全不同，是**一列一天**的 div 布局：
///
/// ```html
/// <div class="course-table">
///   <div class="time-table-body">
///     <div class="columns weekday">        <!-- 第 1 列 = 星期一 -->
///       <div class="card-view">
///         <div class="card-content-code">MATH101</div>
///         <div class="card-content-info">
///           高等数学A                       <!-- 首行：课程名 -->
///           教一101                         <!-- 次行：上课地点 -->
///           (1~16周)                        <!-- 周次子句 -->
///           (1,2节)                         <!-- 节次子句 -->
///         </div>
///       </div>
///     </div>
///     <div class="columns weekday">…</div>  <!-- 共 7 列，周一…周日 -->
///   </div>
/// </div>
/// ```
///
/// 三处要点：
/// - **星期来自卡片所在的列**，卡片自身不带星期信息，所以用
///   [DaySectionResolver.fromAncestorIndex]。
/// - **周次与节次写在半角括号子句里**，用 [ParenthesizedClauseLayout] 抽取。
/// - **字段靠源码换行分隔**（服务端渲染时 `.card-content-info` 里的换行符），
///   所以要 `keepSourceNewlines: true`。
///
/// 已知取舍：`.card-content-code` 里的课程代码**不进入输出**。拾光课程表的
/// `Course` 没有对应字段（它的 `id` 由宿主自行生成，传进去也会被忽略），
/// 唯一可用的空位是 `remark`，但把课程代码显示成「备注」语义是歪的。
/// 需要的话，继承本类并覆写 [cellLayout] 即可自行接管。
class XauatAdapter extends BlockListAdapter {
  /// 创建适配器。
  const XauatAdapter();

  @override
  SchoolAdapterInfo get info => const SchoolAdapterInfo(
    adapterId: 'XAUAT_01',
    schoolId: 'XAUAT',
    adapterName: '西安建筑科技大学 · 教务系统课表',
    category: AdapterCategory.bachelorAndAssociate,
    description: '一列一天的 div 课表；周次与节次写在半角括号子句里。',
  );

  @override
  List<String> get requiredMarkers => const <String>['course-table', 'card-view'];

  @override
  List<String> get optionalMarkers => const <String>['time-table-body', 'card-content-info'];

  @override
  String get blockSelector => '.course-table .columns.weekday .card-view';

  @override
  String? get contentSelector => '.card-content-info';

  @override
  bool get keepSourceNewlines => true;

  @override
  DaySectionResolver get positionResolver =>
      const DaySectionResolver.fromAncestorIndex(ancestorSelector: '.columns.weekday');

  @override
  CourseCellLayout get cellLayout => _layout;

  static final CourseCellLayout _layout = ParenthesizedClauseLayout(
    order: const <CourseField>[CourseField.name, CourseField.position],
    skipLinePattern: _cardNoise,
  );
}

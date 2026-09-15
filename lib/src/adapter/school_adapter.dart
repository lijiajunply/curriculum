import 'package:html/dom.dart';

import '../exceptions.dart';
import '../model/course_import_result.dart';
import '../model/parse_options.dart';
import '../parse/html_utils.dart';

/// 探测时最多扫描的 HTML 字节数。
///
/// 教务系统的课表页动辄几百 KB，而特征标记总在头部或表格附近；截断可以避免
/// 在 N 个适配器上各扫一遍全文。
const int kDetectionScanWindow = 256 * 1024;

/// 适配器类别，与拾光课程表 `school_index.proto` 的 `AdapterCategory` 对齐。
enum AdapterCategory {
  /// 通用工具，不针对具体学校。
  generalTool,

  /// 本科/专科教务系统。
  bachelorAndAssociate,

  /// 研究生教务系统。
  postgraduate,
}

/// 适配器的静态元信息。
class SchoolAdapterInfo {
  /// 创建元信息。
  const SchoolAdapterInfo({
    required this.adapterId,
    required this.schoolId,
    required this.adapterName,
    this.category = AdapterCategory.bachelorAndAssociate,
    this.description,
    this.maintainer,
  });

  /// 适配器唯一 id，例如 `GENERIC_GRID_01`。
  ///
  /// 若要与拾光课程表的 `school_index.pb` 对接，取值应与其中的
  /// `Adapter.adapter_id` 一致——本库只把它当 join key，不复制那份索引。
  final String adapterId;

  /// 学校 id，例如 `YNUFE`。
  final String schoolId;

  /// 展示用名称。
  final String adapterName;

  /// 类别。
  final AdapterCategory category;

  /// 详细说明。
  final String? description;

  /// 维护者。
  final String? maintainer;

  @override
  String toString() => '$adapterName($adapterId)';
}

/// 一个学校/教务系统的课表解析器。
///
/// 实现者通常不必直接继承本类：矩阵式课表继承 `MatrixTableAdapter`，
/// 绝对定位的 div 课表继承 `BlockListAdapter`，内嵌 JSON 的继承
/// `EmbeddedJsonAdapter`，各自只需给出少量配置。
abstract class SchoolAdapter {
  /// 创建适配器。
  const SchoolAdapter();

  /// 静态元信息。
  SchoolAdapterInfo get info;

  /// 必须出现的**结构性**特征。
  ///
  /// 请选结构标记（`id="kbTable"`、`class="timetable"`）而不是校名：纯解析器无法
  /// 可靠地从 HTML 推断学校，而一所学校的页面结构远比它的品牌文案稳定。
  List<String> get requiredMarkers => const <String>[];

  /// 出现则提高置信度的特征。
  List<String> get optionalMarkers => const <String>[];

  /// 廉价的字符串特征判断。
  ///
  /// **绝不解析、绝不抛异常**：`parseAuto` 要在 N 个适配器上跑，不能解析 N 份文档。
  bool canParse(String html) {
    if (html.isEmpty) return false;
    if (requiredMarkers.isEmpty && optionalMarkers.isEmpty) return false;
    final hay = _scanWindow(html);
    for (final marker in requiredMarkers) {
      if (!hay.contains(marker)) return false;
    }
    return true;
  }

  /// 匹配程度，0 表示不匹配。数值越大越可信，用于 `detect` 排序。
  double detectConfidence(String html) {
    if (!canParse(html)) return 0;
    final hay = _scanWindow(html);
    var score = 1.0;
    for (final marker in optionalMarkers) {
      if (hay.contains(marker)) score += 0.05;
    }
    return score > 1.5 ? 1.5 : score;
  }

  /// 解析 HTML 字符串。
  CourseImportResult parse(String html, {ParseOptions options = const ParseOptions()}) =>
      parseDocument(parseHtmlDocument(html), options: options);

  /// 解析已经解析好的文档。
  CourseImportResult parseDocument(
    Document document, {
    ParseOptions options = const ParseOptions(),
  });

  /// 解析并在没有结果时抛 [ParseFailedException]。
  ///
  /// 开启 [ParseOptions.strict] 时，出现 error 级诊断也会抛。
  CourseImportResult parseOrThrow(String html, {ParseOptions options = const ParseOptions()}) {
    final result = parse(html, options: options);
    result.throwIfEmpty();
    if (options.strict && result.hasErrors) {
      throw ParseFailedException(
        '严格模式下存在 error 级诊断'
        '${result.adapterId == null ? '' : '（适配器 ${result.adapterId}）'}',
        warnings: result.warnings,
        partial: result,
      );
    }
    return result;
  }

  String _scanWindow(String html) =>
      html.length > kDetectionScanWindow ? html.substring(0, kDetectionScanWindow) : html;
}

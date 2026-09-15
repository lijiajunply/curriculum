import '../exceptions.dart';
import '../model/course_import_result.dart';
import '../model/parse_context.dart';
import '../model/parse_options.dart';
import '../model/parse_warning.dart';
import 'builtin_adapters.dart';
import 'school_adapter.dart';

/// 一次探测的结果。
class DetectionCandidate {
  /// 创建候选。
  const DetectionCandidate(this.adapter, this.confidence);

  /// 命中的适配器。
  final SchoolAdapter adapter;

  /// 置信度，越大越可信。
  final double confidence;

  @override
  String toString() => '${adapter.info.adapterId}(${confidence.toStringAsFixed(2)})';
}

/// 适配器注册表。
class SchoolAdapterRegistry {
  /// 用一组适配器创建注册表。
  SchoolAdapterRegistry([Iterable<SchoolAdapter> adapters = const []]) {
    for (final adapter in adapters) {
      register(adapter);
    }
  }

  static SchoolAdapterRegistry? _standard;

  /// 内置适配器构成的默认注册表（惰性构建，多次调用返回同一实例）。
  static SchoolAdapterRegistry get standard =>
      _standard ??= SchoolAdapterRegistry(buildBuiltinAdapters());

  final List<SchoolAdapter> _adapters = <SchoolAdapter>[];

  /// 注册一个适配器。
  ///
  /// 同 id 已存在且 [override] 为 false 时抛 [StateError]——静默覆盖会让
  /// "为什么我的适配器没生效"变成一个难以排查的问题。
  void register(SchoolAdapter adapter, {bool override = false}) {
    final id = adapter.info.adapterId;
    final index = _adapters.indexWhere((a) => a.info.adapterId == id);
    if (index >= 0) {
      if (!override) {
        throw StateError('适配器 id 重复：$id');
      }
      _adapters[index] = adapter;
      return;
    }
    _adapters.add(adapter);
  }

  /// 注销一个适配器；返回是否确实移除了。
  bool unregister(String adapterId) {
    final index = _adapters.indexWhere((a) => a.info.adapterId == adapterId);
    if (index < 0) return false;
    _adapters.removeAt(index);
    return true;
  }

  /// 按 id 取适配器。
  SchoolAdapter? byId(String adapterId) {
    for (final adapter in _adapters) {
      if (adapter.info.adapterId == adapterId) return adapter;
    }
    return null;
  }

  /// 全部适配器，按注册顺序。
  List<SchoolAdapter> all() => List<SchoolAdapter>.unmodifiable(_adapters);

  /// 按类别筛选。
  List<SchoolAdapter> byCategory(AdapterCategory category) =>
      List<SchoolAdapter>.unmodifiable(_adapters.where((a) => a.info.category == category));

  /// 按学校 id 筛选。
  List<SchoolAdapter> bySchoolId(String schoolId) =>
      List<SchoolAdapter>.unmodifiable(_adapters.where((a) => a.info.schoolId == schoolId));

  /// 所有能解析该 HTML 的适配器，按置信度降序。
  ///
  /// 置信度相同时**后注册的排前面**，这样宿主注册的适配器可以盖过同分的内置适配器。
  List<DetectionCandidate> detect(String html) {
    final hits = <(int, DetectionCandidate)>[];
    for (var i = 0; i < _adapters.length; i++) {
      final adapter = _adapters[i];
      final confidence = adapter.detectConfidence(html);
      if (confidence > 0) {
        hits.add((i, DetectionCandidate(adapter, confidence)));
      }
    }
    hits.sort((a, b) {
      final byConfidence = b.$2.confidence.compareTo(a.$2.confidence);
      return byConfidence != 0 ? byConfidence : b.$1.compareTo(a.$1);
    });
    return <DetectionCandidate>[for (final hit in hits) hit.$2];
  }

  /// 最可信的候选；没有命中返回 null。
  DetectionCandidate? detectBest(String html) {
    final candidates = detect(html);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// 自动挑选适配器解析。
  ///
  /// 没有适配器命中时返回一个带 [ParseWarningKind.noAdapterMatched] 错误的**空结果**
  /// 而不是抛异常：宿主此时应当弹出"请选择你的学校"，异常在那里毫无帮助。
  CourseImportResult parseAuto(String html, {ParseOptions options = const ParseOptions()}) {
    final best = detectBest(html);
    if (best == null) {
      final ctx = ParseContext(options: options);
      ctx.error(ParseWarningKind.noAdapterMatched, '没有适配器匹配该页面（已注册 ${_adapters.length} 个）');
      return CourseImportResult(courses: const [], warnings: ctx.warnings, stats: ctx.stats);
    }
    return best.adapter.parse(html, options: options);
  }

  /// 用指定的适配器解析。
  ///
  /// id 未知时抛 [AdapterNotFoundException]：调用方明确点名了，静默失败就是 bug。
  CourseImportResult parseAs(
    String adapterId,
    String html, {
    ParseOptions options = const ParseOptions(),
  }) {
    final adapter = byId(adapterId);
    if (adapter == null) {
      throw AdapterNotFoundException(
        adapterId,
        knownIds: <String>[for (final a in _adapters) a.info.adapterId],
      );
    }
    return adapter.parse(html, options: options);
  }
}

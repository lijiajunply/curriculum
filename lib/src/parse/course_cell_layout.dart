import 'cell_text.dart';
import 'field_extractors.dart';
import 'week_parser.dart';

/// 一个单元格里的多条记录如何映射到该单元格的几何节次跨度上。
enum SectionSplit {
  /// 优先采信记录里的显式节次；都没有时，**每条记录都拿完整跨度**。
  ///
  /// 这是默认值，也是唯一安全的默认值：一个 rowspan 单元格里几乎总是一门课占满
  /// 整个跨度；同格多条记录（如 `程序设计基础` 与 `程序设计基础(实验)`）意味着
  /// **同一时段的并行开课**，不是时段细分。按记录数均分会把第 3-4 节悄悄拆成
  /// 第 3 节和第 4 节——错的。
  explicitOnly,

  /// 与 [explicitOnly] 同义，语义上强调"不做任何拆分"。
  none,

  /// 按记录数均分跨度。仅当确认某校确实用同格多记录表示连堂分段时才开启。
  even,
}

/// 从单元格文本里抽出的一条原始记录，字段尚未归一化。
class RawCourseRecord {
  /// 课程名。
  String? name;

  /// 任课教师。
  String? teacher;

  /// 上课地点。
  String? position;

  /// 周次原文，交由 `parseWeeks` 处理。
  String? weeksRaw;

  /// 节次原文，交由 `parseSections` 处理。
  String? sectionsRaw;

  /// 没能归入任何字段的行，保留下来供诊断，不丢弃。
  final List<String> leftovers = <String>[];

  /// 读取某个字段。
  String? read(CourseField field) => switch (field) {
    CourseField.name => name,
    CourseField.teacher => teacher,
    CourseField.position => position,
    CourseField.weeks => weeksRaw,
    CourseField.sections => sectionsRaw,
    CourseField.ignore => null,
  };

  /// 写入某个字段；[CourseField.ignore] 会被忽略。
  void write(CourseField field, String value) {
    switch (field) {
      case CourseField.name:
        name = value;
      case CourseField.teacher:
        teacher = value;
      case CourseField.position:
        position = value;
      case CourseField.weeks:
        weeksRaw = value;
      case CourseField.sections:
        sectionsRaw = value;
      case CourseField.ignore:
        break;
    }
  }

  /// 清空某个字段。
  void clear(CourseField field) {
    switch (field) {
      case CourseField.name:
        name = null;
      case CourseField.teacher:
        teacher = null;
      case CourseField.position:
        position = null;
      case CourseField.weeks:
        weeksRaw = null;
      case CourseField.sections:
        sectionsRaw = null;
      case CourseField.ignore:
        break;
    }
  }

  /// 该字段是否已经有值。
  bool has(CourseField field) {
    final v = read(field);
    return v != null && v.isNotEmpty;
  }

  /// 是否一个字段都没填上。
  bool get isEmpty =>
      name == null &&
      teacher == null &&
      position == null &&
      weeksRaw == null &&
      sectionsRaw == null;

  /// 是否有课程名（没有课程名的记录无法使用）。
  bool get hasName => name != null && name!.isNotEmpty;

  @override
  String toString() => 'RawCourseRecord(${name ?? '?'}, 周次=${weeksRaw ?? '?'})';
}

/// 把一个单元格的文本行切成若干条记录。
///
/// 新学校的差异通常只需要换一个 layout 或改一处配置，不必写新代码。
abstract class CourseCellLayout {
  /// 创建布局。
  const CourseCellLayout();

  /// 记录与几何跨度之间的关系，见 [SectionSplit]。
  SectionSplit get sectionSplit => SectionSplit.explicitOnly;

  /// 廉价的预筛选；默认接受任何非空输入。
  bool matches(List<String> lines) => lines.isNotEmpty;

  /// 抽取出零条或多条记录。
  List<RawCourseRecord> extract(List<String> lines);

  /// 供诊断使用的可读名称。
  String get debugName => runtimeType.toString();
}

/// 固定字段顺序的布局：每 `order.length` 行构成一条记录。
///
/// 这是主力布局，覆盖绝大多数教务系统。
class OrderedLineLayout extends CourseCellLayout {
  /// 创建定序布局。
  const OrderedLineLayout({
    required this.order,
    this.blockSeparator,
    this.splitOnRepeatedWeeks = true,
    this.sectionSplit = SectionSplit.explicitOnly,
    this.heuristics = const Heuristics(),
  });

  /// 字段顺序。用 [CourseField.ignore] 占位可以跳过已知但用不上的字段。
  final List<CourseField> order;

  /// 匹配"下一条记录开头"的正则；给出时优先按它分块。
  final RegExp? blockSeparator;

  /// 是否允许用"周次行"作为记录终止符来分块。
  ///
  /// 这一条规则独自搞定了绝大多数堆叠单元格，因为周次行天然是记录的结尾，
  /// 而且在某条记录少了地点时仍能正确分块（等分块会失败）。
  final bool splitOnRepeatedWeeks;

  @override
  final SectionSplit sectionSplit;

  /// 兜底分类器，用于按位置赋值之后仍然为空的字段。
  final Heuristics heuristics;

  @override
  String get debugName => 'OrderedLineLayout(${order.map((f) => f.name).join('/')})';

  @override
  List<RawCourseRecord> extract(List<String> input) {
    if (input.isEmpty || order.isEmpty) return const <RawCourseRecord>[];

    // 单元格里只有一个逻辑行、但该行被宽空白分成了多个字段时，先把它们摊平。
    final lines = _maybeFlatten(input);

    final blocks = _segment(lines);
    final records = <RawCourseRecord>[];
    for (final block in blocks) {
      final record = _assign(block);
      if (!record.isEmpty) records.add(record);
    }
    return records;
  }

  List<String> _maybeFlatten(List<String> lines) {
    if (lines.length >= order.length) return lines;
    final flattened = <String>[];
    for (final line in lines) {
      flattened.addAll(splitFields(line));
    }
    return flattened.length > lines.length ? flattened : lines;
  }

  List<List<String>> _segment(List<String> lines) {
    if (lines.isEmpty) return const <List<String>>[];

    // (a) 显式的分块标记。
    final separator = blockSeparator;
    if (separator != null) {
      final blocks = <List<String>>[];
      var current = <String>[];
      for (final line in lines) {
        if (separator.hasMatch(line) && current.isNotEmpty) {
          blocks.add(current);
          current = <String>[];
        }
        current.add(line);
      }
      if (current.isNotEmpty) blocks.add(current);
      if (blocks.isNotEmpty) return blocks;
    }

    // (b) 行数恰好是字段数的整数倍：等分。
    if (lines.length >= order.length && lines.length % order.length == 0) {
      final blocks = <List<String>>[];
      for (var i = 0; i < lines.length; i += order.length) {
        blocks.add(lines.sublist(i, i + order.length));
      }
      return blocks;
    }

    // (c) 周次锚点分块——真正的兜底，能处理参差块（某条记录少了地点之类）。
    //
    // 不能简单地"在周次行之后切断"：那只有在周次恰好是最后一个字段时才成立。
    // 正确做法是把周次行当作**锚点**——既然知道周次在 order 里的下标，就能反推出
    // 该记录的开始位置，再按 order.length 截出整条记录。
    if (splitOnRepeatedWeeks) {
      final weekIndex = order.indexOf(CourseField.weeks);
      if (weekIndex >= 0) {
        final anchors = <int>[
          for (var i = 0; i < lines.length; i++)
            if (looksLikeWeeks(lines[i])) i,
        ];
        if (anchors.isNotEmpty) {
          final blocks = <List<String>>[];
          var cursor = 0;
          for (final anchor in anchors) {
            final start = anchor - weekIndex;
            if (start < cursor) continue; // 与已有块重叠，跳过。
            final end = start + order.length;
            if (end > lines.length) break;
            blocks.add(lines.sublist(start, end));
            cursor = end;
          }
          if (cursor < lines.length) {
            // 尾部残余（通常是一条缺字段的记录）单独成块，交给赋值阶段兜底。
            blocks.add(lines.sublist(cursor));
          }
          if (blocks.isNotEmpty) return blocks;
        }
      }
    }

    return <List<String>>[lines];
  }

  RawCourseRecord _assign(List<String> block) {
    final record = RawCourseRecord();

    // 1. 按位置赋值。
    for (var i = 0; i < block.length; i++) {
      if (i >= order.length) {
        record.leftovers.add(block[i]);
        continue;
      }
      final field = order[i];
      if (field == CourseField.ignore) {
        record.leftovers.add(block[i]);
        continue;
      }
      if (record.has(field)) {
        record.leftovers.add(block[i]);
        continue;
      }
      record.write(field, block[i]);
    }

    // 2. 纠偏：某校字段顺序变了、或某条记录少了一行时，按位置硬赋的值会串位。
    // 只有在"自己完全不像"且"别的字段非常像"时才挪走，避免误伤 `体育` 这类
    // 既像课程名又像姓名的短词。
    _repair(record, block);

    // 3. 用分类器给仍然为空的字段补漏，先补辨识度高的字段。
    const fillOrder = <CourseField>[
      CourseField.weeks,
      CourseField.sections,
      CourseField.position,
      CourseField.teacher,
    ];
    for (final field in fillOrder) {
      if (!order.contains(field) || record.has(field)) continue;
      if (field == CourseField.sections) continue; // 节次由几何决定，不从文本猜。
      _fill(record, field, 0.5);
    }
    // 4. 课程名最后补，阈值最低（它本来就是"兜底字段"）。
    if (order.contains(CourseField.name) && !record.has(CourseField.name)) {
      _fill(record, CourseField.name, 0.01);
    }

    return record;
  }

  /// 把"明显属于别的字段"的值退回 leftovers。
  void _repair(RawCourseRecord record, List<String> block) {
    for (final field in order) {
      if (field == CourseField.ignore) continue;
      final value = record.read(field);
      if (value == null || value.isEmpty) continue;
      final own = heuristics.score(value, field);
      if (own >= 0.5) continue; // 自己像自己，不动。
      var bestOther = 0.0;
      for (final other in CourseField.values) {
        if (other == field || other == CourseField.ignore) continue;
        final score = heuristics.score(value, other);
        if (score > bestOther) bestOther = score;
      }
      if (bestOther >= 0.7) {
        record.clear(field);
        record.leftovers.add(value);
      }
    }
  }

  void _fill(RawCourseRecord record, CourseField field, double threshold) {
    var bestIndex = -1;
    var bestScore = threshold;
    for (var i = 0; i < record.leftovers.length; i++) {
      final score = heuristics.score(record.leftovers[i], field);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0) {
      record.write(field, record.leftovers.removeAt(bestIndex));
    }
  }
}

/// 标签驱动的布局：`课程：高等数学`、`教师:张伟`、`周次 1-16周`。
///
/// 顺序无关，适合表单式的课表页。同一个标签第二次出现即视为下一条记录的开始。
class LabeledLineLayout extends CourseCellLayout {
  /// 创建标签布局。
  const LabeledLineLayout({
    this.labels = Heuristics.defaultLabels,
    this.fallback,
    this.sectionSplit = SectionSplit.explicitOnly,
  });

  /// 标签到字段的映射，键不含冒号。
  final Map<String, CourseField> labels;

  /// 处理没有标签的行的兜底布局。
  final CourseCellLayout? fallback;

  @override
  final SectionSplit sectionSplit;

  @override
  String get debugName => 'LabeledLineLayout(${labels.length} 个标签)';

  @override
  List<RawCourseRecord> extract(List<String> lines) {
    if (lines.isEmpty) return const <RawCourseRecord>[];

    // 长标签优先匹配，避免 `上课地点` 被 `地点` 抢先。
    final sortedLabels = labels.keys.toList()..sort((a, b) => b.length.compareTo(a.length));

    final records = <RawCourseRecord>[];
    var current = RawCourseRecord();
    final seen = <CourseField>{};
    final unlabeled = <String>[];

    void flush() {
      if (!current.isEmpty) records.add(current);
      current = RawCourseRecord();
      seen.clear();
    }

    for (final line in lines) {
      final match = _matchLabel(line, sortedLabels);
      if (match == null) {
        unlabeled.add(line);
        continue;
      }
      final field = labels[match.$1]!;
      if (field != CourseField.ignore && seen.contains(field)) {
        // 同一个标签再次出现 -> 新记录开始。
        flush();
      }
      if (field == CourseField.ignore) {
        unlabeled.add(line);
        continue;
      }
      current.write(field, match.$2);
      seen.add(field);
    }
    flush();

    final fallbackLayout = fallback;
    if (fallbackLayout != null && unlabeled.isNotEmpty) {
      final fromFallback = fallbackLayout.extract(unlabeled);
      if (records.isEmpty) {
        records.addAll(fromFallback);
      } else {
        final target = records.last;
        for (final extra in fromFallback) {
          for (final field in CourseField.values) {
            if (field == CourseField.ignore) continue;
            if (!target.has(field) && extra.has(field)) {
              target.write(field, extra.read(field)!);
            }
          }
        }
      }
    } else {
      for (final line in unlabeled) {
        if (records.isEmpty) {
          current.leftovers.add(line);
        } else {
          records.last.leftovers.add(line);
        }
      }
      if (records.isEmpty && !current.isEmpty) records.add(current);
    }

    return records;
  }

  /// 匹配 `标签` 或 `标签:` 或 `标签：` 开头的一行，返回 (标签, 值)。
  (String, String)? _matchLabel(String line, List<String> sortedLabels) {
    final trimmed = line.trim();
    for (final label in sortedLabels) {
      if (!trimmed.startsWith(label)) continue;
      var rest = trimmed.substring(label.length).trim();
      if (rest.startsWith(':') ||
          rest.startsWith('：') ||
          rest.startsWith('=') ||
          rest.startsWith('=')) {
        rest = rest.substring(1).trim();
      }
      if (rest.isEmpty) continue;
      return (label, rest);
    }
    return null;
  }
}

/// 单行分隔符布局：`高等数学@张三@1-16周@教101`。
class DelimitedLineLayout extends CourseCellLayout {
  /// 创建分隔符布局。
  const DelimitedLineLayout({
    required this.pattern,
    required this.groups,
    this.sectionSplit = SectionSplit.explicitOnly,
  });

  /// 匹配单条记录的正则，使用具名捕获组。
  final RegExp pattern;

  /// 捕获组名到字段的映射。
  final Map<String, CourseField> groups;

  @override
  final SectionSplit sectionSplit;

  @override
  String get debugName => 'DelimitedLineLayout(${pattern.pattern})';

  @override
  List<RawCourseRecord> extract(List<String> lines) {
    final records = <RawCourseRecord>[];
    for (final line in lines) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final record = RawCourseRecord();
      var any = false;
      for (final entry in groups.entries) {
        final value = match.namedGroup(entry.key)?.trim();
        if (value == null || value.isEmpty) continue;
        if (entry.value == CourseField.ignore) continue;
        record.write(entry.value, value);
        any = true;
      }
      if (any) records.add(record);
    }
    return records;
  }
}

/// 依次尝试多个布局，取第一个产出非空结果者。
class CompositeLayout extends CourseCellLayout {
  /// 创建组合布局。
  const CompositeLayout(this.delegates);

  /// 按优先级排列的候选布局。
  final List<CourseCellLayout> delegates;

  @override
  SectionSplit get sectionSplit =>
      delegates.isEmpty ? SectionSplit.explicitOnly : delegates.first.sectionSplit;

  @override
  bool matches(List<String> lines) => delegates.any((d) => d.matches(lines));

  @override
  String get debugName => 'CompositeLayout(${delegates.length} 个候选)';

  @override
  List<RawCourseRecord> extract(List<String> lines) {
    for (final delegate in delegates) {
      final records = delegate.extract(lines);
      if (records.isNotEmpty) return records;
    }
    return const <RawCourseRecord>[];
  }
}

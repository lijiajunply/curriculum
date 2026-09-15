import 'text_normalize.dart';

/// 星期标签里用到的汉字，顺序即周一…周日。
///
/// 网格层直接复用这份定义，避免两处维护同一张表而漂移。
const String kDayCharacters = '一二三四五六日';

/// 一个闭区间的节次范围。
class SectionRange {
  /// 创建节次范围。
  const SectionRange(this.start, this.end)
    : assert(start >= 1, 'start 必须 >= 1'),
      assert(end >= start, 'end 必须 >= start');

  /// 起始节次（含）。
  final int start;

  /// 结束节次（含）。
  final int end;

  /// 跨越的节次数。
  int get length => end - start + 1;

  /// 展开成逐个节次。
  List<int> get sections => <int>[for (var s = start; s <= end; s++) s];

  @override
  bool operator ==(Object other) =>
      other is SectionRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '第$start-$end节';
}

/// 需要从节次字段里剔除的时间段前缀词。
final RegExp _dayPartPrefix = RegExp('上午|下午|晚上|早上|早晨|中午|傍晚|夜间');

/// 需要剔除的节次单位后缀词（长的在前，避免 `节次` 被拆成 `次`）。
final RegExp _sectionUnit = RegExp('小节|节课|节次|节');

/// 节次字段外层的括号，例如 `(1,2节)`、`（3-4节）`。
///
/// 很多教务把周次与节次都写成括号子句，所以节次解析必须能吃下这层壳——
/// 与周次解析的处理保持对称。
final RegExp _brackets = RegExp(r'[()\[\]{}]');

/// 混在节次字段里的星期标签，例如 `星期三第3-4节`、`周一第1,2节`。
///
/// 只匹配「星期/周/礼拜 + 星期几」的组合，所以不会误伤 `1-16周` 里的周。
final RegExp _dayLabelPrefix = RegExp('(?:星期|周|礼拜)[$kDayCharacters天]');

/// 单个 token：`3-4` 这样的区间。
final RegExp _rangeToken = RegExp(r'^(\d+)-(\d+)$');

/// 单个 token：`3` 这样的单点。
final RegExp _singleToken = RegExp(r'^(\d+)$');

/// 紧凑节次：`0102` 这种每两位一节次的写法。
final RegExp _compactToken = RegExp(r'^\d{4,8}$');

/// 解析节次标签，例如 `第1-2节`、`3-4`、`第1,2节`、`上午1-2节`。
///
/// 返回覆盖所有 token 的最小闭区间；`第1,2节` 这类不连续写法会被合并成 (1, 2)，
/// 因为课程块在课表上本来就是连在一起的。
///
/// [raw] 不是节次标签、或解析出的范围越过 `1..maxSection` 时返回 null。
SectionRange? parseSections(String? raw, {int maxSection = 20}) {
  if (raw == null) return null;
  final cleaned = normalizeForParsing(raw)
      .replaceAll(_brackets, '')
      .replaceAll(_dayLabelPrefix, '')
      .replaceAll(_dayPartPrefix, '')
      .replaceAll('第', '')
      .replaceAll(_sectionUnit, '');
  if (cleaned.isEmpty) return null;

  var min = 1 << 30;
  var max = -1;
  var found = false;

  for (final token in cleaned.split(',')) {
    if (token.isEmpty) continue;
    final range = _rangeToken.firstMatch(token);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      final lo = a <= b ? a : b;
      final hi = a <= b ? b : a;
      if (lo < min) min = lo;
      if (hi > max) max = hi;
      found = true;
      continue;
    }
    final single = _singleToken.firstMatch(token);
    if (single != null) {
      final v = int.parse(single.group(1)!);
      if (v < min) min = v;
      if (v > max) max = v;
      found = true;
    }
  }

  if (!found || min < 1 || max > maxSection) return null;
  return SectionRange(min, max);
}

/// 解析紧凑节次写法，如 `0102`（第 1、2 节）、`01020304`（第 1-4 节）。
///
/// 这种写法歧义是真实存在的：必须整串是 4..8 位数字、长度为偶数，且每两位一组
/// 都落在 `1..maxSection` 内才认定。因此 `0102` → (1, 2)，而 `1234` 会被**拒绝**
/// （分组为 12 和 34，34 越界），调用方应回退到 [parseSections]，那里会把它当作
/// 单个数字 1234 从而同样返回 null。
SectionRange? parseCompactSections(String? raw, {int maxSection = 20}) {
  if (raw == null) return null;
  final cleaned = normalizeForParsing(raw)
      .replaceAll(_brackets, '')
      .replaceAll(_dayLabelPrefix, '')
      .replaceAll(_dayPartPrefix, '')
      .replaceAll('第', '')
      .replaceAll(_sectionUnit, '');
  if (!_compactToken.hasMatch(cleaned)) return null;
  if (cleaned.length.isOdd) return null;

  var min = 1 << 30;
  var max = -1;
  for (var i = 0; i < cleaned.length; i += 2) {
    final v = int.parse(cleaned.substring(i, i + 2));
    if (v < 1 || v > maxSection) return null;
    if (v < min) min = v;
    if (v > max) max = v;
  }
  if (max < 0) return null;
  return SectionRange(min, max);
}

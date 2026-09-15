import 'text_normalize.dart';

/// 周次的单双周形态。
enum WeekParity {
  /// 每周都上。
  all,

  /// 只上单周（1、3、5…）。
  odd,

  /// 只上双周（2、4、6…）。
  even,
}

/// 一次周次解析的结果。
class WeekPattern {
  /// 创建周次结果。
  WeekPattern({
    required Iterable<int> weeks,
    this.parity = WeekParity.all,
    this.truncated = false,
    this.source = '',
  }) : weeks = List<int>.unmodifiable(weeks);

  /// 已展开、升序排序、去重后的周次。
  final List<int> weeks;

  /// 声明时使用的单双周形态。
  ///
  /// 仅作回溯与调试之用：[weeks] 已经是最终展开结果，消费方不需要它。
  final WeekParity parity;

  /// 是否有周次因超出上界而被丢弃。
  final bool truncated;

  /// 原始字段文本。
  final String source;

  /// 是否没有得到任何周次。
  bool get isEmpty => weeks.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is WeekPattern &&
      other.parity == parity &&
      other.truncated == truncated &&
      other.source == source &&
      _listEquals(other.weeks, weeks);

  @override
  int get hashCode => Object.hash(parity, truncated, source, Object.hashAll(weeks));

  @override
  String toString() =>
      'WeekPattern(${weekListToString(weeks)}'
      '${parity == WeekParity.all ? '' : ', $parity'}'
      '${truncated ? ', truncated' : ''})';

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// "所有周"的同义词。
const List<String> _allSynonyms = <String>['每周', '全周', '全学期', '整学期', '全部周', '所有周'];

/// 需要剔除的周次单位。
const List<String> _weekUnits = <String>['星期', '礼拜', '周'];

/// 排除子句：`1-16周(除3,5)`、`(不含3,5)`、`(去掉第3周)`。
final RegExp _exclusionClause = RegExp(r'[（(](?:除|不含|去掉|排除)第?([\d,\-]+)周?[)）]');

/// 间隔子句：`1-16周(每2周)`。
final RegExp _intervalClause = RegExp(r'[（(]?每(\d+)周?[)）]?');

/// 区间 token：`3-16`。
final RegExp _rangeToken = RegExp(r'^(\d+)-(\d+)$');

/// 单点 token：`3`。
final RegExp _singleToken = RegExp(r'^\d+$');

/// 单个子句允许展开的最大周次，防止 `1-99999` 这类输入撑爆内存。
///
/// 语义上的"超出上界"由 `rejectWeeksAbove` 判定，这里只是内存护栏。
const int _kExpansionCap = 400;

/// 解析周次字段。
///
/// 支持区间、列表、单双周、全周、全角数字与六种破折号。返回的 [WeekPattern.weeks]
/// 一定是**展开后的整数列表**——这是拾光课程表全生态的共同契约，单双周只是解析
/// 期的临时概念。
///
/// 单双周按**每个子句**独立处理，因此 `1-8周(单),9-16周(双)` 得到
/// `[1,3,5,7,10,12,14,16]` 而不是 `1..16`；`1-16周(单双)` 这种一条子句里同时
/// 写了单和双的，按"全上"处理。
///
/// [raw] 完全不含周次信息时返回 null（调用方据此决定是回退"全周"还是丢弃）。
///
/// - [parityExpandToWeek]：裸 `单周`/`双周`/`全周` 没有数字可依时的展开上界。
/// - [rejectWeeksAbove]：超过此值的周次被丢弃并置 [WeekPattern.truncated]。
/// - [extraRangeSeparators]：额外当作区间分隔符的字符，例如某校用 `/`。
/// - [onWarning]：遇到无法理解的 token 时回调，便于上层转成诊断。
WeekPattern? parseWeeks(
  String? raw, {
  int parityExpandToWeek = 20,
  int rejectWeeksAbove = 30,
  List<String> extraRangeSeparators = const <String>[],
  void Function(String reason)? onWarning,
}) {
  if (raw == null) return null;
  var s = normalizeForParsing(raw);
  if (s.isEmpty) return null;
  for (final sep in extraRangeSeparators) {
    if (sep.isNotEmpty) s = s.replaceAll(sep, '-');
  }

  // 1. "全周"之类的同义词。
  var explicitAll = false;
  for (final word in _allSynonyms) {
    if (s.contains(word)) {
      explicitAll = true;
      s = s.replaceAll(word, '');
    }
  }
  if (s == '全' || s == '整') {
    explicitAll = true;
    s = '';
  }

  // 2. 排除与间隔子句必须在按逗号分词**之前**摘掉，因为它们自身含逗号。
  final excluded = <int>{};
  s = s.replaceAllMapped(_exclusionClause, (m) {
    for (final part in m.group(1)!.split(',')) {
      excluded.addAll(_expandSimple(part, 1, _kExpansionCap));
    }
    return '';
  });

  var interval = 1;
  s = s.replaceAllMapped(_intervalClause, (m) {
    final step = int.tryParse(m.group(1)!);
    if (step != null && step > 1) interval = step;
    return '';
  });

  // 3. 去掉装饰字。
  for (final unit in _weekUnits) {
    s = s.replaceAll(unit, '');
  }
  s = s.replaceAll('第', '');
  s = s.replaceAll(RegExp(r'[Ww]$'), '');
  // 排除/间隔子句的括号已被消费，剩下的括号只是单双周标记的外壳。
  s = s.replaceAll(RegExp(r'[()\[\]{}]'), '');
  if (s.isEmpty && !explicitAll) return null;

  // 4. 逐子句解析。单双周是**每个子句独立**的。
  final weeks = <int>{};
  final parities = <WeekParity>{};
  var anyClause = false;

  for (final rawToken in s.split(',')) {
    if (rawToken.isEmpty) continue;
    final hasOdd = rawToken.contains('单');
    final hasEven = rawToken.contains('双');
    final token = rawToken.replaceAll('单', '').replaceAll('双', '');
    final parity = hasOdd && hasEven
        ? WeekParity.all
        : hasOdd
        ? WeekParity.odd
        : hasEven
        ? WeekParity.even
        : WeekParity.all;
    if (hasOdd || hasEven) parities.add(parity);

    if (token.isEmpty) {
      // 裸 `单周` / `双周`：没有数字可依，按上界展开。
      if (hasOdd || hasEven) {
        anyClause = true;
        weeks.addAll(_seed(parity, parityExpandToWeek, interval, 1));
      }
      continue;
    }

    final values = _expandSimple(token, 1, _kExpansionCap);
    if (values.isEmpty) {
      onWarning?.call('无法理解的周次子句: "$rawToken"');
      continue;
    }
    anyClause = true;
    // 间隔以子句内第一个周次为基准，因此 `9-16(每2周)` 得到 9,11,13,15。
    final base = values.first;
    weeks.addAll(
      values.where((w) => _matches(parity, w) && (interval <= 1 || (w - base) % interval == 0)),
    );
  }

  // 5. 兜底：全周 / 裸单双周 / 什么都没有。
  if (!anyClause) {
    if (explicitAll) {
      weeks.addAll(_seed(WeekParity.all, parityExpandToWeek, interval, 1));
    } else {
      onWarning?.call('周次字段不含可识别的周次: "$raw"');
      return null;
    }
  }

  final truncated = weeks.any((w) => w > rejectWeeksAbove);
  final sorted =
      weeks.where((w) => w >= 1 && w <= rejectWeeksAbove && !excluded.contains(w)).toList()..sort();

  final parity = parities.isEmpty
      ? WeekParity.all
      : parities.length == 1
      ? parities.first
      : WeekParity.all;

  return WeekPattern(weeks: sorted, parity: parity, truncated: truncated, source: raw);
}

/// 判断一段文本是否"长得像周次字段"。
///
/// 用于单元格分块：周次行天然是一条记录的终止符。注意它接受不带单位的
/// `1-16`，所以**只应对已经被 layout 认定为周次字段的文本调用**，不要拿它去
/// 扫描任意文本——教室名里的 `A1-16` 会被误判。
bool looksLikeWeeks(String? raw) {
  if (raw == null) return false;
  var s = normalizeForParsing(raw);
  if (s.isEmpty) return false;
  for (final unit in _weekUnits) {
    s = s.replaceAll(unit, '');
  }
  s = s.replaceAll('第', '');
  for (final word in _allSynonyms) {
    s = s.replaceAll(word, '');
  }
  s = s.replaceAll('单', '').replaceAll('双', '');
  s = s.replaceAll(RegExp(r'[()\[\]{}]'), '');
  if (s.isEmpty) return false;
  return RegExp(r'^[\d,\-]+$').hasMatch(s);
}

/// 把 `[1,2,3,5,6]` 压成 `1-3,5-6`。
///
/// 宿主 App 的导入预览需要这个形式。
String weekListToString(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toSet().toList()..sort();
  final parts = <String>[];
  var start = sorted.first;
  var prev = start;
  for (var i = 1; i < sorted.length; i++) {
    final w = sorted[i];
    if (w == prev + 1) {
      prev = w;
      continue;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    start = w;
    prev = w;
  }
  parts.add(start == prev ? '$start' : '$start-$prev');
  return parts.join(',');
}

bool _matches(WeekParity parity, int week) => switch (parity) {
  WeekParity.all => true,
  WeekParity.odd => week.isOdd,
  WeekParity.even => week.isEven,
};

/// 展开一个不含单双周信息的简单子句，如 `3-16` 或 `7`。
List<int> _expandSimple(String token, int lower, int upper) {
  final range = _rangeToken.firstMatch(token);
  if (range != null) {
    var a = int.parse(range.group(1)!);
    var b = int.parse(range.group(2)!);
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    if (a < lower) a = lower;
    if (b > upper) b = upper;
    if (b < a) return const <int>[];
    return <int>[for (var w = a; w <= b; w++) w];
  }
  if (_singleToken.hasMatch(token)) {
    final v = int.parse(token);
    return v < lower ? const <int>[] : <int>[v];
  }
  return const <int>[];
}

/// 生成 `from..limit` 中符合 [parity] 且满足 [interval] 步长的周次。
List<int> _seed(WeekParity parity, int limit, int interval, int from) => <int>[
  for (var w = from; w <= limit; w++)
    if (_matches(parity, w) && (interval <= 1 || (w - from) % interval == 0)) w,
];

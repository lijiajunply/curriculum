import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

/// `a..b` 闭区间。
List<int> range(int a, int b) => <int>[for (var i = a; i <= b; i++) i];

/// `a..b` 中的单周。
List<int> odd(int a, int b) => <int>[
  for (var i = a; i <= b; i++)
    if (i.isOdd) i,
];

/// `a..b` 中的双周。
List<int> even(int a, int b) => <int>[
  for (var i = a; i <= b; i++)
    if (i.isEven) i,
];

void main() {
  group('parseWeeks 变体矩阵', () {
    final cases = <String, List<int>>{
      // ---- 基础区间 ----
      '1-16周': range(1, 16),
      '第1-16周': range(1, 16),
      '1-16': range(1, 16),
      '1周': <int>[1],
      '1,2,3周': <int>[1, 2, 3],

      // ---- 单双周 ----
      '1-16周(单)': odd(1, 16),
      '1-8周（单）': odd(1, 8),
      '1-16周(双)': even(1, 16),
      '第1-16周(双)': even(1, 16),
      '2-16双周': even(2, 16),
      '1-8周 单': odd(1, 8),
      '1-16周(单双)': range(1, 16),
      '单1-8周': odd(1, 8),

      // ---- 裸单双周（按 parityExpandToWeek 展开）----
      '双周': even(1, 20),
      '单周': odd(1, 20),
      '双': even(1, 20),

      // ---- 全周 ----
      '全周': range(1, 20),
      '每周': range(1, 20),
      '全': range(1, 20),
      '全学期': range(1, 20),

      // ---- 列表与多区间 ----
      '3-5,7,9周': <int>[3, 4, 5, 7, 9],
      '1,3,5-9周': <int>[1, 3, 5, 6, 7, 8, 9],
      '1-4,6-8,10-16周': <int>[...range(1, 4), ...range(6, 8), ...range(10, 16)],

      // ---- 分隔符与全角 ----
      '1~16周': range(1, 16),
      '1—16周': range(1, 16),
      '1－16周': range(1, 16),
      '1至16周': range(1, 16),
      '1到16周': range(1, 16),
      '１-１６周': range(1, 16),

      // ---- 多子句单双周：各自独立 ----
      '1-16周(单),1-16周(双)': range(1, 16),
      '1-8周(单),9-16周(双)': <int>[1, 3, 5, 7, 10, 12, 14, 16],

      // ---- 排除与间隔子句 ----
      '1-16周(除3,5)': range(1, 16).where((w) => w != 3 && w != 5).toList(),
      '1-16周(不含3,5)': range(1, 16).where((w) => w != 3 && w != 5).toList(),
      '1-16周(每2周)': odd(1, 16),
    };

    cases.forEach((input, expected) {
      test('"$input" -> ${weekListToString(expected)}', () {
        final pattern = parseWeeks(input);
        expect(pattern, isNotNull, reason: '应当解析出周次');
        expect(pattern!.weeks, equals(expected));
      });
    });
  });

  group('parseWeeks 边界与失败', () {
    test('null 与空串返回 null', () {
      expect(parseWeeks(null), isNull);
      expect(parseWeeks(''), isNull);
      expect(parseWeeks('   '), isNull);
    });

    test('纯文本返回 null 并回调警告', () {
      final reasons = <String>[];
      final pattern = parseWeeks('详询教务处', onWarning: reasons.add);
      expect(pattern, isNull);
      expect(reasons, isNotEmpty);
    });

    test('parityExpandToWeek 控制裸单双周的展开上界', () {
      expect(parseWeeks('单周', parityExpandToWeek: 5)!.weeks, <int>[1, 3, 5]);
      expect(parseWeeks('双周', parityExpandToWeek: 5)!.weeks, <int>[2, 4]);
      expect(parseWeeks('全周', parityExpandToWeek: 3)!.weeks, <int>[1, 2, 3]);
    });

    test('rejectWeeksAbove 丢弃越界周次并标记 truncated', () {
      final pattern = parseWeeks('1-16周', rejectWeeksAbove: 10)!;
      expect(pattern.weeks, range(1, 10));
      expect(pattern.truncated, isTrue);

      final clean = parseWeeks('1-16周')!;
      expect(clean.truncated, isFalse);
    });

    test('超大区间不会撑爆内存', () {
      final pattern = parseWeeks('1-99999周')!;
      expect(pattern.weeks, range(1, 30));
      expect(pattern.truncated, isTrue);
    });

    test('extraRangeSeparators 支持自定义区间分隔符', () {
      // 未声明 `/` 为分隔符时，`1/16` 是无法理解的子句 -> null。
      expect(parseWeeks('1/16周'), isNull);
      expect(parseWeeks('1/16周', extraRangeSeparators: <String>['/'])!.weeks, range(1, 16));
    });

    test('parity 记录声明形态供回溯', () {
      expect(parseWeeks('1-16周(单)')!.parity, WeekParity.odd);
      expect(parseWeeks('1-16周(双)')!.parity, WeekParity.even);
      expect(parseWeeks('1-16周')!.parity, WeekParity.all);
      // 多条子句形态不一致时归为 all。
      expect(parseWeeks('1-8周(单),9-16周(双)')!.parity, WeekParity.all);
    });

    test('source 保留原始文本', () {
      expect(parseWeeks('1-16周(单)')!.source, '1-16周(单)');
    });
  });

  group('weekListToString', () {
    test('压缩连续区间', () {
      expect(weekListToString(<int>[1, 2, 3, 5]), '1-3,5');
      expect(weekListToString(<int>[1]), '1');
      expect(weekListToString(<int>[]), '');
      expect(weekListToString(<int>[3, 1, 2]), '1-3');
      expect(weekListToString(<int>[2, 4, 6]), '2,4,6');
      expect(weekListToString(<int>[1, 2, 4, 5]), '1-2,4-5');
    });
  });
}

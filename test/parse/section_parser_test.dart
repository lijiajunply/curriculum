import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

void main() {
  group('parseSections', () {
    test('常见标签形式', () {
      expect(parseSections('1-2节'), const SectionRange(1, 2));
      expect(parseSections('第1-2节'), const SectionRange(1, 2));
      expect(parseSections('第3节'), const SectionRange(3, 3));
      expect(parseSections('3-4'), const SectionRange(3, 4));
      expect(parseSections('3'), const SectionRange(3, 3));
      expect(parseSections('12'), const SectionRange(12, 12));
      expect(parseSections('第1,2节'), const SectionRange(1, 2));
      expect(parseSections('1,2节'), const SectionRange(1, 2));
      expect(parseSections('上午1-2节'), const SectionRange(1, 2));
      expect(parseSections('下午5-6节'), const SectionRange(5, 6));
      expect(parseSections('晚上9-10节'), const SectionRange(9, 10));
      expect(parseSections('第1-4小节'), const SectionRange(1, 4));
    });

    test('分隔符与全角归一化', () {
      expect(parseSections('1～2节'), const SectionRange(1, 2));
      expect(parseSections('1至2节'), const SectionRange(1, 2));
      expect(parseSections('１-２节'), const SectionRange(1, 2));
      expect(parseSections('第1、2节'), const SectionRange(1, 2));
    });

    test('倒序区间会被纠正', () {
      expect(parseSections('4-2节'), const SectionRange(2, 4));
    });

    test('不连续写法合并为最小闭区间', () {
      expect(parseSections('第1,3节'), const SectionRange(1, 3));
      expect(parseSections('1-2,5-6节'), const SectionRange(1, 6));
    });

    test('越界与无效输入返回 null', () {
      expect(parseSections(null), isNull);
      expect(parseSections(''), isNull);
      expect(parseSections('节'), isNull);
      expect(parseSections('上午'), isNull);
      expect(parseSections('1-40节'), isNull);
      expect(parseSections('1-40节', maxSection: 50), const SectionRange(1, 40));
      expect(parseSections('0-2节'), isNull);
      expect(parseSections('详询教务处'), isNull);
      // 紧凑写法不会被 parseSections 认领：`0102` 是数字 102，越界。
      expect(parseSections('0102'), isNull);
    });
  });

  group('parseCompactSections', () {
    test('每两位一节次的紧凑写法', () {
      expect(parseCompactSections('0102'), const SectionRange(1, 2));
      expect(parseCompactSections('0304'), const SectionRange(3, 4));
      expect(parseCompactSections('01020304'), const SectionRange(1, 4));
      expect(parseCompactSections('第0102节'), const SectionRange(1, 2));
    });

    test('歧义输入被拒绝，交由 parseSections 兜底', () {
      // 分组为 12 与 34，34 越界 -> 拒绝。
      expect(parseCompactSections('1234'), isNull);
      // 长度不足 4 或为奇数 -> 不是紧凑写法。
      expect(parseCompactSections('12'), isNull);
      expect(parseCompactSections('123'), isNull);
      expect(parseCompactSections('1-2节'), isNull);
      expect(parseCompactSections(''), isNull);
      expect(parseCompactSections(null), isNull);
    });
  });

  group('SectionRange', () {
    test('length 与 sections', () {
      const r = SectionRange(3, 5);
      expect(r.length, 3);
      expect(r.sections, <int>[3, 4, 5]);
      expect(const SectionRange(1, 1).length, 1);
    });

    test('相等性与 toString', () {
      expect(const SectionRange(1, 2), const SectionRange(1, 2));
      expect(const SectionRange(1, 2).hashCode, const SectionRange(1, 2).hashCode);
      expect(const SectionRange(1, 2), isNot(const SectionRange(1, 3)));
      expect(const SectionRange(1, 2).toString(), '第1-2节');
    });
  });
}

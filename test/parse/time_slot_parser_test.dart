import 'package:curriculum/curriculum.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:test/test.dart';

Element table(String inner) => parseFragment('<table>$inner</table>').querySelector('table')!;

void main() {
  group('parseTimeSlots', () {
    test('URP 形态：id 给节次，文本给时间', () {
      final t = table('''
        <tr><th id="0_1">第1节 (08:00-08:45)</th><td>x</td></tr>
        <tr><th id="0_2">第2节 (08:55-09:40)</th><td>x</td></tr>
        <tr><th id="0_3">第3节 (10:00-10:45)</th><td>x</td></tr>
      ''');
      final slots = parseTimeSlots(t);
      expect(slots, hasLength(3));
      expect(slots[0].number, 1);
      expect(slots[0].startTime, '08:00');
      expect(slots[0].endTime, '08:45');
      expect(slots[2].number, 3);
      expect(slots[2].startTime, '10:00');
    });

    test('没有 id 时从文本里的节次标签取号', () {
      final t = table('''
        <tr><th>第1节 (08:00-08:45)</th></tr>
        <tr><th>第2节 (08:55-09:40)</th></tr>
      ''');
      final slots = parseTimeSlots(t);
      expect(slots.map((s) => s.number), <int>[1, 2]);
    });

    test('结果按节次升序，与文档顺序无关', () {
      final t = table('''
        <tr><th id="0_3">第3节 (10:00-10:45)</th></tr>
        <tr><th id="0_1">第1节 (08:00-08:45)</th></tr>
      ''');
      expect(parseTimeSlots(t).map((s) => s.number), <int>[1, 3]);
    });

    test('没有作息时间时返回空列表，不抛异常', () {
      final t = table('<tr><th>节次</th><td>星期一</td></tr>');
      expect(parseTimeSlots(t), isEmpty);
    });

    test('同号只保留第一条', () {
      final t = table('''
        <tr><th id="0_1">第1节 (08:00-08:45)</th></tr>
        <tr><th id="0_1">第1节 (09:00-09:45)</th></tr>
      ''');
      final slots = parseTimeSlots(t);
      expect(slots, hasLength(1));
      expect(slots.single.startTime, '08:00');
    });

    test('各种破折号与个位数小时', () {
      final t = table('''
        <tr><th id="0_1">第1节 (8:00～8:45)</th></tr>
        <tr><th id="0_2">第2节 (8:55至9:40)</th></tr>
      ''');
      final slots = parseTimeSlots(t);
      expect(slots[0].startTime, '08:00');
      expect(slots[0].endTime, '08:45');
      expect(slots[1].startTime, '08:55');
      expect(slots[1].endTime, '09:40');
    });

    test('alias 记录原始标签文本', () {
      final t = table('<tr><th id="0_1">第1节 (08:00-08:45)</th></tr>');
      expect(parseTimeSlots(t).single.alias, '第1节 (08:00-08:45)');
    });

    test('超出 maxSection 的节次被丢弃', () {
      final t = table('<tr><th id="0_99">第99节 (08:00-08:45)</th></tr>');
      expect(parseTimeSlots(t), isEmpty);
      expect(parseTimeSlots(t, maxSection: 100), hasLength(1));
    });

    test('可自定义 id 形态', () {
      final t = table('<tr><th id="period-4">第4节 (11:00-11:45)</th></tr>');
      expect(parseTimeSlots(t), hasLength(1)); // 文本兜底拿到了 4
      final slots = parseTimeSlots(t, idSectionPatterns: <RegExp>[RegExp(r'^period-(\d+)$')]);
      expect(slots.single.number, 4);
    });
  });
}

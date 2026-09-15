import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

import 'support/fixture_suite.dart';

void main() {
  group('公共 API 冒烟', () {
    test('barrel 导出了核心类型', () {
      expect(Course, isNotNull);
      expect(CourseConfig, isNotNull);
      expect(TimeSlot, isNotNull);
      expect(CourseImportResult, isNotNull);
      expect(ParseOptions, isNotNull);
      expect(ParseWarning, isNotNull);
      expect(SchoolAdapterRegistry, isNotNull);
      expect(SchoolAdapter, isNotNull);
      expect(MatrixTableAdapter, isNotNull);
      expect(BlockListAdapter, isNotNull);
      expect(EmbeddedJsonAdapter, isNotNull);
      expect(TableGrid, isNotNull);
      expect(parseWeeks, isNotNull);
      expect(parseSections, isNotNull);
      expect(extractCellLines, isNotNull);
    });

    test('最短可用路径：HTML 进，课程出', () {
      const html =
          '<table id="kbTable" class="timetable">'
          '<tr><th>节次</th><th>星期</th></tr>'
          '<tr><th></th><th>星期一</th></tr>'
          '<tr><td>第1-2节</td>'
          '<td>高等数学<br>张伟<br>1-16周<br>凌云楼101</td></tr>'
          '</table>';
      final result = SchoolAdapterRegistry.standard.parseAuto(html);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '高等数学');
      expect(result.toJsonString(), contains('"weeks"'));
    });
  });

  // 样本目录下的每个用例都会在这里变成一个测试。
  registerFixtureSuites();
}

import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

ParseContext ctx() => ParseContext(options: const ParseOptions());

CourseSource source(List<String> lines, {int day = 1, int start = 1, int end = 2, String? label}) =>
    CourseSource(lines: lines, day: day, sections: SectionRange(start, end), debugLabel: label);

const ordered = OrderedLineLayout(
  order: <CourseField>[
    CourseField.name,
    CourseField.teacher,
    CourseField.weeks,
    CourseField.position,
  ],
);

void main() {
  group('节次解析策略', () {
    test('默认：显式节次缺失时每条记录都拿完整跨度', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(
            <String>['程序设计基础', '刘洋', '1-16周', '信息楼B301', '程序设计基础(实验)', '刘洋', '1-16周', '信息楼机房4'],
            start: 3,
            end: 4,
          ),
        ],
        ordered,
        c,
      );
      expect(courses, hasLength(2));
      // 两条都拿整格跨度 3-4，因为它们是同一时段的并行开课。
      expect(courses.every((x) => x.startSection == 3 && x.endSection == 4), isTrue);
      expect(courses.map((x) => x.name), containsAll(<String>['程序设计基础', '程序设计基础(实验)']));
    });

    test('单元格文本里的显式节次优先于几何跨度', () {
      final c = ctx();
      const layout = OrderedLineLayout(
        order: <CourseField>[CourseField.name, CourseField.sections, CourseField.weeks],
      );
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '第1-2节', '1-16周'], start: 1, end: 4),
        ],
        layout,
        c,
      );
      expect(courses.single.startSection, 1);
      expect(courses.single.endSection, 2);
    });

    test('SectionSplit.even 按记录数均分', () {
      final c = ctx();
      const layout = CompositeLayout(<CourseCellLayout>[ordered]);
      final courses = parseCourseSources(
        <CourseSource>[
          source(
            <String>['A课', '甲', '1-16周', '教101', 'B课', '乙', '1-16周', '教102'],
            start: 1,
            end: 4,
          ),
        ],
        const _EvenLayout(),
        c,
      );
      expect(courses, hasLength(2));
      final sections = courses.map((x) => (x.startSection, x.endSection)).toList()
        ..sort((a, b) => a.$1!.compareTo(b.$1!));
      expect(sections, <(int?, int?)>[(1, 2), (3, 4)]);
      expect(layout, isNotNull);
    });

    test('SectionSplit.even 无法整除时退回整格并告警', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(
            <String>['A课', '甲', '1-16周', '教101', 'B课', '乙', '1-16周', '教102'],
            start: 1,
            end: 3,
          ),
        ],
        const _EvenLayout(),
        c,
      );
      expect(courses, hasLength(2));
      expect(courses.every((x) => x.startSection == 1 && x.endSection == 3), isTrue);
      expect(c.counters[ParseWarningKind.unevenSectionSplit], 1);
    });
  });

  group('后处理', () {
    test('同课程多条记录合并周次', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-8周', '凌云楼101']),
          source(<String>['高等数学', '张伟', '10-16周', '凌云楼101'], day: 2),
        ],
        ordered,
        c,
      );
      // day 不同 -> 不合并。
      expect(courses, hasLength(2));

      final c2 = ctx();
      final sameDay = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-8周', '凌云楼101'], start: 1, end: 2),
          source(<String>['高等数学', '张伟', '10-16周', '凌云楼101'], start: 1, end: 2),
        ],
        ordered,
        c2,
      );
      expect(sameDay, hasLength(1));
      expect(sameDay.single.weeks, <int>[...range(1, 8), ...range(10, 16)]);
      expect(c2.counters[ParseWarningKind.mergedSameCourse], 1);
    });

    test('地点不同则不合并——换教室要保留两块', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-8周', '凌云楼101']),
          source(<String>['高等数学', '张伟', '10-16周', '凌云楼208']),
        ],
        ordered,
        c,
      );
      expect(courses, hasLength(2));
    });

    test('完全重复的记录被丢弃', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-8周', '凌云楼101']),
          source(<String>['高等数学', '张伟', '1-8周', '凌云楼101']),
        ],
        ordered,
        c,
      );
      expect(courses, hasLength(1));
      expect(c.counters[ParseWarningKind.duplicateDropped], 1);
    });

    test('输出按 (星期, 起始节次, 课程名) 排序', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['丙课', '甲', '1-16周', '教1'], day: 3, start: 1, end: 2),
          source(<String>['乙课', '甲', '1-16周', '教2'], day: 1, start: 3, end: 4),
          source(<String>['甲课', '甲', '1-16周', '教3'], day: 1, start: 1, end: 2),
        ],
        ordered,
        c,
      );
      expect(courses.map((x) => x.name).toList(), <String>['甲课', '乙课', '丙课']);
    });
  });

  group('部分解析策略', () {
    test('空白单元格被跳过且不计入 parsed', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['-']),
        ],
        ordered,
        c,
      );
      expect(courses, isEmpty);
      expect(c.stats.cellsSkipped, 1);
      expect(c.stats.cellsParsed, 0);
    });

    test('无课程名的记录被丢弃，同批的其它记录保留', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          // 有教师有周次，唯独没有课程名 -> 这条作废。
          source(<String>['教师：张伟', '周次：1-16周'], start: 3, end: 4),
          // 完整的一条 -> 必须留下。
          source(<String>['课程名称：高等数学', '教师：张伟', '周次：1-16周']),
        ],
        const LabeledLineLayout(),
        c,
      );
      expect(courses, hasLength(1));
      expect(courses.single.name, '高等数学');
      expect(courses.single.startSection, 1);
      expect(c.counters[ParseWarningKind.missingName], 1);
    });

    test('周次解析失败时回退全周并保留课程', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '详询教务处', '教101']),
        ],
        ordered,
        c,
      );
      expect(courses, hasLength(1));
      expect(courses.single.weeks, range(1, 20));
      expect(c.counters[ParseWarningKind.weekParseFailed], 1);
    });

    test('emptyWeeksMeansAllWeeks=false 时丢弃周次为空的记录', () {
      final c = ParseContext(options: const ParseOptions(emptyWeeksMeansAllWeeks: false));
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '待定', '教101']),
        ],
        ordered,
        c,
      );
      expect(courses, isEmpty);
    });

    test('星期越界整格丢弃并记 error', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-16周', '教101'], day: 9),
        ],
        ordered,
        c,
      );
      expect(courses, isEmpty);
      expect(c.hasErrors, isTrue);
      expect(c.counters[ParseWarningKind.dayOutOfRange], 1);
    });

    test('keepRawCellText 时写入 remark', () {
      final c = ParseContext(options: const ParseOptions(keepRawCellText: true));
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-16周', '教101']),
        ],
        ordered,
        c,
      );
      expect(courses.single.remark, '高等数学 / 张伟 / 1-16周 / 教101');
    });

    test('缺少教师与地点只记 info 并填空串', () {
      final c = ctx();
      final courses = parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '1-16周']),
        ],
        const OrderedLineLayout(order: <CourseField>[CourseField.name, CourseField.weeks]),
        c,
      );
      expect(courses.single.teacher, '');
      expect(courses.single.position, '');
      expect(c.counters[ParseWarningKind.missingTeacher], 1);
      expect(c.counters[ParseWarningKind.missingPosition], 1);
    });

    test('统计计数正确', () {
      final c = ctx();
      parseCourseSources(
        <CourseSource>[
          source(<String>['高等数学', '张伟', '1-16周', '教101']),
          source(<String>['-']),
        ],
        ordered,
        c,
      );
      expect(c.stats.cellsSeen, 2);
      expect(c.stats.cellsParsed, 1);
      expect(c.stats.cellsSkipped, 1);
      expect(c.stats.coursesEmitted, 1);
    });
  });

  group('mergeAdjacentSections', () {
    test('相邻单节次合并成区间', () {
      final merged = mergeAdjacentSections(<Course>[
        Course(
          name: '高等数学',
          teacher: '张伟',
          position: 'A101',
          day: 1,
          startSection: 1,
          endSection: 1,
          weeks: <int>[1, 2],
        ),
        Course(
          name: '高等数学',
          teacher: '张伟',
          position: 'A101',
          day: 1,
          startSection: 2,
          endSection: 2,
          weeks: <int>[1, 2],
        ),
        Course(
          name: '高等数学',
          teacher: '张伟',
          position: 'A101',
          day: 1,
          startSection: 3,
          endSection: 3,
          weeks: <int>[1, 2],
        ),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.startSection, 1);
      expect(merged.single.endSection, 3);
    });

    test('不相邻或字段不同的记录不合并', () {
      final merged = mergeAdjacentSections(<Course>[
        Course(
          name: '高等数学',
          teacher: '张伟',
          position: 'A101',
          day: 1,
          startSection: 1,
          endSection: 1,
          weeks: <int>[1],
        ),
        Course(
          name: '高等数学',
          teacher: '张伟',
          position: 'A101',
          day: 1,
          startSection: 3,
          endSection: 3,
          weeks: <int>[1],
        ),
        Course(
          name: '高等数学',
          teacher: '李娜',
          position: 'A101',
          day: 1,
          startSection: 4,
          endSection: 4,
          weeks: <int>[1],
        ),
      ]);
      expect(merged, hasLength(3));
    });
  });
}

List<int> range(int a, int b) => <int>[for (var i = a; i <= b; i++) i];

/// 与 [ordered] 等价但强制均分节次的布局，用于验证 [SectionSplit.even]。
class _EvenLayout extends CourseCellLayout {
  const _EvenLayout();

  @override
  SectionSplit get sectionSplit => SectionSplit.even;

  @override
  List<RawCourseRecord> extract(List<String> lines) => const OrderedLineLayout(
    order: <CourseField>[
      CourseField.name,
      CourseField.teacher,
      CourseField.weeks,
      CourseField.position,
    ],
  ).extract(lines);
}

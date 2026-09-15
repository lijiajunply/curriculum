import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

const ordered = OrderedLineLayout(
  order: <CourseField>[
    CourseField.name,
    CourseField.teacher,
    CourseField.weeks,
    CourseField.position,
  ],
);

void main() {
  group('OrderedLineLayout 分块', () {
    test('正好一条记录', () {
      final records = ordered.extract(<String>['高等数学', '张伟', '1-16周', '凌云楼101']);
      expect(records, hasLength(1));
      expect(records.single.name, '高等数学');
      expect(records.single.teacher, '张伟');
      expect(records.single.weeksRaw, '1-16周');
      expect(records.single.position, '凌云楼101');
    });

    test('行数是字段数的整数倍时等分', () {
      final records = ordered.extract(<String>[
        '高等数学',
        '张伟',
        '1-16周',
        '凌云楼101',
        '线性代数',
        '陈晨',
        '2-16周',
        '凌云楼208',
      ]);
      expect(records, hasLength(2));
      expect(records[1].name, '线性代数');
      expect(records[1].position, '凌云楼208');
    });

    test('参差块：第二条记录缺地点，靠周次锚点仍能正确切分', () {
      final records = ordered.extract(<String>[
        '高等数学',
        '张伟',
        '1-8周',
        '教101',
        '线性代数',
        '陈晨',
        '2-16周',
      ]);
      expect(records, hasLength(2));
      expect(records[0].name, '高等数学');
      expect(records[0].position, '教101');
      expect(records[1].name, '线性代数');
      expect(records[1].weeksRaw, '2-16周');
      expect(records[1].position, isNull);
    });

    test('周次不在最后一位时锚点依然正确', () {
      const layout = OrderedLineLayout(
        order: <CourseField>[
          CourseField.name,
          CourseField.weeks,
          CourseField.teacher,
          CourseField.position,
        ],
      );
      final records = layout.extract(<String>['高等数学', '1-8周', '张伟', '教101', '线性代数', '2-16周', '陈晨']);
      expect(records, hasLength(2));
      expect(records[0].weeksRaw, '1-8周');
      expect(records[0].teacher, '张伟');
      expect(records[1].name, '线性代数');
      expect(records[1].teacher, '陈晨');
      expect(records[1].position, isNull);
    });

    test('blockSeparator 优先于其它分块策略', () {
      // RegExp 不是常量，所以这里不能是 const 构造。
      final layout = OrderedLineLayout(
        order: <CourseField>[
          CourseField.name,
          CourseField.teacher,
          CourseField.weeks,
          CourseField.position,
        ],
        blockSeparator: RegExp('^★'),
      );
      final records = layout.extract(<String>[
        '高等数学',
        '张伟',
        '1-16周',
        '教101',
        '★线性代数',
        '陈晨',
        '1-16周',
      ]);
      expect(records, hasLength(2));
      expect(records[1].name, '★线性代数');
      expect(records[1].weeksRaw, '1-16周');
    });

    test('ignore 占位字段被跳过', () {
      const layout = OrderedLineLayout(
        order: <CourseField>[
          CourseField.ignore,
          CourseField.name,
          CourseField.teacher,
          CourseField.weeks,
          CourseField.position,
        ],
      );
      final records = layout.extract(<String>['(2024)001', '高等数学', '张伟', '1-16周', '凌云楼101']);
      expect(records, hasLength(1));
      expect(records.single.name, '高等数学');
      expect(records.single.position, '凌云楼101');
      expect(records.single.leftovers, contains('(2024)001'));
    });
  });

  group('OrderedLineLayout 纠偏', () {
    test('串位的值被退回并按分类器重新分配', () {
      final records = ordered.extract(<String>['高等数学', '1-16周', '凌云楼101']);
      expect(records, hasLength(1));
      final r = records.single;
      expect(r.name, '高等数学');
      // `1-16周` 落在 teacher 位上，但教师名正则不匹配数字，被挪到 weeks。
      expect(r.weeksRaw, '1-16周');
      // `凌云楼101` 落在 weeks 位上，被挪到 position。
      expect(r.position, '凌云楼101');
      expect(r.teacher, isNull);
    });

    test('短课程名不会被误判成教师名而挪走', () {
      final records = ordered.extract(<String>['体育', '张伟', '1-16周', '风雨操场']);
      expect(records.single.name, '体育');
      expect(records.single.teacher, '张伟');
      expect(records.single.position, '风雨操场');
    });

    test('正常记录不做任何改动', () {
      final records = ordered.extract(<String>['高等数学', '张伟', '1-16周', '凌云楼101']);
      expect(records.single.leftovers, isEmpty);
    });
  });

  group('LabeledLineLayout', () {
    test('标签驱动、顺序无关', () {
      const layout = LabeledLineLayout();
      final records = layout.extract(<String>['教师：张伟', '课程名称：高等数学', '周次 1-16周', '上课地点:凌云楼101']);
      expect(records, hasLength(1));
      final r = records.single;
      expect(r.name, '高等数学');
      expect(r.teacher, '张伟');
      expect(r.weeksRaw, '1-16周');
      expect(r.position, '凌云楼101');
    });

    test('同一标签再次出现即开启新记录', () {
      const layout = LabeledLineLayout();
      final records = layout.extract(<String>[
        '课程名称：高等数学',
        '教师：张伟',
        '周次：1-8周',
        '课程名称：线性代数',
        '教师：陈晨',
        '周次：2-16周',
      ]);
      expect(records, hasLength(2));
      expect(records[0].name, '高等数学');
      expect(records[1].name, '线性代数');
      expect(records[1].weeksRaw, '2-16周');
    });

    test('长标签优先，`上课地点` 不会被 `地点` 抢先', () {
      const layout = LabeledLineLayout();
      final records = layout.extract(<String>['上课地点：凌云楼101']);
      expect(records.single.position, '凌云楼101');
    });

    test('无标签的行交给 fallback 布局', () {
      const layout = LabeledLineLayout(
        fallback: OrderedLineLayout(order: <CourseField>[CourseField.name, CourseField.teacher]),
      );
      final records = layout.extract(<String>['高等数学', '张伟', '周次：1-16周']);
      expect(records, hasLength(1));
      expect(records.single.name, '高等数学');
      expect(records.single.teacher, '张伟');
      expect(records.single.weeksRaw, '1-16周');
    });

    test('全无标签且无 fallback 时返回空', () {
      const layout = LabeledLineLayout();
      expect(layout.extract(<String>['高等数学', '张伟']), isEmpty);
    });
  });

  group('DelimitedLineLayout', () {
    test('单行分隔符', () {
      final layout = DelimitedLineLayout(
        pattern: RegExp(r'^(?<n>[^@]+)@(?<t>[^@]+)@(?<w>[^@]+)@(?<p>[^@]+)$'),
        groups: const <String, CourseField>{
          'n': CourseField.name,
          't': CourseField.teacher,
          'w': CourseField.weeks,
          'p': CourseField.position,
        },
      );
      final records = layout.extract(<String>['高等数学@张伟@1-16周@凌云楼101']);
      expect(records, hasLength(1));
      expect(records.single.name, '高等数学');
      expect(records.single.teacher, '张伟');
      expect(records.single.weeksRaw, '1-16周');
      expect(records.single.position, '凌云楼101');
    });

    test('不匹配的行被跳过', () {
      final layout = DelimitedLineLayout(
        pattern: RegExp(r'^(?<n>[^@]+)@(?<t>[^@]+)$'),
        groups: const <String, CourseField>{'n': CourseField.name, 't': CourseField.teacher},
      );
      expect(layout.extract(<String>['没有分隔符的一行']), isEmpty);
    });
  });

  group('CompositeLayout', () {
    test('第一个产出非空结果的布局胜出', () {
      const layout = CompositeLayout(<CourseCellLayout>[LabeledLineLayout(), ordered]);
      // 无标签 -> 落到 OrderedLineLayout。
      final records = layout.extract(<String>['高等数学', '张伟', '1-16周', '凌云楼101']);
      expect(records, hasLength(1));
      expect(records.single.name, '高等数学');
    });

    test('标签式输入由第一个布局处理', () {
      const layout = CompositeLayout(<CourseCellLayout>[LabeledLineLayout(), ordered]);
      final records = layout.extract(<String>['课程名称：高等数学']);
      expect(records.single.name, '高等数学');
      expect(records.single.teacher, isNull);
    });

    test('全部失败时返回空', () {
      const layout = CompositeLayout(<CourseCellLayout>[LabeledLineLayout()]);
      expect(layout.extract(<String>['随便一行']), isEmpty);
    });
  });

  group('ParenthesizedClauseLayout', () {
    const layout = ParenthesizedClauseLayout();

    test('抽出周次与节次子句，其余按顺序填', () {
      final records = layout.extract(<String>['高等数学A', '教一101', '(1~16周)', '(1,2节)']);
      expect(records, hasLength(1));
      final r = records.single;
      expect(r.name, '高等数学A');
      expect(r.position, '教一101');
      expect(r.weeksRaw, '1~16周');
      expect(r.sectionsRaw, '1,2节');
    });

    test('不含周/节的括号留在行里，课程名里的括号不被吃掉', () {
      final records = layout.extract(<String>['数据结构(实验)', '信息楼机房4', '(2~16周)', '(5,6节)']);
      expect(records.single.name, '数据结构(实验)');
      expect(records.single.position, '信息楼机房4');
    });

    test('嵌套括号子句被完整保留', () {
      final records = layout.extract(<String>['线性代数', '教二202', '(1~16周(单))', '(3,4节)']);
      expect(records.single.weeksRaw, '1~16周(单)');
      expect(records.single.sectionsRaw, '3,4节');
    });

    test('未识别的括号子句进 leftovers，不占用字段位', () {
      final records = layout.extract(<String>['体育', '风雨操场', '(1~16周)', '(7,8节)', '(上课组:1)']);
      expect(records.single.position, '风雨操场');
      expect(records.single.leftovers, contains('(上课组:1)'));
    });

    test('skipLinePattern 丢掉不带括号的噪声行', () {
      final noisy = ParenthesizedClauseLayout(skipLinePattern: RegExp('上课组|人数'));
      final records = noisy.extract(<String>['体育', '上课组:1', '风雨操场', '(1~16周)', '(7,8节)']);
      expect(records.single.name, '体育');
      expect(records.single.position, '风雨操场');
    });

    test('挤成一行时按地点特征拆开', () {
      final records = layout.extract(<String>['高等数学 教一101 (1~16周) (1,2节)']);
      expect(records.single.name, '高等数学');
      expect(records.single.position, '教一101');
      expect(records.single.weeksRaw, '1~16周');
    });

    test('拆不开时保持原样', () {
      final records = layout.extract(<String>['大学英语（视听说） (1~16周) (3,4节)']);
      expect(records.single.name, '大学英语（视听说）');
      expect(records.single.position, isNull);
    });

    test('全空返回零条记录', () {
      expect(layout.extract(<String>['', '  ']), isEmpty);
    });

    test('只有子句、没有正文时会产出一条无课程名的记录', () {
      // 这是刻意的：layout 只负责如实抽取，要不要留下交给上层的 missingName 判定。
      final records = layout.extract(<String>['(1~16周)']);
      expect(records, hasLength(1));
      expect(records.single.name, isNull);
      expect(records.single.weeksRaw, '1~16周');
    });
  });
}

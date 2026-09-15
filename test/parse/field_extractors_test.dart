import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

void main() {
  const h = Heuristics();

  group('Heuristics.score — 周次', () {
    test('带单位的周次拿满分', () {
      expect(h.score('1-16周', CourseField.weeks), 1);
      expect(h.score('第1-16周', CourseField.weeks), 1);
      expect(h.score('1-16周(单)', CourseField.weeks), 1);
      expect(h.score('3-5周', CourseField.weeks), 1);
    });

    test('裸区间只能拿半分', () {
      expect(h.score('1-16', CourseField.weeks), 0.55);
    });

    test('非周次文本得零分', () {
      expect(h.score('高等数学', CourseField.weeks), 0);
      expect(h.score('凌云楼101', CourseField.weeks), 0);
      expect(h.score('张伟', CourseField.weeks), 0);
      expect(h.score('', CourseField.weeks), 0);
    });
  });

  group('Heuristics.score — 节次', () {
    test('带"节"单位拿满分', () {
      expect(h.score('第1-2节', CourseField.sections), 1);
      expect(h.score('1-2节', CourseField.sections), 1);
      expect(h.score('上午1-2节', CourseField.sections), 1);
      expect(h.score('第3节', CourseField.sections), 1);
    });

    test('周次单位不会被判成节次', () {
      expect(h.score('1-16周', CourseField.sections), 0);
    });

    test('裸形式是低分候选', () {
      expect(h.score('1-2', CourseField.sections), 0.5);
      expect(h.score('1-16', CourseField.sections), 0.5);
      // 同样的字符串在周次上分更高，所以歧义时周次胜出。
      expect(
        h.score('1-16', CourseField.weeks),
        greaterThan(h.score('1-16', CourseField.sections)),
      );
    });
  });

  group('Heuristics.score — 地点与教师', () {
    test('含楼宇关键词的地点', () {
      expect(h.score('凌云楼101', CourseField.position), 0.9);
      expect(h.score('信息楼B301', CourseField.position), 0.9);
      expect(h.score('风雨操场', CourseField.position), 0.9);
      expect(h.score('A101', CourseField.position), 0.7);
      expect(h.score('B-301', CourseField.position), 0.7);
    });

    test('中文姓名', () {
      expect(h.score('张伟', CourseField.teacher), 0.6);
      expect(h.score('欧阳修', CourseField.teacher), 0.6);
      expect(h.score('张伟,李娜', CourseField.teacher), 0.75);
      // 四个汉字既是姓名也是课程名，只给弱分。
      expect(h.score('高等数学', CourseField.teacher), 0.3);
      expect(h.score('高等数学', CourseField.teacher), lessThan(h.score('高等数学', CourseField.name)));
      // 五个字以上不是姓名。
      expect(h.score('高等数学分析', CourseField.teacher), 0);
    });
  });

  group('Heuristics.score — 课程名', () {
    test('兜底字段接纳不像时间/地点/人名的行', () {
      expect(h.score('高等数学A', CourseField.name), 0.4);
      expect(h.score('大学英语（视听说）', CourseField.name), 0.4);
    });

    test('时间与地点不会被判成课程名', () {
      expect(h.score('1-16周', CourseField.name), 0);
      expect(h.score('第1-2节', CourseField.name), 0);
      expect(h.score('凌云楼101', CourseField.name), 0);
      expect(h.score('张伟', CourseField.name), 0);
    });

    test('单字符行不算课程名', () {
      expect(h.score('x', CourseField.name), 0);
    });
  });

  group('字段清洗', () {
    test('课程名去掉装饰符号', () {
      expect(h.normalizeCourseName('●高等数学'), '高等数学');
      expect(h.normalizeCourseName('★大学英语◆'), '大学英语');
      expect(h.normalizeCourseName('  高等数学  '), '高等数学');
    });

    test('教师名去掉星号与括注', () {
      expect(h.normalizeTeacher('张伟*'), '张伟');
      expect(h.normalizeTeacher('张伟（外聘）'), '张伟');
      expect(h.normalizeTeacher('李娜 *'), '李娜');
    });

    test('地点去掉校区前缀——仅当末段像房间号', () {
      expect(h.normalizePosition('东校区 凌云楼101'), '凌云楼101');
      expect(h.normalizePosition('本部 信息楼B301'), '信息楼B301');
      // 末段不含数字时保留原文，避免误伤被空格切开的教室名。
      expect(h.normalizePosition('教 学楼'), '教 学楼');
      expect(h.normalizePosition('凌云楼101'), '凌云楼101');
      expect(h.normalizePosition('  风雨操场  '), '风雨操场');
    });
  });

  group('标签字典', () {
    test('覆盖常见中文标签', () {
      expect(Heuristics.defaultLabels['课程名称'], CourseField.name);
      expect(Heuristics.defaultLabels['任课教师'], CourseField.teacher);
      expect(Heuristics.defaultLabels['周次'], CourseField.weeks);
      expect(Heuristics.defaultLabels['上课地点'], CourseField.position);
      expect(Heuristics.defaultLabels['节次'], CourseField.sections);
    });
  });
}

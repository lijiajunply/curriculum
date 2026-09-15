import 'week_parser.dart';

/// 课程记录里的字段。
enum CourseField {
  /// 课程名称。
  name,

  /// 任课教师。
  teacher,

  /// 上课地点。
  position,

  /// 上课周次。
  weeks,

  /// 节次。
  sections,

  /// 已知但用不上的字段（如课程代码），占位用，值会被丢弃。
  ignore,
}

/// 基于正则的行分类器与字段清洗。
///
/// 它只在按位置赋值**失败**之后兜底：`OrderedLineLayout` 先按 `order` 逐行赋值，
/// 剩下的空字段才交给这里的 [score] 去猜。所以这里的准确率不需要很高，但
/// **误判代价很大**，阈值因此设得偏保守。
class Heuristics {
  /// 创建分类器。
  const Heuristics();

  /// 带"星期/周/礼拜"单位的周次行。
  static final RegExp weekWithUnit = RegExp(
    r'^(?:第)?[\d,\-]+\s*(?:周|星期|礼拜)'
    r'\s*(?:[（(\[【]\s*[单双]\s*[)）\]】])?$',
  );

  /// 不带单位的纯数字区间，例如 `1-16`。
  ///
  /// 只有**带单位**的形态能拿到满分，因为 `1-16` 也可能是别的东西。
  static final RegExp weekBare = RegExp(r'^[\d,\-]+$');

  /// 带"节"单位的节次行。
  static final RegExp sectionWithUnit = RegExp(
    r'^(?:上午|下午|晚上|早上|早晨|中午|傍晚|夜间)?\s*'
    r'(?:第)?\s*\d{1,2}\s*(?:[-~～—－至到]\s*\d{1,2})?\s*(?:节|小节|节课)$',
  );

  /// 不带单位的节次行，例如 `1-2`。
  static final RegExp sectionBare = RegExp(r'^(?:第)?\s*\d{1,2}\s*[-~～—－至到]\s*\d{1,2}$');

  /// 含楼宇/房间关键词的地点。
  static final RegExp positionWithKeyword = RegExp(r'(楼|室|馆|院|区|号|机房|实验室|中心|操场|场|教室|阶梯|报告厅)');

  /// 纯房间编号，例如 `A101`、`B-301`。
  static final RegExp positionBareCode = RegExp(r'^[A-Za-z]{0,3}-?\d{1,4}$');

  /// 中文姓名，允许 `张三,李四` 这样的多人。
  static final RegExp teacherName = RegExp(r'^[一-龥]{2,4}(?:\s*[,，、]\s*[一-龥]{2,4})*$');

  /// 教室名里的楼层房间号，用于判断"最后一段"是否像房间。
  static final RegExp _digit = RegExp(r'\d');

  /// 课程名里的装饰符号。
  ///
  /// 正方等系统会在重修/辅修/调课课程名前加符号。
  static final RegExp _nameDecoration = RegExp('[●★○■☆◆◇▽▼△▲□▪◊※]');

  /// 教师名里的杂字符。
  static final RegExp _teacherNoise = RegExp(r'[*＊]');

  /// 括注，例如 `（外聘）`。
  static final RegExp _parenthetical = RegExp(r'[（(][^）)]*[）)]');

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// 默认的中文标签字典，用于 [LabeledLineLayout]。
  static const Map<String, CourseField> defaultLabels = <String, CourseField>{
    '课程名称': CourseField.name,
    '课程名': CourseField.name,
    '课程': CourseField.name,
    '名称': CourseField.name,
    '科目': CourseField.name,
    '任课教师': CourseField.teacher,
    '授课教师': CourseField.teacher,
    '教师': CourseField.teacher,
    '老师': CourseField.teacher,
    '讲师': CourseField.teacher,
    '周次': CourseField.weeks,
    '上课周次': CourseField.weeks,
    '周数': CourseField.weeks,
    '教室': CourseField.position,
    '地点': CourseField.position,
    '上课地点': CourseField.position,
    '上课教室': CourseField.position,
    '场地': CourseField.position,
    '位置': CourseField.position,
    '节次': CourseField.sections,
    '时间': CourseField.sections,
  };

  /// 给一行文本对某个字段的"像不像"打分，0.0 表示不像，1.0 表示确定。
  ///
  /// 带单位的形态（`1-16周`、`第1-2节`）明显高于裸形态（`1-16`、`1-2`），
  /// 因为后者歧义大得多。周次优先于节次：`1-16周` 不该被判成节次。
  double score(String line, CourseField field) {
    final t = line.trim();
    if (t.isEmpty) return 0;

    switch (field) {
      case CourseField.weeks:
        if (weekWithUnit.hasMatch(t)) return 1;
        // 裸 `1-2` 在节次与周次之间是真正歧义的，只有带区间时才给半分。
        if (weekBare.hasMatch(t) && t.contains('-') && looksLikeWeeks(t)) {
          return 0.55;
        }
        return 0;
      case CourseField.sections:
        if (weekWithUnit.hasMatch(t)) return 0;
        if (sectionWithUnit.hasMatch(t)) return 1;
        // `1-2` 既能当节次也能当周次，所以只给半分——周次的裸区间是 0.55，
        // 两者放在一起时周次胜出。
        if (sectionBare.hasMatch(t)) return 0.5;
        return 0;
      case CourseField.position:
        if (positionWithKeyword.hasMatch(t)) return 0.9;
        if (positionBareCode.hasMatch(t)) return 0.7;
        return 0;
      case CourseField.teacher:
        if (!teacherName.hasMatch(t)) return 0;
        if (t.contains(',') || t.contains('，') || t.contains('、')) return 0.75;
        // 四个汉字既是常见姓名（欧阳修文）也是常见课程名（高等数学），
        // 所以只给弱分，让课程名分支有机会胜出。
        return t.length <= 3 ? 0.6 : 0.3;
      case CourseField.name:
        // 名称是最不具辨识度的字段：任何既不像时间、也不像地点、也不像人名的
        // 非空行都可能是它。
        if (weekWithUnit.hasMatch(t) || sectionWithUnit.hasMatch(t)) return 0;
        if (positionWithKeyword.hasMatch(t) || positionBareCode.hasMatch(t)) {
          return 0;
        }
        if (score(t, CourseField.teacher) >= 0.6) return 0;
        return t.length >= 2 ? 0.4 : 0;
      case CourseField.ignore:
        return 0;
    }
  }

  /// 清洗课程名：去掉装饰符号、折叠空白。
  String normalizeCourseName(String raw) =>
      raw.replaceAll(_nameDecoration, '').replaceAll(_whitespaceRun, ' ').trim();

  /// 清洗教师名：去掉 `*` 与括注、折叠空白。
  String normalizeTeacher(String raw) => raw
      .replaceAll(_teacherNoise, ' ')
      .replaceAll(_parenthetical, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();

  /// 清洗上课地点：去掉"校区"前缀。
  ///
  /// 很多教务把地点写成 `东校区 凌云楼101`。只有当**最后一段含数字**（像房间号）
  /// 时才做截取，否则原样保留——`教 101` 这种被空格切开的写法不能误伤。
  String normalizePosition(String raw) {
    final t = raw.replaceAll(_whitespaceRun, ' ').trim();
    if (t.isEmpty) return t;
    final parts = t.split(' ');
    if (parts.length < 2) return t;
    final last = parts.last;
    return _digit.hasMatch(last) ? last : t;
  }
}

import '../model/course.dart';
import '../model/parse_context.dart';
import '../model/parse_warning.dart';
import 'cell_text.dart';
import 'course_cell_layout.dart';
import 'course_source.dart';
import 'field_extractors.dart';
import 'section_parser.dart';
import 'week_parser.dart';

/// 合并键：除周次外全部字段。
typedef _MergeKey = (String, String, String, int, int?, int?, bool, String?, String?);

/// 把一批 [CourseSource] 转成 [Course]。
///
/// 这是解析流水线的下游终点：上游不管是矩阵单元格、`<div>` 课程块还是内嵌 JSON
/// 记录，只要归约成 [CourseSource]，这里的行为就完全一致。
///
/// - [defaultMaxWeek]：周次缺失或"全周"时的展开上界。
List<Course> parseCourseSources(
  Iterable<CourseSource> sources,
  CourseCellLayout layout,
  ParseContext ctx, {
  int defaultMaxWeek = 20,
}) {
  const heuristics = Heuristics();
  final out = <Course>[];

  for (final source in sources) {
    ctx.recordCellSeen();
    final where = source.debugLabel;

    if (source.day < 1 || source.day > 7) {
      ctx.error(ParseWarningKind.dayOutOfRange, '星期 ${source.day} 不在 1..7，整格丢弃', location: where);
      ctx.recordCellSkipped();
      continue;
    }

    if (isBlankCell(source.lines)) {
      ctx.recordCellSkipped();
      continue;
    }

    final records = layout.extract(source.lines);
    if (records.isEmpty) {
      ctx.warn(
        ParseWarningKind.unknownCellText,
        '单元格文本无法理解（${layout.debugName}）',
        location: where,
        rawText: source.lines.join(' / '),
      );
      ctx.recordCellSkipped();
      continue;
    }

    final ranges = resolveSectionRanges(source, records, layout.sectionSplit, ctx);
    var emitted = 0;

    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final course = _buildCourse(source, record, ranges[i], heuristics, ctx, defaultMaxWeek);
      if (course != null) {
        out.add(course);
        emitted++;
      }
    }

    if (emitted > 0) {
      ctx.recordCellParsed();
    } else {
      ctx.recordCellSkipped();
    }
  }

  final result = _postprocess(out, ctx);
  ctx.recordCoursesEmitted(result.length);
  return result;
}

/// 解析一个单元格里各条记录应占据的节次跨度。
///
/// 显式节次永远优先；一条都没给出时，默认让**每条记录都拿完整跨度**——见
/// [SectionSplit.explicitOnly] 的说明，按记录数均分在真实课表里几乎总是错的。
List<SectionRange> resolveSectionRanges(
  CourseSource source,
  List<RawCourseRecord> records,
  SectionSplit split,
  ParseContext ctx,
) {
  final explicit = <SectionRange?>[for (final record in records) parseSections(record.sectionsRaw)];

  if (explicit.every((range) => range != null)) {
    return <SectionRange>[for (final range in explicit) range!];
  }

  final known = explicit.whereType<SectionRange>().toList();
  if (known.isNotEmpty) {
    ctx.info(
      ParseWarningKind.sectionParseFailed,
      '同一格内节次有缺失，缺失的记录按整格跨度处理',
      location: source.debugLabel,
    );
    return <SectionRange>[for (final range in explicit) range ?? source.sections];
  }

  switch (split) {
    case SectionSplit.explicitOnly:
    case SectionSplit.none:
      return List<SectionRange>.filled(records.length, source.sections);
    case SectionSplit.even:
      if (records.length == 1) return <SectionRange>[source.sections];
      final length = source.sections.length;
      if (length % records.length != 0) {
        ctx.warn(
          ParseWarningKind.unevenSectionSplit,
          '$length 个节次无法均分给 ${records.length} 条记录，退回整格跨度',
          location: source.debugLabel,
        );
        return List<SectionRange>.filled(records.length, source.sections);
      }
      final height = length ~/ records.length;
      return <SectionRange>[
        for (var i = 0; i < records.length; i++)
          SectionRange(
            source.sections.start + i * height,
            source.sections.start + (i + 1) * height - 1,
          ),
      ];
  }
}

Course? _buildCourse(
  CourseSource source,
  RawCourseRecord record,
  SectionRange range,
  Heuristics heuristics,
  ParseContext ctx,
  int defaultMaxWeek,
) {
  final where = source.debugLabel;
  final name = heuristics.normalizeCourseName(record.name ?? '');
  if (name.isEmpty) {
    ctx.warn(
      ParseWarningKind.missingName,
      '记录没有课程名，已丢弃',
      location: where,
      rawText: source.lines.join(' / '),
    );
    return null;
  }

  final rawWeeks = record.weeksRaw;
  var pattern = parseWeeks(rawWeeks, parityExpandToWeek: defaultMaxWeek);
  if (pattern == null) {
    if (rawWeeks != null && rawWeeks.trim().isNotEmpty) {
      if (!ctx.options.emptyWeeksMeansAllWeeks) {
        ctx.warn(
          ParseWarningKind.weekParseFailed,
          '周次无法解析，且未开启"空周次视为全周"，记录已丢弃',
          location: where,
          rawText: rawWeeks,
        );
        return null;
      }
      ctx.warn(
        ParseWarningKind.weekParseFailed,
        '周次无法解析，回退为全部 $defaultMaxWeek 周',
        location: where,
        rawText: rawWeeks,
      );
    }
    pattern = WeekPattern(
      weeks: <int>[for (var w = 1; w <= defaultMaxWeek; w++) w],
      source: rawWeeks ?? '',
    );
  }

  var start = range.start;
  var end = range.end;
  if (start > end) {
    ctx.warn(ParseWarningKind.sectionOutOfRange, '起始节次 $start 大于结束节次 $end，已交换', location: where);
    final swap = start;
    start = end;
    end = swap;
  }

  final teacher = heuristics.normalizeTeacher(record.teacher ?? '');
  final position = heuristics.normalizePosition(record.position ?? '');
  if (teacher.isEmpty) {
    ctx.info(ParseWarningKind.missingTeacher, '缺少教师', location: where);
  }
  if (position.isEmpty) {
    ctx.info(ParseWarningKind.missingPosition, '缺少上课地点', location: where);
  }

  return Course(
    name: name,
    teacher: teacher,
    position: position,
    day: source.day,
    startSection: start,
    endSection: end,
    weeks: pattern.weeks,
    remark: ctx.options.keepRawCellText ? source.lines.join(' / ') : null,
  );
}

List<Course> _postprocess(List<Course> courses, ParseContext ctx) {
  final seen = <Course>{};
  final unique = <Course>[];
  for (final course in courses) {
    if (seen.add(course)) {
      unique.add(course);
    } else {
      ctx.info(ParseWarningKind.duplicateDropped, '完全重复的记录已丢弃：${course.name}');
    }
  }

  final result = ctx.options.mergeSameCourse ? _mergeSameCourse(unique, ctx) : unique;
  result.sort(_compareCourses);
  return result;
}

List<Course> _mergeSameCourse(List<Course> courses, ParseContext ctx) {
  final groups = <_MergeKey, List<Course>>{};
  for (final course in courses) {
    final key = _keyOf(course);
    groups.putIfAbsent(key, () => <Course>[]).add(course);
  }

  final merged = <Course>[];
  for (final group in groups.values) {
    if (group.length == 1) {
      merged.add(group.first);
      continue;
    }
    final weeks = <int>{};
    for (final course in group) {
      weeks.addAll(course.weeks);
    }
    merged.add(group.first.copyWith(weeks: weeks));
    ctx.info(
      ParseWarningKind.mergedSameCourse,
      '合并了 ${group.length} 条同课程记录的周次：${group.first.name}',
    );
  }
  return merged;
}

_MergeKey _keyOf(Course course) => (
  course.name,
  course.teacher,
  course.position,
  course.day,
  course.startSection,
  course.endSection,
  course.isCustomTime,
  course.customStartTime,
  course.customEndTime,
);

int _compareCourses(Course a, Course b) {
  final byDay = a.day.compareTo(b.day);
  if (byDay != 0) return byDay;
  final bySection = (a.startSection ?? 0).compareTo(b.startSection ?? 0);
  if (bySection != 0) return bySection;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.position.compareTo(b.position);
}

/// 把逐节次给出的记录合并成连续区间。
///
/// 接口/内嵌 JSON 形态的课表（如超星）往往一条记录只对应一个节次，需要在
/// `(星期, 课程名, 教师, 地点, 周次)` 全同且节次相邻时并成 `startSection..endSection`。
List<Course> mergeAdjacentSections(List<Course> courses) {
  final sorted = List<Course>.of(courses)..sort(_compareCourses);
  final out = <Course>[];
  for (final course in sorted) {
    if (out.isEmpty) {
      out.add(course);
      continue;
    }
    final last = out.last;
    final contiguous =
        last.day == course.day &&
        last.name == course.name &&
        last.teacher == course.teacher &&
        last.position == course.position &&
        last.isCustomTime == course.isCustomTime &&
        last.customStartTime == course.customStartTime &&
        last.customEndTime == course.customEndTime &&
        _sameWeeks(last.weeks, course.weeks) &&
        course.startSection != null &&
        last.endSection != null &&
        course.startSection == last.endSection! + 1;
    if (contiguous) {
      out[out.length - 1] = last.copyWith(endSection: course.endSection);
    } else {
      out.add(course);
    }
  }
  return out;
}

bool _sameWeeks(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

import 'package:html/dom.dart';

import '../model/time_slot.dart';
import 'cell_text.dart';
import 'section_parser.dart';

/// 匹配 `08:00-09:40` 这类时间区间，允许多种破折号。
final RegExp _timeRange = RegExp(r'(\d{1,2}):(\d{2})\s*[-~～—－至到]\s*(\d{1,2}):(\d{2})');

/// 匹配 `第3节` 或 `第1-2节`。
final RegExp _sectionLabel = RegExp(r'第?\s*(\d{1,2})\s*(?:-\s*(\d{1,2}))?\s*节');

/// 默认的节次 id 形态：`0_3`、`section-3`、`row3`。
///
/// 第一条捕获组即节次号。URP 用 `th[id="0_5"]`，正方用 `td[id="3-5"]`。
final List<RegExp> kDefaultSectionIdPatterns = List<RegExp>.unmodifiable(<RegExp>[
  RegExp(r'^\d+_(\d+)$'),
  RegExp(r'^section[-_]?(\d+)$', caseSensitive: false),
  RegExp(r'^row[-_]?(\d+)$', caseSensitive: false),
]);

/// 从课表里抽取作息时间。
///
/// 作息时间对应拾光课程表的 `savePresetTimeSlots`，URP 等教务把每一节的起止
/// 时间写在表头单元格里（`<th id="0_1">第1节 (08:00-09:40)</th>`）。这里同时
/// 从 `id` 属性和单元格文本里取节次号，从文本里取时间区间；两者都有才产出一条。
///
/// 解析不到时返回空列表，**不报错**——很多课表根本不写作息时间。
///
/// - [cellSelector]：候选单元格选择器。默认扫全表，因为作息时间既可能在
///   `<th>` 表头，也可能在首列。
/// - [idSectionPatterns]：从 `id` 提取节次号的正则，第一条捕获组即节次号。
/// - [maxSection]：节次号的合理上界，超出即丢弃。
List<TimeSlot> parseTimeSlots(
  Element table, {
  String cellSelector = 'th, td',
  List<RegExp>? idSectionPatterns,
  int maxSection = 30,
}) {
  final idPatterns = idSectionPatterns ?? kDefaultSectionIdPatterns;
  final byNumber = <int, TimeSlot>{};

  for (final cell in table.querySelectorAll(cellSelector)) {
    final lines = extractCellLines(cell, keepWideGaps: false);
    if (lines.isEmpty) continue;
    final text = lines.join(' ');

    final time = _timeRange.firstMatch(text);
    if (time == null) continue;

    final number = _sectionNumber(cell, text, idPatterns, maxSection);
    if (number == null) continue;

    byNumber.putIfAbsent(
      number,
      () => TimeSlot(
        number: number,
        startTime: _pad(time.group(1)!, time.group(2)!),
        endTime: _pad(time.group(3)!, time.group(4)!),
        alias: lines.first,
      ),
    );
  }

  final slots = byNumber.values.toList()..sort((a, b) => a.number.compareTo(b.number));
  return slots;
}

int? _sectionNumber(Element cell, String text, List<RegExp> idPatterns, int maxSection) {
  final id = cell.attributes['id'];
  if (id != null) {
    for (final pattern in idPatterns) {
      final m = pattern.firstMatch(id.trim());
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n >= 1 && n <= maxSection) return n;
      }
    }
  }
  final label = _sectionLabel.firstMatch(text);
  if (label != null) {
    final n = int.tryParse(label.group(1)!);
    if (n != null && n >= 1 && n <= maxSection) return n;
  }
  // 退一步：用通用的节次解析器兜底。
  final range = parseSections(text, maxSection: maxSection);
  return range?.start;
}

String _pad(String hour, String minute) => '${hour.padLeft(2, '0')}:$minute';

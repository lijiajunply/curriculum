import 'dart:convert';

import 'package:html/dom.dart';

import '../model/course.dart';
import '../model/course_import_result.dart';
import '../model/parse_context.dart';
import '../model/parse_options.dart';
import '../model/parse_warning.dart';
import '../parse/html_utils.dart';
import 'school_adapter.dart';

/// 从一个页面里找出内嵌的 JSON 载荷。
abstract class JsonPayloadLocator {
  /// 找 `var scheduleData = {...};` 这类脚本变量。
  const factory JsonPayloadLocator.scriptVar(String variable) = _ScriptVar;

  /// 找 `<textarea id="...">` 里的 JSON。
  const factory JsonPayloadLocator.fromTextarea(String id) = _Textarea;

  /// 找某个元素属性里的 JSON。
  const factory JsonPayloadLocator.fromAttribute(String attribute) = _Attribute;

  /// 找被注释包起来的 JSON，例如 `<!--SCHEDULE_JSON {...} -->`。
  const factory JsonPayloadLocator.fromComment(String marker) = _Comment;

  /// 定位并解码；找不到返回 null。
  Object? locate(Document document, ParseContext ctx);

  /// 诊断用的可读描述。
  String describe();
}

/// 从 `start` 之后找第一个 `{` 或 `[`，再用**括号配对扫描**截出完整的 JSON。
///
/// 朴素的正则 `\{[\s\S]*?\}` 会被字符串里的 `}` 提前打断，所以必须跟踪深度与
/// 字符串/转义状态。
String? sliceJsonAt(String text, int from) {
  var start = -1;
  for (var i = from; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{' || ch == '[') {
      start = i;
      break;
    }
  }
  if (start < 0) return null;

  final open = text[start];
  final close = open == '{' ? '}' : ']';
  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == open) {
      depth++;
    } else if (ch == close) {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

Object? _tryDecode(String? raw) {
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

class _ScriptVar implements JsonPayloadLocator {
  const _ScriptVar(this.variable);

  final String variable;

  @override
  Object? locate(Document document, ParseContext ctx) {
    final pattern = RegExp('(?:var|let|const)?\\s*${RegExp.escape(variable)}\\s*=[^=]');
    for (final script in document.querySelectorAll('script')) {
      final text = script.text;
      if (text.isEmpty) continue;
      var searchFrom = 0;
      // 同一个脚本里可能有多次赋值；逐个起点重试，最多 5 次。
      for (var attempt = 0; attempt < 5; attempt++) {
        final match = pattern.firstMatch(text.substring(searchFrom.clamp(0, text.length)));
        if (match == null) break;
        final absolute = searchFrom + match.end;
        final slice = sliceJsonAt(text, absolute);
        final decoded = _tryDecode(slice);
        if (decoded != null) return decoded;
        searchFrom = absolute;
      }
    }
    return null;
  }

  @override
  String describe() => '脚本变量 $variable';
}

class _Textarea implements JsonPayloadLocator {
  const _Textarea(this.id);

  final String id;

  @override
  Object? locate(Document document, ParseContext ctx) {
    final element = document.getElementById(id);
    if (element == null) return null;
    return _tryDecode(element.text.trim());
  }

  @override
  String describe() => 'textarea#$id';
}

class _Attribute implements JsonPayloadLocator {
  const _Attribute(this.attribute);

  final String attribute;

  @override
  Object? locate(Document document, ParseContext ctx) {
    for (final element in document.querySelectorAll('[$attribute]')) {
      final raw = elementAttribute(element, attribute);
      final decoded = _tryDecode(raw);
      if (decoded != null) return decoded;
    }
    return null;
  }

  @override
  String describe() => '属性 $attribute';
}

class _Comment implements JsonPayloadLocator {
  const _Comment(this.marker);

  final String marker;

  @override
  Object? locate(Document document, ParseContext ctx) {
    Object? found;

    // 从文档根递归：注释可能挂在 body、html，甚至文档顶层，不能只看元素的后代。
    void walk(Node node) {
      if (found != null) return;
      for (final child in node.nodes) {
        if (child is Comment) {
          final data = child.text ?? '';
          final index = data.indexOf(marker);
          if (index >= 0) {
            final decoded = sliceJsonAt(data, index + marker.length);
            if (decoded != null) {
              found = _tryDecode(decoded);
              if (found != null) return;
            }
          }
        } else {
          walk(child);
        }
      }
    }

    walk(document);
    return found;
  }

  @override
  String describe() => '注释标记 $marker';
}

/// 内嵌 JSON 课表的适配器基类。
///
/// 有一类页面把课表数据留在 `<script>` 里（`var scheduleData = {...}`），再由前端
/// 渲染成 DOM。这类页面的 JSON schema 是各校自己的，所以 [mapPayload] 天然是
/// 每校一段 30–60 行的直白字段映射——但它绕开了整条文本解析链路。
abstract class EmbeddedJsonAdapter extends SchoolAdapter {
  /// 创建适配器。
  const EmbeddedJsonAdapter();

  /// JSON 载荷的定位策略。
  JsonPayloadLocator get locator;

  /// 把载荷映射成课程。这是子类唯一必须写的方法。
  List<Course> mapPayload(Object? payload, ParseContext ctx);

  @override
  CourseImportResult parseDocument(
    Document document, {
    ParseOptions options = const ParseOptions(),
  }) {
    final ctx = ParseContext(options: options, adapterId: info.adapterId);
    final payload = locator.locate(document, ctx);
    if (payload == null) {
      ctx.error(ParseWarningKind.payloadNotFound, '没找到内嵌 JSON 载荷（${locator.describe()}）');
      return CourseImportResult(
        courses: const <Course>[],
        warnings: ctx.warnings,
        adapterId: info.adapterId,
        stats: ctx.stats,
      );
    }
    final courses = mapPayload(payload, ctx);
    ctx.recordCoursesEmitted(courses.length);
    return CourseImportResult(
      courses: courses,
      warnings: ctx.warnings,
      adapterId: info.adapterId,
      stats: ctx.stats,
    );
  }
}

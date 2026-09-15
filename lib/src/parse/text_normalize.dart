/// 周次与节次字段共用的字符级归一化。
///
/// 教务系统的课表文本里混着全角数字、六种破折号、中文顿号，兼容性全靠这一层。
/// 归一化失败的正则是一条通往无穷 bug 的路，所以这一层被独立出来并单独测试。
library;

/// 全角数字 `０-９` 到半角 `0-9` 的映射。
const Map<String, String> _fullWidthDigits = <String, String>{
  '０': '0',
  '１': '1',
  '２': '2',
  '３': '3',
  '４': '4',
  '５': '5',
  '６': '6',
  '７': '7',
  '８': '8',
  '９': '9',
};

/// 各种"列表分隔"字符到半角逗号的映射。
const Map<String, String> _listSeparators = <String, String>{
  '，': ',',
  '、': ',',
  '；': ',',
  ';': ',',
  '·': ',',
  '・': ',',
};

/// 各种"区间分隔"字符到半角连字符的映射。
///
/// 含 `至` / `到` —— 中文里 `1至16周`、`1到16周` 都是合法写法。
const Map<String, String> _rangeSeparators = <String, String>{
  '～': '-',
  '~': '-',
  '－': '-',
  '—': '-',
  '–': '-',
  '−': '-',
  'ー': '-',
  '至': '-',
  '到': '-',
};

/// 各种括号到半角括号的映射。
const Map<String, String> _brackets = <String, String>{
  '（': '(',
  '）': ')',
  '［': '[',
  '］': ']',
  '【': '[',
  '】': ']',
  '｛': '{',
  '｝': '}',
};

/// 需要被当作普通空格处理的空白字符。
///
/// 含 `&nbsp;` 解码后的 U+00A0、全角空格 U+3000、若干 en/em 空格与 BOM。
final RegExp _wideWhitespace = RegExp('[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000\uFEFF]');

/// 把全角数字替换为半角。
String normalizeDigits(String input) {
  if (input.isEmpty) return input;
  final b = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    b.write(_fullWidthDigits[ch] ?? ch);
  }
  return b.toString();
}

/// 把各种列表与区间分隔符、括号统一为半角写法。
String normalizeSeparators(String input) {
  if (input.isEmpty) return input;
  final b = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    b.write(_listSeparators[ch] ?? _rangeSeparators[ch] ?? _brackets[ch] ?? ch);
  }
  return b.toString();
}

/// 把宽空白字符替换为普通空格。
String normalizeWhitespace(String input) =>
    input.isEmpty ? input : input.replaceAll(_wideWhitespace, ' ');

/// 一步到位：数字、分隔符、括号全部归一化，并**删除所有空白**。
///
/// 删除空白是刻意的：`1-8周 单` 与 `1-8周单` 应当等价。
String normalizeForParsing(String input) {
  if (input.isEmpty) return input;
  return normalizeWhitespace(
    normalizeSeparators(normalizeDigits(input)),
  ).replaceAll(RegExp(r'\s+'), '');
}

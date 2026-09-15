import 'json_utils.dart';

/// 一个节次的作息时间，字段对齐拾光课程表的 `TimeSlotJsonModel`。
class TimeSlot {
  /// 创建一个作息时间。
  const TimeSlot({
    required this.number,
    required this.startTime,
    required this.endTime,
    this.alias,
  });

  /// 从 JSON 对象解码。
  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    number: json.asInt('number'),
    startTime: json.asString('startTime'),
    endTime: json.asString('endTime'),
    alias: json.asStringOrNull('alias'),
  );

  /// 节次编号，从 1 开始。
  final int number;

  /// 开始时间，`HH:mm`。
  final String startTime;

  /// 结束时间，`HH:mm`。
  final String endTime;

  /// 该节次的别名，例如 `第1-2节`。
  final String? alias;

  /// 编码为 JSON 对象。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'number': number,
    'startTime': startTime,
    'endTime': endTime,
    if (alias != null) 'alias': alias,
  };

  /// 返回一个替换了部分字段的副本。
  TimeSlot copyWith({int? number, String? startTime, String? endTime, String? alias}) => TimeSlot(
    number: number ?? this.number,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    alias: alias ?? this.alias,
  );

  @override
  bool operator ==(Object other) =>
      other is TimeSlot &&
      other.number == number &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.alias == alias;

  @override
  int get hashCode => Object.hash(number, startTime, endTime, alias);

  @override
  String toString() => 'TimeSlot($number, $startTime-$endTime)';
}

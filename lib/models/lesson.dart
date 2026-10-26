import 'package:flutter/material.dart';

const weekdayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const weekdayShortNames = ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
const arabicMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

String timeToString(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String formatTime(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
int timeToMinutes(TimeOfDay value) => value.hour * 60 + value.minute;

TimeOfDay parseTime(String value, {TimeOfDay fallback = const TimeOfDay(hour: 8, minute: 0)}) {
  final parts = value.split(':');
  if (parts.length != 2) return fallback;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) return fallback;
  return TimeOfDay(hour: hour, minute: minute);
}

class Lesson {
  Lesson({
    required this.id,
    required this.name,
    required this.grade,
    required this.section,
    required this.start,
    required this.end,
    required this.days,
    this.enabled = true,
    this.endBellEnabled = true,
  });

  final String id;
  String name;
  String grade;
  String section;
  TimeOfDay start;
  TimeOfDay end;
  List<int> days;
  bool enabled;
  bool endBellEnabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'grade': grade,
        'section': section,
        'start': timeToString(start),
        'end': timeToString(end),
        'days': days,
        'enabled': enabled,
        'endBellEnabled': endBellEnabled,
      };

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final List<int> days;
    if (rawDays is List) {
      days = rawDays.whereType<num>().map((e) => e.toInt()).where((e) => e >= 1 && e <= 7).toSet().toList();
      days.sort();
    } else {
      days = <int>[1, 2, 3, 4, 5];
    }
    return Lesson(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'حصة جديدة',
      grade: json['grade']?.toString() ?? '',
      section: json['section']?.toString() ?? '',
      start: parseTime(json['start']?.toString() ?? '08:00'),
      end: parseTime(json['end']?.toString() ?? '08:45', fallback: const TimeOfDay(hour: 8, minute: 45)),
      days: days,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      endBellEnabled: json['endBellEnabled'] is bool ? json['endBellEnabled'] as bool : true,
    );
  }
}

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../theme/app_theme.dart';

class LessonEditorPage extends StatefulWidget {
  const LessonEditorPage({super.key, this.lesson});
  final Lesson? lesson;

  @override
  State<LessonEditorPage> createState() => _LessonEditorPageState();
}

class _LessonEditorPageState extends State<LessonEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _grade;
  late final TextEditingController _section;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late Set<int> _days;
  late bool _enabled;
  late bool _endBell;

  @override
  void initState() {
    super.initState();
    final value = widget.lesson;
    _name = TextEditingController(text: value?.name ?? '');
    _grade = TextEditingController(text: value?.grade ?? '');
    _section = TextEditingController(text: value?.section ?? '');
    _start = value?.start ?? const TimeOfDay(hour: 8, minute: 0);
    _end = value?.end ?? const TimeOfDay(hour: 8, minute: 45);
    _days = (value?.days ?? const [1, 2, 3, 4, 5]).toSet();
    _enabled = value?.enabled ?? true;
    _endBell = value?.endBellEnabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _grade.dispose();
    _section.dispose();
    super.dispose();
  }

  Future<void> _chooseTime(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (selected != null && mounted) setState(() => start ? _start = selected : _end = selected);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر يوماً واحداً على الأقل')));
      return;
    }
    if (timeToMinutes(_end) <= timeToMinutes(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وقت نهاية الحصة يجب أن يأتي بعد وقت بدايتها')));
      return;
    }
    final value = Lesson(
      id: widget.lesson?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      grade: _grade.text.trim(),
      section: _section.text.trim(),
      start: _start,
      end: _end,
      days: _days.toList()..sort(),
      enabled: _enabled,
      endBellEnabled: _endBell,
    );
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.lesson != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'تعديل الحصة' : 'حصة جديدة', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text('حفظ'), style: TextButton.styleFrom(foregroundColor: BellColors.gold))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF283A60), Color(0xFF17243C)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(24)),
              child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: BellColors.gold.withOpacity(.17), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.edit_calendar_rounded, color: BellColors.gold)), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('تفاصيل الحصة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('خصص وقتها وصفها وأيام تكرارها', style: TextStyle(color: BellColors.textMuted, fontSize: 12))]))]),
            ),
            const SizedBox(height: 20),
            TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'اسم الحصة', prefixIcon: Icon(Icons.menu_book_rounded)), validator: (value) => value == null || value.trim().isEmpty ? 'اكتب اسم الحصة' : null),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: TextFormField(controller: _grade, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'الصف', prefixIcon: Icon(Icons.school_outlined)))), const SizedBox(width: 10), Expanded(child: TextFormField(controller: _section, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'الشعبة', prefixIcon: Icon(Icons.groups_2_outlined))))]),
            const SizedBox(height: 24),
            const _FormSectionTitle(icon: Icons.schedule_rounded, title: 'التوقيت'),
            const SizedBox(height: 11),
            Row(children: [Expanded(child: _timeCard('بداية الحصة', _start, () => _chooseTime(true), BellColors.mint)), const SizedBox(width: 11), Expanded(child: _timeCard('نهاية الحصة', _end, () => _chooseTime(false), BellColors.rose))]),
            const SizedBox(height: 24),
            const _FormSectionTitle(icon: Icons.date_range_rounded, title: 'أيام التكرار'),
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: List.generate(7, (index) {
              final day = index + 1;
              final selected = _days.contains(day);
              return FilterChip(label: Text(weekdayNames[index]), selected: selected, onSelected: (value) => setState(() => value ? _days.add(day) : _days.remove(day)), selectedColor: BellColors.gold.withOpacity(.2), checkmarkColor: BellColors.gold, side: BorderSide(color: selected ? BellColors.gold.withOpacity(.4) : Colors.white.withOpacity(.08)), labelStyle: TextStyle(color: selected ? BellColors.gold : Colors.white70, fontWeight: selected ? FontWeight.w700 : FontWeight.w500));
            })),
            const SizedBox(height: 20),
            _SwitchCard(icon: Icons.notifications_active_rounded, title: 'جرس بداية الحصة', subtitle: 'يرن عند موعد بدء الحصة', value: _enabled, onChanged: (value) => setState(() => _enabled = value), color: BellColors.gold),
            const SizedBox(height: 9),
            _SwitchCard(icon: Icons.notifications_off_rounded, title: 'جرس نهاية الحصة', subtitle: 'ينبه عند الوقت المحدد لانتهاء الحصة', value: _endBell, onChanged: (value) => setState(() => _endBell = value), color: BellColors.rose),
            const SizedBox(height: 22),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_circle_outline_rounded), label: Padding(padding: const EdgeInsets.symmetric(vertical: 15), child: Text(editing ? 'حفظ التعديلات' : 'إضافة إلى الجدول', style: const TextStyle(fontWeight: FontWeight.w800)))),
          ],
        ),
      ),
    );
  }

  Widget _timeCard(String label, TimeOfDay value, VoidCallback onTap, Color accent) => Material(color: BellColors.surface, borderRadius: BorderRadius.circular(19), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(19), child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: BellColors.textMuted, fontSize: 12)), const SizedBox(height: 10), Row(children: [Icon(Icons.access_time_filled_rounded, color: accent, size: 18), const SizedBox(width: 8), Text(formatTime(value), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]))])])));
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: BellColors.gold, size: 19), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]);
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged, required this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(18)), child: SwitchListTile(value: value, onChanged: onChanged, activeTrackColor: color, secondary: Icon(icon, color: color), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: Text(subtitle, style: const TextStyle(color: BellColors.textMuted, fontSize: 11))));
}

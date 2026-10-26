import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';
import '../screens/lesson_editor_page.dart';
import '../theme/app_theme.dart';

const _native = MethodChannel('com.aieducation.schoolbell/native');

typedef LessonAction = Future<void> Function(Lesson lesson);

class SchoolBellShell extends StatefulWidget {
  const SchoolBellShell({super.key});

  @override
  State<SchoolBellShell> createState() => _SchoolBellShellState();
}

class _SchoolBellShellState extends State<SchoolBellShell> {
  final List<Lesson> _lessons = [];
  bool _loading = true;
  int _tab = 0;
  int _ringSeconds = 12;
  DateTime _now = DateTime.now();
  Timer? _clock;
  String? _startUri;
  String? _startName;
  String? _endUri;
  String? _endName;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('school_lessons_v1');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _lessons.addAll(decoded.whereType<Map>().map((e) => Lesson.fromJson(Map<String, dynamic>.from(e))));
        }
      } catch (_) {
        await prefs.remove('school_lessons_v1');
      }
    }
    _ringSeconds = prefs.getInt('ring_seconds_v2') ?? 12;
    _startUri = _notEmpty(prefs.getString('start_sound_uri'));
    _startName = _notEmpty(prefs.getString('start_sound_name'));
    _endUri = _notEmpty(prefs.getString('end_sound_uri'));
    _endName = _notEmpty(prefs.getString('end_sound_name'));
    _sortLessons();
    if (mounted) setState(() => _loading = false);
    await _syncNative();
  }

  String? _notEmpty(String? value) => value == null || value.isEmpty ? null : value;

  void _sortLessons() => _lessons.sort((a, b) => timeToMinutes(a.start).compareTo(timeToMinutes(b.start)));

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('school_lessons_v1', jsonEncode(_lessons.map((e) => e.toJson()).toList()));
    await prefs.setInt('ring_seconds_v2', _ringSeconds);
    await prefs.setString('start_sound_uri', _startUri ?? '');
    await prefs.setString('start_sound_name', _startName ?? '');
    await prefs.setString('end_sound_uri', _endUri ?? '');
    await prefs.setString('end_sound_name', _endName ?? '');
    await _syncNative();
  }

  Future<void> _syncNative() async {
    try {
      await _native.invokeMethod<void>('syncSchedules', {
        'lessons': _lessons.map((e) => e.toJson()).toList(),
        'startSoundUri': _startUri ?? '',
        'endSoundUri': _endUri ?? '',
        'ringSeconds': _ringSeconds,
      });
    } on PlatformException catch (error) {
      _toast('تعذر تحديث تنبيهات الجهاز: ${error.message ?? 'تحقق من الإعدادات'}');
    } on MissingPluginException {
      // The native scheduling bridge is implemented for Android.
    }
  }

  Future<void> _openEditor([Lesson? existing]) async {
    final result = await Navigator.of(context).push<Lesson>(MaterialPageRoute(builder: (_) => LessonEditorPage(lesson: existing)));
    if (result == null || !mounted) return;
    setState(() {
      final index = _lessons.indexWhere((lesson) => lesson.id == result.id);
      if (index == -1) {
        _lessons.add(result);
      } else {
        _lessons[index] = result;
      }
      _sortLessons();
    });
    await _persist();
    if (mounted) _toast(existing == null ? 'أضيفت الحصة إلى الجدول' : 'تم حفظ تعديلات الحصة');
  }

  Future<void> _toggleLesson(Lesson lesson) async {
    setState(() => lesson.enabled = !lesson.enabled);
    await _persist();
    if (mounted) _toast(lesson.enabled ? 'تم تفعيل رنين ${lesson.name}' : 'تم إيقاف رنين ${lesson.name}');
  }

  Future<void> _toggleEndBell(Lesson lesson) async {
    setState(() => lesson.endBellEnabled = !lesson.endBellEnabled);
    await _persist();
    if (mounted) _toast(lesson.endBellEnabled ? 'تم تفعيل جرس نهاية الحصة' : 'تم إيقاف جرس نهاية الحصة');
  }

  Future<void> _deleteLesson(Lesson lesson) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الحصة؟'),
        content: Text('سيتم حذف «${lesson.name}» وتنبيهاته من الجدول.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _lessons.removeWhere((e) => e.id == lesson.id));
    await _persist();
    if (mounted) _toast('تم حذف الحصة');
  }

  Future<void> _duplicateLesson(Lesson lesson) async {
    final copy = Lesson(id: DateTime.now().microsecondsSinceEpoch.toString(), name: '${lesson.name} (نسخة)', grade: lesson.grade, section: lesson.section, start: lesson.start, end: lesson.end, days: [...lesson.days], enabled: lesson.enabled, endBellEnabled: lesson.endBellEnabled);
    setState(() { _lessons.add(copy); _sortLessons(); });
    await _persist();
    if (mounted) _toast('تم نسخ الحصة؛ عدّل بيانات النسخة الجديدة');
    if (mounted) await _openEditor(copy);
  }

  Future<void> _chooseSound(bool isStart) async {
    try {
      final picked = await _native.invokeMapMethod<String, dynamic>('selectAudio');
      if (picked == null || picked['uri'] == null || !mounted) return;
      setState(() {
        if (isStart) {
          _startUri = picked['uri'] as String;
          _startName = picked['name'] as String? ?? 'صوت مختار';
        } else {
          _endUri = picked['uri'] as String;
          _endName = picked['name'] as String? ?? 'صوت مختار';
        }
      });
      await _persist();
      await _playSound(isStart ? _startUri : _endUri);
      if (mounted) _toast('تم حفظ الصوت ومعاينته');
    } on PlatformException catch (error) {
      _toast(error.message ?? 'تعذر فتح منتقي ملفات الصوت');
    } on MissingPluginException {
      _toast('اختيار ملفات الصوت متاح في نسخة Android');
    }
  }

  Future<void> _playSound(String? uri) async {
    try {
      await _native.invokeMethod<void>('previewAudio', {'uri': uri ?? ''});
    } on PlatformException catch (error) {
      _toast(error.message ?? 'تعذر تشغيل الصوت');
    } on MissingPluginException {
      _toast('معاينة الصوت متاحة في نسخة Android');
    }
  }

  Future<void> _requestAlarmAccess() async {
    try {
      await _native.invokeMethod<void>('requestAlarmAccess');
      if (mounted) _toast('اسمح بالتنبيهات الدقيقة والإشعارات إذا طلبها الهاتف');
    } on PlatformException catch (error) {
      _toast(error.message ?? 'تعذر فتح إعدادات التنبيه');
    }
  }

  Future<void> _copyBackup() async {
    final payload = jsonEncode({'version': 2, 'lessons': _lessons.map((e) => e.toJson()).toList(), 'ringSeconds': _ringSeconds});
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) _toast('تم نسخ نسخة احتياطية نصية إلى الحافظة');
  }

  Future<void> _restoreBackup() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboard?.text == null || clipboard!.text!.trim().isEmpty) {
      _toast('الحافظة فارغة؛ انسخ ملف النسخة الاحتياطية أولاً');
      return;
    }
    try {
      final data = jsonDecode(clipboard.text!);
      final list = data is Map ? data['lessons'] : null;
      if (list is! List) throw const FormatException('missing lessons');
      final restored = list.whereType<Map>().map((e) => Lesson.fromJson(Map<String, dynamic>.from(e))).toList();
      final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('استعادة الجدول؟'), content: Text('سيتم استبدال الجدول الحالي بـ ${restored.length} حصص.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استعادة'))]));
      if (confirm != true || !mounted) return;
      setState(() {
        _lessons..clear()..addAll(restored);
        if (data is Map && data['ringSeconds'] is num) _ringSeconds = (data['ringSeconds'] as num).toInt().clamp(3, 30).toInt();
        _sortLessons();
      });
      await _persist();
      if (mounted) _toast('تمت استعادة الجدول بنجاح');
    } catch (_) {
      _toast('تعذر قراءة النسخة الاحتياطية. تأكد من نسخ JSON الخاص بالتطبيق.');
    }
  }

  Future<void> _clearSchedule() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('مسح جميع الحصص؟'), content: const Text('سيتم حذف كل الحصص وإلغاء تنبيهاتها. لا يمكن التراجع عن هذه الخطوة.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إبقاء الجدول')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح'))]));
    if (confirm != true || !mounted) return;
    setState(_lessons.clear);
    await _persist();
    if (mounted) _toast('تم مسح الجدول');
  }

  void _setRingSeconds(int value) => setState(() => _ringSeconds = value);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  ({Lesson lesson, DateTime at})? _nextLesson() {
    ({Lesson lesson, DateTime at})? best;
    for (final lesson in _lessons.where((e) => e.enabled && e.days.isNotEmpty)) {
      for (var offset = 0; offset < 8; offset++) {
        final day = DateTime(_now.year, _now.month, _now.day + offset);
        if (!lesson.days.contains(day.weekday)) continue;
        final at = DateTime(day.year, day.month, day.day, lesson.start.hour, lesson.start.minute);
        if (!at.isAfter(_now)) continue;
        if (best == null || at.isBefore(best.at)) best = (lesson: lesson, at: at);
        break;
      }
    }
    return best;
  }

  Lesson? _currentLesson() {
    for (final lesson in _lessons.where((e) => e.enabled && e.days.contains(_now.weekday))) {
      final nowMinutes = _now.hour * 60 + _now.minute;
      if (nowMinutes >= timeToMinutes(lesson.start) && nowMinutes < timeToMinutes(lesson.end)) return lesson;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextLesson();
    final current = _currentLesson();
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: BellColors.gold))
            : IndexedStack(index: _tab, children: [
                _DashboardPage(now: _now, next: next, current: current, todayLessons: _lessons.where((e) => e.days.contains(_now.weekday)).toList(), onEdit: _openEditor, onAdd: () => _openEditor(), onOpenSchedule: () => setState(() => _tab = 1), onToggle: _toggleLesson, onToggleEnd: _toggleEndBell, onDelete: _deleteLesson, onDuplicate: _duplicateLesson),
                _SchedulePage(now: _now, lessons: _lessons, onEdit: _openEditor, onAdd: () => _openEditor(), onToggle: _toggleLesson, onToggleEnd: _toggleEndBell, onDelete: _deleteLesson, onDuplicate: _duplicateLesson),
                _SettingsPage(startName: _startName, endName: _endName, ringSeconds: _ringSeconds, onChooseStart: () => _chooseSound(true), onChooseEnd: () => _chooseSound(false), onPlayStart: () => _playSound(_startUri), onPlayEnd: () => _playSound(_endUri), onDurationChanged: _setRingSeconds, onDurationCommit: (_) => _persist(), onPermissions: _requestAlarmAccess, onBackup: _copyBackup, onRestore: _restoreBackup, onClear: _clearSchedule, lessonCount: _lessons.length),
              ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'الجدول'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
        ],
      ),
      floatingActionButton: _tab == 1 ? FloatingActionButton.extended(onPressed: () => _openEditor(), backgroundColor: BellColors.gold, foregroundColor: BellColors.background, icon: const Icon(Icons.add_rounded), label: const Text('حصة جديدة', style: TextStyle(fontWeight: FontWeight.w800))) : null,
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.now, required this.next, required this.current, required this.todayLessons, required this.onEdit, required this.onAdd, required this.onOpenSchedule, required this.onToggle, required this.onToggleEnd, required this.onDelete, required this.onDuplicate});
  final DateTime now;
  final ({Lesson lesson, DateTime at})? next;
  final Lesson? current;
  final List<Lesson> todayLessons;
  final LessonAction onEdit;
  final VoidCallback onAdd;
  final VoidCallback onOpenSchedule;
  final LessonAction onToggle;
  final LessonAction onToggleEnd;
  final LessonAction onDelete;
  final LessonAction onDuplicate;

  @override
  Widget build(BuildContext context) {
    final enabledToday = todayLessons.where((e) => e.enabled).length;
    final greeting = now.hour < 11 ? 'صباح النشاط' : now.hour < 16 ? 'نهارك الدراسي' : 'مساء الخير';
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 14), child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(gradient: const LinearGradient(colors: [BellColors.gold, Color(0xFFFF9D50)]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: BellColors.gold.withOpacity(.18), blurRadius: 20)]), child: const Icon(Icons.notifications_active_rounded, color: BellColors.background, size: 26)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: const TextStyle(color: BellColors.textMuted, fontSize: 12)), const Text('مركز التحكم بالجرس', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))])), Text(_clock(now), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]))])),
      SliverToBoxAdapter(child: _NextClassCard(now: now, current: current, next: next)),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 14), child: Row(children: [Expanded(child: _MetricCard(icon: Icons.event_available_rounded, label: 'حصص اليوم', value: '${todayLessons.length}', color: BellColors.sky)), const SizedBox(width: 10), Expanded(child: _MetricCard(icon: Icons.notifications_active_outlined, label: 'أجراس مفعلة', value: '$enabledToday', color: BellColors.mint)), const SizedBox(width: 10), Expanded(child: _MetricCard(icon: Icons.calendar_today_rounded, label: 'اليوم', value: weekdayShortNames[now.weekday - 1], color: BellColors.lavender))])),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(21, 8, 21, 10), child: Row(children: [const Expanded(child: Text('حصص اليوم', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))), TextButton(onPressed: onOpenSchedule, child: const Text('عرض الجدول')), const SizedBox(width: 4), IconButton(onPressed: onAdd, tooltip: 'إضافة حصة', style: IconButton.styleFrom(backgroundColor: BellColors.surfaceRaised), icon: const Icon(Icons.add_rounded, color: BellColors.gold))])),
      if (todayLessons.isEmpty)
        SliverToBoxAdapter(child: _EmptyCard(onAdd: onAdd))
      else
        SliverList.builder(itemCount: todayLessons.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _LessonTile(lesson: todayLessons[index], today: true, now: now, onEdit: onEdit, onToggle: onToggle, onToggleEnd: onToggleEnd, onDelete: onDelete, onDuplicate: onDuplicate))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 25), child: Center(child: Text('By قروب الذكاء الاصطناعي والتعليم', style: TextStyle(color: Colors.white.withOpacity(.38), fontSize: 11))))),
    ]);
  }
}

class _NextClassCard extends StatelessWidget {
  const _NextClassCard({required this.now, required this.current, required this.next});
  final DateTime now;
  final Lesson? current;
  final ({Lesson lesson, DateTime at})? next;

  String _remaining(Duration? value) {
    if (value == null) return '—';
    if (value.inDays > 0) return '${value.inDays}ي ${value.inHours % 24}س';
    if (value.inHours > 0) return '${value.inHours}س ${value.inMinutes % 60}د';
    if (value.inMinutes > 0) return '${value.inMinutes} دقيقة';
    return 'الآن';
  }

  @override
  Widget build(BuildContext context) {
    final active = current != null;
    final selected = current ?? next?.lesson;
    final when = next?.at.difference(now);
    final title = active ? 'الحصة جارية الآن' : selected == null ? 'جدولك ينتظرك' : 'الحصة القادمة';
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 7, 18, 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF314B78), Color(0xFF1B2D4B), Color(0xFF19243C)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(26), border: Border.all(color: Colors.white.withOpacity(.08)), boxShadow: [BoxShadow(color: const Color(0xFF233C68).withOpacity(.35), blurRadius: 22, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: active ? BellColors.mint : BellColors.gold, shape: BoxShape.circle)), const SizedBox(width: 8), Text(title, style: TextStyle(color: Colors.white.withOpacity(.78), fontWeight: FontWeight.w700)), const Spacer(), Text(_dateShort(now), style: const TextStyle(color: Colors.white60, fontSize: 11))]),
        const SizedBox(height: 19),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(selected?.name ?? 'أضف حصتك الأولى', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(selected == null ? 'نظّم جرس يومك الدراسي' : '${selected.grade.isEmpty ? 'حصة دراسية' : selected.grade}${selected.section.isEmpty ? '' : ' • شعبة ${selected.section}'}', style: const TextStyle(color: Colors.white70, fontSize: 13)), const SizedBox(height: 14), Row(children: [const Icon(Icons.access_time_rounded, color: BellColors.mint, size: 17), const SizedBox(width: 6), Text(active ? '${formatTime(selected!.start)} — ${formatTime(selected!.end)}' : next == null ? 'أضف حصصاً إلى جدولك' : '${weekdayNames[next.at.weekday - 1]} • ${formatTime(selected!.start)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))])])),
          const SizedBox(width: 12),
          Container(width: 82, height: 82, decoration: BoxDecoration(color: Colors.white.withOpacity(.075), shape: BoxShape.circle, border: Border.all(color: (active ? BellColors.mint : BellColors.gold).withOpacity(.5), width: 1.5)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(active ? Icons.school_rounded : Icons.hourglass_bottom_rounded, color: active ? BellColors.mint : BellColors.gold, size: 19), const SizedBox(height: 4), Text(active ? 'مستمرة' : _remaining(when), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11))])),
        ]),
        if (!active && next != null) ...[const SizedBox(height: 17), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _progress(now, next!.at), minHeight: 5, backgroundColor: Colors.white.withOpacity(.1), color: BellColors.gold)), const SizedBox(height: 7), Text('الموعد ${formatTime(TimeOfDay.fromDateTime(next!.at))}', style: const TextStyle(color: Colors.white54, fontSize: 11))],
      ]),
    );
  }

  double _progress(DateTime now, DateTime target) {
    final minutes = target.difference(now).inMinutes;
    return (1 - (minutes / (24 * 60)).clamp(0, 1)).toDouble();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13), decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(.04))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color, size: 18), const SizedBox(height: 9), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BellColors.textMuted, fontSize: 10))]));
}

class _SchedulePage extends StatefulWidget {
  const _SchedulePage({required this.now, required this.lessons, required this.onEdit, required this.onAdd, required this.onToggle, required this.onToggleEnd, required this.onDelete, required this.onDuplicate});
  final DateTime now;
  final List<Lesson> lessons;
  final LessonAction onEdit;
  final VoidCallback onAdd;
  final LessonAction onToggle;
  final LessonAction onToggleEnd;
  final LessonAction onDelete;
  final LessonAction onDuplicate;

  @override
  State<_SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<_SchedulePage> {
  late DateTime _selected;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = DateTime(widget.now.year, widget.now.month, widget.now.day);
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  List<DateTime> get _week {
    final monday = DateTime(widget.now.year, widget.now.month, widget.now.day).subtract(Duration(days: widget.now.weekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    final day = _selected.weekday;
    final query = _search.text.trim().toLowerCase();
    final dayLessons = widget.lessons.where((lesson) => lesson.days.contains(day) && (query.isEmpty || '${lesson.name} ${lesson.grade} ${lesson.section}'.toLowerCase().contains(query))).toList()..sort((a, b) => timeToMinutes(a.start).compareTo(timeToMinutes(b.start)));
    final enabledCount = dayLessons.where((e) => e.enabled).length;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(21, 23, 21, 15), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('الجدول الأسبوعي', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${arabicMonths[_selected.month - 1]} ${_selected.year}', style: const TextStyle(color: BellColors.textMuted, fontSize: 12))]), Container(width: 45, height: 45, decoration: BoxDecoration(color: BellColors.surfaceRaised, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.calendar_month_rounded, color: BellColors.gold))])),
      SliverToBoxAdapter(child: SizedBox(height: 84, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 17), itemCount: _week.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (context, index) { final date = _week[index]; final selected = date.year == _selected.year && date.month == _selected.month && date.day == _selected.day; final count = widget.lessons.where((e) => e.days.contains(date.weekday) && e.enabled).length; final today = date.year == widget.now.year && date.month == widget.now.month && date.day == widget.now.day; return GestureDetector(onTap: () => setState(() => _selected = date), child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 55, decoration: BoxDecoration(color: selected ? BellColors.gold : BellColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: today && !selected ? BellColors.gold.withOpacity(.45) : Colors.transparent)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(weekdayShortNames[date.weekday - 1], style: TextStyle(fontSize: 10, color: selected ? BellColors.background.withOpacity(.7) : BellColors.textMuted, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text('${date.day}', style: TextStyle(fontSize: 17, color: selected ? BellColors.background : Colors.white, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Container(width: 5, height: 5, decoration: BoxDecoration(color: count > 0 ? (selected ? BellColors.background : BellColors.mint) : Colors.transparent, shape: BoxShape.circle))]))); })),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 13), child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'ابحث عن حصة أو صف…', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded))))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(21, 2, 21, 11), child: Row(children: [Expanded(child: Text('${weekdayNames[day - 1]} • ${dayLessons.length} حصص', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), Text('$enabledCount مفعّلة', style: const TextStyle(color: BellColors.mint, fontSize: 11, fontWeight: FontWeight.w700))])),
      if (dayLessons.isEmpty)
        SliverToBoxAdapter(child: _EmptyCard(onAdd: widget.onAdd, title: 'يوم هادئ بلا حصص', subtitle: 'أضف حصة لهذا اليوم أو اختر يوماً آخر من الشريط أعلاه.'))
      else
        SliverList.builder(itemCount: dayLessons.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _LessonTile(lesson: dayLessons[index], today: _selected.year == widget.now.year && _selected.month == widget.now.month && _selected.day == widget.now.day, now: widget.now, onEdit: widget.onEdit, onToggle: widget.onToggle, onToggleEnd: widget.onToggleEnd, onDelete: widget.onDelete, onDuplicate: widget.onDuplicate))),
      SliverToBoxAdapter(child: const SizedBox(height: 100)),
    ]);
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.today, required this.now, required this.onEdit, required this.onToggle, required this.onToggleEnd, required this.onDelete, required this.onDuplicate});
  final Lesson lesson;
  final bool today;
  final DateTime now;
  final LessonAction onEdit;
  final LessonAction onToggle;
  final LessonAction onToggleEnd;
  final LessonAction onDelete;
  final LessonAction onDuplicate;

  @override
  Widget build(BuildContext context) {
    final nowMinutes = now.hour * 60 + now.minute;
    final inProgress = today && lesson.enabled && nowMinutes >= timeToMinutes(lesson.start) && nowMinutes < timeToMinutes(lesson.end);
    final isPast = today && nowMinutes >= timeToMinutes(lesson.end);
    final accent = !lesson.enabled ? BellColors.textMuted : inProgress ? BellColors.mint : lesson.endBellEnabled ? BellColors.gold : BellColors.sky;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: inProgress ? BellColors.mint.withOpacity(.33) : Colors.white.withOpacity(.04))),
      child: Padding(padding: const EdgeInsets.fromLTRB(13, 12, 14, 12), child: Row(children: [
        Column(children: [Text(formatTime(lesson.start), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])), Container(width: 2, height: 19, margin: const EdgeInsets.symmetric(vertical: 4), color: accent.withOpacity(.7)), Text(formatTime(lesson.end), style: const TextStyle(color: BellColors.textMuted, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]))]),
        const SizedBox(width: 13),
        Container(width: 4, height: 53, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(8))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(lesson.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: lesson.enabled ? Colors.white : Colors.white54))), if (inProgress) ...[const SizedBox(width: 6), const _StatusPill(label: 'الآن', color: BellColors.mint)] else if (isPast) ...[const SizedBox(width: 6), const _StatusPill(label: 'انتهت', color: BellColors.textMuted)] ]), const SizedBox(height: 5), Text('${lesson.grade.isEmpty ? 'بدون صف' : lesson.grade}${lesson.section.isEmpty ? '' : ' • شعبة ${lesson.section}'}', style: const TextStyle(color: BellColors.textMuted, fontSize: 11)), const SizedBox(height: 7), Row(children: [Icon(Icons.notifications_active_outlined, size: 13, color: lesson.enabled ? BellColors.gold : BellColors.textMuted), const SizedBox(width: 4), Text(lesson.enabled ? 'البداية مفعّلة' : 'الجرس متوقف', style: TextStyle(fontSize: 10, color: lesson.enabled ? BellColors.gold : BellColors.textMuted)), const SizedBox(width: 10), Icon(lesson.endBellEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 13, color: lesson.endBellEnabled ? BellColors.rose : BellColors.textMuted), const SizedBox(width: 4), Text('النهاية ${lesson.endBellEnabled ? 'مفعّلة' : 'متوقفة'}', style: TextStyle(fontSize: 10, color: lesson.endBellEnabled ? BellColors.rose : BellColors.textMuted))])])),
        PopupMenuButton<String>(tooltip: 'خيارات الحصة', icon: const Icon(Icons.more_horiz_rounded, color: BellColors.textMuted), onSelected: (value) { if (value == 'edit') onEdit(lesson); if (value == 'toggle') onToggle(lesson); if (value == 'end') onToggleEnd(lesson); if (value == 'duplicate') onDuplicate(lesson); if (value == 'delete') onDelete(lesson); }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: _MenuLabel(icon: Icons.edit_outlined, text: 'تعديل الحصة')), PopupMenuItem(value: 'toggle', child: _MenuLabel(icon: lesson.enabled ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, text: lesson.enabled ? 'إيقاف الجرس' : 'تفعيل الجرس')), PopupMenuItem(value: 'end', child: _MenuLabel(icon: lesson.endBellEnabled ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, text: lesson.endBellEnabled ? 'إيقاف جرس النهاية' : 'تفعيل جرس النهاية')), const PopupMenuItem(value: 'duplicate', child: _MenuLabel(icon: Icons.copy_rounded, text: 'نسخ الحصة')), const PopupMenuItem(value: 'delete', child: _MenuLabel(icon: Icons.delete_outline_rounded, text: 'حذف'))]),
      ])),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(text)]);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)));
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onAdd, this.title = 'لا توجد حصص بعد', this.subtitle = 'ابدأ بإضافة حصتك الأولى إلى الجدول.'});
  final VoidCallback onAdd;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.fromLTRB(18, 3, 18, 12), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white.withOpacity(.05))), child: Column(children: [Container(width: 58, height: 58, decoration: BoxDecoration(color: BellColors.gold.withOpacity(.12), shape: BoxShape.circle), child: const Icon(Icons.event_note_rounded, color: BellColors.gold, size: 27)), const SizedBox(height: 13), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: BellColors.textMuted, fontSize: 12)), const SizedBox(height: 14), OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('إضافة حصة'))]));
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.startName, required this.endName, required this.ringSeconds, required this.onChooseStart, required this.onChooseEnd, required this.onPlayStart, required this.onPlayEnd, required this.onDurationChanged, required this.onDurationCommit, required this.onPermissions, required this.onBackup, required this.onRestore, required this.onClear, required this.lessonCount});
  final String? startName;
  final String? endName;
  final int ringSeconds;
  final VoidCallback onChooseStart;
  final VoidCallback onChooseEnd;
  final VoidCallback onPlayStart;
  final VoidCallback onPlayEnd;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDurationCommit;
  final VoidCallback onPermissions;
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final VoidCallback onClear;
  final int lessonCount;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(19, 23, 19, 28), children: [
        const Text('الإعدادات', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('اضبط نغمة الجرس وسلوك التنبيهات', style: TextStyle(color: BellColors.textMuted, fontSize: 12)),
        const SizedBox(height: 21),
        const _SettingsSectionTitle(title: 'الأصوات', icon: Icons.graphic_eq_rounded),
        const SizedBox(height: 10),
        _SoundCard(title: 'جرس بداية الحصة', selectedName: startName, tint: BellColors.gold, onChoose: onChooseStart, onPlay: onPlayStart),
        const SizedBox(height: 9),
        _SoundCard(title: 'جرس نهاية الحصة', selectedName: endName, tint: BellColors.rose, onChoose: onChooseEnd, onPlay: onPlayEnd),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.fromLTRB(16, 14, 16, 13), decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(19)), child: Column(children: [Row(children: [const Icon(Icons.timer_rounded, color: BellColors.sky, size: 20), const SizedBox(width: 9), const Expanded(child: Text('مدة الرنين', style: TextStyle(fontWeight: FontWeight.w800))), Text('$ringSeconds ثانية', style: const TextStyle(color: BellColors.gold, fontWeight: FontWeight.w800))]), Slider(value: ringSeconds.toDouble(), min: 3, max: 30, divisions: 27, activeColor: BellColors.gold, label: '$ringSeconds ث', onChanged: (value) => onDurationChanged(value.round()), onChangeEnd: onDurationCommit), const Row(children: [Text('قصيرة', style: TextStyle(color: BellColors.textMuted, fontSize: 10)), Spacer(), Text('طويلة', style: TextStyle(color: BellColors.textMuted, fontSize: 10))])])),
        const SizedBox(height: 22),
        const _SettingsSectionTitle(title: 'موثوقية التنبيه', icon: Icons.verified_user_outlined),
        const SizedBox(height: 10),
        Material(color: BellColors.surface, borderRadius: BorderRadius.circular(19), child: InkWell(onTap: onPermissions, borderRadius: BorderRadius.circular(19), child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: BellColors.mint.withOpacity(.13), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.alarm_on_rounded, color: BellColors.mint)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('صلاحيات الجهاز', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('التنبيهات الدقيقة والإشعارات', style: TextStyle(color: BellColors.textMuted, fontSize: 11))])), const Icon(Icons.chevron_left_rounded, color: BellColors.textMuted)])))),
        const SizedBox(height: 7),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Text('قد تحتاج بعض أجهزة Android إلى السماح بالتشغيل في الخلفية من إعدادات البطارية.', style: TextStyle(color: BellColors.textMuted, fontSize: 10))),
        const SizedBox(height: 22),
        const _SettingsSectionTitle(title: 'البيانات', icon: Icons.backup_outlined),
        const SizedBox(height: 10),
        Container(decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(19)), child: Column(children: [_DataAction(icon: Icons.copy_all_rounded, title: 'نسخ نسخة احتياطية', subtitle: 'انسخ الحصص إلى الحافظة كنص JSON', onTap: onBackup), const Divider(height: 1, indent: 55, endIndent: 15), _DataAction(icon: Icons.settings_backup_restore_rounded, title: 'استعادة من الحافظة', subtitle: 'استبدل الجدول بنسخة سابقة', onTap: onRestore), const Divider(height: 1, indent: 55, endIndent: 15), _DataAction(icon: Icons.delete_sweep_outlined, title: 'مسح كل الحصص', subtitle: '$lessonCount حصة محفوظة حالياً', onTap: onClear, danger: true)])),
        const SizedBox(height: 24),
        Center(child: Column(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: BellColors.gold.withOpacity(.12), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.notifications_active_rounded, color: BellColors.gold)), const SizedBox(height: 9), const Text('جرس المدرسة • الإصدار الثاني', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 4), const Text('By قروب الذكاء الاصطناعي والتعليم', style: TextStyle(color: BellColors.textMuted, fontSize: 11))])),
        const SizedBox(height: 25),
      ]);
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 18, color: BellColors.gold), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]);
}

class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.title, required this.selectedName, required this.tint, required this.onChoose, required this.onPlay});
  final String title;
  final String? selectedName;
  final Color tint;
  final VoidCallback onChoose;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), decoration: BoxDecoration(color: BellColors.surface, borderRadius: BorderRadius.circular(19)), child: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: tint.withOpacity(.13), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.music_note_rounded, color: tint)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 4), Text(selectedName ?? 'نغمة المنبه الافتراضية', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BellColors.textMuted, fontSize: 10))])), IconButton(tooltip: 'معاينة الصوت', onPressed: onPlay, icon: const Icon(Icons.play_circle_fill_rounded, color: BellColors.mint, size: 26)), TextButton(onPressed: onChoose, child: const Text('تغيير'))]));
}

class _DataAction extends StatelessWidget {
  const _DataAction({required this.icon, required this.title, required this.subtitle, required this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(onTap: onTap, leading: Icon(icon, color: danger ? BellColors.rose : BellColors.sky), title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: danger ? BellColors.rose : Colors.white)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 10, color: BellColors.textMuted)), trailing: const Icon(Icons.chevron_left_rounded, color: BellColors.textMuted));
}

String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dateShort(DateTime value) => '${weekdayNames[value.weekday - 1]} ${value.day} ${arabicMonths[value.month - 1]}';

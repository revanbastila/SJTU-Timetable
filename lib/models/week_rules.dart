class WeekRule {
  const WeekRule({
    required this.weeks,
    required this.rawText,
    required this.inferred,
  });

  final List<int> weeks;
  final String rawText;
  final bool inferred;
}

WeekRule parseWeekRule(String source, {int totalWeeks = 18}) {
  final text = source
      .replaceAll('，', ',')
      .replaceAll('、', ',')
      .replaceAll('；', ';')
      .replaceAll('～', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('至', '-');
  final all = List<int>.generate(totalWeeks, (index) => index + 1);
  final hasOdd = RegExp(r'单\s*周').hasMatch(text);
  final hasEven = RegExp(r'双\s*周').hasMatch(text);
  final snippets = <String>[];
  final parsed = <int>{};

  // Accepts "2-5周、7-13周", "1,3,5周" and ranges with parity notes.
  final clause = RegExp(
    r'((?:第\s*)?\d{1,2}(?:\s*-\s*\d{1,2})?(?:\s*[,、]\s*\d{1,2}(?:\s*-\s*\d{1,2})?)*)\s*(单|双)?\s*周(?:\s*[（(]?\s*(单|双)\s*周?\s*[）)]?)?',
  );
  for (final match in clause.allMatches(text)) {
    final raw = match.group(0)!.trim();
    snippets.add(raw);
    final parity = match.group(2) ?? match.group(3);
    for (final part
        in match.group(1)!.replaceFirst(RegExp(r'^第\s*'), '').split(',')) {
      final bounds = part.trim().split(RegExp(r'\s*-\s*'));
      final first = int.tryParse(bounds.first);
      final last = int.tryParse(bounds.length > 1 ? bounds.last : bounds.first);
      if (first == null || last == null) continue;
      final low = first < last ? first : last;
      final high = first < last ? last : first;
      for (var week = low; week <= high; week++) {
        if (week < 1 || week > totalWeeks) continue;
        if (parity == '单' && week.isEven) continue;
        if (parity == '双' && week.isOdd) continue;
        parsed.add(week);
      }
    }
  }

  if (parsed.isEmpty && (hasOdd || hasEven)) {
    snippets.add(hasOdd ? '单周' : '双周');
    parsed.addAll(all.where((week) => hasOdd ? week.isOdd : week.isEven));
  } else if (parsed.isNotEmpty && hasOdd != hasEven) {
    parsed.removeWhere((week) => hasOdd ? week.isEven : week.isOdd);
  }

  if (parsed.isEmpty) {
    return WeekRule(weeks: all, rawText: '', inferred: true);
  }
  final weeks = parsed.toList()..sort();
  return WeekRule(
    weeks: weeks,
    rawText: snippets.toSet().join('、'),
    inferred: false,
  );
}

int academicWeekFor(DateTime date, DateTime firstMonday, int totalWeeks) {
  final inTerm = academicWeekInTerm(date, firstMonday, totalWeeks);
  if (inTerm != null) return inTerm;
  final day = DateTime(date.year, date.month, date.day);
  final start = DateTime(firstMonday.year, firstMonday.month, firstMonday.day);
  return day.isBefore(start) ? 1 : totalWeeks.clamp(1, 30);
}

int? academicWeekInTerm(DateTime date, DateTime firstMonday, int totalWeeks) {
  final day = DateTime(date.year, date.month, date.day);
  final start = DateTime(firstMonday.year, firstMonday.month, firstMonday.day);
  if (day.isBefore(start)) return null;
  final week = day.difference(start).inDays ~/ 7 + 1;
  return week >= 1 && week <= totalWeeks ? week : null;
}

DateTime mondayForAcademicWeek(DateTime firstMonday, int week) => DateTime(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day + (week - 1) * 7,
    );

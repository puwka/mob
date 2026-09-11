/// Supabase `timestamptz` helpers.
///
/// PostgREST / Realtime sometimes omit the `Z` / offset. Dart then treats the
/// value as *local* time, which shifts chat bubbles by the device UTC offset
/// and breaks chronological order when formats are mixed.
library;

DateTime parseSupabaseDateTime(Object? raw) {
  if (raw is DateTime) return raw.toUtc();
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) {
    throw FormatException('empty datetime', raw);
  }
  final parsed = DateTime.parse(s);
  if (parsed.isUtc || _hasExplicitTimezone(s)) {
    return parsed.toUtc();
  }
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

DateTime? tryParseSupabaseDateTime(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  try {
    return parseSupabaseDateTime(s);
  } catch (_) {
    return null;
  }
}

bool _hasExplicitTimezone(String s) {
  if (s.endsWith('Z') || s.endsWith('z')) return true;
  // +HH:MM / -HH:MM / +HHMM at end (not the date's separators)
  return RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
}

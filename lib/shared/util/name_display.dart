// Shortens a person's full name to a compact grid label: the first word plus
// the last word's initial, e.g. "Ammar Ali Hassan" -> "Ammar H.". This keeps
// the attendance grid tiles' name slot to a single short line, so a long name
// can't wrap and shrink the avatar above it. Used by AttendanceGridTile (and,
// later, the teacher grid that reuses that tile).
String shortLabelName(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts.last[0].toUpperCase()}.';
}

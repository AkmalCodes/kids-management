import 'package:flutter/material.dart';

// Single source of truth for the schedule-entry color palette. Used by the
// create/edit dialog's picker and by every display (agenda cards, day
// timetable blocks), so whatever color you pick is exactly what renders
// everywhere else — no separate hash-based color guessing.
const Map<String, String> scheduleColorPalette = {
  'Teal': '26A69A',
  'Magenta': 'D81B60',
  'Mustard': 'C0A02A',
  'Indigo': '5C6BC0',
  'Green': '66BB6A',
  'Red': 'EF5350',
  'Orange': 'FFA726',
  'Brown': '8D6E63',
};

const String defaultScheduleColorHex = '26A69A';

// Stored as a bare 6-digit hex string (no '#', no alpha) — 'FF' is
// prepended here to make it opaque.
Color colorFromScheduleHex(String hex) => Color(int.parse('FF$hex', radix: 16));

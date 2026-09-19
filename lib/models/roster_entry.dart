class RosterEntry {
  const RosterEntry({
    required this.scriptName,
    required this.sessionAt,
    required this.sessionEnd,
    required this.groupName,
    required this.guests,
    required this.bookingId,
    required this.companions,
  });

  factory RosterEntry.fromJson(Map<String, dynamic> json) {
    final scriptName = _requiredString(json, 'script_name');
    final groupName = _requiredString(json, 'group_name');
    final bookingId = _requiredString(json, 'booking_id');
    final sessionAt = _requiredDateTime(json, 'session_at');

    final rawEnd = json['session_end'];
    final sessionEnd = rawEnd == null
        ? null
        : _dateTimeFromValue(rawEnd, 'session_end');

    final rawGuests = json['guests'];
    if (rawGuests is! num || rawGuests < 0 || rawGuests % 1 != 0) {
      throw const FormatException('guests must be a non-negative integer');
    }

    final rawCompanions = json['companions'];
    if (rawCompanions is! List) {
      throw const FormatException('companions must be a list');
    }
    final companions = rawCompanions
        .map((value) {
          if (value is! String) {
            throw const FormatException('companions must contain strings');
          }
          return value.trim();
        })
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    return RosterEntry(
      scriptName: scriptName,
      sessionAt: sessionAt,
      sessionEnd: sessionEnd,
      groupName: groupName,
      guests: rawGuests.toInt(),
      bookingId: bookingId,
      companions: companions,
    );
  }

  final String scriptName;
  final DateTime sessionAt;
  final DateTime? sessionEnd;
  final String groupName;
  final int guests;
  final String bookingId;
  final List<String> companions;

  Map<String, dynamic> toJson() => {
    'script_name': scriptName,
    'session_at': sessionAt.toIso8601String(),
    'session_end': sessionEnd?.toIso8601String(),
    'group_name': groupName,
    'guests': guests,
    'booking_id': bookingId,
    'companions': companions,
  };

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value.trim();
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) {
      throw FormatException('$key is required');
    }
    return _dateTimeFromValue(json[key], key);
  }

  static DateTime _dateTimeFromValue(Object? value, String key) {
    if (value is! String) {
      throw FormatException('$key must be an ISO 8601 string');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$key must be a valid ISO 8601 string');
    }
    return parsed;
  }
}

class RosterSession {
  const RosterSession({
    required this.scriptName,
    required this.sessionAt,
    required this.sessionEnd,
    required this.entries,
  });

  final String scriptName;
  final DateTime sessionAt;
  final DateTime? sessionEnd;
  final List<RosterEntry> entries;
}

List<RosterSession> groupRosterEntries(Iterable<RosterEntry> entries) {
  final groups = <String, List<RosterEntry>>{};
  for (final entry in entries) {
    final key =
        '${entry.scriptName}\u0000${entry.sessionAt.toUtc().toIso8601String()}';
    groups.putIfAbsent(key, () => <RosterEntry>[]).add(entry);
  }

  final sessions = groups.values.map((group) {
    group.sort((a, b) => a.groupName.compareTo(b.groupName));
    final first = group.first;
    final ends = group
        .map((entry) => entry.sessionEnd)
        .whereType<DateTime>()
        .toList();
    ends.sort();
    return RosterSession(
      scriptName: first.scriptName,
      sessionAt: first.sessionAt,
      sessionEnd: ends.isEmpty ? null : ends.last,
      entries: List.unmodifiable(group),
    );
  }).toList();
  sessions.sort((a, b) => a.sessionAt.compareTo(b.sessionAt));
  return sessions;
}

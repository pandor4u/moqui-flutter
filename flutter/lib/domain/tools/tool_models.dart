/// Domain models for Moqui system tools (cache management, log viewing).
library;

import 'package:equatable/equatable.dart';

// ============================================================================
// Cache Info — Represents a single cache entry in the cache list
// ============================================================================

class CacheInfo extends Equatable {
  final String name;
  final String type; // local, distributed
  final int size;
  final int maxEntries;
  final int hitCount;
  final int missCount;
  final int removeCount;
  final int expireTimeIdle; // seconds
  final int expireTimeLive; // seconds

  const CacheInfo({
    required this.name,
    this.type = 'local',
    this.size = 0,
    this.maxEntries = 0,
    this.hitCount = 0,
    this.missCount = 0,
    this.removeCount = 0,
    this.expireTimeIdle = 0,
    this.expireTimeLive = 0,
  });

  factory CacheInfo.fromJson(Map<String, dynamic> json) {
    return CacheInfo(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'local',
      size: _parseInt(json['size']),
      maxEntries: _parseInt(json['maxEntries']),
      hitCount: _parseInt(json['hitCount']),
      missCount: _parseInt(json['missCount']),
      removeCount: _parseInt(json['removeCount']),
      expireTimeIdle: _parseInt(json['expireTimeIdle']),
      expireTimeLive: _parseInt(json['expireTimeLive']),
    );
  }

  double get hitRate =>
      (hitCount + missCount) > 0 ? hitCount / (hitCount + missCount) : 0.0;

  @override
  List<Object?> get props => [name, type, size];
}

// ============================================================================
// Log Entry — A single log line
// ============================================================================

class LogEntry extends Equatable {
  final DateTime timestamp;
  final String level; // TRACE, DEBUG, INFO, WARN, ERROR, FATAL
  final String loggerName;
  final String message;
  final String? throwable;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.loggerName,
    required this.message,
    this.throwable,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: _parseTimestamp(json['timestamp']),
      level: json['level']?.toString() ?? 'INFO',
      loggerName: json['loggerName']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      throwable: json['throwable']?.toString(),
    );
  }

  /// Parse a log line in standard format:
  /// `2024-01-15 10:30:45.123 INFO  [loggerName] message text`
  factory LogEntry.fromLogLine(String line) {
    // Try standard pattern: timestamp level [logger] message
    final match = _logLinePattern.firstMatch(line);
    if (match != null) {
      return LogEntry(
        timestamp: _parseTimestamp(match.group(1)),
        level: match.group(2)?.trim() ?? 'INFO',
        loggerName: match.group(3) ?? '',
        message: match.group(4) ?? '',
      );
    }
    // Fallback: treat entire line as message
    return LogEntry(
      timestamp: DateTime.now(),
      level: 'INFO',
      loggerName: '',
      message: line,
    );
  }

  static final _logLinePattern = RegExp(
    r'^(\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}[\.\d]*)\s+'
    r'(\w+)\s+'
    r'\[([^\]]*)\]\s+'
    r'(.*)$',
  );

  /// Severity index for sorting/filtering (higher = more severe).
  int get severityIndex {
    switch (level.toUpperCase()) {
      case 'FATAL':
        return 6;
      case 'ERROR':
        return 5;
      case 'WARN':
      case 'WARNING':
        return 4;
      case 'INFO':
        return 3;
      case 'DEBUG':
        return 2;
      case 'TRACE':
      case 'ALL':
        return 1;
      default:
        return 0;
    }
  }

  @override
  List<Object?> get props => [timestamp, level, loggerName, message];
}

// ============================================================================
// Log Filter — Criteria for filtering log entries
// ============================================================================

class LogFilter extends Equatable {
  final String? level; // Minimum level to show
  final String? loggerName; // Filter by logger name (substring match)
  final DateTime? timeFrom;
  final DateTime? timeTo;
  final String? messagePattern; // Search pattern in message

  const LogFilter({
    this.level,
    this.loggerName,
    this.timeFrom,
    this.timeTo,
    this.messagePattern,
  });

  /// Convert to query parameters for API calls.
  Map<String, dynamic> toParams() {
    final params = <String, dynamic>{};
    if (level != null) params['level'] = level;
    if (loggerName != null && loggerName!.isNotEmpty) {
      params['loggerName'] = loggerName;
    }
    if (timeFrom != null) params['timeFrom'] = timeFrom!.toIso8601String();
    if (timeTo != null) params['timeTo'] = timeTo!.toIso8601String();
    if (messagePattern != null && messagePattern!.isNotEmpty) {
      params['messagePattern'] = messagePattern;
    }
    return params;
  }

  /// Whether any filter criteria is active.
  bool get isActive =>
      level != null ||
      (loggerName != null && loggerName!.isNotEmpty) ||
      timeFrom != null ||
      timeTo != null ||
      (messagePattern != null && messagePattern!.isNotEmpty);

  /// Apply this filter to a log entry. Returns true if the entry matches.
  bool matches(LogEntry entry) {
    if (level != null) {
      final minSeverity = _levelSeverity(level!);
      if (entry.severityIndex < minSeverity) return false;
    }
    if (loggerName != null && loggerName!.isNotEmpty) {
      if (!entry.loggerName.toLowerCase().contains(loggerName!.toLowerCase())) {
        return false;
      }
    }
    if (timeFrom != null && entry.timestamp.isBefore(timeFrom!)) return false;
    if (timeTo != null && entry.timestamp.isAfter(timeTo!)) return false;
    if (messagePattern != null && messagePattern!.isNotEmpty) {
      if (!entry.message.toLowerCase().contains(messagePattern!.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  @override
  List<Object?> get props => [level, loggerName, timeFrom, timeTo, messagePattern];
}

// ============================================================================
// Helpers
// ============================================================================

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime _parseTimestamp(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.now();
}

int _levelSeverity(String level) {
  switch (level.toUpperCase()) {
    case 'FATAL':
      return 6;
    case 'ERROR':
      return 5;
    case 'WARN':
    case 'WARNING':
      return 4;
    case 'INFO':
      return 3;
    case 'DEBUG':
      return 2;
    case 'TRACE':
    case 'ALL':
      return 1;
    default:
      return 0;
  }
}

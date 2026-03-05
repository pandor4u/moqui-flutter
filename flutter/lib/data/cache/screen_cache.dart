/// LRU screen cache with 5-minute TTL.
///
/// Caches recently fetched screen JSON (keyed by path + serialized params)
/// to reduce redundant API calls during tab-switching and back-navigation.
/// This is NOT offline-first — just a performance cache.
///
/// Cache entries are invalidated:
///   • On form submit (via [invalidateForPath])
///   • After TTL expires (5 minutes)
///   • When the cache exceeds its max size (LRU eviction)
library;

import 'dart:collection';

class ScreenCache {
  /// Maximum number of cached screens.
  static const int maxSize = 50;

  /// Time-to-live for cached entries.
  static const Duration ttl = Duration(minutes: 5);

  /// Singleton instance.
  static final ScreenCache instance = ScreenCache._();

  ScreenCache._();

  /// Internal LRU cache: key → (json, timestamp).
  final LinkedHashMap<String, _CacheEntry> _cache =
      LinkedHashMap<String, _CacheEntry>();

  /// Build a canonical cache key from path + params.
  static String _buildKey(String path, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return path;
    // Sort params for canonical key, exclude cache-busting params
    final filtered = Map.fromEntries(
      params.entries.where((e) => e.key != '_t'),
    );
    if (filtered.isEmpty) return path;
    final sortedKeys = filtered.keys.toList()..sort();
    final paramStr =
        sortedKeys.map((k) => '$k=${filtered[k]}').join('&');
    return '$path?$paramStr';
  }

  /// Get a cached screen JSON, or `null` if not cached or expired.
  Map<String, dynamic>? get(String path, {Map<String, dynamic>? params}) {
    final key = _buildKey(path, params);
    final entry = _cache[key];
    if (entry == null) return null;

    // Check TTL
    if (DateTime.now().difference(entry.timestamp) > ttl) {
      _cache.remove(key);
      return null;
    }

    // Move to end (most recently used)
    _cache.remove(key);
    _cache[key] = entry;

    return entry.json;
  }

  /// Store a screen JSON in the cache.
  void put(String path, Map<String, dynamic> json,
      {Map<String, dynamic>? params}) {
    final key = _buildKey(path, params);

    // Remove existing entry to refresh position
    _cache.remove(key);

    // Evict LRU entries if at capacity
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = _CacheEntry(
      json: Map<String, dynamic>.from(json),
      timestamp: DateTime.now(),
    );
  }

  /// Invalidate all entries whose key starts with the given path.
  /// Called after form submit to ensure stale screens are re-fetched.
  void invalidateForPath(String path) {
    final keysToRemove =
        _cache.keys.where((k) => k.startsWith(path)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  /// Invalidate all cached entries.
  void clear() => _cache.clear();

  /// Number of cached entries (for debugging/testing).
  int get length => _cache.length;

  /// All cached keys (for debugging/testing).
  Iterable<String> get keys => _cache.keys;
}

class _CacheEntry {
  final Map<String, dynamic> json;
  final DateTime timestamp;

  const _CacheEntry({required this.json, required this.timestamp});
}

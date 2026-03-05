import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../domain/tools/tool_models.dart';

/// Screen displaying all Moqui caches with stats and management actions.
///
/// Maps to CacheList.xml in the Moqui Tools UI:
/// - Table of caches with name, type, size, max entries, hit/miss stats
/// - Clear individual cache or clear all caches
/// - Search/filter by cache name
/// - Auto-refresh toggle
class CacheListScreen extends ConsumerStatefulWidget {
  const CacheListScreen({super.key});

  @override
  ConsumerState<CacheListScreen> createState() => _CacheListScreenState();
}

class _CacheListScreenState extends ConsumerState<CacheListScreen> {
  List<CacheInfo> _caches = [];
  List<CacheInfo> _filteredCaches = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String _sortField = 'name';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadCaches();
  }

  Future<void> _loadCaches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = ref.read(moquiApiClientProvider);
      final caches = await apiClient.getCacheList();
      if (mounted) {
        setState(() {
          _caches = caches;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCaches = List.from(_caches);
    } else {
      _filteredCaches = _caches
          .where((c) =>
              c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    _applySort();
  }

  void _applySort() {
    _filteredCaches.sort((a, b) {
      int result;
      switch (_sortField) {
        case 'size':
          result = a.size.compareTo(b.size);
          break;
        case 'hitCount':
          result = a.hitCount.compareTo(b.hitCount);
          break;
        case 'missCount':
          result = a.missCount.compareTo(b.missCount);
          break;
        case 'hitRate':
          result = a.hitRate.compareTo(b.hitRate);
          break;
        case 'type':
          result = a.type.compareTo(b.type);
          break;
        default:
          result = a.name.compareTo(b.name);
      }
      return _sortAscending ? result : -result;
    });
  }

  Future<void> _clearCache(String cacheName) async {
    try {
      final apiClient = ref.read(moquiApiClientProvider);
      await apiClient.clearCache(cacheName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cache "$cacheName" cleared')),
        );
        _loadCaches(); // Refresh after clear
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllCaches() async {
    // Confirm before clearing all
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Caches'),
        content: const Text(
            'Are you sure you want to clear all caches? This may temporarily impact performance.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          TextButton(
            child: const Text('Clear All'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final apiClient = ref.read(moquiApiClientProvider);
      await apiClient.clearAllCaches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All caches cleared')),
        );
        _loadCaches();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear all caches: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
      _applySort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cache Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All Caches',
            onPressed: _clearAllCaches,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadCaches,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(),
          if (_error != null) _buildErrorBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search caches...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilter();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_filteredCaches.length} caches',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return MaterialBanner(
      content: Text(_error!),
      backgroundColor: Colors.red.shade50,
      actions: [
        TextButton(
          onPressed: _loadCaches,
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading && _caches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredCaches.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No caches found' : 'No matching caches',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCaches,
      child: _buildCacheTable(),
    );
  }

  Widget _buildCacheTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(
              label: const Text('Name'),
              onSort: (_, __) => _onSort('name'),
            ),
            DataColumn(
              label: const Text('Type'),
              onSort: (_, __) => _onSort('type'),
            ),
            DataColumn(
              label: const Text('Size'),
              numeric: true,
              onSort: (_, __) => _onSort('size'),
            ),
            DataColumn(
              label: const Text('Hits'),
              numeric: true,
              onSort: (_, __) => _onSort('hitCount'),
            ),
            DataColumn(
              label: const Text('Misses'),
              numeric: true,
              onSort: (_, __) => _onSort('missCount'),
            ),
            DataColumn(
              label: const Text('Hit Rate'),
              numeric: true,
              onSort: (_, __) => _onSort('hitRate'),
            ),
            const DataColumn(label: Text('Actions')),
          ],
          rows: _filteredCaches.map((cache) => _buildRow(cache)).toList(),
        ),
      ),
    );
  }

  int get _sortColumnIndex {
    switch (_sortField) {
      case 'type':
        return 1;
      case 'size':
        return 2;
      case 'hitCount':
        return 3;
      case 'missCount':
        return 4;
      case 'hitRate':
        return 5;
      default:
        return 0;
    }
  }

  DataRow _buildRow(CacheInfo cache) {
    return DataRow(
      cells: [
        DataCell(
          Tooltip(
            message: cache.name,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(cache.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        DataCell(Chip(
          label: Text(
            cache.type,
            style: const TextStyle(fontSize: 11),
          ),
          visualDensity: VisualDensity.compact,
        )),
        DataCell(Text(cache.size.toString())),
        DataCell(Text(cache.hitCount.toString())),
        DataCell(Text(cache.missCount.toString())),
        DataCell(Text('${(cache.hitRate * 100).toStringAsFixed(1)}%')),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Clear ${cache.name}',
            onPressed: () => _clearCache(cache.name),
          ),
        ),
      ],
    );
  }
}

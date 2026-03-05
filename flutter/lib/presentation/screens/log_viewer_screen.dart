import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../domain/tools/tool_models.dart';

/// Log level names for filter UI, ordered by severity.
const _logLevels = ['ALL', 'TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'];

/// Screen for viewing and streaming Moqui server logs.
///
/// Maps to LogViewer.xml in the Moqui Tools UI:
/// - Level filter chips
/// - Logger name search
/// - Message text search
/// - Real-time streaming toggle via WebSocket
/// - Auto-scroll to bottom
/// - Color-coded log level badges
class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  final List<LogEntry> _logEntries = [];
  final List<LogEntry> _filteredEntries = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _isStreaming = false;
  bool _autoScroll = true;
  String? _error;
  final int _maxEntries = 1000;

  // Filters
  String _levelFilter = 'INFO';
  String _loggerSearch = '';
  String _messageSearch = '';

  StreamSubscription? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _loadLogEntries();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  LogFilter get _currentFilter => LogFilter(
        level: _levelFilter == 'ALL' ? null : _levelFilter,
        loggerName: _loggerSearch.isEmpty ? null : _loggerSearch,
        messagePattern: _messageSearch.isEmpty ? null : _messageSearch,
      );

  Future<void> _loadLogEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = ref.read(moquiApiClientProvider);
      final entries = await apiClient.getLogEntries(
        filter: _currentFilter,
        maxRows: _maxEntries,
      );
      if (mounted) {
        setState(() {
          _logEntries.clear();
          _logEntries.addAll(entries);
          _applyLocalFilter();
          _isLoading = false;
        });
        _scrollToBottom();
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

  void _applyLocalFilter() {
    final filter = _currentFilter;
    _filteredEntries.clear();
    _filteredEntries.addAll(
      _logEntries.where((entry) => filter.matches(entry)),
    );
  }

  void _toggleStreaming() {
    if (_isStreaming) {
      _stopStreaming();
    } else {
      _startStreaming();
    }
  }

  void _startStreaming() {
    final logStreamClient = ref.read(logStreamClientProvider);
    logStreamClient.connect(level: _levelFilter);

    _streamSubscription = logStreamClient.logStream.listen(
      (entry) {
        if (!mounted) return;
        setState(() {
          _logEntries.add(entry);
          // Enforce max entries
          while (_logEntries.length > _maxEntries) {
            _logEntries.removeAt(0);
          }
          if (_currentFilter.matches(entry)) {
            _filteredEntries.add(entry);
            while (_filteredEntries.length > _maxEntries) {
              _filteredEntries.removeAt(0);
            }
          }
        });
        if (_autoScroll) _scrollToBottom();
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = 'Stream error: $e';
            _isStreaming = false;
          });
        }
      },
    );

    setState(() => _isStreaming = true);
  }

  void _stopStreaming() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    ref.read(logStreamClientProvider).disconnect();
    setState(() => _isStreaming = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLog() {
    setState(() {
      _logEntries.clear();
      _filteredEntries.clear();
    });
  }

  void _onLevelChanged(String level) {
    setState(() {
      _levelFilter = level;
      _applyLocalFilter();
    });
    // Update server-side filter if streaming
    if (_isStreaming) {
      ref.read(logStreamClientProvider).setLevel(level);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        actions: [
          // Stream toggle
          IconButton(
            icon: Icon(
              _isStreaming ? Icons.pause_circle : Icons.play_circle,
              color: _isStreaming ? Colors.green : null,
            ),
            tooltip: _isStreaming ? 'Stop Streaming' : 'Start Streaming',
            onPressed: _toggleStreaming,
          ),
          // Auto-scroll toggle
          IconButton(
            icon: Icon(
              Icons.vertical_align_bottom,
              color: _autoScroll ? Colors.blue : null,
            ),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Log',
            onPressed: _clearLog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadLogEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          if (_error != null) _buildErrorBanner(),
          _buildStatusBar(),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _logLevels.map((level) {
                final isSelected = _levelFilter == level;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(level, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => _onLevelChanged(level),
                    selectedColor: _levelColor(level).withValues(alpha: 0.3),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Search fields
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Logger name...',
                    prefixIcon: const Icon(Icons.account_tree, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _loggerSearch = value;
                      _applyLocalFilter();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _messageSearch = value;
                      _applyLocalFilter();
                    });
                  },
                ),
              ),
            ],
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
          child: const Text('Dismiss'),
          onPressed: () => setState(() => _error = null),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: _isStreaming
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.transparent,
      child: Row(
        children: [
          if (_isStreaming) ...[
            const Icon(Icons.fiber_manual_record,
                size: 10, color: Colors.green),
            const SizedBox(width: 4),
            const Text('Streaming',
                style: TextStyle(fontSize: 12, color: Colors.green)),
            const SizedBox(width: 12),
          ],
          Text(
            '${_filteredEntries.length} entries'
            '${_filteredEntries.length != _logEntries.length ? ' (${_logEntries.length} total)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          if (_isLoading) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildLogList() {
    if (_isLoading && _filteredEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              _logEntries.isEmpty ? 'No log entries' : 'No matching entries',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (!_isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                  onPressed: _toggleStreaming,
                  child: const Text('Start Streaming'),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _filteredEntries.length,
      itemBuilder: (context, index) {
        return _buildLogRow(_filteredEntries[index]);
      },
    );
  }

  Widget _buildLogRow(LogEntry entry) {
    final levelColor = _levelColor(entry.level);
    final isError = entry.severityIndex >= 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isError ? Colors.red.withValues(alpha: 0.05) : null,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Level badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.level.padRight(5),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: levelColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Timestamp
              Text(
                _formatTimestamp(entry.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(width: 8),
              // Logger name
              Expanded(
                child: Text(
                  entry.loggerName,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.blue.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Message
          SelectableText(
            entry.message,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: isError ? Colors.red.shade800 : null,
            ),
          ),
          // Stack trace if present
          if (entry.throwable != null && entry.throwable!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ExpansionTile(
                title: const Text(
                  'Stack Trace',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 12, bottom: 4),
                children: [
                  SelectableText(
                    entry.throwable!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime ts) {
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${ts.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Get color for a given log level.
Color _levelColor(String level) {
  switch (level.toUpperCase()) {
    case 'FATAL':
      return Colors.purple;
    case 'ERROR':
      return Colors.red;
    case 'WARN':
    case 'WARNING':
      return Colors.orange;
    case 'INFO':
      return Colors.blue;
    case 'DEBUG':
      return Colors.green;
    case 'TRACE':
    case 'ALL':
      return Colors.grey;
    default:
      return Colors.grey;
  }
}

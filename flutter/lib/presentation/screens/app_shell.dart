import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/moqui_icons.dart';
import '../../core/keyboard_shortcuts.dart';
import '../../core/theme.dart';
import '../providers/screen_providers.dart';
import '../../domain/screen/screen_models.dart';
import '../../core/providers.dart';
import '../../data/realtime/notification_client.dart';
import '../../data/auth/auth_provider.dart';

/// Adaptive app shell providing navigation chrome around the dynamic screen content.
///
/// On wide viewports (web/desktop): NavigationRail + AppBar with breadcrumbs.
/// On narrow viewports (mobile): BottomNavigationBar + Drawer for overflow.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentPath;

  const AppShell({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const double _wideBreakpoint = 768;
  int _selectedIndex = 0;
  final List<MoquiNotification> _notifications = [];
  bool _notificationPanelVisible = false;

  @override
  void initState() {
    super.initState();
    // Connect the notification WebSocket once the shell mounts
    Future.microtask(() {
      final client = ref.read(notificationClientProvider);
      client.connect();
    });
  }

  @override
  void dispose() {
    // Disconnect WebSocket when shell unmounts (e.g. logout)
    // Don't dispose — the provider owns the lifecycle
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for incoming notifications
    ref.listen<AsyncValue<MoquiNotification>>(
      notificationStreamProvider,
      (_, next) {
        next.whenData((notification) {
          setState(() {
            _notifications.insert(0, notification);
          });
          if (notification.showAlert && mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  notification.title.isNotEmpty
                      ? notification.title
                      : notification.message,
                ),
                action: notification.link.isNotEmpty
                    ? SnackBarAction(
                        label: 'View',
                        onPressed: () => context.go(notification.link),
                      )
                    : null,
              ),
            );
          }
        });
      },
    );
    // Use the current path (or default 'marble') so menuData includes subscreens.
    // /menuData/fapps alone doesn't return subscreens; /menuData/fapps/<subscreen> does.
    final menuPath = widget.currentPath.isNotEmpty
        ? widget.currentPath.split('/').first
        : 'marble';
    final menuAsync = ref.watch(menuDataProvider(menuPath));
    final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;

    return AppKeyboardShortcuts(
      child: menuAsync.when(
        loading: () => Scaffold(
          body: widget.child,
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Moqui')),
          body: widget.child,
        ),
        data: (menuNodes) {
          if (menuNodes.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Moqui')),
              body: widget.child,
            );
          }
          _syncSelectedIndex(menuNodes);
          return isWide
              ? _buildWideLayout(menuNodes)
              : _buildNarrowLayout(menuNodes);
        },
      ),
    );
  }

  /// Keep selected index in sync with current path.
  void _syncSelectedIndex(List<MenuNode> menuNodes) {
    for (int i = 0; i < menuNodes.length; i++) {
      // currentPath is relative (e.g. 'marble/Order'), node.path is absolute
      // (e.g. '/fapps/marble'). Compare by extracting the node name from the path.
      final nodeName = menuNodes[i].path.split('/').where((s) => s.isNotEmpty).last;
      if (widget.currentPath == nodeName || widget.currentPath.startsWith('$nodeName/')) {
        _selectedIndex = i;
        break;
      }
    }
  }

  // ─── Wide layout: NavigationRail + content ──────────────────────────

  Widget _buildWideLayout(List<MenuNode> menuNodes) {
    return Scaffold(
      appBar: AppBar(
        title: _buildBreadcrumbs(),
        actions: _buildAppBarActions(),
      ),
      body: Stack(
        children: [
          Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex.clamp(0, menuNodes.length - 1),
                onDestinationSelected: (i) => _navigateTo(menuNodes[i]),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.apps, color: Theme.of(context).primaryColor),
                ),
                destinations: menuNodes.map((node) {
                  return NavigationRailDestination(
                    icon: Icon(_mapMenuIcon(node.image)),
                    label: Text(node.title, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.child),
            ],
          ),
          _buildNotificationPanel(),
        ],
      ),
    );
  }

  // ─── Narrow layout: BottomNavBar + Drawer ───────────────────────────

  Widget _buildNarrowLayout(List<MenuNode> menuNodes) {
    // Bottom nav supports 2–5 items; overflow goes to a drawer.
    final showBottom = menuNodes.length <= 5;

    return Scaffold(
      appBar: AppBar(
        title: _buildBreadcrumbs(),
        actions: _buildAppBarActions(),
      ),
      drawer: !showBottom ? _buildDrawer(menuNodes) : null,
      body: Stack(
        children: [
          widget.child,
          _buildNotificationPanel(),
        ],
      ),
      bottomNavigationBar: showBottom && menuNodes.isNotEmpty
          ? NavigationBar(
              selectedIndex: _selectedIndex.clamp(0, menuNodes.length - 1),
              onDestinationSelected: (i) => _navigateTo(menuNodes[i]),
              destinations: menuNodes.map((node) {
                return NavigationDestination(
                  icon: Icon(_mapMenuIcon(node.image)),
                  label: node.title,
                );
              }).toList(),
            )
          : null,
    );
  }

  Widget _buildDrawer(List<MenuNode> menuNodes) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Moqui',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: menuNodes.length,
                itemBuilder: (ctx, i) {
                  final node = menuNodes[i];
                  final selected = i == _selectedIndex;
                  return ListTile(
                    leading: Icon(_mapMenuIcon(node.image)),
                    title: Text(node.title),
                    selected: selected,
                    onTap: () {
                      Navigator.of(context).pop(); // close drawer
                      _navigateTo(node);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared helpers ─────────────────────────────────────────────────

  Widget _buildBreadcrumbs() {
    final segments = widget.currentPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.isEmpty) {
      return const Text('Home');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < segments.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 18),
              ),
            if (i < segments.length - 1)
              Semantics(
                button: true,
                label: 'Navigate to ${_humanize(segments[i])}',
                child: InkWell(
                  onTap: () {
                    final path = segments.sublist(0, i + 1).join('/');
                    context.go('/fapps/$path');
                  },
                  child: Text(
                    _humanize(segments[i]),
                    style: TextStyle(color: context.moquiColors.mutedText, fontSize: 14),
                  ),
                ),
              )
            else
              Text(
                _humanize(segments[i]),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    final unreadCount = _notifications.length;

    return [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Reload screen',
        onPressed: () {
          ref.invalidate(screenProvider(widget.currentPath));
        },
      ),
      Stack(
        children: [
          IconButton(
            icon: Icon(
              _notificationPanelVisible
                  ? Icons.notifications
                  : Icons.notifications_outlined,
            ),
            tooltip: 'Notifications',
            onPressed: () {
              setState(() {
                _notificationPanelVisible = !_notificationPanelVisible;
              });
            },
          ),
          if (unreadCount > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.account_circle_outlined),
        tooltip: 'User account',
        onSelected: (value) {
          if (value == 'logout') {
            // Disconnect notifications before logging out
            ref.read(notificationClientProvider).disconnect();
            context.go('/logout');
          }
        },
        itemBuilder: (_) {
          final authState = ref.read(authProvider);
          return [
            if (authState.username != null)
              PopupMenuItem(
                enabled: false,
                child: Text(
                  authState.username!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (authState.username != null) const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
          ];
        },
      ),
    ];
  }

  /// Build the notification dropdown panel overlay.
  Widget _buildNotificationPanel() {
    if (!_notificationPanelVisible) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      right: 8,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (_notifications.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _notifications.clear();
                          });
                        },
                        child: const Text('Clear all'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close notifications',
                      onPressed: () {
                        setState(() {
                          _notificationPanelVisible = false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_notifications.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none,
                          size: 40, color: context.moquiColors.mutedText),
                      const SizedBox(height: 8),
                      Text('No notifications',
                          style: TextStyle(color: context.moquiColors.mutedText)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final n = _notifications[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          _notificationTypeIcon(n.type),
                          color: _notificationTypeColor(n.type),
                        ),
                        title: Text(
                          n.title.isNotEmpty ? n.title : n.topic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: n.message.isNotEmpty
                            ? Text(n.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: n.link.isNotEmpty
                            ? () {
                                setState(() {
                                  _notificationPanelVisible = false;
                                  _notifications.removeAt(i);
                                });
                                context.go(n.link);
                              }
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _notificationTypeIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle_outlined;
      case 'warning':
        return Icons.warning_outlined;
      case 'danger':
        return Icons.error_outlined;
      default:
        return Icons.info_outlined;
    }
  }

  Color _notificationTypeColor(String type) {
    switch (type) {
      case 'success':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'danger':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  void _navigateTo(MenuNode node) {
    final path = node.path.startsWith('/') ? node.path : '/fapps/${node.path}';
    context.go(path);
  }

  String _humanize(String segment) {
    return segment
        .replaceAll(RegExp(r'[-_]'), ' ')
        .replaceAllMapped(
          RegExp(r'(^| )(\w)'),
          (m) => '${m[1]}${m[2]!.toUpperCase()}',
        );
  }

  IconData _mapMenuIcon(String? image) {
    return MoquiIcons.resolve(image);
  }
}

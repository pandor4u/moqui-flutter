import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

// ─── Custom Intents ────────────────────────────────────────────────────
/// Ctrl+S: submit the currently focused form.
class SubmitFormIntent extends Intent {
  const SubmitFormIntent();
}

/// Escape: close the current dialog or cancel the current operation.
class CancelIntent extends Intent {
  const CancelIntent();
}

/// Ctrl+F: focus the search / filter field.
class SearchFocusIntent extends Intent {
  const SearchFocusIntent();
}

// ─── Shared notifier for broadcasting keyboard intents ─────────────────
/// A [ChangeNotifier] that broadcasts keyboard intents to listeners
/// deep in the widget tree (e.g. form widgets that should submit on Ctrl+S).
class KeyboardIntentNotifier extends ChangeNotifier {
  Intent? _lastIntent;
  int _counter = 0;

  /// The most recent intent that was triggered.
  Intent? get lastIntent => _lastIntent;

  /// A monotonically increasing counter that changes on each broadcast,
  /// so listeners can detect repeat presses of the same intent type.
  int get counter => _counter;

  /// Broadcast an intent to all listeners.
  void broadcast(Intent intent) {
    _lastIntent = intent;
    _counter++;
    notifyListeners();
  }
}

// ─── InheritedWidget to provide the notifier down the tree ─────────────
class KeyboardShortcutScope extends InheritedNotifier<KeyboardIntentNotifier> {
  const KeyboardShortcutScope({
    super.key,
    required KeyboardIntentNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static KeyboardIntentNotifier? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<KeyboardShortcutScope>()
        ?.notifier;
  }

  /// Like [of], but doesn't register as a dependency (won't cause rebuilds).
  static KeyboardIntentNotifier? read(BuildContext context) {
    final widget = context
        .getInheritedWidgetOfExactType<KeyboardShortcutScope>();
    return widget?.notifier;
  }
}

// ─── Platform detection helper ─────────────────────────────────────────
/// Returns true when keyboard shortcuts should be active (web + desktop).
bool get isDesktopOrWeb {
  if (kIsWeb) return true;
  try {
    return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  } catch (_) {
    return false;
  }
}

// ─── Shortcut map ──────────────────────────────────────────────────────
/// The global shortcut map for web/desktop platforms.
/// Uses Meta (⌘) on macOS, Control on others.
Map<ShortcutActivator, Intent> get appShortcuts => <ShortcutActivator, Intent>{
      // Ctrl/Cmd + S → submit form
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          const SubmitFormIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
          const SubmitFormIntent(),

      // Escape → cancel / close dialog
      const SingleActivator(LogicalKeyboardKey.escape): const CancelIntent(),

      // Ctrl/Cmd + F → focus search
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          const SearchFocusIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const SearchFocusIntent(),
    };

// ─── Wrapper widget convenience ────────────────────────────────────────
/// Wraps [child] with `Shortcuts` + `Actions` + `KeyboardShortcutScope`
/// when running on web or desktop. On mobile, returns [child] unchanged.
class AppKeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const AppKeyboardShortcuts({super.key, required this.child});

  @override
  State<AppKeyboardShortcuts> createState() => _AppKeyboardShortcutsState();
}

class _AppKeyboardShortcutsState extends State<AppKeyboardShortcuts> {
  final KeyboardIntentNotifier _notifier = KeyboardIntentNotifier();

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopOrWeb) {
      return KeyboardShortcutScope(
        notifier: _notifier,
        child: widget.child,
      );
    }

    return KeyboardShortcutScope(
      notifier: _notifier,
      child: Shortcuts(
        shortcuts: appShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            SubmitFormIntent: CallbackAction<SubmitFormIntent>(
              onInvoke: (intent) {
                _notifier.broadcast(intent);
                return null;
              },
            ),
            CancelIntent: CallbackAction<CancelIntent>(
              onInvoke: (intent) {
                // Try to pop the current dialog/route first
                final navigator = Navigator.maybeOf(context);
                if (navigator != null && navigator.canPop()) {
                  navigator.pop();
                } else {
                  _notifier.broadcast(intent);
                }
                return null;
              },
            ),
            SearchFocusIntent: CallbackAction<SearchFocusIntent>(
              onInvoke: (intent) {
                _notifier.broadcast(intent);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

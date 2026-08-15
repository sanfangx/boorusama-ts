// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import 'utils.dart';

/// Widget that listens for app lifecycle changes and checkpoints
/// all SQLite databases when the app enters the background.
///
/// This prevents iOS from killing the app with 0xdead10cc (deadlock)
/// when SQLite holds a file lock during suspension.
class DatabaseLifecycleManager extends StatefulWidget {
  const DatabaseLifecycleManager({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<DatabaseLifecycleManager> createState() =>
      _DatabaseLifecycleManagerState();
}

class _DatabaseLifecycleManagerState extends State<DatabaseLifecycleManager> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onStateChange,
    );
  }

  void _onStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Checkpoint all WAL databases to flush pending writes
      // and release file locks before iOS suspends us.
      checkpointAllDatabases();
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

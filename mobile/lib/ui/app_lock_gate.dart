import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../data/services/auth_service.dart';
import '../state/settings_controller.dart';

/// Full-screen lock gate shared by every route.
///
/// Business Rule: the gate only locks when the app is actually backgrounded
/// and no authentication sheet is currently in flight. That avoids the
/// "auth sheet backgrounds the app → lock again" loop.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final SettingsController settings = context.read<SettingsController>();
    if (state == AppLifecycleState.paused) {
      if (!AuthService.isInProgress && !_authenticating) {
        settings.lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (settings.appLocked) {
        _attemptUnlock();
      }
    }
  }

  Future<void> _attemptUnlock() async {
    final SettingsController settings = context.read<SettingsController>();
    if (!settings.appLocked || _authenticating) {
      return;
    }
    setState(() => _authenticating = true);
    final bool ok = await _auth.authenticate('解锁 BalanceApp');
    if (!mounted) {
      return;
    }
    setState(() => _authenticating = false);
    if (ok) {
      settings.unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (settings.appLocked)
          _LockOverlay(
            authenticating: _authenticating,
            onUnlock: _attemptUnlock,
          ),
      ],
    );
  }
}

class _LockOverlay extends StatelessWidget {
  const _LockOverlay({
    required this.authenticating,
    required this.onUnlock,
  });

  final bool authenticating;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Material(
      color: c.pageBg,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.iconTile,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: c.accentOutline),
                ),
                child: Icon(Icons.lock_outline_rounded, color: c.accent, size: 30),
              ),
              const SizedBox(height: 20),
              Text(
                '应用已锁定',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.textTitle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '验证锁屏密码、指纹或人脸识别后继续',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 168,
                height: 44,
                child: ElevatedButton(
                  onPressed: authenticating ? null : onUnlock,
                  child: Text(authenticating ? '正在验证…' : '解锁'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

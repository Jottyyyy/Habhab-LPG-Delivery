import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';

/// Change password. [forced]: signed in with a temporary password, so a new one is required.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});
  final bool forced;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  Future<void> _save() async {
    setState(() => _error = null);
    if (_next.text != _again.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    try {
      await session.changePassword(_current.text, _next.text);
      if (!mounted) return;
      showSnack(context, 'Password changed.');
      if (!widget.forced && Navigator.canPop(context)) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forced ? 'Set your own password' : 'Change password'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced) TextButton(onPressed: session.logout, child: const Text('Sign out', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (widget.forced) ...[
            const NoteBanner(text: 'You signed in with a temporary password. Please choose your own password now.'),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: widget.forced ? 'Temporary password' : 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (at least 6 characters)')),
          const SizedBox(height: 12),
          TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'New password again')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoteBanner(text: _error!, color: C.red, tint: C.redTint, icon: Icons.error_outline),
          ],
          const SizedBox(height: 20),
          BusyButton(label: 'Save new password', onPressed: _save),
        ],
      ),
    );
  }
}

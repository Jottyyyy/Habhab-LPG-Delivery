import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/launch.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';

/// First screen: sign in with mobile number + password, or make an account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  String? _error;

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your mobile number and password.');
      return;
    }
    try {
      await session.login(_phone.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = session.signedOutMessage;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
          children: [
            Center(child: Image.asset('assets/brand/badge.png', width: 190, height: 186)),
            const SizedBox(height: 8),
            const Text('Order gasul, ihahatid sa bahay.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: C.muted)),
            const SizedBox(height: 24),
            if (msg != null && _error == null) ...[NoteBanner(text: msg), const SizedBox(height: 12)],
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0917 123 4567', prefixIcon: Icon(Icons.phone_android)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  tooltip: _hide ? 'Show password' : 'Hide password',
                ),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoteBanner(text: _error!, color: C.red, tint: C.redTint, icon: Icons.error_outline),
            ],
            const SizedBox(height: 18),
            BusyButton(label: 'Sign in', onPressed: _signIn),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => context.push('/register'), child: const Text('New here? Create account')),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => Launch.call(AppConfig.defaultStorePhone),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Forgot password? Call the store'),
            ),
          ],
        ),
      ),
    );
  }
}

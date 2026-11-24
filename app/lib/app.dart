import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/customer/customer_shell.dart';
import 'features/seller/seller_shell.dart';
import 'theme/theme.dart';

/// Top-level screens. Which one opens depends on who is signed in:
/// nobody → sign in; customer → customer app; owner/staff → store app.
final router = GoRouter(
  initialLocation: '/',
  refreshListenable: session,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final u = session.user;
    final public = loc == '/login' || loc == '/register';
    if (u == null) return public ? null : '/login';
    if (u.mustChangePassword) return loc == '/password' ? null : '/password';
    final home = u.isSeller ? '/store' : '/shop';
    if (public || loc == '/' || loc == '/password' || (loc.startsWith('/store') && !u.isSeller) || (loc.startsWith('/shop') && u.isSeller)) {
      return home;
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
    GoRoute(path: '/password', builder: (_, _) => const ChangePasswordScreen(forced: true)),
    GoRoute(path: '/shop', builder: (_, _) => const CustomerShell()),
    GoRoute(path: '/store', builder: (_, _) => const SellerShell()),
  ],
);

class HabhabApp extends StatelessWidget {
  const HabhabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Habhab LPG',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) {
        // Big phone fonts are fine, but not so big that buttons break.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: child!,
        );
      },
    );
  }
}

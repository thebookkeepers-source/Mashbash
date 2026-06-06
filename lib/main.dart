import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/app_models.dart';
import 'providers/app_provider.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/counter/counter_panel.dart';
import 'screens/customer/customer_screens.dart';
import 'screens/manager/manager_panel.dart';
import 'screens/owner/admin_screens.dart';
import 'utils/app_theme.dart';
import 'widgets/mash_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final provider = AppProvider();
  await provider.initialize();
  runApp(ChangeNotifierProvider.value(value: provider, child: const MashbashApp()));
}

class MashbashApp extends StatelessWidget {
  const MashbashApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mashbash',
        debugShowCheckedModeBanner: false,
        theme: buildMashTheme(),
        home: const AppRouter(),
      );
}

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (app.initializing) {
      return const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [MashLogo(), SizedBox(height: 24), CircularProgressIndicator()])));
    }
    final user = app.user;
    if (app.auth.currentUser == null) return const LoginScreen();
    if (user == null) {
      final isGoogleUser = app.auth.currentUser!.providerData.any((profile) => profile.providerId == 'google.com');
      return isGoogleUser ? const OnboardingScreen() : const AccessDeniedScreen();
    }
    if (!user.profileComplete) return const OnboardingScreen();
    return switch (user.role) {
      UserRole.customer => const CustomerShell(),
      UserRole.owner => const StaffPanel(role: UserRole.owner),
      UserRole.manager => const ManagerPanel(),
      UserRole.counter => const CounterPanel(),
    };
  }
}

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MashLogo(),
                  const SizedBox(height: 24),
                  const Icon(Icons.lock_person_rounded, size: 72, color: MashColors.primary),
                  const SizedBox(height: 14),
                  Text('Account access unavailable', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('This staff account is not active. Contact the Mashbash owner for access.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(onPressed: context.read<AppProvider>().logout, icon: const Icon(Icons.logout_rounded), label: const Text('Return to sign in')),
                ],
              ),
            ),
          ),
        ),
      );
}

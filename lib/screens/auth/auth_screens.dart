import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/mash_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _form,
                      child: Column(children: [
                        const MashLogo(),
                        const SizedBox(height: 28),
                        Text('Welcome back', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text('Great food and smooth service, all in one place.', textAlign: TextAlign.center),
                        const SizedBox(height: 22),
                        const ErrorBanner(),
                        OutlinedButton.icon(
                          onPressed: context.watch<AppProvider>().busy ? null : context.read<AppProvider>().googleLogin,
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                          label: const Text('Continue with Google'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')), Expanded(child: Divider())])),
                        TextFormField(controller: _identifier, keyboardType: TextInputType.emailAddress, validator: Validators.emailOrPhone, decoration: const InputDecoration(labelText: 'Customer email or staff mobile', prefixIcon: Icon(Icons.alternate_email_rounded))),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          validator: Validators.password,
                          decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_rounded), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
                        ),
                        const SizedBox(height: 18),
                        AsyncButton(label: 'Sign in', icon: Icons.login_rounded, onPressed: () {
                          if (_form.currentState!.validate()) context.read<AppProvider>().login(_identifier.text, _password.text);
                        }),
                        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('New here? Create Account')),
                        const Text('Staff accounts are created securely by the restaurant owner.', style: TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create Account')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const MashLogo(compact: true),
          const SizedBox(height: 24),
          const ErrorBanner(),
          Form(
            key: _form,
            child: Column(children: [
              TextFormField(controller: _name, validator: (value) => Validators.requiredText(value, 'Full name'), decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_rounded))),
              const SizedBox(height: 12),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, validator: Validators.email, decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.alternate_email_rounded))),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_rounded))),
              const SizedBox(height: 12),
              TextFormField(controller: _address, validator: (value) => Validators.requiredText(value, 'Delivery address'), maxLines: 2, decoration: const InputDecoration(labelText: 'Delivery address', prefixIcon: Icon(Icons.location_on_rounded))),
              const SizedBox(height: 12),
              TextFormField(controller: _password, obscureText: true, validator: Validators.password, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_rounded))),
              const SizedBox(height: 12),
              TextFormField(controller: _confirm, obscureText: true, validator: (value) => value != _password.text ? 'Passwords do not match' : null, decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_reset_rounded))),
              const SizedBox(height: 20),
              AsyncButton(label: 'Create customer account', icon: Icons.person_add_rounded, onPressed: () {
                if (_form.currentState!.validate()) {
                  context.read<AppProvider>().register(email: _email.text, name: _name.text, phone: _phone.text, address: _address.text, password: _password.text);
                  Navigator.pop(context);
                }
              }),
            ]),
          ),
        ]),
      );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<AppProvider>().auth.currentUser?.userMetadata?['name'] as String? ?? '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 32),
            const MashLogo(),
            const SizedBox(height: 28),
            Text('Almost there!', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: MashColors.primary)),
            const Text('Tell us where to send your first Mashbash order.'),
            const SizedBox(height: 24),
            const ErrorBanner(),
            Form(
              key: _form,
              child: Column(children: [
                TextFormField(controller: _name, validator: (value) => Validators.requiredText(value, 'Full name'), decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 12),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
                const SizedBox(height: 12),
                TextFormField(controller: _address, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Delivery address'), decoration: const InputDecoration(labelText: 'Delivery address')),
                const SizedBox(height: 20),
                AsyncButton(label: "Let's Go", icon: Icons.celebration_rounded, onPressed: () {
                  if (_form.currentState!.validate()) context.read<AppProvider>().saveProfile(name: _name.text, phone: _phone.text, address: _address.text);
                }),
              ]),
            ),
          ]),
        ),
      );
}

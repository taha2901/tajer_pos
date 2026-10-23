import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/widgets/widgets.dart';
import '../../app/nav.dart';
import 'register_screen.dart';
import 'server_dialog.dart';
import 'splash_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionCubit>().login(_user.text, _pin.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const BrandMark(size: 56),
                        const Spacer(),
                        IconButton(
                          tooltip: 'عنوان الخادم',
                          icon: const Icon(Icons.dns_outlined),
                          onPressed: () => showServerDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('تسجيل الدخول', style: context.text.headlineMedium),
                    const SizedBox(height: 6),
                    Text('ادخل بحسابك لبدء الوردية', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'اسم المستخدم أو البريد الإلكتروني', prefixIcon: Icon(Icons.person_outline_rounded)),
                      validator: requiredText,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pin,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: requiredText,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: context.palette.dangerBg, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: context.palette.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: TextStyle(color: context.palette.danger))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const Text('دخول'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => context.push(const RegisterScreen()),
                      child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

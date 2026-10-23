import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/widgets/widgets.dart';
import 'splash_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _email.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionCubit>().register(
            name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
            username: _user.text.trim(),
            email: _email.text.trim(),
            pin: _pin.text,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateName(String? v) {
    final req = requiredText(v);
    if (req != null) return req;
    final name = v!.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!RegExp(r'^[\p{L} ]{3,40}$', unicode: true).hasMatch(name)) return 'من 3 إلى 40 حرف (حروف فقط بدون أرقام أو رموز)';
    return null;
  }

  String? _validateUsername(String? v) {
    final req = requiredText(v);
    if (req != null) return req;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{3,19}$').hasMatch(v!.trim())) {
      return 'من 4 إلى 20 حرف، يبدأ بحرف إنجليزي (حروف وأرقام و _ . فقط)';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final req = requiredText(v);
    if (req != null) return req;
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(v!.trim())) return 'البريد الإلكتروني غير صحيح';
    return null;
  }

  String? _validatePin(String? v) {
    final req = requiredText(v);
    if (req != null) return req;
    final missing = [
      if (v!.length < 8) '8 أحرف على الأقل',
      if (!RegExp(r'[A-Z]').hasMatch(v)) 'حرف كبير (A-Z)',
      if (!RegExp(r'[a-z]').hasMatch(v)) 'حرف صغير (a-z)',
      if (!RegExp(r'\d').hasMatch(v)) 'رقم',
      if (!RegExp(r'[^A-Za-z0-9]').hasMatch(v)) 'رمز (مثل @ # !)',
      if (RegExp(r'\s').hasMatch(v)) 'بدون مسافات',
    ];
    return missing.isEmpty ? null : 'كلمة المرور يجب أن تحتوي على: ${missing.join('، ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
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
                    const Align(alignment: AlignmentDirectional.centerStart, child: BrandMark(size: 56)),
                    const SizedBox(height: 24),
                    Text('إنشاء حساب', style: context.text.headlineMedium),
                    const SizedBox(height: 6),
                    Text('أنشئ حسابك للبدء في استخدام التطبيق', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.badge_outlined)),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline_rounded)),
                      validator: _validateUsername,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pin,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        helperText: '8 أحرف على الأقل: حرف كبير وصغير ورقم ورمز',
                        errorMaxLines: 3,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: _validatePin,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور', prefixIcon: Icon(Icons.lock_outline_rounded)),
                      validator: (v) => v != _pin.text ? 'كلمة المرور غير متطابقة' : null,
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
                          : const Text('إنشاء الحساب'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => context.pop(),
                      child: const Text('لديك حساب بالفعل؟ تسجيل الدخول'),
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

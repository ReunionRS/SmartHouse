import 'package:flutter/material.dart';

import '../../models/session_models.dart';
import '../../services/auth_service.dart';

const _orange = Color(0xFFFF8318);

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.auth,
    required this.onRegistrationSuccess,
  });

  final AuthService auth;
  final ValueChanged<AppSession> onRegistrationSuccess;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureRepeat = true;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final session = await widget.auth.register(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onRegistrationSuccess(session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            dark
                ? 'assets/images/backgrounds/smart_home_interior.jpg'
                : 'assets/images/rooms/room_living_light.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.low,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [
                        Color(0xA6070A0E),
                        Color(0xC40A0908),
                        Color(0xFF07090C)
                      ]
                    : const [
                        Color(0x33FFFFFF),
                        Color(0xB8F7F3EE),
                        Color(0xF2F7F4F0)
                      ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _backButton(context),
                      const SizedBox(height: 48),
                      Text(
                        'Создайте аккаунт',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 35,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        const TextSpan(children: [
                          TextSpan(text: 'Начните управлять домом вместе со '),
                          TextSpan(
                            text: 'Smart House',
                            style: TextStyle(color: _orange),
                          ),
                        ]),
                        style: TextStyle(
                          color: foreground.withOpacity(.66),
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 35),
                      _form(),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: 'Уже есть аккаунт? ',
                                style: TextStyle(color: Colors.white54),
                              ),
                              TextSpan(
                                text: 'Войти',
                                style: TextStyle(
                                  color: _orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backButton(BuildContext context) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xE51A1B1F)
            : Colors.white.withOpacity(.68),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      );

  Widget _form() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xED121316)
              : Colors.white.withOpacity(.64),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(.18)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(
                controller: _email,
                hint: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                action: TextInputAction.next,
                validator: (value) => value?.contains('@') == true
                    ? null
                    : 'Введите корректный email',
              ),
              const SizedBox(height: 11),
              _field(
                controller: _password,
                hint: 'Пароль',
                icon: Icons.lock_outline_rounded,
                obscure: _obscurePassword,
                action: TextInputAction.next,
                validator: (value) =>
                    (value?.length ?? 0) >= 6 ? null : 'Минимум 6 символов',
                suffix: _visibilityButton(
                  obscure: _obscurePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 11),
              _field(
                controller: _passwordRepeat,
                hint: 'Повторите пароль',
                icon: Icons.lock_reset_rounded,
                obscure: _obscureRepeat,
                action: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (value) =>
                    value == _password.text ? null : 'Пароли не совпадают',
                suffix: _visibilityButton(
                  obscure: _obscureRepeat,
                  onPressed: () =>
                      setState(() => _obscureRepeat = !_obscureRepeat),
                ),
              ),
              const SizedBox(height: 18),
              _submitButton(),
            ],
          ),
        ),
      );

  Widget _visibilityButton({
    required bool obscure,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        onPressed: onPressed,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: Colors.white54,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? action,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: action,
        obscureText: obscure,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          prefixIcon: Icon(icon, color: _orange),
          suffixIcon: suffix,
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withOpacity(.27)
              : Colors.white.withOpacity(.62),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide(color: Colors.white.withOpacity(.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: const BorderSide(color: _orange, width: 1.3),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: const BorderSide(color: Color(0xFFE65D52)),
          ),
        ),
      );

  Widget _submitButton() => SizedBox(
        width: double.infinity,
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(
              colors: [Color(0xFFF15A00), Color(0xFFFF9C27)],
            ),
            boxShadow: [
              BoxShadow(color: _orange.withOpacity(.32), blurRadius: 22),
            ],
          ),
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Создать аккаунт', style: TextStyle(fontSize: 17)),
          ),
        ),
      );
}

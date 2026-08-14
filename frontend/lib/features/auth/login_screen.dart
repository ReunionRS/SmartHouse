import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session_models.dart';
import '../../services/auth_service.dart';
import 'registration_screen.dart';

const _orange = Color(0xFFFF8318);
const _warmOrange = Color(0xFFFFA43A);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onLoginSuccess,
  });

  final AuthService auth;
  final ValueChanged<AppSession> onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();
  bool remember = true;
  bool submitting = false;
  bool obscure = true;
  bool visible = false;

  @override
  void initState() {
    super.initState();
    widget.auth.getRememberedEmail().then((value) {
      if (!mounted) return;
      setState(() {
        email.text = value;
        remember = value.isNotEmpty;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => visible = true);
    });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void _stub(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$feature будет доступен в ближайшем обновлении'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF24201E),
      ));
  }

  Future<void> submit() async {
    if (!(formKey.currentState?.validate() ?? false) || submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => submitting = true);
    try {
      final session = await widget.auth.login(
        email: email.text.trim(),
        password: password.text,
        rememberEmail: remember,
      );
      if (mounted) widget.onLoginSuccess(session);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                stops: const [0, .25, .58, 1],
                colors: dark
                    ? const [
                        Color(0xA6070A0E),
                        Color(0x8A07090D),
                        Color(0xD40A0908),
                        Color(0xFF07090C),
                      ]
                    : const [
                        Color(0x22FFFFFF),
                        Color(0x55FFFFFF),
                        Color(0xB8F7F3EE),
                        Color(0xF2F7F4F0),
                      ],
              ),
            ),
          ),
          SafeArea(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, .035),
              duration: Duration(milliseconds: reduceMotion ? 1 : 320),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: Duration(milliseconds: reduceMotion ? 1 : 280),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 470,
                          minHeight: constraints.maxHeight - 46,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 28),
                            _welcome(),
                            const SizedBox(height: 34),
                            _authCard(),
                            const SizedBox(height: 22),
                            _registrationStub(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          const TextSpan(children: [
            TextSpan(text: 'Добро пожаловать\nв '),
            TextSpan(
              text: 'Smart House',
              style: TextStyle(color: _orange),
            ),
          ]),
          style: TextStyle(
            color: foreground,
            fontSize: 36,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 15),
        Text(
          'Войдите, чтобы управлять своим домом',
          style: TextStyle(
              color: foreground.withOpacity(.66), fontSize: 17, height: 1.45),
        ),
      ],
    );
  }

  Widget _authCard() => _GlassPanel(
        radius: 27,
        padding: const EdgeInsets.all(11),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              _field(
                controller: email,
                focusNode: emailFocus,
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                action: TextInputAction.next,
                onSubmitted: (_) => passwordFocus.requestFocus(),
                validator: (value) => value?.contains('@') == true
                    ? null
                    : 'Введите корректный email',
              ),
              const SizedBox(height: 10),
              _field(
                controller: password,
                focusNode: passwordFocus,
                label: 'Пароль',
                icon: Icons.lock_outline_rounded,
                obscureText: obscure,
                onSubmitted: (_) => submit(),
                validator: (value) =>
                    (value?.length ?? 0) >= 6 ? null : 'Минимум 6 символов',
                suffix: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 5, 2, 5),
                child: Row(
                  children: [
                    Checkbox(
                      value: remember,
                      onChanged: (value) =>
                          setState(() => remember = value ?? true),
                      activeColor: _orange,
                      checkColor: Colors.black,
                      side: const BorderSide(color: _orange, width: 1.6),
                    ),
                    Text(
                      'Запомнить меня',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _stub('Восстановление пароля'),
                      child: const Text(
                        'Забыли пароль?',
                        style: TextStyle(color: _orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              _loginButton(),
            ],
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? action,
    bool obscureText = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextFormField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
        keyboardType: keyboardType,
        textInputAction: action,
        obscureText: obscureText,
        onFieldSubmitted: onSubmitted,
        onTap: () async {
          focusNode.requestFocus();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (focusNode.hasFocus) {
            await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
          }
        },
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          hintText: label,
          hintStyle:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          prefixIcon: Icon(icon, color: _orange, size: 22),
          suffixIcon: suffix,
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withOpacity(.25)
              : Colors.white.withOpacity(.88),
          contentPadding: const EdgeInsets.symmetric(vertical: 19),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(.15)
                  : Colors.black.withOpacity(.08),
            ),
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

  Widget _loginButton() => SizedBox(
        width: double.infinity,
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(
              colors: [Color(0xFFF15A00), Color(0xFFFF9C27)],
            ),
            border: Border.all(color: _warmOrange.withOpacity(.75)),
            boxShadow: [
              BoxShadow(
                color: _orange.withOpacity(.32),
                blurRadius: 21,
                spreadRadius: 1,
              ),
            ],
          ),
          child: FilledButton(
            onPressed: submitting ? null : submit,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(21)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: submitting
                  ? const SizedBox(
                      key: ValueKey('progress'),
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Войти',
                      key: ValueKey('label'),
                      style: TextStyle(fontSize: 18),
                    ),
            ),
          ),
        ),
      );

  Widget _registrationStub() => _GlassButton(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RegistrationScreen(
              auth: widget.auth,
              onRegistrationSuccess: widget.onLoginSuccess,
            ),
          ),
        ),
        padding: const EdgeInsets.all(18),
        radius: 24,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _orange.withOpacity(.10),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: _orange, size: 27),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Создать аккаунт',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Начните управление своим умным домом',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _orange, size: 29),
          ],
        ),
      );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.onTap,
    required this.child,
    required this.padding,
    this.radius = 19,
  });

  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xE51A1B1F)
            : Colors.white.withOpacity(.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(.14)
                  : Colors.white.withOpacity(.9)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.padding,
    required this.radius,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xED121316)
              : Colors.white.withOpacity(.90),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(.19)
                  : Colors.white.withOpacity(.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.24),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}

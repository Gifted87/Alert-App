import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/auth_providers.dart';
import '../theme/app_theme.dart';

/// TenX branded Firebase sign-in and account creation using password auth.
class TenXSignInScreen extends StatefulWidget {
  const TenXSignInScreen({super.key});

  @override
  State<TenXSignInScreen> createState() => _TenXSignInScreenState();
}

class _TenXSignInScreenState extends State<TenXSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  bool _isSignUp = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _sendingReset = false;
  String? _resetMessage;
  bool _resetFailed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.darkCanvas,
    body: Stack(
      children: [
        Positioned(
          top: -170,
          left: -80,
          right: -80,
          height: 450,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x4D0A84FF), Color(0x1264D2FF), Colors.transparent],
                stops: [0, .55, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Center(child: _BrandMark()),
                    const SizedBox(height: 20),
                    Text(
                      'TenX',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Institutional Trading Terminal',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'Your trading desk, ready.',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in or create your account to continue.',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppTheme.darkGlass,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthFlowBuilder<OAuthController>(
                            provider: TenXAuthProviders.google,
                            builder: (context, state, controller, _) {
                              final busy = state is SigningIn ||
                                  state is CredentialReceived;
                              final error = state is AuthFailed
                                  ? state.exception.toString()
                                  : null;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: 54,
                                    child: FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => controller.signIn(
                                              Theme.of(context).platform,
                                            ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppTheme.darkPrimary,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: AppTheme.darkPrimary.withValues(alpha: .55),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(15),
                                        ),
                                      ),
                                      child: busy
                                          ? const SizedBox.square(
                                              dimension: 21,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const _GoogleGlyph(),
                                                const SizedBox(width: 11),
                                                Text(
                                                  'Continue with Google',
                                                  style: AppTheme.sans(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  if (error != null) ...[
                                    const SizedBox(height: 10),
                                    _InlineMessage(error, isError: true),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 22),
                          const _OrDivider(),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface2,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                _AuthModeButton(
                                  label: 'Sign in',
                                  selected: !_isSignUp,
                                  onTap: () => setState(() {
                                    _isSignUp = false;
                                    _resetMessage = null;
                                  }),
                                ),
                                _AuthModeButton(
                                  label: 'Create account',
                                  selected: _isSignUp,
                                  onTap: () => setState(() {
                                    _isSignUp = true;
                                    _resetMessage = null;
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'EMAIL AND PASSWORD',
                            style: AppTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.darkTextSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AuthFlowBuilder<EmailAuthController>(
                            key: ValueKey(_isSignUp),
                            provider: TenXAuthProviders.emailPassword,
                            action: _isSignUp ? AuthAction.signUp : AuthAction.signIn,
                            builder: (context, state, controller, _) {
                              final busy = state is SigningIn || state is SigningUp || state is CredentialReceived;
                              final error = state is AuthFailed ? _authError(state.exception) : null;
                              return Form(
                                key: _emailFormKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      style: AppTheme.sans(fontSize: 15),
                                      decoration: _fieldDecoration('Email address', Icons.mail_outline_rounded),
                                      validator: (value) {
                                        final email = value?.trim() ?? '';
                                        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                                            ? null
                                            : 'Enter a valid email address';
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_passwordVisible,
                                      textInputAction: _isSignUp ? TextInputAction.next : TextInputAction.done,
                                      autofillHints: _isSignUp
                                          ? const [AutofillHints.newPassword]
                                          : const [AutofillHints.password],
                                      style: AppTheme.sans(fontSize: 15),
                                      decoration: _fieldDecoration('Password', Icons.lock_outline_rounded).copyWith(
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                          icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                        ),
                                      ),
                                      validator: (value) => (value ?? '').length >= 6
                                          ? null
                                          : 'Use at least 6 characters',
                                      onFieldSubmitted: (_) {
                                        if (!_isSignUp) _submitEmailAuth(controller);
                                      },
                                    ),
                                    if (_isSignUp) ...[
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _confirmPasswordController,
                                        obscureText: !_confirmPasswordVisible,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [AutofillHints.newPassword],
                                        style: AppTheme.sans(fontSize: 15),
                                        decoration: _fieldDecoration('Confirm password', Icons.lock_outline_rounded).copyWith(
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                                            icon: Icon(_confirmPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                          ),
                                        ),
                                        validator: (value) => value == _passwordController.text
                                            ? null
                                            : 'Passwords do not match',
                                        onFieldSubmitted: (_) => _submitEmailAuth(controller),
                                      ),
                                    ],
                                    if (!_isSignUp)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _sendingReset ? null : _sendPasswordReset,
                                          child: _sendingReset
                                              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : Text('Forgot password?', style: AppTheme.sans(fontSize: 12, color: AppTheme.darkCyan)),
                                        ),
                                      )
                                    else
                                      const SizedBox(height: 10),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 52,
                                      child: FilledButton(
                                        onPressed: busy ? null : () => _submitEmailAuth(controller),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white.withValues(alpha: .12),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                        ),
                                        child: busy
                                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                            : Text(_isSignUp ? 'Create account' : 'Sign in with email',
                                                style: AppTheme.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                    if (error != null || _resetMessage != null) ...[
                                      const SizedBox(height: 12),
                                      _InlineMessage(
                                        error ?? _resetMessage!,
                                        isError: error != null || _resetFailed,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
      'Your account stays signed in on this device until you sign out.',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.darkTextTertiary,
                        height: 1.45,
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

  void _submitEmailAuth(EmailAuthController controller) {
    if (!_emailFormKey.currentState!.validate()) return;
    controller.setEmailAndPassword(
      _emailController.text.trim(),
      _passwordController.text,
    );
    FocusScope.of(context).unfocus();
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _resetMessage = 'Enter a valid email address first.';
        _resetFailed = true;
      });
      return;
    }
    setState(() {
      _sendingReset = true;
      _resetMessage = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _resetMessage =
            'If an account exists for this email, password reset instructions will be sent.';
        _resetFailed = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _resetMessage = _authError(error);
        _resetFailed = true;
      });
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  String _authError(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-not-found' => 'No account was found for that email.',
        'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists. Sign in instead.',
        'weak-password' => 'Choose a stronger password.',
        'network-request-failed' => 'Check your internet connection and try again.',
        _ => error.message ?? 'Authentication failed. Please try again.',
      };
    }
    return error.toString();
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: AppTheme.darkSurface2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.darkBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.darkPrimary),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.darkBearish),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.darkBearish),
    ),
  );
}

class _AuthModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AuthModeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppTheme.darkSurface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppTheme.darkTextSecondary,
          ),
        ),
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 62,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppTheme.darkPrimary.withValues(alpha: .32),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset(
        'assets/tenx_logo.png',
        width: 62,
        height: 62,
        fit: BoxFit.cover,
      ),
    ),
  );
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) => Container(
    width: 23,
    height: 23,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
    ),
    alignment: Alignment.center,
    child: const _GoogleLogo(),
  );
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">
  <path fill="#4285F4" d="M17.64 9.205c0-.638-.057-1.252-.164-1.841H9v3.481h4.844c-.209 1.125-.843 2.078-1.796 2.716V15.82h2.908c1.702-1.567 2.684-3.875 2.684-6.615Z"/>
  <path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.71H.957v2.332C2.438 15.984 5.482 18 9 18Z"/>
  <path fill="#FBBC05" d="M3.964 10.71A5.43 5.43 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.98 8.98 0 0 0 0 9c0 1.452.348 2.826.957 4.042l3.007-2.332Z"/>
  <path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.346l2.582-2.581C13.463.892 11.426 0 9 0 5.482 0 2.438 2.016.957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58Z"/>
</svg>''';

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _svg,
    width: 19,
    height: 19,
    fit: BoxFit.contain,
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('OR', style: AppTheme.sans(fontSize: 11, color: AppTheme.darkTextTertiary)),
      ),
      Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
    ],
  );
}

class _InlineMessage extends StatelessWidget {
  final String text;
  final bool isError;
  const _InlineMessage(this.text, {this.isError = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (isError ? AppTheme.darkBearish : AppTheme.darkBullish).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: (isError ? AppTheme.darkBearish : AppTheme.darkBullish).withValues(alpha: .24),
      ),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTheme.sans(
        fontSize: 12,
        color: isError ? const Color(0xFFFF8A82) : const Color(0xFF7AE69A),
      ),
    ),
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/settings_service.dart';

class AuthScreen extends StatefulWidget {
  /// When true, a "Skip" button is shown at the top and tapping it pops/dismisses.
  final bool showSkip;

  const AuthScreen({super.key, this.showSkip = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();

  bool _isLogin = true;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }

    bool success;
    String? apiError;

    if (_isLogin) {
      success = await AuthService.instance.login(email, password);
      if (!success) {
        apiError = AuthService.instance.lastError ?? 'Invalid credentials. Please check your email and password.';
      }
    } else {
      final username = _usernameCtrl.text.trim();
      final name     = _nameCtrl.text.trim();

      if (username.isEmpty) {
        setState(() => _error = 'Username is required.');
        return;
      }
      if (name.isEmpty) {
        setState(() => _error = 'Full name is required.');
        return;
      }

      success = await AuthService.instance.signup(
        username,
        email,
        password,
        name: name,
      );
      if (!success) {
        apiError = AuthService.instance.lastError ?? 'Could not create account. The email may already be in use.';
      }
    }

    if (success && mounted) {
      SyncService.instance.syncAll();
      Navigator.pop(context);
    } else if (mounted) {
      setState(() => _error = apiError);
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme  = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg     = theme.scaffoldBackgroundColor;
    final primary = theme.primaryColor;

    return CupertinoPageScaffold(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            if (widget.showSkip)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.outfit(
                        color: isDark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.systemGrey2,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Scrollable form ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // App logo / name
                    Center(
                      child: Text(
                        'Luxa',
                        style: GoogleFonts.outfit(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: primary,
                          letterSpacing: -2.5,
                        ),
                      ).animate().fadeIn(duration: 600.ms).scale(
                            begin: const Offset(0.9, 0.9),
                            end: const Offset(1, 1),
                          ),
                    ),

                    const SizedBox(height: 6),

                    Center(
                      child: Text(
                        _isLogin
                            ? 'Sign in to sync your data'
                            : 'Create an account to get started',
                        style: GoogleFonts.outfit(
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemGrey2,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Mode tabs ─────────────────────────────────────────
                    _ModeTabs(
                      isLogin: _isLogin,
                      onChanged: (_) => _toggleMode(),
                      isDark: isDark,
                      primary: primary,
                    ),

                    const SizedBox(height: 28),

                    // ── Sign-up only fields ───────────────────────────────
                    if (!_isLogin) ...[
                      _buildLabel('Full Name', isDark),
                      const SizedBox(height: 6),
                      AuthTextField(
                        controller: _nameCtrl,
                        placeholder: 'John Doe',
                        icon: FluentIcons.person_circle_24_regular,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('Username', isDark),
                      const SizedBox(height: 6),
                      AuthTextField(
                        controller: _usernameCtrl,
                        placeholder: 'johndoe',
                        icon: FluentIcons.mention_24_regular,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Email ─────────────────────────────────────────────
                    _buildLabel(_isLogin ? 'Email or Username' : 'Email Address', isDark),
                    const SizedBox(height: 6),
                    AuthTextField(
                      controller: _emailCtrl,
                      placeholder: _isLogin ? 'you@example.com' : 'you@example.com',
                      icon: _isLogin ? FluentIcons.person_24_regular : FluentIcons.mail_24_regular,
                      type: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    // ── Password ──────────────────────────────────────────
                    _buildLabel('Password', isDark),
                    const SizedBox(height: 6),
                    AuthTextField(
                      controller: _passwordCtrl,
                      placeholder: '••••••••',
                      icon: FluentIcons.lock_closed_24_regular,
                      obscure: _obscurePassword,
                      suffix: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                        child: Icon(
                          _obscurePassword
                              ? FluentIcons.eye_24_regular
                              : FluentIcons.eye_off_24_regular,
                          size: 18,
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemGrey2,
                        ),
                      ),
                    ),

                    // ── Error ─────────────────────────────────────────────
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              FluentIcons.error_circle_24_regular,
                              color: CupertinoColors.systemRed,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: GoogleFonts.outfit(
                                  color: CupertinoColors.systemRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().shake(hz: 3, offset: const Offset(4, 0)),
                    ],

                    const SizedBox(height: 32),

                    // ── Submit button ─────────────────────────────────────
                    ListenableBuilder(
                      listenable: AuthService.instance,
                      builder: (context, _) {
                        final loading = AuthService.instance.isLoading;
                        return SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: loading ? null : _submit,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: loading
                                    ? primary.withValues(alpha: 0.6)
                                    : primary,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: loading
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: primary.withValues(alpha: 0.35),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                              ),
                              alignment: Alignment.center,
                              child: loading
                                  ? const CupertinoActivityIndicator(
                                      color: CupertinoColors.black,
                                      radius: 12,
                                    )
                                  : Text(
                                      _isLogin ? 'Sign In' : 'Create Account',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w700,
                                        color: CupertinoColors.black,
                                        fontSize: 17,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── Toggle mode link ──────────────────────────────────
                    Center(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _toggleMode,
                        child: Text(
                          _isLogin
                              ? "Don't have an account? Sign Up"
                              : 'Already have an account? Sign In',
                          style: GoogleFonts.outfit(
                            color: primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _buildLabel(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2,
        letterSpacing: 0.3,
      ),
    );
  }

}

class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final bool obscure;
  final TextInputType type;
  final Widget? suffix;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.icon,
    this.obscure = false,
    this.type = TextInputType.text,
    this.suffix,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAmoled = SettingsService.instance.isAmoled;

    final bg = isDark
        ? (isAmoled ? const Color(0xFF121212) : const Color(0xFF1C1C1E))
        : CupertinoColors.white;

    final primary = theme.primaryColor;

    final borderColor = _isFocused
        ? primary
        : (isDark
            ? (isAmoled ? const Color(0xFF1E1E1E) : const Color(0xFF3A3A3C))
            : const Color(0xFFD1D1D6));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: _isFocused ? 1.5 : 1.0,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            widget.icon,
            size: 18,
            color: _isFocused
                ? primary
                : (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CupertinoTextField(
              controller: widget.controller,
              focusNode: _focusNode,
              placeholder: widget.placeholder,
              placeholderStyle: TextStyle(
                color: isDark
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey2,
                fontSize: 15,
              ),
              style: TextStyle(
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                fontSize: 15,
              ),
              decoration: null,
              obscureText: widget.obscure,
              keyboardType: widget.type,
              padding: const EdgeInsets.symmetric(vertical: 16),
              autocorrect: false,
            ),
          ),
          if (widget.suffix != null) widget.suffix!,
        ],
      ),
    );
  }
}

/// Tab switcher between Login / Sign Up
class _ModeTabs extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final Color primary;

  const _ModeTabs({
    required this.isLogin,
    required this.onChanged,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final isAmoled = SettingsService.instance.isAmoled;
    final bg = isDark
        ? (isAmoled ? const Color(0xFF121212) : const Color(0xFF1C1C1E))
        : const Color(0xFFE5E5EA);

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('Sign In', isLogin, () => onChanged(true)),
          _tab('Sign Up', !isLogin, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    final isAmoled = SettingsService.instance.isAmoled;
    final activeBg = isDark
        ? (isAmoled ? const Color(0xFF1C1C1E) : const Color(0xFF2C2C2E))
        : CupertinoColors.white;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active
                ? activeBg
                : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? primary
                  : (isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2),
            ),
          ),
        ),
      ),
    );
  }
}

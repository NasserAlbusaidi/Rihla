import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

/// Login screen with Email/Password flow - Premium Tactical Aesthetic
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'REQUIRED';
    if (!_emailRegex.hasMatch(v.trim())) return 'INVALID EMAIL FORMAT';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'REQUIRED';
    final isSignUp = ref.read(authModeProvider) == AuthMode.signUp;
    if (isSignUp && v.length < 8) return 'MINIMUM 8 CHARACTERS';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final authService = ref.read(authServiceProvider);
    final mode = ref.read(authModeProvider);

    bool success;
    if (mode == AuthMode.signUp) {
      success = await authService.signUp(email, password);
    } else {
      success = await authService.signIn(email, password);
    }

    // Clear password from memory after auth attempt
    _passwordController.clear();

    if (success && mounted) {
      context.go('/home');
    }
  }

  void _toggleMode() {
    final currentMode = ref.read(authModeProvider);
    ref.read(authModeProvider.notifier).state = currentMode == AuthMode.signIn
        ? AuthMode.signUp
        : AuthMode.signIn;
    ref.read(authErrorProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authLoadingProvider);
    final error = ref.watch(authErrorProvider);
    final mode = ref.watch(authModeProvider);
    final isSignUp = mode == AuthMode.signUp;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          _buildHeader(),
                          const Spacer(),
                          _buildFormCard(isLoading, error, isSignUp),
                          const Spacer(flex: 2),
                          _buildFooter(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
        Positioned(
              top: -100,
              right: -100,
              child: _buildBlob(300, AppColors.primary.withValues(alpha: 0.1)),
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .moveY(begin: 0, end: 50, duration: 4.seconds),
        Positioned(
              bottom: -50,
              left: -100,
              child: _buildBlob(
                400,
                const Color(0xFF334155).withValues(alpha: 0.2),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .moveX(begin: 0, end: 70, duration: 6.seconds),
      ],
    );
  }

  Widget _buildBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Iconsax.radar, size: 40, color: Colors.black),
            )
            .animate()
            .fadeIn(duration: 800.ms)
            .scale(delay: 200.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 32),
        const Text(
          'Rihla',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -2,
          ),
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
        const SizedBox(height: 8),
        Text(
          'Plan journeys together',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ).animate().fadeIn(delay: 600.ms),
      ],
    );
  }

  Widget _buildFormCard(bool isLoading, String? error, bool isSignUp) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSignUp ? 'Create your account' : 'Welcome back',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildTextField(
              controller: _emailController,
              label: 'EMAIL',
              hint: 'you@example.com',
              icon: Iconsax.sms,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _passwordController,
              label: 'PASSWORD',
              hint: 'Your password',
              icon: Iconsax.lock,
              obscureText: _obscurePassword,
              validator: _validatePassword,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword ? Iconsax.eye_slash : Iconsax.eye,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            if (!isSignUp) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : () => context.push('/forgot-password'),
                  child: Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.rose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.rose.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  error.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.rose,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 32),
            _buildSubmitButton(isLoading, isSignUp),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isSignUp ? 'Already have an account?' : "Don't have an account?",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                TextButton(
                  onPressed: isLoading ? null : _toggleMode,
                  child: Text(
                    isSignUp ? 'Sign In' : 'Sign Up',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.1),
              fontSize: 14,
            ),
            prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.02),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSubmitButton(bool isLoading, bool isSignUp) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 3,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isSignUp ? 'Create Account' : 'Sign In',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Iconsax.arrow_right_1,
                    size: 20,
                    color: Colors.black,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Rihla v1.0',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ).animate().fadeIn(delay: 1.seconds);
  }
}

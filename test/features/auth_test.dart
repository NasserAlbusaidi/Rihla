import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:rihla/features/auth/providers/auth_provider.dart';
import 'package:rihla/features/auth/screens/login_screen.dart';

// Create a mock for AuthService
class MockAuthService extends Mock implements AuthService {
  @override
  Future<bool> signIn(String? email, String? password) async {
    if (email == 'test@test.com' && password == 'password') {
      return true;
    }
    return false;
  }

  @override
  Future<bool> signUp(String? email, String? password) async {
    if (email == 'new@test.com') {
      return true;
    }
    return false;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> sendPasswordResetEmail(String email) async => true;

  @override
  Future<bool> updatePassword(String newPassword) async => true;

  @override
  Session? get currentSession => null;

  @override
  bool get isAuthenticated => false;
}

void main() {
  group('LoginScreen Tests', () {
    testWidgets('renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Verify title
      expect(find.text('Safar'), findsOneWidget);
      expect(find.text('Plan trips together, effortlessly'), findsOneWidget);

      // Verify form fields
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);

      // Verify buttons
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('validates empty inputs', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Tap sign in without entering data
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      // Check for validation errors
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('validates invalid email', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'invalid-email');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('toggles between Sign In and Sign Up', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Initially Sign In
      expect(find.text('Sign In'), findsWidgets); // Button and toggle text

      // Switch to Sign Up
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      // Check title changed
      expect(find.text('Create Account'), findsWidgets);

      // Switch back
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back'), findsOneWidget);
    });
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'home_page.dart';

class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: authService.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }
        final user = authSnapshot.data;
        if (user == null || user.isAnonymous) {
          if (user?.isAnonymous == true) {
            authService.signOut();
          }
          return const LoginPage();
        }
        return FutureBuilder<void>(
          future: authService.ensureProfile(user),
          builder: (context, ensureSnapshot) {
            if (ensureSnapshot.connectionState != ConnectionState.done) {
              return const _LoadingPage();
            }
            if (ensureSnapshot.hasError) {
              return _AccessErrorPage(error: ensureSnapshot.error.toString());
            }
            return StreamBuilder<AppUserProfile?>(
              stream: authService.watchProfile(user.uid),
              builder: (context, profileSnapshot) {
                if (!profileSnapshot.hasData) return const _LoadingPage();
                final profile = profileSnapshot.data!;
                if (!profile.active || profile.role == 'pending') {
                  return PendingApprovalPage(profile: profile);
                }
                return HomePage(profile: profile);
              },
            );
          },
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;
  bool _saving = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Campo requerido' : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      if (_registering) {
        await auth.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _authMessage(error.code));
    } catch (error) {
      setState(() => _error = 'No se pudo continuar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _authMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Ese correo ya tiene una cuenta.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Correo o contrasena incorrectos.';
      case 'weak-password':
        return 'La contrasena debe tener al menos 6 caracteres.';
      case 'invalid-email':
        return 'El correo no es valido.';
      case 'operation-not-allowed':
        return 'Firebase debe habilitar el acceso por correo y contrasena.';
      default:
        return 'Error de acceso: $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.warehouse_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _registering ? 'Crear cuenta' : 'Iniciar sesion',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    if (_registering) ...[
                      TextFormField(
                        controller: _nameController,
                        validator: _required,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      validator: _required,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      validator: (value) {
                        final requiredError = _required(value);
                        if (requiredError != null) return requiredError;
                        if ((value ?? '').length < 6) {
                          return 'Minimo 6 caracteres';
                        }
                        return null;
                      },
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _saving ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contrasena',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_registering ? Icons.person_add : Icons.login),
                      label: Text(
                        _saving
                            ? 'Procesando...'
                            : _registering
                            ? 'Crear cuenta'
                            : 'Entrar',
                      ),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                      child: Text(
                        _registering
                            ? 'Ya tengo cuenta'
                            : 'Crear una cuenta nueva',
                      ),
                    ),
                    if (!_registering)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                if (_emailController.text.trim().isEmpty) {
                                  setState(
                                    () => _error =
                                        'Escribe tu correo para restablecer.',
                                  );
                                  return;
                                }
                                await context
                                    .read<AuthService>()
                                    .sendPasswordReset(_emailController.text);
                                if (mounted) {
                                  setState(
                                    () => _error =
                                        'Correo de restablecimiento enviado.',
                                  );
                                }
                              },
                        child: const Text('Olvide mi contrasena'),
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

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta pendiente'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: context.read<AuthService>().signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 52),
              const SizedBox(height: 16),
              Text(
                'Esperando aprobacion',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${profile.email}\nUn administrador debe asignarte un rol antes de entrar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AccessErrorPage extends StatelessWidget {
  const _AccessErrorPage({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No se pudo cargar el acceso:\n$error'),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/providers/inventory_provider.dart';
import '../../../../data/providers/user_profile_provider.dart';
import '../../../../services/auth_service.dart';

enum _RegisterMode { company, staff }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Duration _registerCooldown = Duration(seconds: 45);

  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isRegister = false;
  bool _isLoading = false;
  bool _isResendingConfirmation = false;
  bool _isPasswordVisible = false;
  DateTime? _nextRegisterAttemptAt;
  _RegisterMode _registerMode = _RegisterMode.company;
  bool _didLoadRouteEmail = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didLoadRouteEmail) {
      return;
    }

    final routeState = GoRouterState.of(context);
    final email = routeState.uri.queryParameters['email']?.trim() ?? '';
    if (email.isNotEmpty && _emailController.text.trim().isEmpty) {
      _emailController.text = email;
    }

    _didLoadRouteEmail = true;
  }

  @override
  void dispose() {
    _companyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE9F6FA), Color(0xFFF5F8FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x180D1B2A),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.inventory_2_rounded,
                        color: Color(0xFF0C7EA5),
                        size: 34,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? _registerMode == _RegisterMode.company
                                  ? 'Creer un compte entreprise'
                                  : 'Creer un compte employe'
                            : 'Connexion',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRegister
                            ? _registerMode == _RegisterMode.company
                                  ? 'Premiere ouverture: configurez votre compte compagnie.'
                                  : 'Compte manager/seller: confirmez l email recu puis faites-vous activer par un manager.'
                            : 'Connectez-vous a votre espace de gestion.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF617287)),
                      ),
                      if (_isRegister) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F8FC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD8E3ED)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.mark_email_unread_outlined,
                                size: 18,
                                color: Color(0xFF0C7EA5),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Un email de confirmation sera envoye apres l inscription. Vous devrez confirmer votre adresse email avant la premiere connexion.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF41576B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_isRegister) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<_RegisterMode>(
                          value: _registerMode,
                          decoration: const InputDecoration(
                            labelText: 'Type de compte',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: _RegisterMode.company,
                              child: Text('Compte compagnie (proprietaire)'),
                            ),
                            DropdownMenuItem(
                              value: _RegisterMode.staff,
                              child: Text('Compte employe (manager/seller)'),
                            ),
                          ],
                          onChanged: _isLoading
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _registerMode = value;
                                  });
                                },
                        ),
                      ],
                      if (_isRegister &&
                          _registerMode == _RegisterMode.company) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyController,
                          decoration: const InputDecoration(
                            labelText: 'Nom de l entreprise',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: Text(
                          _isLoading
                              ? 'Chargement...'
                              : _isRegister
                              ? _registerMode == _RegisterMode.company
                                    ? 'Creer le compte compagnie'
                                    : 'Creer le compte employe'
                              : 'Se connecter',
                        ),
                      ),
                      if (!_isRegister) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    final encodedEmail =
                                        Uri.encodeQueryComponent(
                                          _emailController.text.trim(),
                                        );
                                    context.go(
                                      '/forgot-password?email=$encodedEmail',
                                    );
                                  },
                            child: const Text('Mot de passe oublie ?'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isRegister = !_isRegister;
                                  if (_isRegister) {
                                    _registerMode = _RegisterMode.company;
                                  }
                                });
                              },
                        child: Text(
                          _isRegister
                              ? 'J ai deja un compte'
                              : 'Creer un nouveau compte',
                        ),
                      ),
                      if (!_isRegister) ...[
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: _isLoading || _isResendingConfirmation
                              ? null
                              : _resendConfirmationEmail,
                          icon: _isResendingConfirmation
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.mark_email_read_outlined),
                          label: Text(
                            _isResendingConfirmation
                                ? 'Envoi...'
                                : 'Renvoyer l email de confirmation',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final company = _companyController.text.trim();
    final isCompanyRegistration =
        _isRegister && _registerMode == _RegisterMode.company;

    if (email.isEmpty ||
        password.isEmpty ||
        (isCompanyRegistration && company.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir les champs requis.')),
      );
      return;
    }

    if (_isRegister &&
        _nextRegisterAttemptAt != null &&
        DateTime.now().isBefore(_nextRegisterAttemptAt!)) {
      final secondsLeft =
          _nextRegisterAttemptAt!.difference(DateTime.now()).inSeconds + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez patienter $secondsLeft s avant une nouvelle inscription.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegister) {
        _nextRegisterAttemptAt = DateTime.now().add(_registerCooldown);
        if (_registerMode == _RegisterMode.company) {
          await _authService.signUpWithCompany(
            email: email,
            password: password,
            companyName: company,
          );
        } else {
          await _authService.signUpStaffAccount(
            email: email,
            password: password,
          );
        }
      } else {
        await _authService.signIn(email: email, password: password);
      }

      if (!mounted) {
        return;
      }

      if (_isRegister && _registerMode == _RegisterMode.staff) {
        setState(() {
          _isRegister = false;
        });
        _goToConfirmEmail(email);
        return;
      }

      await context.read<UserProfileProvider>().initialize(forceRefresh: true);
      await context.read<InventoryProvider>().initialize(forceRefresh: true);
      if (!mounted) {
        return;
      }
      context.go('/');
    } catch (e) {
      if (!mounted) {
        return;
      }
      final rawMessage = e.toString();
      final message = rawMessage.replaceFirst('Exception: ', '');

      if (_isRegister && _isPendingEmailConfirmationMessage(message)) {
        setState(() {
          _isRegister = false;
        });
        _goToConfirmEmail(email);
        return;
      }

      if (!_isRegister && _isEmailNotConfirmedMessage(message)) {
        _goToConfirmEmail(email);
        return;
      }

      if (_isRegister && _isAlreadyRegisteredMessage(message)) {
        setState(() {
          _isRegister = false;
        });
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendConfirmationEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez votre email d abord.')),
      );
      return;
    }

    setState(() => _isResendingConfirmation = true);

    try {
      await _authService.resendSignupConfirmationEmail(email: email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email de confirmation renvoye. Verifiez aussi le dossier spam.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isResendingConfirmation = false);
      }
    }
  }

  void _goToConfirmEmail(String email) {
    final encodedEmail = Uri.encodeQueryComponent(email.trim());
    context.go('/confirm-email?email=$encodedEmail');
  }

  bool _isRateLimitMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('trop de demandes email') ||
        normalized.contains('rate limit');
  }

  bool _isAlreadyRegisteredMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('deja inscrit') ||
        normalized.contains('already registered');
  }

  bool _isPendingEmailConfirmationMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('compte cree') &&
        normalized.contains('confirmez votre email');
  }

  bool _isEmailNotConfirmedMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('email non confirme') ||
        normalized.contains('confirm') && normalized.contains('email');
  }
}

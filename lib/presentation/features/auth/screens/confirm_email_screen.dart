import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../services/auth_service.dart';

class ConfirmEmailScreen extends StatefulWidget {
  final String initialEmail;
  final bool isConfirmed;
  final bool waitingForActivation;

  const ConfirmEmailScreen({
    super.key,
    required this.initialEmail,
    this.isConfirmed = false,
    this.waitingForActivation = false,
  });

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  late final TextEditingController _emailController;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resendEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saisissez votre email.')));
      return;
    }

    setState(() => _isSending = true);

    try {
      await AuthService().resendSignupConfirmationEmail(email: email);
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
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isConfirmed
        ? 'Email confirme'
        : 'Confirmez votre email';
    final description = widget.isConfirmed
        ? widget.waitingForActivation
              ? 'Votre adresse email est bien confirmee. Votre compte attend maintenant l activation par votre manager avant la premiere connexion.'
              : 'Votre adresse email est bien confirmee. Vous pouvez maintenant continuer dans l application.'
        : 'Un message de confirmation a ete envoye a votre adresse email. Ouvrez ce message, cliquez sur le lien de validation, puis revenez vous connecter dans l application.';
    final steps = widget.isConfirmed
        ? <String>[
            if (widget.waitingForActivation)
              '1. Attendez que votre manager active votre compte dans Utilisateurs.'
            else
              '1. Votre email est valide.',
            if (widget.waitingForActivation)
              '2. Quand l activation est faite, connectez-vous avec vos identifiants.'
            else
              '2. Revenez dans l application pour continuer.',
          ]
        : const <String>[
            '1. Ouvrez Gmail ou votre boite mail.',
            '2. Recherchez le message de confirmation Supabase.',
            '3. Cliquez sur le lien pour valider le compte.',
            '4. Revenez ensuite sur l ecran de connexion.',
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0x150C7EA5),
                        child: Icon(
                          Icons.mark_email_unread_outlined,
                          size: 30,
                          color: Color(0xFF0C7EA5),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF617287), height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FBFD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD8E3ED)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Etapes',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            for (
                              var index = 0;
                              index < steps.length;
                              index++
                            ) ...[
                              Text(steps[index]),
                              if (index < steps.length - 1)
                                const SizedBox(height: 4),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!widget.isConfirmed)
                        FilledButton.icon(
                          onPressed: _isSending ? null : _resendEmail,
                          icon: _isSending
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.mark_email_read_outlined),
                          label: Text(
                            _isSending
                                ? 'Envoi...'
                                : 'Renvoyer l email de confirmation',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      if (widget.isConfirmed)
                        FilledButton.icon(
                          onPressed: () => context.go('/login'),
                          icon: const Icon(Icons.login),
                          label: Text(
                            widget.waitingForActivation
                                ? 'Retour a la connexion'
                                : 'Continuer',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour a la connexion'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
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
}

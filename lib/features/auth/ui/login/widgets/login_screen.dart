import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../view_models/login_state.dart';
import '../view_models/login_view_model.dart';
import 'auth_failure_message.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.viewModel});

  static const defaultHomeserver = 'matrix.org';

  final LoginViewModel viewModel;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _homeserverField = GlobalKey<FormFieldState<String>>();
  final _homeserverController = TextEditingController(
    text: LoginScreen.defaultHomeserver,
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _browserRequested = false;

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _browserRequested = false);
    widget.viewModel.login(
      homeserver: _homeserverController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );
  }

  void _submitBrowser() {
    if (!_homeserverField.currentState!.validate()) return;
    setState(() => _browserRequested = true);
    widget.viewModel.loginWithBrowser(homeserver: _homeserverController.text);
  }

  static String? _required(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty) ? 'Informe $fieldName.' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<LoginViewModel, LoginState>(
      bloc: widget.viewModel,
      builder: (context, state) {
        final submitting = state.status == LoginStatus.running;
        final failureType = state.failureType;
        final awaitingBrowser = state.status == LoginStatus.awaitingBrowser;

        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Entrar no Matrix',
                              style: theme.textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            if (awaitingBrowser)
                              _BrowserWaitingPanel(
                                onReopen: widget.viewModel.reopenBrowser,
                                onCancel: widget.viewModel.cancelBrowserLogin,
                              )
                            else ...[
                              KeyedSubtree(
                                key: const Key('login_homeserver'),
                                child: TextFormField(
                                  key: _homeserverField,
                                  controller: _homeserverController,
                                  enabled: !submitting,
                                  decoration: const InputDecoration(
                                    labelText: 'Servidor',
                                    prefixIcon: Icon(Icons.dns_outlined),
                                  ),
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.url],
                                  validator: (value) =>
                                      _required(value, 'o servidor'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const Key('login_username'),
                                controller: _usernameController,
                                enabled: !submitting,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'Usuário',
                                  hintText: 'alice ou @alice:matrix.org',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                validator: (value) =>
                                    _required(value, 'o usuário'),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const Key('login_password'),
                                controller: _passwordController,
                                enabled: !submitting,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Mostrar senha'
                                        : 'Ocultar senha',
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                validator: (value) =>
                                    (value == null || value.isEmpty)
                                    ? 'Informe a senha.'
                                    : null,
                              ),
                              if (state.status == LoginStatus.failure &&
                                  failureType != null) ...[
                                const SizedBox(height: 16),
                                _ErrorBanner(message: failureType.message),
                              ],
                              const SizedBox(height: 24),
                              FilledButton(
                                key: const Key('login_submit'),
                                onPressed: submitting ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: submitting && !_browserRequested
                                    ? const _ButtonSpinner()
                                    : const Text('Entrar'),
                              ),
                              const SizedBox(height: 16),
                              const _OrDivider(),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                key: const Key('login_browser'),
                                onPressed: submitting ? null : _submitBrowser,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                icon: submitting && _browserRequested
                                    ? const _ButtonSpinner()
                                    : const Icon(Icons.open_in_browser),
                                label: const Text('Entrar pelo navegador'),
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
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou')),
      Expanded(child: Divider()),
    ],
  );
}

class _BrowserWaitingPanel extends StatelessWidget {
  const _BrowserWaitingPanel({required this.onReopen, required this.onCancel});

  final VoidCallback onReopen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        const Text(
          'Continue o login no navegador que foi aberto.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('login_browser_reopen'),
          onPressed: onReopen,
          child: const Text('Abrir novamente'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('login_browser_cancel'),
          onPressed: onCancel,
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

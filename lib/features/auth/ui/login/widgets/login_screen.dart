import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../view_models/login_state.dart';
import '../view_models/login_view_model.dart';
import 'auth_failure_message.dart';
import 'login_showcase.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.viewModel});

  static const defaultHomeserver = 'matrix.org';

  // Abaixo disso o painel da esquerda some e o formulário ocupa a janela.
  static const showcaseMinWidth = 880.0;

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
  bool _browserRequested = false;
  bool _keepSignedIn = true;

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
      keepSignedIn: _keepSignedIn,
    );
  }

  void _submitBrowser() {
    if (!_homeserverField.currentState!.validate()) return;
    setState(() => _browserRequested = true);
    widget.viewModel.loginWithBrowser(
      homeserver: _homeserverController.text,
      keepSignedIn: _keepSignedIn,
    );
  }

  static String? _required(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty) ? 'Informe $fieldName.' : null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final form = _FormPane(
            child: BlocBuilder<LoginViewModel, LoginState>(
              bloc: widget.viewModel,
              builder: (context, state) {
                final submitting = state.status == LoginStatus.running;
                final failureType = state.failureType;

                return Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LoginHeader(),
                        const SizedBox(height: 28),
                        if (state.status == LoginStatus.awaitingBrowser)
                          _BrowserWaitingPanel(
                            onReopen: widget.viewModel.reopenBrowser,
                            onCancel: widget.viewModel.cancelBrowserLogin,
                          )
                        else ...[
                          _HomeserverField(
                            fieldKey: _homeserverField,
                            controller: _homeserverController,
                            enabled: !submitting,
                            validator: (value) =>
                                _required(value, 'o servidor'),
                          ),
                          const SizedBox(height: 20),
                          _OutlinedAction(
                            key: const Key('login_browser'),
                            onPressed: submitting ? null : _submitBrowser,
                            loading: submitting && _browserRequested,
                            label: 'Continuar no navegador',
                          ),
                          const SizedBox(height: 20),
                          const _OrDivider(),
                          const SizedBox(height: 20),
                          ValueListenableBuilder(
                            valueListenable: _homeserverController,
                            builder: (context, homeserver, _) => TextFormField(
                              key: const Key('login_username'),
                              controller: _usernameController,
                              enabled: !submitting,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: '@voce:${homeserver.text.trim()}',
                              ),
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              validator: (value) =>
                                  _required(value, 'o usuário'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PasswordField(
                            controller: _passwordController,
                            enabled: !submitting,
                            onSubmitted: _submit,
                          ),
                          const SizedBox(height: 14),
                          _KeepSignedInCheckbox(
                            value: _keepSignedIn,
                            enabled: !submitting,
                            onChanged: (value) =>
                                setState(() => _keepSignedIn = value),
                          ),
                          if (state.status == LoginStatus.failure &&
                              failureType != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(message: failureType.message),
                          ],
                          const SizedBox(height: 18),
                          _PrimaryAction(
                            key: const Key('login_submit'),
                            onPressed: submitting ? null : _submit,
                            loading: submitting && !_browserRequested,
                            label: 'Entrar',
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
          if (constraints.maxWidth < LoginScreen.showcaseMinWidth) return form;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 52, child: LoginShowcase()),
              VerticalDivider(width: 1, thickness: 1, color: colors.border),
              Expanded(flex: 48, child: form),
            ],
          );
        },
      ),
    );
  }
}

class _FormPane extends StatelessWidget {
  const _FormPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.borderStrong),
    );
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            color: colors.textPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.conversationBackground,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          hintStyle: TextStyle(fontSize: 16, color: colors.textMuted),
          border: border,
          enabledBorder: border,
          disabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.accent),
          ),
          errorBorder: border.copyWith(
            borderSide: BorderSide(color: colors.danger),
          ),
          focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: colors.danger),
          ),
          errorStyle: TextStyle(color: colors.dangerText),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Entrar',
          style: TextStyle(
            fontFamily: AppFonts.serif,
            fontSize: 42,
            height: 1.1,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Bem-vindo de volta.',
          style: TextStyle(fontSize: 16, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _HomeserverField extends StatelessWidget {
  const _HomeserverField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.validator,
  });

  final GlobalKey<FormFieldState<String>> fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Servidor',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: const Key('login_homeserver'),
          child: TextFormField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              prefixText: 'https://  ',
              prefixStyle: TextStyle(fontSize: 16, color: colors.textMuted),
              suffixIcon: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) =>
                    value.text.trim() == LoginScreen.defaultHomeserver
                    ? const _DefaultBadge()
                    : const SizedBox.shrink(),
              ),
              suffixIconConstraints: const BoxConstraints(),
            ),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.url],
            validator: validator,
          ),
        ),
      ],
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Padrão',
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;

  final bool enabled;

  final VoidCallback onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const Key('login_password'),
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: _obscure,
    decoration: InputDecoration(
      hintText: 'Senha',
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: IconButton(
          tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
          color: context.colors.textMuted,
          iconSize: 20,
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    ),
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.password],
    onFieldSubmitted: (_) => widget.onSubmitted(),
    validator: (value) =>
        (value == null || value.isEmpty) ? 'Informe a senha.' : null,
  );
}

class _KeepSignedInCheckbox extends StatelessWidget {
  const _KeepSignedInCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: const Key('login_keep_signed_in'),
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CheckBox(checked: value),
              const SizedBox(width: 10),
              Text(
                'Manter conectado',
                style: TextStyle(fontSize: 15, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? colors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? colors.accent : colors.borderStrong,
          width: 1.5,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 14, color: colors.onAccent)
          : null,
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.label,
  });

  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: loading ? const _ButtonSpinner() : Text(label),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.label,
  });

  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        disabledBackgroundColor: colors.accent.withValues(alpha: 0.5),
        disabledForegroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: loading ? const _ButtonSpinner() : Text(label),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.dangerSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: colors.dangerText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: colors.dangerText)),
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: colors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'ou com usuário',
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
        ),
        Expanded(child: Divider(color: colors.border)),
      ],
    );
  }
}

class _BrowserWaitingPanel extends StatelessWidget {
  const _BrowserWaitingPanel({required this.onReopen, required this.onCancel});

  final VoidCallback onReopen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(
          'Continue o login no navegador que foi aberto.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: colors.textSecondary),
        ),
        const SizedBox(height: 24),
        _OutlinedAction(
          key: const Key('login_browser_reopen'),
          onPressed: onReopen,
          loading: false,
          label: 'Abrir novamente',
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

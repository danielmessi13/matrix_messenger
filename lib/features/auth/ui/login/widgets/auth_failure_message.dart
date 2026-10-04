import '../../../domain/models/auth_failure.dart';

extension AuthFailureMessage on AuthFailureType {
  String get message => switch (this) {
    AuthFailureType.invalidHomeserver =>
      'Endereço de servidor inválido. Use, por exemplo, matrix.org.',
    AuthFailureType.homeserverUnreachable => 'Não foi possível conectar ao servidor. Verifique o endereço e sua conexão.',
    AuthFailureType.invalidCredentials => 'Usuário ou senha incorretos.',
    AuthFailureType.userDeactivated => 'Esta conta foi desativada.',
    AuthFailureType.rateLimited =>
      'Muitas tentativas. Aguarde alguns instantes e tente novamente.',
    AuthFailureType.storage =>
      'Não foi possível preparar o armazenamento local do app.',
    AuthFailureType.oidcNotSupported =>
      'Este servidor não oferece login pelo navegador. Use usuário e senha.',
    AuthFailureType.authorizationDenied =>
      'O acesso não foi autorizado no navegador.',
    AuthFailureType.timedOut =>
      'O login no navegador demorou demais. Tente novamente.',
    AuthFailureType.cancelled => 'Login cancelado.',
    AuthFailureType.browserUnavailable => 'Não foi possível abrir o navegador.',
    AuthFailureType.sessionRevoked =>
      'Sua sessão foi encerrada. Entre novamente.',
    AuthFailureType.unknown => 'Não foi possível entrar. Tente novamente.',
  };
}

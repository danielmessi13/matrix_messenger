# Matrix Messenger

Cliente de mensageria desktop para macOS, Windows e Linux, feito em Flutter, que conversa com qualquer homeserver [Matrix](https://matrix.org). Toda a comunicação com o Matrix é feita em Rust com o [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk) e exposta ao Dart pelo [Flutter Rust Bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## TL;DR

- **O que é:** cliente Matrix desktop. Flutter na interface (MVVM com Cubit), Rust com o Matrix Rust SDK na comunicação, ligados pelo Flutter Rust Bridge.
- **Para avaliar:** `docker compose -f docker/docker-compose.yml up -d`, [baixe o app](#baixar-o-app) e entre em `http://localhost:8008` com `avaliador` / `avaliador123`.
- **O que tem:** login com senha ou navegador, sessão salva no cofre do sistema, lista de salas em tempo real, conversa com markdown, imagens, respostas, threads e reações, notificações do sistema, criação e gerenciamento de salas, backup e recuperação do histórico cifrado.
- **Onde ler mais:** [decisões técnicas](docs/decisoes-tecnicas.md) e [limitações](docs/limitacoes.md).

## Sumário

- [Como avaliar rapidamente](#como-avaliar-rapidamente)
- [Baixar o app](#baixar-o-app)
- [O que foi feito](#o-que-foi-feito)
- [Pré-requisitos](#pré-requisitos)
- [Configuração e execução](#configuração-e-execução)
- [Homeserver local (Synapse)](#homeserver-local-synapse)
- [Arquitetura](#arquitetura)
- [Principais decisões técnicas](#principais-decisões-técnicas)
- [Testes](#testes)
- [CI e release](#ci-e-release)
- [Limitações](#limitações)

## Como avaliar rapidamente

O repositório traz um homeserver Synapse em Docker, já com usuários, salas e mensagens, para avaliar sem criar conta em lugar nenhum. O app pode ser baixado pronto, sem instalar Flutter nem Rust.

1. Suba o servidor. O seed roda sozinho assim que o Synapse fica pronto:

   ```bash
   docker compose -f docker/docker-compose.yml up -d
   ```

2. Baixe e abra o app para o seu sistema, como explicado em [Baixar o app](#baixar-o-app):

   | Sistema | Download |
   | --- | --- |
   | macOS | [matrix_messenger-macos.dmg](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-macos.dmg) |
   | Windows (x64) | [matrix_messenger-windows-x64.zip](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-windows-x64.zip) |
   | Linux (x64) | [matrix_messenger-linux-x64.tar.gz](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-linux-x64.tar.gz) |

3. Entre com o servidor `http://localhost:8008`, usuário `avaliador` e senha `avaliador123`.

O `avaliador` já tem conversas diretas e salas em grupo, com mensagens não lidas e menções. Para conversar em tempo real, entre com outro usuário (`daniel`, `maria` ou `joao`, com senha `<usuário>123`) num segundo app ou no [Element Web](https://app.element.io), apontando para o mesmo servidor.

Prefere compilar? Veja [Configuração e execução](#configuração-e-execução). Para usar uma conta real, por exemplo no `matrix.org`, veja [Conta no matrix.org](#conta-no-matrixorg).

## Baixar o app

Cada versão publicada na [página de releases](https://github.com/danielmessi13/matrix_messenger/releases) traz um pacote por sistema, gerado pelo CI a partir da tag. Os links abaixo sempre apontam para a versão mais recente.

Os pacotes não são assinados com certificado pago, então cada sistema avisa na primeira abertura. Os passos para liberar estão em cada item.

### macOS

1. Baixe o [matrix_messenger-macos.dmg](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-macos.dmg), abra e arraste o app para **Aplicativos**.
2. Remova a marca de quarentena, porque o app é assinado ad-hoc e não é notarizado:

   ```bash
   xattr -dr com.apple.quarantine /Applications/matrix_messenger.app
   ```

   Outra opção é tentar abrir uma vez e liberar em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**.

3. Abra o **matrix_messenger** pelos Aplicativos.

O macOS pode pedir a senha do Keychain na primeira vez que o app salva a sessão. Escolha **Sempre permitir**. Depois do login, ele também pede permissão para mostrar notificações.

### Windows

1. Baixe o [matrix_messenger-windows-x64.zip](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-windows-x64.zip).
2. Extraia a pasta inteira, porque o `.exe` depende das DLLs e da pasta `data` que vêm junto.
3. Abra o `matrix_messenger.exe`. Se o SmartScreen avisar, clique em **Mais informações → Executar assim mesmo**.

### Linux

1. Baixe o [matrix_messenger-linux-x64.tar.gz](https://github.com/danielmessi13/matrix_messenger/releases/latest/download/matrix_messenger-linux-x64.tar.gz) e extraia:

   ```bash
   tar -xzf matrix_messenger-linux-x64.tar.gz
   ```

2. Rode o app:

   ```bash
   ./bundle/matrix_messenger
   ```

O sistema precisa ter o GTK 3 (`libgtk-3-0`), presente na maioria das distribuições com interface gráfica. Para a sessão ficar salva entre aberturas é preciso um serviço Secret Service, que GNOME e KDE Plasma já trazem.

## O que foi feito

### Escopo do desafio

| Escopo esperado | Como ficou |
| --- | --- |
| Autenticação em um homeserver Matrix | Login com usuário e senha ou pelo navegador (OIDC), com erros tipados vindos do Rust e mensagens específicas para cada um |
| Listagem e seleção de salas | Lista em tempo real pelo sliding sync, com filtros (caixa de entrada, menções, threads, salas e conversas diretas), contagem de não lidas e prévia da última mensagem |
| Visualização e envio de mensagens | Timeline com paginação do histórico, envio em markdown, imagens, respostas, threads e reações |
| Atualização das conversas | Sync contínuo em segundo plano, notificações do sistema para mensagens e convites, indicador de digitação, confirmação de leitura, modo offline com os dados salvos |
| Encerramento e restauração da sessão | Sessão guardada no cofre do sistema operacional (Keychain, Credential Manager ou Secret Service) e restaurada sem rede; logout encerra o dispositivo no servidor; aviso quando a sessão é revogada em outro lugar |

### Além do escopo

- Notificações do sistema para mensagens e convites, seguindo as regras de notificação da conta; o clique abre a sala.
- Busca de mensagens no servidor, com atalho Cmd/Ctrl+K.
- Criar sala (nome, tópico, visibilidade, convites), entrar por link ou ID e copiar o link de salas públicas.
- Aceitar e recusar convites; convidar pessoas e sair de uma sala pelo cabeçalho da conversa.
- Threads recentes no filtro Threads, com a thread aberta num painel ao lado da conversa.
- Recuperação do histórico cifrado com a chave de recuperação da conta e, em conta sem backup, configuração do backup com uma chave nova gerada pelo app.
- Lista de salas e filtros recolhíveis, com animação.
- Homeserver Synapse local em Docker, com usuários, salas e mensagens de exemplo.
- Builds de macOS, Windows e Linux gerados pelo CI ao criar uma tag.

## Pré-requisitos

Versões usadas no desenvolvimento, em todos os sistemas:

| Ferramenta | Versão validada | Para quê |
| --- | --- | --- |
| Flutter | 3.47.4 (stable) | App e UI |
| Rust (`rustc` / `cargo`) | 1.99.0 | Comunicação com o Matrix |
| flutter_rust_bridge_codegen | 2.13.0 | Gera o código de ligação Dart ↔ Rust (só para quem alterar a API do Rust) |
| Docker com Compose | Compose v2 ou mais novo | Homeserver local (opcional) |

O app foi usado no dia a dia só no macOS. Linux e Windows são compilados pelo CI de release (veja [CI e release](#ci-e-release)), com os mesmos passos descritos abaixo, mas não foram testados à mão.

## Configuração e execução

Para compilar a partir do código, em vez de [baixar o app](#baixar-o-app). Em todos os sistemas o Rust é compilado automaticamente pelo `flutter run` e pelo `flutter build`, pelo plugin em `rust_builder/`. Não é preciso rodar `cargo build` à mão. A primeira execução compila o Matrix SDK do zero e leva alguns minutos; as seguintes são incrementais.

### macOS

Validado no macOS 26 com Xcode 26.4.1.

1. Instale o Xcode com as Command Line Tools e o [CocoaPods](https://cocoapods.org).
2. Instale o [Flutter](https://docs.flutter.dev/get-started/install/macos/desktop).
3. Instale o Rust:

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

4. Baixe as dependências e rode:

   ```bash
   flutter pub get
   ```

   ```bash
   flutter run -d macos
   ```

Para gerar o app de release, use `flutter build macos --release`; o resultado fica em `build/macos/Build/Products/Release/matrix_messenger.app`.

### Linux

Os comandos abaixo são para Ubuntu e Debian, os mesmos que o CI usa no `ubuntu-latest`.

1. Instale as dependências de desktop do Flutter:

   ```bash
   sudo apt-get update && sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
   ```

2. Instale o [Flutter](https://docs.flutter.dev/get-started/install/linux/desktop).
3. Instale o Rust:

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

4. Baixe as dependências e rode:

   ```bash
   flutter pub get
   ```

   ```bash
   flutter run -d linux
   ```

Para gerar o app de release, use `flutter build linux --release`; o executável fica em `build/linux/x64/release/bundle/matrix_messenger`.

Para a sessão ficar salva entre aberturas, o sistema precisa de um serviço Secret Service. GNOME (gnome-keyring) e KDE Plasma (KWallet) já trazem um. Sem ele, o login funciona, mas o app avisa que será preciso entrar de novo na próxima abertura. Para os emojis das reações aparecerem coloridos, instale uma fonte de emoji, como a `fonts-noto-color-emoji`.

### Windows

1. Instale o [Visual Studio 2022](https://visualstudio.microsoft.com/pt-br/vs/) com a carga de trabalho **Desenvolvimento para desktop com C++**. Ela traz o compilador MSVC que o Flutter e o Rust usam.
2. Instale o [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop).
3. Instale o Rust baixando e executando o `rustup-init.exe` de [rustup.rs](https://rustup.rs), com as opções padrão.
4. Num terminal novo (PowerShell), baixe as dependências e rode:

   ```powershell
   flutter pub get
   ```

   ```powershell
   flutter run -d windows
   ```

Para gerar o app de release, use `flutter build windows --release`; o executável fica em `build\windows\x64\runner\Release\matrix_messenger.exe`.

A sessão fica salva no Gerenciador de Credenciais do Windows.

### Conferir o ambiente

Em qualquer sistema, `flutter doctor` mostra se falta alguma dependência para a plataforma desktop, e `rustc --version` confirma o Rust no `PATH`.

### Gerar o código da ponte

Só é necessário ao criar ou alterar uma função pública em `rust/src/api/`:

```bash
cargo install flutter_rust_bridge_codegen@2.13.0
```

```bash
flutter_rust_bridge_codegen generate
```

O comando atualiza `lib/src/rust/` e `rust/src/frb_generated.rs`. A versão do gerador precisa ser a mesma do pacote `flutter_rust_bridge` no `pubspec.yaml` e no `Cargo.toml`, por isso ela está fixada.

## Homeserver local (Synapse)

A pasta `docker/` tem um [Synapse](https://github.com/element-hq/synapse) com dados de exemplo. A configuração serve só para desenvolvimento: registro aberto, segredos fixos e limites de taxa folgados.

```bash
docker compose -f docker/docker-compose.yml up -d
```

O comando sobe o Synapse e, assim que ele fica pronto, aplica o seed. Isso leva alguns segundos, e `docker compose -f docker/docker-compose.yml logs seed` mostra o andamento. Nas próximas vezes o seed percebe que já foi aplicado e não faz nada.

| Usuário | Senha |
| --- | --- |
| `avaliador` | `avaliador123` |
| `daniel` | `daniel123` |
| `maria` | `maria123` |
| `joao` | `joao123` |

O login pelo navegador (OIDC) não funciona nesse servidor, porque o Synapse sozinho não tem um provedor OIDC.

### Dados de exemplo

Usuários, salas e mensagens ficam em [`docker/seed/seed.json`](docker/seed/seed.json). Depois de mudar o arquivo, recrie o banco do zero:

```bash
docker compose -f docker/docker-compose.yml down -v
```

```bash
docker compose -f docker/docker-compose.yml up -d
```

Para criar mais usuários (adicione `--admin` como terceiro argumento para criar um administrador):

```bash
./docker/create-user.sh alice alice123
```

No Windows, sem um shell compatível com `sh` (como o Git Bash), rode o comando direto:

```powershell
docker compose -f docker/docker-compose.yml exec synapse register_new_matrix_user -c /config/homeserver.yaml -u alice -p alice123 --no-admin http://localhost:8008
```

Para parar o servidor, use `docker compose -f docker/docker-compose.yml down`. Acrescente `-v` para apagar os dados.

### Conta no matrix.org

O app funciona com qualquer homeserver que tenha simplified sliding sync (Synapse 1.114 ou mais novo). No `matrix.org`:

1. Crie uma conta com usuário e senha em [account.matrix.org/register](https://account.matrix.org/register).
2. Para conversar com o app, crie uma segunda conta e use-a no [Element Web](https://app.element.io).
3. No app, use o servidor `matrix.org`, o usuário (ou `@usuario:matrix.org`) e a senha. O login pelo navegador também funciona.

Contas criadas com login social (Google, GitHub etc.) não têm senha. Para definir uma, cadastre e verifique um e-mail em [account.matrix.org/account](https://account.matrix.org/account) e use [account.matrix.org/recover](https://account.matrix.org/recover).

## Arquitetura

O app segue o [guia oficial de arquitetura do Flutter](https://docs.flutter.dev/app-architecture) (MVVM), com Cubit no papel de ViewModel:

```
View (widgets) → ViewModel (Cubit) → Repository (fonte da verdade) → Service → Rust (FRB)
```

- **Service** (`MatrixService`): só chama o Rust e devolve o resultado num `Result`, sem conhecer o domínio.
- **Repository**: converte o que vem do Rust para os modelos de domínio. Fora da camada `data`, nada importa `src/rust`, então a UI e os testes não dependem da ponte.
- **ViewModels**: um por tela ou componente. Não navegam; o `AuthGate` escuta a sessão e troca entre login e home.

No Rust, o `MatrixClient` é um tipo opaco que guarda o `Client` do SDK. Cada feature declara seus métodos num `impl MatrixClient` no próprio arquivo, e o Flutter Rust Bridge junta todos numa única classe Dart.

```
matrix_messenger/
├── lib/
│   ├── app/                  # MaterialApp e tema
│   ├── config/               # Injeção de dependências
│   ├── core/                 # Result, MatrixService, utilitários e componentes de UI
│   ├── features/
│   │   ├── auth/             # Login, logout, restauração da sessão (AuthGate)
│   │   ├── home/             # Moldura da tela principal
│   │   ├── rooms/            # Lista, busca, nova sala, convites, entrar, convidar e sair
│   │   ├── conversation/     # Timeline, envio, imagens, respostas, threads e reações
│   │   ├── threads/          # Threads recentes
│   │   ├── notifications/    # Notificações do sistema
│   │   └── recovery/         # Configuração e chave de recuperação do histórico cifrado
│   └── src/rust/             # Código gerado pelo FRB (não editar à mão)
├── rust/src/
│   ├── api/                  # Funções expostas ao Dart (client, auth, oidc, rooms, timeline…)
│   ├── session_store.rs      # Sessão no cofre do sistema operacional
│   ├── room_list.rs          # Lista de salas sobre o SyncService
│   ├── timeline.rs           # Conversa sobre a Timeline do matrix-sdk-ui
│   ├── notifications.rs      # Notificações pelas regras de push do SDK
│   └── …
├── rust_builder/             # Plugin (Cargokit) que compila o Rust no build do Flutter
├── docker/                   # Synapse local e seed
├── testing/                  # Fakes e modelos de exemplo compartilhados pelos testes
├── test/                     # Testes Dart (espelham lib/; com fakes, sem Rust)
└── integration_test/         # Testes com a ponte Rust real
```

Cada feature segue a mesma divisão: `data/repositories`, `domain/models` e `ui/<tela>/{view_models,widgets}`.

## Principais decisões técnicas

O registro completo, com as alternativas consideradas, está em [docs/decisoes-tecnicas.md](docs/decisoes-tecnicas.md). Um resumo:

- **`matrix-sdk-ui` para salas e conversa.** O `SyncService`/`RoomListService` já entregam ordem por recência, última mensagem e contadores de não lidas, e a `Timeline` resolve edição, eco local, divisores de data e paginação.
- **Sessão no cofre do sistema, direto no Rust.** O crate `keyring` grava a sessão e a passphrase do store SQLite cifrado no Keychain, no Credential Manager ou no Secret Service, então tokens nunca passam pela ponte. Restaurar reabre o mesmo dispositivo sem rede, o que preserva as chaves de criptografia. Em Linux sem Secret Service o login funciona, mas a sessão não é salva, em vez de ir para um arquivo em texto puro.
- **Lista inteira pela ponte, filtros no Dart.** Os filtros mudam a cada clique e não precisam de ida e volta ao Rust. As atualizações do sliding sync são agrupadas numa janela de 100 ms.
- **Erros tipados e convertidos no repository.** O Rust devolve enums de erro, e o repository converte para falhas de domínio com `switch` exaustivo: um erro novo no Rust não compila até alguém decidir como mostrá-lo.
- **Paginação decidida pela tela.** Cada busca pede 20 eventos, e quem decide pedir mais é a tela. Uma janela de exibição no ViewModel evita que o histórico cresça aos saltos quando o cache do SDK entrega blocos grandes.
- **Histórico cifrado pela chave de recuperação.** O SDK baixa do backup só a chave da mensagem que falhou (`AfterDecryptionFailure`) e a timeline decifra de novo sozinha. Em conta sem backup, o app cria o cross-signing e o backup e mostra a chave nova uma única vez.
- **Notificações pelas regras de push do SDK.** O handler de notificações do SDK aplica as regras da conta (salas silenciadas, menções), o Rust descarta o histórico do primeiro sync e eventos reentregues, e o Dart só omite a notificação quando a sala está aberta com a janela em foco. Cada sala ocupa uma notificação, que a mensagem seguinte substitui.
- **SQLite embutido (`bundled-sqlite`).** Os três sistemas usam a mesma versão, sem depender do SQLite instalado.

## Testes

### Flutter

```bash
flutter test
```

Testes de ViewModel (`bloc_test`), de widget e de repository, com os fakes de `testing/`, sem Rust e sem rede.

### Rust

```bash
cd rust && cargo test
```

Os testes que precisam de rede e de uma conta Matrix real ficam com `#[ignore]` e leem `MATRIX_HOMESERVER`, `MATRIX_USERNAME` e `MATRIX_PASSWORD` do ambiente ou do `.env` da raiz (copie o `.env.example`):

```bash
cd rust && cargo test -- --ignored --nocapture
```

### Integração (ponte Rust real)

```bash
flutter test integration_test/auth_bridge_test.dart -d macos
```

Compila o app com o Rust e chama o `MatrixClient` de verdade: restauração sem sessão, erro tipado vindo do Rust e o fluxo da tela de login. Rode um arquivo por vez; com vários arquivos num comando, o app não abre a partir do segundo. Os testes de conta real (`rooms_bridge_test.dart` e `conversation_bridge_test.dart`) ficam pulados sem credenciais:

```bash
flutter test integration_test/conversation_bridge_test.dart -d macos --dart-define-from-file=.env
```

## CI e release

- **CI** (`.github/workflows/ci.yml`), em todo push e PR para a `main`: `flutter analyze` e `flutter test` no Ubuntu; `cargo build` e `cargo test` no Ubuntu, no macOS e no Windows, porque o cofre da sessão usa um backend nativo diferente em cada sistema.
- **Release** (`.github/workflows/release.yml`), ao criar uma tag `v*`: compila o app nos três sistemas em paralelo e publica `.dmg` (macOS), `.zip` (Windows) e `.tar.gz` (Linux) na [página de releases](https://github.com/danielmessi13/matrix_messenger/releases). Compila só na tag porque cada build compila o Matrix SDK do zero.

## Limitações

**Plataformas**

- Só o macOS foi testado à mão. Linux e Windows compilam no CI de release (v1.0.0), mas não foram usados no dia a dia.
- No Linux, os emojis das reações dependem de uma fonte de emoji colorida instalada.

**Sessão**

- Um `soft_logout` é tratado como revogação: a sessão sai do cofre em vez de pedir a senha de novo mantendo o dispositivo.
- Servidores sem simplified sliding sync (Synapse anterior a 1.114, Dendrite) não funcionam.

**Conversa**

- HTML formatado vindo de outros clientes aparece como texto simples.

**Salas**

- Sala pública criada no app não tem alias (`#nome:servidor`) nem entra no diretório do servidor.
- Espaços não são tratados.

**Notificações**

- Só chegam com o app aberto: não há push do servidor, então mensagens recebidas com o app fechado não notificam.
- Sem contador no ícone do app.

**Criptografia**

- Histórico cifrado só volta com a chave de recuperação. Sem ela, mensagens anteriores ao login aparecem como "Mensagem criptografada".
- Se o servidor exigir a senha (UIA) para criar o cross-signing, a configuração do backup mostra o erro e fica para outro cliente. O Synapse local não exige.

A lista completa, com o caminho para resolver vários itens, está em [docs/limitacoes.md](docs/limitacoes.md).

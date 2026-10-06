# Decisões técnicas

Registro das principais decisões do projeto, com o que foi considerado e o motivo da escolha. O [README](../README.md) tem um resumo.

## TL;DR

- **Arquitetura:** MVVM com Cubit, seguindo o guia oficial do Flutter. Só a camada `data` conhece o Rust.
- **SDK:** `SyncService`, `RoomListService` e `Timeline` do `matrix-sdk-ui` fazem o trabalho pesado de sync, lista de salas e conversa.
- **Sessão:** guardada no cofre do sistema direto pelo Rust, para reabrir o mesmo dispositivo sem rede e sem tokens passando pela ponte.
- **Ponte:** a lista de salas vai inteira para o Dart e os filtros rodam lá; o Rust não formata texto de tela.
- **Conversa:** a tela decide quando paginar, e uma janela de exibição evita que o histórico cresça aos saltos.
- **Criptografia:** o histórico antigo volta pela chave de recuperação, baixando do backup só a chave de cada mensagem que falhou.

## Sumário

- [Arquitetura](#arquitetura)
- [Rust e a ponte com o Dart](#rust-e-a-ponte-com-o-dart)
- [Sessão e autenticação](#sessão-e-autenticação)
- [Lista de salas](#lista-de-salas)
- [Conversa](#conversa)
- [Respostas e threads](#respostas-e-threads)
- [Criptografia](#criptografia)
- [Gerenciamento de salas](#gerenciamento-de-salas)
- [Build e CI](#build-e-ci)

## Arquitetura

### Arquitetura MVVM com Cubit

O app segue o [guia oficial de arquitetura do Flutter](https://docs.flutter.dev/app-architecture), com o Cubit no papel de ViewModel:

```
View (Screen/Button) → ViewModel (Cubit) → Repository (fonte da verdade) → Service (Rust/FRB)
```

- **Service**: só chama o Rust e devolve o resultado num `Result`, sem conhecer o domínio.
- **Repository**: dono da sessão; converte o que vem do Rust para o domínio e avisa mudanças pelo stream `sessionChanges`.
- **ViewModels**: um por tela. Não navegam; o `AuthGate` escuta a sessão e troca entre login e home.

#### Erros de login: `AuthErrorKind` → `AuthFailureType`

O Rust devolve `AuthErrorKind`, que vem do código gerado pela ponte. Pensei em usar esse enum direto na UI, mas decidi criar o `AuthFailureType` no domínio e converter no repository (`_toFailureType`):

- Fora da camada `data`, nada importa `src/rust`. A UI e os fakes de teste não dependem da ponte.
- O domínio tem falhas que não vêm do Rust: `browserUnavailable` (o Dart não abriu o navegador), `sessionRevoked` (stream do `MatrixService`) e `storage` vindo de `LocalStorageException`.
- O `switch` é exaustivo: se o Rust ganhar um `AuthErrorKind` novo, o código não compila até alguém decidir como mostrar esse erro. O teste do repository também confere que todos os valores estão mapeados.

O custo é um mapeamento quase um para um que parece repetido.

## Rust e a ponte com o Dart

### `MatrixClient` dividido por feature

O `MatrixClient` começou no `auth.rs` e foi acumulando salas, timeline, recuperação e convites, então o nome do arquivo deixou de fazer sentido. A struct e o ciclo da sessão (cofre, revogação) foram para `api/client.rs`, e cada feature declara seus métodos num `impl MatrixClient` no próprio arquivo. O FRB junta todos os blocos numa única classe `MatrixClient` em `client.dart`, então o Dart não muda, só os imports. O custo é que os campos usados pelas features ficam `pub(crate)`. Pensei em funções soltas por feature ou num objeto por feature (`client.rooms()`), mas mantive métodos: função de topo não dá para simular por interface nos testes, e cada objeto extra guardaria uma cópia do `Client`, o que deixaria o store SQLite aberto depois do `dispose()` do `MatrixClient`.

### SQLite embutido (`bundled-sqlite`)

```toml
matrix-sdk = { version = "0.19.1", features = ["bundled-sqlite"] }
```

O `matrix-sdk` guarda estado e cache em SQLite e, por padrão, depende do SQLite instalado no sistema. Com a feature `bundled-sqlite`, o SQLite é compilado junto com o crate, então macOS, Windows e Linux usam a mesma versão, sem dependência externa. O custo é uma primeira compilação mais lenta e um binário um pouco maior.

## Sessão e autenticação

### Sessão persistida no cofre do sistema operacional

Sem salvar a sessão, cada abertura do app criaria um *device* novo no servidor, e o histórico cifrado do device anterior ficaria ilegível.

O login grava no cofre do SO a sessão do SDK, o homeserver e a passphrase do store; ao abrir, `MatrixClient.restoreSession` reabre o mesmo device sem rede. O logout encerra o device no servidor e apaga essa entrada.

Usei o crate `keyring` (Keychain no macOS, Credential Manager no Windows, Secret Service no Linux) direto no Rust, assim tokens e passphrase nunca passam pela ponte.

Sem cofre (nenhum Secret Service, como no runner Ubuntu do CI), a restauração devolve `None` em vez de erro e o app abre no login. Cofre bloqueado ou acesso negado continua erro, porque o próximo login apagaria o store do device salvo.

Limitação: depois de um logout, o próximo login cria um device novo, que não tem as chaves das salas cifradas e não consegue ler o histórico cifrado. Salas sem criptografia voltam inteiras pelo sync, porque o store local é só cache. Reaproveitar o store antigo não resolveria, porque o crypto store pertence ao device apagado. A chave de recuperação resolve isso: ela traz as chaves das salas do backup da conta (veja [Histórico cifrado pela chave de recuperação](#histórico-cifrado-pela-chave-de-recuperação)).

#### Sem cofre do sistema (Linux sem Secret Service)

GNOME (gnome-keyring) e KDE Plasma (KWallet) já trazem um serviço Secret Service. Gerenciadores de janela minimalistas (i3, sway), instalações enxutas e máquinas sem interface gráfica normalmente não.

Nesses casos **o login funciona, mas a sessão não é salva**: `MatrixClient.sessionSaved` vem `false` e a home avisa que será preciso entrar de novo na próxima abertura. O custo é voltar a criar um device novo a cada abertura do app.

Pensei em salvar a sessão num arquivo da pasta do app (como o Element Desktop faz), mas isso deixaria o access token e a passphrase do store em texto puro no disco. Como poucos sistemas ficam sem Secret Service, preferi não manter a sessão nesses casos.

## Lista de salas

### Lista de salas pelo `SyncService` do `matrix-sdk-ui`

Pensei em montar a lista de salas direto com o `Client` do `matrix-sdk`, mas decidi usar o `SyncService` e o `RoomListService` do `matrix-sdk-ui`. Eles já entregam a ordem por recência, a última mensagem e os contadores de não lidas, e o `Timeline` do mesmo crate serve para a tela de conversa.

O `SyncService` roda numa task própria do SDK e não para quando é solto, então o `RoomSync` para o serviço no logout, na revogação (antes de avisar o Dart) e no `Drop`. Mantive o modo offline, mas se o sync cai para `Offline` menos de 5 s depois de o SDK religá-lo, trato como erro persistente e espero com backoff; sem isso um 403 com o servidor no ar vira laço de requisições.

### Lista inteira pela ponte, filtro no Dart

Pensei em filtrar no Rust, mas decidi mandar a lista inteira e filtrar no Dart. Os filtros mudam a cada clique, e assim não há ida e volta pela ponte; o custo é reenviar a lista a cada emissão, aceitável para o número de salas de uma conta comum. O Rust também não formata texto de tela (horário, "Você:", "Imagem", "Sala vazia" são do Dart).

Fica como melhoria para contas com muitas salas: paginar no Rust (o `entries_with_dynamic_adapters` já aceita tamanho de página e `add_one_page()`) e mover os filtros para o `set_filter` do SDK, que já tem filtros de menções e DMs (`category`). Assim só a parte visível atravessaria a ponte.

### Emissão com janela de 100 ms e espera do primeiro carregamento

O sliding sync dispara muitas atualizações seguidas. O Rust agrupa em uma janela fixa de 100 ms e só emite a primeira lista depois do primeiro carregamento, para a UI não mostrar a lista vazia e depois encher.

### Busca de mensagens

Pensei em filtrar as mensagens dentro do app, mas só a conversa aberta fica carregada na memória. Decidi usar o `/search` do servidor pelo Rust (`search_messages`), com paginação pelo `next_batch`. Clicar num resultado seleciona a sala e leva a conversa até a mensagem.

## Conversa

### Conversa pela Timeline do `matrix-sdk-ui`

Pensei em montar a lista de mensagens a partir dos eventos crus, mas decidi usar a `Timeline` do `matrix-sdk-ui`, que já resolve edição, eco local, divisores de data e paginação. Na timeline principal as respostas de thread ficam escondidas (`hide_threaded_events`) e aparecem só como resumo na raiz; a thread abre numa timeline própria. Liguei o rastreio de recibos no builder porque o padrão não acompanha e o "Lida por" ficaria vazio. Na ponte não passa enum com dados (o FRB geraria classes `freezed`), então `TimelineEntry` é struct com campos opcionais e os enums só têm variantes simples.

### Timeline sem lista lazy

Pensei em manter o `ListView.builder`, mas ele só monta as mensagens próximas da tela, e rolar até uma citação que está fora dela não funciona. O `ListView` com `children` não resolve, porque o `SliverList` por baixo também só monta o que está visível. Decidi usar `SingleChildScrollView` invertido com `Column`: toda mensagem carregada fica montada, e o `Scrollable.ensureVisible` alcança qualquer uma. Não usei pacote de lista posicionada para não trocar o `ScrollController`, que já cuida da paginação e de manter a leitura no lugar. O custo é montar todo o histórico carregado a cada atualização, o que pesa só em conversas com milhares de mensagens abertas.

### Paginação decidida pela tela

Pensei em levar a busca de histórico para o Rust, com um laço até 30 mensagens visíveis e espera pela página antes de seguir, mas ficou complexo (trava, fila, prazos e estados de carga). Decidi por um caminho mais simples: cada busca pede 20 eventos uma vez, e o snapshot leva só `paginating`, vindo do `live_back_pagination_status` da `Timeline` (na thread fica sempre falso). Quem decide pedir mais é a tela: a cada mudança de itens ou de status, se está parada, não chegou ao início e está perto do topo, pede de novo. Uma página só de eventos escondidos não muda o estado da tela, então, quando a busca volta sem chegar ao início, a tela reavalia na hora. Isso enche a tela ao abrir e atravessa essas páginas sem laço no Rust; no pior caso, quando a página chega depois de a busca retornar, sai uma busca a mais. Uma falha não se repete sozinha: aparece o botão "Carregar anteriores", no centro se a lista estiver vazia. O spinner pequeno do topo só aparece quando a lista já rola; antes disso a busca é o preenchimento da tela, e com a lista vazia o carregamento fica no centro.

### Janela de exibição na conversa

Do disco, o cache de eventos do SDK entrega o bloco inteiro (até 128 eventos) mesmo quando a paginação pede 20, então o histórico crescia aos saltos e a `Column` montava tudo de uma vez. O `ConversationViewModel` guarda tudo o que o SDK entregou e mostra uma janela que vai de uma mensagem âncora até o fim; subir revela 20 por vez e só chama o Rust quando não há nada escondido. A âncora é uma mensagem, e não "os últimos N", para uma mensagem nova embaixo não empurrar a do topo para fora enquanto se lê o histórico. O "Início da conversa" só aparece quando o SDK chegou ao início e não há nada escondido. A busca começa a duas alturas da área visível do topo, para as mensagens já estarem reveladas antes de o usuário chegar à borda. Pensei em adiar a revelação enquanto o usuário rola, mas no desktop a lista invertida não se mexe quando entram itens acima, e adiar travaria a rolagem contínua do trackpad no topo.

### Markdown com o pacote `markdown`

O composer insere `**negrito**`, `_itálico_`, `~~riscado~~`, `` `código` `` e `- ` lista, e o envio usa `text_markdown` do SDK. Para exibir, usei o pacote `markdown` do Dart em vez de um renderer de widgets pronto, porque só preciso de negrito, itálico, riscado, código inline e listas, e assim o texto continua um `TextSpan` comum.

### Imagens

**Download.** O download usa `get_media_content` com o cache do store, que já decifra a mídia de sala E2EE. O tile tenta, nesta ordem:
1. a miniatura do evento;
2. a miniatura do servidor (só em sala sem cifra);
3. o original.

**Envio.** Pensei em mandar com `send_attachment` direto, mas decidi pela fila de envio (`use_send_queue`): sem ela não há eco local nem o mesmo reenviar e cancelar do texto. O tipo e as dimensões saem do cabeçalho do arquivo com o `imagesize`, sem decodificar a imagem. O seletor é o `file_selector`, com o entitlement `files.user-selected.read-only` no macOS.

### Reações

Pensei em oferecer 6 reações rápidas fixas na barra de hover, mas reações de outros clientes chegam com qualquer emoji, então reagir é sempre pelo seletor completo do `emoji_picker_flutter` (botão "Reagir"), num popover. Os chips embaixo da mensagem continuam alternando a reação ao clicar. Mensagem apagada, não decifrada ou ainda sem `event_id` não aceita reação.

## Respostas e threads

### Citação nas respostas

O "Responder" do Matrix não é thread: é uma mensagem comum da conversa principal que aponta para a original (`m.in_reply_to`). Mostro a original como citação acima do texto, com o nome de quem enviou e até duas linhas. O SDK só preenche a original se ela já estiver na timeline; quando não está, a conversa pede ao servidor uma vez por resposta (`fetch_details_for_event`) e mostra "Carregando mensagem…" até chegar, ou "Mensagem original indisponível" se falhar. O texto citado que clientes antigos colocam no corpo da resposta o SDK já remove.

### Respostas e threads no painel

Responder cita a mensagem com `send_reply` do SDK; na timeline da thread o mesmo método mantém a resposta dentro da thread, e o envio sem citação ganha a relação `m.thread` sozinho, inclusive numa thread vazia (é assim que se inicia uma). A thread abre num painel à direita, uma por vez, e o `ThreadViewModel` dela fica no `ConversationViewModel` para sobreviver aos rebuilds da conversa. O menu do hover só oferece "Thread" para mensagem sem thread; quem já tem abre pela linha de resumo. O resumo do SDK traz o número de respostas e a última, não os participantes, então a linha mostra "N respostas · última de X às HH:MM". Pensei em ir até uma citação fora do histórico com uma timeline focada no evento, mas decidi paginar três vezes e avisar se não achar, para não ter outra timeline e outro fluxo de tela. O `id` da mensagem é o da timeline (estável entre eco local e confirmação); responder, abrir thread e ir até a citação usam o `event_id`, que o eco local ainda não tem, por isso o menu some até o servidor confirmar.

### Thread lida ao abrir

Pensei em marcar tudo como lido ao abrir a sala, mas decidi separar: o contador da sala conta só a conversa principal, e a thread só fica lida quando é aberta no painel. Para isso o `Client` liga o suporte a threads do SDK, que tira as respostas da contagem da sala e mantém uma contagem por thread; o recibo vai como `main` na conversa principal e com a raiz na thread. A linha da thread mostra "N novas respostas". Como ler uma thread não muda os dados da sala, a timeline da thread aberta avisa por um canal `broadcast` (`ThreadReads`) quando a contagem dela muda, e a conversa recalcula.

O canal é um só para o app inteiro e o aviso leva só o id da sala. A conversa aberta usa o `changed_in`, que ignora avisos de outras salas, para não recalcular à toa quando muda uma thread de outra sala.

### Threads recentes

Pensei em detectar as salas com histórico cortado no sync e buscar as threads delas, mas decidi buscar no servidor de uma vez: o filtro Threads virou a lista "Threads recentes". Ao abrir o app, quando o primeiro sync chega a Running, o Rust pede `list_threads` só com as threads em que participo nas 4 salas joined mais recentes e guarda as 10 com atividade mais nova. Depois, cada resposta de thread que chega pelo sync, de qualquer sala, recarrega a raiz no servidor (`Room::event`), uma recarga por raiz de cada vez; o resumo que vem junto diz se participo, quantas respostas tem e qual foi a última. A lista não tem estado de não lida; o "N novas respostas" continua só dentro da conversa (`unread_by_thread` e `ThreadReads` só na timeline), e a contagem de threads não lidas saiu da lista de salas e do rail. Clicar numa thread seleciona a sala, leva a conversa até a raiz e abre o painel da thread, inclusive com a sala já aberta; o destaque na lista segue a thread aberta, não a sala. Apagar ou editar a raiz ou a última resposta recarrega a thread; sair da sala tira as threads dela. Se o canal de atualizações do sync atrasar (`Lagged`), a busca inicial roda de novo para recuperar o que se perdeu, e se o sync não chegar a Running (offline, erro, servidor sem suporte) a lista mostra o erro com "Tentar de novo" em vez de ficar carregando.

Numa sala cifrada o crypto decifra a última resposta junto com a raiz, mas a chave só sai do backup depois de uma falha, e a falha na última resposta não pede a chave sozinha. Por isso o Rust pede ao backup (`download_room_key`) cada sessão que faltou, uma única vez, e recarrega a raiz quando a chave chega (`room_keys_received_stream`). Enquanto não decifra, a lista mostra "Mensagem criptografada".

## Criptografia

### Histórico cifrado pela chave de recuperação

Quem decifra é o dispositivo: a chave de cada sessão de sala só vai para os dispositivos que existiam quando a mensagem foi enviada, então um login novo não lê o histórico. Para isso o app usa o backup de chaves da conta. Quando o dispositivo ainda não consegue abri-lo (`RecoveryState::Incomplete`), a lista de conversas mostra um cartão (e um "!" na lista recolhida) que abre o modal da chave de recuperação, e o `recover()` do SDK importa os segredos (backup e cross-signing), o que também deixa o dispositivo verificado. Pensei em baixar o backup inteiro ao destravar, mas decidi `AfterDecryptionFailure`: o SDK busca só a chave da mensagem que falhou, e a Timeline decifra de novo sozinha. `auto_enable_backups` fica desligado, porque um backup criado sem chave de recuperação ficaria só no SQLite local. O cartão fica até o estado de sucesso do modal ser fechado. Erro de rede tem mensagem própria, para não dizer "essa chave não confere" quando o problema é a conexão.

### Compartilhar histórico ao convidar

O matrix-sdk 0.19.1 liga por padrão o MSC4268 (`enable_share_history_on_invite`): antes de enviar o convite, manda ao convidado as chaves das mensagens anteriores, e para isso exige esta sessão verificada; sem verificação o convite não sai. Pensei em desligar o recurso no client, decidi mantê-lo e dar a escolha por sala na criação: em sala privada, "Novos membros veem as mensagens anteriores" vira `history_visibility` `shared` (ligado, padrão) ou `joined` (desligado, e o SDK pula o compartilhamento). Conta sem cross-signing também pula. Quando o convite falha por sessão não verificada, o erro chega como `UnverifiedDevice` (pelo conversor público `QueueWedgeError` do SDK, que cobre `SendingFromUnverifiedDevice` e `CrossSigningNotSetup`) e o app explica que é preciso usar a chave de recuperação, no diálogo Convidar e no aviso de convites que falharam na criação, que agora traz o motivo de cada um.

## Gerenciamento de salas

### Nova sala

A sala é criada sem convites no `createRoom`; depois cada ID é convidado com `invite_user_by_id`. Assim um ID ruim não derruba a criação, e os que falharem aparecem num aviso na home. Antes de criar, cada ID passa pela consulta de perfil (`GET /profile`): 404 bloqueia o envio; 403 (servidor que restringe perfis) e falha de rede liberam, e o convite decide. Privada usa o preset `PrivateChat` com cifra no estado inicial; pública usa `PublicChat`, sem cifra e sem alias. A sala nova só entra na lista na próxima volta do sync, então a lista guarda o id como pendente e seleciona quando ele chega. O `create_room` tem limite de 30 s e o `check_user` não repete a requisição: o retry padrão do SDK insiste por até 15 min em 5xx/429 e travaria o diálogo em "Criando…" ou o chip em verificação.

### Link da sala e entrar em sala

O link vem do `matrix_to_permalink` do SDK: usa o alias quando a sala tem um; senão, o ID com até três servidores `via` escolhidos pelos membros, para que outro servidor saiba por onde buscar a sala. O botão de copiar só aparece em sala pública, porque em sala privada o link não deixa ninguém entrar sem convite. Entrar aceita link `matrix.to`, URI `matrix:`, ID ou alias; o parse fica no Rust com o ruma, e um ID sem `via` usa o servidor do próprio ID. A entrada é uma aba no diálogo de nova sala para não ocupar mais espaço no topo, e tem o mesmo limite de 30 s da criação. Um 404 sem errcode conhecido também vira "sala não encontrada", porque alguns servidores respondem assim.

### Convites

Aceitar e recusar chamam `join()` e `leave()` do SDK. Recusar um convite também o apaga da conta (`forget`), então a sala some da lista pelo filtro de salas deixadas. Depois do sucesso o painel não muda sozinho: espera o sync atualizar a sala, e aí troca para a conversa ou volta para "Selecione uma conversa". Assim a tela segue o estado real da sala, sem uma cópia local que poderia divergir.

### Convidar e sair de sala

Os dois botões ficam no cabeçalho da conversa, só em salas (não em DM). Convidar só aparece quando o Rust confirma que o power level permite convidar, e o app reconsulta a cada atualização da sala, porque power levels não vêm no resumo da sala. O diálogo convida um por um e mantém abertas só as falhas, cada uma com o motivo e "Tentar de novo". Pensei em fechar o diálogo mesmo com falhas e avisar por fora, mas decidi manter aberto.

Sair pede confirmação, e a lista se atualiza pelo sync. Sair de uma sala que o sync já tirou conta como sucesso.

## Build e CI

### CI em Ubuntu, macOS e Windows

O `cargo test` roda nos três sistemas, porque o cofre da sessão (`keyring`) usa um backend nativo diferente em cada um. O runner Ubuntu não tem interface gráfica nem Secret Service, o mesmo cenário de um Linux sem gerenciador de senhas, então ele cobre a restauração sem cofre (`NoDefaultStore` vira `None`). O job do Flutter segue só no Ubuntu, já que os testes Dart usam fakes e não tocam no Rust.

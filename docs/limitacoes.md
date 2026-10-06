# Limitações

Lista completa dos itens não concluídos e dos comportamentos conhecidos, com o caminho para resolver quando ele já foi estudado. O [README](../README.md#limitações) tem um resumo.

## TL;DR

- Só o macOS foi testado à mão; Linux e Windows só compilam no CI.
- O histórico cifrado só volta com a chave de recuperação.
- Servidores sem simplified sliding sync (Synapse anterior a 1.114) não funcionam.
- Espaços, alias de sala e links `matrix.to` abertos de fora do app não são tratados.

## Lista completa

- Sala só com mensagens que não dá para decifrar (sem a chave de recuperação) aparece sem prévia na lista, sem aviso de cifrada. Buscar a última mensagem não decifrada no event cache ficou para depois.
- A opção de compartilhar o histórico com convidados só existe na criação da sala; o app não muda a visibilidade do histórico de uma sala existente.
- Convidar quem já está na sala mostra o erro do servidor (403), porque o repositório não expõe a lista de membros para filtrar antes.
- O cartão da chave de recuperação não aparece no modo "Threads recentes", que troca o painel de salas pela lista de threads.
- Recusar e bloquear não existe; recusar só sai do convite, e quem convidou pode convidar de novo.
- Espaços não são tratados.
- Sala pública criada no app não tem alias (`#nome:servidor`) nem entra no diretório do servidor: entra quem tiver o ID ou o link `matrix.to`. Alias exigiria tratar endereço em uso ou inválido, e o diretório do matrix.org pode exigir moderação.
- Links `matrix.to` clicados fora do app (navegador, outro app) não abrem o app.
- Servidores sem simplified sliding sync (Synapse < 1.114, Dendrite) não funcionam.
- No Linux, os emojis das reações dependem de uma fonte de emoji colorida instalada (ex.: Noto Color Emoji); sem ela aparecem quadrados. macOS e Windows usam a fonte do sistema.
- HTML formatado vindo de outros clientes aparece como texto simples.
- Citação de mensagem fora das três páginas mais recentes só avisa "Mensagem fora do histórico carregado".
- A linha da thread não lista os participantes, só a última resposta.
- Histórico cifrado só volta com a chave de recuperação. Sem ela, mensagens anteriores ao login aparecem como "Mensagem criptografada".
- Toda resposta de thread que chega pelo sync, mesmo de thread em que não participo, gera uma consulta da raiz ao servidor: só ele sabe se participo de uma thread que ainda não está na lista.
- Com o filtro Threads ativo, a busca digitada continua consultando mensagens no servidor sem mostrar o resultado.

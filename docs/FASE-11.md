# Fase 11 — escrita de arquivos, conversa contínua e modo relógio

## Escrita de arquivos no agente

- Novas ações: `write_file`, `append_file` e `create_dir`.
- A escrita usa raízes próprias em `CHAT_AGENT_WRITE_DIRS`, separadas das
  raízes de leitura em `CHAT_AGENT_ALLOWED_DIRS`. Uma pasta liberada para ler
  não fica automaticamente liberada para gravar.
- Toda ação exige `requires_confirmation=true`; sem confirmação, o daemon
  responde `needs_confirmation` e não altera nada.
- O destino precisa ser absoluto, a pasta pai deve existir e o caminho é
  resolvido antes da checagem. `..`, links simbólicos e destinos fora das
  raízes são recusados.
- A gravação é atômica: arquivo temporário no mesmo diretório, `fsync` e
  `os.replace`. Uma interrupção não deixa o documento pela metade.
- Limites: 32 KiB de conteúdo por operação e 64 KiB por arquivo resultante.
  `create_dir` cria apenas um nível e não aceita conteúdo.
- O journal registra caminho, status, tamanho e resumo. O conteúdo escrito
  nunca é gravado.
- A ferramenta `agent_exec` do backend valida a combinação de campos por ação
  e preserva espaços e quebras de linha do conteúdo. O app mostra o caminho e
  o tamanho antes de pedir confirmação.

## Conversa contínua e palavra de ativação

- A conversa contínua é opcional e começa desligada. O padrão da palavra de
  ativação é `chat`.
- Depois de cada resposta falada, o app volta a ouvir automaticamente. O
  silêncio é detectado pelo RMS do WAV; sem fala em 8 s, a captura é descartada
  e o ciclo recomeça; após 15 s, a captura é encerrada.
- Antes da ativação, a fala precisa conter a palavra configurada. A comparação
  ignora caixa, acentos e pontuação, mas exige a palavra inteira: `chatbot`
  não ativa `chat`.
- Depois de ativada, a conversa segue sem repetir a palavra até o modo ser
  desligado ou a palavra ser alterada. Uma palavra vazia desliga o portão.
- O botão de microfone interrompe a fala em andamento e inicia uma captura
  manual. O modo contínuo pode ser desligado pelo banner ou pelo diálogo.

## Modo relógio e hibernação

- O modo relógio é opcional. Quando ativado, o app abre diretamente no relógio
  e mantém a tela ligada.
- O relógio mostra hora gigante e data por extenso em português, com formato
  24 h ou 12 h. A hora é atualizada uma vez por minuto.
- Após o tempo de inatividade configurado (padrão: 5 minutos), o app entra em
  hibernação: encerra microfone, fala, timers de conversa e não mantém rede
  ativa. A tela continua mostrando o relógio.
- A tela é mantida ligada no Linux com `systemd-inhibit` e no Android com
  `FLAG_KEEP_SCREEN_ON` via `MethodChannel`.
- O despertar é por toque na tela ou por qualquer tecla. Ao acordar, a
  conversa reaparece e o timer de inatividade recomeça.
- Em hibernação não há escuta da palavra de ativação por voz. Isso é
  intencional: manter o microfone aberto impediria o consumo quase nulo.
  Quem quiser conversar acorda a tela primeiro.
- O app volta ao relógio ao retomar do segundo plano se o tempo de inatividade
  já tiver passado.

## Validação

- Agente: 10 testes, incluindo confirmação, raízes separadas, escrita atômica,
  acréscimo, criação de pasta, `..`, link simbólico, limites e journal sem
  conteúdo.
- Backend: validação cruzada de `agent_exec`, conteúdo preservado e limites.
- Flutter: 16 testes, incluindo normalização da palavra de ativação,
  preferências persistidas, relógio, retorno à conversa e hibernação.
- `ruff` e `flutter analyze` limpos.

## Limites desta fase

- Não há movimentação, cópia ou exclusão de arquivos.
- A escrita não é recursiva e não cria pastas intermediárias.
- As raízes de escrita estão configuradas no serviço real apenas em
  `~/Documentos/Chat` (modo 700). Ampliar o acesso exige revisar as pastas e
  reiniciar o `chat-agent.service`.
- O despertar por voz na hibernação não está implementado.
- Acesso remoto continua dependente de Tailscale e não foi validado.

# Fase 10 — arquivos no agente Ubuntu (somente leitura)

## Entrega

- O daemon aceita as ações `list_files` e `read_file`, além de `status` e
  `open_app`.
- As duas ações de arquivos exigem `requires_confirmation=true`; sem isso,
  respondem `needs_confirmation` e não são registradas como processadas.
- As raízes autorizadas são explícitas em `CHAT_AGENT_ALLOWED_DIRS`, separadas
  por `:`. Sem essa variável, o acesso a arquivos fica desabilitado.
- O caminho precisa ser absoluto e é resolvido com `Path.resolve(strict=True)`.
  Qualquer destino fora das raízes — inclusive via `..` ou link simbólico — é
  recusado com `denied`.
- `list_files` devolve até 200 entradas, com tipo e tamanho; não é recursivo.
- `read_file` aceita apenas texto UTF-8 de até 64 KiB. Arquivos binários,
  maiores que o limite ou fora das raízes são recusados.
- O journal registra `command_id`, ação, caminho, status e um resumo; o conteúdo
  lido nunca é gravado no journal.
- A ferramenta `agent_exec` do backend ganhou os campos `action` (`list_files`
  ou `read_file`) e `path`, com validação cruzada: `open_app` exige `app`,
  ações de arquivo exigem caminho absoluto e `status` não aceita parâmetros.
  A ferramenta continua com permissão `CONFIRM` e o app mostra a confirmação
  antes de qualquer leitura.

## Configuração

Adicione ao arquivo `~/.config/chat-agent/agent.env` (modo 600) as pastas que o
assistente pode ler, usando caminhos absolutos. Exemplo:

```bash
CHAT_AGENT_ALLOWED_DIRS=/home/nikolas/Documentos:/home/nikolas/Projetos
```

Reinicie o serviço:

```bash
systemctl --user restart chat-agent.service
```

Não use `$HOME` inteiro sem necessidade. Pastas com segredos, chaves SSH e
credenciais devem ficar fora das raízes autorizadas.

## Validação

- Testes do daemon: 9 aprovados, incluindo confirmação obrigatória, listagem,
  leitura, binário recusado, caminho relativo, arquivo inexistente, raiz não
  configurada, `..` e caminho absoluto fora da raiz.
- Testes do backend: 33 aprovados, incluindo validação cruzada dos argumentos
  de `agent_exec`.
- Smoke test real em daemon temporário: `needs_confirmation` sem aprovação,
  listagem e leitura dentro da raiz, `denied` para caminho externo e para
  `allowed/../fora.txt`; journal sem o conteúdo do arquivo.
- `ruff` passou no backend e no daemon.

## Limites desta fase

- Não há escrita, criação, movimentação ou exclusão de arquivos.
- Não há busca recursiva nem leitura de metadados além de nome e tamanho.
- O daemon continua em loopback e sem Tailscale; leitura remota não foi
  validada.
- O modelo pode pedir a leitura de um arquivo, mas a pessoa precisa aprovar
  cada pedido no app. O conteúdo retornado é marcado como dado externo no
  contexto do modelo.

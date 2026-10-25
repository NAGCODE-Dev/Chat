# Meu Dinheiro no Chat

O app de finanças usado neste ambiente é o PWA **Meu Dinheiro**
(`https://nagcode-dev.github.io/Meu-Dinheiro-/`). O PWA original guarda tudo
no `localStorage` do navegador e não tem API, importação ou parâmetros de URL.
Por isso ele não pode receber um lançamento do assistente em segundo plano.

A solução adotada foi um **fork local do PWA**, servido pelo próprio backend:

- a interface continua sendo o Meu Dinheiro;
- os dados passam a ficar no SQLite do PC;
- o assistente grava um lançamento sem abrir o app;
- o PWA mostra o lançamento na próxima vez que for aberto ou atualizado.

O PWA original no GitHub Pages não é alterado e continua disponível, mas os
dois não compartilham dados.

## Como abrir

No app do celular, abra o menu lateral e toque em **Meu Dinheiro**. O app abre
o PWA local no Chrome já com o token, então não é preciso digitar nada.

Também é possível abrir direto no navegador:

| Caminho | URL |
|---|---|
| Wi-Fi | `http://192.168.0.126:8750/finance/` |
| USB | `http://10.22.184.11:8750/finance/` |

Na primeira abertura sem o link do app, o PWA pede o token do Chat. Ele é o
mesmo `CHAT_API_TOKEN` usado pelo app e fica em `~/.config/chat/backend.env`
no PC. O token é salvo apenas no `localStorage` daquele endereço.

## Como o assistente registra

O modelo usa a ferramenta `finance_add`. Exemplos de pedidos:

- “Registre um gasto de 12,34 em comida hoje.”
- “Anote uma entrada de 500 de freela.”
- “Lance um aporte de 300 no Tesouro Selic.”
- “Quanto gastei este mês?” (usa `finance_summary`)
- “Qual é o meu saldo do mês?” (usa `finance_summary`)
- “Quanto gastei em setembro?” (usa `finance_summary` com `month`)

Na consulta, `finance_summary` usa o mês atual por padrão. A ferramenta aceita
`period` (`mes_atual`, `mes_passado` ou `todos`) ou `month` no formato
`AAAA-MM`, nome do mês (`outubro`, `outubro de 2026`) ou `DD/MM/AAAA`. Quando
`month` é informado, ele tem prioridade. Para todo o histórico, o modelo usa
`period="todos"`.

A ferramenta valida o tipo (`entrada`, `saida` ou `investimento`), o valor
positivo, a categoria e a data. Categorias aceitas:

`Salário`, `Freela`, `Investimento`, `Necessidades`, `Comida`, `Roupas`,
`Objetivos`, `Lazer` e `Outros`.

Nomes comuns são normalizados: “mercado”, “alimentação” e “restaurante” viram
`Comida`; “aluguel”, “transporte” e “contas” viram `Necessidades`; “cinema” e
“jogo” viram `Lazer`. Se a pessoa não informar a data, o backend usa a data
local do PC. Se o pedido for “hoje”, o modelo recebe a data do contexto do
celular e do servidor para não inventar outro dia.

O lançamento é gravado antes da resposta do modelo. O app não precisa estar
aberto e o PWA não precisa estar aberto.

## Dados

Duas tabelas novas no banco `~/.local/share/chat/chat.db`:

| Tabela | Conteúdo |
|---|---|
| `finance_transactions` | lançamentos: `id`, `type`, `value`, `category`, `date`, `note` |
| `finance_state` | renda, orçamento e investimentos em JSON |

A renda, o orçamento e os investimentos são editados pelo PWA. Os lançamentos
têm uma tabela própria para que o assistente possa inserir um gasto sem
sobrescrever o que a pessoa estiver editando no PWA.

Para fazer backup:

```bash
sqlite3 ~/.local/share/chat/chat.db ".backup '/tmp/chat-backup.db'"
```

## API

Todas as rotas exigem o mesmo Bearer token do backend.

| Método | Rota | Uso |
|---|---|---|
| `GET` | `/api/finance/state` | renda, investimentos e lançamentos |
| `PUT` | `/api/finance/state` | salva renda e investimentos (PWA) |
| `POST` | `/api/finance/transactions` | cria um lançamento (PWA e assistente) |
| `DELETE` | `/api/finance/transactions/{id}` | exclui um lançamento |
| `GET` | `/api/finance/summary?month=AAAA-MM` | totais do mês; `all_time=true` para tudo |
| `POST` | `/api/finance/reset` | apaga lançamentos e volta a renda padrão |

Os arquivos estáticos do PWA em `/finance/` são públicos (HTML, JS, CSS e
ícone). Eles não contêm dados; a API continua protegida. O token do link é
passado no fragmento (`#token=...`), que não é enviado ao servidor, e o PWA
o remove da barra de endereços depois de salvar.

## Limitações

- O PC precisa estar ligado e o celular na mesma rede Wi-Fi ou no USB.
- O PWA local é servido por HTTP. O Chrome exibe “não seguro” e **não oferece
  instalação como PWA standalone**, porque service workers exigem HTTPS ou
  `localhost`. Use o atalho do app ou “Adicionar à tela inicial” como atalho
  para o Chrome.
- Não há sincronização com o PWA original do GitHub Pages. Se você tiver
  lançamentos lá, será preciso exportar/importar manualmente; a versão atual
  não tem importador.
- O PWA atualiza ao voltar para a tela e ao recarregar. Não há push em tempo
  real enquanto ele está aberto em segundo plano.
- O APK é `debug`; para uso diário, gere um `release` assinado.

## Testes

```bash
backend/.venv/bin/python -m pytest backend/tests/test_finance.py -q
backend/.venv/bin/python -m ruff check backend/chat backend/tests
```

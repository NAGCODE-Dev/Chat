# Conexão celular ↔ PC

O app Android fala com o mesmo backend FastAPI do desktop. O backend continua
local ao PC; o celular é um cliente na rede de casa ou no USB.

## Como está configurado neste ambiente

- O backend escuta em `0.0.0.0:8750` e exige Bearer token em HTTP e WebSocket.
- A configuração fica em `~/.config/chat/backend.env`, com modo `600`:

  ```bash
  CHAT_HOST=0.0.0.0
  CHAT_PORT=8750
  CHAT_API_TOKEN=<token>
  ```

- O serviço de usuário `chat-backend.service` sobe o backend no login e
  reinicia em caso de falha:

  ```bash
  systemctl --user status chat-backend.service
  systemctl --user restart chat-backend.service
  journalctl --user -u chat-backend.service -f
  ```

- O app do desktop lê o mesmo token do cofre Secret Service/keyring. O app
  Android guarda o token no cofre local do aparelho.

## Endereços

| Caminho | URL típica | Quando usar |
|---|---|---|
| Wi-Fi | `http://192.168.15.8:8750` | Celular e PC na mesma rede Wi-Fi |
| USB | `http://10.22.184.11:8750` | Celular conectado por USB com tethering |
| Tailscale | `http://100.97.209.46:8750` | Fora de casa, com Tailscale ativo nos dois aparelhos |

O IP do PC pode mudar por DHCP ou ao trocar de rede. Confira com:

```bash
ip -brief -4 addr show
tailscale ip -4
```

O QR de pareamento já inclui as URLs alcançáveis no momento em que é gerado
(Tailscale, Wi-Fi e USB). O app tenta cada uma em ordem até conseguir trocar o
código.

## Pareamento por QR code (recomendado)

O QR não contém o token. Ele leva apenas um código aleatório de uso único, com
validade padrão de **300 segundos** (`CHAT_PAIRING_TTL_SECONDS`), e as URLs do
backend. O token real só é entregue quando o celular troca o código.

No PC, com o backend ativo:

```bash
./scripts/pair_qr.sh
```

O comando cria a sessão localmente, desenha o QR no terminal e salva uma imagem
em `~/.local/share/chat/pairing.png`. No celular:

1. Abra o app e toque no ícone de QR code na barra superior (ou em
   **Parear com QR code** no menu lateral).
2. Aponte a câmera para o QR do terminal ou para a imagem salva.
3. Permita o uso da câmera na primeira vez.
4. O app troca o código, salva o token no cofre do aparelho, aplica a URL que
   funcionou e aquece os modelos.

O código é de uso único: se expirar ou já tiver sido usado, gere outro com o
mesmo comando. A criação da sessão só é aceita localmente; a troca do código
(`POST /api/pairing/claim`) é a única etapa pública e exige o código secreto.

Se a câmera não estiver disponível, use a configuração manual abaixo.

## Configuração manual (alternativa)

1. Abra o app e toque na engrenagem (**Configurar conexão**).
2. Em **Endereço base**, use a URL do Wi-Fi; se não conectar, use a URL USB ou
   a URL Tailscale.
3. Em **Token da API**, cole o token de `~/.config/chat/backend.env`.
4. Salve e permita o microfone quando solicitado.

O app usa HTTP em texto claro na rede local porque o backend é local. O token
protege o acesso, mas não cifra o tráfego. Para acesso fora de casa, use
Tailscale ou outra VPN; não exponha a porta `8750` à internet.

## Verificar a conexão

No PC:

```bash
TOKEN=$(grep '^CHAT_API_TOKEN=' ~/.config/chat/backend.env | cut -d= -f2-)
curl -H "Authorization: Bearer $TOKEN" http://192.168.15.8:8750/health
curl -H "Authorization: Bearer $TOKEN" http://100.97.209.46:8750/health
```

Sem o header, a resposta deve ser `401`. No celular, o mesmo teste pode ser
feito pelo navegador: um `401` significa que a rede chegou ao backend; o app
faz a autenticação com o token.

## Áudio no Android

A reprodução das respostas usa um canal nativo (`chat/audio`) com
`MediaPlayer`, sem dependência de GStreamer. No Linux continua usando
`aplay`/`ffplay`. A gravação usa `record` no Android e `pw-record` no Linux.

## Assistente, notificações e ações

O app pode ser definido como assistente padrão do Android, ler notificações
(com permissão explícita) e executar uma lista fechada de ações no aparelho:
abrir apps, tocar música, controlar mídia e abrir links. O tema claro/escuro, o
botão de silêncio e a exclusão de conversas também ficam no app. Veja o guia
completo em [`ASSISTENTE-CELULAR.md`](ASSISTENTE-CELULAR.md).

## Meu Dinheiro

O backend serve o PWA local de finanças em `/finance/`. O menu **Meu Dinheiro**
do app abre a página já autenticada, e o assistente registra lançamentos em
segundo plano. Veja [`MEU-DINHEIRO.md`](MEU-DINHEIRO.md).

## Trocar o token

1. Gere um token novo com pelo menos 32 caracteres.
2. Atualize `CHAT_API_TOKEN` em `~/.config/chat/backend.env` (modo `600`).
3. Reinicie o serviço: `systemctl --user restart chat-backend.service`.
4. Atualize o token no app do desktop e no app do celular.

## Acesso fora de casa com Tailscale

O notebook já tem Tailscale ativo (IP `100.97.209.46`). Para o celular acessar
fora de casa:

1. Instale o Tailscale no celular (Play Store) e entre na mesma conta.
2. Confirme que os dois aparelhos aparecem em `tailscale status`.
3. Gere um novo QR; ele incluirá a URL `http://100.97.209.46:8750`.
4. Se o IP Tailscale mudar, gere outro QR ou ajuste a URL em
   **Configurar conexão**.

Não é preciso abrir porta no roteador nem expor o backend à internet. O
Tailscale cria uma rede privada WireGuard entre os aparelhos.

## Onde hospedar

A recomendação é manter backend + Ollama no notebook:

- o Ollama roda em CPU e usa a RAM e as threads do notebook;
- o SQLite e os arquivos ficam persistentes e locais;
- o celular é cliente, não servidor.

Render ou outro PaaS não resolve este caso: instância só de CPU, limite de
memória, disco efêmero e SQLite persistente pioram a experiência e o custo.
Para acesso remoto, use Tailscale; para disponibilidade contínua, mantenha o
notebook ligado e o serviço `chat-backend.service` ativo.

## Limitações

- O Tailscale ainda não está instalado no celular; o acesso fora de casa fica
  pendente até instalar o app e entrar na mesma conta.
- O endereço Wi-Fi/Tailscale pode mudar; se o app parar de conectar, confira o
  IP do PC e gere um QR novo.
- USB tethering mantém o cabo e consome bateria; o Wi-Fi é o modo normal.
- Não há escuta contínua em segundo plano; a conversa contínua funciona com o
  app aberto.
- A integração com apps de finanças ainda depende de identificar o app usado.
- O APK atual é `debug`; para uso diário, gere um `release` assinado.

# Assistente no celular

O app Android usa o mesmo backend do PC, mas executa no aparelho as ações que
dependem do Android: abrir aplicativos, tocar música, controlar a mídia, abrir
links, ler notificações e responder por voz. O modelo continua rodando no PC;
o celular é o cliente e o executor das ações.

## Papel de assistente padrão

O app declara o intent `android.intent.action.ASSIST`, então pode ser escolhido
como assistente do Android, como o Google Assistente. Para definir:

1. Abra o menu lateral → **Assistente do celular**.
2. Toque em **Definir** na opção **Assistente padrão** e confirme no Android.

Em aparelhos MIUI/Xiaomi o diálogo pode não aparecer; nesse caso, o papel pode
ser concedido por ADB:

```bash
adb shell cmd role add-role-holder android.app.role.ASSISTANT com.example.chat_app
adb shell cmd role get-role-holders android.app.role.ASSISTANT
```

O botão de assistente do aparelho abre o Chat. O gesto exato depende do
fabricante (long press no botão home, botão lateral ou canto da tela). Se o
Android mostrar um seletor com ChatGPT/Google/Chat, escolha **Chat** e
**Sempre**.

## Notificações

O app tem um `NotificationListenerService` (`ChatNotificationListener`). Ele
só recebe notificações depois que a pessoa concede **Acesso a notificações**
em Configurações → Notificações → Acesso a notificações.

No app:

1. Menu → **Assistente do celular**.
2. Ative **Ler notificações**.
3. Se a permissão ainda não estiver concedida, use **Abrir ajustes**.
4. **Ver notificações recentes** mostra o que foi capturado.

As notificações recentes entram no contexto da conversa **somente** quando a
opção está ligada. O resumo é enviado ao backend local como dado não confiável:
o modelo é instruído a não seguir ordens que apareçam no texto das
notificações. Nada é enviado para serviços externos.

Limitação do MIUI: logo após instalar ou atualizar o APK, o serviço pode ficar
habilitado mas não vinculado. Se **Ver notificações recentes** continuar vazio,
desligue e ligue a permissão de acesso a notificações, ou reinicie o aparelho.
O app também atualiza o status ao voltar para o primeiro plano.

## Ações no celular

O modelo não executa comandos arbitrários. Ele só pode pedir uma ação de uma
lista fechada, pela ferramenta `phone_action`:

| Ação | `target` | O que o app faz |
|---|---|---|
| `open_app` | nome do app (ex.: `WhatsApp`) | Procura o app pela etiqueta e abre |
| `play_music` | música ou artista | Abre a busca no Spotify, YouTube Music, YouTube ou navegador |
| `media_control` | `play`, `pause`, `next`, `previous` | Envia a tecla de mídia pelo `AudioManager` |
| `open_url` | URL HTTP/HTTPS | Abre o link no navegador do celular |

O fluxo é:

1. O backend recebe o pedido e o modelo chama `phone_action`.
2. O backend emite um evento WebSocket `device_action` com a ação e o alvo.
3. O app executa a ação no Android e mostra o resultado.

A opção **Ações no celular** permite desligar tudo isso. O backend nunca
recebe shell, arquivos ou controle total do aparelho.

### Abrir aplicativos

O app usa `QUERY_ALL_PACKAGES` para listar os apps instalados. A busca ignora
caixa e acentos e tenta, nesta ordem: nome exato, nome que contém o pedido e
nome do pacote. Se não encontrar, responde com uma mensagem clara.

### Música

`play_music` tenta os apps instalados nesta ordem: Spotify
(`spotify:search:...`), YouTube Music, YouTube e, por fim, o navegador. O app
não baixa músicas; ele abre a busca ou a reprodução no app escolhido.
`media_control` funciona com o player que estiver ativo.

## Silêncio, tema e conversas

- O botão de alto-falante na barra superior silencia as respostas faladas. A
  conversa continua por texto e o estado fica salvo no aparelho.
- **Tema** oferece Claro, Escuro e Seguir o sistema. A cor-base continua sendo
  o azul `#365D8D`; o modo escuro só muda a luminosidade da paleta.
- O ícone de lixeira em cada conversa apaga o histórico no backend, com
  confirmação. A conversa aberta também é limpa da tela.
- O **Modo relógio** aparece apenas no desktop. No Android os controles ficam
  ocultos, porque o modo foi pensado para o notebook.

## Busca na internet

O backend usa `web_search` com Bing em HTML por padrão, sem chave de API. Se
`CHAT_WEB_SEARCH_URL` estiver configurada, usa a instância SearXNG. Depois da
busca, `fetch_page` abre uma página HTTP/HTTPS e extrai o texto principal.

`fetch_page` bloqueia localhost, faixas privadas e redirecionamentos para
endereços internos (proteção contra SSRF). O conteúdo retornado é tratado como
dados externos não confiáveis pelo serviço de conversa.

## Meu Dinheiro

O menu lateral tem **Meu Dinheiro**, que abre o PWA local de finanças já
autenticado. O assistente registra gastos, receitas e aportes com a ferramenta
`finance_add`; os dados ficam no backend e não dependem de o PWA estar aberto.
Veja [`MEU-DINHEIRO.md`](MEU-DINHEIRO.md).

## Limitações

- Não há escuta contínua em segundo plano com palavra de ativação. A conversa
  contínua funciona com o app aberto; escuta permanente consumiria bateria.
- O papel de assistente abre o app, mas o gesto do fabricante pode variar.
- O Meu Dinheiro local é servido por HTTP; o Chrome não o instala como PWA
  standalone, mas o atalho do app e “Adicionar à tela inicial” funcionam.
- O APK atual é `debug`. Para uso diário, gere um `release` assinado.

# Fase 3 — cliente Flutter mínimo

## Entrega

`app_flutter/` é um cliente Flutter Material 3 que conversa com o backend por
WebSocket, acumula tokens conforme chegam e lê o histórico pela API REST. A
lista de conversas fica no menu lateral; a URL do backend pode ser alterada e
fica salva nas preferências locais do app. A tela e as mensagens estão em
português.

O alvo gerado e validado nesta máquina é Linux desktop. A camada de conexão usa
HTTP/WebSocket padrão e pode ser reutilizada por Android; o build Android ainda
não foi validado neste ambiente.

## Executar

Com o backend iniciado em `127.0.0.1:8750`:

```bash
cd app_flutter
flutter run -d linux
```

Para outro endereço, use a engrenagem no topo. No Android, informe o endereço
alcançável do backend (por exemplo, IP da rede privada); `127.0.0.1` aponta para
o próprio telefone.

## Validação

Na pasta `app_flutter/`: `flutter analyze`, `flutter test` e `flutter build
linux`. A integração WebSocket foi exercitada contra o backend real com o
provedor `fake`, confirmando os eventos de token e a persistência do histórico.

# Chat Flutter

Cliente desktop Flutter para o backend local do assistente.

## Requisitos no Linux

- Flutter e toolchain desktop GTK.
- Serviço Secret Service ativo (GNOME Keyring ou KDE Wallet) para armazenar o
  token da API no cofre do usuário.
- `aplay` ou `ffplay` para reproduzir WAV; a captura usa `pw-record`.

O app abre por padrão `http://127.0.0.1:8750`. Em **Configurar conexão**, ajuste
o endereço do backend e informe o `CHAT_API_TOKEN` quando a autenticação estiver
habilitada. O endereço fica nas preferências do app e o token vai para o cofre
de credenciais do desktop.

## Desenvolvimento e validação

```bash
flutter pub get
flutter analyze
flutter test
flutter build linux --release
```

No desktop Linux, a dependência `flutter_secure_storage_linux_secret_service`
usa o protocolo Secret Service via D-Bus sem precisar compilar `libsecret`.

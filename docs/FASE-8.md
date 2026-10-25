# Fase 8 — telas Flutter e configuração (MVP)

## Entrega

- O menu do app abre telas de desejos, memórias e dispositivos, com cadastro e
  ações de atualização/exclusão.
- A tela de dispositivos pede confirmação antes de enviar Wake-on-LAN.
- A tela Modelo e voz consulta o backend, salva provider/modelo e mostra o
  estado de STT, TTS, busca e agente.
- O token de acesso do backend é salvo no cofre de credenciais do sistema; o
  endereço do backend continua salvo nas preferências do app.
- A API agora oferece CRUD de desejos e persistência do provider/modelo ativo
  na tabela `settings`; os valores são restaurados na inicialização.

## Limite desta fase

O app ainda não tem autenticação por usuário/dispositivo, localização completa
nem edição de todos os campos. As telas passaram por `flutter analyze`, teste de
widget e build Linux; as APIs associadas passaram pelos testes do backend. O
acesso deve permanecer restrito ao backend local até a fase remota ser protegida.

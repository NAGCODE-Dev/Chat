# Fase 7 — dispositivos e Wake-on-LAN (parcial)

## Entrega

- Cadastro local de dispositivos com MAC normalizado e IPv4 opcional.
- Construtor e transmissor de magic packet UDP, com validação de MAC, broadcast
  e porta.
- Endpoints `GET/POST/DELETE /api/devices` e
  `POST /api/devices/{id}/wake`; a rota de ativação exige `confirmed: true`.
- Ferramenta `device_list` (leitura) e `device_wake` (confirmação no chat), com
  auditoria. O retorno deixa claro que enviar o pacote não prova que o aparelho
  iniciou.

## Limite desta fase

Tailscale não está instalado neste ambiente, então túnel, autenticação entre
dispositivos e verificação de conectividade remota não foram configurados. Não
há um MAC alvo conhecido para testar o despertar real. O pacote e a confirmação
são cobertos por testes locais sem transmitir tráfego WOL real. Ruff e os testes
do backend passaram; a lista de dispositivos, validação do MAC e confirmação
foram exercitadas com o transmissor substituído por um mock.

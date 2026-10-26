# Prompt para exportar memórias do ChatGPT

Use este prompt em uma conversa nova do ChatGPT para gerar um JSON compatível
com **Memórias → Importar do ChatGPT** no app.

## Prompt

Copie o bloco abaixo inteiro:

```text
Você vai preparar um dump das memórias que você tem sobre mim para eu importar em outro assistente pessoal. Use apenas informações que você realmente possui em memória ou em conversas anteriores. Não invente, não deduza, não complete lacunas e não repita o que eu disser agora. Se não houver informação suficiente sobre algo, omita.

Responda SOMENTE com JSON válido, sem markdown, sem comentários e sem texto antes ou depois, neste formato exato:

{"memories":[{"kind":"personal","key":"cidade","content":"Moro em ..."},{"kind":"preference","key":"estilo-de-resposta","content":"Prefiro respostas curtas e diretas."}]}

Regras:
- kind deve ser um de: personal, preference, project, fact.
- personal: identidade, rotina, relações, saúde, localização.
- preference: gostos, desgostos, estilo de comunicação, ferramentas favoritas.
- project: projetos, objetivos, estudos, trabalho, clientes, apps que estou construindo.
- fact: fatos estáveis que não se encaixam nas outras categorias.
- key: identificador curto e único, em minúsculas, sem espaços (use hífens), máximo 60 caracteres.
- content: uma frase completa em português, específica e autossuficiente, máximo 300 caracteres. Uma informação por item.
- Não duplique informações. Mescle itens repetidos.
- Priorize o que é útil para um assistente pessoal: como me chamar, onde moro, o que faço, meus projetos, preferências, rotina, restrições e objetivos.
- Não inclua senhas, tokens, chaves de API, números de cartão, documentos, dados bancários, endereço exato nem outros segredos. Se algo for sensível, omita.
- Se você só tiver pouca informação, devolva poucos itens. Não invente para chegar a um número.
- Gere no máximo 60 itens.
```

## Como importar

1. Abra o app do Chat.
2. Abra o menu lateral e entre em **Memórias**.
3. Toque em **Importar do ChatGPT**.
4. Cole o JSON retornado pelo ChatGPT e confirme em **Importar**.
5. Opcional: toque em **Indexar** para gerar os embeddings e melhorar a busca
   semântica. A busca por texto (FTS5) já funciona sem esse passo.

## Se o ChatGPT não devolver JSON limpo

- Remova as crases de bloco (` ```json ` e ` ``` `) antes de colar. O
  importador só reconhece JSON quando o texto começa com `{`.
- Se vier uma lista com marcadores, ela também funciona: o importador aceita
  uma memória por linha e classifica o tipo automaticamente.
- Se o ChatGPT disser que não tem acesso às memórias, confira em
  **Configurações → Personalização → Memória** se o recurso está ativado.
- Revise o JSON antes de importar e apague qualquer informação que você não
  queira guardar no banco local.

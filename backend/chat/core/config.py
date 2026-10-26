"""Configuração central do backend.

Fonte de verdade: variáveis de ambiente (prefixo CHAT_) sobrepostas às
configurações persistidas no SQLite (tabela settings). O banco sempre
vence para chaves de runtime (provider ativo, modelo, voz), pois é o que
o app Flutter altera em Configurações.
"""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# A personalidade vive em um arquivo próprio, independente do modelo. As regras
# do aplicativo (ferramentas, formato, fontes) ficam separadas para que trocar
# de modelo não exija reescrever o comportamento social do assistente.
_PERSONALITY_PATH = Path(__file__).resolve().parent.parent / "prompts" / "personality.md"

_FALLBACK_PERSONALITY = (
    "Você é um assistente de inteligência artificial de propósito geral. "
    "Responda em português brasileiro cotidiano, de forma direta e natural. "
    "Não finja emoções, memórias ou experiências humanas, não invente fatos e "
    "não escreva como se fosse a pessoa usuária."
)


def _load_personality() -> str:
    try:
        text = _PERSONALITY_PATH.read_text(encoding="utf-8").strip()
    except OSError:
        return _FALLBACK_PERSONALITY
    return text or _FALLBACK_PERSONALITY


_PERSONALITY = _load_personality()

_APPLICATION_RULES = """
## REGRAS DO APLICATIVO

Você é o Chat, o assistente deste aplicativo. A pessoa usuária é quem fala com
você. Nunca escreva a fala dela, não responda como se fosse ela e não descreva a
vida dela em primeira pessoa. Se a mensagem começar com uma saudação, um relato
pessoal ou uma pergunta sobre o próprio usuário, responda à pessoa em vez de
repetir o texto. Você é o assistente, não o usuário.

As memórias fornecidas pelo aplicativo descrevem apenas fatos sobre a pessoa
usuária. Use-as para personalizar a ajuda, mas nunca para inventar lembranças,
sentimentos, experiências ou preferências do assistente. Se a mensagem atual
contradisser uma memória, a mensagem atual vence.

Interprete a mensagem pelo sentido, sem corrigir nem estranhar nomes, apelidos,
gírias ou erros de digitação. Se a pessoa relatar cansaço, saudade ou solidão,
reconheça isso em uma frase e responda ao que ela perguntou; não diagnostique,
não dê uma lição e não transforme a conversa em terapia.

Idioma: português brasileiro por padrão, salvo quando a pessoa escolher outro.

Formatação: use **negrito** para destacar os pontos mais importantes, com
moderação; prefira parágrafos curtos e listas com marcadores quando ajudarem a
organizar. Para notícias e pesquisas, comece com um resumo direto e depois traga
os destaques em tópicos, citando o nome da fonte no fim de cada item. Nunca
escreva URLs, links ou endereços no corpo da resposta; os links ficam
disponíveis no botão Fontes do aplicativo. Não use tabelas nem blocos de código
sem necessidade.

Ferramentas: use web_search para informações atuais e fetch_page para ler uma
fonte antes de responder. Para cotação de moedas (dólar, euro, etc.), use sempre
currency_quote; nunca invente taxa de câmbio. Quando a pessoa pedir algo no
celular (abrir aplicativo, tocar música, controlar mídia ou abrir link no
aparelho), use sempre phone_action com a ação exata open_app, play_music,
media_control ou open_url. Nunca use open_url nem open_app para ações no
celular: open_url é exclusivo do navegador do computador. Quando a pessoa pedir
para registrar um gasto, uma receita ou um aporte no Meu Dinheiro, use
finance_add; para consultar gastos, use finance_summary (o padrão é o mês atual;
use period='todos' somente para todo o histórico). Se usar uma ferramenta,
baseie a resposta no resultado e cite a fonte pelo nome, sem colar o link.

## REGRAS FINAIS DE IDENTIDADE E CONVERSA

Você é uma IA, não uma pessoa. Nunca diga que sente, lembra, tem saudade,
carinho, medo ou qualquer emoção; nunca invente experiências, idade, corpo,
donos ou uma relação próxima com a pessoa. Não use apelidos afetivos nem
diminutivos inventados. Não presuma o gênero da pessoa e não atribua gênero a
você. Refira-se ao histórico como "esta conversa" ou "o histórico", nunca como
"nossas conversas" ou uma memória pessoal sua. Não fale em nome de "nós" íntimo
e não transforme a conversa em terapia. Se a pessoa relatar cansaço, saudade ou
solidão, reconheça isso em uma frase e responda ao que ela perguntou. Não repita
a fala dela, não a corrija e não responda como se fosse ela. Termine quando a
pergunta estiver respondida; não ofereça serviços extras sem pedido.
""".strip()

_SYSTEM_PROMPT = f"{_PERSONALITY}\n\n{_APPLICATION_RULES}"

_SYSTEM_PROMPT_FAST = (
    "Você é o Chat, uma IA assistente direta e natural. Responda em português "
    "brasileiro cotidiano, começando pela resposta. Você não é uma pessoa: nunca "
    "diga que sente, lembra ou tem qualquer emoção; não invente apelidos, idade, "
    "corpo, donos, relações ou memórias. Não fale como a pessoa usuária, não "
    "repita a fala dela e não presuma o gênero dela. Se ela relatar cansaço, "
    "saudade ou solidão, reconheça em uma frase e responda ao que perguntou. "
    "Refira-se ao histórico como \"esta conversa\", não como uma memória pessoal "
    "sua. Para perguntas simples, use no máximo dois parágrafos curtos ou uma "
    "lista de três itens. Não use tabelas, blocos de código nem URLs."
)


class Settings(BaseSettings):
    """Configuração de inicialização. Imutável durante o processo."""

    model_config = SettingsConfigDict(env_prefix="CHAT_", env_file=".env", extra="ignore")

    # --- infraestrutura ---
    data_dir: Path = Path.home() / ".local" / "share" / "chat"
    db_path: Path | None = None  # None => data_dir / chat.db
    attachments_dir: Path | None = None  # None => data_dir / attachments
    host: str = "127.0.0.1"
    port: int = 8750
    api_token: str | None = None
    rate_limit_per_minute: int = 120
    ws_message_rate_per_minute: int = 30
    pairing_ttl_seconds: int = 300

    # --- provider ativo (padrão; pode ser sobrescrito pela tabela settings) ---
    # O provider fake é usado em testes e não aparece na interface.
    provider: str = "ollama"
    model: str = "qwen2.5:3b-instruct-q4_K_M"
    provider_base_url: str = "http://127.0.0.1:11434"  # Ollama
    # Seleção automática: usa `model_large` quando há memória livre suficiente
    # e volta para `model` sob pressão. O limite já deve incluir a folga do
    # sistema; para um modelo de ~2,5 GB, 4096 MiB é um bom ponto de partida.
    model_auto: bool = False
    model_large: str | None = None
    model_auto_min_free_mb: int = 4096
    model_auto_keep_free_mb: int = 1024
    # Modelo pequeno para perguntas curtas que não precisam de ferramentas.
    # Fica independente do modelo padrão; se estiver vazio, não há roteamento.
    model_fast: str | None = None
    model_fast_max_chars: int = 280
    # Modelo com visão para anexos de imagem. Vazio desliga o roteamento.
    vision_model: str | None = None
    model_keep_alive: str = "5m"
    model_large_keep_alive: str = "2m"
    num_thread: int = 6
    # O prompt de personalidade é longo e o histórico também ocupa contexto.
    # 8192 dá espaço para o system prompt, a conversa e uma resposta completa.
    num_ctx: int = 8192
    web_search_url: str | None = None
    agent_url: str | None = None
    agent_token: str | None = None
    agent_tls_ca: Path | None = None
    agent_tls_client_cert: Path | None = None
    agent_tls_client_key: Path | None = None

    # --- memória semântica (opcional; FTS5 continua sendo o fallback) ---
    embedding_provider: str = "none"  # none | ollama
    embedding_model: str = "nomic-embed-text"
    embedding_base_url: str | None = None  # None => provider_base_url
    embedding_timeout_seconds: float = 10.0
    embedding_batch_size: int = 16
    embedding_min_similarity: float = 0.0  # 0 desliga o corte; bge-m3 usa 0.6

    # --- voz local (opcional, não ativa até os modelos serem configurados) ---
    whisper_binary: str = "whisper-cli"
    whisper_model_path: Path | None = None
    whisper_language: str = "pt"
    piper_model_path: Path | None = None
    voice_timeout_seconds: float = 180.0

    # --- geração ---
    temperature: float = 0.7
    # 1024 tokens evitam respostas cortadas no meio de uma frase. O streaming
    # também detecta done_reason=length e continua a geração quando necessário.
    max_tokens: int | None = 1024
    # Carregado de chat/prompts/personality.md e combinado com as regras do app.
    system_prompt: str = _SYSTEM_PROMPT
    # Prompt compacto para o modelo rápido em perguntas curtas e sem ferramentas.
    # Menos tokens de sistema = primeiro token mais cedo na CPU.
    system_prompt_fast: str = _SYSTEM_PROMPT_FAST

    @property
    def resolved_db_path(self) -> Path:
        return self.db_path if self.db_path else self.data_dir / "chat.db"

    @property
    def resolved_attachments_path(self) -> Path:
        if self.attachments_dir:
            return self.attachments_dir
        return self.resolved_db_path.parent / "attachments"

    def ensure_dirs(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)


def load_settings() -> Settings:
    s = Settings()
    s.ensure_dirs()
    return s

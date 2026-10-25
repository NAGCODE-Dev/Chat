"""Configuração central do backend.

Fonte de verdade: variáveis de ambiente (prefixo CHAT_) sobrepostas às
configurações persistidas no SQLite (tabela settings). O banco sempre
vence para chaves de runtime (provider ativo, modelo, voz), pois é o que
o app Flutter altera em Configurações.
"""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuração de inicialização. Imutável durante o processo."""

    model_config = SettingsConfigDict(env_prefix="CHAT_", env_file=".env", extra="ignore")

    # --- infraestrutura ---
    data_dir: Path = Path.home() / ".local" / "share" / "chat"
    db_path: Path | None = None  # None => data_dir / chat.db
    host: str = "127.0.0.1"
    port: int = 8750
    api_token: str | None = None
    rate_limit_per_minute: int = 120
    ws_message_rate_per_minute: int = 30
    pairing_ttl_seconds: int = 300

    # --- provider ativo (padrão; pode ser sobrescrito pela tabela settings) ---
    provider: str = "fake"
    model: str = "fake-model"
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
    model_keep_alive: str = "5m"
    model_large_keep_alive: str = "2m"
    num_thread: int = 6
    num_ctx: int = 2048
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
    max_tokens: int | None = None
    system_prompt: str = (
        "Você é o Chat, um assistente pessoal próximo e caloroso. Fale em "
        "português brasileiro com naturalidade, como numa conversa de verdade: "
        "frases curtas, tom humano, sem formalidade excessiva e sem parecer um "
        "relatório. Você pode conversar sobre qualquer assunto, inclusive vida, "
        "sentimentos, ideias, relações e o dia a dia; não transforme toda conversa "
        "em tarefa. Quando fizer sentido, faça uma pergunta curta de acompanhamento "
        "e use o que você lembra da pessoa para personalizar a resposta.\n\n"
        "Estilo: use **negrito** para destacar os pontos mais importantes, com "
        "moderação; prefira parágrafos curtos e listas com marcadores quando "
        "ajudarem a organizar. Para notícias e pesquisas, comece com um resumo "
        "direto e depois traga os destaques em tópicos, citando o nome da fonte no "
        "fim de cada item. Nunca escreva URLs, links ou endereços no corpo da "
        "resposta; os links ficam disponíveis no botão Fontes do aplicativo. Não "
        "use tabelas nem blocos de código sem necessidade.\n\n"
        "Ferramentas: use web_search para informações atuais e fetch_page para ler "
        "uma fonte antes de responder. Para cotação de moedas (dólar, euro, etc.), "
        "use sempre currency_quote; nunca invente taxa de câmbio. Quando a pessoa "
        "pedir algo no celular (abrir aplicativo, tocar música, controlar mídia ou "
        "abrir link no aparelho), use sempre phone_action com a ação exata open_app, "
        "play_music, media_control ou open_url. Nunca use open_url nem open_app para "
        "ações no celular: open_url é exclusivo do navegador do computador. Quando "
        "a pessoa pedir para registrar um gasto, uma receita ou um aporte no Meu "
        "Dinheiro, use finance_add; para consultar gastos, use finance_summary (o "
        "padrão é o mês atual; use period='todos' somente para todo o histórico). "
        "Se usar uma ferramenta, baseie a resposta no resultado e cite a fonte pelo "
        "nome, sem colar o link."
    )

    @property
    def resolved_db_path(self) -> Path:
        return self.db_path if self.db_path else self.data_dir / "chat.db"

    def ensure_dirs(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)


def load_settings() -> Settings:
    s = Settings()
    s.ensure_dirs()
    return s

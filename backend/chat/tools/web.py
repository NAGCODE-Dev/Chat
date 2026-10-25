"""Busca web, leitura de páginas e abertura segura de links.

A busca usa SearXNG quando ``CHAT_WEB_SEARCH_URL`` está configurada. Sem essa
variável, cai para o Bing em HTML — sem chave de API e suficiente para uso
pessoal. Pedidos de notícias usam o RSS do Bing Notícias, que devolve matérias
específicas com veículo e data. Resultados externos são sempre tratados como
dados não confiáveis pelo serviço de conversa.
"""

from __future__ import annotations

import asyncio
import base64
import ipaddress
import re
import socket
import unicodedata
import webbrowser
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from html import unescape
from html.parser import HTMLParser
from typing import ClassVar
from urllib.parse import parse_qs, urlparse

import httpx
from pydantic import Field, field_validator

from chat.tools.base import Permission, Tool, ToolArguments, ToolError, ToolResult

_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
_MAX_PAGE_BYTES = 2_000_000
_MAX_PAGE_CHARS = 12_000
_URL_RE = re.compile(r"https?://\S+|www\.\S+", re.IGNORECASE)


def _strip_urls(value: str) -> str:
    """Remove links do texto; os links ficam apenas nos metadados de fonte."""
    cleaned = _URL_RE.sub("", value)
    cleaned = re.sub(r"[ \t]+([,.;:!?])", r"\1", cleaned)
    return cleaned.strip()


class WebSearchArgs(ToolArguments):
    query: str = Field(min_length=2, max_length=300)
    max_results: int = Field(default=5, ge=1, le=10)


def _decode_bing_url(href: str) -> str:
    """Decodifica o redirecionador ``bing.com/ck/a?...&u=a1<base64>``."""
    if href.startswith(("http://", "https://")) and "bing.com/ck/a" not in href:
        return href
    parsed = urlparse(href)
    value = parse_qs(parsed.query).get("u", [""])[0]
    value = value.removeprefix("a1")
    if not value:
        return href
    padding = "=" * (-len(value) % 4)
    try:
        decoded = base64.urlsafe_b64decode(value + padding).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return href
    return decoded if decoded.startswith(("http://", "https://")) else href


class _BingResultsParser(HTMLParser):
    """Extrai títulos, URLs e trechos dos resultados orgânicos do Bing."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.results: list[dict[str, str]] = []
        self._in_result = False
        self._li_depth = 0
        self._in_title = False
        self._in_snippet = False
        self._current: dict[str, list[str] | str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        classes = (attributes.get("class") or "").split()
        if tag == "li" and "b_algo" in classes:
            self._in_result = True
            self._li_depth = 1
            self._current = {"title": [], "url": "", "snippet": []}
            return
        if not self._in_result or self._current is None:
            return
        if tag == "li":
            self._li_depth += 1
        elif tag == "h2":
            self._in_title = True
        elif tag == "a" and self._in_title and not self._current["url"]:
            self._current["url"] = attributes.get("href") or ""
        elif tag == "p":
            self._in_snippet = True

    def handle_endtag(self, tag: str) -> None:
        if not self._in_result or self._current is None:
            return
        if tag == "h2":
            self._in_title = False
        elif tag == "p":
            self._in_snippet = False
        elif tag == "li":
            self._li_depth -= 1
            if self._li_depth <= 0:
                self._finish()

    def handle_data(self, data: str) -> None:
        if not self._in_result or self._current is None:
            return
        if self._in_title:
            title = self._current["title"]
            assert isinstance(title, list)
            title.append(data)
        elif self._in_snippet:
            snippet = self._current["snippet"]
            assert isinstance(snippet, list)
            snippet.append(data)

    def _finish(self) -> None:
        assert self._current is not None
        title = " ".join("".join(self._current["title"]).split())  # type: ignore[arg-type]
        snippet = " ".join("".join(self._current["snippet"]).split())  # type: ignore[arg-type]
        url = _decode_bing_url(str(self._current["url"]))
        if title and url:
            self.results.append({"title": title, "url": url, "snippet": snippet})
        self._in_result = False
        self._current = None


def parse_bing_results(html: str) -> list[dict[str, str]]:
    parser = _BingResultsParser()
    parser.feed(html)
    return parser.results


_NEWS_HINTS = ("noticia", "manchete")
_NEWS_FILLER = {
    "a", "as", "o", "os", "um", "uma", "de", "da", "das", "do", "dos",
    "em", "na", "nas", "no", "nos", "para", "por", "com", "e", "ou",
    "me", "mostre", "mostra", "traga", "quero", "queria", "ver", "veja",
    "pesquise", "pesquisa", "pesquisar", "busque", "busca", "buscar",
    "procure", "procurar", "quais", "qual", "sobre", "hoje", "agora",
    "ultima", "ultimas", "ultimo", "ultimos", "principal", "principais",
    "recente", "recentes", "noticia", "noticias", "manchete", "manchetes",
    "de hoje", "do dia", "do momento",
}


def _fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(
        char for char in normalized if not unicodedata.combining(char)
    ).casefold()


def is_news_query(query: str) -> bool:
    """Identifica pedidos de notícias sem confundir com conversa sobre notícia."""
    folded = _fold(query)
    if not any(hint in folded for hint in _NEWS_HINTS):
        return False
    request_hints = (
        "pesquise", "pesquisa", "busque", "busca", "procure", "mostre",
        "quais", "ultimas", "ultimos", "manchetes", "me traga", "quero ver",
        "noticias de", "noticias sobre", "noticias do", "noticias da",
        "noticias hoje", "noticias atuais", "noticias recentes",
    )
    return any(hint in folded for hint in request_hints)


def news_topic(query: str) -> str:
    """Limpa o pedido e deixa só o assunto pesquisável.

    "Pesquise notícias de tecnologia de hoje" vira "tecnologia"; sem assunto,
    usa "notícias" para trazer as manchetes do dia.
    """
    words: list[str] = []
    for token in re.findall(r"[^\W_]+", query, flags=re.UNICODE):
        if _fold(token) in _NEWS_FILLER:
            continue
        if token.casefold() not in words:
            words.append(token.casefold())
    return " ".join(words[:8]) or "notícias"


def _decode_bing_news_url(href: str) -> str:
    """Extrai a URL do veículo do redirecionador ``bing.com/news/apiclick``."""
    if "bing.com/news/apiclick" not in href:
        return href
    target = parse_qs(urlparse(href).query).get("url", [""])[0].strip()
    return target if target.startswith(("http://", "https://")) else href


def _news_date(value: str) -> tuple[datetime | None, str]:
    """Converte a data RFC 822 do RSS para o fuso local do servidor."""
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None, ""
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    local = parsed.astimezone()
    return local, local.strftime("%d/%m/%Y %H:%M")


def parse_bing_news_rss(xml_text: str) -> list[dict[str, str]]:
    """Extrai matérias do RSS do Bing Notícias sem manter URLs no texto."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as error:
        raise ValueError(f"RSS de notícias inválido: {error}") from error
    results: list[dict[str, str]] = []
    for item in root.findall("./channel/item"):
        title = " ".join((item.findtext("title") or "").split())
        href = (item.findtext("link") or "").strip()
        url = _decode_bing_news_url(href)
        if not title or not url.startswith(("http://", "https://")):
            continue
        description = html_to_text(item.findtext("description") or "")
        snippet = " ".join(description.split())[:420]
        publisher = ""
        for child in item:
            if child.tag.rsplit("}", 1)[-1].casefold() == "source":
                publisher = " ".join((child.text or "").split())
                break
        if not publisher:
            publisher = (urlparse(url).hostname or "").removeprefix("www.")
        _, published = _news_date(item.findtext("pubDate") or "")
        results.append(
            {
                "title": title,
                "url": url,
                "snippet": snippet,
                "source": publisher,
                "published": published,
            }
        )
    return results


class _TextExtractor(HTMLParser):
    """Converte HTML em texto legível, descartando scripts e estilos."""

    _SKIP: ClassVar[set[str]] = {"script", "style", "noscript", "svg", "canvas", "template"}
    _BLOCK: ClassVar[set[str]] = {
        "p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6",
        "article", "section", "header", "footer", "main",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._SKIP:
            self._skip_depth += 1
        elif tag in self._BLOCK:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in self._SKIP and self._skip_depth:
            self._skip_depth -= 1
        elif tag in self._BLOCK:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth == 0:
            self.parts.append(data)


def html_to_text(html: str) -> str:
    parser = _TextExtractor()
    parser.feed(html)
    text = unescape("".join(parser.parts))
    text = re.sub(r"[ \t\f\v]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text)
    return text.strip()


async def _ensure_public_url(url: str) -> None:
    """Bloqueia localhost e faixas privadas para evitar SSRF."""
    parsed = urlparse(url)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
    ):
        raise ToolError("URL deve usar HTTP/HTTPS e não pode conter credenciais.")
    try:
        infos = await asyncio.to_thread(
            socket.getaddrinfo, parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80)
        )
    except OSError as error:
        raise ToolError(f"Não foi possível resolver o endereço: {error}") from error
    for info in infos:
        address = ipaddress.ip_address(info[4][0])
        if (
            address.is_private
            or address.is_loopback
            or address.is_link_local
            or address.is_reserved
            or address.is_multicast
            or address.is_unspecified
        ):
            raise ToolError("URL aponta para um endereço interno e foi bloqueada.")


class WebSearch(Tool):
    name = "web_search"
    description = (
        "Pesquisa informações atuais na internet. Use quando a pessoa pedir "
        "notícias, previsão do tempo, fatos recentes ou algo que você não saiba."
    )
    permission = Permission.SAFE
    arguments_model = WebSearchArgs

    def __init__(self, base_url: str | None = None):
        self.base_url = base_url.rstrip("/") if base_url else None

    async def run(self, arguments: dict) -> ToolResult:
        if self.base_url:
            return await self._search_searxng(arguments)
        if is_news_query(arguments["query"]):
            return await self._search_bing_news(arguments)
        return await self._search_bing(arguments)

    async def _search_searxng(self, arguments: dict) -> ToolResult:
        assert self.base_url is not None
        parsed = urlparse(self.base_url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username:
            return ToolResult("URL base de busca inválida.", False)
        try:
            async with httpx.AsyncClient(timeout=12, follow_redirects=False) as client:
                response = await client.get(
                    f"{self.base_url}/search",
                    params={"q": arguments["query"], "format": "json"},
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            return ToolResult(f"Falha na busca web: {exc}", False)
        raw_results = response.json().get("results", [])[: arguments["max_results"]]
        results = [
            {
                "title": str(item.get("title", "")).strip(),
                "url": str(item.get("url", "")).strip(),
                "snippet": str(item.get("content", "")).strip(),
            }
            for item in raw_results
            if isinstance(item, dict)
        ]
        return self._format(results)

    async def _search_bing(self, arguments: dict) -> ToolResult:
        try:
            async with httpx.AsyncClient(
                timeout=15,
                follow_redirects=True,
                headers={
                    "User-Agent": _USER_AGENT,
                    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
                },
            ) as client:
                response = await client.get(
                    "https://www.bing.com/search",
                    params={
                        "q": arguments["query"],
                        "setlang": "pt-br",
                        "cc": "br",
                    },
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            return ToolResult(f"Falha na busca web: {exc}", False)
        results = parse_bing_results(response.text)[: arguments["max_results"]]
        return self._format(results)

    async def _search_bing_news(self, arguments: dict) -> ToolResult:
        topic = news_topic(arguments["query"])
        try:
            async with httpx.AsyncClient(
                timeout=15,
                follow_redirects=True,
                headers={
                    "User-Agent": _USER_AGENT,
                    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
                },
            ) as client:
                response = await client.get(
                    "https://www.bing.com/news/search",
                    params={
                        "q": topic,
                        "format": "rss",
                        "setlang": "pt-br",
                        "cc": "br",
                        "qft": 'sortbydate="1"',
                    },
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            return ToolResult(f"Falha na busca de notícias: {exc}", False)
        try:
            results = parse_bing_news_rss(response.text)[: arguments["max_results"]]
        except ValueError as error:
            return ToolResult(str(error), False)
        return self._format(results, data=results)

    @staticmethod
    def _format(
        results: list[dict[str, str]],
        *,
        data: list[dict[str, str]] | None = None,
    ) -> ToolResult:
        if not results:
            return ToolResult("Nenhum resultado encontrado.")
        lines = []
        sources: list[dict[str, str]] = []
        seen: set[str] = set()
        for index, item in enumerate(results, start=1):
            title = _strip_urls(item.get("title", "").strip())
            url = item.get("url", "").strip()
            snippet = _strip_urls(item.get("snippet", "").strip())
            source = _strip_urls(item.get("source", "").strip())
            published = item.get("published", "").strip()
            details = " · ".join(part for part in (source, published) if part)
            heading = f"{title} ({details})" if details else title
            lines.append(f"{index}. {heading}\n   {snippet}")
            if url and url not in seen:
                seen.add(url)
                source_title = f"{source}: {title}" if source else title
                sources.append(
                    {
                        "title": source_title or url,
                        "url": url,
                        "snippet": snippet,
                    }
                )
        return ToolResult("\n".join(lines), sources=sources, data=data)


def _page_title(html: str, fallback: str) -> str:
    match = re.search(r"<title[^>]*>(.*?)</title>", html, re.IGNORECASE | re.DOTALL)
    if not match:
        return fallback
    title = html_to_text(match.group(1)).strip()
    return title[:200] or fallback


class FetchPageArgs(ToolArguments):
    url: str = Field(min_length=8, max_length=2048)
    max_chars: int = Field(default=6000, ge=500, le=_MAX_PAGE_CHARS)


class FetchPage(Tool):
    name = "fetch_page"
    description = (
        "Abre uma página HTTP/HTTPS e devolve o texto principal. Use depois de "
        "web_search para ler uma fonte antes de responder."
    )
    permission = Permission.SAFE
    arguments_model = FetchPageArgs

    async def run(self, arguments: dict) -> ToolResult:
        current = arguments["url"]
        try:
            async with httpx.AsyncClient(
                timeout=15,
                follow_redirects=False,
                headers={
                    "User-Agent": _USER_AGENT,
                    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
                },
            ) as client:
                response: httpx.Response | None = None
                for _ in range(4):
                    await _ensure_public_url(current)
                    response = await client.get(current)
                    if response.is_redirect:
                        location = response.headers.get("location", "")
                        if not location:
                            break
                        current = str(response.url.join(location))
                        continue
                    break
                if response is None:
                    return ToolResult("Não foi possível abrir a página.", False)
                response.raise_for_status()
        except ToolError as error:
            return ToolResult(str(error), False)
        except httpx.HTTPError as exc:
            return ToolResult(f"Falha ao abrir a página: {exc}", False)

        content_type = response.headers.get("content-type", "")
        raw = response.content[:_MAX_PAGE_BYTES]
        decoded = raw.decode(response.encoding or "utf-8", errors="replace")
        if "html" in content_type.lower() or raw.lstrip().startswith(b"<"):
            text = html_to_text(decoded)
            title = _page_title(decoded, current)
        else:
            text = decoded
            title = current
        text = _strip_urls(text)[: arguments["max_chars"]].strip()
        if not text:
            return ToolResult("A página não contém texto legível.", False)
        return ToolResult(
            text,
            sources=[
                {
                    "title": title,
                    "url": current,
                    "snippet": text[:280],
                }
            ],
        )


class OpenURLArgs(ToolArguments):
    url: str = Field(min_length=8, max_length=2048)

    @field_validator("url")
    @classmethod
    def valid_http_url(cls, value: str) -> str:
        parsed = urlparse(value)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("URL deve usar HTTP/HTTPS e não pode conter credenciais")
        return value


class OpenURL(Tool):
    name = "open_url"
    description = (
        "Abre um link HTTP/HTTPS no navegador do computador. Use apenas para "
        "pedidos no desktop; no celular, use phone_action com action=open_url."
    )
    permission = Permission.CONFIRM
    arguments_model = OpenURLArgs

    async def run(self, arguments: dict) -> ToolResult:
        opened = await asyncio.to_thread(webbrowser.open, arguments["url"], new=2)
        return ToolResult("Link enviado ao navegador." if opened else "Não foi possível abrir o navegador.", bool(opened))

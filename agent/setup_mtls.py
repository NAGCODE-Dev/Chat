"""Gera CA e certificados locais para mTLS entre backend e agente."""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path


def run(*args: str) -> None:
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    config = Path.home() / ".config/chat-agent"
    tls = config / "tls"
    env_file = config / "agent.env"
    old = {}
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                old[k] = v
    if len(old.get("CHAT_AGENT_TOKEN", "")) < 32:
        raise SystemExit("CHAT_AGENT_TOKEN ausente ou curto; configure-o antes de gerar mTLS.")
    config.mkdir(parents=True, exist_ok=True, mode=0o700)
    tls.mkdir(mode=0o700)
    os.chmod(config, 0o700)
    if any(tls.iterdir()):
        raise SystemExit(f"Diretório não vazio; preservado: {tls}")
    with tempfile.TemporaryDirectory(prefix="chat-mtls-") as temp:
        work = Path(temp)
        ca_key, ca_cert = work / "ca.key", work / "ca.crt"
        run("openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-keyout", str(ca_key), "-out", str(ca_cert), "-days", "3650", "-subj", "/CN=Chat Local Agent CA", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign")
        for name, usage in (("server", "serverAuth"), ("client", "clientAuth")):
            key, csr, cert = work / f"{name}.key", work / f"{name}.csr", work / f"{name}.crt"
            run("openssl", "req", "-new", "-newkey", "rsa:3072", "-nodes", "-keyout", str(key), "-out", str(csr), "-subj", f"/CN=chat-{name}")
            ext = work / f"{name}.ext"
            contents = f"extendedKeyUsage={usage}\n" + ("subjectAltName=DNS:localhost,IP:127.0.0.1\n" if name == "server" else "")
            ext.write_text(contents)
            run("openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca_cert), "-CAkey", str(ca_key), "-CAcreateserial", "-out", str(cert), "-days", "825", "-extfile", str(ext))
            for source, target in ((key, tls / f"{name}.key"), (cert, tls / f"{name}.crt")):
                target.write_bytes(source.read_bytes())
        (tls / "ca.crt").write_bytes(ca_cert.read_bytes())
    os.chmod(tls, 0o700)
    for file in tls.iterdir():
        os.chmod(file, 0o600)
    values = {
        "CHAT_AGENT_TLS_CA": str(tls / "ca.crt"),
        "CHAT_AGENT_TLS_SERVER_CERT": str(tls / "server.crt"),
        "CHAT_AGENT_TLS_SERVER_KEY": str(tls / "server.key"),
        "CHAT_AGENT_TLS_CLIENT_CERT": str(tls / "client.crt"),
        "CHAT_AGENT_TLS_CLIENT_KEY": str(tls / "client.key"),
        "CHAT_AGENT_URL": "https://127.0.0.1:8765",
    }
    old.update(values)
    env_file.write_text("".join(f"{key}={value}\n" for key, value in old.items()))
    os.chmod(env_file, 0o600)
    print(f"mTLS local configurado em {tls}; reinicie chat-agent.service e o backend.")


if __name__ == "__main__":
    main()

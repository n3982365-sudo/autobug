# AutoBug

Automated bug bounty platform — recon, vuln scan, proof-only exploitation, report, dashboard, Telegram, OSINT.

## Quickstart

    cp .env.example .env
    # edit .env — set POSTGRES_PASSWORD, MINIO_ROOT_PASSWORD, SECRET_KEY
    mkdir -p data
    echo '{"allowed":["scanme.nmap.org"]}' > data/scope.json
    docker compose build
    docker compose up -d

- UI: http://localhost:5173
- API: http://localhost:8000/docs
- MinIO: http://localhost:9001

## Scope guard

Any target not in `data/scope.json` is refused. Add only domains you own or are authorized to test.

## Add a plugin

    mkdir plugins/mytool
    # copy plugins/nmap/{manifest.yaml,runner.py} and edit
    docker compose restart api worker

## License

MIT

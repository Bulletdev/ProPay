```markdown
██████╗ ██████╗  ██████╗ ██████╗  █████╗ ██╗   ██╗
██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██████╔╝██║   ██║██████╔╝███████║ ╚████╔╝
██╔═══╝ ██╔══██╗██║   ██║██╔═══╝ ██╔══██║  ╚██╔╝
██║     ██║  ██║╚██████╔╝██║     ██║  ██║   ██║
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝   ╚═╝

             **Gateway de Pagamentos - ProStaff Ecosystem**
```

[![Ruby Version](https://img.shields.io/badge/ruby-3.4-CC342D?logo=ruby)](https://www.ruby-lang.org/)
[![Roda](https://img.shields.io/badge/roda-3.103-CC342D)](https://roda.jeremyevans.net/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue?logo=postgresql)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7-red?logo=redis)](https://redis.io/)
[![Sidekiq](https://img.shields.io/badge/Sidekiq-7-B1003E?logo=sidekiq)](https://sidekiq.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

---

```
╔══════════════════════════════════════════════════════════════════════════╗
║  PROPAY - Roda / Iodine (Ruby 3.4)                                       ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Gateway de pagamentos proprietário do ecossistema ProStaff.             ║
║  PIX único · PIX recorrente · Carteira interna · Prize pool · p95 < 50ms ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

**KEY FEATURES:**

- **PIX Único** - Geração de QR Code dinâmico (EMV/BR Code) via OpenPix
- **PIX Recorrente** - Protocolo COBR do BACEN via Efi para assinaturas automatizadas
- **Carteira Interna** - Saldo por usuário com débito/crédito atômico e auditoria completa
- **Assinaturas SaaS** - Planos Pro e Enterprise do ProStaff Analytics Hub com trial
- **Prize Pool** - Distribuição automática de prêmios dos campeonatos do ArenaBR
- **Reembolsos** - Cancelamento com crédito na carteira ou PIX de volta (CDC 7 dias)
- **Saques** - PIX de saída para chave cadastrada com validação BACEN
- **Webhooks** - Confirmação assíncrona de PIX em < 3s com HMAC-SHA256
- **Idempotência** - `Idempotency-Key` obrigatória + `end_to_end_id` UNIQUE no banco
- **Isolamento** - Todas as queries escopadas por `customer_id` (sem dados cruzados)
- **Rate Limiting** - Rack::Attack + Redis (30 req/min por IP)
- **Observabilidade** - Métricas Prometheus + endpoints `/health` e `/ready`
- **Alta Performance** - Iodine (event loop em C com epoll) + YJIT + `MALLOC_ARENA_MAX=2`
- **Banco próprio** - PostgreSQL 15 isolado (`propay-db`) na rede Coolify

**TABLE OF CONTENTS:**

- [01 · Quick Start](#quick-start)
- [02 · Technology Stack](#technology-stack)
- [03 · Architecture](#architecture)
- [04 · Setup](#setup)
- [05 · API Endpoints](#api-endpoints)
- [06 · Providers PIX](#providers-pix)
- [07 · Background Jobs](#background-jobs)
- [08 · Webhooks](#webhooks)
- [09 · Deployment](#deployment)
- [10 · Environment Variables](#environment-variables)

---

### QUICK START

**Docker (Recomendado):**

```bash
cp .env.example .env
# Edite .env → PROPAY_OPENPIX_APP_ID, PROPAY_OPENPIX_SECRET, PROPAY_PIX_KEY, INTERNAL_JWT_SECRET
docker compose up -d
curl http://localhost:5555/v1/health
# {"status":"ok","version":"1.0.0"}
```

**Local (sem Docker):**

```bash
cp .env.example .env
bundle install
bundle exec ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"
bundle exec iodine --yjit --yjit-exec-mem-size=8 -p 5555
```

API: `http://localhost:5555`  
Health: `http://localhost:5555/v1/health`

---

### TECHNOLOGY STACK

- **Language**: Ruby 3.4 com YJIT habilitado
- **Framework**: Roda 3.103 (tree routing, ~0.1ms overhead)
- **HTTP Server**: Iodine 0.7 (event loop em C com epoll)
- **JSON**: Oj 3.17 (3-5x mais rápido que stdlib)
- **ORM**: Sequel 5.75 + sequel_pg
- **Database**: PostgreSQL 15 (instância própria `propay-db`)
- **Cache / Locks**: Redis 7 + Redlock
- **HTTP Client**: HTTPX 1.3 (async)
- **Background Jobs**: Sidekiq 7
- **Validação**: dry-validation 1.10
- **Monitoramento**: Prometheus::Client

---

### ARCHITECTURE

**Posição no ecossistema ProStaff:**

```
INTERNET
    |
  Traefik (TLS - Let's Encrypt)
    |
    +-- api.prostaff.gg       → prostaff-api   (Rails,  :3000)
    +-- events.prostaff.gg    → prostaff-events (Phoenix, :4000)
    +-- scraper.prostaff.gg   → ProStaff-Scraper (FastAPI, :8000)
    +-- propay.prostaff.gg    → ProPay           (Roda,   :5555)

REDE DOCKER: coolify
    |
    +-- prostaff-api    → PostgreSQL, Redis, Meilisearch, Sidekiq
    +-- prostaff-events → Redis (compartilhado)
    +-- riot-gateway    → interno
    +-- propay          → propay-db (PostgreSQL próprio), Redis DB 1

FRONTENDS (Cloudflare Pages)
    +-- ArenaBR
    +-- Scrims.lol
    +-- ProStaff Analytics Hub
```

**Fluxo de pagamento (PIX único - ArenaBR):**

```
[Frontend] → POST /v1/wallet/deposit
                ↓
             ProPay cria Charge + OpenPix API
                ↓
             ← {qr_code, qr_code_url, txid}
                ↓
          [Usuário paga no banco]
                ↓
          OpenPix → POST /v1/webhooks/openpix
                ↓
          PixWebhookJob (Sidekiq)
                ↓
          WalletService.credit! (SELECT FOR UPDATE)
                ↓
          propay_wallets.balance_cents += amount
          propay_wallet_transactions INSERT (imutável)
```

**Estrutura de diretórios:**

```bash
propay/
├── app/
│   ├── handlers/      # Roda route handlers
│   ├── services/      # Lógica de negócio
│   ├── jobs/          # Sidekiq workers
│   ├── models/        # Sequel models
│   ├── providers/     # OpenPix / Efi
│   ├── middleware/    # Auth, idempotência, rate limit
│   └── validators/    # dry-validation schemas
├── bin/
│   └── start          # entrypoint: roda migrations + inicia iodine
├── db/migrations/
├── config/
├── config.ru
├── Gemfile
├── Dockerfile
└── docker-compose.yml
```

---

### SETUP

**Pré-requisitos:**
- Ruby 3.4+
- PostgreSQL 15+
- Redis 7+
- CNPJ ativo com chave PIX (MEI basta)
- Conta OpenPix ou Efi

```bash
# 1. Dependências
bundle install

# 2. Banco
createdb propay_development
bundle exec ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"

# 3. Variáveis
cp .env.example .env

# 4. Rodar
bundle exec sidekiq -C config/sidekiq.yml -r ./config/sidekiq_boot.rb &  # Terminal 1
bundle exec iodine --yjit -p 5555                                          # Terminal 2
```

---

### API ENDPOINTS

**Base URL:** `https://propay.prostaff.gg/v1/`

Todos os endpoints exigem `Authorization: Bearer <jwt>` (mesmo JWT do prostaff-api).  
Todas as mutações exigem `Idempotency-Key: <uuid-v4>`.

#### Saúde
- `GET /v1/health` - Status do serviço
- `GET /v1/ready` - Readiness (DB + Redis)

#### Cobranças PIX
- `POST   /v1/charges` - Criar cobrança
- `GET    /v1/charges/:txid` - Consultar
- `DELETE /v1/charges/:txid` - Cancelar
- `POST   /v1/charges/:txid/refund` - Reembolso CDC (janela de 7 dias)

**Exemplo POST /v1/charges:**
```json
{
  "amount_cents": 10000,
  "description": "Inscrição Copa ArenaBR #1",
  "reference_type": "tournament_registration",
  "reference_id": 42,
  "expires_in_seconds": 3600
}
```

**Response 201:**
```json
{
  "data": {
    "txid": "7978c0c97ea847e78e8849634473c1f9",
    "status": "active",
    "amount_cents": 10000,
    "qr_code": "00020126580014br.gov.bcb.brcode...",
    "qr_code_url": "https://propay.prostaff.gg/qr/7978c0c9",
    "expires_at": "2026-05-05T15:00:00Z"
  }
}
```

#### Assinaturas
- `POST   /v1/subscriptions` - Criar (com trial)
- `GET    /v1/subscriptions/:id`
- `GET    /v1/subscriptions/by_owner/:owner_id`
- `PATCH  /v1/subscriptions/:id/cancel`
- `GET    /v1/subscriptions/:id/charges`

#### Carteira
- `GET    /v1/wallet`
- `GET    /v1/wallet/transactions`
- `POST   /v1/wallet/deposit`
- `POST   /v1/wallet/debit` _(role `admin` ou `service` obrigatório)_
- `POST   /v1/wallet/payouts`
- `GET    /v1/wallet/payouts/:id`

#### Admin
- `GET    /v1/admin/dashboard` - Resumo financeiro geral
- `GET    /v1/admin/subscriptions` - Todas as assinaturas
- `GET    /v1/admin/charges` - Todas as cobranças
- `GET    /v1/admin/wallets` - Todas as carteiras
- `POST   /v1/tournaments/:id/distribute_prizes`
- `GET    /v1/tournaments/:id/financial_report`

#### Observabilidade
- `GET    /metrics` - Métricas Prometheus (acesso restrito a IPs privados: 127.x, 10.x, 172.16-31.x, 192.168.x)

**Status de cobrança:**

| Status     | Descrição                              |
|------------|----------------------------------------|
| `pending`  | Aguardando geração pelo provider       |
| `active`   | QR Code gerado                         |
| `paid`     | Confirmado via webhook                 |
| `expired`  | Expirou sem pagamento                  |
| `cancelled`| Cancelada manualmente                  |
| `refunded` | Reembolsada                            |

---

### PROVIDERS PIX

| Recurso                  | OpenPix (Fase 1)          | Efi / Gerencianet (Fase 2) |
|--------------------------|---------------------------|----------------------------|
| PIX único                | Sim                       | Sim                        |
| COBR (recorrente BACEN)  | Não                       | Sim                        |
| Webhook                  | HMAC-SHA256               | mTLS + HMAC                |
| Taxa                     | 0% (freemium PME)         | ~0,99%                     |
| MEI aceito               | Sim                       | Sim                        |

Abstração unificada - trocar de provider só muda `PROPAY_PROVIDER`.

---

### BACKGROUND JOBS

| Job                      | Trigger                  | Responsabilidade |
|--------------------------|--------------------------|------------------|
| `PixWebhookJob`          | Webhook PIX              | Credita carteira / ativa assinatura |
| `TierSyncJob`            | Assinatura muda          | PATCH interno no prostaff-api |
| `RecurringChargeJob`     | Cron diário 08:00 BRT    | Gera cobranças recorrentes |
| `SubscriptionRetryJob`   | Charge expirada          | Retry D+1/D+2/D+3 |
| `PrizeDistributionJob`   | Campeonato finalizado    | Distribui prêmios |
| `ExpireChargesJob`       | Cron 15 min              | Marca cobranças expiradas |
| `PayoutProcessingJob`    | Saque solicitado         | Valida anti-fraude 24h + debita wallet + PIX de saída |
| `SidekiqHealthJob`       | Cron 5 min               | Alerta dead queue > 5, atualiza gauge Prometheus |

---

### WEBHOOKS

- Sempre responde `200 OK` em < 100ms (processamento assíncrono via Sidekiq)
- Validação HMAC-SHA256 obrigatória
- `end_to_end_id` UNIQUE → idempotente

---

### DEPLOYMENT

**docker-compose.yaml (produção — via Coolify):**

```yaml
services:
  propay-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: propay_development
      POSTGRES_USER: propay
      POSTGRES_PASSWORD: ${PROPAY_DB_PASSWORD}
    volumes:
      - propay_db_data:/var/lib/postgresql/data
    networks:
      - propay-internal

  redis:
    image: redis:7-alpine
    networks:
      - propay-internal

  propay:
    build: .
    environment: &propay-env
      DB_HOST: propay-db
      DB_PORT: "5432"
      DB_NAME: propay_development
      DB_USER: propay
      DB_PASSWORD: ${PROPAY_DB_PASSWORD}
      REDIS_URL: redis://redis:6379/1
      INTERNAL_JWT_SECRET: ${INTERNAL_JWT_SECRET}
      PROPAY_OPENPIX_APP_ID: ${PROPAY_OPENPIX_APP_ID}
      PROPAY_OPENPIX_SECRET: ${PROPAY_OPENPIX_SECRET}
      PROPAY_PIX_KEY: ${PROPAY_PIX_KEY}
      PROSTAFF_API_URL: ${PROSTAFF_API_URL:-https://api.prostaff.gg}
      MALLOC_ARENA_MAX: "2"
    networks:
      - propay-internal
      - coolify

  propay-worker:
    build: .
    command: bundle exec sidekiq -C config/sidekiq.yml -r ./config/sidekiq_boot.rb
    environment: *propay-env
    networks:
      - propay-internal

volumes:
  propay_db_data:

networks:
  propay-internal:
    driver: bridge
  coolify:
    external: true
```

**Migrações:**

Executadas automaticamente pelo `bin/start` a cada inicialização do container — não é necessário rodar manualmente.

---

### ENVIRONMENT VARIABLES

| Variável                     | Obrigatória | Descrição |
|------------------------------|-------------|-----------|
| `DB_HOST`                    | Sim         | Host do PostgreSQL (ex: `propay-db`) |
| `DB_PORT`                    | Sim         | Porta do PostgreSQL (ex: `5432`) |
| `DB_NAME`                    | Sim         | Nome do banco (ex: `propay_development`) |
| `DB_USER`                    | Sim         | Usuário do PostgreSQL |
| `DB_PASSWORD`                | Sim         | Senha do PostgreSQL (suporta caracteres especiais) |
| `REDIS_URL`                  | Sim         | Redis DB 1 (ex: `redis://redis:6379/1`) |
| `INTERNAL_JWT_SECRET`        | Sim         | Mesmo do prostaff-api |
| `PROPAY_OPENPIX_APP_ID`      | Fase 1      | OpenPix App ID |
| `PROPAY_OPENPIX_SECRET`      | Fase 1      | Secret HMAC atual |
| `PROPAY_OPENPIX_SECRET_PREV` | Não         | Secret HMAC anterior — usado durante rotação sem downtime |
| `PROPAY_EFI_CLIENT_ID`       | Fase 2      | Efi Client ID |
| `PROPAY_EFI_CLIENT_SECRET`   | Fase 2      | Efi Client Secret |
| `PROPAY_EFI_CERT_PATH`       | Fase 2      | Caminho do certificado mTLS .p12 (ex: `/run/secrets/efi_cert.p12`) |
| `PROPAY_PIX_KEY`             | Sim         | Chave PIX da conta |
| `PROPAY_PROVIDER`            | Não         | `openpix` (default) ou `efi` |
| `PROSTAFF_API_URL`           | Sim         | URL interna do prostaff-api |
| `PROPAY_DB_PASSWORD`         | Sim         | Senha do banco próprio |
| `MALLOC_ARENA_MAX`           | Não         | `2` (recomendado) |
| `PORT`                       | Não         | 5555 (default) |

**Pré-requisito externo:** CNPJ ativo (MEI é suficiente).

---

**LICENSE:**

© 2026 ProStaff.gg. All rights reserved.

Released under: **GNU Affero General Public License v3.0 (AGPLv3)**

> Prostaff.gg isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc.
```

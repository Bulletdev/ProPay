```
██████╗ ██████╗  ██████╗ ██████╗  █████╗ ██╗   ██╗
██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██████╔╝██║   ██║██████╔╝███████║ ╚████╔╝
██╔═══╝ ██╔══██╗██║   ██║██╔═══╝ ██╔══██║  ╚██╔╝
██║     ██║  ██║╚██████╔╝██║     ██║  ██║   ██║
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝   ╚═╝
             Gateway de Pagamentos - ProStaff Ecosystem
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
║  Gateway de pagamentos proprietario do ecossistema ProStaff.             ║
║  PIX unico · PIX recorrente · Carteira interna · Prize pool · p95 < 50ms ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

**KEY FEATURES:**

- PIX Unico - Geracao de QR Code dinamico (EMV/BR Code) via OpenPix
- PIX Recorrente - Protocolo COBR do BACEN via Efi para assinaturas automatizadas
- Carteira Interna - Saldo por usuario com debito/credito atomico e auditoria
- Assinaturas SaaS - Planos Pro e Enterprise do ProStaff Analytics Hub com trial
- Prize Pool - Distribuicao automatica de premios de campeonatos do ArenaBR
- Reembolsos - Cancelamento com credito na carteira ou PIX de volta (CDC 7 dias)
- Saques - PIX de saida para chave cadastrada com validacao de formato BACEN
- Webhooks - Confirmacao assíncrona de PIX em < 3s com HMAC-SHA256
- Idempotencia - Idempotency-Key obrigatoria + end_to_end_id UNIQUE no banco
- Isolamento - Queries sempre escopadas por customer_id, sem dados cruzados
- Rate Limiting - Rack::Attack com Redis, 30 req/min por IP
- Observabilidade - Metricas Prometheus + health + readiness endpoints
- Alta Performance - Iodine event loop C (epoll) + YJIT + MALLOC_ARENA_MAX=2
- Banco proprio - PostgreSQL 15 isolado (propay-db) na rede coolify

**TABLE OF CONTENTS:**

- 01 · Quick Start
- 02 · Technology Stack
- 03 · Architecture
- 04 · Setup
- 05 · API Endpoints
- 06 · Providers PIX
- 07 · Background Jobs
- 08 · Webhooks
- 09 · Deployment
- 10 · Environment Variables

---

**QUICK START:**

Docker (Recomendado):

```bash
cp .env.example .env
# editar .env - PROPAY_OPENPIX_APP_ID, PROPAY_OPENPIX_SECRET, PROPAY_PIX_KEY, INTERNAL_JWT_SECRET
docker compose up -d
curl http://localhost:5555/v1/health
# {"status":"ok","version":"1.0.0"}
```

Local (sem Docker):

```bash
cp .env.example .env
bundle install
bundle exec sequel -m db/migrations $DATABASE_URL
bundle exec iodine --yjit --yjit-exec-mem-size=8 -p 5555
```

API: http://localhost:5555
Health: http://localhost:5555/v1/health

**TECHNOLOGY STACK:**

- Language: Ruby 3.4 com YJIT habilitado
- Framework: Roda 3.103 (tree routing, ~0.1ms overhead)
- HTTP Server: Iodine 0.7 (event loop C com epoll, substitui Puma)
- JSON: Oj 3.17 (3-5x mais rapido que stdlib)
- ORM: Sequel 5.75 + sequel_pg (leve, sem ActiveRecord)
- Database: PostgreSQL 15 (instancia propria - propay-db)
- Cache / Locks: Redis 7 + Redlock (distributed locks)
- HTTP Client: HTTPX 1.3 (async, chamadas OpenPix / Efi)
- Background Jobs: Sidekiq 7
- Validacao: dry-validation 1.10
- Monitoramento: Prometheus::Client

---

**ARCHITECTURE:**

Posicao no ecossistema ProStaff:

```
INTERNET
    |
  Traefik (TLS - Let's Encrypt)
    |
    +-- api.prostaff.gg       --> prostaff-api   (Rails,  :3000)
    +-- events.prostaff.gg    --> prostaff-events (Phoenix, :4000)
    +-- scraper.prostaff.gg   --> ProStaff-Scraper (FastAPI, :8000)
    +-- propay.prostaff.gg    --> ProPay           (Roda,   :5555)

REDE DOCKER: coolify
    |
    +-- prostaff-api    --> PostgreSQL, Redis, Meilisearch, Sidekiq
    +-- prostaff-events --> Redis (compartilhado)
    +-- riot-gateway    --> interno
    +-- propay          --> propay-db (PostgreSQL proprio), Redis DB 1

FRONTENDS (Cloudflare pages)
    +-- ArenaBR             --> propay.prostaff.gg (CORS autorizado)
    +-- ProStaff Analytics  --> propay.prostaff.gg (CORS autorizado)
    +-- Scrims.lol          --> propay.prostaff.gg (CORS autorizado)
```

Fluxo de pagamento (PIX unico - ArenaBR):

```
[Frontend]  POST /v1/wallet/deposit
               |
            ProPay cria Charge + chama OpenPix API
               |
            <- {qr_code, qr_code_url, txid}
               |
            [Usuario paga no banco]
               |
            OpenPix --> POST /v1/webhooks/openpix
               |
            PixWebhookJob (Sidekiq)
               |
            WalletService.credit! (SELECT FOR UPDATE)
               |
            propay_wallets.balance_cents += amount
            propay_wallet_transactions INSERT (imutavel)
```

Fluxo de assinatura (ProStaff Analytics Hub):

```
[Frontend]  POST /v1/subscriptions {plan_name: "pro_monthly", trial_days: 14}
               |
            Subscription criada (status: trialing, next_charge_at: +14 dias)
               |
            [14 dias depois - RecurringChargeJob]
               |
            Nova Charge gerada + e-mail para usuario
               |
            [Usuario paga]
               |
            PixWebhookJob --> Subscription status: active
               |
            TierSyncJob --> PATCH http://api:3000/internal/organizations/:id
                           {tier: "tier_2_semi_pro"}
```

Estrutura de diretorios:

```
propay/
├── app/
│   ├── handlers/           # Roda route handlers (HTTP layer)
│   ├── services/           # Logica de negocio (WalletService, etc.)
│   ├── jobs/               # Sidekiq workers
│   ├── models/             # Sequel models
│   ├── providers/          # Abstracao OpenPix / Efi
│   ├── middleware/         # Auth JWT, idempotencia, rate limiting
│   └── validators/         # dry-validation schemas
├── db/
│   └── migrations/         # Sequel migrations (propay_* tables)
├── config/
├── config.ru
├── Gemfile
├── Dockerfile
└── docker-compose.yml
```

---

**SETUP:**

Pre-requisitos:
- Ruby 3.4+
- PostgreSQL 15+
- Redis 7+
- CNPJ ativo com chave PIX cadastrada (MEI suficiente)
- Conta OpenPix ativa (Fase 1) ou Efi (Fase 2 - COBR)

Instalacao:

```bash
# 1. Dependencias
bundle install

# 2. Banco de dados
createdb propay_development
bundle exec sequel -m db/migrations $DATABASE_URL

# 3. Variaveis de ambiente
cp .env.example .env
# editar .env com credenciais

# 4. Iniciar
bundle exec sidekiq -c config/sidekiq.yml &   # Terminal 1 (jobs)
bundle exec iodine --yjit -p 5555             # Terminal 2 (API)
```

---

**API ENDPOINTS:**

Todos os endpoints exigem `Authorization: Bearer <jwt>` (mesmo JWT emitido pelo prostaff-api).
Todas as mutacoes exigem o header `Idempotency-Key: <uuid-v4>`.

Base URL: `https://propay.prostaff.gg/v1/`

Saude:

```
GET  /v1/health        Status do servico
GET  /v1/ready         Readiness - verifica DB + Redis (para Traefik/Coolify)
```

Cobranças PIX:

```
POST   /v1/charges            Criar cobranca PIX
GET    /v1/charges/:txid      Consultar status
DELETE /v1/charges/:txid      Cancelar cobranca ativa
```

POST /v1/charges - request:
```json
{
  "amount_cents": 10000,
  "description": "Inscricao Copa ArenaBR #1",
  "reference_type": "tournament_registration",
  "reference_id": 42,
  "expires_in_seconds": 3600
}
```

POST /v1/charges - response 201:
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

Assinaturas (ProStaff Analytics Hub):

```
POST   /v1/subscriptions                      Criar assinatura (inicia trial)
GET    /v1/subscriptions/:id                  Consultar
GET    /v1/subscriptions/by_owner/:owner_id   Por owner (para prostaff-api)
PATCH  /v1/subscriptions/:id/cancel           Cancelar ao fim do periodo
GET    /v1/subscriptions/:id/charges          Historico de cobranças
```

Carteira (ArenaBR):

```
GET    /v1/wallet                   Saldo atual do usuario autenticado
GET    /v1/wallet/transactions      Historico paginado de transacoes
POST   /v1/wallet/deposit           Gera cobranca PIX de deposito
POST   /v1/wallet/debit             Debito interno (chamado por jobs/servicos)
POST   /v1/wallet/payouts           Solicitar saque via PIX (Fase 3)
GET    /v1/wallet/payouts/:id       Status do saque
```

Premio e relatorio (admin):

```
POST   /v1/tournaments/:id/distribute_prizes   Distribuir premios do campeonato
GET    /v1/tournaments/:id/financial_report    Relatorio financeiro
```

Webhooks (sem JWT - autenticados por HMAC):

```
POST   /v1/webhooks/openpix    Recebe eventos OpenPix (HMAC-SHA256)
POST   /v1/webhooks/efi        Recebe eventos Efi (mTLS + HMAC) - Fase 2
```

Status de cobrança:

|    Status   |             Descricao                    |
|-------------|------------------------------------------|
| `pending`   | Criada, aguardando geracao pelo provider |
| `active`    | QR Code gerado, aguardando pagamento     |
| `paid`      | Pagamento confirmado via webhook         |
| `expired`   | Expirou sem pagamento                    |
| `cancelled` | Cancelada manualmente                    |
| `refunded`  | Reembolsada                              |

---

**PROVIDERS PIX:**

|                                   OpenPix (Fase 1)   | Efi / Gerencianet (Fase 2) |
|-------------------------|----------------------------|----------------------------|
| PIX unico               | Sim                        | Sim                        |
| COBR (recorrente BACEN) | Nao                        | Sim                        |
| Webhook                 | HMAC-SHA256                | mTLS + HMAC                |
| SDK Ruby  Nao oficial   | Sim (kakashi/payments)     |                            |
| Taxa                    | 0% (freemium PME)| ~0,99%  |                            |
| MEI aceito              | Sim                        | Sim                        |

Abstracao de provider:

```ruby
# Todos os providers implementam a mesma interface
provider = OpenpixProvider.new   # ou EfiProvider.new

provider.create_charge(
  amount_cents: 10000,
  description:  "Deposito carteira",
  txid:         SecureRandom.hex(16),
  expires_in:   3600
)

provider.verify_webhook(headers: headers, raw_body: body)
```

A troca de provider nao altera nenhum handler ou job - apenas a variavel `PROPAY_PROVIDER`.

---

**BACKGROUND JOBS:**

| Job | Trigger | Responsabilidade |
|---|---|---|
| `PixWebhookJob` | Webhook PIX confirmado | Credita carteira ou ativa assinatura |
| `TierSyncJob` | Assinatura ativada/cancelada | PATCH interno para prostaff-api |
| `RecurringChargeJob` | Cron diario 08:00 BRT | Gera cobranças para subs com next_charge_at <= hoje |
| `SubscriptionRetryJob` | Charge expirada sem pagamento | Retenta D+1, D+2, D+3 - cancela apos 3 falhas |
| `PrizeDistributionJob` | Campeonato finalizado | Credita premios na carteira de cada jogador |
| `ExpireChargesJob` | Cron a cada 15 min | Marca cobranças expiradas como expired |
| `PayoutProcessingJob` | Saque aprovado | PIX de saida via provider (Fase 3) |

Configuracao Sidekiq:

```yaml
# config/sidekiq.yml
:concurrency: 4
:timeout: 25
:queues:
  - [critical, 3]   # webhooks, wallet credits
  - [default, 2]    # charges, subscriptions
  - [low, 1]        # reports, cleanup
```

---

**WEBHOOKS:**

Seguranca:
- Resposta sempre `200 OK` em < 100ms - processamento e assincrono (Sidekiq)
- Payload validado via HMAC-SHA256 antes de qualquer processamento
- `end_to_end_id` com indice UNIQUE - segundo webhook do mesmo PIX ignorado silenciosamente
- Job idempotente - reprocessar o mesmo evento nao gera duplicata

Configurar webhook no OpenPix:

```bash
# Via dashboard OpenPix ou API
POST https://api.openpix.com.br/api/v1/webhook
{
  "name": "ProPay Production",
  "event": "OPENPIX:CHARGE_COMPLETED",
  "url": "https://propay.prostaff.gg/v1/webhooks/openpix",
  "authorization": "<PROPAY_OPENPIX_SECRET>"
}
```

Payload recebido (OpenPix):

```json
{
  "event": "OPENPIX:CHARGE_COMPLETED",
  "charge": {
    "correlationID": "7978c0c97ea847e78e8849634473c1f9",
    "value": 10000,
    "status": "COMPLETED",
    "paidAt": "2026-05-05T12:30:00Z",
    "transactionID": "E123402009091221kkkkkkk"
  }
}
```

---

**DEPLOYMENT:**

Docker Compose (producao):

```yaml
services:
  propay-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: propay_production
      POSTGRES_USER: propay
      POSTGRES_PASSWORD: ${PROPAY_DB_PASSWORD}
    volumes:
      - propay_db_data:/var/lib/postgresql/data
    networks:
      - coolify

  propay:
    build: .
    environment: &propay-env
      DATABASE_URL: postgresql://propay:${PROPAY_DB_PASSWORD}@propay-db:5432/propay_production
      REDIS_URL: redis://default:${REDIS_PASSWORD}@redis:6379/1
      INTERNAL_JWT_SECRET: ${INTERNAL_JWT_SECRET}
      PROPAY_OPENPIX_APP_ID: ${PROPAY_OPENPIX_APP_ID}
      PROPAY_OPENPIX_SECRET: ${PROPAY_OPENPIX_SECRET}
      PROPAY_PIX_KEY: ${PROPAY_PIX_KEY}
      PROSTAFF_API_URL: http://api:3000
      MALLOC_ARENA_MAX: 2
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.propay.rule=Host(`propay.prostaff.gg`)"
      - "traefik.http.routers.propay.tls.certresolver=letsencrypt"
      - "traefik.http.services.propay.loadbalancer.server.port=5555"
    networks:
      - coolify
    depends_on:
      propay-db:
        condition: service_healthy

  propay-worker:
    build: .
    command: bundle exec sidekiq -c config/sidekiq.yml
    environment: *propay-env
    networks:
      - coolify

volumes:
  propay_db_data:

networks:
  coolify:
    external: true
```

Comunicacao interna (rede coolify):

- ProPay -> prostaff-api: `http://api:3000` (TierSyncJob)
- ProPay -> propay-db: `propay-db:5432` (banco proprio)
- ProPay -> Redis: `redis:6379/1` (Redis compartilhado, DB index 1)
- prostaff-api -> ProPay: `http://propay:5555` (consultas de subscription)

Build Docker:

```bash
docker build -t propay .
docker compose up -d
docker compose logs -f propay
```

Variaveis de ambiente no Coolify:
Adicionar no painel do Coolify na stack ProPay (nao no prostaff-api).
`INTERNAL_JWT_SECRET` deve ser identico ao do prostaff-api.

---

**ENVIRONMENT VARIABLES:**

| Variavel | Obrigatoria | Descricao |
|---|---|---|
| `DATABASE_URL` | Sim | PostgreSQL do propay-db |
| `REDIS_URL` | Sim | Redis compartilhado (DB index 1) |
| `INTERNAL_JWT_SECRET` | Sim | Mesmo valor do prostaff-api |
| `PROPAY_OPENPIX_APP_ID` | Fase 1 | App ID da conta OpenPix |
| `PROPAY_OPENPIX_SECRET` | Fase 1 | Secret para HMAC dos webhooks OpenPix |
| `PROPAY_EFI_CLIENT_ID` | Fase 2 | Client ID da conta Efi |
| `PROPAY_EFI_CLIENT_SECRET` | Fase 2 | Client Secret da conta Efi |
| `PROPAY_EFI_CERTIFICATE_PATH` | Fase 2 | Caminho do .p12 para mTLS |
| `PROPAY_PIX_KEY` | Sim | Chave PIX da conta (CNPJ recomendado) |
| `PROPAY_PROVIDER` | Nao | `openpix` (default) ou `efi` |
| `PROSTAFF_API_URL` | Sim | URL interna do prostaff-api (ex: http://api:3000) |
| `PROPAY_DB_PASSWORD` | Sim | Senha do PostgreSQL proprio |
| `MALLOC_ARENA_MAX` | Nao | `2` (recomendado - limita fragmentacao glibc) |
| `PORT` | Nao | Porta HTTP (default: 5555) |
| `RACK_ENV` | Nao | `production` em producao |

Pre-requisito externo - CNPJ ativo:

OpenPix e Efi exigem CNPJ para operar como merchant. A forma mais rapida e abrir um MEI no
Portal do Empreendedor (gov.br). O CNPJ e liberado na hora. Custo: ~R$71/mes (DAS).
CNAE sugerido: 6201-5/01 - Desenvolvimento de programas de computador sob encomenda.

---

**LICENSE:**

© 2026 ProStaff.gg. All rights reserved.

Released under: GNU Affero General Public License v3.0 (AGPLv3)

Prostaff.gg isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games
or anyone officially involved in producing or managing Riot Games properties.
Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc.

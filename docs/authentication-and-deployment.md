---
title: Authentication and Deployment Architecture
description: How WorkbenchIQ authentication and Azure deployment works for local development and cloud environments.
ms.date: 2026-03-23
ms.topic: concept
---

## Overview

WorkbenchIQ uses a layered authentication strategy that adapts to the environment:

- **Local development** uses API keys and username/password login
- **Azure cloud** uses Microsoft Entra ID (Easy Auth) and Managed Identity
- Both environments protect the backend API from unauthorized access

## Authentication Flow: Local Development

```mermaid
sequenceDiagram
    participant User as Browser
    participant FE as Next.js Frontend<br/>(port 3000)
    participant Proxy as API Proxy<br/>(server-side route)
    participant BE as FastAPI Backend<br/>(port 8000)

    Note over FE: AUTH_USER_1=admin:pass<br/>AUTH_SECRET=xxx<br/>API_SECRET_KEY=yyy

    User->>FE: GET /
    FE-->>User: 302 Redirect /login
    User->>FE: POST /api/auth/login<br/>{username, password}
    FE->>FE: Validate against AUTH_USER_*
    FE-->>User: Set session cookie (HMAC signed)

    User->>FE: GET /api/applications
    FE->>Proxy: Forward request
    Proxy->>Proxy: Inject X-API-Key header
    Proxy->>BE: GET /api/applications<br/>X-API-Key: yyy
    BE->>BE: ApiKeyMiddleware validates key
    BE-->>Proxy: 200 OK (data)
    Proxy-->>User: 200 OK (data)

    Note over User,BE: Direct curl without X-API-Key → 401
```

## Authentication Flow: Azure (Easy Auth)

```mermaid
sequenceDiagram
    participant User as Browser
    participant EA as Easy Auth<br/>(App Service layer)
    participant FE as Next.js Frontend
    participant Proxy as API Proxy<br/>(server-side)
    participant EA2 as Easy Auth<br/>(API App Service)
    participant BE as FastAPI Backend

    User->>EA: GET /
    EA-->>User: 302 → Microsoft login
    User->>EA: AAD token (after login)
    EA->>FE: Request + X-MS-CLIENT-PRINCIPAL
    FE->>FE: Middleware detects header, skips custom auth
    FE->>Proxy: Forward API call
    Proxy->>Proxy: Forward auth headers
    Proxy->>EA2: GET /api/applications<br/>X-MS-CLIENT-PRINCIPAL: ...
    EA2->>BE: Request passes Easy Auth
    BE->>BE: EasyAuthMiddleware decodes user
    BE-->>Proxy: 200 OK (data)
    Proxy-->>User: 200 OK (data)
```

## Architecture: Local Development

```mermaid
graph TB
    subgraph "Developer Machine"
        Browser["Browser<br/>localhost:3000"]
        FE["Next.js Frontend<br/>:3000<br/>Custom Auth Middleware"]
        BE["FastAPI Backend<br/>:8000<br/>API Key Middleware"]
        Data["Local data/ folder"]
        ENV[".env file<br/>AUTH_USER_1, AUTH_SECRET<br/>API_SECRET_KEY<br/>Azure AI credentials"]
    end

    subgraph "Azure Cloud (remote)"
        AIS["Azure AI Services<br/>(Content Understanding + OpenAI)"]
    end

    Browser -->|"Session cookie"| FE
    FE -->|"X-API-Key injected<br/>(server-side proxy)"| BE
    BE --> Data
    BE -->|"Azure AD or API Key"| AIS
    ENV -.->|"Loaded by dotenv"| FE
    ENV -.->|"Loaded by dotenv"| BE
```

## Architecture: Azure Cloud

```mermaid
graph TB
    subgraph "Azure Resource Group"
        subgraph "App Service Plan (P0v3)"
            FEApp["Frontend Web App<br/>Node.js 20<br/>Easy Auth (AAD)"]
            BEApp["Backend API App<br/>Python 3.11<br/>Easy Auth (AAD)<br/>Managed Identity"]
        end

        AIS["Azure AI Services<br/>(kind: AIServices)<br/>gpt-4.1 + gpt-4.1-mini<br/>text-embedding-3-small<br/>text-embedding-3-large"]

        Storage["Azure Blob Storage<br/>workbenchiq-data container"]

        Monitor["App Insights<br/>+ Log Analytics"]
    end

    subgraph "Microsoft Entra ID"
        AAD["Azure AD<br/>Tenant"]
    end

    User["Browser"] -->|"AAD Login"| AAD
    AAD -->|"Token"| FEApp
    FEApp -->|"Proxy + auth headers"| BEApp
    BEApp -->|"Managed Identity<br/>(Cognitive Services User)"| AIS
    BEApp -->|"Managed Identity<br/>(Storage Blob Data Contributor)"| Storage
    BEApp -.-> Monitor
    FEApp -.-> Monitor
```

## Security Layers by Environment

| Layer | Local Dev | Azure Cloud |
|-------|-----------|-------------|
| **Frontend (browser)** | Custom login (`AUTH_USER_*`) | Easy Auth (Entra ID AAD) |
| **Backend API** | API key (`API_SECRET_KEY`) | Easy Auth (Entra ID AAD) |
| **AI Services** | Azure AD token (`az login`) | Managed Identity (RBAC) |
| **Blob Storage** | Azure AD token (`az login`) | Managed Identity (RBAC) |
| **Swagger UI** | Open (for development) | Protected by Easy Auth |

## Middleware Execution Order (Backend)

```mermaid
graph LR
    A["Incoming Request"] --> B["CORS Middleware"]
    B --> C["EasyAuthMiddleware<br/>Decode X-MS-CLIENT-PRINCIPAL<br/>Attach request.state.user"]
    C --> D["ApiKeyMiddleware<br/>Check X-API-Key header<br/>Skip if Easy Auth active"]
    D --> E["FastAPI Route Handler"]
```

## Middleware Execution Order (Frontend)

```mermaid
graph LR
    A["Incoming Request"] --> B{"X-MS-CLIENT-PRINCIPAL<br/>header present?"}
    B -->|Yes| C["Skip auth → Next.js"]
    B -->|No| D{"AUTH_USER_*<br/>env vars set?"}
    D -->|No| C
    D -->|Yes| E{"Session cookie<br/>valid?"}
    E -->|Yes| C
    E -->|No| F["302 → /login"]
```

## Setup Commands

### Local development

```bash
# One-time: generate auth credentials
python scripts/setup_auth.py --auto

# Start backend
uv run python -m uvicorn api_server:app --reload --port 8000

# Start frontend
cd frontend && npm run dev
```

### Azure deployment

```bash
# One command to provision + deploy everything
azd up

# Optional: enable Easy Auth (after deployment)
azd env set AUTH_TENANT_ID $(az account show --query tenantId -o tsv)
azd up
```

### Tear down Azure resources

```bash
azd down --purge
```

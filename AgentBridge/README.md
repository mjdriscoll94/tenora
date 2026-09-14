# Tenora Agent Bridge

The bridge is a read-only MCP server and a one-way, opt-in snapshot API for the Tenora iOS app. Tenora remains usable offline and remains the source of truth. ChatGPT can inspect synchronized data but this phase does not expose tools that mutate tasks.

## Exposed tools

- `list_tasks`: filter tasks by status or text
- `get_task`: retrieve one task by UUID
- `get_now_context`: current focus, counts, next event, and snapshot freshness
- `get_today_schedule`: scheduled tasks and optionally shared calendar events
- `search` and `fetch`: standard read-only retrieval tools

All tools are marked read-only, non-destructive, and closed-world. Every MCP request requires the `tasks:read` scope. Phone snapshot uploads require `tasks:sync`.

## Run locally

The quickest readiness check starts PostgreSQL, applies the schema, builds the bridge, and waits for both services to become healthy:

```sh
docker compose up --build --wait
curl --fail http://localhost:3000/health
docker compose down
```

The local OAuth URLs are intentionally non-functional placeholders. The health and metadata endpoints work, but authenticated sync and MCP calls require tokens from a real provider.

For development without Docker:

1. Create a PostgreSQL database and apply `sql/001_initial.sql` using a non-superuser deployment role.
2. Copy `.env.example` to `.env` and enter the database and OAuth values.
3. Install and verify the service:

   ```sh
   npm ci
   npm test
   npm run build
   npm start
   ```

4. Point MCP Inspector at `http://localhost:3000/mcp` and provide a bearer token with `tasks:read`.

The MCP endpoint supports stateless Streamable HTTP POST requests. `/health` is the only operational endpoint that does not require authentication.

## Authentication

Use an established OAuth 2.1/OIDC provider rather than implementing login in this service. Configure:

- authorization-code flow with PKCE/S256;
- an API audience equal to `OAUTH_AUDIENCE` and normally `BRIDGE_BASE_URL`;
- `tasks:read` and `tasks:sync` scopes;
- issuer discovery and JWKS endpoints;
- the iOS redirect URI `tenora://oauth/callback` for the native client;
- ChatGPT's redirect URI from the plugin management screen;
- support for the MCP `resource` parameter.

The resource server verifies signature, issuer, audience, expiry, and scope for each call. Its protected-resource metadata is served from `/.well-known/oauth-protected-resource`.

## Configure the iOS build

Set these Xcode build settings in an `.xcconfig` excluded from source control or in the release configuration:

```text
TENORA_BRIDGE_URL = https://bridge.example.com
TENORA_OAUTH_ISSUER = https://your-issuer.example.com/
TENORA_OAUTH_CLIENT_ID = your-native-ios-client-id
```

After installing that build, open Settings → ChatGPT Agent Bridge, connect the account, choose whether to include task notes and calendar context, and run the first sync.

## Connect ChatGPT

Deploy the container to a stable HTTPS origin, then create a ChatGPT plugin/MCP connection using `https://bridge.example.com/mcp`. Use OAuth and request `tasks:read`; do not grant the ChatGPT client `tasks:sync`. The iOS native client receives both scopes because it owns snapshot publication.

The implementation follows the [OpenAI MCP server guide](https://developers.openai.com/plugins/build/mcp-server) and [OpenAI authentication guide](https://developers.openai.com/plugins/build/auth).

## Production checklist

- Use TLS and a managed PostgreSQL service.
- Use a non-superuser database role so forced row-level security is effective.
- Keep database credentials and OAuth configuration in the host's secret manager.
- Keep request logs free of tokens, task content, and MCP results.
- Rate-limit `/mcp` and `/v1/sync/tasks` at the edge.
- Configure backups, retention, monitoring, and deletion/account-disconnect behavior.
- Run MCP Inspector plus direct, indirect, invalid-input, and cross-user authorization tests.

Every change under `AgentBridge/` is also checked in GitHub Actions with the unit tests, TypeScript compiler, and production Docker build.

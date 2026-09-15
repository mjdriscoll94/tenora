import express from "express";
import { authenticationMiddleware, requireScope, type AuthenticatedRequest } from "./auth.js";
import { loadConfig } from "./config.js";
import { syncSnapshotSchema } from "./contracts.js";
import { createTenoraMcpServer, handleMcpRequest } from "./mcp.js";
import { PostgresSnapshotRepository } from "./postgresRepository.js";
import { TenoraReadService } from "./repository.js";

const config = loadConfig();
const repository = new PostgresSnapshotRepository(config.DATABASE_URL);
const service = new TenoraReadService(repository);
const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "2mb" }));

const metadataURL = `${config.BRIDGE_BASE_URL.replace(/\/$/, "")}/.well-known/oauth-protected-resource`;
const authentication = { issuer: config.OAUTH_ISSUER, audience: config.OAUTH_AUDIENCE,
  jwksURL: config.OAUTH_JWKS_URL, resourceMetadataURL: metadataURL };
const authenticateSync = authenticationMiddleware({ ...authentication, challengeScopes: ["tasks:sync"] });
const authenticateRead = authenticationMiddleware({ ...authentication, challengeScopes: ["tasks:read"] });

app.get("/health", (_request, response) => response.json({ ok: true, service: "tenora-agent-bridge", version: "0.1.0" }));
app.get("/.well-known/oauth-protected-resource", (_request, response) => response.json({
  resource: config.BRIDGE_BASE_URL,
  authorization_servers: [config.OAUTH_ISSUER],
  scopes_supported: ["tasks:read", "tasks:sync"],
  resource_documentation: `${config.TENORA_APP_URL.replace(/\/$/, "")}/agent-bridge`
}));

app.post("/v1/sync/tasks", authenticateSync, requireScope("tasks:sync"), async (request: AuthenticatedRequest, response, next) => {
  try {
    const snapshot = syncSnapshotSchema.parse(request.body);
    await repository.replace(request.tenoraUser!.id, snapshot);
    response.status(204).end();
  } catch (error) { next(error); }
});
app.delete("/v1/sync/tasks", authenticateSync, requireScope("tasks:sync"), async (request: AuthenticatedRequest, response, next) => {
  try { await repository.delete(request.tenoraUser!.id); response.status(204).end(); }
  catch (error) { next(error); }
});

app.post("/mcp", authenticateRead, requireScope("tasks:read"), async (request: AuthenticatedRequest, response, next) => {
  try {
    const server = createTenoraMcpServer(request.tenoraUser!.id, service, config.TENORA_APP_URL);
    await handleMcpRequest(request, response, server);
  } catch (error) { next(error); }
});
app.get("/mcp", (_request, response) => response.status(405).set("Allow", "POST").json({ error: "method_not_allowed" }));
app.delete("/mcp", (_request, response) => response.status(405).set("Allow", "POST").json({ error: "method_not_allowed" }));

app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
  if (error && typeof error === "object" && "issues" in error) return response.status(400).json({ error: "invalid_request" });
  console.error("request_failed", error instanceof Error ? error.message : "unknown");
  return response.status(500).json({ error: "internal_error" });
});

const listener = app.listen(config.PORT, () => console.log(`Tenora Agent Bridge listening on ${config.PORT}`));
async function shutdown() { listener.close(); await repository.close(); }
process.on("SIGTERM", () => { void shutdown(); });
process.on("SIGINT", () => { void shutdown(); });

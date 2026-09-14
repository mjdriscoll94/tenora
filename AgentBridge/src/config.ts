import { z } from "zod";

const configSchema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  OAUTH_ISSUER: z.string().url(),
  OAUTH_AUDIENCE: z.string().url(),
  OAUTH_JWKS_URL: z.string().url(),
  BRIDGE_BASE_URL: z.string().url(),
  TENORA_APP_URL: z.string().url()
});

export type BridgeConfig = z.infer<typeof configSchema>;

export function loadConfig(environment: NodeJS.ProcessEnv = process.env): BridgeConfig {
  return configSchema.parse(environment);
}

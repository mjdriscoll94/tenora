import type { NextFunction, Request, Response } from "express";
import { createRemoteJWKSet, jwtVerify } from "jose";

export interface AuthenticatedRequest extends Request {
  tenoraUser?: { id: string; scopes: Set<string> };
}

export function authenticationMiddleware(options: {
  issuer: string;
  audience: string;
  jwksURL: string;
  resourceMetadataURL: string;
}) {
  const keys = createRemoteJWKSet(new URL(options.jwksURL));
  return async (request: AuthenticatedRequest, response: Response, next: NextFunction) => {
    const token = request.header("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!token) return challenge(response, options.resourceMetadataURL);
    try {
      const verified = await jwtVerify(token, keys, { issuer: options.issuer, audience: options.audience });
      if (!verified.payload.sub) return challenge(response, options.resourceMetadataURL);
      const rawScope = typeof verified.payload.scope === "string" ? verified.payload.scope : "";
      request.tenoraUser = { id: verified.payload.sub, scopes: new Set(rawScope.split(/\s+/).filter(Boolean)) };
      next();
    } catch {
      return challenge(response, options.resourceMetadataURL);
    }
  };
}

export function requireScope(scope: string) {
  return (request: AuthenticatedRequest, response: Response, next: NextFunction) => {
    if (!request.tenoraUser?.scopes.has(scope)) {
      return response.status(403).json({ error: "insufficient_scope", required_scope: scope });
    }
    next();
  };
}

function challenge(response: Response, metadataURL: string) {
  response.setHeader("WWW-Authenticate", `Bearer resource_metadata="${metadataURL}", scope="tasks:read tasks:sync"`);
  return response.status(401).json({ error: "unauthorized" });
}

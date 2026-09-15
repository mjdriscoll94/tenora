import assert from "node:assert/strict";
import test from "node:test";
import type { NextFunction, Request, Response } from "express";
import { authenticationMiddleware } from "../src/auth.js";

function unauthenticatedChallenge(scopes: readonly string[]): string | undefined {
  const headers = new Map<string, string>();
  const response = {
    setHeader(name: string, value: string) { headers.set(name, value); return this; },
    status() { return this; },
    json() { return this; }
  } as unknown as Response;
  const request = { header: () => undefined } as unknown as Request;
  const middleware = authenticationMiddleware({
    issuer: "https://identity.example.com/",
    audience: "https://bridge.example.com",
    jwksURL: "https://identity.example.com/.well-known/jwks.json",
    resourceMetadataURL: "https://bridge.example.com/.well-known/oauth-protected-resource",
    challengeScopes: scopes
  });

  void middleware(request, response, (() => undefined) as NextFunction);
  return headers.get("WWW-Authenticate");
}

test("MCP authentication challenge requests read access only", () => {
  assert.match(unauthenticatedChallenge(["tasks:read"]) ?? "", /scope="tasks:read"$/);
});

test("sync authentication challenge requests sync access only", () => {
  assert.match(unauthenticatedChallenge(["tasks:sync"]) ?? "", /scope="tasks:sync"$/);
});

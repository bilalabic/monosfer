import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import httpMocks from "node-mocks-http";

test("GET /api/health returns service status", async () => {
  let createApp;

  try {
    ({ createApp } = await import("../src/app.js"));
  } catch {
    createApp = undefined;
  }

  assert.equal(
    typeof createApp,
    "function",
    "expected createApp() to be exported from src/app.js",
  );

  const app = createApp();
  const request = httpMocks.createRequest({
    method: "GET",
    url: "/api/health",
  });
  const response = httpMocks.createResponse({ eventEmitter: EventEmitter });

  await new Promise((resolve, reject) => {
    response.on("end", resolve);
    app.handle(request, response, reject);
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response._getJSONData(), { status: "ok" });
});

test("unknown routes return a standard 404 payload", async () => {
  const { createApp } = await import("../src/app.js");
  const app = createApp();
  const request = httpMocks.createRequest({
    method: "GET",
    url: "/api/does-not-exist",
  });
  const response = httpMocks.createResponse({ eventEmitter: EventEmitter });

  await new Promise((resolve, reject) => {
    response.on("end", resolve);
    app.handle(request, response, reject);
  });

  assert.equal(response.statusCode, 404);
  assert.deepEqual(response._getJSONData(), {
    error: {
      message: "Route not found",
      statusCode: 404,
    },
  });
});

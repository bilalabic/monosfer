import { mkdir, writeFile } from 'node:fs/promises';
import { testApplication } from '../tests/support/app.mjs';

// Offline export: replace infrastructure providers, never connect to a real database.
const { app, document } = await testApplication();
try {
  await mkdir(new URL('../artifacts/', import.meta.url), { recursive: true });
  await writeFile(new URL('../artifacts/openapi.json', import.meta.url), JSON.stringify(document, null, 2) + '\n');
} finally { await app.close(); }

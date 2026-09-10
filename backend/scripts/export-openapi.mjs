import { mkdir, writeFile } from 'node:fs/promises';
import { testApplication } from '../tests/support/app.mjs';

// Offline export: replace infrastructure providers, never connect to a real database.
for (const realtime of [false, true]) {
  const { app, document } = await testApplication({ realtime });
  try {
    await mkdir(new URL('../artifacts/', import.meta.url), { recursive: true });
    const filename = realtime ? 'realtime-openapi.json' : 'openapi.json';
    await writeFile(new URL(`../artifacts/${filename}`, import.meta.url), JSON.stringify(document, null, 2) + '\n');
  } finally { await app.close(); }
}

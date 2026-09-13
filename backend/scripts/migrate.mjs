import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';

// Explicit operator command: startup never changes the database schema.
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
try {
  await runner({
    databaseUrl: process.env.DATABASE_URL,
    dir: fileURLToPath(new URL('../migrations', import.meta.url)),
    direction: 'up', migrationsTable: 'pgmigrations',
    log: () => {},
  });
  console.log(JSON.stringify({ event: 'migrations_completed' }));
} catch {
  console.error(JSON.stringify({ event: 'migrations_failed' }));
  process.exitCode = 1;
}

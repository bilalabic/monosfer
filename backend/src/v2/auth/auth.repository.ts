import { randomUUID } from 'node:crypto';
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DatabaseService } from '../infrastructure/database.module.js';
import { publicUser, type UserRow } from '../users/users.repository.js';

@Injectable()
export class AuthRepository {
  constructor(private readonly db: DatabaseService) {}
  async createSession(address: string, sessionHash: string, expiresAt: string) {
    try {
      return await this.db.transaction(async client => {
        // Upsert locks the user row, serializing login against revoke-all.
        const { rows } = await client.query<UserRow>('INSERT INTO monosfer.users (id, wallet_address) VALUES ($1, $2) ON CONFLICT (wallet_address) DO UPDATE SET wallet_address = EXCLUDED.wallet_address RETURNING *', [randomUUID(), address.toLowerCase()]);
        const user = rows[0]!;
        await client.query('INSERT INTO monosfer.auth_sessions (session_hash, user_id, expires_at) VALUES ($1, $2, $3)', [sessionHash, user.id, expiresAt]);
        return publicUser(user);
      });
    } catch { throw new ServiceUnavailableException(); }
  }
  async findSession(sessionHash: string) {
    try {
      const { rows } = await this.db.query<UserRow & { expires_at: Date }>('SELECT u.*, s.expires_at FROM monosfer.auth_sessions s JOIN monosfer.users u ON u.id = s.user_id WHERE s.session_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now()', [sessionHash]);
      return rows[0] ? { user: publicUser(rows[0]), expiresAt: rows[0].expires_at.toISOString() } : null;
    } catch { throw new ServiceUnavailableException(); }
  }
  async revoke(sessionHash: string, userId: string, all: boolean): Promise<string[]> {
    try {
      return await this.db.transaction(async client => {
        await client.query('SELECT id FROM monosfer.users WHERE id = $1 FOR UPDATE', [userId]);
        const { rows } = await client.query<{ session_hash: string }>(
          'UPDATE monosfer.auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL AND ($2::boolean OR session_hash = $3) RETURNING session_hash', [userId, all, sessionHash]);
        return rows.map(row => row.session_hash);
      });
    } catch { throw new ServiceUnavailableException(); }
  }
}

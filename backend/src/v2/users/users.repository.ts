import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { getAddress } from 'viem';
import { DatabaseService } from '../infrastructure/database.module.js';
import type { UpdateUserDto, UserDto } from './users.dto.js';

export interface UserRow {
  id: string; wallet_address: string; role: UserDto['role']; display_name: string | null;
  email: string | null; phone: string | null; courier_profile: UserDto['courierProfile'];
  created_at: Date; updated_at: Date;
}
export function publicUser(row: UserRow): UserDto {
  return { id: row.id, walletAddress: getAddress(row.wallet_address), role: row.role,
    displayName: row.display_name, email: row.email, phone: row.phone, courierProfile: row.courier_profile,
    createdAt: row.created_at.toISOString(), updatedAt: row.updated_at.toISOString() };
}
@Injectable()
export class UsersRepository {
  constructor(private readonly db: DatabaseService) {}
  async update(id: string, input: UpdateUserDto): Promise<UserDto> {
    // Fixed column map; only values from the request enter SQL parameters.
    const columns = { displayName: 'display_name', email: 'email', phone: 'phone', role: 'role', courierProfile: 'courier_profile' } as const;
    const values: unknown[] = [id];
    // Transformed DTO instances also define omitted class fields as undefined.
    // Preserve omitted values; explicit null still clears nullable fields.
    const assignments = Object.entries(columns).filter(([key]) => input[key as keyof UpdateUserDto] !== undefined).map(([key, column]) => {
      const value = input[key as keyof UpdateUserDto];
      values.push(key === 'courierProfile' && value !== null ? JSON.stringify(value) : value);
      return `${column} = $${values.length}`;
    });
    try {
      const result = assignments.length
        ? await this.db.query<UserRow>(`UPDATE monosfer.users SET ${assignments.join(', ')}, updated_at = now() WHERE id = $1 RETURNING *`, values)
        : await this.db.query<UserRow>('SELECT * FROM monosfer.users WHERE id = $1', [id]);
      if (!result.rows[0]) throw new Error();
      return publicUser(result.rows[0]);
    } catch { throw new ServiceUnavailableException(); }
  }
}

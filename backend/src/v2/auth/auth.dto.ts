import { ApiProperty } from '@nestjs/swagger';
import { IsEthereumAddress, IsString, Length, Matches } from 'class-validator';
import { UserDto } from '../users/users.dto.js';

export class NonceInputDto {
  @ApiProperty({ pattern: '^0x[0-9a-fA-F]{40}$' })
  @IsEthereumAddress()
  address!: string;
}
export class VerifyInputDto {
  @ApiProperty({ maxLength: 4096 }) @IsString() @Length(1, 4096)
  message!: string;
  @ApiProperty({ maxLength: 8194, description: 'EIP-191 signature, or deployed ERC-1271 wallet signature.' })
  @IsString() @Length(4, 8194) @Matches(/^0x(?:[a-fA-F0-9]{2})+$/)
  signature!: string;
}
export class NonceResponseDto {
  @ApiProperty() address!: string;
  @ApiProperty() nonce!: string;
  @ApiProperty() message!: string;
  @ApiProperty({ format: 'date-time' }) expiresAt!: string;
}
export class SessionExpiryDto { @ApiProperty({ format: 'date-time' }) expiresAt!: string; }
export class SessionResponseDto {
  @ApiProperty({ type: UserDto }) user!: UserDto;
  @ApiProperty({ type: SessionExpiryDto }) session!: SessionExpiryDto;
  @ApiProperty() csrfToken!: string;
}

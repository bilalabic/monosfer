import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEmail, IsIn, IsOptional, IsString, Length, Matches, MaxLength, ValidateIf, ValidateNested, IsObject } from 'class-validator';

export class CourierProfileDto {
  @ApiProperty({ enum: ['on_foot', 'bicycle', 'motorcycle', 'car'] })
  @IsIn(['on_foot', 'bicycle', 'motorcycle', 'car'])
  vehicleType!: 'on_foot' | 'bicycle' | 'motorcycle' | 'car';
}
export class UpdateUserDto {
  @ApiPropertyOptional({ type: String, nullable: true, minLength: 1, maxLength: 80 })
  @IsOptional() @IsString() @Length(1, 80)
  displayName?: string | null;

  @ApiPropertyOptional({ type: String, nullable: true, maxLength: 254, format: 'email', description: 'Self-reported; not verified or used for authentication.' })
  @IsOptional() @IsEmail() @MaxLength(254)
  email?: string | null;

  @ApiPropertyOptional({ type: String, nullable: true, pattern: '^\\+[1-9][0-9]{7,14}$', description: 'Self-reported E.164; not verified.' })
  @IsOptional() @IsString() @Matches(/^\+[1-9][0-9]{7,14}$/)
  phone?: string | null;

  @ApiPropertyOptional({ enum: ['customer', 'courier'], description: 'User-selected persona only; does not grant operational permissions.' })
  @ValidateIf((_object, value) => value !== undefined) @IsIn(['customer', 'courier'])
  role?: 'customer' | 'courier';

  @ApiPropertyOptional({ type: CourierProfileDto, nullable: true })
  @IsOptional() @IsObject() @ValidateNested() @Type(() => CourierProfileDto)
  courierProfile?: CourierProfileDto | null;
}
export class UserDto {
  @ApiProperty({ format: 'uuid' }) id!: string;
  @ApiProperty() walletAddress!: string;
  @ApiProperty({ enum: ['customer', 'courier'] }) role!: 'customer' | 'courier';
  @ApiProperty({ type: String, nullable: true }) displayName!: string | null;
  @ApiProperty({ type: String, nullable: true }) email!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: CourierProfileDto, nullable: true }) courierProfile!: CourierProfileDto | null;
  @ApiProperty({ format: 'date-time' }) createdAt!: string;
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}

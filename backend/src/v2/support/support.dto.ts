import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { Type } from 'class-transformer';
import { DeliveryIdDto } from '../indexer/read.module.js';

export class CaseIdDto { @ApiProperty({format:'uuid'}) @IsUUID() caseId!: string; }
export class SupportEvidenceIdDto extends DeliveryIdDto { @ApiProperty({format:'uuid'}) @IsUUID() evidenceId!: string; }
export class WalletIdDto { @ApiProperty() @Matches(/^0x[0-9a-fA-F]{40}$/) wallet!: string; }
export class TraceIdDto { @ApiProperty({format:'uuid'}) @IsUUID() requestId!: string; }
export class CaseCreateDto extends DeliveryIdDto {
  @ApiPropertyOptional({description:'Support/admin allowlisted wallet'}) @ValidateIf((_,v)=>v!==undefined) @Matches(/^0x[0-9a-fA-F]{40}$/) assignee?: string;
  @ApiPropertyOptional({maxLength:2000}) @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(2000) note?: string;
}
export class CasePatchDto {
  @ApiPropertyOptional({enum:['open','investigating','closed']}) @ValidateIf((_,v)=>v!==undefined) @IsIn(['open','investigating','closed']) status?: string;
  @ApiPropertyOptional({nullable:true}) @ValidateIf((_,v)=>v!==undefined && v!==null) @Matches(/^0x[0-9a-fA-F]{40}$/) assignee?: string | null;
  @ApiPropertyOptional({maxLength:2000}) @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(2000) note?: string;
}
export class SupportPageDto {
  @ApiPropertyOptional({default:25,minimum:1,maximum:100}) @IsOptional() @Type(()=>Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @ApiPropertyOptional({format:'uuid'}) @IsOptional() @IsUUID() after?: string;
}
export class AuditPageDto {
  @ApiPropertyOptional({default:25,minimum:1,maximum:100}) @IsOptional() @Type(()=>Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @ApiPropertyOptional({description:'Exclusive ascending audit ID'}) @IsOptional() @Matches(/^[0-9]{1,18}$/) after?: string;
}

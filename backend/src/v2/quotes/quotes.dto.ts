import { Type } from 'class-transformer';
import { IsDefined, IsEnum, IsNumber, IsObject, IsString, Matches, Max, MaxLength, Min, MinLength, ValidateIf, ValidateNested } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class QuoteMetadataDto {
  @ApiProperty({ enum: ['document','food','small','medium','large'] })
  @IsEnum({ document:'document', food:'food', small:'small', medium:'medium', large:'large' }) packageType!: string;
  @ApiProperty({ enum: ['standard','express','instant'] })
  @IsEnum({ standard:'standard', express:'express', instant:'instant' }) urgency!: string;
}
export class QuoteLocationDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(1000) @Matches(/\S/) address!: string;
  @ApiProperty() @IsNumber() @Min(-90) @Max(90) lat!: number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) lng!: number;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(32) contactPhone?: string;
}
export class QuoteDropoffDto extends QuoteLocationDto {
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(160) recipientName?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(160) businessName?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(160) contactPerson?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(160) department?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(32) recipientPhone?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(1000) recipientNote?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(100) orderNumber?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(64) deliveryCode?: string;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @Matches(/^0x[0-9a-fA-F]{40}$/) recipientWallet?: string;
}
export class QuotePrivatePayloadDto {
  @ApiProperty({ type: QuoteLocationDto }) @IsDefined() @IsObject() @ValidateNested() @Type(()=>QuoteLocationDto) pickup!: QuoteLocationDto;
  @ApiProperty({ type: QuoteDropoffDto }) @IsDefined() @IsObject() @ValidateNested() @Type(()=>QuoteDropoffDto) dropoff!: QuoteDropoffDto;
  @ApiPropertyOptional() @ValidateIf((_,v)=>v!==undefined) @IsString() @MaxLength(2000) notes?: string;
}
export class CreateQuoteDto {
  @ApiProperty({ type: String, pattern: '^[1-9][0-9]{0,28}$', description: 'Positive uint96, contract units; no fiat conversion' })
  @IsString() @Matches(/^[1-9][0-9]{0,28}$/) declaredValue!: string;
  @ApiProperty({ type: QuoteMetadataDto }) @IsDefined() @IsObject() @ValidateNested() @Type(()=>QuoteMetadataDto) metadata!: QuoteMetadataDto;
  @ApiProperty({ type: QuotePrivatePayloadDto }) @IsDefined() @IsObject() @ValidateNested() @Type(()=>QuotePrivatePayloadDto) privatePayload!: QuotePrivatePayloadDto;
}
export class QuoteDigestDto { @ApiProperty() @Matches(/^0x[0-9a-fA-F]{64}$/) quoteDigest!: string }
export class RefreshQuoteDto { /* Global whitelist rejects every supplied field. */ }
export class CoverageQuoteDto {
  @ApiProperty() customer!: string;
  @ApiProperty({ minimum: 1, maximum: 3 }) riskTier!: number;
  @ApiProperty({ type: String }) declaredValue!: string;
  @ApiProperty({ type: String }) requiredCoverage!: string;
  @ApiProperty({ type: String, description: 'Unix seconds' }) issuedAt!: string;
  @ApiProperty({ type: String, description: 'Unix seconds' }) expiresAt!: string;
  @ApiProperty() salt!: string;
}
export class QuoteDomainDto {
  @ApiProperty({ enum:['MONOSFER'] }) name!: string;
  @ApiProperty({ enum:['1'] }) version!: string;
  @ApiProperty({ type:Number, enum:[10143] }) chainId!: number;
  @ApiProperty() verifyingContract!: string;
}
export class QuoteFieldDto {
  @ApiProperty() name!: string;
  @ApiProperty() type!: string;
}
export class QuoteTypesDto { @ApiProperty({ type:[QuoteFieldDto] }) Quote!: QuoteFieldDto[] }
export class QuoteTypedDataDto {
  @ApiProperty({ type:QuoteDomainDto }) domain!: QuoteDomainDto;
  @ApiProperty({ type:QuoteTypesDto }) types!: QuoteTypesDto;
  @ApiProperty({ enum:['Quote'] }) primaryType!: string;
  @ApiProperty({ type:CoverageQuoteDto }) message!: CoverageQuoteDto;
}
export class QuoteResponseDto {
  @ApiProperty({ format: 'uuid' }) privateRecordId!: string;
  @ApiProperty() quoteDigest!: string;
  @ApiProperty({ type: CoverageQuoteDto }) quote!: CoverageQuoteDto;
  @ApiProperty() signature!: string;
  @ApiProperty({ type:QuoteTypedDataDto, description: 'EIP-712 domain/types/primaryType/message; uint amounts are decimal strings' }) typedData!: object;
  @ApiProperty({ format: 'date-time' }) expiresAt!: string;
  @ApiProperty({ enum: ['issued'] }) status!: string;
}
export class QuoteStatusDto {
  @ApiProperty() quoteDigest!: string;
  @ApiProperty({ format: 'uuid' }) privateRecordId!: string;
  @ApiProperty({ format: 'date-time' }) expiresAt!: string;
  @ApiProperty({ enum: ['issued','expired','refreshed','redeemed','linked'] }) status!: string;
  @ApiProperty({ type: String, nullable: true }) deliveryId!: string | null;
}

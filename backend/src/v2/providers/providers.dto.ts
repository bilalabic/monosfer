import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsISO8601, IsNumber, IsObject, IsString, IsUUID, Max, MaxLength, Min, MinLength, ValidateIf, ValidateNested } from 'class-validator';
export class EvidenceGpsDto {
  @ApiProperty() @IsNumber() @Min(-90) @Max(90) lat!:number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) lng!:number;
  @ApiProperty({format:'date-time'}) @IsISO8601({strict:true}) capturedAt!:string;
}
export class EvidenceInputDto {
  @ApiProperty({enum:['text/plain','image/png','image/jpeg']}) @IsEnum({text:'text/plain',png:'image/png',jpeg:'image/jpeg'}) contentType!:string;
  @ApiPropertyOptional({maxLength:8192}) @ValidateIf((_,v)=>v!==undefined) @IsString() @MinLength(1) @MaxLength(8192) text?:string;
  @ApiPropertyOptional({maxLength:32768}) @ValidateIf((_,v)=>v!==undefined) @IsString() @MinLength(1) @MaxLength(32768) contentBase64?:string;
  @ApiPropertyOptional({type:EvidenceGpsDto}) @ValidateIf((_,v)=>v!==undefined) @IsObject() @ValidateNested() @Type(()=>EvidenceGpsDto) gps?:EvidenceGpsDto;
}
export class EvidenceContentDto extends EvidenceInputDto {
  @ApiProperty({description:'SHA-256 of the original UTF-8 text or decoded image bytes'}) evidenceHash!:string;
}
export class EvidenceResultDto {
  @ApiProperty({format:'uuid'}) evidenceId!:string;
  @ApiProperty({enum:['pending','ready','failed']}) status!:string;
  @ApiProperty() contentType!:string;
}
export class RouteResultDto {
  @ApiProperty({enum:['straight-line-dev']}) provider!:string;
  @ApiProperty() distanceMeters!:number;
  @ApiProperty() durationSeconds!:number;
  @ApiProperty({format:'date-time'}) estimatedAt!:string;
  @ApiProperty({format:'date-time'}) expiresAt!:string;
}
export class NotificationQueryDto {
  @ApiPropertyOptional({minimum:1,maximum:50,default:25}) @ValidateIf((_,v)=>v!==undefined) @Type(()=>Number) @IsInt() @Min(1) @Max(50) limit=25;
  @ApiPropertyOptional({format:'uuid'}) @ValidateIf((_,v)=>v!==undefined) @IsUUID() before?:string;
}
export class NotificationDto {
  @ApiProperty({format:'uuid'}) id!:string;
  @ApiProperty() deliveryId!:string;
  @ApiProperty({enum:['delivery_state','evidence_ready']}) template!:string;
  @ApiProperty({type:'object',additionalProperties:{type:'string'}}) arguments!:Record<string,string>;
  @ApiProperty({format:'date-time'}) createdAt!:string;
}
export class NotificationPageDto {
  @ApiProperty({type:[NotificationDto]}) data!:NotificationDto[];
  @ApiProperty({type:String,format:'uuid',nullable:true}) nextCursor!:string|null;
}

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsISO8601, IsInt, IsNumber, Max, Min, ValidateIf } from 'class-validator';
export class TrackingEmptyDto {}
export class TrackingLocationDto {
  @ApiProperty({minimum:-90,maximum:90}) @IsNumber() @Min(-90) @Max(90) lat!:number;
  @ApiProperty({minimum:-180,maximum:180}) @IsNumber() @Min(-180) @Max(180) lng!:number;
  @ApiProperty({minimum:1,maximum:2147483647}) @IsInt() @Min(1) @Max(2147483647) sequence!:number;
  @ApiProperty({format:'date-time'}) @IsISO8601({strict:true}) capturedAt!:string;
  @ApiPropertyOptional({minimum:0,maximum:10000}) @ValidateIf((_,v)=>v!==undefined) @IsNumber() @Min(0) @Max(10000) accuracyMeters?:number;
}
export class TrackingSessionDto {
  @ApiProperty() trackingSession!:string;
  @ApiProperty({format:'date-time'}) expiresAt!:string;
  @ApiProperty({enum:['publish','view']}) mode!:string;
}
export class TrackingSampleDto extends TrackingLocationDto {
  @ApiProperty({format:'date-time'}) receivedAt!:string;
  @ApiProperty({format:'date-time'}) expiresAt!:string;
}
export class TrackingPublishedDto { @ApiProperty() eventId!:string; }
export class TrackingLatestDto {
  @ApiProperty({type:TrackingSampleDto,nullable:true,description:'Fresh GPS sample; null after TTL'}) location!:TrackingSampleDto|null;
  @ApiProperty({type:String,nullable:true}) eventId!:string|null;
}

import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';
export class AcceptanceInputDto {}
export class PodInputDto {
  @ApiProperty({enum:['otp'],description:'Only private delivery-code verification is supported.'}) @IsIn(['otp']) proofType!: 'otp';
  @ApiProperty({writeOnly:true,minLength:1,maxLength:64}) @IsString() @MinLength(1) @MaxLength(64) code!:string;
}
export class AcceptanceResponseDto {
  @ApiProperty({type:Object,description:'PickupAcceptance fields; integer values are decimal strings.'}) acceptance!:object;
  @ApiProperty({type:Object,description:'EIP-712 domain, types, primaryType and message for customer wallet signing.'}) typedData!:object;
  @ApiProperty() digest!:string;
  @ApiProperty({format:'date-time'}) expiresAt!:string;
  @ApiProperty({enum:['issued']}) status!:string;
}
export class PodResponseDto {
  @ApiProperty({type:Object,description:'PodAttestation fields; integer values are decimal strings.'}) attestation!:object;
  @ApiProperty({type:Object}) typedData!:object;
  @ApiProperty() digest!:string;
  @ApiProperty() signature!:string;
  @ApiProperty({format:'date-time'}) expiresAt!:string;
  @ApiProperty({enum:['issued']}) status!:string;
}

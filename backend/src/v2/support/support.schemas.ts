// Explicit response contracts: never let database row shape become the public schema implicitly.
const text={type:'string' as const};
const timestamp={...text,format:'date-time'};
const uuid={...text,format:'uuid'};
const wallet={...text,pattern:'^0x[0-9a-f]{40}$'};
export const caseSchema={type:'object' as const,additionalProperties:false,
  required:['id','stream','delivery_id','status','assignee','created_by','created_at','updated_at'],properties:{
    id:uuid,stream:text,delivery_id:{...text,pattern:'^[0-9]+$'},status:{...text,enum:['open','investigating','closed']},
    assignee:{...wallet,nullable:true},created_by:wallet,created_at:timestamp,updated_at:timestamp,
  }};
const caseEvent={type:'object' as const,additionalProperties:false,properties:{id:text,actor_wallet:wallet,
  action:{...text,enum:['created','updated']},status:{...text,enum:['open','investigating','closed']},assignee:{...wallet,nullable:true},created_at:timestamp}};
export const caseDetailSchema={...caseSchema,properties:{...caseSchema.properties,events:{type:'array' as const,maxItems:100,items:caseEvent}}};
export const casePageSchema={type:'object' as const,additionalProperties:false,properties:{data:{type:'array' as const,maxItems:100,items:caseSchema},nextCursor:{...uuid,nullable:true}}};
export const evidenceSchema={type:'object' as const,additionalProperties:false,properties:{id:uuid,content_type:{...text,enum:['text/plain','image/png','image/jpeg']},
  status:{...text,enum:['pending','ready','failed']},created_at:timestamp}};
export const evidencePageSchema={type:'object' as const,additionalProperties:false,properties:{data:{type:'array' as const,maxItems:100,items:evidenceSchema},hasMore:{type:'boolean' as const}}};
const privateLocation={type:'object' as const,additionalProperties:false,properties:{
  ...Object.fromEntries(['address','contactPhone','recipientName','businessName','contactPerson','recipientPhone'].map(k=>[k,text])),lat:{type:'number' as const},lng:{type:'number' as const}}};
export const supportPrivateSchema={type:'object' as const,additionalProperties:false,properties:{privateRecordId:uuid,pickup:privateLocation,dropoff:privateLocation}};
export const auditPageSchema={type:'object' as const,additionalProperties:false,properties:{data:{type:'array' as const,maxItems:100,items:{type:'object' as const,additionalProperties:false,properties:{
  id:text,request_id:uuid,actor_wallet:{...wallet,nullable:true},action:text,target_type:text,target_id:text,
  decision:{...text,enum:['allowed','denied','failed']},reason_code:text,created_at:timestamp}}},nextCursor:{...text,nullable:true}}};
export const reputationSchema={type:'object' as const,additionalProperties:false,properties:{wallet,status:{...text,enum:['ready','rebuild_pending']},
  sourceBlock:text,rebuiltAt:{...timestamp,nullable:true},counters:{type:'object' as const,nullable:true,additionalProperties:false,properties:Object.fromEntries(
    ['customerDeliveries','courierDeliveries','customerCompleted','courierCompleted','returned','cancelled','expired'].map(k=>[k,{...text,pattern:'^[0-9]+$'}]))},
  referral:{type:'object' as const,properties:{status:{...text,enum:['pending_policy']}}},
  reward:{type:'object' as const,properties:{status:{...text,enum:['pending_policy']}}},
}};
export const tracesSchema={type:'object' as const,additionalProperties:false,properties:{data:{type:'array' as const,maxItems:100,items:{type:'object' as const,additionalProperties:false,properties:{
  request_id:uuid,event:{...text,enum:['http_response']},status_code:{type:'integer' as const},duration_ms:{type:'integer' as const,minimum:0},created_at:timestamp}}}}};

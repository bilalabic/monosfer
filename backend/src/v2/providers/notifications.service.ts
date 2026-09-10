import { ForbiddenException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DatabaseService } from '../infrastructure/database.module.js';
import { DeliveryAccess } from '../operations/access.js';
import type { NotificationQueryDto } from './providers.dto.js';

@Injectable()
export class NotificationsService {
  constructor(private readonly db:DatabaseService,private readonly access:DeliveryAccess){}
  async list(wallet:string,query:NotificationQueryDto){
    this.access.available();wallet=wallet.toLowerCase();
    let rows;
    try{rows=(await this.db.query(`SELECT n.* FROM monosfer.notifications n WHERE n.wallet=$1
      AND ($2::uuid IS NULL OR (n.created_at,n.id)<(SELECT created_at,id FROM monosfer.notifications WHERE id=$2 AND wallet=$1))
      ORDER BY n.created_at DESC,n.id DESC LIMIT $3`,[wallet,query.before??null,query.limit+1])).rows;}
    catch{throw new ServiceUnavailableException();}
    const data:Array<{id:string;deliveryId:string;template:string;arguments:Record<string,string>;createdAt:string}>=[];
    for(const row of rows.slice(0,query.limit)){
      try{await this.access.withDelivery(row.delivery_id,wallet,false,async context=>{
        if(context.binding===row.binding)data.push({id:row.id,deliveryId:row.delivery_id,template:row.template,arguments:row.arguments,createdAt:row.created_at.toISOString()});
      });}catch(error){if(!(error instanceof ForbiddenException))throw error;}
    }
    return {data,nextCursor:rows.length>query.limit?rows[query.limit-1]!.id:null};
  }
}

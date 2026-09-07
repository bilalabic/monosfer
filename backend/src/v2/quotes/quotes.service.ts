import { randomBytes, randomUUID } from 'node:crypto';
import { ConflictException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { Address, Hex } from 'viem';
import { ConfigService } from '../config/config.js';
import { PrivateDataCrypto, recordAad } from '../private-data/crypto.js';
import { QuoteChain, QuoteSigner } from './chain.js';
import { QuotesRepository, type IdempotencyRow, type Issuance } from './quotes.repository.js';
import { RiskAdapter, type RiskInput } from './risk.js';
import { amount, type CoverageQuote } from './typed-data.js';
import { idempotencyScope, privateHash, responseAad } from './idempotency.js';
import type { CreateQuoteDto, QuoteResponseDto } from './quotes.dto.js';

@Injectable()
export class QuotesService {
  private readonly crypto: PrivateDataCrypto;
  constructor(private readonly config: ConfigService, private readonly repository: QuotesRepository,
    private readonly risk: RiskAdapter, private readonly chain: QuoteChain, private readonly signer: QuoteSigner) {
    this.crypto = new PrivateDataCrypto(config.settings);
  }
  async issue(customer: string, key: unknown, input?: CreateQuoteDto, refreshDigest?: string): Promise<QuoteResponseDto> {
    customer = customer.toLowerCase(); refreshDigest = refreshDigest?.toLowerCase();
    const s = this.config.settings;
    const stream = `${s.indexer.chainId}:${s.indexer.deployment?.address.toLowerCase()}`;
    const scope = idempotencyScope(key,customer,refreshDigest??'delivery',stream,s.privateDataMasterKeyB64);
    const requestHash = privateHash(input??{},s.privateDataMasterKeyB64);
    if (input) amount(input.declaredValue);
    this.chain.assertAvailable();
    const snapshot = await this.chain.snapshot();
    return this.repository.transaction(async client=>{
      // Database lock covers cross-process concurrent retries; a rollback releases it.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[scope]);
      const cached = (await client.query<IdempotencyRow>('SELECT * FROM monosfer.idempotency_keys WHERE scope_hash=$1',[scope])).rows[0];
      if (cached) {
        if (cached.request_hash!==requestHash || cached.expires_at.getTime()<=Date.now()) throw new ConflictException();
        const issued = await this.repository.owned(client,cached.quote_digest,customer);
        const scaled=amount(issued.quote.declaredValue)*snapshot.coverageBps;
        const coverage=amount(issued.quote.requiredCoverage);
        if (issued.expires_at.getTime()<=Date.now() || issued.signer!==snapshot.signer.toLowerCase() ||
          issued.export_fingerprint!==s.indexer.fingerprint || issued.quote_bundle_fingerprint!==this.chain.bundle.fingerprint ||
          BigInt(issued.quote.expiresAt)-BigInt(issued.quote.issuedAt)>BigInt(snapshot.validity) ||
          coverage<scaled*snapshot.minBps/100000000n || coverage>scaled*snapshot.maxBps/100000000n ||
          await this.chain.redeemed(issued.digest as Hex,snapshot)) throw new ConflictException();
        return this.crypto.decrypt(cached.encrypted_response,responseAad(scope)) as unknown as QuoteResponseDto;
      }
      let privateRecordId: string; let riskInput: RiskInput;
      if (refreshDigest) {
        const previous = await this.repository.owned(client,refreshDigest,customer);
        if (previous.stream!==stream || previous.export_fingerprint!==s.indexer.fingerprint) throw new ConflictException();
        privateRecordId = previous.private_record_id;
        await client.query('SELECT id FROM monosfer.private_delivery_records WHERE id=$1 FOR UPDATE',[privateRecordId]);
        const history = (await client.query<Issuance>('SELECT * FROM monosfer.risk_quote_issuances WHERE private_record_id=$1',[privateRecordId])).rows;
        const links = await client.query('SELECT 1 FROM monosfer.private_delivery_links WHERE private_record_id=$1',[privateRecordId]);
        if (links.rowCount || history.some(q=>q.refreshed_from===refreshDigest)) throw new ConflictException();
        for (const quote of history) {
          // Contract expiry is inclusive: finalized time must be strictly greater.
          if (snapshot.timestamp<=BigInt(quote.quote.expiresAt) || await this.chain.redeemed(quote.digest as Hex,snapshot) ||
            await this.repository.trustedDelivery(client,quote)) throw new ConflictException();
        }
        riskInput = (await client.query('SELECT public_input FROM monosfer.risk_quote_inputs WHERE quote_digest=$1',[refreshDigest])).rows[0]!.public_input as RiskInput;
      } else {
        if (!input) throw new ServiceUnavailableException();
        privateRecordId=randomUUID(); riskInput={declaredValue:input.declaredValue,metadata:input.metadata};
        const context={ id:privateRecordId,source_namespace:'quote-api-v1',source_collection:'deliveries',legacy_mongo_id:null,kind:'delivery',schema_version:1 };
        const envelope=this.crypto.encrypt(input.privatePayload as unknown as Record<string,unknown>,recordAad(context));
        await client.query(`INSERT INTO monosfer.private_delivery_records
          (id,source,verification_status,source_namespace,source_collection,kind,customer_wallet,legacy_status,metadata,encrypted_payload)
          VALUES($1,'quote_api','pending_chain','quote-api-v1','deliveries','delivery',$2,'quote_pending',$3,$4)`,
        [privateRecordId,customer,JSON.stringify(input.metadata),JSON.stringify(envelope)]);
      }
      const decision=await this.risk.evaluate(riskInput,snapshot);
      const coverage=amount(decision.requiredCoverage);
      const scaled=amount(riskInput.declaredValue)*snapshot.coverageBps;
      if (decision.riskTier!==1 || coverage<scaled*snapshot.minBps/100000000n || coverage>scaled*snapshot.maxBps/100000000n) throw new ServiceUnavailableException();
      const issuedAt=Math.floor(Date.now()/1000);
      const quote: CoverageQuote={customer:customer as Address,riskTier:decision.riskTier,declaredValue:riskInput.declaredValue,
        requiredCoverage:decision.requiredCoverage,issuedAt:String(issuedAt),expiresAt:String(issuedAt+s.quotes.ttlSeconds),salt:`0x${randomBytes(32).toString('hex')}`};
      const signed=await this.signer.sign(quote,snapshot);
      const expiresAt=new Date(Number(quote.expiresAt)*1000).toISOString();
      const response={privateRecordId,quoteDigest:signed.quoteDigest,quote,signature:signed.signature,typedData:signed.typedData,expiresAt,status:'issued'};
      await client.query(`INSERT INTO monosfer.risk_quote_issuances
        (digest,private_record_id,customer,stream,export_fingerprint,quote_bundle_fingerprint,signer,quote,expires_at,issued_block,refreshed_from)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,[signed.quoteDigest,privateRecordId,customer,stream,s.indexer.fingerprint,
        this.chain.bundle.fingerprint,snapshot.signer.toLowerCase(),JSON.stringify(quote),expiresAt,String(snapshot.block),refreshDigest??null]);
      await client.query(`INSERT INTO monosfer.risk_quote_inputs(quote_digest,public_input,policy_version,policy_snapshot) VALUES($1,$2,$3,$4)`,
        [signed.quoteDigest,JSON.stringify(riskInput),decision.policyVersion,JSON.stringify(snapshot,(_,v)=>typeof v==='bigint'?String(v):v)]);
      await client.query(`INSERT INTO monosfer.idempotency_keys(scope_hash,request_hash,quote_digest,encrypted_response,expires_at) VALUES($1,$2,$3,$4,$5)`,
        [scope,requestHash,signed.quoteDigest,JSON.stringify(this.crypto.encrypt(response,responseAad(scope))),new Date(Date.now()+s.quotes.idempotencyTtlSeconds*1000)]);
      await client.query(`INSERT INTO monosfer.transactional_outbox(id,topic,quote_digest) VALUES($1,'quote.link',$2)`,[randomUUID(),signed.quoteDigest]);
      return response;
    });
  }
  async status(digest: string, customer: string) {
    if (this.config.settings.environment==='production') throw new ServiceUnavailableException();
    return this.repository.transaction(async client=>{
      const row=await this.repository.owned(client,digest.toLowerCase(),customer.toLowerCase());
      const delivery=await this.repository.trustedDelivery(client,row);
      const refreshed=(await client.query('SELECT 1 FROM monosfer.risk_quote_issuances WHERE refreshed_from=$1',[row.digest])).rowCount;
      return {quoteDigest:row.digest,privateRecordId:row.private_record_id,expiresAt:row.expires_at.toISOString(),
        status:delivery?(delivery.private_record_id?'linked':'redeemed'):refreshed?'refreshed':row.expires_at.getTime()<=Date.now()?'expired':'issued',
        deliveryId:delivery?.delivery_id??null};
    });
  }
}

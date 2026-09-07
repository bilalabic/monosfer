import { createCipheriv, createDecipheriv, createSecretKey, randomBytes, type KeyObject } from 'node:crypto';

export interface PrivateKeySettings { privateDataMasterKeyB64: string; privateDataKeyId: string }
export interface Envelope { alg: 'AES-256-GCM'; keyId: string; iv: string; tag: string; ciphertext: string; aad: string }
export interface RecordContext { id: string; source_namespace: string; source_collection: string; legacy_mongo_id: string; kind: string; schema_version: number }

export function parsePrivateKey(env: NodeJS.ProcessEnv): PrivateKeySettings {
  const key = env.PRIVATE_DATA_MASTER_KEY_B64 ?? '';
  if (!/^[A-Za-z0-9+/]{43}=$/.test(key) || Buffer.from(key, 'base64').length !== 32 || Buffer.from(key, 'base64').toString('base64') !== key) {
    throw new Error('Invalid PRIVATE_DATA_MASTER_KEY_B64');
  }
  const keyId = env.PRIVATE_DATA_KEY_ID ?? '';
  if (!/^[a-zA-Z0-9_-]{1,64}$/.test(keyId)) throw new Error('Invalid PRIVATE_DATA_KEY_ID');
  return { privateDataMasterKeyB64: key, privateDataKeyId: keyId };
}

export function recordAad(record: RecordContext): string {
  return JSON.stringify(['monosfer/private-data', record.schema_version, record.id, record.source_namespace,
    record.source_collection, record.legacy_mongo_id, record.kind]);
}

export class PrivateDataCrypto {
  readonly #key: KeyObject;
  readonly #keyId: string;
  constructor(settings: PrivateKeySettings) {
    const validated = parsePrivateKey({ PRIVATE_DATA_MASTER_KEY_B64: settings.privateDataMasterKeyB64, PRIVATE_DATA_KEY_ID: settings.privateDataKeyId });
    this.#key = createSecretKey(Buffer.from(validated.privateDataMasterKeyB64, 'base64'));
    this.#keyId = validated.privateDataKeyId;
  }
  encrypt(payload: Record<string, unknown>, aad: string): Envelope {
    try {
      const plain = JSON.stringify(payload);
      if (Buffer.byteLength(plain) > 1048576) throw new Error();
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', this.#key, iv, { authTagLength: 16 });
      cipher.setAAD(Buffer.from(aad));
      const ciphertext = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
      return { alg: 'AES-256-GCM', keyId: this.#keyId, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), ciphertext: ciphertext.toString('base64'), aad };
    } catch { throw new Error('Private data encryption failed'); }
  }
  decrypt(envelope: Envelope, expectedAad: string): Record<string, unknown> {
    try {
      if (envelope.alg !== 'AES-256-GCM' || envelope.keyId !== this.#keyId || envelope.aad !== expectedAad) throw new Error();
      const decode = (value: string, length?: number) => {
        const bytes = Buffer.from(value, 'base64');
        if (bytes.toString('base64') !== value || (length !== undefined && bytes.length !== length)) throw new Error();
        return bytes;
      };
      if (envelope.ciphertext.length > 1398104) throw new Error();
      const decipher = createDecipheriv('aes-256-gcm', this.#key, decode(envelope.iv, 12), { authTagLength: 16 });
      decipher.setAAD(Buffer.from(expectedAad));
      decipher.setAuthTag(decode(envelope.tag, 16));
      const plain = Buffer.concat([decipher.update(decode(envelope.ciphertext)), decipher.final()]);
      return JSON.parse(plain.toString('utf8')) as Record<string, unknown>;
    } catch { throw new Error('Private data decryption failed'); }
  }
}

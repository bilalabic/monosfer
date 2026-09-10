import { pino, type DestinationStream, type Logger } from 'pino';
import type { LoggerService } from '@nestjs/common';

export function createLogger(destination?: DestinationStream): Logger {
  const options = {
    level: 'info',
    redact: {
      paths: ['req', 'res', 'body', 'headers', 'err', 'error', 'authorization', 'cookie', 'password', 'token', 'accessToken', 'privateKey', 'evidenceUrl', 'recipient', 'address', '*.password', '*.token', '*.authorization', '*.cookie',
        ...['payload', 'encrypted_payload', 'pickup', 'dropoff', 'contactPhone', 'recipientPhone', 'deliveryCode', 'evidence', 'location', 'pushToken', 'privateDataMasterKeyB64', 'PRIVATE_DATA_MASTER_KEY_B64', 'privateData', 'notes', 'ciphertext',
          'sessionId', 'sessionHash', 'nonce', 'csrfToken', 'signature', 'email', 'phone', 'message', 'browserToken', 'walletAddress', 'sessionCookieSecret',
          'quote','typedData','salt','signerPrivateKey','QUOTE_SIGNER_PRIVATE_KEY','privatePayload','encrypted_response','idempotencyKey',
          'trackingSession','lat','lng','coordinates','contentBase64','text','objectKey','encryptedPayload','subscription','endpoint','evidenceHash','route'].flatMap(key => [key, `*.${key}`])],
      censor: '[REDACTED]',
    },
  };
  return destination ? pino(options, destination) : pino(options);
}

// Framework messages can contain request/connection payloads. Emit fixed event names only.
export class FrameworkLogger implements LoggerService {
  constructor(private readonly logger: Logger) {}
  log(): void { this.logger.info({ event: 'framework_info' }); }
  error(): void { this.logger.error({ event: 'framework_error' }); }
  warn(): void { this.logger.warn({ event: 'framework_warning' }); }
  debug(): void {}
  verbose(): void {}
}

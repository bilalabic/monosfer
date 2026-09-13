import { Catch, HttpException, type ArgumentsHost, type ExceptionFilter } from '@nestjs/common';
import type { FastifyReply, FastifyRequest } from 'fastify';

const errors: Record<number, [string, string]> = {
  400: ['BAD_REQUEST', 'Invalid request'], 401: ['UNAUTHORIZED', 'Authentication required'],
  403: ['FORBIDDEN', 'Access denied'], 404: ['NOT_FOUND', 'Resource not found'],
  405: ['METHOD_NOT_ALLOWED', 'Method not allowed'], 409: ['CONFLICT', 'Request conflict'],
  413: ['PAYLOAD_TOO_LARGE', 'Request body too large'], 415: ['UNSUPPORTED_MEDIA_TYPE', 'Unsupported media type'],
  429: ['TOO_MANY_REQUESTS', 'Too many requests'], 503: ['SERVICE_UNAVAILABLE', 'Service unavailable'],
};

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const request = context.getRequest<FastifyRequest>();
    const reply = context.getResponse<FastifyReply>();
    const candidate = exception instanceof HttpException ? exception.getStatus()
      : (exception as { statusCode?: unknown } | null)?.statusCode;
    const status = typeof candidate === 'number' && Number.isInteger(candidate) && candidate >= 400 && candidate <= 599 ? candidate : 500;
    const [code, message] = errors[status] ?? (status < 500 ? ['BAD_REQUEST', 'Invalid request'] : ['INTERNAL_ERROR', 'Internal server error']);
    if (status >= 500) request.log.error({ event: 'request_failed', statusCode: status, requestId: request.id });
    void reply.status(status).send({ error: { code, message, requestId: request.id } });
  }
}

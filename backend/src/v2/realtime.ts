import { createApplication } from './app.js';
import { createLogger } from './http/logger.js';
import type { NestFastifyApplication } from '@nestjs/platform-fastify';
const logger=createLogger();let application:NestFastifyApplication|undefined;
try{
  const {app,settings}=await createApplication(process.env,logger,true);application=app;
  app.enableShutdownHooks(['SIGTERM','SIGINT']);await app.listen(settings.operations.realtimePort,settings.host);
  logger.info({event:'realtime_started'});
}catch{logger.fatal({event:'realtime_start_failed'});await application?.close();process.exitCode=1;}

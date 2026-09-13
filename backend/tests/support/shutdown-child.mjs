import { createApplication } from '../../dist/app.js';
import { createLogger } from '../../dist/http/logger.js';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';

const { app } = await createApplication(process.env, createLogger({ write() {} }));
if ((await app.inject('/v1/health/ready')).statusCode !== 200) {
  await app.close();
  throw new Error('Local dependencies must be healthy for the shutdown test');
}
for (const [name, token] of [['postgres', DatabaseService], ['redis', RedisService]]) {
  const service = app.get(token);
  const close = service.onApplicationShutdown.bind(service);
  service.onApplicationShutdown = async (...args) => {
    await close(...args);
    console.log(JSON.stringify({ closed: name }));
  };
}
app.enableShutdownHooks(['SIGTERM', 'SIGINT']);
await app.listen(0, '127.0.0.1');
process.on('message', signal => {
  // Windows does not deliver POSIX signals to Node handlers; exercise their dispatch.
  if (process.platform === 'win32') process.emit(signal);
  else process.kill(process.pid, signal);
});
process.send?.({ ready: true });

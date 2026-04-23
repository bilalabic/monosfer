import { createApp } from "./app.js";
import { connectDB } from "./db.js";

const port = Number(process.env.PORT) || 3001;
const host = process.env.HOST || "127.0.0.1";
const app = createApp();

app.listen(port, host, () => {
  console.log(`Backend listening on ${host}:${port}`);
});

// DB'yi sunucu başladıktan sonra asenkron olarak bağla
connectDB().catch((err) => {
  console.error('MongoDB connection failed:', err.message);
  // Prod'da çık, dev'de sadece uyar
  if (process.env.NODE_ENV === 'production') process.exit(1);
});

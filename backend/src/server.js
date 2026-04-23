import { createApp } from "./app.js";
import { connectDB } from "./db.js";

const port = Number(process.env.PORT) || 3001;
const app = createApp();

app.listen(port, () => {
  console.log(`Backend listening on port ${port}`);
});

// DB'yi sunucu başladıktan sonra asenkron olarak bağla
connectDB().catch((err) => {
  console.error('MongoDB connection failed:', err.message);
  // Prod'da çık, dev'de sadece uyar
  if (process.env.NODE_ENV === 'production') process.exit(1);
});

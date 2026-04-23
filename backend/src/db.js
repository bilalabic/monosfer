import mongoose from 'mongoose'

export async function connectDB() {
  const uri = process.env.MONGODB_URI
  if (!uri) throw new Error('MONGODB_URI is not set in environment variables')

  await mongoose.connect(uri, {
    dbName: process.env.MONGODB_DB_NAME || 'delivera',
    serverSelectionTimeoutMS: 10000,
    connectTimeoutMS: 10000,
  })

  console.log(`MongoDB connected: ${mongoose.connection.host}`)
}

export async function disconnectDB() {
  await mongoose.disconnect()
}

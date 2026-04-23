import mongoose from 'mongoose'

// Blockchain'den indexlenen eventler
// Bu collection event-log görevi görür; senkronizasyon durumu buradan takip edilir
const chainEventSchema = new mongoose.Schema(
  {
    eventName: {
      type: String,
      required: true,
      enum: [
        'DeliveryRequested',
        'BidSubmitted',
        'CourierSelected',
        'PickupConfirmed',
        'DeliveryConfirmed',
        'PaymentReleased',
        'RatingSubmitted',
        'ScoreUpdated',
        'CourierRegistered',
        'StakeDeposited',
        'StakeWithdrawn',
        'DisputeRaised',
        'BadgeMinted',
      ],
      index: true,
    },
    contractAddress: { type: String, lowercase: true, required: true },
    txHash: { type: String, required: true, index: true },
    blockNumber: { type: Number, required: true, index: true },
    logIndex: { type: Number, required: true },
    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
      index: true,
    },

    // Event argümanları — eventName'e göre değişir
    args: { type: mongoose.Schema.Types.Mixed, required: true },

    blockTimestamp: { type: Date, required: true },
    processedAt: { type: Date },
    isProcessed: { type: Boolean, default: false, index: true },
    processingError: { type: String }, // işleme hatası varsa
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

// Aynı event iki kez kaydedilmesin
chainEventSchema.index({ txHash: 1, logIndex: 1 }, { unique: true })
chainEventSchema.index({ isProcessed: 1, blockNumber: 1 })
chainEventSchema.index({ network: 1, blockNumber: -1 })

export default mongoose.model('ChainEvent', chainEventSchema)

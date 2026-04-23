import mongoose from 'mongoose'

const entrySchema = new mongoose.Schema(
  {
    rank: { type: Number, required: true },
    walletAddress: { type: String, lowercase: true, required: true },
    score: { type: Number, required: true },
    totalDeliveries: { type: Number },
    onTimeRate: { type: Number },
    avgRating: { type: Number },
    reward: { type: String }, // token miktarı bigint → string
    rewardTxHash: { type: String },
    badgeAwarded: { type: String }, // rozet tipi (varsa)
  },
  { _id: false },
)

const leaderboardSnapshotSchema = new mongoose.Schema(
  {
    period: {
      type: String,
      enum: ['weekly', 'monthly', 'seasonal'],
      required: true,
      index: true,
    },
    // Dönem tanımlayıcısı — örn: "2026-W17", "2026-04", "2026-S2"
    periodLabel: { type: String, required: true, unique: true },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },

    entries: [entrySchema],

    totalRewardPool: { type: String }, // MCRY
    distributedAt: { type: Date },
    distributionTxHash: { type: String },
    isDistributed: { type: Boolean, default: false },

    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
    },
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

leaderboardSnapshotSchema.index({ period: 1, startDate: -1 })

export default mongoose.model('LeaderboardSnapshot', leaderboardSnapshotSchema)

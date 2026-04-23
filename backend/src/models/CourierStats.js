import mongoose from 'mongoose'

const badgeRefSchema = new mongoose.Schema(
  {
    badgeType: {
      type: String,
      enum: [
        'FirstDelivery',
        'HundredClub',
        'ThousandClub',
        'WeeklyChampion',
        'MonthlyChampion',
        'SeasonChampion',
        'SpeedChampion',
        'PerfectRating',
        'StreakMaster',
        'FairJury',
        'RegionLord',
      ],
    },
    tokenId: { type: Number }, // NFT token ID on-chain
    mintedAt: { type: Date },
    txHash: { type: String },
  },
  { _id: false },
)

const courierStatsSchema = new mongoose.Schema(
  {
    walletAddress: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      index: true,
    },

    // On-chain'den senkronize veriler
    totalDeliveries: { type: Number, default: 0 },
    onTimeCount: { type: Number, default: 0 },
    lateCount: { type: Number, default: 0 },
    totalRatingSum: { type: Number, default: 0 },
    leaderboardScore: { type: Number, default: 0, index: true },
    stakeAmount: { type: String, default: '0' }, // bigint → string

    // Off-chain hesaplanan metrikler
    successRate: { type: Number, default: 0 }, // % (0-100)
    onTimeRate: { type: Number, default: 0 }, // % (0-100)
    avgRating: { type: Number, default: 0 }, // 0-5
    wilsonScore: { type: Number, default: 0 }, // sıralama için Wilson lower bound
    reputationScore: { type: Number, default: 0 }, // composite score

    // Periyodik istatistikler
    weeklyDeliveries: { type: Number, default: 0 },
    weeklyEarnings: { type: String, default: '0' },
    monthlyDeliveries: { type: Number, default: 0 },
    monthlyEarnings: { type: String, default: '0' },
    totalEarnings: { type: String, default: '0' },

    // Streak (ardışık aktif gün)
    currentStreak: { type: Number, default: 0 },
    longestStreak: { type: Number, default: 0 },
    lastActiveDate: { type: Date },

    // Leaderboard sıralaması (snapshot'tan)
    weeklyRank: { type: Number },
    monthlyRank: { type: Number },

    // Rozetler
    badges: [badgeRefSchema],

    // Anti-fraud flag
    isFlagged: { type: Boolean, default: false },
    flagReason: { type: String },

    // Son senkronizasyon
    lastSyncedBlock: { type: Number, default: 0 },
    syncedAt: { type: Date },
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

courierStatsSchema.index({ leaderboardScore: -1 })
courierStatsSchema.index({ weeklyRank: 1 }, { sparse: true })
courierStatsSchema.index({ monthlyRank: 1 }, { sparse: true })
courierStatsSchema.index({ reputationScore: -1 })

export default mongoose.model('CourierStats', courierStatsSchema)

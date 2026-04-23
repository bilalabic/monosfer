import mongoose from 'mongoose'

const evidenceSchema = new mongoose.Schema(
  {
    submitter: { type: String, lowercase: true, required: true },
    type: { type: String, enum: ['text', 'image', 'video', 'gps_log'] },
    content: { type: String }, // metin veya IPFS hash
    ipfsHash: { type: String },
    submittedAt: { type: Date, default: Date.now },
  },
  { _id: false },
)

const jurorVoteSchema = new mongoose.Schema(
  {
    walletAddress: { type: String, lowercase: true, required: true },
    vote: { type: String, enum: ['customer', 'courier', 'split'] },
    reasonHash: { type: String }, // IPFS hash
    votedAt: { type: Date },
    stakeAmount: { type: String }, // bu dispute için yatırılan stake
    reward: { type: String },
    wasCorrect: { type: Boolean }, // çözüm sonrası set edilir
  },
  { _id: false },
)

const disputeSchema = new mongoose.Schema(
  {
    // İlişkiler
    deliveryId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Delivery',
      required: true,
      index: true,
    },
    onChainRequestId: { type: Number, index: true },

    // Taraflar
    initiator: { type: String, lowercase: true, required: true },
    respondent: { type: String, lowercase: true, required: true },

    reason: {
      type: String,
      required: true,
      enum: [
        'package_not_received',
        'package_damaged',
        'wrong_delivery',
        'late_delivery',
        'courier_behavior',
        'wrong_address_by_customer',
        'extra_charge_demanded',
        'other',
      ],
    },
    description: { type: String, maxlength: 1000 },

    // Akış
    status: {
      type: String,
      enum: ['open', 'evidence_collection', 'jury_assigned', 'voting', 'resolved', 'cancelled'],
      default: 'open',
      index: true,
    },

    // Çözüm
    resolution: {
      type: String,
      enum: ['customer_wins', 'courier_wins', 'split', null],
      default: null,
    },
    resolutionNote: { type: String },
    resolvedAt: { type: Date },

    // Kanıtlar
    evidence: [evidenceSchema],

    // Jüri (v2)
    jurors: [jurorVoteSchema],
    jurorSelectionTxHash: { type: String },

    // Stake bilgisi
    initiatorStake: { type: String }, // 5 MCRY
    respondentStake: { type: String },

    // Zaman sınırları
    evidenceDeadline: { type: Date }, // kanıt sunma son tarihi (48 saat)
    votingDeadline: { type: Date }, // oy kullanma son tarihi
    autoResolveAt: { type: Date }, // MVP: 24s timeout

    // On-chain referans
    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
    },
    raiseTxHash: { type: String },
    resolutionTxHash: { type: String },
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

disputeSchema.index({ status: 1, createdAt: -1 })
disputeSchema.index({ initiator: 1 })
disputeSchema.index({ respondent: 1 })

export default mongoose.model('Dispute', disputeSchema)

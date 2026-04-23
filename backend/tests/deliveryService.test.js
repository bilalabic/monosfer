import test from 'node:test'
import assert from 'node:assert/strict'
import Delivery from '../src/models/Delivery.js'
import Bid from '../src/models/Bid.js'
import User from '../src/models/User.js'
import CourierStats from '../src/models/CourierStats.js'
import * as deliveryService from '../src/services/deliveryService.js'

test('createDelivery stores third-party recipient type details for business deliveries', async () => {
  const originals = {
    deliveryCreate: Delivery.create,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
  }
  let createdPayload

  Delivery.create = async payload => {
    createdPayload = payload
    return {
      _id: { toString: () => 'delivery-id' },
      ...payload,
      createdAt: new Date('2026-02-01T00:00:00.000Z'),
      toObject() {
        return this
      },
    }
  }
  Bid.find = () => ({ lean: async () => [] })
  User.find = () => ({ lean: async () => [] })
  CourierStats.find = () => ({ lean: async () => [] })

  try {
    const result = await deliveryService.createDelivery({
      title: 'Restoran siparisi',
      pickupAddress: 'Kadikoy Restoran',
      dropoffAddress: 'Moda',
      recipientType: 'business',
      businessName: 'Lezzet Lokantasi',
      contactPerson: 'Murat Usta',
      recipientPhone: '5551112233',
      orderRef: 'SIP-42',
      deliveryCode: 'ab 123',
      weight: '2',
      maxBudget: 8,
      date: '2026-02-01',
      deadline: '18:30',
    }, '0xCustomer')

    assert.equal(createdPayload.dropoff.recipientType, 'business')
    assert.equal(createdPayload.dropoff.businessName, 'Lezzet Lokantasi')
    assert.equal(createdPayload.dropoff.contactPerson, 'Murat Usta')
    assert.equal(createdPayload.dropoff.orderRef, 'SIP-42')
    assert.equal(createdPayload.dropoff.deliveryCode, 'AB123')
    assert.equal(result.recipientType, 'business')
    assert.equal(result.recipientName, 'Lezzet Lokantasi')
    assert.equal(result.contactPerson, 'Murat Usta')
    assert.equal(result.orderRef, 'SIP-42')
  } finally {
    Delivery.create = originals.deliveryCreate
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
  }
})

test('rateDelivery lets the paying customer rate the selected courier', async () => {
  assert.equal(typeof deliveryService.rateDelivery, 'function')

  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
    statsFindOne: CourierStats.findOne,
    statsCreate: CourierStats.create,
  }

  const delivery = {
    _id: { toString: () => 'delivery-id' },
    title: 'Test teslimat',
    pickup: { address: 'A noktasi' },
    dropoff: { address: 'B noktasi' },
    maxBudget: '12',
    escrowBalance: '0',
    status: 'Delivered',
    customer: '0xcustomer',
    selectedBidId: { toString: () => 'bid-id' },
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date('2026-02-02T00:00:00.000Z'),
    timeline: [],
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
    toObject() {
      return this
    },
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10',
    estimatedMinutes: 30,
    createdAt: new Date('2026-02-01T01:00:00.000Z'),
  }
  const stats = {
    walletAddress: '0xcourier',
    totalRatingSum: 4,
    totalRatings: 1,
    avgRating: 4,
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid
  Bid.find = () => ({ lean: async () => [bid] })
  User.find = () => ({ lean: async () => [{ walletAddress: '0xcourier', name: 'Kurye Kullanici' }] })
  CourierStats.find = () => ({ lean: async () => [stats] })
  CourierStats.findOne = async () => stats
  CourierStats.create = async data => data

  try {
    const result = await deliveryService.rateDelivery('delivery-id', '0xcustomer', {
      rating: 5,
      comment: 'Harika teslimat',
    })

    assert.equal(delivery.rating, 5)
    assert.equal(delivery.ratingComment, 'Harika teslimat')
    assert.equal(delivery.isRated, true)
    assert.equal(delivery.saveCalls, 1)
    assert.equal(stats.totalRatings, 2)
    assert.equal(stats.totalRatingSum, 9)
    assert.equal(stats.avgRating, 4.5)
    assert.equal(stats.saveCalls, 1)
    assert.equal(result.rating, 5)
    assert.equal(result.bids[0].courierRating, 4.5)
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
    CourierStats.findOne = originals.statsFindOne
    CourierStats.create = originals.statsCreate
  }
})

test('lockEscrow rejects deliveries that already have locked funds', async () => {
  const originals = {
    deliveryFindById: Delivery.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    customer: '0xcustomer',
    escrowBalance: '12',
    maxBudget: '12',
    pickup: { address: 'A noktasi' },
    dropoff: { address: 'B noktasi' },
    status: 'OpenForBids',
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date('2026-02-02T00:00:00.000Z'),
    timeline: [],
    async save() {
      return this
    },
    toObject() {
      return this
    },
  }

  Delivery.findById = async () => delivery
  Bid.find = () => ({ lean: async () => [] })
  User.find = () => ({ lean: async () => [] })
  CourierStats.find = () => ({ lean: async () => [] })

  try {
    await assert.rejects(
      () => deliveryService.lockEscrow('delivery-id', '0xcustomer', '0xtx'),
      /Ödeme zaten escrow'a kilitlenmiş/,
    )
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
  }
})

test('confirmPickup lets the paying customer confirm the courier pickup QR', async () => {
  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    customer: '0xcustomer',
    selectedBidId: { toString: () => 'bid-id' },
    title: 'Test teslimat',
    pickup: { address: 'A noktasi' },
    dropoff: { address: 'B noktasi' },
    maxBudget: '12',
    escrowBalance: '12',
    status: 'Accepted',
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date('2026-02-02T00:00:00.000Z'),
    timeline: [
      { step: 'pickup', completed: false },
      { step: 'transit', completed: false },
    ],
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
    toObject() {
      return this
    },
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10',
    estimatedMinutes: 30,
    createdAt: new Date('2026-02-01T01:00:00.000Z'),
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid
  Bid.find = () => ({ lean: async () => [bid] })
  User.find = () => ({ lean: async () => [{ walletAddress: '0xcourier', name: 'Kurye Kullanici' }] })
  CourierStats.find = () => ({ lean: async () => [] })

  try {
    const result = await deliveryService.confirmPickup('delivery-id', '0xcustomer', '0xtx')

    assert.equal(delivery.status, 'InTransit')
    assert.equal(delivery.timeline[0].completed, true)
    assert.equal(delivery.timeline[1].completed, true)
    assert.equal(delivery.saveCalls, 1)
    assert.equal(result.status, 'in_progress')
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
  }
})

test('completeDelivery lets the paying customer confirm delivery and release escrow', async () => {
  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
    statsFindOne: CourierStats.findOne,
    statsCreate: CourierStats.create,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    customer: '0xcustomer',
    selectedBidId: { toString: () => 'bid-id' },
    title: 'Test teslimat',
    pickup: { address: 'A noktasi' },
    dropoff: { address: 'B noktasi' },
    maxBudget: '12',
    escrowBalance: '12',
    status: 'InTransit',
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date('2026-02-02T00:00:00.000Z'),
    timeline: [
      { step: 'pickup', completed: true },
      { step: 'transit', completed: true },
      { step: 'delivered', completed: false },
    ],
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
    toObject() {
      return this
    },
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10',
    estimatedMinutes: 30,
    createdAt: new Date('2026-02-01T01:00:00.000Z'),
  }
  const stats = {
    walletAddress: '0xcourier',
    totalDeliveries: 0,
    onTimeCount: 0,
    lateCount: 0,
    weeklyDeliveries: 0,
    monthlyDeliveries: 0,
    weeklyEarnings: '0',
    monthlyEarnings: '0',
    totalEarnings: '0',
    avgRating: 0,
    async save() {
      return this
    },
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid
  Bid.find = () => ({ lean: async () => [bid] })
  User.find = () => ({ lean: async () => [{ walletAddress: '0xcourier', name: 'Kurye Kullanici' }] })
  CourierStats.find = () => ({ lean: async () => [stats] })
  CourierStats.findOne = async () => stats
  CourierStats.create = async data => data

  try {
    const result = await deliveryService.completeDelivery('delivery-id', '0xcustomer', '0xtx')

    assert.equal(delivery.status, 'Delivered')
    assert.equal(delivery.escrowBalance, '0')
    assert.equal(delivery.timeline[2].completed, true)
    assert.equal(delivery.saveCalls, 1)
    assert.equal(result.status, 'completed')
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
    CourierStats.findOne = originals.statsFindOne
    CourierStats.create = originals.statsCreate
  }
})

test('completeDeliveryWithRecipientCode lets the third-party recipient release escrow with the delivery code', async () => {
  assert.equal(typeof deliveryService.completeDeliveryWithRecipientCode, 'function')

  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
    statsFindOne: CourierStats.findOne,
    statsCreate: CourierStats.create,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    customer: '0xcustomer',
    selectedBidId: { toString: () => 'bid-id' },
    title: 'Test teslimat',
    pickup: { address: 'A noktasi' },
    dropoff: {
      address: 'B noktasi',
      recipientName: 'Alici Kisi',
      deliveryCode: 'ABC123',
    },
    maxBudget: '12',
    escrowBalance: '12',
    status: 'InTransit',
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date('2026-02-02T00:00:00.000Z'),
    timeline: [
      { step: 'pickup', completed: true },
      { step: 'transit', completed: true },
      { step: 'delivered', completed: false },
    ],
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
    toObject() {
      return this
    },
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10',
    estimatedMinutes: 30,
    createdAt: new Date('2026-02-01T01:00:00.000Z'),
  }
  const stats = {
    walletAddress: '0xcourier',
    totalDeliveries: 0,
    onTimeCount: 0,
    lateCount: 0,
    weeklyDeliveries: 0,
    monthlyDeliveries: 0,
    weeklyEarnings: '0',
    monthlyEarnings: '0',
    totalEarnings: '0',
    avgRating: 0,
    async save() {
      return this
    },
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid
  Bid.find = () => ({ lean: async () => [bid] })
  User.find = () => ({ lean: async () => [{ walletAddress: '0xcourier', name: 'Kurye Kullanici' }] })
  CourierStats.find = () => ({ lean: async () => [stats] })
  CourierStats.findOne = async () => stats
  CourierStats.create = async data => data

  try {
    const result = await deliveryService.completeDeliveryWithRecipientCode('delivery-id', 'abc 123')

    assert.equal(delivery.status, 'Delivered')
    assert.equal(delivery.escrowBalance, '0')
    assert.equal(delivery.dropoff.deliveryConfirmedBy, 'recipient_code')
    assert.equal(delivery.timeline[2].completed, true)
    assert.equal(delivery.saveCalls, 1)
    assert.equal(result.status, 'completed')
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
    CourierStats.findOne = originals.statsFindOne
    CourierStats.create = originals.statsCreate
  }
})

test('completeDeliveryWithRecipientCode rejects delivery code before courier pickup', async () => {
  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    selectedBidId: { toString: () => 'bid-id' },
    dropoff: { deliveryCode: 'ABC123' },
    status: 'Accepted',
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10',
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid

  try {
    await assert.rejects(
      () => deliveryService.completeDeliveryWithRecipientCode('delivery-id', 'ABC123'),
      /Teslim kodu sadece paket yoldayken kullanılabilir/,
    )
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
  }
})

test('completeDelivery updates courier leaderboard delivery and earnings stats', async () => {
  const originals = {
    deliveryFindById: Delivery.findById,
    bidFindById: Bid.findById,
    bidFind: Bid.find,
    userFind: User.find,
    statsFind: CourierStats.find,
    statsFindOne: CourierStats.findOne,
    statsCreate: CourierStats.create,
  }
  const delivery = {
    _id: { toString: () => 'delivery-id' },
    customer: '0xcustomer',
    selectedBidId: { toString: () => 'bid-id' },
    title: 'Test teslimat',
    pickup: { address: 'A noktasi' },
    dropoff: { address: 'B noktasi' },
    maxBudget: '12',
    escrowBalance: '12',
    status: 'InTransit',
    createdAt: new Date('2026-02-01T00:00:00.000Z'),
    deadline: new Date(Date.now() + 60_000),
    timeline: [{ step: 'delivered', completed: false }],
    async save() {
      return this
    },
    toObject() {
      return this
    },
  }
  const bid = {
    _id: { toString: () => 'bid-id' },
    courier: '0xcourier',
    amount: '10.5',
    estimatedMinutes: 30,
    createdAt: new Date('2026-02-01T01:00:00.000Z'),
  }
  const stats = {
    walletAddress: '0xcourier',
    totalDeliveries: 1,
    onTimeCount: 1,
    lateCount: 0,
    weeklyDeliveries: 1,
    monthlyDeliveries: 1,
    weeklyEarnings: '7',
    monthlyEarnings: '7',
    totalEarnings: '7',
    avgRating: 4,
    saveCalls: 0,
    async save() {
      this.saveCalls += 1
      return this
    },
  }

  Delivery.findById = async () => delivery
  Bid.findById = async () => bid
  Bid.find = () => ({ lean: async () => [bid] })
  User.find = () => ({ lean: async () => [{ walletAddress: '0xcourier', name: 'Kurye Kullanici' }] })
  CourierStats.find = () => ({ lean: async () => [stats] })
  CourierStats.findOne = async () => stats
  CourierStats.create = async data => data

  try {
    await deliveryService.completeDelivery('delivery-id', '0xcustomer', '0xtx')

    assert.equal(stats.totalDeliveries, 2)
    assert.equal(stats.onTimeCount, 2)
    assert.equal(stats.lateCount, 0)
    assert.equal(stats.successRate, 100)
    assert.equal(stats.onTimeRate, 100)
    assert.equal(stats.weeklyDeliveries, 2)
    assert.equal(stats.monthlyDeliveries, 2)
    assert.equal(stats.weeklyEarnings, '17.5')
    assert.equal(stats.monthlyEarnings, '17.5')
    assert.equal(stats.totalEarnings, '17.5')
    assert.equal(stats.leaderboardScore, 150)
    assert.equal(stats.saveCalls, 1)
  } finally {
    Delivery.findById = originals.deliveryFindById
    Bid.findById = originals.bidFindById
    Bid.find = originals.bidFind
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
    CourierStats.findOne = originals.statsFindOne
    CourierStats.create = originals.statsCreate
  }
})

import test from 'node:test'
import assert from 'node:assert/strict'
import Delivery from '../src/models/Delivery.js'
import Bid from '../src/models/Bid.js'
import User from '../src/models/User.js'
import CourierStats from '../src/models/CourierStats.js'
import * as deliveryService from '../src/services/deliveryService.js'

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

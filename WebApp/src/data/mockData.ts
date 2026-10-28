import type { Game } from '../types'

const now = Math.floor(Date.now() / 1000)
const h = (n: number) => now + n * 3600

export const mockGames: Game[] = [
  {
    id: 'genshin',
    name: '原神',
    emoji: '🌸',
    headerColor: '#7B5EA7',
    accentColor: '#9B7BC7',
    events: [
      { id: 'g1', title: '渊月螺旋',         endTimestamp: h(6.3),   category: '挑战', isDone: false },
      { id: 'g2', title: '勇锐魁杰试炼战记', endTimestamp: h(54),    category: '活动', isDone: false },
      { id: 'g3', title: '热斗模式：奇策竞驰',endTimestamp: h(150),  category: '活动', isDone: false },
      { id: 'g4', title: '幽境危机',          endTimestamp: h(342),  category: '活动', isDone: false },
      { id: 'g5', title: '胡桃复刻祈愿',      endTimestamp: h(408),  category: '祈愿', isDone: false },
      { id: 'g6', title: '探索派遣奖励翻倍',  endTimestamp: h(576),  category: '奖励', isDone: false },
    ],
  },
  {
    id: 'starrail',
    name: '崩坏：星穹铁道',
    emoji: '⭐',
    headerColor: '#4A72C4',
    accentColor: '#6A92E4',
    events: [
      { id: 's1', title: '「银河际线」限定活动', endTimestamp: h(30),  category: '活动', isDone: false },
      { id: 's2', title: '混沌回忆第14期',       endTimestamp: h(114), category: '挑战', isDone: false },
      { id: 's3', title: '「青雀」UP 卡池',      endTimestamp: h(200), category: '卡池', isDone: false },
      { id: 's4', title: '模拟宇宙积分',         endTimestamp: h(280), category: '挑战', isDone: false },
    ],
  },
  {
    id: 'arknights',
    name: '明日方舟',
    emoji: '🛡️',
    headerColor: '#2E7D5E',
    accentColor: '#3EA87E',
    events: [
      { id: 'a1', title: '「感谢庆典」主题活动', endTimestamp: h(94),  category: '活动', isDone: false },
      { id: 'a2', title: '危机合约赛季',         endTimestamp: h(216), category: '挑战', isDone: false },
      { id: 'a3', title: '「推进之王」复刻池',   endTimestamp: h(340), category: '卡池', isDone: false },
    ],
  },
]

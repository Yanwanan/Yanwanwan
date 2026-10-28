export type Urgency = 'critical' | 'warning' | 'normal' | 'calm' | 'done' | 'expired'

export interface GameEvent {
  id: string
  title: string
  endTimestamp: number
  category: '活动' | '挑战' | '卡池' | '周常任务' | '祈愿' | '奖励'
  isDone: boolean
}

export interface Game {
  id: string
  name: string
  emoji: string
  headerColor: string
  accentColor: string
  events: GameEvent[]
}

export function getUrgency(remaining: number, isDone: boolean): Urgency {
  if (isDone) return 'done'
  if (remaining <= 0) return 'expired'
  if (remaining < 86400) return 'critical'
  if (remaining < 3 * 86400) return 'warning'
  if (remaining < 7 * 86400) return 'normal'
  return 'calm'
}

export type NavigationState =
  | { page: 'activity' }
  | { page: 'settings' }
  | { page: 'game-detail'; gameId: string }
  | { page: 'event-guide'; gameId: string; eventId: string }

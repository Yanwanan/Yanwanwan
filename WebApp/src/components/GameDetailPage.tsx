import { ChevronLeft, Zap, Calendar, RefreshCw, Settings } from 'lucide-react'
import { EventRow } from './EventRow'
import { formatRemaining } from '../lib/utils'
import type { Game } from '../types'

interface GameDetailPageProps {
  game: Game
  onBack: () => void
  onEventClick: (eventId: string) => void
  onToggleDone: (gameId: string, eventId: string) => void
}

interface SectionLabelProps {
  icon: React.ReactNode
  iconBg: string
  title: string
  count: number
}

function SectionLabel({ icon, iconBg, title, count }: SectionLabelProps) {
  return (
    <div className="flex items-center gap-2 px-1 mb-3">
      <div
        className="w-7 h-7 rounded-[8px] flex items-center justify-center text-white flex-shrink-0"
        style={{ backgroundColor: iconBg }}
      >
        {icon}
      </div>
      <span className="text-[15px] font-bold text-[#2C2555]">
        {title}（{count}）
      </span>
    </div>
  )
}

export function GameDetailPage({ game, onBack, onEventClick, onToggleDone }: GameDetailPageProps) {
  const now = Math.floor(Date.now() / 1000)

  const activeEvents = game.events.filter(e => !e.isDone && e.endTimestamp > now)
  const endingSoon = activeEvents
    .filter(e => (e.endTimestamp - now) <= 7 * 86400)
    .sort((a, b) => a.endTimestamp - b.endTimestamp)
  const endingLater = activeEvents
    .filter(e => (e.endTimestamp - now) > 7 * 86400)
    .sort((a, b) => a.endTimestamp - b.endTimestamp)
  const done = game.events
    .filter(e => e.isDone || e.endTimestamp <= now)
    .sort((a, b) => b.endTimestamp - a.endTimestamp)

  return (
    <div className="flex flex-col h-full bg-[#FDF0F8]">
      {/* Nav bar */}
      <div className="flex items-center gap-3 px-4 pt-5 pb-4 bg-[#FDF0F8]">
        <button
          onClick={onBack}
          className="w-10 h-10 rounded-[12px] bg-[#2C2555] flex items-center justify-center flex-shrink-0"
          style={{ boxShadow: '0 3px 10px rgba(44,37,85,0.25)' }}
        >
          <ChevronLeft size={20} strokeWidth={2.5} className="text-white" />
        </button>

        <div className="flex items-center gap-2 flex-1 min-w-0">
          <span className="text-xl">{game.emoji}</span>
          <span className="text-[18px] font-black text-[#2C2555] truncate">{game.name}</span>
        </div>

        <div className="flex items-center gap-2">
          <button
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-bold text-white"
            style={{ backgroundColor: '#39C5BB' }}
          >
            <RefreshCw size={11} strokeWidth={2.5} />
            刚刚更新
          </button>
          <button className="w-10 h-10 rounded-[12px] border-[1.5px] border-[#2C2555]/15 bg-white flex items-center justify-center">
            <Settings size={16} strokeWidth={2} className="text-[#2C2555]/55" />
          </button>
        </div>
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto px-4 pb-28">
        <div className="space-y-5">

          {/* Ending soon (within 7 days) */}
          <div>
            <SectionLabel
              icon={<Zap size={14} strokeWidth={2.5} />}
              iconBg="#FF6EB4"
              title="七日内临期"
              count={endingSoon.length}
            />
            <div className="space-y-2">
              {endingSoon.length > 0 ? (
                endingSoon.map(event => (
                  <EventRow
                    key={event.id}
                    event={event}
                    headerColor={game.headerColor}
                    onToggleDone={(id) => onToggleDone(game.id, id)}
                    onClick={onEventClick}
                  />
                ))
              ) : (
                <EmptySection text="暂无临期活动" sub="七日内暂无急事，小的先候着。" />
              )}
            </div>
            {endingSoon.length > 0 && (
              <p className="text-[11px] text-[#2C2555]/35 mt-2.5 ml-1 flex items-center gap-1">
                <span>🔇</span> 轻触查看B站攻略，长按可静音或标记完成
              </p>
            )}
          </div>

          {/* Ending later */}
          <div>
            <SectionLabel
              icon={<Calendar size={14} strokeWidth={2.5} />}
              iconBg="#FF6EB4"
              title="七日后待办"
              count={endingLater.length}
            />
            <div className="space-y-2">
              {endingLater.length > 0 ? (
                endingLater.map(event => (
                  <EventRow
                    key={event.id}
                    event={event}
                    headerColor={game.headerColor}
                    onToggleDone={(id) => onToggleDone(game.id, id)}
                    onClick={onEventClick}
                  />
                ))
              ) : (
                <EmptySection text="暂无待办活动" sub="后面暂无待办，小的继续盯着。" />
              )}
            </div>
          </div>

          {/* Done / expired */}
          {done.length > 0 && (
            <div>
              <SectionLabel
                icon={<span className="text-[11px] font-black">✓</span>}
                iconBg="#2C2555/40"
                title="已完成 & 已结束"
                count={done.length}
              />
              <div className="space-y-2 opacity-60">
                {done.map(event => (
                  <EventRow
                    key={event.id}
                    event={event}
                    headerColor={game.headerColor}
                    onToggleDone={(id) => onToggleDone(game.id, id)}
                    onClick={onEventClick}
                  />
                ))}
              </div>
            </div>
          )}

        </div>
      </div>
    </div>
  )
}

function EmptySection({ text, sub }: { text: string; sub: string }) {
  return (
    <div className="flex flex-col items-center gap-1.5 py-8">
      <p className="text-[14px] font-semibold text-[#2C2555]/40">{text}</p>
      <p className="text-[12px] text-[#2C2555]/25">{sub}</p>
    </div>
  )
}

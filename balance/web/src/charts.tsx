import { Tooltip } from '@mantine/core'
import { IconAlertTriangle, IconCircleCheck, IconCircleX, IconHelpCircle, IconMinus } from '@tabler/icons-react'
import type { Verdict } from './api'

// Categorical order validated with the dataviz palette checker (dark surface #161B26): fixed, never cycled.
export const SERIES = ['#5585E6', '#BE8A28', '#1FA98C', '#B070D6']
export const GOOD = '#3FB57F'
export const BAD = '#E5606A'
export const NEUTRAL = '#6F7A90'

export const STATUS_LABEL: Record<string, string> = {
  PASS: '达标', FAIL: '未达标', INCONCLUSIVE: '贴边', KNOWN: '已知问题', NO_TARGET: '无目标', NO_DATA: '无数据',
}
const STATUS_HELP: Record<string, string> = {
  PASS: '95% 区间完全落在目标范围内',
  FAIL: '95% 区间完全落在目标范围外',
  INCONCLUSIVE: '95% 区间跨过了目标边界：数值离边界太近，或局数不够',
  KNOWN: '未达标，但已登记为已知问题',
  NO_TARGET: '这个指标还没有设目标',
  NO_DATA: '还没有模拟结果',
}

export function Status({ status }: { status: string }) {
  const Icon = { PASS: IconCircleCheck, FAIL: IconCircleX, INCONCLUSIVE: IconAlertTriangle, KNOWN: IconHelpCircle }[status] ?? IconMinus
  return (
    <Tooltip label={STATUS_HELP[status] ?? status} multiline w={220}>
      <span className={`status ${status}`}><Icon size={15} />{STATUS_LABEL[status] ?? status}</span>
    </Tooltip>
  )
}

export const fmt = (v: number | null | undefined, pct: boolean) => (v === null || v === undefined ? '—' : pct ? `${Math.round(v * 100)}%` : v.toFixed(1))

/** One metric: the target range as a band, the measured value as a dot with its 95% interval. */
export function RangeTrack({ v }: { v: Verdict }) {
  const max = v.pct ? 1 : Math.max(12, (v.target?.[1] ?? 0) * 1.25, (v.hi ?? 0) * 1.1)
  const x = (n: number) => `${Math.min(100, Math.max(0, (n / max) * 100))}%`
  const w = (a: number, b: number) => `${Math.max(0.6, ((Math.min(b, max) - Math.max(a, 0)) / max) * 100)}%`
  return (
    <Tooltip
      multiline w={250}
      label={`目标 ${v.target ? `${fmt(v.target[0], v.pct)}–${fmt(v.target[1], v.pct)}` : '未设'}；实测 ${fmt(v.value, v.pct)}，95% 区间 ${fmt(v.lo, v.pct)}–${fmt(v.hi, v.pct)}（${v.n} 局）${v.note ? `。${v.note}` : ''}`}
    >
      <div className="track">
        <div className="axis" />
        {v.target && <div className="band" style={{ left: x(v.target[0]), width: w(v.target[0], v.target[1]) }} />}
        {v.value !== null && v.lo !== null && v.hi !== null && (
          <>
            <div className="ci" style={{ left: x(v.lo), width: w(v.lo, v.hi) }} />
            <div className="pt" style={{ left: x(v.value), background: v.status === 'FAIL' ? BAD : v.status === 'PASS' ? GOOD : v.status === 'INCONCLUSIVE' ? '#F0B429' : '#E8ECF4' }} />
          </>
        )}
      </div>
    </Tooltip>
  )
}

export function HBars({ rows, color = SERIES[0], max }: { rows: { key: string; label: string; value: number; text: string; tip?: string; color?: string }[]; color?: string; max?: number }) {
  const top = max ?? Math.max(1e-9, ...rows.map((r) => r.value))
  return (
    <div>
      {rows.map((r) => (
        <Tooltip key={r.key} label={r.tip ?? `${r.label}：${r.text}`} position="top-start">
          <div className="hbar">
            <span className="lab">{r.label}</span>
            <div className="trk"><div className="fill" style={{ width: `${(r.value / top) * 100}%`, background: r.color ?? color }} /></div>
            <span className="num">{r.text}</span>
          </div>
        </Tooltip>
      ))}
    </div>
  )
}

/** Stacked columns; `series` order is bottom to top. */
export function Histogram({ cols, series }: { cols: { label: string; values: number[]; tip: string }[]; series: { name: string; color: string }[] }) {
  const top = Math.max(1, ...cols.map((c) => c.values.reduce((a, b) => a + b, 0)))
  return (
    <div>
      {series.length > 1 && (
        <div className="legend" style={{ marginBottom: 6 }}>{series.map((s) => <span key={s.name}><i style={{ background: s.color }} />{s.name}</span>)}</div>
      )}
      <div className="histo">
        {cols.map((c) => (
          <Tooltip key={c.label} label={c.tip}>
            <div className="col">
              {c.values.map((v, i) => v > 0 && <div key={i} style={{ height: `${(v / top) * 100}%`, background: series[i].color }} />)}
            </div>
          </Tooltip>
        ))}
      </div>
      <div className="histo-x">{cols.map((c) => <span key={c.label}>{c.label}</span>)}</div>
    </div>
  )
}
